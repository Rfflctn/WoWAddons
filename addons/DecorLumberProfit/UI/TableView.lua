-- UI/TableView.lua | DecorLumberProfit | Retail 12.1.0
-- Таблица рецептов (Этап 8): колонки, сортировка, строки, RefreshTable.
-- Состояние — в UI.lua (UI._x). Чистая математика видимости — UI.VisibleRange (тесты).

local UI = _G.DecorLumberProfitUI or {}
local L = DecorLumberProfitL10n.L
local TL = DecorLumberProfitL10n.TL

-- Общее описание колонок таблицы (ширины для заголовка и строк)
-- Порядок = порядок в таблице. ahQty — конкуренция: сколько штук/лотів output на АХ.
local COLUMNS = {
    { key = "recipe",       width = 150 },
    { key = "prof",         width = 54 }, -- иконка-кнопка (клик — открыть профу); имя — в тултипе
    { key = "learned",      width = 110, align = "CENTER" }, -- имена персонажей (п.1), поэтому шире
    { key = "wood",         width = 120 },
    { key = "sellPrice",    width = 85 },
    { key = "ahQty",        width = 55,  align = "CENTER" }, -- по заголовку «На АХ» (п.3)
    { key = "ahMineQty",    width = 55,  align = "CENTER" }, -- по заголовку «Мои» (п.3)
    { key = "woodQty",      width = 45,  align = "CENTER" },
    { key = "maxWoodPrice", width = 100 },
    { key = "profit",       width = 100 },
}
UI.COLUMNS = COLUMNS -- читает MainFrame для шапки

-- ==== Видимость колонок (чекбоксы «Столбцы», персист в DB.settings.hiddenColumns) ====
-- UI._hiddenColumns: { [key] = true } — скрытые. nil/отсутствие = видимая.
function UI.IsColumnVisible(key)
    local h = UI._hiddenColumns
    if h and h[key] then return false end
    return true
end

