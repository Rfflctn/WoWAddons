-- Core.lua | DecorLumberProfit | Retail 12.1.0
-- Логика поиска рецептов, содержащих ЛЮБУЮ древесину (12 типов), и расчёт экономики.

local ADDON = "DecorLumberProfit"
DecorLumberProfitCore = {}
local Core = DecorLumberProfitCore

local WOOD_IDS = nil
local WOOD_SET = nil
local WOOD_NAMES = nil

local function GetWoodIDs()
    if WOOD_IDS then return WOOD_IDS, WOOD_SET end
    if DecorLumberProfitConfig then
        if DecorLumberProfitConfig.WOOD_ITEM_IDS then
            WOOD_IDS = DecorLumberProfitConfig.WOOD_ITEM_IDS
        elseif DecorLumberProfitConfig.WOOD_ITEM_ID then
            WOOD_IDS = { DecorLumberProfitConfig.WOOD_ITEM_ID }
        end
        if DecorLumberProfitConfig.WOOD_IDS_SET then
            WOOD_SET = DecorLumberProfitConfig.WOOD_IDS_SET
        elseif WOOD_IDS then
            WOOD_SET = {}
            for _, id in ipairs(WOOD_IDS) do WOOD_SET[id] = true end
        end
    end
    return WOOD_IDS, WOOD_SET
end

local function GetWoodID()
    local ids = GetWoodIDs()
    if ids and #ids > 0 then return ids[#ids] end
    return nil
end

local function GetWoodNames()
    if WOOD_NAMES then return WOOD_NAMES end
    WOOD_NAMES = (DecorLumberProfitConfig and DecorLumberProfitConfig.WOOD_NAMES) or {"Талассийская древесина"}
    return WOOD_NAMES
end

local function IsWoodID(itemID)
    if type(itemID) ~= "number" then return false end
    local _, set = GetWoodIDs()
    return set and set[itemID] or false
end

local function SafeCall(func, ...)
    if not func then return nil end
    local ok, result = pcall(func, ...)
    if ok then return result end
    return nil
end

-- Enum.ItemBind (14-й возврат C_Item.GetItemInfo):
-- 0=None, 1=OnAcquire(BoP), 2=OnEquip(BoE), 3=OnUse/"в отряде, на арене или в рейде", 4=Quest, 7=Account, 8=Warband, 9=Warband-until-equipped
-- На АХ выставляются только 0 (без привязки) и 2 (BoE до экипировки) — используем белый список.
-- 3 (привязка при присоединении к отряду/рейду) явно ИСКЛЮЧЁН.
local ITEM_BIND_SELLABLE = { [0]=true, [2]=true }
local _bindCache = {}
local _nameCache = {}
local _loadRequested = {}
-- tri-state: true=нельзя продать, false=можно, nil=данные о предмете ещё не загружены
local function OutputIsUnsellable(itemID)
    if type(itemID) ~= "number" then return false end
    if _bindCache[itemID] ~= nil then return _bindCache[itemID] end
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
        if not _loadRequested[itemID] and _G.Item and Item.CreateFromItemID then
            _loadRequested[itemID] = true
            local ok, it = pcall(Item.CreateFromItemID, itemID)
            if ok and it and it.ContinueOnItemLoad then
                pcall(function() it:ContinueOnItemLoad(function() end) end)
            end
        end
        return nil
    end
    local r = not ITEM_BIND_SELLABLE[bind]
    _bindCache[itemID] = r
    return r
end

-- Рецепты, ожидающие загрузки bindType: [spellID] = rec
Core._pendingBind = Core._pendingBind or {}

-- Сервер сообщил, что данных о предмете нет (success=false) — сбрасываем ждущие по нему рецепты
function Core:FailPendingForItem(itemID)
    for spellID, rec in pairs(self._pendingBind) do
        if rec.outputItemID == itemID then
            self._pendingBind[spellID] = nil
            if DecorLumberProfitDB and DecorLumberProfitDB.recipes then
                DecorLumberProfitDB.recipes[spellID] = nil
            end
        end
    end
end

-- Вызывается из UI по GET_ITEM_INFO_RECEIVED: возвращает рецепты, ставшие known-продаваемыми
function Core:ResolvePendingBind()
    local resolved = {}
    for spellID, rec in pairs(self._pendingBind) do
        local st = rec.outputItemID and OutputIsUnsellable(rec.outputItemID)
        if st == false then
            self._pendingBind[spellID] = nil
            table.insert(resolved, rec)
        elseif st == true then
            self._pendingBind[spellID] = nil
            if DecorLumberProfitDB and DecorLumberProfitDB.recipes then
                DecorLumberProfitDB.recipes[spellID] = nil
            end
        end
    end
    return resolved
end

-- Удаляет из списка рецепты с непродаваемой (привязанной) продукцией; unsell==nil (данные ещё грузятся) оставляет, ждём ResolvePendingBind
function Core:PruneUnsellable(list)
    if not list then return 0 end
    local removed = 0
    for i = #list, 1, -1 do
        local rec = list[i]
        if rec and rec.outputItemID and OutputIsUnsellable(rec.outputItemID) == true then
            table.remove(list, i)
            removed = removed + 1
            if rec.recipeSpellID and DecorLumberProfitDB and DecorLumberProfitDB.recipes then
                DecorLumberProfitDB.recipes[rec.recipeSpellID] = nil
            end
        end
    end
    return removed
end

