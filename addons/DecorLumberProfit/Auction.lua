-- Auction.lua | DecorLumberProfit | Retail 12.1.0
-- Получение цен с аукциона через C_AuctionHouse (commodity + item), throttle-очередь.

DecorLumberProfitAuction = {}
local Auction = DecorLumberProfitAuction

local priceCache = {} -- [itemID] = { price=copper, timestamp=time(), source=..., noauction? }
local pending = {}    -- [itemID] = true (ожидает ответа)
local queue = {}      -- список itemID на запрос
local overflow = {}   -- излишек сверх MAX_QUEUE, подгружается по мере обработки
local queuedSet = {}  -- [itemID] = true — O(1) проверка «уже в queue/overflow»
local isProcessing = false
local lastQueryTime = 0
local attempts = {}   -- [itemID] = число попыток запроса
local droppedIDs = {} -- [itemID] = true (запрос отброшен троттлом — попытка не считается)
local lastSentItemID = nil
local MAX_ATTEMPTS = 3
local RESOLVE_DELAY = 1.5

local FRAME = nil

local function Now() return time() end

local function CfgNumber(key, fallback)
    local v = DecorLumberProfitConfig and DecorLumberProfitConfig.AUCTION and DecorLumberProfitConfig.AUCTION[key]
    return (type(v) == "number") and v or fallback
end

local function GetTTL() return CfgNumber("PRICE_TTL", 900) end
local function GetDelay() return CfgNumber("QUERY_DELAY", 0.75) end
local function GetQueueCap() return CfgNumber("MAX_QUEUE", 400) end

-- Единая точка записи в кэш: память + SavedVariables
local function CacheEntry(itemID, entry)
    priceCache[itemID] = entry
    DecorLumberProfitDB = DecorLumberProfitDB or {}
    DecorLumberProfitDB.priceCache = DecorLumberProfitDB.priceCache or {}
    DecorLumberProfitDB.priceCache[itemID] = entry
end

local function IsExpired(entry, ttl)
    return entry.timestamp ~= nil and (Now() - entry.timestamp) > ttl
end

-- ==== Форматирование денег ====
local MONEY_ICON = {
    g = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t",
    s = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t",
    c = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t",
}

