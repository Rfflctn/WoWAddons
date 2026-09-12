-- Services/Recipes.lua | DecorLumberProfit | Retail 12.1.0
-- Поиск рецептов с древесиной (Этап 4): перечисление, схемы, unified Scan.
-- Соглашение: все функции — через точку (без self). Core держит тонкие :-врапперы.
-- WoW Lua 5.1: no goto, no //, no bitwise ops. No WoW calls at top level.

DecorLumberProfitRecipes = {}
local Recipes = DecorLumberProfitRecipes

local SafeCall = DecorLumberProfit.SafeCall

-- ==== Wood-доступ (Wood.lua с фолбэком на Config) ====

local function GetWoodIDs()
    local W = _G.DecorLumberProfitWood
    if W and W.IDs then return W.IDs() end
    local cfg = _G.DecorLumberProfitConfig
    if cfg and cfg.WOOD_ITEM_IDS and #cfg.WOOD_ITEM_IDS > 0 then
        return cfg.WOOD_ITEM_IDS, cfg.WOOD_IDS_SET
    end
    return nil, nil
end

local function GetWoodNames()
    local W = _G.DecorLumberProfitWood
    if W and W.Names then return W.Names() end
    local cfg = _G.DecorLumberProfitConfig
    if cfg and cfg.WOOD_NAMES then return cfg.WOOD_NAMES end
    return { "Талассийская древесина" }
end

local function IsWoodID(itemID)
    if type(itemID) ~= "number" then return false end
    local _, set = GetWoodIDs()
    return set and set[itemID] or false
end

local function GetItemName(itemID)
    local M = _G.DecorLumberProfitItemInfo
    if M and M.GetName then return M.GetName(itemID) end
    return nil
end

-- ==== Флаги сканирования (Config.SCAN с дефолтами) ====

function Recipes.BruteForceEnabled()
    local cfg = _G.DecorLumberProfitConfig
    if cfg and cfg.SCAN and cfg.SCAN.ENABLE_BRUTEFORCE ~= nil then
        return cfg.SCAN.ENABLE_BRUTEFORCE and true or false
    end
    return true
end

function Recipes.MaxResults()
    local cfg = _G.DecorLumberProfitConfig
    if cfg and cfg.SCAN and type(cfg.SCAN.MAX_RESULTS) == "number" then
        -- кламп как в /dlp debug set maxscan (защита от ручной правки SV)
        return math.max(50, math.min(5000, math.floor(cfg.SCAN.MAX_RESULTS)))
    end
    return 500
end

function Recipes.GetWoodIDs() return GetWoodIDs() end
function Recipes.IsWoodItem(itemID) return IsWoodID(itemID) end

-- ==== Нормализация профессий: подвиды дополнений -> базовая профессия ====
-- Blizzard отдаёт вариант ("Зандаларское кузнечное дело", "Khaz Algar Blacksmithing")
-- в ProfessionInfo.professionName, а базу — в parentProfessionName.
-- parent — истина (все локали сразу); подстрока — фолбэк для старых сейвов/клиентов без parent.
local PROF_BASE_EN = {
    "Blacksmithing", "Leatherworking", "Alchemy", "Herbalism", "Cooking",
    "Mining", "Tailoring", "Engineering", "Enchanting", "Fishing",
    "Skinning", "Jewelcrafting", "Inscription", "Archaeology", "First Aid",
    "Carpentry",
}

local PROF_BASE_RU = {
    "Кузнечное дело", "Кожевничество", "Алхимия", "Травничество", "Кулинария",
    "Горное дело", "Портняжное дело", "Инженерия", "Наложение чар", "Рыбалка",
    "Снятие шкур", "Ювелирное дело", "Начертание", "Археология", "Первая помощь",
}

-- Нижний регистр первой буквы без UTF-8 либы (WoW Lua 5.1): кириллица — картой, латиница — :lower().
-- Нужен для вариантов вида "Зандаларское кузнечное дело" (база "Кузнечное дело" со строчной "к").
local CYR_LOWER_FIRST = {
    ["А"] = "а", ["Б"] = "б", ["В"] = "в", ["Г"] = "г", ["Д"] = "д",
    ["Е"] = "е", ["Ё"] = "ё", ["Ж"] = "ж", ["З"] = "з", ["И"] = "и",
    ["Й"] = "й", ["К"] = "к", ["Л"] = "л", ["М"] = "м", ["Н"] = "н",
    ["О"] = "о", ["П"] = "п", ["Р"] = "р", ["С"] = "с", ["Т"] = "т",
    ["У"] = "у", ["Ф"] = "ф", ["Х"] = "х", ["Ц"] = "ц", ["Ч"] = "ч",
    ["Ш"] = "ш", ["Щ"] = "щ", ["Ъ"] = "ъ", ["Ы"] = "ы", ["Ь"] = "ь",
    ["Э"] = "э", ["Ю"] = "ю", ["Я"] = "я",
}

