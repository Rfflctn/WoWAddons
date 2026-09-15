-- Services/Prices.lua | DecorLumberProfit | Retail 12.1.0
-- Цены аукциона через C_AuctionHouse (commodity + item), throttle-очередь.
-- (Этап 7: переименование Auction.lua; FormatMoney — в Util/Money.lua.)
-- Соглашение: функции через точку (без self), кроме исторических :-методов — не менять.

DecorLumberProfitPrices = {}
local Auction = DecorLumberProfitPrices

local priceCache = {} -- active realm: [itemID] = { price=copper, timestamp=time(), ... }
local activeRealmKey = nil
local activeRealmName = nil
local pending = {}    -- [itemID] = true (ожидает ответа)
local queue = {}      -- список itemID на запрос
local overflow = {}   -- излишек сверх MAX_QUEUE, подгружается по мере обработки
local queuedSet = {}  -- [itemID] = true — O(1) проверка «уже в queue/overflow»
local isProcessing = false
local lastQueryTime = 0
local attempts = {}   -- [itemID] = число попыток запроса
local droppedIDs = {} -- [itemID] = true (запрос отброшен троттлом — попытка не считается)
local lastSentItemID = nil
local overflowHead = 1 -- голова overflow (Этап 7: O(1) вместо table.remove(overflow, 1))
local sentAt = {}     -- [itemID] = GetTime() отправки (Этап 7: батч-sweep вместо N C_Timer.After)
local stats = { requested = 0, resolved = 0 } -- прогресс очереди для UI/status (Этап 7)
local lastPriceUpdate = nil -- timestamp time() последнего успешного обновления цены (задача: время в статусе)
local ownedRefreshQueued = false
local NotifyPriceUpdate
local MAX_ATTEMPTS = 3
local RESOLVE_DELAY = 1.5

local itemRole = {}     -- [itemID] = "output" | "reagent": режим агрегации цены
local previewCache = {} -- [itemID] = { price, t }: быстрый browse-скан (только память)
local previewTargets = {}

local FRAME = nil

local function Now() return time() end

local function CfgNumber(key, fallback)
    local v = DecorLumberProfitConfig and DecorLumberProfitConfig.AUCTION and DecorLumberProfitConfig.AUCTION[key]
    return (type(v) == "number") and v or fallback
end

local function GetTTL() return CfgNumber("PRICE_TTL", 3600) end
local function GetDelay() return CfgNumber("QUERY_DELAY", 0.65) end
local function GetQueueCap() return CfgNumber("MAX_QUEUE", 400) end

local function RealmContext()
    local key, name
    if _G.GetNormalizedRealmName then
        local ok, value = pcall(_G.GetNormalizedRealmName)
        if ok and type(value) == "string" and value ~= "" then key = value end
    end
    if _G.GetRealmName then
        local ok, value = pcall(_G.GetRealmName)
        if ok and type(value) == "string" and value ~= "" then name = value end
    end
    name = name or key
    if not key and name then key = name:gsub("[%s%p]", ""):lower() end
    if not key or key == "" then return nil, name end
    return key, name or key
end

local function ActivateRealm()
    local key, name = RealmContext()
    if not key then return nil end
    if activeRealmKey and activeRealmKey ~= key and Auction.ClearQueue then
        Auction.ClearQueue()
    end
    activeRealmKey, activeRealmName = key, name
    local Store = _G.DecorLumberProfitStore
    if Store and Store.MigrateRealmData then Store.MigrateRealmData(key, name) end
    DecorLumberProfitDB = DecorLumberProfitDB or {}
    DecorLumberProfitDB.priceCache = DecorLumberProfitDB.priceCache or {}
    DecorLumberProfitDB.priceCache[key] = DecorLumberProfitDB.priceCache[key] or {}
    DecorLumberProfitDB.realmMeta = DecorLumberProfitDB.realmMeta or {}
    DecorLumberProfitDB.realmMeta[key] = DecorLumberProfitDB.realmMeta[key] or {}
    DecorLumberProfitDB.realmMeta[key].name = name or DecorLumberProfitDB.realmMeta[key].name or key
    DecorLumberProfitDB.realmMeta[key].lastSeen = Now()
    DecorLumberProfitDB.priceUpdatedAtByRealm = DecorLumberProfitDB.priceUpdatedAtByRealm or {}
    priceCache = DecorLumberProfitDB.priceCache[key]
    lastPriceUpdate = DecorLumberProfitDB.priceUpdatedAtByRealm[key]
    return key
end

function Auction.InitializeRealm()
    return ActivateRealm()
end

local function EnsureRealm()
    local key = RealmContext()
    if key and key ~= activeRealmKey then ActivateRealm() end
    return activeRealmKey
end

local function RealmBucket(realmKey)
    realmKey = realmKey or EnsureRealm()
    if not realmKey then return nil end
    DecorLumberProfitDB = DecorLumberProfitDB or {}
    DecorLumberProfitDB.priceCache = DecorLumberProfitDB.priceCache or {}
    DecorLumberProfitDB.priceCache[realmKey] = DecorLumberProfitDB.priceCache[realmKey] or {}
    return DecorLumberProfitDB.priceCache[realmKey]
end

-- Штамп последнего обновления цен (память + SavedVariables, переживает /reload)
local function TouchPriceUpdate()
    local realmKey = EnsureRealm()
    if not realmKey then return end
    lastPriceUpdate = Now()
    DecorLumberProfitDB = DecorLumberProfitDB or {}
    DecorLumberProfitDB.priceUpdatedAtByRealm = DecorLumberProfitDB.priceUpdatedAtByRealm or {}
    DecorLumberProfitDB.priceUpdatedAtByRealm[realmKey] = lastPriceUpdate
end

-- Единая точка записи в кэш: память + SavedVariables
local function CacheEntry(itemID, entry)
    if not EnsureRealm() then return end
    priceCache[itemID] = entry
    DecorLumberProfitDB = DecorLumberProfitDB or {}
    DecorLumberProfitDB.priceCache = DecorLumberProfitDB.priceCache or {}
    DecorLumberProfitDB.priceCache[activeRealmKey] = DecorLumberProfitDB.priceCache[activeRealmKey] or {}
    DecorLumberProfitDB.priceCache[activeRealmKey][itemID] = entry
    TouchPriceUpdate()
end

-- Пустой АХ (0 лотов при полных результатах): помечаем отсутствие, НО сохраняем
-- последнюю известную цену (lastPrice) — иначе один пустой скан навсегда стирал
-- цену из SavedVariables ("забытая" цена). Глобальный штамп lastPriceUpdate НЕ
-- трогаем: новых данных не пришло, время в статусе честно показывает старый скан.
local function CacheNoAuction(itemID, source)
    if type(itemID) ~= "number" then return end
    if not EnsureRealm() then return end
    previewCache[itemID] = nil
    local old = priceCache[itemID]
    local entry = { noauction = true, timestamp = Now(), source = source or "unknown", qty = 0, listings = 0 }
    if type(old) == "table" then
        if type(old.price) == "number" then
            entry.lastPrice, entry.lastTimestamp, entry.lastSource = old.price, old.timestamp, old.source
        elseif type(old.lastPrice) == "number" then
            entry.lastPrice, entry.lastTimestamp, entry.lastSource = old.lastPrice, old.lastTimestamp, old.lastSource
        end
    end
    priceCache[itemID] = entry
    DecorLumberProfitDB = DecorLumberProfitDB or {}
    DecorLumberProfitDB.priceCache = DecorLumberProfitDB.priceCache or {}
    DecorLumberProfitDB.priceCache[activeRealmKey] = DecorLumberProfitDB.priceCache[activeRealmKey] or {}
    DecorLumberProfitDB.priceCache[activeRealmKey][itemID] = entry
