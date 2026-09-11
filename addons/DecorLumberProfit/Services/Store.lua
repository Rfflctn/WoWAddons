-- Services/Store.lua | DecorLumberProfit | Retail 12.1.0
-- Персистентность: account-wide база рецептов, realm-scoped цены и снимки АХ.
-- Все функции — через точку (без self). Core держит тонкие :-врапперы.
-- WoW Lua 5.1: no goto, no //, no bitwise ops. No WoW calls at top level.

DecorLumberProfitStore = {}
local Store = DecorLumberProfitStore

Store.RECIPE_CAP = 1000 -- кап таблицы recipes (EnforceCap режет только timestamped, сверх капа — самые старые)

local function Now()
    if _G.time then
        local ok, t = pcall(_G.time)
        if ok and type(t) == "number" then return t end
    end
    return 0
end

local function CurrentPlayer()
    if _G.UnitName then
        local ok, name = pcall(_G.UnitName, "player")
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return "player"
end

local function RealmContext()
    local normalized, display
    if _G.GetNormalizedRealmName then
        local ok, value = pcall(_G.GetNormalizedRealmName)
        if ok and type(value) == "string" and value ~= "" then normalized = value end
    end
    if _G.GetRealmName then
        local ok, value = pcall(_G.GetRealmName)
        if ok and type(value) == "string" and value ~= "" then display = value end
    end
    display = display or normalized
    if not normalized and display then
        normalized = display:gsub("[%s%p]", ""):lower()
    end
    if not normalized or normalized == "" then return nil, display end
    return normalized, display or normalized
end

-- Есть ли хоть один персонаж, знающий рецепт (значения learnedBy — явные boolean)
local function HasAnyLearner(learnedBy)
    if type(learnedBy) ~= "table" then return false end
    for _, v in pairs(learnedBy) do
        if v == true then return true end
    end
    return false
end

local function CountTable(t)
    local Addon = _G.DecorLumberProfit
    if Addon and Addon.CountTable then return Addon.CountTable(t) end
    if type(t) ~= "table" then return 0 end
    local c = 0
    for _ in pairs(t) do c = c + 1 end
    return c
end

-- ==== Миграции ====

--Adopt legacy SavedVariables names (v1.4.0 rename LumberProfit/ThalassianWood -> DecorLumberProfit).
local function AdoptLegacyNames()
    if DecorLumberProfitDB == nil and _G.LumberProfitDB ~= nil then DecorLumberProfitDB = _G.LumberProfitDB end
    if DecorLumberProfitDB == nil and _G.ThalassianWoodDB ~= nil then DecorLumberProfitDB = _G.ThalassianWoodDB end
    if DecorLumberProfitCharDB == nil and _G.LumberProfitCharDB ~= nil then DecorLumberProfitCharDB = _G.LumberProfitCharDB end
    if DecorLumberProfitCharDB == nil and _G.ThalassianWoodCharDB ~= nil then DecorLumberProfitCharDB = _G.ThalassianWoodCharDB end
end

local function EnsureTables()
    DecorLumberProfitDB = DecorLumberProfitDB or {}
    DecorLumberProfitDB.priceCache = DecorLumberProfitDB.priceCache or {}
    DecorLumberProfitDB.realmMeta = DecorLumberProfitDB.realmMeta or {}
    DecorLumberProfitDB.ownedAuctions = DecorLumberProfitDB.ownedAuctions or {}
    DecorLumberProfitDB.knownRecipes = DecorLumberProfitDB.knownRecipes or {}
    DecorLumberProfitDB.recipes = DecorLumberProfitDB.recipes or {}
    DecorLumberProfitDB.settings = DecorLumberProfitDB.settings or {}
    DecorLumberProfitCharDB = DecorLumberProfitCharDB or {}
    DecorLumberProfitCharDB.seenRecipes = DecorLumberProfitCharDB.seenRecipes or {}
end