local function LowerFirst(s)
    if type(s) ~= "string" or s == "" then return s end
    local b1 = s:byte(1)
    local first, rest
    if b1 and b1 >= 128 then
        first, rest = s:sub(1, 2), s:sub(3) -- кириллица в UTF-8 — 2 байта
    else
        first, rest = s:sub(1, 1), s:sub(2)
    end
    local low = CYR_LOWER_FIRST[first] or first:lower()
    return low .. (rest or "")
end

local function Trim(s)
    if type(s) ~= "string" then return s end
    return s:match("^%s*(.-)%s*$")
end

-- "Зандаларское кузнечное дело" -> "Кузнечное дело", "Khaz Algar Blacksmithing" -> "Blacksmithing".
-- Неизвестное имя возвращается как есть (trim), nil — nil.
function Recipes.NormalizeProfessionName(name)
    if name == nil then return nil end
    if type(name) ~= "string" then return name end
    local t = Trim(name)
    if t == "" then return t end
    local best, bestLen = nil, 0
    local lower = t:lower() -- для en (ASCII) корректен; кириллицу не портит
    for _, base in ipairs(PROF_BASE_EN) do
        local bl = base:lower()
        if lower:find(bl, 1, true) and #base > bestLen then
            best, bestLen = base, #base
        end
    end
    if best then return best end
    for _, base in ipairs(PROF_BASE_RU) do
        if t:find(base, 1, true) or t:find(LowerFirst(base), 1, true) then
            if #base > bestLen then best, bestLen = base, #base end
        end
    end
    if best then return best end
    return t
end

-- Статичная карта иконок базовых профессий (ключа — EN-база из PROF_BASE_EN).
-- ProfessionInfo иконки не содержит, поэтому динамика через API невозможна;
-- карта работает и для старых сейвов (у них только имя-строка).
-- Неизвестное имя -> nil (звать показывает "?"); пути сверены с клиентом при smoke-test.
local PROF_ICONS = {
    ["First Aid"]      = "Interface\\ICONS\\INV_Misc_Bandage_12",
    ["Blacksmithing"]  = "Interface\\ICONS\\Trade_BlackSmithing",
    ["Leatherworking"] = "Interface\\ICONS\\Trade_LeatherWorking",
    ["Alchemy"]        = "Interface\\ICONS\\Trade_Alchemy",
    ["Herbalism"]      = "Interface\\ICONS\\Trade_Herbalism",
    ["Cooking"]        = "Interface\\ICONS\\INV_Misc_Food_15",
    ["Mining"]         = "Interface\\ICONS\\Trade_Mining",
    ["Tailoring"]      = "Interface\\ICONS\\Trade_Tailoring",
    ["Engineering"]    = "Interface\\ICONS\\Trade_Engineering",
    ["Enchanting"]     = "Interface\\ICONS\\Trade_Engraving",
    ["Fishing"]        = "Interface\\ICONS\\Trade_Fishing",
    ["Skinning"]       = "Interface\\ICONS\\INV_Misc_Pelt_Wolf_01",
    ["Jewelcrafting"]  = "Interface\\ICONS\\INV_Misc_Gem_01",
    ["Inscription"]    = "Interface\\ICONS\\INV_Inscription_Tradeskill01",
    ["Archaeology"]    = "Interface\\ICONS\\Trade_Archaeology",
    ["Carpentry"]      = "Interface\\ICONS\\INV_Misc_Wood_01",
}
-- RU-алиасы: на RU-клиенте parentProfessionName приходит по-русски
-- ("Кузнечное дело"), нормализация возвращает RU-базу — маппим её на ту же иконку.
-- PROF_BASE_RU идёт в том же порядке, что PROF_BASE_EN (без Carpentry:
-- RU-название новой профессии Midnight уточняется по клиенту, фолбэк — "?").
for _ri, _ru in ipairs(PROF_BASE_RU) do
    local _en = PROF_BASE_EN[_ri]
    if _en and PROF_ICONS[_en] and not PROF_ICONS[_ru] then PROF_ICONS[_ru] = PROF_ICONS[_en] end