end

-- Публичная пометка "нет на АХ" (использует и ResolveItem): переживает lastPrice.
function Auction.MarkNoAuction(itemID, source)
    return CacheNoAuction(itemID, source)
end

-- Время последнего успешного обновления цен (timestamp time()) или nil («ещё не обновляли»).
-- Фолбэк на SavedVariables — переживает /reload даже до первого SetPrice в сессии.
function Auction.GetLastPriceUpdate(realmKey)
    if realmKey and realmKey ~= activeRealmKey then
        local saved = DecorLumberProfitDB and DecorLumberProfitDB.priceUpdatedAtByRealm
        return saved and saved[realmKey] or nil
    end
    EnsureRealm()
    if lastPriceUpdate then return lastPriceUpdate end
    local saved = DecorLumberProfitDB and DecorLumberProfitDB.priceUpdatedAtByRealm
    saved = saved and activeRealmKey and saved[activeRealmKey] or nil
    if type(saved) == "number" and saved > 0 then
        lastPriceUpdate = saved
        return saved
    end
    return nil
end

local function IsExpired(entry, ttl)
    return entry.timestamp ~= nil and (Now() - entry.timestamp) > ttl
end

-- ==== Форматирование денег — в Util/Money.lua (Этап 7). Алиас для совместимости. ====
function Auction.FormatMoney(copper)
    local M = _G.DecorLumberProfitMoney
    if M and M.FormatMoney then return M.FormatMoney(copper) end
    return "—"
end

-- ==== Кэш цен ====
-- Возвращает последнюю известную цену: живую (entry.price) или сохранённую
-- при пустом АХ (entry.lastPrice, см. CacheNoAuction). nil — данных нет вообще.
function Auction.GetCachedPrice(itemID, realmKey)
    if type(itemID) ~= "number" then return nil end
    local entry
    if realmKey then
        local bucket = RealmBucket(realmKey)
        entry = bucket and bucket[itemID]
    else
        EnsureRealm()
        entry = priceCache[itemID]
    end
    if not entry then
        -- SavedVariables переживают /reload и релогины: отдаём последнюю известную
        -- цену независимо от давности (свежесть гейтит только HasFreshPrice/need;
        -- стирается цена — только ручным сбросом кэша или переустановкой).
        local bucket = RealmBucket(realmKey)
        local saved = bucket and bucket[itemID]
        if saved then
            if not realmKey or realmKey == activeRealmKey then priceCache[itemID] = saved end
            return saved.price or saved.lastPrice, saved
        end
        return nil
    end
    return entry.price or entry.lastPrice, entry
end

function Auction.SetPrice(itemID, price, source, qty, listings)
    if type(itemID) ~= "number" or type(price) ~= "number" then return end
    if not EnsureRealm() then return end
    previewCache[itemID] = nil
    local old = priceCache[itemID]
    if qty == nil and old then qty = old.qty end
    if listings == nil and old then listings = old.listings end
    CacheEntry(itemID, { price = price, timestamp = Now(), source = source or "unknown", qty = qty, listings = listings })
end

-- Запись точного результата скана с двумя метриками:
--   priceMin — самая дешёвая единица (для крафтовых предметов);
--   priceAvg — средняя цена 10 самых дешёвых единиц, взвешенная по количеству
--              в лоте (для реагентов: "10 дешёвых предметов", а не 10 строк).
-- entry.price (что читает экономика/таблица) выбирается по роли предмета.
function Auction.SetSamplePrice(itemID, priceMin, priceAvg, source, qty, listings)
    if type(itemID) ~= "number" then return end
    if not EnsureRealm() then return end
    local role = itemRole[itemID]
    local primary = (role == "reagent") and (priceAvg or priceMin) or priceMin
    if primary == nil then return end
    previewCache[itemID] = nil
    local old = priceCache[itemID]
    if qty == nil and old then qty = old.qty end
    if listings == nil and old then listings = old.listings end
    CacheEntry(itemID, {
        price = primary, priceMin = priceMin, priceAvg = priceAvg,
        timestamp = Now(), source = source or "unknown", qty = qty, listings = listings,
    })
end

-- Кол-во лотов/штук на аукционе (конкуренция). Делит TTL с ценой: пишется тем же
-- ответом SendSearchQuery, отдельного запроса не требует.
-- Возвращает qty (суммарно штук), listings (число лотов), entry. nil — ещё не сканировали.
function Auction.GetCachedQuantity(itemID)
    if type(itemID) ~= "number" then return nil end
    EnsureRealm()
    local entry = priceCache[itemID]
    if not entry then
        -- SavedVariables переживают /reload: количество тоже не теряем по TTL
        -- (свежесть гейтит только HasFreshPrice; стирается — только сбросом).
        local bucket = RealmBucket()
        local saved = bucket and bucket[itemID]
        if saved then
            priceCache[itemID] = saved
            entry = saved
        end
    end
    if not entry then return nil end
    if entry.qty == nil and entry.listings == nil then return nil end
    return entry.qty, entry.listings, entry
end

-- Удобный агрегат для таблицы/тултипа: цена + конкуренция одним вызовом.
function Auction.GetAuctionInfo(itemID)
    if type(itemID) ~= "number" then return nil end
    local price, entry = Auction.GetCachedPrice(itemID)
    local qty, listings = Auction.GetCachedQuantity(itemID)
    if price == nil and qty == nil and listings == nil then return nil end
    return { price = price, qty = qty, listings = listings, entry = entry }
end

local function CurrentCharacter()
    if _G.UnitName then
        local ok, name = pcall(_G.UnitName, "player")
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return "player"
end

local function OwnedRoot(realmKey)
    realmKey = realmKey or EnsureRealm()
    if not realmKey then return nil end
    DecorLumberProfitDB = DecorLumberProfitDB or {}
    DecorLumberProfitDB.ownedAuctions = DecorLumberProfitDB.ownedAuctions or {}
    DecorLumberProfitDB.ownedAuctions[realmKey] = DecorLumberProfitDB.ownedAuctions[realmKey] or {}
    return DecorLumberProfitDB.ownedAuctions[realmKey]
end

local function OwnedStats(itemID, realmKey)
    local root = OwnedRoot(realmKey)
    if not root then return nil, nil, false, nil end
    local qty, listings, latestAt = 0, 0, nil
    local hasData = false
    for _, snapshot in pairs(root) do
        if type(snapshot) == "table" and type(snapshot.updatedAt) == "number" then
            hasData = true
            if not latestAt or snapshot.updatedAt > latestAt then latestAt = snapshot.updatedAt end
            local item = snapshot.items and snapshot.items[itemID]
            if item then
                qty = qty + (tonumber(item.quantity) or 0)
                listings = listings + (tonumber(item.listings) or 0)
            end
        end
    end
    if not hasData then return nil, nil, false, nil end
    return qty, listings, true, latestAt