-- Переносит старый плоский priceCache[itemID] в bucket текущего реалма.
-- До PLAYER_LOGIN имя реалма может быть недоступно, поэтому миграция идемпотентна
-- и повторяется из Prices.InitializeRealm(). Старые данные нельзя достоверно
-- распределить по нескольким реалмам — относим их к текущему.
function Store.MigrateRealmData(realmKey, realmName)
    local db = _G.DecorLumberProfitDB
    if not db or not realmKey or realmKey == "" then return false end
    db.priceCache = db.priceCache or {}
    db.realmMeta = db.realmMeta or {}
    db.ownedAuctions = db.ownedAuctions or {}
    local bucket = db.priceCache[realmKey]
    if type(bucket) ~= "table" then bucket = {}; db.priceCache[realmKey] = bucket end
    for itemID, entry in pairs(db.priceCache) do
        if type(itemID) == "number" and type(entry) == "table" then
            if bucket[itemID] == nil then bucket[itemID] = entry end
            db.priceCache[itemID] = nil
        end
    end
    if type(db.priceUpdatedAt) == "number" then
        db.priceUpdatedAtByRealm = db.priceUpdatedAtByRealm or {}
        if db.priceUpdatedAtByRealm[realmKey] == nil then
            db.priceUpdatedAtByRealm[realmKey] = db.priceUpdatedAt
        end
        db.priceUpdatedAt = nil
    end
    db.priceUpdatedAtByRealm = db.priceUpdatedAtByRealm or {}
    db.realmMeta[realmKey] = db.realmMeta[realmKey] or {}
    db.realmMeta[realmKey].name = realmName or db.realmMeta[realmKey].name or realmKey
    db.realmMeta[realmKey].lastSeen = Now()
    db.realmMigrationPending = nil
    return true
end