end

-- Классические ID профессий для C_TradeSkillUI.OpenTradeSkill (открывает окно профы).
-- Expansion-варианты skillLine (напр. 2907) OpenTradeSkill НЕ открывает (возвращает false),
-- рабочие ID — классика 164/165/171... (подтверждено сообществом для актуального клиента).
local PROF_CLASSIC_IDS = {
    ["First Aid"] = 129, ["Blacksmithing"] = 164, ["Leatherworking"] = 165,
    ["Alchemy"] = 171, ["Cooking"] = 185, ["Herbalism"] = 182,
    ["Mining"] = 186, ["Tailoring"] = 197, ["Engineering"] = 202,
    ["Fishing"] = 356, ["Enchanting"] = 333, ["Skinning"] = 393,
    ["Jewelcrafting"] = 755, ["Inscription"] = 773, ["Archaeology"] = 794,
    -- Carpentry (Midnight): классического ID нет — только через Enum/skillLine-кандидаты
}

-- Классический ID профессии по имени (EN/RU, варианты дополнений).
-- Чистая функция (тестируема без клиента). nil если нет (Carpentry, неизвестное).
function Recipes.GetClassicProfessionID(name)
    if type(name) ~= "string" or name == "" then return nil end
    local norm = Recipes.NormalizeProfessionName(name)
    if type(norm) ~= "string" then return nil end
    if PROF_CLASSIC_IDS[norm] then return PROF_CLASSIC_IDS[norm] end
    for i, ru in ipairs(PROF_BASE_RU) do
        if ru == norm and PROF_BASE_EN[i] then
            return PROF_CLASSIC_IDS[PROF_BASE_EN[i]]
        end
    end
    return nil
end

-- Иконка профессии по имени (строка) или записи рецепта ({profession=...}).
-- Нормализует RU-варианты ("Зандаларское кузнечное дело" -> "Blacksmithing").
-- Чистая функция (тестируема без клиента). Возвращает путь текстуры или nil.
function Recipes.GetProfessionIcon(nameOrRec)
    local name = nameOrRec
    if type(nameOrRec) == "table" then name = nameOrRec.profession end
    if type(name) ~= "string" or name == "" then return nil end
    local norm = Recipes.NormalizeProfessionName(name)
    if type(norm) ~= "string" then return nil end
    return PROF_ICONS[norm]
end

-- База из ProfessionInfo: parentProfessionName (истина) -> нормализация professionName -> nil.
local function GetBaseProfessionName(profInfo)
    if type(profInfo) ~= "table" then return nil end
    if type(profInfo.parentProfessionName) == "string" and Trim(profInfo.parentProfessionName) ~= "" then
        return Trim(profInfo.parentProfessionName)
    end
    if type(profInfo.professionName) == "string" then
        return Recipes.NormalizeProfessionName(profInfo.professionName)
    end
    return nil
end

-- ==== Схемы рецептов ====

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

function Recipes.GetRecipeData(recipeSpellID)
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
        profession = GetBaseProfessionName(profInfo),
        professionID = (type(profInfo) == "table" and profInfo.professionID) or nil,
        parentProfessionID = (type(profInfo) == "table" and profInfo.parentProfessionID) or nil,
        professionEnum = (type(profInfo) == "table" and profInfo.profession) or nil,
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

-- ==== Перечисление кандидатов ====

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
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionSpells and Recipes.BruteForceEnabled() then
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

function Recipes.SetActiveSkillLineID(skillLineID)
    if type(skillLineID) == "number" and skillLineID ~= 0 then
        _activeSkillLineID = skillLineID
    end
end

function Recipes.GetActiveSkillLineID()
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
    -- debug сохраняем в модуле для /dump
    Recipes._lastActiveDebug = debug
    return ids
end