function UI.GetVisibleColumns()
    local out = {}
    for _, c in ipairs(COLUMNS) do
        if UI.IsColumnVisible(c.key) then out[#out + 1] = c end
    end
    if #out == 0 then out[1] = COLUMNS[1] end -- страховка: хоть что-то рисуем
    return out
end

local function IsKnownColumn(key)
    for _, c in ipairs(COLUMNS) do if c.key == key then return true end end
    return false
end

-- Загружает скрытые колонки из SavedVariables (вызывает Commands при ADDON_LOADED).
-- Невалидные ключи (от старых версий) молча отбрасываем.
function UI.LoadColumnVisibility()
    UI._hiddenColumns = {}
    local saved = DecorLumberProfitDB and DecorLumberProfitDB.settings and DecorLumberProfitDB.settings.hiddenColumns
    if type(saved) == "table" then
        for k, v in pairs(saved) do
            if v and IsKnownColumn(k) then UI._hiddenColumns[k] = true end
        end
    end
end

local function PersistColumnVisibility()
    if DecorLumberProfitDB and DecorLumberProfitDB.settings then
        local t = {}
        for k, v in pairs(UI._hiddenColumns or {}) do
            if v and IsKnownColumn(k) then t[k] = true end
        end
        DecorLumberProfitDB.settings.hiddenColumns = t
    end
end

-- Показать/скрыть колонку + перераскладка (шапка, пул строк, Refresh).
-- Возвращает true при успехе, false если ключ неизвестен или пытаются скрыть последнюю.
function UI.SetColumnVisible(key, visible)
    if not IsKnownColumn(key) then return false end
    UI._hiddenColumns = UI._hiddenColumns or {}
    if visible then
        if not UI._hiddenColumns[key] then return true end
        UI._hiddenColumns[key] = nil
    else
        if UI._hiddenColumns[key] then return true end
        -- Нельзя скрыть последнюю видимую колонку
        local n = 0
        for _, c in ipairs(COLUMNS) do
            if c.key ~= key and UI.IsColumnVisible(c.key) then n = n + 1 end
        end
        if n == 0 then
            UI.SetStatus(DecorLumberProfitL10n.L.ST_AT_LEAST_ONE_COLUMN, 1, 0.7, 0.2)
            if UI.RefreshColumnsPanel then UI.RefreshColumnsPanel() end
            return false
        end
        UI._hiddenColumns[key] = true
    end
    PersistColumnVisibility()
    if UI.LayoutHeaderCells then UI.LayoutHeaderCells() end
    if UI._rows then
        for _, row in ipairs(UI._rows) do
            if row.Hide then
                local ok = pcall(row.Hide, row)
                if not ok then break end
            end
        end
        if table.wipe then table.wipe(UI._rows) else UI._rows = {} end
    end
    UI._lastRowCount = nil
    local sf = UI._scrollFrame
    if sf and sf.SetVerticalScroll then pcall(sf.SetVerticalScroll, sf, 0) end
    if UI.RefreshColumnsPanel then UI.RefreshColumnsPanel() end
    if UI._mainFrame then UI.RefreshTable() end
    return true
end

-- Показать все колонки (кнопка «Показать все» в панели).
function UI.ResetColumns()
    UI._hiddenColumns = {}
    PersistColumnVisibility()
    if UI.LayoutHeaderCells then UI.LayoutHeaderCells() end
    if UI._rows then
        for _, row in ipairs(UI._rows) do
            if row.Hide then pcall(row.Hide, row) end
        end
        if table.wipe then table.wipe(UI._rows) else UI._rows = {} end
    end
    UI._lastRowCount = nil
    if UI.RefreshColumnsPanel then UI.RefreshColumnsPanel() end
    if UI._mainFrame then UI.RefreshTable() end
end

UI.BASE_WIDTH = DecorLumberProfitConfig.UI.WIDTH -- базовая ширина для масштаба колонок (Этап 9)
UI._colScale = 1

-- Эффективные ширины колонок при текущем масштабе (ресайз окна)
function UI.LayoutColumns()
    local w = UI._colWidths or {}
    for _, c in ipairs(COLUMNS) do
        w[c.key] = math.max(30, math.floor(c.width * (UI._colScale or 1)))
    end
    UI._colWidths = w
    return w
end
UI.LayoutColumns()

function UI.ColWidth(key, fallback)
    local ws = UI._colWidths
    if ws and ws[key] then return ws[key] end
    return fallback
end

-- Ширина области таблицы: по текущему окну, иначе по конфигу
local function TableWidth()
    local mf = UI._mainFrame
    if mf and mf.GetWidth then
        local ok, w = pcall(mf.GetWidth, mf)
        if ok and type(w) == "number" and w > 0 then return w - 30 end
    end
    return DecorLumberProfitConfig.UI.WIDTH - 30
end

-- Чистая математика видимого окна (Этап 9, тесты: test_tableview.py).
-- Возвращает first (1-based), count с учётом overscan-запаса.
function UI.VisibleRange(scrollOffset, viewHeight, total, rowH, overscan)
    overscan = overscan or 3
    total = total or 0
    rowH = rowH or 20
    if total <= 0 then return 1, 0 end
    local first = math.floor(math.max(0, scrollOffset or 0) / rowH) + 1
    if first > total then first = total end
    local count = math.ceil((viewHeight or 0) / rowH) + overscan
    if count < 1 then count = 1 end
    count = math.min(count, total - first + 1)
    return first, count
end

-- ==== Колонка профессии: иконка + открытие по клику ====
-- Иконка — статичная карта Recipes.GetProfessionIcon (ProfessionInfo иконки не содержит).
-- Возвращает путь текстуры или nil (звать показывает "?"). Гарды: без Recipes — nil.
function UI.GetProfessionIcon(nameOrRec)
    local R = _G.DecorLumberProfitRecipes
    if R and R.GetProfessionIcon then
        local ok, path = pcall(R.GetProfessionIcon, nameOrRec)
        if ok and type(path) == "string" and path ~= "" then return path end
    end
    return nil
end

-- Ищет skillLineID профессии рецепта среди линий персонажа.
-- Матч: professionID -> parentProfessionID -> нормализованное имя. Побочек нет.
-- Возвращает список (может быть пустым). Порядок — порядок клиента.
function UI.FindProfessionSkillLines(rec)
    local out = {}
    if type(rec) ~= "table" then return out end
    local TS = C_TradeSkillUI
    if not (TS and TS.GetAllProfessionTradeSkillLines and TS.GetProfessionInfoBySkillLineID) then return out end
    local ok, lines = pcall(TS.GetAllProfessionTradeSkillLines)
    if not ok or type(lines) ~= "table" or #lines == 0 then return out end
    local R = _G.DecorLumberProfitRecipes
    local function norm(name)
        if type(name) ~= "string" then return nil end
        if R and R.NormalizeProfessionName then
            local nOk, n = pcall(R.NormalizeProfessionName, name)
            if nOk and type(n) == "string" then return n end
        end
        return name
    end
    local wantName = norm(rec.profession)
    for _, sid in ipairs(lines) do
        if type(sid) == "number" and sid ~= 0 then
            local iOk, info = pcall(TS.GetProfessionInfoBySkillLineID, sid)
            if iOk and type(info) == "table" then
                local hit = false
                if rec.professionID and info.professionID == rec.professionID then hit = true end
                if not hit and rec.parentProfessionID
                    and (info.professionID == rec.parentProfessionID
                        or info.parentProfessionID == rec.parentProfessionID) then
                    hit = true
                end
                if not hit and wantName
                    and norm(info.parentProfessionName or info.professionName) == wantName then
                    hit = true
                end
                if hit then out[#out + 1] = sid end
            end
        end
    end
    return out
end

function UI.FindProfessionSkillLine(rec)
    local list = UI.FindProfessionSkillLines(rec)
    return list[1]
end

-- Кандидаты для C_TradeSkillUI.OpenTradeSkill (по приоритету, без дублей).
-- ВАЖНО: OpenTradeSkill принимает классический ID профессии (164/165/171...),
-- а НЕ expansion-вариант skillLine (напр. 2907 -> всегда false). Поэтому первым
-- идёт GetProfessionSkillLineID(Enum) — рекомендованный Blizzard путь.
function UI.ProfessionOpenCandidates(rec)
    local ids, seen = {}, {}
    local function add(id)
        if type(id) == "number" and id ~= 0 and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    if type(rec) ~= "table" then return ids end
    local TS = C_TradeSkillUI
    if TS and TS.GetProfessionSkillLineID and rec.professionEnum then
        local ok, sid = pcall(TS.GetProfessionSkillLineID, rec.professionEnum)
        if ok then add(sid) end
    end
    add(rec.professionID)
    add(rec.parentProfessionID)
    local R = _G.DecorLumberProfitRecipes
    if R and R.GetClassicProfessionID and type(rec.profession) == "string" then
        local ok, cid = pcall(R.GetClassicProfessionID, rec.profession)
        if ok then add(cid) end
    end
    for _, sid in ipairs(UI.FindProfessionSkillLines(rec)) do add(sid) end
    return ids
end

-- Есть ли чем пробовать открыть (для хинта иконки). Побочек нет.
function UI.CanOpenProfession(rec)
    return #UI.ProfessionOpenCandidates(rec) > 0
end

local function ProfessionsFrameShown()
    local pf = _G.ProfessionsFrame
    if pf and pf.IsShown then
        local ok, v = pcall(pf.IsShown, pf)
        if ok then return v and true or false end
    end
    return nil
end

-- Открывает окно профессии рецепта (клик по иконке).
-- Не изучена этим персонажем -> молча noop (штатный кейс, без WARN).
-- Изучена, но ни один кандидат не сработал -> статус + WARN в Diag со списком проб.
function UI.OpenProfession(rec)
    if type(rec) ~= "table" then return false end
    local TS = C_TradeSkillUI
    if not (TS and TS.OpenTradeSkill) then
        local D = _G.DecorLumberProfitDiag
        if D and D.Log then pcall(D.Log, "WARN", "prof", "OpenTradeSkill API missing") end
        UI.SetStatus(L.ST_PROF_OPEN_FAIL, 1, 0.7, 0.2)
        return false
    end
    local learned = #UI.FindProfessionSkillLines(rec) > 0
    local candidates = UI.ProfessionOpenCandidates(rec)
    local tried = {}
    for _, id in ipairs(candidates) do
        tried[#tried + 1] = tostring(id)
        local ok, opened = pcall(TS.OpenTradeSkill, id)
        if ok and opened then return true end
    end
    -- Последний шанс: открыть конкретный рецепт (тянет окно профы за собой).
    if TS.OpenRecipe then
        for _, rid in ipairs({ rec.recipeID, rec.recipeSpellID }) do
            if type(rid) == "number" then
                tried[#tried + 1] = "recipe:" .. tostring(rid)
                local ok = pcall(TS.OpenRecipe, rid)
                if ok and ProfessionsFrameShown() then return true end
            end
        end
    end
    if not learned then
        return false -- не изучена этим персонажем — noop по дизайну (в т.ч. рецепты др. персов)
    end
    local D = _G.DecorLumberProfitDiag
    if D and D.Log then
        pcall(D.Log, "WARN", "prof", "open failed rec=%s tried=%s",
            tostring(rec.recipeSpellID), table.concat(tried, ","))
    end
    UI.SetStatus(L.ST_PROF_OPEN_FAIL, 1, 0.7, 0.2)
    return false
end

-- ==== Колонка рецепта: ссылка (клик — открыть, Shift+клик — аукцион) ====
-- Клик открывает рецепт в окне профессии (C_TradeSkillUI.OpenRecipe по
-- rec.recipeID, фолбэк rec.recipeSpellID, затем UI.OpenProfession).
-- Shift+клик при открытом аукционе линкует крафтовый предмет в поиск АХ
-- (ChatEdit_InsertLink -> SearchBox -> SendBrowseQuery, по наличию API).
-- Все вызовы WoW за pcall; провал обязательного API — WARN в Diag (п.6 AGENTS).

-- Кандидаты recipeID для C_TradeSkillUI.OpenRecipe (он принимает recipeID,
-- а НЕ recipeSpellID; в старых сейвах они могут совпадать — без дублей).
-- Чистая функция (тесты).
function UI.RecipeOpenCandidates(rec)
    local ids = {}
    if type(rec) ~= "table" then return ids end
    for _, rid in ipairs({ rec.recipeID, rec.recipeSpellID }) do
        if type(rid) == "number" and rid ~= 0 then
            local dup = false
            for _, v in ipairs(ids) do if v == rid then dup = true; break end end
            if not dup then ids[#ids + 1] = rid end
        end
    end
    return ids
end

-- Открыт ли аукцион (Midnight: AuctionHouseFrame; legacy AuctionFrame — фолбэк).
-- Побочек нет.
function UI.IsAuctionHouseShown()
    local ah = _G.AuctionHouseFrame
    if ah and ah.IsShown then
        local ok, v = pcall(ah.IsShown, ah)
        if ok and v then return true end
    end
    local legacy = _G.AuctionFrame
    if legacy and legacy.IsShown then
        local ok, v = pcall(legacy.IsShown, legacy)
        if ok and v then return true end
    end
    return false
end

-- Ссылка крафтового предмета рецепта (|Hitem:...|h) или nil (нет данных/ID).
-- Побочек нет.
function UI.GetRecipeItemLink(rec)
    if type(rec) ~= "table" then return nil end
    local itemID = rec.outputItemID
    if type(itemID) ~= "number" then return nil end
    if C_Item and C_Item.GetItemInfo then
        local ok, _, link = pcall(C_Item.GetItemInfo, itemID)
        if ok and type(link) == "string" and link ~= "" then return link end
    end
    if _G.GetItemInfo then
        local ok, _, link = pcall(_G.GetItemInfo, itemID)
        if ok and type(link) == "string" and link ~= "" then return link end
    end
    return nil
end

-- Имя крафтового предмета для поиска на АХ или nil. Побочек нет.
function UI.GetRecipeSearchText(rec)
    if type(rec) ~= "table" then return nil end
    local itemID = rec.outputItemID
    if type(itemID) ~= "number" then return nil end
    local M = _G.DecorLumberProfitItemInfo
    if M and M.GetName then
        local ok, n = pcall(M.GetName, itemID)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    if C_Item and C_Item.GetItemInfo then
        local ok, n = pcall(C_Item.GetItemInfo, itemID)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    if _G.GetItemInfo then
        local ok, n = pcall(_G.GetItemInfo, itemID)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    return nil
end

-- Линкует крафтовый предмет рецепта в поиск аукциона (Shift+клик).
-- Без открытого АХ или без предмета — статус-подсказка + false (штатный кейс).
-- Успех — true (текст в строке поиска и/или запущенный поиск).
function UI.SearchAuctionForOutput(rec)
    if type(rec) ~= "table" then return false end
    local itemID = rec.outputItemID
    if type(itemID) ~= "number" then
        UI.SetStatus(L.ST_AH_NO_ITEM, 1, 0.7, 0.2)
        return false
    end
    if not UI.IsAuctionHouseShown() then
        UI.SetStatus(L.ST_AH_NOT_OPEN, 1, 0.7, 0.2)
        return false
    end
    local link = UI.GetRecipeItemLink and UI.GetRecipeItemLink(rec) or nil
    local name = UI.GetRecipeSearchText and UI.GetRecipeSearchText(rec) or nil
    -- 1) Стандарт Blizzard: вставка ссылки в открытое поле (поиск АХ подхватывает сам).
    if type(link) == "string" and link ~= "" then
        if _G.ChatEdit_InsertLink then
            local ok, handled = pcall(_G.ChatEdit_InsertLink, link)
            if ok and handled then return true end
        end
        if _G.HandleModifiedItemClick then
            local ok, handled = pcall(_G.HandleModifiedItemClick, link)
            if ok and handled then return true end
        end
    end
    -- 2) Прямая установка текста поиска АХ (визуальная линковка) + запуск поиска.
    local searchText = (type(name) == "string" and name ~= "" and name)
        or (type(link) == "string" and link ~= "" and link) or nil
    if type(searchText) == "string" and searchText ~= "" then
        local ah = _G.AuctionHouseFrame
        local box = ah and ah.SearchBar and ah.SearchBar.SearchBox or nil
        if not box and ah and ah.SearchBar and ah.SearchBar.SetText then
            box = ah.SearchBar -- вариант сборки, где SearchBar сам EditBox
        end
        if box and box.SetText then
            local ok = pcall(box.SetText, box, searchText)
            if ok then
                if C_AuctionHouse and C_AuctionHouse.SendBrowseQuery then
                    pcall(C_AuctionHouse.SendBrowseQuery, {
                        searchString = searchText, sorts = {},
                        minLevel = nil, maxLevel = nil, filters = nil, itemClassFilters = nil,
                    })
                end
                return true
            end
        end
        -- 3) Коробки нет (другая сборка АХ), но имя есть: хотя бы запускаем поиск,
        -- чтобы стоимость была видна в результатах.
        if type(name) == "string" and name ~= "" and C_AuctionHouse and C_AuctionHouse.SendBrowseQuery then
            local ok = pcall(C_AuctionHouse.SendBrowseQuery, {
                searchString = name, sorts = {},
                minLevel = nil, maxLevel = nil, filters = nil, itemClassFilters = nil,
            })
            if ok then return true end
        end
    end
    local D = _G.DecorLumberProfitDiag
    if D and D.Log then
        pcall(D.Log, "WARN", "recipe-link", "AH link failed item=%s", tostring(itemID))
    end
    UI.SetStatus(L.ST_AH_NO_ITEM, 1, 0.7, 0.2)
    return false
end

-- Открывает рецепт в окне профессии (клик по названию).
-- Сначала точечный OpenRecipe (тянет окно + фокус на рецепте), фолбэк —
-- UI.OpenProfession (открывает окно профы; изученность/статус/WARN — там).
function UI.OpenRecipe(rec)
    if type(rec) ~= "table" then return false end
    local TS = C_TradeSkillUI
    if TS and TS.OpenRecipe then
        for _, rid in ipairs(UI.RecipeOpenCandidates(rec)) do
            pcall(TS.OpenRecipe, rid)
            if ProfessionsFrameShown() then return true end
        end
    end
    if UI.OpenProfession then
        return UI.OpenProfession(rec)
    end
    local D = _G.DecorLumberProfitDiag
    if D and D.Log then
        pcall(D.Log, "WARN", "recipe-link", "open failed rec=%s (no API)", tostring(rec.recipeSpellID))
    end
    UI.SetStatus(L.ST_RECIPE_OPEN_FAIL, 1, 0.7, 0.2)
    return false
end

-- Маршрутизация клика по названию рецепта: Shift (+открытый АХ) — поиск
-- предмета на аукционе, иначе — открыть рецепт. Возвращает результат действия.
function UI.HandleRecipeClick(rec, isShift)
    if type(rec) ~= "table" then return false end
    if isShift then
        if UI.IsAuctionHouseShown() then
            return UI.SearchAuctionForOutput(rec)
        end
        UI.SetStatus(L.ST_AH_NOT_OPEN, 1, 0.7, 0.2)
        return false
    end
    return UI.OpenRecipe(rec)
end

-- Зебра/ховер строк
local ZEBRA_EVEN  = { 0.15, 0.15, 0.15, 0.4 }
local ZEBRA_ODD   = { 0.08, 0.08, 0.08, 0.4 }
local ZEBRA_HOVER = { 0.25, 0.25, 0.10, 0.5 }

-- Обрезка краёв иконок (стандарт WoW: у текстур предметов пустая рамка 1-2px).
-- Без TexCoord иконка выглядит «мыльной» и визуально расширяет отступ колонки.
local function ApplyIconCrop(tex)
    if tex and tex.SetTexCoord then
        pcall(tex.SetTexCoord, tex, 0.08, 0.92, 0.08, 0.92)
    end
end
UI.ApplyIconCrop = ApplyIconCrop

-- Вертикальные разделители колонок: тонкая 1px линия (текстура, мышь не ловит).
local DIVIDER_COLOR = { 0.55, 0.55, 0.55, 0.28 }

-- Расставляет разделители на границах видимых колонок (зовётся из CreateRow).
-- Пул строк сносится при смене видимости/ширины/высоты, поэтому статичных
-- позиций достаточно — пересоздадутся вместе со строкой.
local function LayoutRowDividers(row, rowH)
    if not (row and row._colX) then return end
    row._dividers = row._dividers or {}
    local vis = UI.GetVisibleColumns()
    local nDiv = math.max(#vis - 1, 0)
    for i = 1, nDiv do
        local div = row._dividers[i]
        if not div then
            if row.CreateTexture then
                local ok, tex = pcall(row.CreateTexture, row, nil, "OVERLAY")
                if ok then div = tex end
            end
            row._dividers[i] = div
        end
        local boundX = vis[i + 1] and row._colX[vis[i + 1].key]
        if div and div.SetSize and type(boundX) == "number" then
            if div.SetColorTexture then
                pcall(div.SetColorTexture, div, DIVIDER_COLOR[1], DIVIDER_COLOR[2], DIVIDER_COLOR[3], DIVIDER_COLOR[4])
            end
            pcall(div.SetSize, div, 1, rowH)
            if div.ClearAllPoints and div.SetPoint then
                pcall(div.ClearAllPoints, div)
                pcall(div.SetPoint, div, "LEFT", boundX, 0)
            end
            if div.Show then pcall(div.Show, div) end
        end
    end
    for i = nDiv + 1, #row._dividers do
        local div = row._dividers[i]
        if div and div.Hide then pcall(div.Hide, div) end
    end
end

local function RowBGColor(index)
    return (index % 2 == 0) and ZEBRA_EVEN or ZEBRA_ODD
end
UI.RowBGColor = RowBGColor -- читает MainFrame? нет; экспорт для Этапа 9

local function SetRowBG(bg, color)
    bg:SetColorTexture(color[1], color[2], color[3], color[4])
end

-- Множество уже имеющихся рецептов (для append без дублей)
function UI.BuildExistingSet(recipes)
    local set = {}
    for _, r in ipairs(recipes or {}) do
        if r.recipeSpellID then set[r.recipeSpellID] = true end
    end
    return set
end

-- Обновляет заголовки колонок (стрелки сортировки)
function UI.UpdateHeaderArrows()
    if not UI.headerCells then return end
    for _, cell in ipairs(UI.headerCells) do
        local arrow = ""
        -- ASCII-маркеры: ▲▼ отсутствуют в шрифте клиента (tofu-квадрат), ^/v есть всегда
        if UI._sortKey == cell.key then arrow = UI._sortDesc and " v" or " ^" end
        cell.fs:SetText(cell.text .. arrow)
    end
end

local SORT_GETTERS = {
    recipe       = function(rec, eco) return (rec.name or ""):lower() end,
    prof         = function(rec, eco) return (rec.profession or ""):lower() end,
    learned      = function(rec, eco) return (rec.learned and 2 or (UI.HasOtherLearners(rec) and 1 or 0)) end,
    wood         = function(rec, eco) return UI.GetWoodDisplayName(rec):lower() end,
    sellPrice    = function(rec, eco) return eco.outputTotalPrice or -1 end,
    ahQty        = function(rec, eco) return eco.ahQty or -1 end,
    ahMineQty    = function(rec, eco) return eco.ahMineQty or -1 end,
    woodQty      = function(rec, eco) return rec.woodQty or 0 end,
    maxWoodPrice = function(rec, eco) return eco.maxWoodPrice or -1e18 end,
    profit       = function(rec, eco) return eco.profit or -1e18 end,
}

-- Суффикс статуса с временем последнего обновления цен: " | Цены: 12:34:56" или " | Цены: —".
-- Чистая обёртка над Prices.GetLastPriceUpdate (тестируема через подмену GetLastPriceUpdate).
function UI.PriceTimeSuffix()
    local P = _G.DecorLumberProfitPrices
    local ts = nil
    if P and P.GetLastPriceUpdate then
        local ok, v = pcall(P.GetLastPriceUpdate)
        if ok then ts = v end
    end
    if type(ts) ~= "number" then
        return L.ST_PRICES_NEVER
    end
    local timestr = nil
    if _G.date then
        local ok, s = pcall(_G.date, "%H:%M:%S", ts)
        if ok and type(s) == "string" then timestr = s end
    end
    if not timestr and os and os.date then
        local ok, s = pcall(os.date, "%H:%M:%S", ts)
        if ok and type(s) == "string" then timestr = s end
    end
    timestr = timestr or tostring(ts)
    return TL("ST_PRICES_TIME", timestr)
end

-- Формат ячейки конкуренции: только суммарно штук (лоты не показываем).
-- Чистая функция (тесты). qty/listings могут быть nil — тогда nil (звать FillRow решает dash).
-- Параметр listings оставлен для совместимости вызовов, но игнорируется.
function UI.FormatAuctionQuantity(qty, listings)
    if qty == nil and listings == nil then return nil end
    qty = tonumber(qty) or 0
    return tostring(qty)
end

-- Fallback для колонок «На АХ»/«Мои» с другого сервера (п.4): текущее значение
-- приоритетно, но если на текущем сервере данных нет — показываем первое известное
-- с другого сервера + "*" (расшифровка по серверам — в тултипе строки).
-- realms — список из Prices.GetRealmAuctionInfo, field — "qty" или "ownQty".
-- Чистая функция (тесты). Возвращает строку или nil.
function UI.FallbackRealmQuantity(realms, field)
    if type(realms) ~= "table" or (field ~= "qty" and field ~= "ownQty") then return nil end
    for _, info in ipairs(realms) do
        if type(info) == "table" and info[field] ~= nil then
            return tostring(info[field]) .. "*"
        end
    end
    return nil
end

local function SortPairs(pairs)
    local getter = UI._sortKey and SORT_GETTERS[UI._sortKey]
    if not getter then
        table.sort(pairs, function(a, b) return (a.rec.name or "") < (b.rec.name or "") end)
        return
    end
    table.sort(pairs, function(a, b)
        local va, vb = getter(a.rec, a.eco), getter(b.rec, b.eco)
        local r
        if type(va) == "string" and type(vb) == "string" then
            r = va < vb
        elseif type(va) == "number" and type(vb) == "number" then
            r = va < vb
        else
            r = tostring(va) < tostring(vb)
        end
        if UI._sortDesc then return not r and va ~= vb end
        return r
    end)
end

-- Клик по шапке: переключение ключа/направления (вызывает MainFrame)
function UI.OnHeaderClick(key)
    if UI._sortKey == key then
        UI._sortDesc = not UI._sortDesc
    else
        UI._sortKey = key
        UI._sortDesc = (key ~= "recipe" and key ~= "prof" and key ~= "wood")
    end
    UI.UpdateHeaderArrows()
    UI.RefreshTable()
end

-- ==== Высота строк (настройка /dlp rowheight, персист в DB.settings.rowHeight) ====
-- Высота тянет за собой шрифт строк и размер иконок (рецепт + профессия).
UI.BASE_ROW_HEIGHT = 20 -- база (Config.UI.ROW_HEIGHT): шрифт 12pt, иконка 18px
UI.BASE_ROW_FONT = 12
UI.MIN_ROW_HEIGHT = 16
UI.MAX_ROW_HEIGHT = 32
UI._rowHeight = nil -- override из SavedVariables (LoadRowHeight при ADDON_LOADED)

function UI.GetRowHeight()
    local h = UI._rowHeight
    if type(h) == "number" and h >= UI.MIN_ROW_HEIGHT and h <= UI.MAX_ROW_HEIGHT then
        return math.floor(h)
    end
    local cfg = _G.DecorLumberProfitConfig
    if cfg and cfg.UI and type(cfg.UI.ROW_HEIGHT) == "number" then
        return cfg.UI.ROW_HEIGHT
    end
    return UI.BASE_ROW_HEIGHT
end

-- Применяет сохранённую высоту (вызывает Commands при ADDON_LOADED). Возвращает итог.
function UI.LoadRowHeight()
    UI._rowHeight = nil
    local db = _G.DecorLumberProfitDB
    local saved = db and db.settings and db.settings.rowHeight
    if type(saved) == "number" and saved >= UI.MIN_ROW_HEIGHT and saved <= UI.MAX_ROW_HEIGHT then
        UI._rowHeight = math.floor(saved)
    end
    return UI.GetRowHeight()
end

-- Меняет высоту строк + сносит пул (строки пересоздадутся). true при успехе.
function UI.SetRowHeight(h)
    h = tonumber(h)
    if not h then return false end
    h = math.floor(h)
    if h < UI.MIN_ROW_HEIGHT or h > UI.MAX_ROW_HEIGHT then return false end
    UI._rowHeight = h
    local db = _G.DecorLumberProfitDB
    if db and db.settings then db.settings.rowHeight = h end
    if UI._rows then
        for _, row in ipairs(UI._rows) do
            if row.Hide then pcall(row.Hide, row) end
        end
        if table.wipe then table.wipe(UI._rows) else UI._rows = {} end
    end
    UI._lastRowCount = nil
    local sf = UI._scrollFrame
    if sf and sf.SetVerticalScroll then pcall(sf.SetVerticalScroll, sf, 0) end
    if UI.RefreshRowHeightLabel then UI.RefreshRowHeightLabel() end
    if UI._mainFrame then UI.RefreshTable() end
    return true
end

-- Размер иконок строки (рецепт + профессия): высота строки минус паддинг (20 -> 18).
function UI.RowIconSize()
    return math.max(12, UI.GetRowHeight() - 2)
end

-- Обновляет цифру степпера в футере (если окно создано). Зовётся из SetRowHeight.
function UI.RefreshRowHeightLabel()
    local fs = UI._rowHeightLabel
    if fs and fs.SetText then pcall(fs.SetText, fs, tostring(UI.GetRowHeight())) end
end

-- Масштабирует шрифт строки под высоту (база 12pt при 20px). Без клиента/шрифта — noop.
local _rowFontPath, _rowFontFlags
local function ApplyRowFont(fs)
    if not (fs and fs.SetFont) then return end
    if not _rowFontPath then
        local gf = _G.GameFontHighlightSmall
        if gf and gf.GetFont then
            local ok, path, _, flags = pcall(gf.GetFont, gf)
            if ok and type(path) == "string" then
                _rowFontPath, _rowFontFlags = path, flags
            end
        end
    end
    if _rowFontPath then
        local size = UI.BASE_ROW_FONT * UI.GetRowHeight() / UI.BASE_ROW_HEIGHT
        pcall(fs.SetFont, fs, _rowFontPath, size, _rowFontFlags)
    end
end

-- Создаёт строку таблицы (позиция выставляется при рендере — пул переиспользуется, Этап 9)
-- Учитывает только видимые колонки (панель «Столбцы»); при смене видимости пул сносится.
local function CreateRow(parent, width)
    local ROW_H = UI.GetRowHeight()
    local ICON_SZ = UI.RowIconSize() -- только для иконки профессии (у рецепта иконки нет, п.2)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, ROW_H)
    row._dataIndex = 0

    row.cols = {}
    row._colX = {}
    local x = 0
    for _, c in ipairs(UI.GetVisibleColumns()) do
        local cw = UI.ColWidth(c.key, c.width)
        row._colX[c.key] = x
        if c.key == "recipe" then
            -- Ссылка рецепта: клик — открыть в профе, Shift+клик — поиск на АХ.
            -- Кнопка с текстом от края колонки (иконки нет, как шапка).
            local btn = CreateFrame("Button", nil, row)
            btn:SetPoint("LEFT", x + 2, 0)
            btn:SetSize(math.max(cw - 4, 20), ROW_H)
            local rfs = nil
            if btn.CreateFontString then
                local ok, f = pcall(btn.CreateFontString, btn, nil, "OVERLAY", "GameFontHighlightSmall")
                if ok and f then rfs = f end
            end
            if rfs then
                if rfs.SetPoint then pcall(rfs.SetPoint, rfs, "LEFT", 0, 0) end
                if rfs.SetSize then pcall(rfs.SetSize, rfs, math.max(cw - 6, 20), ROW_H) end
                if rfs.SetJustifyH then pcall(rfs.SetJustifyH, rfs, c.align or "LEFT") end
                if rfs.SetWordWrap then pcall(rfs.SetWordWrap, rfs, false) end
                ApplyRowFont(rfs)
                btn._fs = rfs
            end
            btn._rec = nil
            btn._row = row
            if btn.RegisterForClicks then pcall(btn.RegisterForClicks, btn, "LeftButtonUp") end
            if btn.SetScript then
                pcall(btn.SetScript, btn, "OnClick", function(self)
                    local shift = false
                    if _G.IsShiftKeyDown then
                        local ok, v = pcall(_G.IsShiftKeyDown)
                        if ok and v then shift = true end
                    end
                    if not shift and _G.IsModifiedClick then
                        local ok, v = pcall(_G.IsModifiedClick, "CHATLINK")
                        if ok and v then shift = true end
                    end
                    UI.HandleRecipeClick(self._rec, shift)
                end)
                pcall(btn.SetScript, btn, "OnEnter", function(self)
                    if type(self._rec) ~= "table" then return end
                    local r = self._row
                    if r and r._bg then SetRowBG(r._bg, ZEBRA_HOVER) end
                    local di = (r and r._dataIndex) or 0
                    UI.ShowRowTooltip(self, di)
                    GameTooltip:AddLine(L.TIP_RECIPE_OPEN_HINT, 0.6, 0.9, 0.6)
                    if UI.IsAuctionHouseShown and UI.IsAuctionHouseShown() then
                        GameTooltip:AddLine(L.TIP_RECIPE_AH_HINT, 1, 0.82, 0)
                    end
                    GameTooltip:Show()
                    if self._fs and self._fs.SetTextColor then
                        pcall(self._fs.SetTextColor, self._fs, 1, 0.82, 0)
                    end
                end)
                pcall(btn.SetScript, btn, "OnLeave", function(self)
                    local r = self._row
                    local stillOver = false
                    if r and r.IsMouseOver then
                        local ok, v = pcall(r.IsMouseOver, r)
                        if ok and v then stillOver = true end
                    end
                    if not stillOver and r and r._bg and r._dataIndex then
                        SetRowBG(r._bg, RowBGColor(r._dataIndex))
                    end
                    GameTooltip:Hide()
                    if self._fs and self._fs.SetTextColor then
                        pcall(self._fs.SetTextColor, self._fs, 1, 1, 1)
                    end
                end)
            end
            row.cols[c.key] = btn
        elseif c.key == "prof" then
            -- Иконка-кнопка профессии: клик открывает окно (если изучена), ховер — имя + подсказка
            local btn = CreateFrame("Button", nil, row)
            btn:SetPoint("LEFT", x + 1, 0)
            btn:SetSize(math.max(cw - 2, 20), ROW_H)
            local tex = btn:CreateTexture(nil, "OVERLAY")
            tex:SetSize(ICON_SZ, ICON_SZ)
            tex:SetPoint("CENTER", 0, 0)
            ApplyIconCrop(tex)
            tex:Hide()
            btn._icon = tex
            local fb = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fb:SetPoint("CENTER", 0, 0)
            fb:SetJustifyH("CENTER")
            fb:SetText(L.CELL_PROF_UNKNOWN)
            fb:Hide()
            ApplyRowFont(fb)
            btn._fallback = fb
            btn._rec = nil
            btn:RegisterForClicks("LeftButtonUp")
            btn:SetScript("OnClick", function(self)
                UI.OpenProfession(self._rec)
            end)
            btn:SetScript("OnEnter", function(self)
                local rec = self._rec
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                local pname = (type(rec) == "table" and rec.profession) or nil
                GameTooltip:AddLine(pname or L.CELL_PROF_UNKNOWN, 1, 1, 1)
                if UI.CanOpenProfession and UI.CanOpenProfession(rec) then
                    GameTooltip:AddLine(L.TIP_PROF_OPEN_HINT, 0.6, 0.9, 0.6)
                else
                    GameTooltip:AddLine(L.TIP_PROF_NOT_LEARNED, 0.7, 0.7, 0.7)
                end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.cols[c.key] = btn
        else
            -- Текстовая ячейка: отступ 2 от края колонки (иконки у рецепта нет, п.2 —
            -- текст идёт как шапка, без пустого места слева).
            local off = 2
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", x + off, 0)
            fs:SetSize(cw - off - 2, ROW_H)
            fs:SetJustifyH(c.align or "LEFT")
            fs:SetWordWrap(false)
            ApplyRowFont(fs)
            row.cols[c.key] = fs
        end
        x = x + cw
    end

    -- Фон зебры
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    SetRowBG(bg, ZEBRA_ODD)
    row._bg = bg
    -- Вертикальные разделители между столбцами (поверх фона, под текстом по уровню OVERLAY)
    LayoutRowDividers(row, ROW_H)
    -- Ховер
    row:SetScript("OnEnter", function(self)
        SetRowBG(bg, ZEBRA_HOVER)
        UI.ShowRowTooltip(self, self._dataIndex)
    end)
    row:SetScript("OnLeave", function(self)
        SetRowBG(bg, RowBGColor(self._dataIndex))
        GameTooltip:Hide()
    end)
    return row
end

-- Пул строк: создаём по потребности, лишние прячем (Этап 9: виртуализация)
local function EnsurePool(n)
    local rows = UI._rows
    local width = TableWidth()
    for i = 1, n do
        if not rows[i] then
            rows[i] = CreateRow(UI._scrollChild, width)
        end
    end
    for i = n + 1, #rows do rows[i]:Hide() end
end

-- Заполнение одной строки данными (позиция — по dataIndex, не по месту в пуле)
-- Все обращения к row.cols.* за гардами: колонка может быть скрыта через панель «Столбцы».
local function FillRow(row, p, dataIndex)
    local ROW_H = UI.GetRowHeight()
    row._dataIndex = dataIndex
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -(dataIndex - 1) * ROW_H)
    if row._bg then SetRowBG(row._bg, RowBGColor(dataIndex)) end
    local rec, eco = p.rec, p.eco
    -- Рецепт-ссылка (кнопка): текст от края колонки, клик — открыть, Shift+клик — АХ
    if row.cols.recipe then
        local cell = row.cols.recipe
        local txt = rec.name or ("#" .. (rec.recipeSpellID or "?"))
        if cell._fs and cell._fs.SetText then
            pcall(cell._fs.SetText, cell._fs, txt)
            if cell._fs.SetTextColor then pcall(cell._fs.SetTextColor, cell._fs, 1, 1, 1) end
        elseif cell.SetText then
            pcall(cell.SetText, cell, txt)
        end
        cell._rec = rec
    end

    -- Профессия: иконка-кнопка (клик — открыть, если изучена). Имя — в тултипе иконки и строки.
    if row.cols.prof then
        local btn = row.cols.prof
        btn._rec = rec
        local path = UI.GetProfessionIcon and UI.GetProfessionIcon(rec) or nil
        if btn._icon and btn._fallback then
            if path then
                btn._icon:SetTexture(path)
                ApplyIconCrop(btn._icon)
                btn._icon:Show()
                btn._fallback:Hide()
            else
                btn._icon:Hide()
                btn._fallback:SetText(L.CELL_PROF_UNKNOWN)
                btn._fallback:Show()
            end
        elseif btn.SetText then
            pcall(btn.SetText, btn, rec.profession or L.CELL_PROF_UNKNOWN)
        end
    end

    -- Изучен: имена персонажей, знающих рецепт (п.1; фолбэки — да/нет/? для legacy)
    if row.cols.learned then
        if UI.FormatLearnedCell then
            row.cols.learned:SetText(UI.FormatLearnedCell(rec))
        elseif rec.learned == true then
            row.cols.learned:SetText(L.CELL_YES)
        elseif UI.HasOtherLearners and UI.HasOtherLearners(rec) then
            row.cols.learned:SetText(L.CELL_OTHER)
        elseif rec.learned == false then
            row.cols.learned:SetText(L.CELL_NO)
        else
            row.cols.learned:SetText(L.CELL_UNKNOWN)
        end
    end

    -- Используемая древесина
    if row.cols.wood then
        row.cols.wood:SetText(UI.GetWoodDisplayName(rec))
    end

    -- Цена продажи
    if row.cols.sellPrice then
        if eco.outputUnitPrice then
            -- Показываем цену за штуку и суммарную
            if rec.outputQty > 1 then
                row.cols.sellPrice:SetText(UI.GetMoneyStr(eco.outputUnitPrice) .. " / " .. UI.GetMoneyStr(eco.outputTotalPrice))
            else
                row.cols.sellPrice:SetText(UI.GetMoneyStr(eco.outputUnitPrice))
            end
        else
            row.cols.sellPrice:SetText(L.CELL_NO_AH)
        end
    end

    -- Конкуренция: сколько штук output выложено на АХ.
    -- nil (не сканировали текущий сервер) — fallback с другого сервера + "*"
    -- (п.4, хранение realm-scoped как у цены); совсем нет данных — dash.
    -- 0 (пустой АХ, noauction) — "0".
    if row.cols.ahQty then
        local txt = UI.FormatAuctionQuantity(eco.ahQty, eco.ahListings)
        if txt then
            row.cols.ahQty:SetText(txt)
        else
            local fb = UI.FallbackRealmQuantity and UI.FallbackRealmQuantity(eco.ahRealms, "qty") or nil
            if fb then
                row.cols.ahQty:SetText(fb)
            else
                row.cols.ahQty:SetText(L.CELL_DASH)
            end
        end
    end

    -- Наши предметы: сначала текущий сервер (сумма снимков всех персонажей
    -- аккаунта на нём). Если снимков текущего сервера нет — значение с другого
    -- сервера + "*" (п.4); dash означает, что ни один снимок ещё не получен нигде.
    if row.cols.ahMineQty then
        if eco.ahMineQty ~= nil then
            row.cols.ahMineQty:SetText(tostring(eco.ahMineQty))
        else
            local fb = UI.FallbackRealmQuantity and UI.FallbackRealmQuantity(eco.ahRealms, "ownQty") or nil
            if fb then
                row.cols.ahMineQty:SetText(fb)
            else
                row.cols.ahMineQty:SetText(L.CELL_DASH)
            end
        end
    end

    if row.cols.woodQty then
        row.cols.woodQty:SetText(tostring(eco.woodQty or rec.woodQty or 0))
    end

    if row.cols.maxWoodPrice then
        if eco.maxWoodPrice then
            if eco.maxWoodPrice < 0 then
                row.cols.maxWoodPrice:SetText("|cffff0000" .. UI.GetMoneyStr(eco.maxWoodPrice) .. "|r")
            else
                row.cols.maxWoodPrice:SetText(UI.GetMoneyStr(eco.maxWoodPrice))
            end
        else
            row.cols.maxWoodPrice:SetText(L.CELL_DASH)
        end
    end

    if row.cols.profit then
        if eco.profit then
            local col = eco.profit > 0 and "|cff00ff00" or (eco.profit < 0 and "|cffff0000" or "|cffffff00")
            row.cols.profit:SetText(col .. UI.GetMoneyStr(eco.profit) .. "|r")
        else
            row.cols.profit:SetText(L.CELL_DASH)
        end
    end
end

-- Пустое состояние: одна строка с сообщением (в первой видимой колонке)
local function RenderEmpty(msg)
    EnsurePool(1)
    local rows = UI._rows
    local row = rows[1]
    row._dataIndex = 1
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, 0)
    if row._bg then SetRowBG(row._bg, ZEBRA_ODD) end
    for _, fs in pairs(row.cols) do
        if fs._fs and fs._fs.SetText then
            pcall(fs._fs.SetText, fs._fs, "")
        elseif fs.SetText then
            pcall(fs.SetText, fs, "")
        end
        if fs._icon then fs._icon:Hide() end
        if fs._fallback then fs._fallback:Hide() end
        fs._rec = nil
    end
    local vis = UI.GetVisibleColumns()
    local firstKey = vis[1] and vis[1].key or "recipe"
    local function SetEmptyText(cell)
        if not cell then return end
        if cell._fs and cell._fs.SetText then
            pcall(cell._fs.SetText, cell._fs, msg)
        elseif cell.SetText then
            pcall(cell.SetText, cell, msg)
        end
    end
    if row.cols[firstKey] then
        SetEmptyText(row.cols[firstKey])
    elseif row.cols.recipe then
        SetEmptyText(row.cols.recipe)
    end
    row:Show()
    for i = 2, #rows do rows[i]:Hide() end
end

-- Рендер видимого окна (Этап 9): только строки в вьюпорте + overscan.
-- Фолбэк без известной высоты — рендерим всё (как до виртуализации).
function UI.RenderVisibleRows()
    local sc, sf = UI._scrollChild, UI._scrollFrame
    if not (UI._mainFrame and sc and sf) then return end
    local displayList = UI._displayList
    if #displayList == 0 then return end
    local ROW_H = UI.GetRowHeight()
    local ok, offset = pcall(sf.GetVerticalScroll, sf)
    if not ok or type(offset) ~= "number" then offset = 0 end
    local first, count
    local ok2, vh = pcall(sf.GetHeight, sf)
    if ok2 and type(vh) == "number" and vh > 0 then
        first, count = UI.VisibleRange(offset, vh, #displayList, ROW_H, 4)
    else
        first, count = 1, #displayList
    end
    EnsurePool(count)
    local rows = UI._rows
    for i = 1, count do
        local di = first + i - 1
        FillRow(rows[i], displayList[di], di)
        rows[i]:Show()
    end
    for i = count + 1, #rows do rows[i]:Hide() end
end

-- Добивка eco конкуренцией с АХ (не меняет формулу Economy: только отображение/сортировка).
-- ahQty/ahMineQty — текущий сервер (как цена); ahRealms — сводка по ВСЕМ известным
-- серверам (realm-scoped хранение как у цены, п.4) для fallback "*" и тултипа.
local function AttachAuctionQuantity(rec, eco)
    if not eco or not rec or not rec.outputItemID then return eco end
    local P = _G.DecorLumberProfitPrices
    if P and P.GetAuctionStats then
        local ok, info = pcall(P.GetAuctionStats, rec.outputItemID)
        if ok and info then
            eco.ahQty = info.qty
            eco.ahListings = info.listings
            eco.ahMineQty = info.ownKnown and info.ownQty or nil
            eco.ahMineListings = info.ownKnown and info.ownListings or nil
        end
    elseif P and P.GetCachedQuantity then
        local ok, qty, listings = pcall(P.GetCachedQuantity, rec.outputItemID)
        if ok then
            eco.ahQty = qty
            eco.ahListings = listings
        end
    end
    if P and P.GetRealmAuctionInfo then
        local okR, realms = pcall(P.GetRealmAuctionInfo, rec.outputItemID)
        if okR and type(realms) == "table" and #realms > 0 then
            eco.ahRealms = realms
        end
    end
    return eco
end

local function ComputePairs(recipes, priceMap)
    local arr = {}
    for _, rec in ipairs(recipes) do
        local eco = DecorLumberProfitCore:CalculateRecipeEconomy(rec, priceMap)
        AttachAuctionQuantity(rec, eco)
        table.insert(arr, { rec = rec, eco = eco })
    end
    return arr
end

-- Топ-3 рецепта по каждой древесине (критерий: макс. цена за штуку древесины)
local function ComputeTopPairs(priceMap, recipes)
    local groups = {}
    for _, rec in ipairs(recipes or UI._currentRecipes) do
        if rec.woodItemID then
            local eco = DecorLumberProfitCore:CalculateRecipeEconomy(rec, priceMap)
            AttachAuctionQuantity(rec, eco)
            if eco.maxWoodPrice then
                local g = groups[rec.woodItemID]
                if not g then g = {}; groups[rec.woodItemID] = g end
                table.insert(g, { rec = rec, eco = eco })
            end
        end
    end
    local woodIDs = {}
    for wid in pairs(groups) do woodIDs[#woodIDs + 1] = wid end
    table.sort(woodIDs, function(a, b)
        return (DecorLumberProfitCore:GetItemName(a) or ""):lower() < (DecorLumberProfitCore:GetItemName(b) or ""):lower()
    end)
    local out = {}
    for _, wid in ipairs(woodIDs) do
        local g = groups[wid]
        table.sort(g, function(a, b) return (a.eco.maxWoodPrice or -1e18) > (b.eco.maxWoodPrice or -1e18) end)
        for i = 1, math.min(3, #g) do out[#out + 1] = g[i] end
    end
    return out
end

-- Переключение режима «Топ выгода»
function UI.ToggleTop()
    UI._topMode = not UI._topMode
    if UI.btnTop then
        UI.btnTop:SetText(UI._topMode and L.BTN_SHOW_ALL or L.BTN_TOP)
    end
    if UI._topMode and #UI._currentRecipes > 0 and UI._mainFrame and not UI._mainFrame:IsShown() then
        UI._mainFrame:Show()
    end
    UI.RefreshTable()
end

-- Фильтрация по галочке «скрыть неизученное»
local function FilterRecipesForDisplay()
    if not UI.hideUnlearned then return UI._currentRecipes, 0 end
    local out = {}
    local hidden = 0
    for _, rec in ipairs(UI._currentRecipes) do
        if UI.IsLearnedAnywhere(rec) then
            out[#out + 1] = rec
        else
            hidden = hidden + 1
        end
    end
    return out, hidden
end

-- Обновляет таблицу на основе текущих данных
function UI.RefreshTable()
    local mainFrame, scrollChild = UI._mainFrame, UI._scrollChild
    if not mainFrame or not scrollChild then return end
    local currentRecipes = UI._currentRecipes
    local displayList = UI._displayList
    -- Принудительно убираем рецепты с непродаваемой продукцией — BoP
    -- ("Становится персональным при получении", bind 1) и Warband
    -- ("Привязывается к отряду", bind 8/9).
    -- (старые записи, добавленные до включения фильтра, могут оставаться в currentRecipes/SavedVariables)
    local removed = DecorLumberProfitCore:PruneUnsellable(currentRecipes)
    if removed and removed > 0 then
        UI.SetStatus(TL("ST_PRUNED", removed), 1, 0.7, 0.2)
    end
    if #currentRecipes == 0 then
        table.wipe(displayList)
        RenderEmpty(L.ST_EMPTY_TABLE)
        UI._lastRowCount = 0
        return
    end

    local workRecipes, hiddenCount = FilterRecipesForDisplay()
    if #workRecipes == 0 then
        table.wipe(displayList)
        RenderEmpty(TL("ST_ALL_HIDDEN", hiddenCount))
        UI._lastRowCount = 0
        return
    end

    -- Собираем цены
    local priceMap, need = DecorLumberProfitPrices.CollectPricesForRecipes(workRecipes)

    -- Фильтр «Топ выгода» или полный список
    local arr = UI._topMode and ComputeTopPairs(priceMap, workRecipes) or ComputePairs(workRecipes, priceMap)
    SortPairs(arr)

    table.wipe(displayList)
    for i, p in ipairs(arr) do
        displayList[i] = p
    end

    -- Обновить высоту скролла; позицию скролла сбрасываем только при смене числа строк,
    -- чтобы обновление цен не прыгало к началу списка
    local h = math.max(#displayList, 1) * UI.GetRowHeight()
    scrollChild:SetSize(TableWidth(), h)
    local scrollFrame = UI._scrollFrame
    if scrollFrame and UI._lastRowCount ~= #displayList then
        scrollFrame:SetVerticalScroll(0)
        UI._lastRowCount = #displayList
    end
    -- Этап 9: рендерим только видимое окно (пул строк)
    UI.RenderVisibleRows()

    -- Статус-строка: сколько без цен
    local missing = 0
    for _, p in ipairs(displayList) do if p.eco.hasUnknownPrice then missing = missing + 1 end end
    local prefix = UI._topMode and TL("TOP_PREFIX", #displayList, #workRecipes) or ""
    if hiddenCount > 0 then prefix = prefix .. TL("ST_HIDDEN_SUFFIX", hiddenCount) end
    if #need > 0 then
        -- Этап 9: прогресс очереди АХ (requested/resolved из Prices.GetQueueInfo)
        local prog = ""
        local P = _G.DecorLumberProfitPrices
        if P and P.GetQueueInfo then
            local ok, qi = pcall(P.GetQueueInfo)
            if ok and qi and (qi.requested or 0) > 0 then
                prog = TL("ST_QUEUE_PROGRESS", qi.resolved or 0, qi.requested or 0)
            end
        end
        UI.SetStatus(prefix .. TL("ST_QUEUED", #displayList, missing, #need) .. prog .. UI.PriceTimeSuffix(), 1, 0.82, 0)
    else
        if missing > 0 then
            UI.SetStatus(prefix .. TL("ST_PARTIAL", #displayList, missing) .. UI.PriceTimeSuffix(), 1, 1, 0.6)
        else
            UI.SetStatus(prefix .. TL("ST_OK", #displayList) .. UI.PriceTimeSuffix(), 0.3, 1, 0.3)
        end
    end
end

function UI.OnPriceUpdate()
    if UI._mainFrame and UI._mainFrame:IsShown() then
        UI.RefreshTable()
    end
end

function UI.OnAuctionScanFinished()
    UI.SetStatus(L.ST_SCAN_DONE .. UI.PriceTimeSuffix(), 0.3, 1, 0.3)
    UI.RefreshTable()
end

function UI.OnThrottleDropped()
    UI.SetStatus(L.ST_THROTTLE, 1, 0.3, 0.3)
end

-- Применяет состояние фильтра «скрыть неизученное»
function UI.SetHideUnlearned(v)
    UI.hideUnlearned = v and true or false
    if DecorLumberProfitDB and DecorLumberProfitDB.settings then
        DecorLumberProfitDB.settings.hideUnlearned = UI.hideUnlearned or nil
    end
    if UI._mainFrame then UI.RefreshTable() end
end