-- Режет таблицу сверх капа: только записи С меткой savedAt (самые старые первыми);
-- без метки (дедовские сейвы) не трогаем.
function Store.EnforceCap()
    local db = _G.DecorLumberProfitDB
    if not (db and db.recipes) then return 0 end
    local total = CountTable(db.recipes)
    if total <= Store.RECIPE_CAP then return 0 end
    local stamped = {}
    for spellID, ser in pairs(db.recipes) do
        if type(ser) == "table" and type(ser.savedAt) == "number" then
            stamped[#stamped + 1] = { spellID = spellID, at = ser.savedAt }
        end
    end
    table.sort(stamped, function(a, b) return a.at < b.at end)
    local drop = total - Store.RECIPE_CAP
    local removed = 0
    for i = 1, math.min(drop, #stamped) do
        db.recipes[stamped[i].spellID] = nil
        removed = removed + 1
    end
    return removed
end

-- Удаляет из SavedVariables рецепты с непродаваемой продукцией
-- (BoP bind 1, Warband bind 8/9 и остальные не из белого списка 0/2).
-- bind==nil (данные предмета ещё грузятся) — оставляем, решит LoadSavedRecipes/ResolvePending.
-- Возвращает число удалённых записей.
function Store.PurgeUnsellable()
    local db = _G.DecorLumberProfitDB
    if not (db and db.recipes) then return 0 end
    local ItemInfo = _G.DecorLumberProfitItemInfo
    if not (ItemInfo and ItemInfo.IsUnsellable) then return 0 end
    local removed = 0
    for spellID, ser in pairs(db.recipes) do
        if type(ser) == "table" and ser.outputItemID then
            local ok, u = pcall(ItemInfo.IsUnsellable, ser.outputItemID)
            if ok and u == true then
                db.recipes[spellID] = nil
                removed = removed + 1
            end
        end
    end
    return removed
end

-- Точка входа при ADDON_LOADED (вызывает UI): adopt -> ensure -> migrate -> stamp.
function Store.Upgrade()
    AdoptLegacyNames()
    EnsureTables()
    local realmKey, realmName = RealmContext()
    if realmKey then
        Store.MigrateRealmData(realmKey, realmName)
    else
        DecorLumberProfitDB.realmMigrationPending = true
    end
    Store.PurgeUnsellable() -- чистка сейвов от BoP/Warband-выходов (см. ItemInfo)
    local Addon = _G.DecorLumberProfit
    local target = (Addon and Addon.DB_SCHEMA) or 1
    local schema = DecorLumberProfitDB.schemaVersion or 0
    if schema < 1 then
        Store.EnforceCap()
    end
    -- будущие схемы: if schema < 2 then ... end (по нарастающей)
    -- Применяем сохранённые настройки сканирования поверх Config (переживают /reload)
    DecorLumberProfitConfig = DecorLumberProfitConfig or {}
    local sc = DecorLumberProfitConfig.SCAN or {}
    local saved = DecorLumberProfitDB.settings.scan or {}
    if saved.bruteforce ~= nil then sc.ENABLE_BRUTEFORCE = saved.bruteforce end
    if type(saved.maxscan) == "number" then sc.MAX_RESULTS = saved.maxscan end
    DecorLumberProfitConfig.SCAN = sc
    -- Мультиреалм-отображение (переживает /reload; сбор данных не гейтится)
    if DecorLumberProfitDB.settings.multiRealm ~= nil then
        DecorLumberProfitConfig.MULTI_REALM = DecorLumberProfitDB.settings.multiRealm and true or false
    elseif DecorLumberProfitConfig.MULTI_REALM == nil then
        DecorLumberProfitConfig.MULTI_REALM = false
    end
    DecorLumberProfitDB.schemaVersion = target
    _G.DecorLumberProfitDB = DecorLumberProfitDB
    _G.DecorLumberProfitCharDB = DecorLumberProfitCharDB
    return DecorLumberProfitDB
end

-- ==== knownRecipes / seenRecipes ====

function Store.RememberRecipe(recipeID, recipeLevel)
    if not recipeID then return end
    DecorLumberProfitDB = DecorLumberProfitDB or {}
    DecorLumberProfitDB.knownRecipes = DecorLumberProfitDB.knownRecipes or {}
    DecorLumberProfitDB.knownRecipes[recipeID] = { level = recipeLevel, time = Now() }
    DecorLumberProfitCharDB = DecorLumberProfitCharDB or {}
    DecorLumberProfitCharDB.seenRecipes = DecorLumberProfitCharDB.seenRecipes or {}
    DecorLumberProfitCharDB.seenRecipes[recipeID] = true
end

-- ==== Таблица recipes (account-wide snapshot'ы) ====

local function EnsureRecipes()
    DecorLumberProfitDB = DecorLumberProfitDB or {}
    DecorLumberProfitDB.recipes = DecorLumberProfitDB.recipes or {}
    return DecorLumberProfitDB.recipes
end

function Store.SerializeRecipe(rec)
    if not rec or not rec.recipeSpellID then return nil end
    local reagents = {}
    for i, r in ipairs(rec.reagents or {}) do
        reagents[i] = { itemID = r.itemID, quantity = r.quantity, required = r.required,
                        slotIndex = r.slotIndex, reagentType = r.reagentType, isWood = r.isWood }
    end
    local prof = rec.profession
    local Recipes = _G.DecorLumberProfitRecipes
    if type(prof) == "string" and Recipes and Recipes.NormalizeProfessionName then
        local ok, norm = pcall(Recipes.NormalizeProfessionName, prof)
        if ok and type(norm) == "string" and norm ~= "" then prof = norm end
    end
    return {
        recipeSpellID = rec.recipeSpellID,
        name = rec.name,
        profession = prof,
        outputItemID = rec.outputItemID,
        outputQty = rec.outputQty, outputMin = rec.outputMin, outputMax = rec.outputMax,
        icon = rec.icon,
        woodQty = rec.woodQty, woodItemID = rec.woodItemID, woodName = rec.woodName,
        reagents = reagents,
        learned = rec.learned,
    }
end

-- Сохраняет snapshot рецепта в общую базу (account-wide).
-- learned — пер-персонажный флаг: learnedBy[player]=true — знает, =false —
-- проверено, что НЕ знает; записи ДРУГИХ персонажей не трогаем.
-- ser.learned — "знает хоть кто-то" (OR по learnedBy, legacy-фолбэк для старых сейвов).
-- rec.learned == nil (API не ответил) — learned/learnedBy не трогаем, прежнее не затираем.
-- BoP ("Становится персональным при получении", bind 1) и Warband
-- ("Привязывается к отряду", bind 8/9) в базу НЕ пишем: их нельзя продать на АХ.
function Store.SaveRecipe(rec)
    if not rec or not rec.recipeSpellID then return end
    local ItemInfo = _G.DecorLumberProfitItemInfo
    if ItemInfo and ItemInfo.IsUnsellable and rec.outputItemID then
        local ok, u = pcall(ItemInfo.IsUnsellable, rec.outputItemID)
        if ok and u == true then
            local db0 = DecorLumberProfitDB and DecorLumberProfitDB.recipes
            if db0 then db0[rec.recipeSpellID] = nil end
            return nil
        end
    end
    local db = EnsureRecipes()
    local ser = Store.SerializeRecipe(rec)
    local existing = db[rec.recipeSpellID]
    if existing then
        if type(existing.learnedBy) == "table" then
            ser.learnedBy = existing.learnedBy
        else
            ser.learnedBy = {}
        end        ser.savedAt = existing.savedAt -- возраст записи не омолаживаем апдейтами
        -- обновляем только если пришли более полные данные (есть reagents)
        if not (ser.reagents and #ser.reagents > 0) and existing.reagents and #existing.reagents > 0 then
            ser.reagents = existing.reagents
        end
    else
        ser.learnedBy = {}
        ser.savedAt = Now()
    end
    local player = CurrentPlayer()
    if rec.learned == true then
        ser.learnedBy[player] = true
        ser.learned = true
    elseif rec.learned == false then
        ser.learnedBy[player] = false
        ser.learned = HasAnyLearner(ser.learnedBy) and true or false
    else
        if existing then
            ser.learned = existing.learned
        else
            ser.learned = nil
        end
    end
    ser.updatedAt = Now()
    db[rec.recipeSpellID] = ser
    return db[rec.recipeSpellID]
end

-- Отмечает, что рецепт изучен текущим персонажем
function Store.MarkLearnedBy(spellID)
    if not spellID then return end
    local db = EnsureRecipes()
    local ser = db[spellID]
    if not ser then return end
    ser.learnedBy = ser.learnedBy or {}
    ser.learnedBy[CurrentPlayer()] = true
    ser.learned = true
end

-- Загружает все сохранённые рецепты (общие для аккаунта), ре-валидируя привязку выхода
function Store.LoadSavedRecipes()
    local out = {}
    if not (DecorLumberProfitDB and DecorLumberProfitDB.recipes) then return out end
    local ItemInfo = _G.DecorLumberProfitItemInfo
    local function unsell(itemID)
        if ItemInfo and ItemInfo.IsUnsellable then return ItemInfo.IsUnsellable(itemID) end
        return false
    end
    local Recipes = _G.DecorLumberProfitRecipes
    for spellID, ser in pairs(DecorLumberProfitDB.recipes) do
        if type(ser) == "table" and ser.recipeSpellID then
            local rec = {}
            for k, v in pairs(ser) do rec[k] = v end
            -- Миграция на лету: старые сейвы хранят варианты ("Зандаларское ...") — сводим к базе.
            if type(rec.profession) == "string" and Recipes and Recipes.NormalizeProfessionName then
                local ok, norm = pcall(Recipes.NormalizeProfessionName, rec.profession)
                if ok and type(norm) == "string" and norm ~= "" then
                    rec.profession = norm
                    if type(ser.profession) ~= "string" or ser.profession ~= norm then
                        ser.profession = norm -- чиним и базу, чтобы не мигрировать каждый раз
                    end
                end
            end
            -- learned текущего персонажа: приоритет — его запись в learnedBy,
            -- иначе legacy-фолбэк ser.learned (сейвы до пер-персонажного учёта)
            if type(ser.learnedBy) == "table" then
                local mine = ser.learnedBy[CurrentPlayer()]
                if mine ~= nil then rec.learned = mine and true or false end
            else
                rec.learnedBy = {}
            end
            if type(rec.learnedBy) ~= "table" then rec.learnedBy = {} end
            local u = nil
            if rec.outputItemID then u = unsell(rec.outputItemID) end
            if u == true then
                DecorLumberProfitDB.recipes[spellID] = nil -- чистим базу от непродаваемых
            elseif u == nil and rec.outputItemID then
                rec.isUnavailable = (rec.learned == false)
                if ItemInfo and ItemInfo.PendingAdd then
                    ItemInfo.PendingAdd(spellID, rec) -- bind неизвестен — ждём догрузки, в таблицу не пускаем
                end
            else
                rec.isUnavailable = (rec.learned == false)
                table.insert(out, rec)
            end
        end
    end
    return out
end

function Store.GetSavedRecipe(spellID)
    if not (DecorLumberProfitDB and DecorLumberProfitDB.recipes) then return nil end
    return DecorLumberProfitDB.recipes[spellID]
end

function Store.ClearSavedRecipes()
    if DecorLumberProfitDB then DecorLumberProfitDB.recipes = {} end
end

function Store.SavedRecipeCount()
    local db = _G.DecorLumberProfitDB
    if db and db.recipes then return CountTable(db.recipes) end
    return 0
end

-- Пересчитывает learned для загруженных рецептов по живому API (для текущего персонажа)
-- и СРАЗУ сохраняет результат в DB, чтобы пережить /reload без повторного скана.
-- info.learned == nil (API не ответил) — ни память, ни DB не трогаем.
function Store.RefreshLearnedFlags(list)
    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeInfo then return end
    local Addon = _G.DecorLumberProfit
    local function sc(func, ...)
        if Addon and Addon.SafeCall then return Addon.SafeCall(func, ...) end
        return nil
    end
    local player = CurrentPlayer()
    for _, rec in ipairs(list) do
        if rec.recipeSpellID then
            local info = sc(C_TradeSkillUI.GetRecipeInfo, rec.recipeSpellID)
            if info and info.learned ~= nil then
                rec.learned = info.learned and true or false
                rec.isUnavailable = (info.learned == false)
                local ser = Store.GetSavedRecipe(rec.recipeSpellID)
                if ser then
                    if type(ser.learnedBy) ~= "table" then ser.learnedBy = {} end
                    if info.learned then
                        ser.learnedBy[player] = true
                        ser.learned = true
                    else
                        ser.learnedBy[player] = false
                        ser.learned = HasAnyLearner(ser.learnedBy) and true or false
                    end
                    rec.learnedBy = ser.learnedBy
                else
                    if type(rec.learnedBy) ~= "table" then rec.learnedBy = {} end
                end
            end
        end
    end
end

function Store.HealthCheck()
    local db = _G.DecorLumberProfitDB
    local ch = _G.DecorLumberProfitCharDB
    return {
        ok = db ~= nil,
        schema = db and (db.schemaVersion or 0) or 0,
        recipes = db and db.recipes and CountTable(db.recipes) or 0,
        known = db and db.knownRecipes and CountTable(db.knownRecipes) or 0,
        seen = ch and ch.seenRecipes and CountTable(ch.seenRecipes) or 0,
    }
end

_G.DecorLumberProfitStore = Store