local function TryGetActiveRecipeSpellIDs()
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
        if Recipes.BruteForceEnabled() then
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
                    -- Вниз по коду нужны recipeSpellID (GetRecipeSchematic/GetRecipeInfo):
                    -- при наличии обоих берём spellID, recipeID — только за неимением
                    -- (namespace события NEW_RECIPE_LEARNED, для прямого вызова не годится).
                    local rid = data and (data.recipeSpellID or data.spellID or data.recipeID
                        or (data.recipeInfo and (data.recipeInfo.recipeSpellID or data.recipeInfo.recipeID)))
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

-- ==== Unified Scan (Этап 4): один цикл вместо FindWoodRecipesInActiveWindow/FindWoodRecipes ====
-- scope="active" (окно профессии) или "all" (все перечисляемые). Коды ошибок сохранены.

function Recipes.Scan(opts)
    opts = opts or {}
    local scope = opts.scope or "active"
    local ids = GetWoodIDs()
    if not ids or #ids == 0 then return {}, "WOOD_ID_NOT_SET" end
    local Core = _G.DecorLumberProfitCore
    local ItemInfo = _G.DecorLumberProfitItemInfo
    -- Tri-state привязки выхода (см. Services/ItemInfo.lua):
    -- true = непродаваемый (BoP bind 1 "Становится персональным при получении",
    --   Warband bind 8/9 "Привязывается к отряду", прочие не из 0/2) — пропускаем;
    -- nil = данные грузятся — паркуем в pending до GET_ITEM_INFO_RECEIVED.
    local function unsell(itemID)
        if ItemInfo and ItemInfo.IsUnsellable then return ItemInfo.IsUnsellable(itemID) end
        return false
    end
    local candidates = {}
    local activeLines = nil
    if scope == "all" then
        candidates = TryGetAllRecipeSpellIDs()
        if #candidates == 0 then
            return {}, "NO_RECIPES_ENUMERATED"
        end
    else
        candidates = TryGetActiveRecipeSpellIDs()
        activeLines = GetActiveSkillLineIDs()
        if #candidates == 0 then
            if #activeLines == 0 then
                return {}, "NO_ACTIVE_WINDOW", { scanned = 0, found = 0, activeSkillLines = activeLines }
            else
                return {}, "NO_RECIPES_IN_ACTIVE_WINDOW", { scanned = 0, found = 0, activeSkillLines = activeLines, candidateCount = 0 }
            end
        end
    end
    local maxResults = Recipes.MaxResults()
    local results = {}
    local scanned, noOutput, noWood, notLearned, bindSkipped, bindPending = 0, 0, 0, 0, 0, 0
    -- Образец пропущенных как непродаваемые (первые 8: имя + bind) и гистограмма
    -- bind-значений — чтобы "пропущено N" было видно поимённо (/dlp debug skipped).
    local skippedSample, bindHistogram = {}, {}
    local function noteSkipped(spellID, data)
        bindSkipped = bindSkipped + 1
        local b = nil
        if ItemInfo and ItemInfo.GetBindType and data and data.outputItemID then
            b = ItemInfo.GetBindType(data.outputItemID)
        end
        local hk = (b == nil) and "nil" or tostring(b)
        bindHistogram[hk] = (bindHistogram[hk] or 0) + 1
        if #skippedSample < 8 then
            table.insert(skippedSample, { spellID = spellID, name = data and data.name,
                outputItemID = data and data.outputItemID, bind = b })
        end
    end
    for _, spellID in ipairs(candidates) do
        scanned = scanned + 1
        local data = Recipes.GetRecipeData(spellID)
        if data and data.outputItemID and data.woodQty then
            local u = unsell(data.outputItemID)
            if u == true then
                noteSkipped(spellID, data)
            elseif u == nil then
                if ItemInfo and ItemInfo.PendingAdd then ItemInfo.PendingAdd(spellID, data) end
                bindPending = bindPending + 1
            else
                if data.recipeInfo and data.recipeInfo.learned == false then
                    notLearned = notLearned + 1
                    data.isUnavailable = true
                end
                table.insert(results, data)
                if Core and Core.RememberRecipe then
                    Core:RememberRecipe(spellID, data.recipeInfo and data.recipeInfo.unlockedRecipeLevel or 1)
                end
            end
        else
            if data and not data.outputItemID then
                noOutput = noOutput + 1
            elseif data and not data.woodQty then
                noWood = noWood + 1
            end
        end
        if #results >= maxResults then break end
        if scope == "all" and scanned % 200 == 0 and coroutine.running() then coroutine.yield() end
    end
    -- Если в активном окне есть кандидаты, но ни один не содержит древесину — спец. ошибка с диагностикой
    if scope ~= "all" and #results == 0 and #candidates > 0 then
        Recipes._lastSkipped = skippedSample
        return {}, "NO_WOOD_IN_ACTIVE_CANDIDATES", { scanned = scanned, found = 0, noOutput = noOutput, noWood = noWood, notLearned = notLearned, bindSkipped = bindSkipped, bindPending = bindPending, candidateCount = #candidates, activeSkillLines = activeLines, skippedSample = skippedSample, bindHistogram = bindHistogram }
    end
    table.sort(results, function(a, b) return (a.name or "") < (b.name or "") end)
    Recipes._lastSkipped = skippedSample
    local meta = { scanned = scanned, found = #results, noOutput = noOutput, noWood = noWood,
        notLearned = notLearned, bindSkipped = bindSkipped, bindPending = bindPending,
        skippedSample = skippedSample, bindHistogram = bindHistogram }
    if scope ~= "all" then
        meta.candidateCount = #candidates
        meta.activeSkillLines = activeLines
    end
    return results, nil, meta
end

function Recipes.ScanAndRememberCurrentProfession()
    if not C_TradeSkillUI or not C_TradeSkillUI.GetProfessionSpells then return 0 end
    local Core = _G.DecorLumberProfitCore
    local added = 0
    local candidates = TryGetAllRecipeSpellIDs()
    for _, sid in ipairs(candidates) do
        local info = SafeCall(C_TradeSkillUI.GetRecipeInfo, sid)
        if info and info.learned then
            local before = DecorLumberProfitDB and DecorLumberProfitDB.knownRecipes and DecorLumberProfitDB.knownRecipes[sid]
            if Core and Core.RememberRecipe then
                Core:RememberRecipe(sid, info.unlockedRecipeLevel or 1)
            end
            if not before then added = added + 1 end
        end
    end
    return added
end

-- ==== Диагностика (переехала из Core без изменений логики) ====

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

-- Диагностика активного окна: доступна из /dump DecorLumberProfitCore:DebugActive()
function Recipes.DebugActive()
    local lines = GetActiveSkillLineIDs()
    local spellsInfo = {}
    for _, sid in ipairs(lines) do
        local info = SafeCall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, sid)
        table.insert(spellsInfo, { skillLineID = sid, info = info })
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
        return { pid = pid, sid = sid, withSID = CountTable(a), withoutSID = CountTable(b) }
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
    for _, pid in ipairs({ 164, 171, 182, 186, 197, 202, 333, 393, 755, 2907, 2904 }) do
        table.insert(probes, probe(pid, nil))
    end
    return {
        activeSkillLines = lines,
        spellsInfo = spellsInfo,
        debugSources = Recipes._lastActiveDebug,
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

-- Прямой тест: /dump DecorLumberProfitCore:DebugSpell(123456)
function Recipes.DebugSpell(spellID)
    local data = Recipes.GetRecipeData(spellID)
    if not data then return { err = "no schematic", spellID = spellID } end
    local bindType, unsell = nil, nil
    if data.outputItemID then
        local M = _G.DecorLumberProfitItemInfo
        if M then
            if M.GetBindType then bindType = M.GetBindType(data.outputItemID) end
            if M.IsUnsellable then unsell = M.IsUnsellable(data.outputItemID) end
        end
    end
    return {
        spellID = spellID,
        name = data.name,
        outputItemID = data.outputItemID,
        woodQty = data.woodQty,
        woodItemID = data.woodItemID,
        reagents = data.reagents,
        schematic = data.schematic and #data.schematic.reagentSlotSchematics or 0,
        info = data.recipeInfo,
        bindType = bindType,
        unsellable = unsell,
    }
end

-- Образец рецептов, пропущенных последним Scan как непродаваемые
-- (заполняется в Scan; пусто до первого скана). Для /dlp debug skipped.
function Recipes.LastSkipped()
    return Recipes._lastSkipped or {}
end

function Recipes.HealthCheck()
    local ids = GetWoodIDs()
    return { ok = ids ~= nil and #ids > 0,
        woodTypes = ids and #ids or 0,
        bruteforce = Recipes.BruteForceEnabled(),
        maxResults = Recipes.MaxResults() }
end

_G.DecorLumberProfitRecipes = Recipes