-- Компактно: >1g — «12g 34s», <1g — «56s 78c», <1s — «9c». Знак — текстом, цвет задаёт вызывающий.
function Auction.FormatMoney(copper)
    if copper == nil then return "—" end
    copper = math.floor(tonumber(copper) or 0)
    local sign = ""
    if copper < 0 then sign = "-"; copper = -copper end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then
        parts[#parts + 1] = tostring(g) .. MONEY_ICON.g
        if s > 0 then parts[#parts + 1] = tostring(s) .. MONEY_ICON.s end
    elseif s > 0 then
        parts[#parts + 1] = tostring(s) .. MONEY_ICON.s
        if c > 0 then parts[#parts + 1] = tostring(c) .. MONEY_ICON.c end
    else
        parts[#parts + 1] = tostring(c) .. MONEY_ICON.c
    end
    return sign .. table.concat(parts, " ")
end

-- ==== Кэш цен ====
function Auction.GetCachedPrice(itemID)
    if type(itemID) ~= "number" then return nil end
    local entry = priceCache[itemID]
    if not entry then
        -- Пробуем SavedVariables (переживает /reload; TTL x2 — компромисс между свежестью и запросами)
        local saved = DecorLumberProfitDB and DecorLumberProfitDB.priceCache and DecorLumberProfitDB.priceCache[itemID]
        if saved then
            if IsExpired(saved, GetTTL() * 2) then return nil end
            priceCache[itemID] = saved
            return saved.price, saved
        end
        return nil
    end
    return entry.price, entry
end

function Auction.SetPrice(itemID, price, source)
    if type(itemID) ~= "number" or type(price) ~= "number" then return end
    CacheEntry(itemID, { price = price, timestamp = Now(), source = source or "unknown" })
end

function Auction.ClearPriceCache()
    priceCache = {}
    if DecorLumberProfitDB then
        DecorLumberProfitDB.priceCache = {}
    end
end

function Auction.IsPending(itemID) return pending[itemID] end

function Auction.HasFreshPrice(itemID)
    local entry = priceCache[itemID] or (DecorLumberProfitDB and DecorLumberProfitDB.priceCache and DecorLumberProfitDB.priceCache[itemID])
    if not entry then return false end
    if entry.noauction then
        return (entry.timestamp ~= nil) and (Now() - entry.timestamp) <= GetTTL()
    end
    if not entry.price then return false end
    if not entry.timestamp then return true end
    return (Now() - entry.timestamp) <= GetTTL()
end

-- ==== Парсинг цены из результатов аукциона ====
-- Минимальная цена по первым N результатам (ограничиваем 15 для производительности)
local function GetMinPrice(count, getInfo, extractPrice)
    local minPrice = nil
    local limit = math.min(count or 0, 15)
    for i = 1, limit do
        local info = getInfo(i)
        local p = info and extractPrice(info)
        p = p and tonumber(p)
        if p and (not minPrice or p < minPrice) then minPrice = p end
    end
    return minPrice
end

local function UpdatePriceFromCommodity(itemID)
    if not C_AuctionHouse or not C_AuctionHouse.GetCommoditySearchResultsQuantity then return nil end
    local num = C_AuctionHouse.GetNumCommoditySearchResults and C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
    local qty = C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID)
    if (not qty or qty == 0) and (not num or num == 0) then return nil end
    local minPrice = GetMinPrice(num, function(i)
        return C_AuctionHouse.GetCommoditySearchResultInfo and C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
    end, function(info) return info.unitPrice end)
    if minPrice then
        Auction.SetPrice(itemID, minPrice, "commodity")
        return minPrice
    end
    return nil
end

local function UpdatePriceFromItem(itemKey, itemID)
    if not C_AuctionHouse or not C_AuctionHouse.GetItemSearchResultsQuantity then return nil end
    local num = C_AuctionHouse.GetNumItemSearchResults and C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0
    local qty = C_AuctionHouse.GetItemSearchResultsQuantity(itemKey)
    if (not qty or qty == 0) and (not num or num == 0) then return nil end
    local minPrice = GetMinPrice(num, function(i)
        return C_AuctionHouse.GetItemSearchResultInfo and C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
    end, function(info) return info.buyoutAmount or info.minBid end)
    -- Fallback: browse results (когда item-поиск пуст, но browse что-то вернул)
    if not minPrice and C_AuctionHouse.GetBrowseResults then
        local browse = C_AuctionHouse.GetBrowseResults()
        if browse then
            for _, br in ipairs(browse) do
                if br.itemKey and br.itemKey.itemID == itemID and br.minPrice then
                    local p = tonumber(br.minPrice)
                    if p and (not minPrice or p < minPrice) then minPrice = p end
                end
            end
        end
    end
    if minPrice then
        Auction.SetPrice(itemID, minPrice, "item")
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

-- Переливает overflow в очередь, выкидывая предметы, цена для которых уже не нужна.
-- Инвариант: queuedSet[id]=true ⇔ id лежит в queue или overflow.
local function PopFromOverflow()
    while #queue < GetQueueCap() and #overflow > 0 do
        local id = table.remove(overflow, 1)
        if not Auction.HasFreshPrice(id) and not Auction.IsPending(id) then
            table.insert(queue, id)
        else
            queuedSet[id] = nil
        end
    end
end

function Auction.ClearQueue()
    queue = {}
    overflow = {}
    queuedSet = {}
    pending = {}
    attempts = {}
    droppedIDs = {}
    lastSentItemID = nil
    isProcessing = false
    if FRAME then FRAME:SetScript("OnUpdate", nil) end
end

-- Завершение обработки одного предмета: цена / пустой лот / ретрай
local function ResolveItem(itemID)
    if type(itemID) ~= "number" then return end
    local p = Auction.TryUpdateFromCache(itemID)
    pending[itemID] = nil
    if p then
        attempts[itemID] = nil
        return
    end
    -- Полные результаты по commodity и ноль лотов = предмета нет на аукционе -> кэшируем как "нет аукционов"
    if C_AuctionHouse and C_AuctionHouse.HasFullCommoditySearchResults then
        local ok, full = pcall(C_AuctionHouse.HasFullCommoditySearchResults, itemID)
        if ok and full then
            CacheEntry(itemID, { noauction = true, timestamp = Now(), source = "commodity-empty" })
            attempts[itemID] = nil
            return
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
    if not FRAME then
        FRAME = CreateFrame("Frame", "DecorLumberProfitAuctionFrame")
    end
    isProcessing = true
    lastQueryTime = 0

    FRAME:SetScript("OnUpdate", function(self)
        if #queue == 0 then
            PopFromOverflow()
        end
        -- Завершаем скан только когда и очередь, и pending пусты
        if #queue == 0 and not next(pending) then
            self:SetScript("OnUpdate", nil)
            isProcessing = false
            NotifyScanFinished()
            return
        end

        local now = GetTime()
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
            if #queue == 0 and not next(pending) then
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
            -- Разрешаем предмет после предполагаемого ответа (цена / пустой лот / ретрай)
            C_Timer.After(RESOLVE_DELAY, function()
                ResolveItem(itemID)
            end)
        end

        lastQueryTime = GetTime()
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

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_RECEIVED" then
        local itemID = arg1
        if type(itemID) == "number" then
            Auction.TryUpdateFromCache(itemID)
            if priceCache[itemID] and priceCache[itemID].price then
                pending[itemID] = nil
                attempts[itemID] = nil
            end
        else
            -- COMMODITY_SEARCH_RESULTS_RECEIVED без аргумента — пробуем обновить все pending commodity
            for id in pairs(pending) do Auction.TryUpdateFromCache(id) end
        end
        if DecorLumberProfitUI and DecorLumberProfitUI.OnPriceUpdate then DecorLumberProfitUI.OnPriceUpdate() end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        local itemKey = arg1
        if itemKey and itemKey.itemID then
            local itemID = itemKey.itemID
            local p = UpdatePriceFromItem(itemKey, itemID)
            if p then
                pending[itemID] = nil
                attempts[itemID] = nil
            end
            if DecorLumberProfitUI and DecorLumberProfitUI.OnPriceUpdate then DecorLumberProfitUI.OnPriceUpdate() end
        end
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "EXTRA_BROWSE_INFO_RECEIVED" then
        for id in pairs(pending) do Auction.TryUpdateFromCache(id) end
        if DecorLumberProfitUI and DecorLumberProfitUI.OnPriceUpdate then DecorLumberProfitUI.OnPriceUpdate() end
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

    local function Collect(id)
        if handled[id] then return end
        handled[id] = true
        local p, entry = Auction.GetCachedPrice(id)
        if p then
            map[id] = p
        elseif not (entry and entry.noauction) then
            table.insert(need, id)
        end
    end

    for _, rec in ipairs(recipes) do
        if rec.outputItemID then Collect(rec.outputItemID) end
        for _, r in ipairs(rec.reagents or {}) do
            if type(r.itemID) == "number" then Collect(r.itemID) end
        end
    end
    -- Древесина, реально используемая рецептами (для колонки «цена др.» и расчёта maxWoodPrice)
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

-- Глобальный доступ для отладки
_G.DecorLumberProfitAuction = Auction