local function GetItemName(itemID)
    if type(itemID) ~= "number" then return nil end
    if _nameCache[itemID] then return _nameCache[itemID] end
    local name = nil
    if C_Item and C_Item.GetItemInfo then
        local ok, n = pcall(C_Item.GetItemInfo, itemID)
        if ok then name = n end
    end
    if not name and _G.GetItemInfo then name = GetItemInfo(itemID) end
    if name then _nameCache[itemID] = name end
    return name
end

local function SchematicUsesWood(schematic, woodSetOrID)
    if not schematic or not schematic.reagentSlotSchematics then return nil end
    local woodQty = 0
    local woodSlot = nil
    local woodItemID = nil
    local set = nil
    if type(woodSetOrID) == "table" then
        set = woodSetOrID
    elseif type(woodSetOrID) == "number" then
        set = {[woodSetOrID]=true}
    else
        local _, s = GetWoodIDs()
        set = s
    end
    if not set then return nil end
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        if slot.reagents then
            for _, reagent in ipairs(slot.reagents) do
                if reagent.itemID and set[reagent.itemID] then
                    woodQty = slot.quantityRequired or 0
                    woodSlot = slot
                    woodItemID = reagent.itemID
                    break
                end
            end
        end
        if woodQty > 0 then break end
        if slot.variableQuantities then
            for _, vq in ipairs(slot.variableQuantities) do
                if vq.reagent and vq.reagent.itemID and set[vq.reagent.itemID] then
                    woodQty = vq.quantity or slot.quantityRequired or 0
                    woodSlot = slot
                    woodItemID = vq.reagent.itemID
                    break
                end
            end
        end
        if woodQty > 0 then break end
    end
    if woodQty > 0 then return woodQty, woodSlot, woodItemID end
    -- Fallback по имени (на случай если itemID поменялся или качество даёт другой ID)
    local woodNames = GetWoodNames()
    if woodNames and #woodNames>0 then
        local nameSet = {}
        for _, n in ipairs(woodNames) do nameSet[n:lower()] = true end
        for _, slot in ipairs(schematic.reagentSlotSchematics) do
            if slot.reagents then
                for _, reagent in ipairs(slot.reagents) do
                    if reagent.itemID then
                        local name = GetItemName(reagent.itemID)
                        if name and nameSet[name:lower()] then
                            woodQty = slot.quantityRequired or 0
                            woodSlot = slot
                            woodItemID = reagent.itemID
                            break
                        end
                    end
                end
            end
            if woodQty > 0 then break end
        end
        if woodQty > 0 then return woodQty, woodSlot, woodItemID end
    end
    return nil
end

local function ExtractReagents(schematic)
    local list = {}
    if not schematic or not schematic.reagentSlotSchematics then return list end
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        if not slot.hiddenInCraftingForm then
            local reagentItemID = nil
            local quantity = slot.quantityRequired or 0
            if slot.reagents and #slot.reagents > 0 then
                local reagent = slot.reagents[1]
                if reagent.itemID then
                    reagentItemID = reagent.itemID
                elseif reagent.currencyID then
                    reagentItemID = ("currency:%d"):format(reagent.currencyID)
                end
            end
            if reagentItemID and quantity > 0 then
                table.insert(list, {
                    itemID = reagentItemID,
                    quantity = quantity,
                    required = slot.required,
                    slotIndex = slot.dataSlotIndex or slot.slotIndex,
                    reagentType = slot.reagentType,
                    isWood = (type(reagentItemID)=="number" and IsWoodID(reagentItemID)),
                })
            end
        end
    end
    return list
end

-- GetRecipeInfo с защитой от отсутствия C_TradeSkillUI
local function GetRecipeInfoSafe(recipeSpellID)
    return SafeCall(C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo, recipeSpellID)
end

-- Схема рецепта на конкретном уровне (nil — без уровня)
local function GetSchematicAtLevel(recipeSpellID, level)
    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeSchematic then return nil end
    if level then
        return SafeCall(C_TradeSkillUI.GetRecipeSchematic, recipeSpellID, false, level)
    end
    return SafeCall(C_TradeSkillUI.GetRecipeSchematic, recipeSpellID, false)
end

function Core:GetRecipeData(recipeSpellID)
    if type(recipeSpellID) ~= "number" then return nil end
    local schematic = GetSchematicAtLevel(recipeSpellID)
    -- пробуем с уровнем рецепта если без него nil (Midnight: разные ранги)
    if not schematic then
        local info = GetRecipeInfoSafe(recipeSpellID)
        if info and info.unlockedRecipeLevel then
            schematic = GetSchematicAtLevel(recipeSpellID, info.unlockedRecipeLevel)
        end
    end
    if not schematic then return nil end
    local outputItemID = schematic.outputItemID
    if not outputItemID and C_TradeSkillUI and C_TradeSkillUI.GetRecipeOutputItemData then
        local outputInfo = SafeCall(C_TradeSkillUI.GetRecipeOutputItemData, recipeSpellID)
        if outputInfo and outputInfo.itemID then outputItemID = outputInfo.itemID end
        if not outputItemID then
            local infoTmp = GetRecipeInfoSafe(recipeSpellID)
            if infoTmp and infoTmp.unlockedRecipeLevel then
                local oi2 = SafeCall(C_TradeSkillUI.GetRecipeOutputItemData, recipeSpellID, nil, nil, infoTmp.unlockedRecipeLevel)
                if oi2 and oi2.itemID then outputItemID = oi2.itemID end
            end
        end
    end
    local _, woodSet = GetWoodIDs()
    local woodQty, woodSlot, woodItemID = SchematicUsesWood(schematic, woodSet)
    -- fallback: если древесина не нашлась, пробуем schematic с уровнем (другая итерация рецепта)
    if not woodQty then
        local infoTmp = GetRecipeInfoSafe(recipeSpellID)
        if infoTmp and infoTmp.unlockedRecipeLevel then
            local sch2 = GetSchematicAtLevel(recipeSpellID, infoTmp.unlockedRecipeLevel)
            if sch2 and sch2 ~= schematic then
                local wq2, ws2, wi2 = SchematicUsesWood(sch2, woodSet)
                if wq2 then woodQty, woodSlot, woodItemID, schematic = wq2, ws2, wi2, sch2 end
            end
        end
    end
    local info = GetRecipeInfoSafe(recipeSpellID)
    local profInfo = SafeCall(C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoByRecipeID, recipeSpellID)
    return {
        recipeSpellID = recipeSpellID,
        recipeID = schematic.recipeID,
        name = schematic.name or (info and info.name) or ("Spell "..recipeSpellID),
        profession = profInfo and profInfo.professionName or nil,
        outputItemID = outputItemID,
        outputMin = schematic.quantityMin or 1,
        outputMax = schematic.quantityMax or 1,
        outputQty = schematic.quantityMin or 1,
        icon = schematic.icon,
        learned = info and info.learned,
        available = info and info.craftable,
        schematic = schematic,
        reagents = ExtractReagents(schematic),
        woodQty = woodQty,
        woodItemID = woodItemID,
        woodName = woodItemID and GetItemName(woodItemID) or nil,
        woodSlot = woodSlot,
        recipeInfo = info,
    }
