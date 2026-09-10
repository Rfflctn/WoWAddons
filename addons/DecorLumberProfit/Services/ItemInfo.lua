-- Services/ItemInfo.lua | DecorLumberProfit | Retail 12.1.0
-- Кэш данных предметов (Этап 3): имена, bindType, отложенные рецепты.
-- Tri-state привязки: true=продукцию нельзя продать, false=можно, nil=данные ещё грузятся.
-- WoW Lua 5.1: no goto, no //, no bitwise ops. No WoW calls at top level.

DecorLumberProfitItemInfo = {}
local ItemInfo = DecorLumberProfitItemInfo

-- Enum.ItemBind (14-й возврат C_Item.GetItemInfo):
-- 0=None, 1=OnAcquire(BoP), 2=OnEquip(BoE), 3=OnUse/"в отряде, на арене или в рейде", 4=Quest, 7=Account, 8=Warband, 9=Warband-until-equipped
-- На АХ выставляются только 0 (без привязки) и 2 (BoE до экипировки) — используем белый список.
-- 3 (привязка при присоединении к отряду/рейду) явно ИСКЛЮЧЁН.
local ITEM_BIND_SELLABLE = { [0] = true, [2] = true }

ItemInfo._bindCache = {}
ItemInfo._nameCache = {}
ItemInfo._loadRequested = {}
-- Рецепты, ожидающие загрузки bindType: [spellID] = rec
ItemInfo._pending = {}

function ItemInfo.IsUnsellable(itemID)
    if type(itemID) ~= "number" then return false end
    if ItemInfo._bindCache[itemID] ~= nil then return ItemInfo._bindCache[itemID] end
    local bind = nil
    if C_Item and C_Item.GetItemInfo then
        local ok, _, _, _, _, _, _, _, _, _, _, _, _, b = pcall(C_Item.GetItemInfo, itemID)
        if ok and b ~= nil then bind = b end
    end
    if bind == nil and _G.GetItemInfo then
        local _, _, _, _, _, _, _, _, _, _, _, _, _, b = GetItemInfo(itemID)
        bind = b
    end
    if bind == nil then
        -- предмет не в кэше клиента — запрашиваем асинхронную загрузку с сервера
        if not ItemInfo._loadRequested[itemID] and _G.Item and Item.CreateFromItemID then
            ItemInfo._loadRequested[itemID] = true
            local ok, it = pcall(Item.CreateFromItemID, itemID)
            if ok and it and it.ContinueOnItemLoad then
                pcall(function() it:ContinueOnItemLoad(function() end) end)
            end
        end
        return nil
    end
    local r = not ITEM_BIND_SELLABLE[bind]
    ItemInfo._bindCache[itemID] = r
    return r
end

function ItemInfo.GetName(itemID)
    if type(itemID) ~= "number" then return nil end
    if ItemInfo._nameCache[itemID] then return ItemInfo._nameCache[itemID] end
    local name = nil
    if C_Item and C_Item.GetItemInfo then
        local ok, n = pcall(C_Item.GetItemInfo, itemID)
        if ok then name = n end
    end
    if not name and _G.GetItemInfo then name = GetItemInfo(itemID) end
    if name then ItemInfo._nameCache[itemID] = name end
    return name
end

function ItemInfo.PendingAdd(spellID, rec)
    if spellID and rec then ItemInfo._pending[spellID] = rec end
end

function ItemInfo.PendingCount()
    local c = 0
    for _ in pairs(ItemInfo._pending) do c = c + 1 end
    return c
end

-- Сервер сообщил, что данных о предмете нет (success=false) — сбрасываем ждущие по нему рецепты
function ItemInfo.FailPendingForItem(itemID)
    for spellID, rec in pairs(ItemInfo._pending) do
        if rec.outputItemID == itemID then
            ItemInfo._pending[spellID] = nil
            if DecorLumberProfitDB and DecorLumberProfitDB.recipes then
                DecorLumberProfitDB.recipes[spellID] = nil
            end
        end
    end
end

-- Возвращает рецепты, ставшие known-продаваемыми (bind дозагрузился)
function ItemInfo.ResolvePending()
    local resolved = {}
    for spellID, rec in pairs(ItemInfo._pending) do
        local st = rec.outputItemID and ItemInfo.IsUnsellable(rec.outputItemID)
        if st == false then
            ItemInfo._pending[spellID] = nil
            table.insert(resolved, rec)
        elseif st == true then
            ItemInfo._pending[spellID] = nil
            if DecorLumberProfitDB and DecorLumberProfitDB.recipes then
                DecorLumberProfitDB.recipes[spellID] = nil
            end
        end
    end
    return resolved
end

-- Удаляет из списка рецепты с непродаваемой продукцией; unsell==nil оставляет
function ItemInfo.PruneUnsellable(list)
    if not list then return 0 end
    local removed = 0
    for i = #list, 1, -1 do
        local rec = list[i]
        if rec and rec.outputItemID and ItemInfo.IsUnsellable(rec.outputItemID) == true then
            table.remove(list, i)
            removed = removed + 1
            if rec.recipeSpellID and DecorLumberProfitDB and DecorLumberProfitDB.recipes then
                DecorLumberProfitDB.recipes[rec.recipeSpellID] = nil
            end
        end
    end
    return removed
end

-- Диагностика для Diag (/dlp debug status через Core:GetPendingBindCount).
function ItemInfo.HealthCheck()
    local b, n = 0, 0
    for _ in pairs(ItemInfo._bindCache) do b = b + 1 end
    for _ in pairs(ItemInfo._nameCache) do n = n + 1 end
    return { ok = true, pending = ItemInfo.PendingCount(), bindCached = b, namesCached = n }
end

_G.DecorLumberProfitItemInfo = ItemInfo
