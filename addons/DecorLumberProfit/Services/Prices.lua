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
        -- Пробуем SavedVariables (переживает /reload; TTL x2 — компромисс между свежестью и запросами)
        local bucket = RealmBucket(realmKey)
        local saved = bucket and bucket[itemID]
        if saved then
            if IsExpired(saved, GetTTL() * 2) then return nil end
            if not realmKey or realmKey == activeRealmKey then priceCache[itemID] = saved end
            return saved.price, saved
        end
        return nil
    end
    return entry.price, entry
end

function Auction.SetPrice(itemID, price, source, qty, listings)
    if type(itemID) ~= "number" or type(price) ~= "number" then return end
    if not EnsureRealm() then return end
    local old = priceCache[itemID]
    if qty == nil and old then qty = old.qty end
    if listings == nil and old then listings = old.listings end
    CacheEntry(itemID, { price = price, timestamp = Now(), source = source or "unknown", qty = qty, listings = listings })
end

-- Кол-во лотов/штук на аукционе (конкуренция). Делит TTL с ценой: пишется тем же
-- ответом SendSearchQuery, отдельного запроса не требует.
-- Возвращает qty (суммарно штук), listings (число лотов), entry. nil — ещё не сканировали.
function Auction.GetCachedQuantity(itemID)
    if type(itemID) ~= "number" then return nil end
    EnsureRealm()
    local entry = priceCache[itemID]
    if not entry then
        local bucket = RealmBucket()
        local saved = bucket and bucket[itemID]
        if saved then
            if IsExpired(saved, GetTTL() * 2) then return nil end
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
        local price = entry and entry.price or nil
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
            stale = entry and IsExpired(entry, GetTTL()) or false,
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
        price = entry and entry.price or nil,
        qty = qty,
        listings = listings,
        ownQty = ownQty,
        ownListings = ownListings,
        ownKnown = ownKnown,
        ownUpdatedAt = ownUpdatedAt,
        timestamp = entry and entry.timestamp or nil,
        stale = entry and IsExpired(entry, GetTTL()) or false,
    }
end

function Auction.RefreshOwnedAuctions()
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
    root[CurrentCharacter()] = { updatedAt = Now(), items = items }
    NotifyPriceUpdate()
    return true
end

local function QueueOwnedRefresh()
    if ownedRefreshQueued then return end
    ownedRefreshQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, function()
            ownedRefreshQueued = false
            Auction.RefreshOwnedAuctions()
        end)
    else
        ownedRefreshQueued = false
        Auction.RefreshOwnedAuctions()
    end
end

function Auction.ClearPriceCache(realmKey)
    local requestedRealm = realmKey
    realmKey = realmKey or EnsureRealm()
    if not realmKey then return end
    priceCache = {}
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
-- Минимальная цена по первым N результатам (ограничиваем 15 для производительности).
-- Все вызовы API за pcall: в Midnight методы могут кидать (taint/secret) — скан не должен рваться.
local function GetMinPrice(count, getInfo, extractPrice)
    local minPrice = nil
    local limit = math.min(count or 0, 15)
    for i = 1, limit do
        local ok, info = pcall(getInfo, i)
        if ok and info then
            local ok2, p = pcall(extractPrice, info)
            if ok2 then
                p = p and tonumber(p)
                if p and (not minPrice or p < minPrice) then minPrice = p end
            end
        end
    end
    return minPrice
end

local function UpdatePriceFromCommodity(itemID)
    if not C_AuctionHouse then return nil end
    -- Только Safe-версии (внутри pcall): прямые вызовы без гардов рвали весь скан при ошибке API.
    local qty, num = SafeCommodityQuantity(itemID)
    if (not qty or qty == 0) and (not num or num == 0) then return nil end
    local minPrice = GetMinPrice(num, function(i)
        if not C_AuctionHouse.GetCommoditySearchResultInfo then return nil end
        return C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
    end, function(info) return info.unitPrice end)
    if minPrice then
        Auction.SetPrice(itemID, minPrice, "commodity", qty, num)
        return minPrice
    end
    return nil
end

local function UpdatePriceFromItem(itemKey, itemID)
    if not C_AuctionHouse then return nil end
    local qty, num = SafeItemQuantity(itemKey)
    if (not qty or qty == 0) and (not num or num == 0) then return nil end
    local minPrice = GetMinPrice(num, function(i)
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
        if qty == nil then qty = browseQty end
        Auction.SetPrice(itemID, minPrice, "item", qty, num)
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
            CacheEntry(itemID, { noauction = true, timestamp = Now(), source = "commodity-empty", qty = 0, listings = 0 })
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
                CacheEntry(itemID, { noauction = true, timestamp = Now(), source = "item-empty", qty = 0, listings = 0 })
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
                local okSend = pcall(C_AuctionHouse.SendSearchQuery, itemKey, {}, false)
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

-- ==== Обработчики событий аукциона ====
local eventFrame = CreateFrame("Frame")
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
        QueueOwnedRefresh()
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
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "EXTRA_BROWSE_INFO_RECEIVED" then
        -- Результаты browse изменились: индекс протух; pending-проход — коалеснутый
        InvalidateBrowseIndex()
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

-- ==== Сбор цен для списка рецептов (map itemID -> price) ====
-- map: известные цены; need: уникальные itemID без свежей цены (для очереди запросов)
function Auction.CollectPricesForRecipes(recipes)
    local map = {}
    local need = {}
    local handled = {}
    -- Древесина на аукционе не продаётся: запросы по ней не отправляем вообще.
    -- Только кэш-прочтение для колонки «цена др.»; экономика держится на maxWoodPrice.
    local cfg = DecorLumberProfitConfig
    local woodSet = (cfg and cfg.WOOD_IDS_SET) or {}
    if cfg and cfg.WOOD_IDS_SET == nil and cfg.WOOD_ITEM_IDS then
        woodSet = {}
        for _, id in ipairs(cfg.WOOD_ITEM_IDS) do woodSet[id] = true end
    end

    local function Collect(id)
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
            -- свежий noauction: ни в map, ни в need (цены нет и не будет до протухания)
        else
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
            if not skip then Collect(rec.outputItemID) end
        end
        for _, r in ipairs(rec.reagents or {}) do
            if type(r.itemID) == "number" then Collect(r.itemID) end
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
        if used then Collect(woodID) end
    end
    return map, need
end

function Auction.RequestPrices(itemIDs)
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
    }
end

-- Глобальный доступ для отладки + legacy-алиас (Этап 7: переименование Auction -> Prices)
_G.DecorLumberProfitPrices = Auction
_G.DecorLumberProfitAuction = Auction
