-- Services/ItemInfo.lua | DecorLumberProfit | Retail 12.1.0
-- Кэш данных предметов (Этап 3): имена, bindType, отложенные рецепты.
-- Tri-state привязки: true=продукцию нельзя продать, false=можно, nil=данные ещё грузятся.
-- WoW Lua 5.1: no goto, no //, no bitwise ops. No WoW calls at top level.

DecorLumberProfitItemInfo = {}
local ItemInfo = DecorLumberProfitItemInfo

-- Enum.ItemBind (14-й возврат C_Item.GetItemInfo / GetItemInfo):
-- 0=None, 1=OnAcquire, 2=OnEquip, 3=OnUse, 4=Quest, 5=Unused1, 6=Unused2,
-- 7=ToWoWAccount, 8=ToBnetAccount, 9=ToBnetAccountUntilEquipped
-- (см. wiki-lua/blizzard_api_doc/ItemConstantsDocumentation.lua:179-195).
-- Русские тултипы клиента:
--  1 = "Становится персональным при получении" (BoP),
--  8 = "Привязывается к отряду" (Warband),
--  9 = "Привязывается к отряду до надевания" (Warband-until-equipped).
-- На АХ выставляются только 0 (без привязки) и 2 (BoE до экипировки) — используем белый список.
-- 1/8/9 явно ИСКЛЮЧЕНЫ (рецепты с такой продукцией не учитываются).
ItemInfo.BIND_NONE = 0
ItemInfo.BIND_ON_ACQUIRE = 1 -- BoP: "Становится персональным при получении"
ItemInfo.BIND_ON_EQUIP = 2 -- BoE
ItemInfo.BIND_ON_USE = 3
ItemInfo.BIND_QUEST = 4
ItemInfo.BIND_ACCOUNT = 7
ItemInfo.BIND_WARBAND = 8 -- "Привязывается к отряду"
ItemInfo.BIND_WARBAND_UNTIL_EQUIPPED = 9 -- "Привязывается к отряду до надевания"
local ITEM_BIND_SELLABLE = { [0] = true, [2] = true }
-- Явный блок-лист из запроса: BoP + Warband всегда непродаваемы,
-- даже если белый список выше когда-либо расширят.
local ITEM_BIND_EXCLUDED = { [1] = true, [8] = true, [9] = true }

ItemInfo._bindCache = {}
ItemInfo._nameCache = {}
ItemInfo._loadRequested = {}
-- Рецепты, ожидающие загрузки bindType: [spellID] = rec
ItemInfo._pending = {}

-- Сырой bindType предмета (Enum.ItemBind) или nil, если данные ещё грузятся.
-- Возвращает nil БЕЗ кэширования: вызывающий решает (pending vs пропуск).
function ItemInfo.GetBindType(itemID)
    if type(itemID) ~= "number" then return nil end
    local bind = nil
    if C_Item and C_Item.GetItemInfo then
        local ok, _, _, _, _, _, _, _, _, _, _, _, _, b = pcall(C_Item.GetItemInfo, itemID)
        if ok and b ~= nil then bind = b end
    end
    if bind == nil and _G.GetItemInfo then
        local _, _, _, _, _, _, _, _, _, _, _, _, _, b = GetItemInfo(itemID)
        bind = b
    end
    return bind
end

-- true — bind точно непродаваемый (в т.ч. BoP=1, Warband=8/9);
-- false — продаваемый (0/2); nil — данные ещё грузятся.
function ItemInfo.IsBindUnsellable(bind)
    if bind == nil then return nil end
    if ITEM_BIND_EXCLUDED[bind] then return true end
    return not ITEM_BIND_SELLABLE[bind]
end

function ItemInfo.IsUnsellable(itemID)
    if type(itemID) ~= "number" then return false end
    if ItemInfo._bindCache[itemID] ~= nil then return ItemInfo._bindCache[itemID] end
    local bind = ItemInfo.GetBindType(itemID)
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
    local r = ItemInfo.IsBindUnsellable(bind)
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

-- Удаляет из списка рецепты с непродаваемой продукцией
-- (BoP bind 1, Warband bind 8/9 и остальные не из белого списка 0/2); unsell==nil оставляет
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
