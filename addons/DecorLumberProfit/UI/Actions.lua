-- UI/Actions.lua | DecorLumberProfit | Retail 12.1.0
-- Бизнес-действия таблицы (Этап 8): скан, загрузка из DB, цены, очистка.

local UI = _G.DecorLumberProfitUI or {}
local L = DecorLumberProfitL10n.L
local TL = DecorLumberProfitL10n.TL

function UI.RebuildRecipeList(showMessage)
    -- Новый принцип: добавляем рецепты из АКТИВНОГО окна профессии в таблицу (append, без дублей)
    local recipes, err, meta = DecorLumberProfitCore:FindWoodRecipesInActiveWindow()

    if err == "WOOD_ID_NOT_SET" then
        UI.SetStatus(L.ST_ERR_WOOD_ID, 1, 0.3, 0.3)
        UI.RefreshTable()
        return
    elseif err == "NO_ACTIVE_WINDOW" then
        UI.SetStatus(L.ST_NO_ACTIVE_WINDOW, 1, 0.7, 0.2)
        if showMessage then print(L.PREFIX_ERR .. L.ST_NO_ACTIVE_WINDOW) end
        UI.RefreshTable()
        return
    elseif err == "NO_RECIPES_IN_ACTIVE_WINDOW" then
        local dbg = meta and TL("DBG_META", table.concat(meta.activeSkillLines or {}, ","), tostring(meta.candidateCount or 0)) or ""
        UI.SetStatus(L.ST_NO_RECIPES_IN_WINDOW .. dbg, 1, 0.7, 0.2)
        if showMessage then
            print(L.PREFIX_ERR .. TL("PRINT_NO_RECIPES_ACTIVE", dbg))
        end
        UI.RefreshTable()
        return
    elseif err == "NO_WOOD_IN_ACTIVE_CANDIDATES" then
        local dbg = meta and TL("DBG_META_NO_WOOD", meta.candidateCount or 0, meta.noOutput or 0, meta.noWood or 0, meta.bindSkipped or 0, meta.bindPending or 0, table.concat(meta.activeSkillLines or {}, ",")) or ""
        -- Fallback: пробуем глобальный поиск по всем профессиям и добавляем те, что содержат древесину
        local global, gErr, gMeta = DecorLumberProfitCore:FindWoodRecipes()
        if global and #global > 0 then
            local existing = UI.BuildExistingSet(UI._currentRecipes)
            local added = 0
            for _, r in ipairs(global) do if not existing[r.recipeSpellID] then table.insert(UI._currentRecipes, r); added = added + 1 end end
            table.sort(UI._currentRecipes, function(a, b) return (a.name or "") < (b.name or "") end)
            UI.SetStatus(TL("ST_GLOBAL_FALLBACK", meta and meta.candidateCount or 0, #global, added, #UI._currentRecipes), 0.3, 1, 0.3)
            if showMessage then print(L.PREFIX_OK .. TL("PRINT_GLOBAL_FALLBACK", dbg, added)) end
            UI.RefreshTable()
            return
        end
        UI.SetStatus(TL("ST_NO_WOOD_IN_WINDOW", tostring(meta and meta.candidateCount or "?"), dbg), 1, 0.7, 0.2)
        if showMessage then
            print(L.PREFIX_ERR .. TL("PRINT_NO_WOOD_DETAIL", tostring(meta and meta.candidateCount or "?"), tostring(meta and meta.noOutput or "?"), tostring(meta and meta.noWood or "?")))
            local ids = DecorLumberProfitCore:GetWoodIDs()
            print(L.PREFIX_DIM .. TL("PRINT_WOOD_IDS", table.concat(ids, ", ")) .. "|r")
            if meta and meta.candidateCount and meta.candidateCount > 0 then
                local debug = DecorLumberProfitCore:DebugActive()
                print(L.PREFIX_DIM .. TL("PRINT_ACTIVE_DEBUG", table.concat(debug.activeSkillLines or {}, ","), table.concat(debug.firstCandidates or {}, ",")) .. "|r")
            end
        end
        UI.RefreshTable()
        return
    elseif err == "NO_RECIPES_ENUMERATED" then
        UI.SetStatus(L.ST_NO_RECIPES_ENUMERATED, 1, 0.7, 0.2)
        UI.RefreshTable()
        return
    end

    -- append без дублей + сохранение в общую (account-wide) базу
    local existing = UI.BuildExistingSet(UI._currentRecipes)
    local added = 0
    for _, r in ipairs(recipes or {}) do
        local ser = DecorLumberProfitCore:SaveRecipe(r)
        if r.learned == true then DecorLumberProfitCore:MarkLearnedBy(r.recipeSpellID); ser = DecorLumberProfitCore:GetSavedRecipe(r.recipeSpellID) end
        if ser then r.learnedBy = ser.learnedBy end
        if not existing[r.recipeSpellID] then
            table.insert(UI._currentRecipes, r)
            existing[r.recipeSpellID] = true
            added = added + 1
        end
    end
    table.sort(UI._currentRecipes, function(a, b) return (a.name or "") < (b.name or "") end)

    if #recipes == 0 then
        UI.SetStatus(TL("ST_FOUND_ZERO", #UI._currentRecipes), 1, 0.7, 0.2)
    elseif added == 0 then
        UI.SetStatus(TL("ST_ALL_DUP", #recipes, #UI._currentRecipes), 0.3, 1, 0.3)
        if showMessage then print(L.PREFIX_OK .. TL("PRINT_ALL_DUP", #recipes, #UI._currentRecipes)) end
    else
        UI.SetStatus(TL("ST_ADDED", added, #recipes, #UI._currentRecipes), 0.3, 1, 0.3)
        if showMessage then print(L.PREFIX_OK .. TL("PRINT_ADDED", added, #UI._currentRecipes)) end
    end
    UI.RefreshTable()
end

-- Поднимает накопленную общую базу рецептов из SavedVariables
function UI.LoadFromDB()
    local saved = DecorLumberProfitCore:LoadSavedRecipes()
    if not saved or #saved == 0 then return 0 end
    local existing = UI.BuildExistingSet(UI._currentRecipes)
    local loaded = 0
    for _, rec in ipairs(saved) do
        if not existing[rec.recipeSpellID] then
            table.insert(UI._currentRecipes, rec)
            existing[rec.recipeSpellID] = true
            loaded = loaded + 1
        end
    end
    -- learned актуализируется под текущего персонажа (в т.ч. learnedBy)
    pcall(function() DecorLumberProfitCore:RefreshLearnedFlags(UI._currentRecipes) end)
    table.sort(UI._currentRecipes, function(a, b) return (a.name or "") < (b.name or "") end)
    return loaded
end

-- Полная перезагрузка таблицы (используется редко, например, при /reload)
function UI.RebuildAllRecipes()
    local recipes, err, meta = DecorLumberProfitCore:FindWoodRecipes()
    if err then
        UI.SetStatus(L.ST_REBUILD_EMPTY, 1, 0.7, 0.2)
        UI.RefreshTable()
        return
    end
    UI._currentRecipes = {}
    for _, r in ipairs(recipes or {}) do
        table.insert(UI._currentRecipes, r)
    end
    for _, r in ipairs(UI._currentRecipes) do DecorLumberProfitCore:SaveRecipe(r) end
    table.sort(UI._currentRecipes, function(a, b) return (a.name or "") < (b.name or "") end)
    UI.SetStatus(TL("ST_REBUILD_LOADED", #UI._currentRecipes), 0.3, 1, 0.3)
    UI.RefreshTable()
end

function UI.RequestAuctionUpdate()
    if #UI._currentRecipes == 0 then
        UI.SetStatus(L.ST_NO_RECIPES_FOR_PRICES, 1, 0.5, 0)
        return
    end
    local _, need = DecorLumberProfitPrices.CollectPricesForRecipes(UI._currentRecipes)
    if #need == 0 then
        UI.SetStatus(TL("ST_PRICES_CACHED", (DecorLumberProfitConfig.AUCTION.PRICE_TTL / 60)) .. UI.PriceTimeSuffix(), 0.7, 0.7, 1)
        UI.RefreshTable()
        return
    end
    -- Фильтруем только уникальные
    local uniq, seen = {}, {}
    for _, id in ipairs(need) do if not seen[id] then seen[id] = true; table.insert(uniq, id) end end
    UI.SetStatus(TL("ST_PRICES_REQUESTED", #uniq) .. UI.PriceTimeSuffix(), 0.3, 0.8, 1)
    DecorLumberProfitPrices.RequestPrices(uniq)
end

-- Очистка таблицы + общей базы (для кнопки и /dlp clear)
function UI.ClearAll()
    UI._currentRecipes = {}
    table.wipe(UI._displayList)
    UI._lastRowCount = nil
    UI._topMode = false
    if UI.btnTop then UI.btnTop:SetText(L.BTN_TOP) end
    DecorLumberProfitCore:ClearSavedRecipes()
    if UI._mainFrame then UI.RefreshTable() end
end
