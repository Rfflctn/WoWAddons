-- UI/Commands.lua | DecorLumberProfit | Retail 12.1.0
-- Слэш-команды и события клиента (Этап 8). Логики нет — только диспетчеризация в UI.*/Services.*.

local UI = _G.DecorLumberProfitUI or {}
local L = DecorLumberProfitL10n.L
local TL = DecorLumberProfitL10n.TL

-- Инициализация слэш-команд и миникарты/кнопки не требуется — минимально.

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("NEW_RECIPE_LEARNED")
initFrame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
initFrame:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
initFrame:RegisterEvent("TRADE_SKILL_SHOW")
initFrame:RegisterEvent("TRADE_SKILL_CLOSE")
initFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

initFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == "DecorLumberProfit" then
        -- Миграции и создание таблиц — Services/Store.lua:Upgrade() (Этап 5).
        local Store = _G.DecorLumberProfitStore
        if Store and Store.Upgrade then
            Store.Upgrade()
        else
            -- degraded: частичная установка без Store (минимум таблиц, без миграций имён)
            DecorLumberProfitDB = DecorLumberProfitDB or { priceCache = {}, knownRecipes = {}, recipes = {}, settings = {} }
            DecorLumberProfitCharDB = DecorLumberProfitCharDB or { seenRecipes = {} }
        end

        -- Локаль: переопределение из settings или авто-определение по клиенту
        local loc = DecorLumberProfitDB.settings.locale
        if loc ~= "enUS" and loc ~= "ruRU" then loc = DecorLumberProfitL10n.DetectLocale() end
        DecorLumberProfitL10n.SetLocale(loc)
        UI.hideUnlearned = DecorLumberProfitDB.settings.hideUnlearned and true or false
        if UI.LoadColumnVisibility then UI.LoadColumnVisibility() end
        if UI.LoadRowHeight then UI.LoadRowHeight() end
        UI.RegisterPopups()

        SLASH_DECORLUMBERPROFIT1 = "/dlp"
        SLASH_DECORLUMBERPROFIT2 = "/lp"
        SLASH_DECORLUMBERPROFIT3 = "/twc"
        SLASH_DECORLUMBERPROFIT4 = "/thalwood"
        SLASH_DECORLUMBERPROFIT5 = "/древесина"
        SlashCmdList["DECORLUMBERPROFIT"] = function(msg)
            msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            if msg == "help" or msg == "?" then
                print(L.PREFIX_OK .. L.PRINT_HELP)
                print(L.PREFIX_OK .. L.DEBUG_HELP)
            elseif msg == "reset" then
                DecorLumberProfitPrices.ClearPriceCache()
                print(L.PREFIX_ERR .. L.PRINT_CACHE_RESET)
                if UI._mainFrame and UI._mainFrame:IsShown() then UI.RefreshTable() end
            elseif msg == "clear" then
                UI.ClearAll()
                print(L.PREFIX_ERR .. L.PRINT_TABLE_CLEARED)
            elseif msg == "scan" then
                UI.RebuildRecipeList(true)
            elseif msg == "multirealm on" or msg == "multirealm off" then
                local on = (msg == "multirealm on")
                if UI.SetMultiRealm then
                    UI.SetMultiRealm(on)
                else
                    _G.DecorLumberProfitConfig = _G.DecorLumberProfitConfig or {}
                    _G.DecorLumberProfitConfig.MULTI_REALM = on
                    if DecorLumberProfitDB and DecorLumberProfitDB.settings then
                        DecorLumberProfitDB.settings.multiRealm = on
                    end
                end
                print(L.PREFIX_OK .. TL("PRINT_MULTIREALM_SET", on and "on" or "off"))
            elseif msg == "multirealm" then
                local on = UI.IsMultiRealmEnabled and UI.IsMultiRealmEnabled()
                print(L.PREFIX_OK .. TL("PRINT_MULTIREALM_SET", on and "on" or "off"))
            elseif msg:find("^rowheight") then
                local n = tonumber(msg:match("^rowheight%s+(%d+)"))
                if n and UI.SetRowHeight and UI.SetRowHeight(n) then
                    print(L.PREFIX_OK .. TL("PRINT_ROWHEIGHT_SET", tostring(UI.GetRowHeight())))
                else
                    print(L.PREFIX_ERR .. L.PRINT_ROWHEIGHT_USAGE)
                end
            elseif msg:find("^locale") then
                local arg = msg:match("^locale%s+(%a+)")
                local norm = DecorLumberProfitL10n.NormalizeLocaleArg(arg)
                if arg and norm then
                    if norm == "auto" then
                        DecorLumberProfitDB.settings.locale = nil
                        norm = DecorLumberProfitL10n.DetectLocale()
                    else
                        DecorLumberProfitDB.settings.locale = norm
                    end
                    print(L.PREFIX_OK .. TL("PRINT_LOCALE_SET", norm))
                else
                    print(L.PREFIX_ERR .. L.PRINT_LOCALE_USAGE)
                end
            elseif msg == "debug" or msg == "debug status" then
                local D = _G.DecorLumberProfitDiag
                if D and D.PrintStatus then D.PrintStatus() else print(L.PREFIX_ERR .. "Diag missing") end
            elseif msg == "debug selftest" then
                local D = _G.DecorLumberProfitDiag
                if D and D.PrintSelfTest then D.PrintSelfTest() else print(L.PREFIX_ERR .. "Diag missing") end
            elseif msg == "debug skipped" then
                -- Поимённый список рецептов, пропущенных как непродаваемые
                -- (вместо голого счётчика "пропущено N" в статусе скана).
                local C = _G.DecorLumberProfitCore
                if C and C.FindWoodRecipesInActiveWindow and C.LastSkipped then
                    local _, serr, smeta = C:FindWoodRecipesInActiveWindow()
                    local sk = C:LastSkipped()
                    local total = (smeta and smeta.bindSkipped) or #sk
                    print(L.PREFIX_OK .. string.format("unsellable skipped: %d, sample %d:", total, #sk))
                    for i, s in ipairs(sk) do
                        print(string.format("  %d. %s (spell %s, out %s, bind %s)",
                            i, tostring(s.name), tostring(s.spellID),
                            tostring(s.outputItemID), tostring(s.bind)))
                        if i >= 10 then break end
                    end
                    if #sk == 0 then print(L.PREFIX_OK .. tostring(serr or "none skipped")) end
                else
                    print(L.PREFIX_ERR .. "Core missing")
                end
            elseif msg == "bug" then
                local D = _G.DecorLumberProfitDiag
                if D and D.PrintBug then D.PrintBug() else print(L.PREFIX_ERR .. "Diag missing") end
            elseif msg == "debug verbose on" then
                local D = _G.DecorLumberProfitDiag
                if D and D.SetVerbose then D.SetVerbose(true) end
                print(L.PREFIX_OK .. TL("PRINT_VERBOSE_SET", "on"))
            elseif msg == "debug verbose off" then
                local D = _G.DecorLumberProfitDiag
                if D and D.SetVerbose then D.SetVerbose(false) end
                print(L.PREFIX_OK .. TL("PRINT_VERBOSE_SET", "off"))
            elseif msg == "debug set bruteforce on" or msg == "debug set bruteforce off" then
                local on = (msg == "debug set bruteforce on")
                _G.DecorLumberProfitConfig = _G.DecorLumberProfitConfig or {}
                _G.DecorLumberProfitConfig.SCAN = _G.DecorLumberProfitConfig.SCAN or {}
                _G.DecorLumberProfitConfig.SCAN.ENABLE_BRUTEFORCE = on
                -- персист: переживает /reload (применяется в Store.Upgrade)
                if DecorLumberProfitDB and DecorLumberProfitDB.settings then
                    DecorLumberProfitDB.settings.scan = DecorLumberProfitDB.settings.scan or {}
                    DecorLumberProfitDB.settings.scan.bruteforce = on
                end
                print(L.PREFIX_OK .. TL("PRINT_SCAN_SET", "bruteforce", on and "on" or "off"))
            elseif msg:find("^debug set maxscan") then
                local n = tonumber(msg:match("^debug set maxscan%s+(%d+)"))
                if n and n >= 50 and n <= 5000 then
                    _G.DecorLumberProfitConfig = _G.DecorLumberProfitConfig or {}
                    _G.DecorLumberProfitConfig.SCAN = _G.DecorLumberProfitConfig.SCAN or {}
                    _G.DecorLumberProfitConfig.SCAN.MAX_RESULTS = n
                    if DecorLumberProfitDB and DecorLumberProfitDB.settings then
                        DecorLumberProfitDB.settings.scan = DecorLumberProfitDB.settings.scan or {}
                        DecorLumberProfitDB.settings.scan.maxscan = n
                    end
                    print(L.PREFIX_OK .. TL("PRINT_SCAN_SET", "maxscan", tostring(n)))
                else
                    print(L.PREFIX_ERR .. L.PRINT_MAXSCAN_USAGE)
                end
            else
                UI.Toggle()
            end
        end
        print(L.PREFIX_OK .. TL("PRINT_LOADED", #(DecorLumberProfitConfig.WOOD_ITEM_IDS or {})))

    elseif event == "PLAYER_LOGIN" then
        if DecorLumberProfitPrices and DecorLumberProfitPrices.InitializeRealm then
            DecorLumberProfitPrices.InitializeRealm()
        end
        -- Грузим накопленную ОБЩУЮ базу аккаунта (все персонажи) и обновляем learned под текущего
        local saved = DecorLumberProfitCore:LoadSavedRecipes()
        if saved and #saved > 0 then
            UI._currentRecipes = saved
            pcall(function() DecorLumberProfitCore:RefreshLearnedFlags(UI._currentRecipes) end)
            table.sort(UI._currentRecipes, function(a, b) return (a.name or "") < (b.name or "") end)
        end
        UI._loadedFromDB = true

    elseif event == "NEW_RECIPE_LEARNED" then
        local recipeID = arg1
        local recipeLevel = arg2
        if DecorLumberProfitCore and DecorLumberProfitCore.RememberRecipe then
            DecorLumberProfitCore:RememberRecipe(recipeID, recipeLevel)
        end
        -- Событие несёт recipeID (9.0.1+, НЕ recipeSpellID-ключ базы), поэтому
        -- прямой MarkLearnedBy промахивается; ApplyLearnedByEvent мэппит оба
        -- неймспейса и помечает запись в памяти и в DB — иначе выученное
        -- не переживает сессию. Refresh ниже — страховка для живых API-данных.
        if DecorLumberProfitCore and DecorLumberProfitCore.ApplyLearnedByEvent then
            pcall(function() DecorLumberProfitCore:ApplyLearnedByEvent(UI._currentRecipes, recipeID) end)
        end
        pcall(function() DecorLumberProfitCore:RefreshLearnedFlags(UI._currentRecipes) end)
        if UI._mainFrame and UI._mainFrame:IsShown() then
            C_Timer.After(0.5, function() UI.RebuildRecipeList(false) end)
        end

    elseif event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
        -- Запоминаем активный skillLine для кнопки «Обновить рецепты»
        if C_TradeSkillUI and C_TradeSkillUI.GetProfessionChildSkillLineID and DecorLumberProfitCore and DecorLumberProfitCore.SetActiveSkillLineID then
            local sid = nil
            local ok, val = pcall(C_TradeSkillUI.GetProfessionChildSkillLineID)
            if ok and type(val) == "number" and val ~= 0 then sid = val end
            if sid then DecorLumberProfitCore:SetActiveSkillLineID(sid) end
        end
        -- Пассивно кэшируем изученные рецепты даже когда окно закрыто
        if DecorLumberProfitCore and DecorLumberProfitCore.ScanAndRememberCurrentProfession then
            pcall(DecorLumberProfitCore.ScanAndRememberCurrentProfession, DecorLumberProfitCore)
        end
        -- Авто-добавление убрано: пользователь сам нажимает «Обновить рецепты», таблица только накапливает
    elseif event == "TRADE_SKILL_SHOW" then
        if C_TradeSkillUI and C_TradeSkillUI.GetProfessionChildSkillLineID and DecorLumberProfitCore and DecorLumberProfitCore.SetActiveSkillLineID then
            local ok, val = pcall(C_TradeSkillUI.GetProfessionChildSkillLineID)
            if ok and type(val) == "number" and val ~= 0 then DecorLumberProfitCore:SetActiveSkillLineID(val) end
        end
        -- Подсказка если окно LP открыто
        if UI._mainFrame and UI._mainFrame:IsShown() then
            UI.SetStatus(L.ST_PROF_WINDOW_FOUND, 0.6, 1, 0.6)
        end
    elseif event == "TRADE_SKILL_CLOSE" then
        -- skillLine остаётся запомненным до следующего открытия

    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- arg1=itemID, arg2=success. Если данных о предмете нет — убираем ждуны по нему.
        if arg2 == false then DecorLumberProfitCore:FailPendingForItem(arg1) end
        -- Предмет догрузился с сервера: проверяем отложенные рецепты (bindType был неизвестен)
        local resolved = DecorLumberProfitCore:ResolvePendingBind()
        if resolved and #resolved > 0 then
            -- Холодный старт: записи подняты из DB со stale-флагами learned
            -- (при логине LoadSavedRecipes паркует их в pending и Refresh пропускается).
            -- Сверяем с живым API ДО сохранения, иначе «нет» застревает между сессиями.
            -- API не ответил (nil) — Refresh ничего не трогает, stale сохраняется.
            pcall(function() DecorLumberProfitCore:RefreshLearnedFlags(resolved) end)
            local existing = UI.BuildExistingSet(UI._currentRecipes)
            local added = 0
            for _, rec in ipairs(resolved) do
                local ser = DecorLumberProfitCore:SaveRecipe(rec)
                if ser then rec.learnedBy = ser.learnedBy end
                if not existing[rec.recipeSpellID] then
                    table.insert(UI._currentRecipes, rec)
                    existing[rec.recipeSpellID] = true
                    added = added + 1
                end
            end
            if added > 0 then
                if UI._mainFrame and UI._mainFrame:IsShown() then UI.RefreshTable() end
                print(L.PREFIX_OK .. TL("PRINT_ITEMS_RESOLVED", added))
            end
        end
    end
end)