end

local function spellsToIDs(spells, seen, ids)
    if type(spells) ~= "table" then return 0 end
    local n = 0
    local function add(sid)
        if type(sid) == "number" and not seen[sid] then
            seen[sid] = true
            table.insert(ids, sid)
            n = n + 1
        end
    end
    -- массив? иначе dict-форма (некоторые билды возвращают {[spellID]=true})
    local isArray = false
    for _, v in ipairs(spells) do isArray = (type(v) == "number"); break end
    if isArray then
        for _, sid in ipairs(spells) do add(sid) end
    else
        for k, v in pairs(spells) do
            if type(k) == "number" then
                if type(v) == "number" then add(v) else add(k) end
            end
        end
    end
    return n
end

local function TryGetAllRecipeSpellIDs()
    local ids = {}
    local seen = {}
    local function addSpells(spells) return spellsToIDs(spells, seen, ids) end
    -- Основной источник в Midnight: все рецепты текущего окна (выученные и нет)
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
        local all = SafeCall(C_TradeSkillUI.GetAllRecipeIDs)
        if all then addSpells(all) end
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetAllProfessionTradeSkillLines then
        local skillLines = SafeCall(C_TradeSkillUI.GetAllProfessionTradeSkillLines)
        if (not skillLines or #skillLines == 0) and C_TradeSkillUI.GetChildProfessionInfos then
            local childInfos = SafeCall(C_TradeSkillUI.GetChildProfessionInfos)
            if childInfos then
                skillLines = skillLines or {}
                for _, info in ipairs(childInfos) do
                    local sid = info.skillLineID or info.skillLine or info.professionID
                    if type(sid) == "number" then table.insert(skillLines, sid) end
                end
            end
        end
        if (not skillLines or #skillLines == 0) and C_TradeSkillUI.GetBaseProfessionInfo then
            local baseInfo = SafeCall(C_TradeSkillUI.GetBaseProfessionInfo)
            if baseInfo and baseInfo.skillLineID then
                skillLines = { baseInfo.skillLineID }
            end
        end
        if skillLines then
            for _, skillLineID in ipairs(skillLines) do
                local profInfo = SafeCall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
                if C_TradeSkillUI.GetProfessionSpells then
                    local pid, profEnum
                    if profInfo then
                        pid = profInfo.professionID
                        profEnum = profInfo.profession
                    end
                    local tried = {}
                    local function tryCall(a, b)
                        local key = tostring(a)..":"..tostring(b)
                        if tried[key] then return nil end
                        tried[key]=true
                        if a == nil then return nil end
                        if b ~= nil then
                            return SafeCall(C_TradeSkillUI.GetProfessionSpells, a, b)
                        else
                            return SafeCall(C_TradeSkillUI.GetProfessionSpells, a)
                        end
                    end
                    local spells
                    spells = tryCall(pid, skillLineID)
                    if not spells or #spells == 0 then spells = tryCall(pid, nil) end
                    if (not spells or #spells == 0) and profEnum then
                        spells = tryCall(profEnum, skillLineID)
                        if not spells or #spells == 0 then spells = tryCall(profEnum, nil) end
                    end
                    if (not spells or #spells == 0) then spells = tryCall(skillLineID, nil) end
                    if spells then addSpells(spells) end
                end
            end
        end
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionSpells then
        -- Перебираем реальные professionID из известных skillLine, а также частые ID (164,171,182 и т.д.)
        local commonPIDs = {164,165,171,182,186,197,202,333,393,755,773,794,129,185,356,762,165,197}
        for _, pid in ipairs(commonPIDs) do
            local spells = SafeCall(C_TradeSkillUI.GetProfessionSpells, pid)
            if spells and #spells > 0 then addSpells(spells) end
        end
        -- Расширенный перебор для Midnight (skillLine 2900+)
        for pid = 2700, 3100 do
            local spells = SafeCall(C_TradeSkillUI.GetProfessionSpells, pid)
            if spells and #spells > 0 then addSpells(spells) end
        end
        -- Последний шанс: brute 1..100 (покроет старые)
        for pid = 1, 100 do
            local spells = SafeCall(C_TradeSkillUI.GetProfessionSpells, pid)
            if spells and #spells > 0 then addSpells(spells) end
        end
    end
    if DecorLumberProfitDB and DecorLumberProfitDB.knownRecipes then
        for rid,_ in pairs(DecorLumberProfitDB.knownRecipes) do
            if not seen[rid] then
                seen[rid]=true
                table.insert(ids, rid)
            end
        end
    end
    if DecorLumberProfitCharDB and DecorLumberProfitCharDB.seenRecipes then
        for rid,_ in pairs(DecorLumberProfitCharDB.seenRecipes) do
            if not seen[rid] then seen[rid]=true; table.insert(ids, rid) end
        end
    end
    return ids
end

-- Активное окно профессии
local _activeSkillLineID = nil

function Core:SetActiveSkillLineID(skillLineID)
    if type(skillLineID) == "number" and skillLineID ~= 0 then
        _activeSkillLineID = skillLineID
    end
end

function Core:GetActiveSkillLineID()
    return _activeSkillLineID
end

local function GetActiveSkillLineIDs()
    local ids = {}
    local seen = {}
    local debug = {}
    local function add(id, src)
        if type(id)=="number" and id~=0 and not seen[id] then
            seen[id]=true
            table.insert(ids,id)
            table.insert(debug, string.format("%s:%d", src or "?", id))
        end
    end
    if _activeSkillLineID then add(_activeSkillLineID, "_active") end
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionChildSkillLineID then
        local sid = SafeCall(C_TradeSkillUI.GetProfessionChildSkillLineID)
        if type(sid)=="number" then add(sid, "ChildSkillLineID") end
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
        local info = SafeCall(C_TradeSkillUI.GetBaseProfessionInfo)
        if info and info.profession then
            local sid = SafeCall(C_TradeSkillUI.GetProfessionSkillLineID, info.profession)
            if type(sid)=="number" then add(sid, "Base") end
        end
        if info and info.professionID then
            -- пробуем напрямую skillLine из professionID через GetAllProfessionTradeSkillLines
            -- (некоторые билды Midnight хранят professionID == skillLineID)
            add(info.professionID, "BasePID")
        end
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetChildProfessionInfo then
        local cinfo = SafeCall(C_TradeSkillUI.GetChildProfessionInfo)
        if cinfo and cinfo.profession then
            local sid = SafeCall(C_TradeSkillUI.GetProfessionSkillLineID, cinfo.profession)
            if type(sid)=="number" then add(sid, "Child") end
        end
    end
    -- fallback: если всё пусто, но окно профессии видимо — считаем видимым ProfessionsFrame
    if #ids==0 and _G.ProfessionsFrame and _G.ProfessionsFrame:IsVisible() then
        if C_TradeSkillUI.GetAllProfessionTradeSkillLines then
            local all = SafeCall(C_TradeSkillUI.GetAllProfessionTradeSkillLines)
            if all and #all==1 then add(all[1], "AllSingle") end
        end
    end
    -- debug сохраняем в глобал для /dump
    DecorLumberProfitCore._lastActiveDebug = debug
    return ids
end

local TryGetActiveRecipeSpellIDs

TryGetActiveRecipeSpellIDs = function()
    if not C_TradeSkillUI then return {} end
    -- Primary (Midnight-safe): список ВСЕХ рецептов текущего окна профессии
    if C_TradeSkillUI.GetAllRecipeIDs then
        local ids = {}
        local seen = {}
        local all = SafeCall(C_TradeSkillUI.GetAllRecipeIDs)
        if all and spellsToIDs(all, seen, ids) > 0 then return ids end
    end
    if not C_TradeSkillUI.GetProfessionSpells then return {} end
    local activeLines = GetActiveSkillLineIDs()
    if #activeLines == 0 then return {} end
    local ids = {}
    local seen = {}
    local function addSpells(spells) spellsToIDs(spells, seen, ids) end
    for _, skillLineID in ipairs(activeLines) do
        local profInfo = SafeCall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
        local pid, profEnum
        if profInfo then
            pid = profInfo.professionID
            profEnum = profInfo.profession
        end
        local function tryCall(a,b)
            if a==nil then return nil end
            if b~=nil then
                return SafeCall(C_TradeSkillUI.GetProfessionSpells, a, b)
            else
                return SafeCall(C_TradeSkillUI.GetProfessionSpells, a)
            end
        end
        local spells
        spells = tryCall(pid, skillLineID)
        if spells then addSpells(spells) end
        if not spells or #spells == 0 then
            spells = tryCall(pid, nil)
            if spells then addSpells(spells) end
        end
        if profEnum and (#ids==0) then
            spells = tryCall(profEnum, skillLineID)
            if spells then addSpells(spells) end
            if not spells or #spells == 0 then
                spells = tryCall(profEnum, nil)
                if spells then addSpells(spells) end
            end
        end
        if #ids==0 then
            spells = tryCall(skillLineID, nil)
            if spells then addSpells(spells) end
        end
    end
    if #ids==0 and C_TradeSkillUI.IsRecipeInSkillLine then
        local commonPIDs = {164,165,171,182,186,197,202,333,393,755,773,794,129,185,356,762}
        for _, pid in ipairs(commonPIDs) do
            local spells = SafeCall(C_TradeSkillUI.GetProfessionSpells, pid)
            if spells then
                for _, sid in ipairs(spells) do
                    if not seen[sid] then
                        for _, activeSID in ipairs(activeLines) do
                            local ok = SafeCall(C_TradeSkillUI.IsRecipeInSkillLine, sid, activeSID)
                            if ok then seen[sid]=true; table.insert(ids,sid); break end
                        end
                    end
                end
            end
        end
        for pid=2700,3100 do
            local spells = SafeCall(C_TradeSkillUI.GetProfessionSpells, pid)
            if spells then
                for _, sid in ipairs(spells) do
                    if not seen[sid] then
                        for _, activeSID in ipairs(activeLines) do
                            local ok = SafeCall(C_TradeSkillUI.IsRecipeInSkillLine, sid, activeSID)
                            if ok then seen[sid]=true; table.insert(ids,sid); break end
                        end
                    end
                end
            end
        end
    end
    -- Fallback 2: если всё ещё пусто — фильтруем ВСЕ известные заклинания (TryGetAll) по активному skillLine
    if #ids==0 then
        local all = TryGetAllRecipeSpellIDs()
        if all and #all>0 and C_TradeSkillUI.IsRecipeInSkillLine then
            for _, sid in ipairs(all) do
                if not seen[sid] then
                    for _, activeSID in ipairs(activeLines) do
                        local ok = SafeCall(C_TradeSkillUI.IsRecipeInSkillLine, sid, activeSID)
                        if ok then seen[sid]=true; table.insert(ids,sid); break end
                    end
                    -- также проверяем IsRecipeInBaseSkillLine как fallback
                    if not seen[sid] and C_TradeSkillUI.IsRecipeInBaseSkillLine then
                        local ok2 = SafeCall(C_TradeSkillUI.IsRecipeInBaseSkillLine, sid)
                        if ok2 then
                            -- проверяем, что рецепт принадлежит одному из активных линий через ProfessionInfo
                            local rInfo = SafeCall(C_TradeSkillUI.GetProfessionInfoByRecipeID, sid)
                            if rInfo then
                                for _, activeSID in ipairs(activeLines) do
                                    local aInfo = SafeCall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, activeSID)
                                    if aInfo and rInfo.professionID==aInfo.professionID then
                                        seen[sid]=true; table.insert(ids,sid); break
                                    end
                                end
                            end
                        end
                    end
                end
            end
        elseif all and #all>0 and #activeLines>0 then
            -- API IsRecipeInSkillLine недоступен — отдаём всё из TryGetAll, фильтр по древесине потом отсеет
            for _, sid in ipairs(all) do
                if not seen[sid] then seen[sid]=true; table.insert(ids,sid) end
            end
        end
    end
    -- Fallback 3: чтение из UI ProfessionsFrame (работает даже когда GetProfessionSpells сломан в Midnight)
    if #ids==0 and _G.ProfessionsFrame and _G.ProfessionsFrame:IsVisible() then
        local function addFromFrame()
            local pf = _G.ProfessionsFrame
            local cp = pf.CraftingPage
            local sb = (cp and (cp.RecipeScrollBox or (cp.RecipeList and cp.RecipeList.ScrollBox)))
                or (pf.RecipeList and pf.RecipeList.ScrollBox)
            if not sb or not sb.GetDataProvider then return end
            local ok, dp = pcall(sb.GetDataProvider, sb)
            if not ok or not dp then return end
            -- DataProviderMixin: GetNumElements()/GetElementData(i)
            local count = nil
            if dp.GetNumElements then
                local cOk, c = pcall(dp.GetNumElements, dp)
                if cOk and type(c)=="number" then count = c end
            end
            if not count and dp.GetSize then
                local cOk, c = pcall(dp.GetSize, dp)
                if cOk and type(c)=="number" then count = c end
            end
            if count and count > 0 then
                for i=1, math.min(count, 2000) do
                    local data = nil
                    if dp.GetElementData then
                        local dOk, d = pcall(dp.GetElementData, dp, i)
                        if dOk then data = d end
                    end
                    if not data and dp.GetElement then
                        local dOk, d = pcall(dp.GetElement, dp, i)
                        if dOk then data = d end
                    end
                    if not data and dp.GetEntryAt then
                        local dOk, d = pcall(dp.GetEntryAt, dp, i)
                        if dOk then data = d end
                    end
                    local rid = data and (data.recipeID or data.recipeSpellID or data.spellID
                        or (data.recipeInfo and (data.recipeInfo.recipeID or data.recipeInfo.recipeSpellID)))
                    if type(rid)=="number" and not seen[rid] then
                        seen[rid]=true; table.insert(ids, rid)
                    end
                end
            end
            if #ids > 0 then return end
            -- перебор кнопок как последний шанс
            local target = sb.GetTarget and SafeCall(sb.GetTarget, sb) or sb.ScrollTarget
            if target and target.GetChildren then
                for _, btn in ipairs({target:GetChildren()}) do
                    local rid = btn.recipeID or btn.spellID or (btn.GetRecipeID and SafeCall(btn.GetRecipeID, btn))
                        or (btn.elementData and btn.elementData.recipeID)
                    if type(rid)=="number" and not seen[rid] then
                        seen[rid]=true; table.insert(ids, rid)
                    end
                end
            end
        end
        pcall(addFromFrame)
    end
    return ids
end

-- Диагностика активного окна: доступна из /dump DecorLumberProfitCore.DebugActive()
local function CountTable(t)
    if type(t) ~= "table" then return 0 end
    local c = 0
    for _ in pairs(t) do c = c + 1 end
    return c
end

local function FirstN(t, n)
    local out = {}
    if type(t) == "table" then
        for i = 1, n do out[i] = t[i] end
    end
    return out
end

function Core:DebugActive()
    local lines = GetActiveSkillLineIDs()
    local spellsInfo = {}
    for _, sid in ipairs(lines) do
        local info = SafeCall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, sid)
        table.insert(spellsInfo, { skillLineID=sid, info=info })
    end
    local cand = TryGetActiveRecipeSpellIDs()
    local all = TryGetAllRecipeSpellIDs()
    -- сырые вызовы API для диагностики
    local rawAllLines = SafeCall(C_TradeSkillUI.GetAllProfessionTradeSkillLines)
    local rawChildInfos = SafeCall(C_TradeSkillUI.GetChildProfessionInfos)
    local rawBaseInfo = SafeCall(C_TradeSkillUI.GetBaseProfessionInfo)
    local rawChildInfo = SafeCall(C_TradeSkillUI.GetChildProfessionInfo)
    local rawChildSID = SafeCall(C_TradeSkillUI.GetProfessionChildSkillLineID)
    local rawAllRecipeIDs = SafeCall(C_TradeSkillUI.GetAllRecipeIDs)
    local isProfFrameVisible = _G.ProfessionsFrame and _G.ProfessionsFrame:IsVisible() or false
    -- прямые пробы GetProfessionSpells
    local probes = {}
    local function probe(pid, sid)
        local a = SafeCall(C_TradeSkillUI.GetProfessionSpells, pid, sid)
        local b = SafeCall(C_TradeSkillUI.GetProfessionSpells, pid)
        return { pid=pid, sid=sid, withSID=CountTable(a), withoutSID=CountTable(b) }
    end
    for _, sid in ipairs(lines) do
        local info = SafeCall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, sid)
        if info then
            table.insert(probes, probe(info.professionID, sid))
            if info.profession then table.insert(probes, probe(info.profession, sid)) end
            table.insert(probes, probe(sid, sid))
            table.insert(probes, probe(sid, nil))
        end
    end
    for _, pid in ipairs({164,171,182,186,197,202,333,393,755,2907,2904}) do
        table.insert(probes, probe(pid, nil))
    end
    return {
        activeSkillLines = lines,
        spellsInfo = spellsInfo,
        debugSources = self._lastActiveDebug,
        _activeSkillLineID = _activeSkillLineID,
        candidateCount = cand and #cand or 0,
        firstCandidates = FirstN(cand, 5),
        allCount = all and #all or 0,
        firstAll = FirstN(all, 3),
        woodIDs = select(1, GetWoodIDs()),
        rawAllLines = rawAllLines,
        rawChildInfos = rawChildInfos,
        rawBaseInfo = rawBaseInfo,
        rawChildInfo = rawChildInfo,
        rawChildSID = rawChildSID,
        rawAllRecipeIDsCount = CountTable(rawAllRecipeIDs),
        rawAllRecipeIDsFirst = FirstN(rawAllRecipeIDs, 3),
        isProfFrameVisible = isProfFrameVisible,
        probes = probes,
        knowRecipesCount = DecorLumberProfitDB and DecorLumberProfitDB.knownRecipes and CountTable(DecorLumberProfitDB.knownRecipes) or 0,
    }
end

-- Прямой тест: /dump DecorLumberProfitCore.DebugSpell(123456)
function Core:DebugSpell(spellID)
    local data = self:GetRecipeData(spellID)
    if not data then return { err="no schematic", spellID=spellID } end
    return {
        spellID=spellID,
        name=data.name,
        outputItemID=data.outputItemID,
        woodQty=data.woodQty,
        woodItemID=data.woodItemID,
        reagents=data.reagents,
        schematic=data.schematic and #data.schematic.reagentSlotSchematics or 0,
        info=data.recipeInfo,
    }
end

function Core:FindWoodRecipesInActiveWindow()
    local ids, set = GetWoodIDs()
    if not ids or #ids==0 then return {}, "WOOD_ID_NOT_SET" end
    local candidates = TryGetActiveRecipeSpellIDs()
    local activeLines = GetActiveSkillLineIDs()
    if #candidates==0 then
        if #activeLines==0 then
            return {}, "NO_ACTIVE_WINDOW", { scanned=0, found=0, activeSkillLines=activeLines }
        else
            return {}, "NO_RECIPES_IN_ACTIVE_WINDOW", { scanned=0, found=0, activeSkillLines=activeLines, candidateCount=0 }
        end
    end
    local results = {}
    local scanned = 0
    local noOutput = 0
    local noWood = 0
    local bindSkipped = 0
    local bindPending = 0
    for _, spellID in ipairs(candidates) do
        scanned = scanned + 1
        local data = self:GetRecipeData(spellID)
        if data and data.outputItemID and data.woodQty then
            local unsell = OutputIsUnsellable(data.outputItemID)
            if unsell == true then
                bindSkipped = bindSkipped + 1
            elseif unsell == nil then
                self._pendingBind[spellID] = data
                bindPending = bindPending + 1
            else
                if data.recipeInfo and data.recipeInfo.learned==false then data.isUnavailable=true end
                table.insert(results, data)
                self:RememberRecipe(spellID, data.recipeInfo and data.recipeInfo.unlockedRecipeLevel or 1)
            end
        else
            if data and not data.outputItemID then
                noOutput = noOutput + 1
            elseif data and not data.woodQty then
                noWood = noWood + 1
            end
        end
        if #results>=500 then break end
    end
    -- Если в активном окне есть кандидаты, но ни один не содержит древесину — вернём спец. ошибку с диагностикой
    if #results==0 and #candidates>0 then
        return {}, "NO_WOOD_IN_ACTIVE_CANDIDATES", { scanned=scanned, found=0, noOutput=noOutput, noWood=noWood, bindSkipped=bindSkipped, bindPending=bindPending, candidateCount=#candidates, activeSkillLines=activeLines }
    end
    table.sort(results, function(a,b) return (a.name or "")<(b.name or "") end)
    local meta = { scanned=scanned, found=#results, noOutput=noOutput, noWood=noWood, bindSkipped=bindSkipped, bindPending=bindPending, candidateCount=#candidates, activeSkillLines=activeLines }
    return results, nil, meta
end

function Core:ScanAndRememberCurrentProfession()
    if not C_TradeSkillUI or not C_TradeSkillUI.GetProfessionSpells then return 0 end
    local added = 0
    local candidates = TryGetAllRecipeSpellIDs()
    for _, sid in ipairs(candidates) do
        local info = SafeCall(C_TradeSkillUI.GetRecipeInfo, sid)
        if info and info.learned then
            local before = DecorLumberProfitDB and DecorLumberProfitDB.knownRecipes and DecorLumberProfitDB.knownRecipes[sid]
            self:RememberRecipe(sid, info.unlockedRecipeLevel or 1)
            if not before then added = added + 1 end
        end
    end
    return added
end

function Core:FindWoodRecipes()
    local ids, set = GetWoodIDs()
    if not ids or #ids == 0 then
        return {}, "WOOD_ID_NOT_SET"
    end
    local candidates = TryGetAllRecipeSpellIDs()
    local results = {}
    local scanned = 0
    local noOutput = 0
    local notLearned = 0
    local bindSkipped = 0
    local bindPending = 0
    if #candidates == 0 then
        return {}, "NO_RECIPES_ENUMERATED"
    end
    for _, spellID in ipairs(candidates) do
        scanned = scanned + 1
        local data = self:GetRecipeData(spellID)
        if data then
            local unsell = data.outputItemID and OutputIsUnsellable(data.outputItemID) or nil
            if not data.outputItemID then
                noOutput = noOutput + 1
            elseif unsell == true then
                bindSkipped = bindSkipped + 1
            elseif unsell == nil then
                self._pendingBind[spellID] = data
                bindPending = bindPending + 1
            elseif not data.woodQty then
                -- рецепт без древесины — пропускаем
            else
                if data.recipeInfo and data.recipeInfo.learned == false then
                    notLearned = notLearned + 1
                    data.isUnavailable = true
                end
                table.insert(results, data)
                if #results >= 500 then break end
            end
        end
        if scanned % 200 == 0 and coroutine.running() then coroutine.yield() end
    end
    table.sort(results, function(a,b) return (a.name or "") < (b.name or "") end)
    local meta = {
        scanned = scanned,
        found = #results,
        noOutput = noOutput,
        notLearned = notLearned,
        bindSkipped = bindSkipped,
        bindPending = bindPending,
    }
    return results, nil, meta
end

function Core:CalculateRecipeEconomy(recipeData, auctionPrices)
    auctionPrices = auctionPrices or {}
    local woodQty = recipeData.woodQty or 0
    local outputQty = recipeData.outputQty or recipeData.outputMin or 1
    if outputQty <=0 then outputQty = 1 end
    local otherCost = 0
    local totalCost = 0
    local woodCost = 0
    local missingReagents = {}
    local hasUnknownPrice = false
    for _, r in ipairs(recipeData.reagents) do
        local itemID = r.itemID
        if type(itemID) == "string" and itemID:find("^currency:") then
            hasUnknownPrice = true
            table.insert(missingReagents, itemID)
        else
            local unitPrice = auctionPrices[itemID]
            if unitPrice == nil then
                hasUnknownPrice = true
                table.insert(missingReagents, itemID)
                unitPrice = 0
            end
            local cost = unitPrice * r.quantity
            totalCost = totalCost + cost
            if r.isWood then
                woodCost = woodCost + cost
            else
                otherCost = otherCost + cost
            end
        end
    end
    local outputItemID = recipeData.outputItemID
    local outputUnitPrice = outputItemID and auctionPrices[outputItemID] or nil
    local outputTotalPrice = nil
    if outputUnitPrice then
        outputTotalPrice = outputUnitPrice * outputQty
    else
        hasUnknownPrice = true
    end
    local woodItemID = recipeData.woodItemID
    local woodPrice = nil
    if woodItemID and auctionPrices[woodItemID] then
        woodPrice = auctionPrices[woodItemID]
    elseif woodQty > 0 then
        local ids, _ = GetWoodIDs()
        for _, wid in ipairs(ids) do
            if auctionPrices[wid] then woodPrice = auctionPrices[wid]; break end
        end
    end
    local maxWoodPrice = nil
    local profit = nil
    if outputTotalPrice and woodQty > 0 then
        maxWoodPrice = (outputTotalPrice - otherCost) / woodQty
        profit = outputTotalPrice - totalCost
    end
    return {
        outputQty = outputQty,
        outputUnitPrice = outputUnitPrice,
        outputTotalPrice = outputTotalPrice,
        otherCost = otherCost,
        totalCost = totalCost,
        costNoWood = totalCost - woodCost,
        woodCost = woodCost,
        woodQty = woodQty,
        woodItemID = woodItemID,
        woodPrice = woodPrice,
        maxWoodPrice = maxWoodPrice,
        profit = profit,
        profitPerOutput = profit and (profit / outputQty) or nil,
        hasUnknownPrice = hasUnknownPrice,
        missingReagents = missingReagents,
        status = (function()
            if outputUnitPrice == nil then return "NO_OUTPUT_PRICE" end
            if hasUnknownPrice and totalCost==0 then return "NO_REAGENT_PRICES" end
            if maxWoodPrice == nil then return "UNKNOWN" end
            if profit and profit > 0 then return "PROFITABLE" end
            if profit and profit == 0 then return "BREAKEVEN" end
            return "UNPROFITABLE"
        end)(),
    }
end

function Core:RememberRecipe(recipeID, recipeLevel)
    if not recipeID then return end
    DecorLumberProfitDB = DecorLumberProfitDB or {}
    DecorLumberProfitDB.knownRecipes = DecorLumberProfitDB.knownRecipes or {}
    DecorLumberProfitDB.knownRecipes[recipeID] = { level = recipeLevel, time = time() }
    DecorLumberProfitCharDB = DecorLumberProfitCharDB or {}
    DecorLumberProfitCharDB.seenRecipes = DecorLumberProfitCharDB.seenRecipes or {}
    DecorLumberProfitCharDB.seenRecipes[recipeID] = true
end

-- ==== Персистентность: общая (account-wide) база рецептов между персонажами/сессиями ====
local function ensureDB()
    DecorLumberProfitDB = DecorLumberProfitDB or {}
    DecorLumberProfitDB.recipes = DecorLumberProfitDB.recipes or {}
    return DecorLumberProfitDB.recipes
end

function Core:SerializeRecipe(rec)
    if not rec or not rec.recipeSpellID then return nil end
    local reagents = {}
    for i, r in ipairs(rec.reagents or {}) do
        reagents[i] = { itemID = r.itemID, quantity = r.quantity, required = r.required,
                        slotIndex = r.slotIndex, reagentType = r.reagentType, isWood = r.isWood }
    end
    return {
        recipeSpellID = rec.recipeSpellID,
        name = rec.name,
        profession = rec.profession,
        outputItemID = rec.outputItemID,
        outputQty = rec.outputQty, outputMin = rec.outputMin, outputMax = rec.outputMax,
        icon = rec.icon,
        woodQty = rec.woodQty, woodItemID = rec.woodItemID, woodName = rec.woodName,
        reagents = reagents,
        learned = rec.learned,
    }
end

-- Сохраняет snapshot рецепта в общую базу (не перетирая learned-флаг других персонажей)
function Core:SaveRecipe(rec)
    if not rec or not rec.recipeSpellID then return end
    local db = ensureDB()
    local ser = self:SerializeRecipe(rec)
    local existing = db[rec.recipeSpellID]
    if existing then
        ser.learnedBy = existing.learnedBy or {}
        -- обновляем только если пришли более полные данные (есть reagents)
        if not (ser.reagents and #ser.reagents>0) and existing.reagents and #existing.reagents>0 then
            ser.reagents = existing.reagents
        end
    else
        ser.learnedBy = {}
    end
    db[rec.recipeSpellID] = ser
    return db[rec.recipeSpellID]
end

-- Отмечает, что рецепт изучен текущим персонажем
function Core:MarkLearnedBy(spellID)
    if not spellID then return end
    local db = ensureDB()
    local ser = db[spellID]
    if not ser then return end
    ser.learnedBy = ser.learnedBy or {}
    ser.learnedBy[_G.UnitName and UnitName("player") or "player"] = true
    ser.learned = true
end

-- Загружает все сохранённые рецепты (общие для аккаунта), ре-валидируя привязку выхода
function Core:LoadSavedRecipes()
    local out = {}
    if not (DecorLumberProfitDB and DecorLumberProfitDB.recipes) then return out end
    for spellID, ser in pairs(DecorLumberProfitDB.recipes) do
        if ser and ser.recipeSpellID then
            local rec = {}
            for k,v in pairs(ser) do rec[k] = v end
            local unsell = nil
            if rec.outputItemID then unsell = OutputIsUnsellable(rec.outputItemID) end
            if unsell == true then
                DecorLumberProfitDB.recipes[spellID] = nil -- чистим базу от непродаваемых
            elseif unsell == nil and rec.outputItemID then
                rec.isUnavailable = (rec.learned == false)
                self._pendingBind[spellID] = rec -- bind неизвестен — ждём догрузки, в таблицу не пускаем
            else
                rec.isUnavailable = (rec.learned == false)
                table.insert(out, rec)
            end
        end
    end
    return out
end

function Core:GetSavedRecipe(spellID)
    if not (DecorLumberProfitDB and DecorLumberProfitDB.recipes) then return nil end
    return DecorLumberProfitDB.recipes[spellID]
end

function Core:ClearSavedRecipes()
    if DecorLumberProfitDB then DecorLumberProfitDB.recipes = {} end
end

function Core:SavedRecipeCount()
    local c=0
    if DecorLumberProfitDB and DecorLumberProfitDB.recipes then
        for _ in pairs(DecorLumberProfitDB.recipes) do c=c+1 end
    end
    return c
end

-- Пересчитывает learned для загруженных рецептов по живому API (для текущего персонажа)
function Core:RefreshLearnedFlags(list)
    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeInfo then return end
    local player = (_G.UnitName and UnitName("player")) or "player"
    for _, rec in ipairs(list) do
        if rec.recipeSpellID then
            local info = SafeCall(C_TradeSkillUI.GetRecipeInfo, rec.recipeSpellID)
            if info then
                rec.learned = info.learned
                rec.isUnavailable = (info.learned == false)
                if info.learned then self:MarkLearnedBy(rec.recipeSpellID) end
                local ser = self:GetSavedRecipe(rec.recipeSpellID)
                if ser then
                    ser.learnedBy = ser.learnedBy or {}
                    if info.learned then ser.learnedBy[player] = true end
                end
            end
        end
    end
end

function Core:IsWoodItem(itemID) return IsWoodID(itemID) end
function Core:GetWoodIDs() return GetWoodIDs() end
function Core:GetWoodID() return GetWoodID() end
function Core:GetItemName(itemID) return GetItemName(itemID) end
function Core:IsOutputUnsellable(itemID) return OutputIsUnsellable(itemID) end