end

-- Сводка по всем известным реалмам для тултипа предмета. В отличие от
-- GetCachedPrice не скрывает старые записи: stale=true позволяет показать
-- пользователю дату, но не выдаёт устаревшее значение экономике.
function Auction.GetRealmAuctionInfo(itemID)
    if type(itemID) ~= "number" then return {} end
    local db = _G.DecorLumberProfitDB
    if not db then return {} end
    local realms = {}
    local seen = {}
    local function AddRealm(realmKey)
        if type(realmKey) ~= "string" or seen[realmKey] then return end
        seen[realmKey] = true
        local bucket = db.priceCache and db.priceCache[realmKey]
        local entry = type(bucket) == "table" and bucket[itemID] or nil
        local qty, listings, ownKnown, ownUpdatedAt = OwnedStats(itemID, realmKey)
        if not entry and not ownKnown then return end
        local meta = db.realmMeta and db.realmMeta[realmKey]
        local price = entry and (entry.price or entry.lastPrice) or nil
        realms[#realms + 1] = {
            key = realmKey,
            name = (type(meta) == "table" and meta.name) or realmKey,
            price = price,
            qty = entry and entry.qty or nil,
            listings = entry and entry.listings or nil,
            ownQty = qty,
            ownListings = listings,
            ownUpdatedAt = ownUpdatedAt,
            timestamp = entry and entry.timestamp or nil,
            stale = entry and (entry.noauction == true or IsExpired(entry, GetTTL())) or false,
        }
    end
    for realmKey, bucket in pairs(db.priceCache or {}) do
        if type(bucket) == "table" and bucket[itemID] then AddRealm(realmKey) end
    end
    for realmKey in pairs(db.ownedAuctions or {}) do AddRealm(realmKey) end
    table.sort(realms, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return realms
end

function Auction.GetAuctionStats(itemID, realmKey)
    if type(itemID) ~= "number" then return nil end
    local bucket = RealmBucket(realmKey)
    local entry = bucket and bucket[itemID]
    local qty = entry and entry.qty or nil
    local listings = entry and entry.listings or nil
    local ownQty, ownListings, ownKnown, ownUpdatedAt = OwnedStats(itemID, realmKey)
    if not entry and not ownKnown then return nil end
    return {
        -- при пустом АХ показываем последнюю известную цену как stale (см. CacheNoAuction)
        price = entry and (entry.price or entry.lastPrice) or nil,
        qty = qty,
        listings = listings,
        ownQty = ownQty,
        ownListings = ownListings,
        ownKnown = ownKnown,
        ownUpdatedAt = ownUpdatedAt,
        timestamp = entry and entry.timestamp or nil,
        stale = entry and (entry.noauction == true or IsExpired(entry, GetTTL())) or false,
    }
end

-- Снимок своих лотов. authoritative=true — сервер только что прислал данные
-- (OWNED_AUCTIONS_UPDATED): пишем как есть, пусто = «действительно ничего нет».
-- authoritative=false/nil — спекулятивный опрос (таймер после AUCTION_HOUSE_SHOW):
-- данные могут быть ещё не готовы, поэтому пустой ответ НЕ затирает хороший
-- снимок (иначе «Мои» молча обнуляется до следующего удачного скана).
function Auction.RefreshOwnedAuctions(authoritative)
    local realmKey = EnsureRealm()
    if not realmKey or not C_AuctionHouse then return false end
    local rows = nil
    if C_AuctionHouse.GetOwnedAuctions then
        local ok, value = pcall(C_AuctionHouse.GetOwnedAuctions)
        if ok and type(value) == "table" then rows = value end
    end
    if not rows and C_AuctionHouse.GetNumOwnedAuctions and C_AuctionHouse.GetOwnedAuctionInfo then
        local okCount, count = pcall(C_AuctionHouse.GetNumOwnedAuctions)
        if okCount and type(count) == "number" then
            rows = {}
            for i = 1, count do
                local okInfo, info = pcall(C_AuctionHouse.GetOwnedAuctionInfo, i)
                if okInfo and info then rows[#rows + 1] = info end
            end
        end
    end
    if type(rows) ~= "table" then
        if DecorLumberProfit and DecorLumberProfit.Log then
            DecorLumberProfit.Log("WARN", "Prices", "Owned auction API unavailable")
        end
        return false
    end
    local items = {}
    for _, info in ipairs(rows) do
        pcall(function()
            local itemID = info.itemKey and tonumber(info.itemKey.itemID)
            local quantity = tonumber(info.quantity)
            if type(itemID) ~= "number" or itemID <= 0 then return end
            local item = items[itemID]
            if not item then item = { quantity = 0, listings = 0 }; items[itemID] = item end
            item.quantity = item.quantity + (quantity or 0)
            item.listings = item.listings + 1
        end)
    end
    local root = OwnedRoot(realmKey)
    local me = CurrentCharacter()
    if not authoritative then
        local fresh = 0
        for _ in pairs(items) do fresh = fresh + 1 end
        if fresh == 0 then
            local prev = root[me]
            local prevCount = 0
            if type(prev) == "table" and type(prev.items) == "table" then
                for _ in pairs(prev.items) do prevCount = prevCount + 1 end
            end
            if prevCount > 0 then
                if DecorLumberProfit and DecorLumberProfit.Log then
                    DecorLumberProfit.Log("VERBOSE", "Prices", "Owned snapshot not ready yet, keeping %d lots", prevCount)
                end
                return true
            end
        end
    end
    root[me] = { updatedAt = Now(), items = items }
    NotifyPriceUpdate()
    return true
end

local function QueueOwnedRefresh(authoritative)
    if ownedRefreshQueued then return end
    ownedRefreshQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, function()
            ownedRefreshQueued = false
            Auction.RefreshOwnedAuctions(authoritative)
        end)
    else
        ownedRefreshQueued = false
        Auction.RefreshOwnedAuctions(authoritative)
    end
end

function Auction.ClearPriceCache(realmKey)
    local requestedRealm = realmKey
    realmKey = realmKey or EnsureRealm()
    if not realmKey then return end
    lastPriceUpdate = nil
    if DecorLumberProfitDB then
        DecorLumberProfitDB.priceCache = DecorLumberProfitDB.priceCache or {}
        DecorLumberProfitDB.priceUpdatedAtByRealm = DecorLumberProfitDB.priceUpdatedAtByRealm or {}
        if requestedRealm then
            DecorLumberProfitDB.priceCache[realmKey] = {}
            DecorLumberProfitDB.priceUpdatedAtByRealm[realmKey] = nil
        else
            DecorLumberProfitDB.priceCache = {}
            DecorLumberProfitDB.priceUpdatedAtByRealm = {}
        end
    end
    -- Память смотрит на тот же (пустой) бакет, что и SV: иначе priceCache и
    -- DB.priceCache[realm] — разные таблицы, и записи расползаются.
    priceCache = RealmBucket(realmKey) or {}
    previewCache = {}
    previewTargets = {}
    -- «Сбросить кэш» сбрасывает и «Мои»: колонка своих лотов — тоже кэш
    -- (снимки), а не живые данные; scope тот же: конкретный реалм или всё.
    Auction.ClearOwnedAuctions(requestedRealm and realmKey or nil)
end

-- Сброс снимков своих лотов («Мои»). Scope как у ClearPriceCache: realmKey —
-- только этот реалм, nil — все реалмы. Отдельной памяти нет (OwnedStats читает
-- DB напрямую), достаточно удалить записи — следующий снимок придёт с АХ.
function Auction.ClearOwnedAuctions(realmKey)
    if not DecorLumberProfitDB then return end
    if realmKey then
        if DecorLumberProfitDB.ownedAuctions then
            DecorLumberProfitDB.ownedAuctions[realmKey] = nil
        end
    else
        DecorLumberProfitDB.ownedAuctions = {}
    end
end

function Auction.IsPending(itemID) return pending[itemID] end

function Auction.HasFreshPrice(itemID)
    EnsureRealm()
    local entry = priceCache[itemID] or (RealmBucket() and RealmBucket()[itemID])
    if not entry then return false end
    if entry.noauction then
        return (entry.timestamp ~= nil) and (Now() - entry.timestamp) <= GetTTL()
    end
    if not entry.price then return false end
    if not entry.timestamp then return true end
    return (Now() - entry.timestamp) <= GetTTL()
end

-- ==== Парсинг цены из результатов аукциона ===
-- Безопасное чтение конкуренции: суммарно штук (totalQuantity) + число лотов (num results).
-- Всё за гардами + pcall: в тестах/старых клиентах методов может не быть — тогда nil.
local function SafeCommodityQuantity(itemID)
    if not C_AuctionHouse or type(itemID) ~= "number" then return nil, nil end
    local qty, num = nil, nil
    if C_AuctionHouse.GetCommoditySearchResultsQuantity then
        local ok, v = pcall(C_AuctionHouse.GetCommoditySearchResultsQuantity, itemID)
        if ok and type(v) == "number" then qty = v end
    end
    if C_AuctionHouse.GetNumCommoditySearchResults then
        local ok, v = pcall(C_AuctionHouse.GetNumCommoditySearchResults, itemID)
        if ok and type(v) == "number" then num = v end
    end
    return qty, num
end

local function SafeItemQuantity(itemKey)
    if not C_AuctionHouse or not itemKey then return nil, nil end
    local qty, num = nil, nil
    if C_AuctionHouse.GetItemSearchResultsQuantity then
        local ok, v = pcall(C_AuctionHouse.GetItemSearchResultsQuantity, itemKey)
        if ok and type(v) == "number" then qty = v end
    end
    if C_AuctionHouse.GetNumItemSearchResults then
        local ok, v = pcall(C_AuctionHouse.GetNumItemSearchResults, itemKey)
        if ok and type(v) == "number" then num = v end
    end
    return qty, num
end
-- Индекс browse-результатов [itemID] -> { minPrice, totalQuantity }: строится ОДИН раз
-- на поколение результатов (инвалидация событиями АХ), дальше lookup O(1).
-- Было: пересканирование всего GetBrowseResults() на каждый предмет -> O(N×M) в событиях.
local browseIndex = nil
local function InvalidateBrowseIndex() browseIndex = nil end
local function GetBrowseIndex()
    if browseIndex ~= nil then return browseIndex end
    browseIndex = {}
    if C_AuctionHouse and C_AuctionHouse.GetBrowseResults then
        local ok, browse = pcall(C_AuctionHouse.GetBrowseResults)
        if ok and type(browse) == "table" then
            for _, br in ipairs(browse) do
                if type(br) == "table" and br.itemKey and type(br.itemKey.itemID) == "number" then
                    local p = tonumber(br.minPrice)
                    local e = browseIndex[br.itemKey.itemID]
                    if p and (not e or p < e.minPrice) then
                        browseIndex[br.itemKey.itemID] = { minPrice = p, totalQuantity = br.totalQuantity }
                    end
                end
            end
        end
    end
    return browseIndex
end
-- Сканирует первые N результатов (ограничиваем 15 для производительности) и считает:
--   priceMin — цена самой дешёвой единицы;
--   priceAvg — средняя цена 10 самых дешёвых ЕДИНИЦ (реагенты), взвешенная по
--              количеству в лоте: лот на 7 шт по 100 и 7 шт по 120 даёт
--              (7*100 + 3*120) / 10 = 106;
--   rowQty   — построчная сумма info.quantity (фолбэк для totals-API, см. 2.2.2).
-- getInfo(i) -> info; extractPrice(info) -> цена ЗА ЕДИНИЦУ; extractQty(info) -> кол-во единиц.
-- Все вызовы API за pcall: в Midnight методы могут кидать (taint/secret) — скан не должен рваться.
local PRICE_AVG_UNITS = 10
local function GetSamplePrices(count, getInfo, extractPrice, extractQty)
    local limit = math.min(count or 0, 15)
    local rows, rowQty = {}, 0
    for i = 1, limit do
        local ok, info = pcall(getInfo, i)
        if ok and info then
            local ok2, p = pcall(extractPrice, info)
            if ok2 then
                p = p and tonumber(p)
                if p and p > 0 then
                    local q = 1
                    if extractQty then
                        local ok3, v = pcall(extractQty, info)
                        if ok3 then q = tonumber(v) or 1 end
                    end
                    if q < 1 then q = 1 end
                    rows[#rows + 1] = { price = p, qty = q }
                end
            end
            local qAll = (type(info) == "table" and tonumber(info.quantity)) or nil
            if qAll then rowQty = rowQty + qAll end
        end
    end
    if #rows == 0 then return nil, nil, rowQty end
    -- Сортируем сами: даже если сервер не отсортировал или сортировка недоступна,
    -- среднее берётся по самым дешёвым единицам.
    table.sort(rows, function(a, b) return a.price < b.price end)
    local minPrice, sum, units = nil, 0, 0
    for _, r in ipairs(rows) do
        if not minPrice then minPrice = r.price end
        if units >= PRICE_AVG_UNITS then break end
        local take = math.min(r.qty, PRICE_AVG_UNITS - units)
        sum = sum + r.price * take
        units = units + take
    end
    local avgPrice = (units > 0) and (sum / units) or nil
    return minPrice, avgPrice, rowQty
end

-- Построчный фолбэк qty: цена и количество должны происходить из одного чтения,
-- иначе запись рождается "цена без количества" и на других реалмах застывает
-- навсегда (пересканировать чужой реалм отсюда нельзя). Точный только при
-- num <= 15 (все строки просканированы); при большем num молча не применяем.
local function FallbackRowQty(qty, num, rowQty)
    if qty == nil and num ~= nil and num <= 15 and (rowQty or 0) > 0 then
        return rowQty
    end
    return qty
end

local function UpdatePriceFromCommodity(itemID)
    if not C_AuctionHouse then return nil end
    -- Только Safe-версии (внутри pcall): прямые вызовы без гардов рвали весь скан при ошибке API.
    local qty, num = SafeCommodityQuantity(itemID)
    if (not qty or qty == 0) and (not num or num == 0) then return nil end
    local minPrice, avgPrice, rowQty = GetSamplePrices(num, function(i)
        if not C_AuctionHouse.GetCommoditySearchResultInfo then return nil end
        return C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
    end, function(info) return info.unitPrice end,
       function(info) return info.quantity end)
    if minPrice then
        Auction.SetSamplePrice(itemID, minPrice, avgPrice, "commodity", FallbackRowQty(qty, num, rowQty), num)
        return minPrice
    end
    return nil
end

local function UpdatePriceFromItem(itemKey, itemID)
    if not C_AuctionHouse then return nil end
    local qty, num = SafeItemQuantity(itemKey)
    if (not qty or qty == 0) and (not num or num == 0) then return nil end
    -- Обычные (не commodity) предметы: buyoutAmount/minBid — цена ЛОТА (так её
    -- трактует и тест, и 2.2.2). Среднее по 10 единицам считаем только для
    -- commodity-реагентов (unitPrice уже за единицу), поэтому avg не передаём:
    -- крафтовый предмет показывает минимум, а non-commodity реагент — тоже минимум.
    local minPrice, _, rowQty = GetSamplePrices(num, function(i)
        if not C_AuctionHouse.GetItemSearchResultInfo then return nil end
        return C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
    end, function(info) return info.buyoutAmount or info.minBid end)
    -- Fallback: browse results (когда item-поиск пуст, но browse что-то вернул).
    -- Через индекс: O(1) на предмет вместо пересканирования всего списка.
    local browseQty = nil
    if not minPrice then
        local br = GetBrowseIndex()[itemID]
        if br then minPrice = br.minPrice; browseQty = br.totalQuantity end
    end
    if minPrice then
        if qty == nil then qty = FallbackRowQty(qty, num, rowQty) end
        if qty == nil then qty = browseQty end
        Auction.SetSamplePrice(itemID, minPrice, nil, "item", qty, num)
        return minPrice
    end
    return nil
end

-- Попытка синхронно получить цену из кэша аукциона (если уже искали)
function Auction.TryUpdateFromCache(itemID)
    if not itemID or type(itemID) ~= "number" then return nil end
    local p = UpdatePriceFromCommodity(itemID)
    if p then return p end
    if C_AuctionHouse and C_AuctionHouse.MakeItemKey then
        local ok, itemKey = pcall(C_AuctionHouse.MakeItemKey, itemID, 0, 0, 0)
        if ok and itemKey then
            p = UpdatePriceFromItem(itemKey, itemID)
            if p then return p end
        end
    end
    return nil
end

-- ==== Очередь запросов ====
-- Не выбрасываем предметы при переполнении: MAX_QUEUE ограничивает только мгновенную
-- вспышку Enqueue; излишек копится в overflow и подгружается по мере обработки.

function Auction.Enqueue(itemIDs)
    if not itemIDs then return end
    if type(itemIDs) == "number" then itemIDs = { itemIDs } end
    local cap = GetQueueCap()
    for _, id in ipairs(itemIDs) do
        if type(id) == "number" and not queuedSet[id]
            and not Auction.HasFreshPrice(id) and not Auction.IsPending(id) then
            if #queue < cap then
                table.insert(queue, id)
            else
                table.insert(overflow, id)
            end
            queuedSet[id] = true
        end
    end
    Auction.ProcessQueue()
end

local function OverflowSize()
    return #overflow - overflowHead + 1
end

-- Переливает overflow в очередь, выкидывая предметы, цена для которых уже не нужна.
-- Инвариант: queuedSet[id]=true ⇔ id лежит в queue или overflow.
local function PopFromOverflow()
    while #queue < GetQueueCap() and overflowHead <= #overflow do
        local id = overflow[overflowHead]
        overflow[overflowHead] = nil
        overflowHead = overflowHead + 1
        if not Auction.HasFreshPrice(id) and not Auction.IsPending(id) then
            table.insert(queue, id)
        else
            queuedSet[id] = nil
        end
    end
    if overflowHead > #overflow then overflow, overflowHead = {}, 1 end -- голова убежала: сброс массива
end

function Auction.ClearQueue()
    queue = {}
    overflow = {}
    overflowHead = 1
    queuedSet = {}
    pending = {}
    sentAt = {}
    attempts = {}
    droppedIDs = {}
    stats = { requested = 0, resolved = 0 }
    lastSentItemID = nil
    isProcessing = false
    if FRAME then FRAME:SetScript("OnUpdate", nil) end
end

-- Завершение обработки одного предмета: цена / пустой лот / ретрай
local function ResolveItem(itemID)
    if type(itemID) ~= "number" then return end
    local wasPending = pending[itemID]
    local p = Auction.TryUpdateFromCache(itemID)
    pending[itemID] = nil
    sentAt[itemID] = nil
    if p then
        attempts[itemID] = nil
        if wasPending then stats.resolved = stats.resolved + 1 end
        return
    end
    -- Полные результаты и ноль лотов = предмета нет на аукционе -> кэшируем как "нет аукционов".
    -- Проверяем и commodity, и item: некоммодити (экипировка и т.п.) иначе ретраились бы вечно.
    if C_AuctionHouse and C_AuctionHouse.HasFullCommoditySearchResults then
        local ok, full = pcall(C_AuctionHouse.HasFullCommoditySearchResults, itemID)
        if ok and full then
            CacheNoAuction(itemID, "commodity-empty")
            attempts[itemID] = nil
            if wasPending then stats.resolved = stats.resolved + 1 end
            return
        end
    end
    if C_AuctionHouse and C_AuctionHouse.HasFullItemSearchResults and C_AuctionHouse.MakeItemKey then
        local okKey, itemKey = pcall(C_AuctionHouse.MakeItemKey, itemID, 0, 0, 0)
        if okKey and itemKey then
            local ok, full = pcall(C_AuctionHouse.HasFullItemSearchResults, itemKey)
            if ok and full then
                CacheNoAuction(itemID, "item-empty")
                attempts[itemID] = nil
                if wasPending then stats.resolved = stats.resolved + 1 end
                return
            end
        end
    end
    -- Ответ не пришёл (троттл/дроп/таймаут) — ретраим; дропнутый троттлом запрос не тратит попытку
    local a = attempts[itemID] or 0
    if droppedIDs[itemID] then
        droppedIDs[itemID] = nil
    else
        a = a + 1
    end
    attempts[itemID] = a
    if a < MAX_ATTEMPTS then
        Auction.Enqueue({ itemID })
    else
        attempts[itemID] = nil -- след. ручной «Обновить цены» попробует заново
    end
end

local function NotifyScanFinished()
    if DecorLumberProfitUI and DecorLumberProfitUI.OnAuctionScanFinished then
        DecorLumberProfitUI.OnAuctionScanFinished()
    end
end

function Auction.ProcessQueue()
    if isProcessing then return end
    PopFromOverflow()
    if #queue == 0 then return end
    stats = { requested = 0, resolved = 0 } -- новый скан считается с нуля (Этап 7)
    if not FRAME then
        FRAME = CreateFrame("Frame", "DecorLumberProfitAuctionFrame")
    end
    isProcessing = true
    lastQueryTime = 0

    FRAME:SetScript("OnUpdate", function(self)
        if #queue == 0 then
            PopFromOverflow()
        end
        -- Завершаем скан только когда очередь, pending и sentAt пусты
        if #queue == 0 and not next(pending) and not next(sentAt) then
            self:SetScript("OnUpdate", nil)
            isProcessing = false
            NotifyScanFinished()
            return
        end

        local now = GetTime()
        -- Батч-разрешение отправленных (Этап 7): один sweep вместо N C_Timer.After.
        -- Удаление текущего ключа при обходе pairs безопасно; ResolveItem в sentAt не пишет.
        for id, t0 in pairs(sentAt) do
            if (now - t0) >= RESOLVE_DELAY then
                ResolveItem(id)
            end
        end
        if (now - lastQueryTime) < GetDelay() then return end

        -- Проверяем throttle
        if C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady then
            local ok, ready = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
            if ok and ready == false then
                -- ждём событие AUCTION_HOUSE_THROTTLED_SYSTEM_READY
                return
            end
        end

        -- Пропускаем предметы, цена на которые уже появилась, пока они ждали в очереди
        local itemID = nil
        while #queue > 0 do
            local cand = table.remove(queue, 1)
            queuedSet[cand] = nil
            if not Auction.HasFreshPrice(cand) and not Auction.IsPending(cand) then
                itemID = cand
                break
            end
        end
        if not itemID then
            PopFromOverflow()
            if #queue == 0 and not next(pending) and not next(sentAt) then
                self:SetScript("OnUpdate", nil)
                isProcessing = false
                NotifyScanFinished()
            end
            return
        end
        pending[itemID] = true

        -- Отправляем запрос: commodity/item через SendSearchQuery
        local sent = false
        if C_AuctionHouse and C_AuctionHouse.MakeItemKey and C_AuctionHouse.SendSearchQuery then
            local okKey, itemKey = pcall(C_AuctionHouse.MakeItemKey, itemID, 0, 0, 0)
            if okKey and itemKey then
                -- Сортировка по цене (возрастание): читаем дешёвые лоты первыми,
                -- среднее по 10 единицам считается по самым дешёвым.
                local E = _G.Enum
                local order = E and E.AuctionHouseSortOrder and E.AuctionHouseSortOrder.Price
                local sorts = order and { { sortOrder = order, reverseSort = false } } or {}
                local okSend = pcall(C_AuctionHouse.SendSearchQuery, itemKey, sorts, false)
                if okSend then sent = true end
            end
        end
        -- Fallback: SendBrowseQuery с searchString (если SendSearchQuery недоступен или аукцион закрыт)
        if not sent and C_AuctionHouse and C_AuctionHouse.SendBrowseQuery then
            local itemName = nil
            if C_Item and C_Item.GetItemInfo then
                local okName, name = pcall(C_Item.GetItemInfo, itemID)
                if okName then itemName = name end
            end
            if not itemName and GetItemInfo then
                itemName = GetItemInfo(itemID)
            end
            if itemName then
                local query = { searchString = itemName, sorts = {}, minLevel = nil, maxLevel = nil, filters = nil, itemClassFilters = nil }
                pcall(C_AuctionHouse.SendBrowseQuery, query)
                sent = true
            end
        end

        if not sent then
            -- Не удалось отправить — вернём в конец очереди с учётом попытки
            pending[itemID] = nil
            local a = (attempts[itemID] or 0) + 1
            attempts[itemID] = a
            if a < MAX_ATTEMPTS then
                table.insert(overflow, itemID)
                queuedSet[itemID] = true
            else
                attempts[itemID] = nil
            end
        else
            lastSentItemID = itemID
            stats.requested = stats.requested + 1
            -- Разрешение — батчем в sweep выше (Этап 7), без персонального таймера
            sentAt[itemID] = GetTime()
        end

        lastQueryTime = GetTime()
    end)
end

-- Снятие ожидания из всех структур (успех из события; считает прогресс один раз — см. ResolveItem)
local function ClearPending(itemID)
    if pending[itemID] then stats.resolved = stats.resolved + 1 end
    pending[itemID] = nil
    sentAt[itemID] = nil
    attempts[itemID] = nil
end

-- Coalesce UI-обновлений (Этап 7): события АХ сыплются пачками, таблица — максимум ~3/сек
local uiDirty = false
NotifyPriceUpdate = function()
    if uiDirty then return end
    uiDirty = true
    C_Timer.After(0.3, function()
        uiDirty = false
        if DecorLumberProfitUI and DecorLumberProfitUI.OnPriceUpdate then
            DecorLumberProfitUI.OnPriceUpdate()
        end
    end)
end

-- Коалесценция pending-прохода по browse-событиям: EXTRA_BROWSE_INFO_RECEIVED летит
-- по одному на предмет — прямой проход на каждое событие стоил O(события × pending × browse-строки).
-- Один проход на пачку (~0.1с) + индекс browse внутри = O(pending) на пачку.
local browsePassQueued = false
local function QueuePendingBrowsePass()
    if browsePassQueued then return end
    browsePassQueued = true
    C_Timer.After(0.1, function()
        browsePassQueued = false
        -- Удаление текущего ключа при обходе pairs безопасно: ClearPending только
        -- nil-ит существующие ключи pending, новых не добавляет.
        for id in pairs(pending) do
            Auction.TryUpdateFromCache(id)
            if priceCache[id] and priceCache[id].price then
                ClearPending(id)
            end
        end
        NotifyPriceUpdate()
    end)
end

-- ==== Быстрый предварительный browse-скан (по категориям) ====
-- Пока идёт точный точечный скан (100 запросов/мин), таблица получает
-- приблизительную минимальную цену сразу: SendBrowseQuery по категориям
-- (Reagent/Tradegoods/Housing) даёт minPrice без лимита SendSearchQuery.
-- Значения живут только в памяти (previewCache) и НЕ считаются свежим кэшем:
-- HasFreshPrice их не видит, поэтому точный запрос по предмету всё равно уходит.
-- Клиент удаляет запись, как только пришла точная цена (SetSamplePrice/
-- SetPrice/CacheNoAuction обнуляют preview).
local PREVIEW_TTL = 120
function Auction.GetPreviewPrice(itemID)
    local e = previewCache[itemID]
    if not e then return nil end
    if (GetTime() - (e.t or 0)) > PREVIEW_TTL then previewCache[itemID] = nil; return nil end
    return e.price
end

local function IngestPreview(rows)
    if type(rows) ~= "table" or not next(previewTargets) then return end
    local now, added = GetTime(), 0
    for _, row in ipairs(rows) do
        if type(row) == "table" and row.itemKey and type(row.itemKey.itemID) == "number" then
            local id = row.itemKey.itemID
            if previewTargets[id] and not Auction.HasFreshPrice(id) then
                local p = tonumber(row.minPrice)
                if p and p > 0 and (not previewCache[id] or p < previewCache[id].price) then
                    previewCache[id] = { price = p, t = now }
                    added = added + 1
                end
            end
        end
    end
    if added > 0 and NotifyPriceUpdate then NotifyPriceUpdate() end
end

function Auction.StartPreview(itemIDs)
    local cfg = DecorLumberProfitConfig and DecorLumberProfitConfig.AUCTION
    if not cfg or cfg.PREVIEW_ENABLED == false then return end
    if not (C_AuctionHouse and C_AuctionHouse.SendBrowseQuery) then return end
    previewTargets = {}
    local any = false
    for _, id in ipairs(itemIDs or {}) do
        if type(id) == "number" then previewTargets[id] = true; any = true end
    end
    if not any then return end
    local E = _G.Enum
    local order = E and E.AuctionHouseSortOrder and E.AuctionHouseSortOrder.Price
    local sorts = order and { { sortOrder = order, reverseSort = false } } or {}
    for _, classID in ipairs(cfg.PREVIEW_CLASSES or { 5, 7, 20 }) do
        local query = { searchString = "", sorts = sorts, itemClassFilters = { { classID = classID } } }
        pcall(C_AuctionHouse.SendBrowseQuery, query)
    end
end

-- ==== Обработчики событий аукциона ====
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
eventFrame:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
eventFrame:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
eventFrame:RegisterEvent("COMMODITY_SEARCH_RESULTS_RECEIVED")
eventFrame:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
eventFrame:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
eventFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
eventFrame:RegisterEvent("EXTRA_BROWSE_INFO_RECEIVED")
eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
eventFrame:RegisterEvent("OWNED_AUCTIONS_UPDATED")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "AUCTION_HOUSE_SHOW" or event == "OWNED_AUCTIONS_UPDATED" then
        -- SHOW — спекулятивно (данные могут догружаться), UPDATED от сервера — авторитетно
        QueueOwnedRefresh(event == "OWNED_AUCTIONS_UPDATED")
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_RECEIVED" then
        local itemID = arg1
        if type(itemID) == "number" then
            Auction.TryUpdateFromCache(itemID)
            if priceCache[itemID] and priceCache[itemID].price then
                ClearPending(itemID)
            end
        else
            -- COMMODITY_SEARCH_RESULTS_RECEIVED без аргумента — пробуем обновить все pending commodity
            for id in pairs(pending) do
                Auction.TryUpdateFromCache(id)
                if priceCache[id] and priceCache[id].price then
                    ClearPending(id)
                end
            end
        end
        NotifyPriceUpdate()
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        local itemKey = arg1
        if itemKey and itemKey.itemID then
            local itemID = itemKey.itemID
            local p = UpdatePriceFromItem(itemKey, itemID)
            if p then
                ClearPending(itemID)
            end
            NotifyPriceUpdate()
        end
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        -- Пачка browse-результатов: сразу подтягиваем предварительные цены.
        IngestPreview(arg1)
        InvalidateBrowseIndex()
        QueuePendingBrowsePass()
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "EXTRA_BROWSE_INFO_RECEIVED" then
        -- Результаты browse изменились: индекс протух; pending-проход — коалеснутый.
        -- Если preview-скан ещё активен, добираем минимумы из текущего набора.
        InvalidateBrowseIndex()
        if next(previewTargets) and C_AuctionHouse and C_AuctionHouse.GetBrowseResults then
            local ok, rows = pcall(C_AuctionHouse.GetBrowseResults)
            if ok then IngestPreview(rows) end
        end
        QueuePendingBrowsePass()
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        -- Продолжаем очередь
        lastQueryTime = 0
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
        -- Запрос отброшен из-за лимита 100/мин: пауза ~4 сек, последнему предмету сохраним попытку
        if lastSentItemID and pending[lastSentItemID] then
            droppedIDs[lastSentItemID] = true
        end
        lastQueryTime = GetTime() + 4
        if DecorLumberProfitUI and DecorLumberProfitUI.OnThrottleDropped then DecorLumberProfitUI.OnThrottleDropped() end
    end
end)

-- ==== Внешний источник цен (Auctionator, опционально) ====
-- Auctionator.API.v1.GetAuctionPriceByItemID(itemID) -> copper | nil
-- ("last scanned price" из базы сканов Auctionator). Только чтение чужой базы:
-- синхронно, без throttle и без открытого АХ. Отдаёт ТОЛЬКО цену (без
-- qty/listings) — колонки «На АХ»/«Мои» при таком источнике показывают прочерк.
-- nil/мусор = «данных нет»: в need для native fallback, НЕ маркируем noauction
-- (иначе затёрли бы lastPrice ложным отсутствием). Все вызовы за pcall + WARN
-- в Diag при поломке API (AGENTS п.6: guard не молчит о поломке).
local externalWarned = false

function Auction.IsAuctionatorAvailable()
    local A = _G.Auctionator
    if type(A) ~= "table" then return false end
    local api = A.API
    if type(api) ~= "table" then return false end
    local v1 = api.v1
    if type(v1) ~= "table" then return false end
    return type(v1.GetAuctionPriceByItemID) == "function"
end

function Auction.GetExternalPrice(itemID)
    if type(itemID) ~= "number" then return nil end
    if not Auction.IsAuctionatorAvailable() then return nil end
    local fn = _G.Auctionator.API.v1.GetAuctionPriceByItemID
    local ok, value = pcall(fn, itemID)
    if not ok then
        if not externalWarned and DecorLumberProfit and DecorLumberProfit.Log then
            DecorLumberProfit.Log("WARN", "Prices", "Auctionator API failed, native fallback")
        end
        externalWarned = true
        return nil
    end
    value = tonumber(value)
    if value and value > 0 then return value end
    return nil
end

-- Эффективный источник: "auctionator" | "native".
-- Настройка AUCTION.PRICE_SOURCE ("auto"|"native"|"auctionator", персист
-- DB.settings.priceSource): auto = auctionator при наличии API, иначе native.
-- Без Auctionator поведение 1:1 как раньше при любом значении.
local function IsValidSource(v)
    return v == "auto" or v == "native" or v == "auctionator"
end

function Auction.GetConfiguredPriceSource()
    local db = _G.DecorLumberProfitDB
    local saved = db and db.settings and db.settings.priceSource
    if type(saved) == "string" and IsValidSource(saved) then return saved end
    local cfg = _G.DecorLumberProfitConfig and _G.DecorLumberProfitConfig.AUCTION
    local v = cfg and cfg.PRICE_SOURCE
    if type(v) == "string" and IsValidSource(v) then return v end
    return "auto"
end

function Auction.SetPriceSource(src)
    if type(src) ~= "string" or not IsValidSource(src) then return false end
    DecorLumberProfitConfig = DecorLumberProfitConfig or {}
    DecorLumberProfitConfig.AUCTION = DecorLumberProfitConfig.AUCTION or {}
    DecorLumberProfitConfig.AUCTION.PRICE_SOURCE = src
    DecorLumberProfitDB = DecorLumberProfitDB or {}
    DecorLumberProfitDB.settings = DecorLumberProfitDB.settings or {}
    DecorLumberProfitDB.settings.priceSource = src
    return true
end

function Auction.IsExternalActive()
    local src = Auction.GetConfiguredPriceSource()
    if src == "native" then return false end
    -- "auto" и "auctionator": external только при живом API; иначе тихий native fallback
    return Auction.IsAuctionatorAvailable()
end

-- Мгновенный импорт списка itemID из Auctionator в общий кэш (realm-bucket,
-- source="auctionator", штамп TouchPriceUpdate через SetPrice).
-- Возвращает imported (число), missing (без данных — для native fallback).
function Auction.ImportFromAuctionator(itemIDs)
    local imported, missing = 0, {}
    if type(itemIDs) ~= "table" then return imported, missing end
    for _, id in ipairs(itemIDs) do
        if type(id) == "number" and not Auction.HasFreshPrice(id) then
            local price = Auction.GetExternalPrice(id)
            if price then
                Auction.SetPrice(id, price, "auctionator")
                imported = imported + 1
            else
                missing[#missing + 1] = id
            end
        end
    end
    return imported, missing
end

-- ==== Сбор цен для списка рецептов (map itemID -> price) ====
-- map: известные цены; need: уникальные itemID без свежей цены (для очереди запросов)
function Auction.CollectPricesForRecipes(recipes)
    local map = {}
    local need = {}
    local handled = {}
    local extImported = 0 -- сколько цен подтянуто из Auctionator за этот вызов
    -- Древесина на аукционе не продаётся: запросы по ней не отправляем вообще.
    -- Только кэш-прочтение для колонки «цена др.»; экономика держится на maxWoodPrice.
    local cfg = DecorLumberProfitConfig
    local woodSet = (cfg and cfg.WOOD_IDS_SET) or {}
    if cfg and cfg.WOOD_IDS_SET == nil and cfg.WOOD_ITEM_IDS then
        woodSet = {}
        for _, id in ipairs(cfg.WOOD_ITEM_IDS) do woodSet[id] = true end
    end

    local function Collect(id, role)
        if type(id) ~= "number" then return end
        -- Роль важна даже для уже обработанного id: от неё зависит, что показывать —
        -- минимум (крафтовый предмет) или среднее 10 дешёвых единиц (реагент).
        -- Приоритет у output: если предмет и крафтится, и используется как реагент,
        -- в колонке «цена продажи» показываем минимум.
        if role == "output" then
            itemRole[id] = "output"
        elseif itemRole[id] ~= "output" then
            itemRole[id] = role or "reagent"
        end
        if handled[id] then return end
        handled[id] = true
        if woodSet[id] then
            -- cache-only: в need (поиск по АХ) не попадает никогда
            local p = Auction.GetCachedPrice(id)
            if p then map[id] = p end
            return
        end
        -- TTL-корректно: свежесть решает HasFreshPrice, а не наличие записи.
        -- Раньше протухшая цена в памяти считалась свежей (GetCachedPrice без TTL),
        -- а протухший noauction вообще никогда не перезапрашивался.
        if Auction.HasFreshPrice(id) then
            local p = Auction.GetCachedPrice(id)
            if p then map[id] = p end
            -- свежий чистый noauction (без lastPrice): ни в map, ни в need
            -- (цены нет и не будет до протухания)
        else
            -- Протухшая цена: показываем последнюю известную, пока идёт фоновый
            -- рескан — иначе цена "забывается" каждый TTL. В need — всё равно.
            local p = Auction.GetCachedPrice(id)
            if p then map[id] = p end
            -- Совсем нет кэша — берём быструю предварительную (browse) цену, чтобы
            -- таблица не была пустой; помечаем "~" в UI. Точный запрос всё равно в need.
            if not p and Auction.GetPreviewPrice then
                local pv = Auction.GetPreviewPrice(id)
                if pv then map[id] = pv end
            end
            -- External-first: синхронный импорт из Auctionator выигрывает у очереди АХ
            -- (свежая внешняя цена перекрывает и протухшую). Нет данных — в need
            -- для native fallback, как раньше.
            if Auction.IsExternalActive() then
                local ext = Auction.GetExternalPrice(id)
                if ext then
                    Auction.SetPrice(id, ext, "auctionator")
                    map[id] = ext
                    extImported = extImported + 1
                    return
                end
            end
            table.insert(need, id)
        end
    end

    for _, rec in ipairs(recipes) do
        -- Выход с BoP (bind 1) / Warband (bind 8/9) на АХ не продаётся:
        -- цену не ищем и очередь АХ такими предметами не засоряем.
        -- (Сюда они попадать не должны — Scan/Store их режут, — но guard дешёвый.)
        if rec.outputItemID then
            local skip = false
            local ItemInfo = _G.DecorLumberProfitItemInfo
            if ItemInfo and ItemInfo.IsUnsellable then
                local ok, u = pcall(ItemInfo.IsUnsellable, rec.outputItemID)
                if ok and u == true then skip = true end
            end
            if not skip then Collect(rec.outputItemID, "output") end
        end
        for _, r in ipairs(rec.reagents or {}) do
            if type(r.itemID) == "number" then Collect(r.itemID, "reagent") end
        end
    end
    -- Древесина, реально используемая рецептами (колонка «цена др.»; cache-only, АХ не ищется)
    local woodIDs = DecorLumberProfitConfig.WOOD_ITEM_IDS or (DecorLumberProfitConfig.WOOD_ITEM_ID and { DecorLumberProfitConfig.WOOD_ITEM_ID } or {})
    for _, woodID in ipairs(woodIDs) do
        local used = false
        for _, rec in ipairs(recipes) do
            if rec.woodItemID == woodID then used = true; break end
            for _, r in ipairs(rec.reagents or {}) do
                if r.itemID == woodID then used = true; break end
            end
            if used then break end
        end
        if used then Collect(woodID, "reagent") end
    end
    -- Третий возврат (extImported) аддитивен: старые колл-сайты на двух значениях не ломаются.
    return map, need, extImported
end

function Auction.RequestPrices(itemIDs)
    if itemIDs then Auction.StartPreview(itemIDs) end
    Auction.Enqueue(itemIDs)
end

-- Интроспекция очереди для Diag (/dlp debug status). Этап 0.2, аддитивно.
-- Этап 7: overflow через OverflowSize(), плюс прогресс requested/resolved.
function Auction.GetQueueInfo()
    local p, a, d = 0, 0, 0
    for _ in pairs(pending) do p = p + 1 end
    for _ in pairs(attempts) do a = a + 1 end
    for _ in pairs(droppedIDs) do d = d + 1 end
    return {
        realm = activeRealmKey,
        realmName = activeRealmName,
        queue = #queue,
        overflow = OverflowSize(),
        pending = p,
        attempts = a,
        dropped = d,
        lastSent = lastSentItemID,
        processing = isProcessing,
        requested = stats.requested,
        resolved = stats.resolved,
        lastUpdate = Auction.GetLastPriceUpdate(),
        source = Auction.GetConfiguredPriceSource(),
        external = Auction.IsExternalActive(),
    }
end

-- Глобальный доступ для отладки + legacy-алиас (Этап 7: переименование Auction -> Prices)
_G.DecorLumberProfitPrices = Auction
_G.DecorLumberProfitAuction = Auction
