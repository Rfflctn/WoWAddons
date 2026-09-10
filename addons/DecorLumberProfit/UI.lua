-- UI.lua | DecorLumberProfit | Retail 12.1.0
-- Интерфейс: окно (фон+рамка), таблица, фильтры, кнопка обновления, сообщения об ошибках.
-- Все тексты — через L/TL из Locales.lua (ru/en).

DecorLumberProfitUI = {}
local UI = DecorLumberProfitUI
local L = DecorLumberProfitL10n.L
local TL = DecorLumberProfitL10n.TL

local FRAME_NAME = "DecorLumberProfitFrame"
local mainFrame = nil
local scrollChild = nil
local scrollFrame = nil
local statusText = nil

local currentRecipes = {}
local displayList = {} -- [{rec=,eco=}] — отрисованный вид (после фильтра/сортировки)
UI.displayList = displayList

-- Общее описание колонок таблицы (ширины для заголовка и строк)
local COLUMNS = {
    { key="recipe",       width=150 },
    { key="prof",         width=95 },
    { key="learned",      width=55,  align="CENTER" },
    { key="wood",         width=120 },
    { key="sellPrice",    width=85 },
    { key="totalCost",    width=90 },
    { key="woodQty",      width=45,  align="CENTER" },
    { key="maxWoodPrice", width=100 },
    { key="profit",       width=100 },
}

-- Зебра/ховер строк
local ZEBRA_EVEN  = { 0.15, 0.15, 0.15, 0.4 }
local ZEBRA_ODD   = { 0.08, 0.08, 0.08, 0.4 }
local ZEBRA_HOVER = { 0.25, 0.25, 0.10, 0.5 }

local function RowBGColor(index)
    return (index % 2 == 0) and ZEBRA_EVEN or ZEBRA_ODD
end

local function SetRowBG(bg, color)
    bg:SetColorTexture(color[1], color[2], color[3], color[4])
end

-- Множество уже имеющихся рецептов (для append без дублей)
local function BuildExistingSet(recipes)
    local set = {}
    for _, r in ipairs(recipes or {}) do
        if r.recipeSpellID then set[r.recipeSpellID] = true end
    end
    return set
end

local sortKey = nil
local sortDesc = false
local topMode = false
local lastRowCount = nil

UI.hideUnlearned = false

local function GetMoneyStr(copper)
    return DecorLumberProfitAuction.FormatMoney(copper)
end

local function GetWoodDisplayName(rec)
    if not rec.woodName and rec.woodItemID then
        rec.woodName = DecorLumberProfitCore:GetItemName(rec.woodItemID)
    end
    return rec.woodName or (rec.woodItemID and ("#"..rec.woodItemID)) or "?"
end

-- Обновляет заголовки колонок (стрелки сортировки)
function UI.UpdateHeaderArrows()
    if not UI.headerCells then return end
    for _, cell in ipairs(UI.headerCells) do
        local arrow = ""
        if sortKey == cell.key then arrow = sortDesc and " ▼" or " ▲" end
        cell.fs:SetText(cell.text..arrow)
    end
end

local function HasOtherLearners(rec)
    if type(rec.learnedBy) ~= "table" then return false end
    for _ in pairs(rec.learnedBy) do return true end
    return false
end

-- Изучен ли рецепт хотя бы на одном персонаже аккаунта
local function IsLearnedAnywhere(rec)
    return rec.learned == true or HasOtherLearners(rec)
end

local SORT_GETTERS = {
    recipe       = function(rec, eco) return (rec.name or ""):lower() end,
    prof         = function(rec, eco) return (rec.profession or ""):lower() end,
    learned      = function(rec, eco) return (rec.learned and 2 or (HasOtherLearners(rec) and 1 or 0)) end,
    wood         = function(rec, eco) return GetWoodDisplayName(rec):lower() end,
    sellPrice    = function(rec, eco) return eco.outputTotalPrice or -1 end,
    totalCost    = function(rec, eco) return eco.costNoWood or -1 end,
    woodQty      = function(rec, eco) return rec.woodQty or 0 end,
    maxWoodPrice = function(rec, eco) return eco.maxWoodPrice or -1e18 end,
    profit       = function(rec, eco) return eco.profit or -1e18 end,
}

local function SortPairs(pairs)
    local getter = sortKey and SORT_GETTERS[sortKey]
    if not getter then
        table.sort(pairs, function(a,b) return (a.rec.name or "") < (b.rec.name or "") end)
        return
    end
    table.sort(pairs, function(a,b)
        local va, vb = getter(a.rec, a.eco), getter(b.rec, b.eco)
        local r
        if type(va)=="string" and type(vb)=="string" then
            r = va < vb
        elseif type(va)=="number" and type(vb)=="number" then
            r = va < vb
        else
            r = tostring(va) < tostring(vb)
        end
        if sortDesc then return not r and va ~= vb end
        return r
    end)
end



-- Создаёт строку таблицы
local function CreateRow(parent, index, width)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, DecorLumberProfitConfig.UI.ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index-1)*DecorLumberProfitConfig.UI.ROW_HEIGHT)

    row.cols = {}
    local x = 0
    for _, c in ipairs(COLUMNS) do
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", x+2, 0)
        fs:SetSize(c.width-4, DecorLumberProfitConfig.UI.ROW_HEIGHT)
        fs:SetJustifyH(c.align or "LEFT")
        fs:SetWordWrap(false)
        row.cols[c.key] = fs
        x = x + c.width
    end

    -- Фон зебры
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    SetRowBG(bg, RowBGColor(index))
    -- Ховер
    row:SetScript("OnEnter", function(self)
        SetRowBG(bg, ZEBRA_HOVER)
        -- Тултип: список реагентов
        local pair = displayList[index]
        local rec = pair and pair.rec
        if rec then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(rec.name or L.TIP_RECIPE_FALLBACK, 1,1,1)
            if rec.outputItemID then
                local outName = DecorLumberProfitCore:GetItemName(rec.outputItemID)
                if outName then
                    GameTooltip:AddLine(TL("TIP_CREATES", outName, rec.outputQty or 1), 0.6,0.9,1)
                else
                    GameTooltip:AddLine(TL("TIP_CREATES_ITEM", rec.outputItemID, rec.outputQty or 1), 0.6,0.9,1)
                end
            end
            if rec.profession then
                GameTooltip:AddLine(TL("TIP_PROFESSION", rec.profession), 0.6,0.9,1)
            end
            if rec.reagents then
                GameTooltip:AddLine(L.TIP_REAGENTS, 0.8,0.8,0.8)
                for _, r in ipairs(rec.reagents) do
                    local name = r.itemID
                    if type(r.itemID)=="number" then
                        local n = DecorLumberProfitCore:GetItemName(r.itemID)
                        if n then name=n end
                    end
                    local price = DecorLumberProfitAuction.GetCachedPrice(r.itemID)
                    local priceStr = price and GetMoneyStr(price) or L.CELL_NO_PRICE
                    GameTooltip:AddLine(string.format("  %s x%d — %s", tostring(name), r.quantity, priceStr), 1,1,1)
                end
            end
            local eco = pair.eco
            if eco and eco.missingReagents and #eco.missingReagents>0 then
                GameTooltip:AddLine(TL("TIP_NO_PRICE_FOR", table.concat(eco.missingReagents, ", ")), 1,0.3,0.3)
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        SetRowBG(bg, RowBGColor(index))
        GameTooltip:Hide()
    end)
    return row
end

local rows = {}

local function EnsureRows(count)
    local width = DecorLumberProfitConfig.UI.WIDTH - 30
    for i=1,count do
        if not rows[i] then
            rows[i] = CreateRow(scrollChild, i, width)
        end
        rows[i]:Show()
    end
    for i=count+1, #rows do rows[i]:Hide() end
end

local function SetStatus(msg, r, g, b)
    if statusText then
        statusText:SetText(msg or "")
        if r then statusText:SetTextColor(r,g,b) end
    end
end

local function ComputePairs(recipes, priceMap)
    local arr = {}
    for _, rec in ipairs(recipes) do
        table.insert(arr, { rec=rec, eco=DecorLumberProfitCore:CalculateRecipeEconomy(rec, priceMap) })
    end
    return arr
end

-- Топ-3 рецепта по каждой древесине (критерий: макс. цена за штуку древесины)
local function ComputeTopPairs(priceMap, recipes)
    local groups = {}
    for _, rec in ipairs(recipes or currentRecipes) do
        if rec.woodItemID then
            local eco = DecorLumberProfitCore:CalculateRecipeEconomy(rec, priceMap)
            if eco.maxWoodPrice then
                local g = groups[rec.woodItemID]
                if not g then g = {}; groups[rec.woodItemID] = g end
                table.insert(g, { rec=rec, eco=eco })
            end
        end
    end
    local woodIDs = {}
    for wid in pairs(groups) do woodIDs[#woodIDs+1] = wid end
    table.sort(woodIDs, function(a,b)
        return (DecorLumberProfitCore:GetItemName(a) or ""):lower() < (DecorLumberProfitCore:GetItemName(b) or ""):lower()
    end)
    local out = {}
    for _, wid in ipairs(woodIDs) do
        local g = groups[wid]
        table.sort(g, function(a,b) return (a.eco.maxWoodPrice or -1e18) > (b.eco.maxWoodPrice or -1e18) end)
        for i=1, math.min(3, #g) do out[#out+1] = g[i] end
    end
    return out
end

-- Переключение режима «Топ выгода»
function UI.ToggleTop()
    topMode = not topMode
    if UI.btnTop then
        UI.btnTop:SetText(topMode and L.BTN_SHOW_ALL or L.BTN_TOP)
    end
    if topMode and #currentRecipes > 0 and not mainFrame:IsShown() then
        mainFrame:Show()
    end
    UI.RefreshTable()
end

-- Фильтрация по галочке «скрыть неизученное»
local function FilterRecipesForDisplay()
    if not UI.hideUnlearned then return currentRecipes, 0 end
    local out = {}
    local hidden = 0
    for _, rec in ipairs(currentRecipes) do
        if IsLearnedAnywhere(rec) then
            out[#out+1] = rec
        else
            hidden = hidden + 1
        end
    end
    return out, hidden
end

-- Обновляет таблицу на основе текущих данных
function UI.RefreshTable()
    if not mainFrame or not scrollChild then return end
    -- Принудительно убираем рецепты с привязанной (непродаваемой) продукцией — "привязано к отряду" и т.п.
    -- (старые записи, добавленные до включения фильтра, могут оставаться в currentRecipes/SavedVariables)
    local removed = DecorLumberProfitCore:PruneUnsellable(currentRecipes)
    if removed and removed > 0 then
        SetStatus(TL("ST_PRUNED", removed), 1,0.7,0.2)
    end
    if #currentRecipes == 0 then
        table.wipe(displayList)
        EnsureRows(1)
        local row = rows[1]
        for _, fs in pairs(row.cols) do fs:SetText("") end
        row.cols.recipe:SetText(L.ST_EMPTY_TABLE)
        lastRowCount = 0
        return
    end

    local workRecipes, hiddenCount = FilterRecipesForDisplay()
    if #workRecipes == 0 then
        table.wipe(displayList)
        EnsureRows(1)
        local row = rows[1]
        for _, fs in pairs(row.cols) do fs:SetText("") end
        row.cols.recipe:SetText(TL("ST_ALL_HIDDEN", hiddenCount))
        lastRowCount = 0
        return
    end

    -- Собираем цены
    local priceMap, need = DecorLumberProfitAuction.CollectPricesForRecipes(workRecipes)

    -- Фильтр «Топ выгода» или полный список
    local arr = topMode and ComputeTopPairs(priceMap, workRecipes) or ComputePairs(workRecipes, priceMap)
    SortPairs(arr)

    table.wipe(displayList)
    for i, p in ipairs(arr) do
        displayList[i] = p
    end

    EnsureRows(#displayList)
    for i, p in ipairs(displayList) do
        local row = rows[i]
        local rec, eco = p.rec, p.eco
        -- Рецепт
        row.cols.recipe:SetText(rec.name or ("#" .. (rec.recipeSpellID or "?")))

        -- Профессия
        row.cols.prof:SetText(rec.profession or L.CELL_PROF_UNKNOWN)

        -- Изучен ли рецепт: текущим персом / другим персом / никем
        if rec.learned == true then
            row.cols.learned:SetText(L.CELL_YES)
        elseif HasOtherLearners(rec) then
            row.cols.learned:SetText(L.CELL_OTHER)
        elseif rec.learned == false then
            row.cols.learned:SetText(L.CELL_NO)
        else
            row.cols.learned:SetText(L.CELL_UNKNOWN)
        end

        -- Используемая древесина
        row.cols.wood:SetText(GetWoodDisplayName(rec))

        -- Цена продажи
        if eco.outputUnitPrice then
            -- Показываем цену за штуку и суммарную
            if rec.outputQty > 1 then
                row.cols.sellPrice:SetText(GetMoneyStr(eco.outputUnitPrice) .. " / " .. GetMoneyStr(eco.outputTotalPrice))
            else
                row.cols.sellPrice:SetText(GetMoneyStr(eco.outputUnitPrice))
            end
        else
            row.cols.sellPrice:SetText(L.CELL_NO_AH)
        end

        -- Себестоимость без стоимости древесины
        local cnw = eco.costNoWood
        if cnw and eco.hasUnknownPrice and cnw==0 then
            row.cols.totalCost:SetText(L.CELL_UNKNOWN_COST)
        elseif cnw and eco.hasUnknownPrice then
            row.cols.totalCost:SetText(GetMoneyStr(cnw) .. "*")
        elseif cnw then
            row.cols.totalCost:SetText(GetMoneyStr(cnw))
        else
            row.cols.totalCost:SetText(L.CELL_DASH)
        end

        row.cols.woodQty:SetText(tostring(eco.woodQty or rec.woodQty or 0))

        if eco.maxWoodPrice then
            if eco.maxWoodPrice < 0 then
                row.cols.maxWoodPrice:SetText("|cffff0000"..GetMoneyStr(math.floor(eco.maxWoodPrice)).."|r")
            else
                row.cols.maxWoodPrice:SetText(GetMoneyStr(math.floor(eco.maxWoodPrice)))
            end
        else
            row.cols.maxWoodPrice:SetText(L.CELL_DASH)
        end

        if eco.profit then
            local col = eco.profit > 0 and "|cff00ff00" or (eco.profit<0 and "|cffff0000" or "|cffffff00")
            row.cols.profit:SetText(col..GetMoneyStr(math.floor(eco.profit)).."|r")
        else
            row.cols.profit:SetText(L.CELL_DASH)
        end
    end

    -- Обновить высоту скролла; позицию скролла сбрасываем только при смене числа строк,
    -- чтобы обновление цен не прыгало к началу списка
    local h = math.max(#displayList,1) * DecorLumberProfitConfig.UI.ROW_HEIGHT
    scrollChild:SetSize(DecorLumberProfitConfig.UI.WIDTH-30, h)
    if scrollFrame and lastRowCount ~= #displayList then
        scrollFrame:SetVerticalScroll(0)
        lastRowCount = #displayList
    end

    -- Статус-строка: сколько без цен
    local missing = 0
    for _, p in ipairs(displayList) do if p.eco.hasUnknownPrice then missing=missing+1 end end
    local prefix = topMode and TL("TOP_PREFIX", #displayList, #workRecipes) or ""
    if hiddenCount > 0 then prefix = prefix .. TL("ST_HIDDEN_SUFFIX", hiddenCount) end
    if #need > 0 then
        SetStatus(prefix..TL("ST_QUEUED", #displayList, missing, #need), 1, 0.82, 0)
    else
        if missing>0 then
            SetStatus(prefix..TL("ST_PARTIAL", #displayList, missing), 1, 1, 0.6)
        else
            SetStatus(prefix..TL("ST_OK", #displayList), 0.3, 1, 0.3)
        end
    end
end

function UI.OnPriceUpdate()
    if mainFrame and mainFrame:IsShown() then
        UI.RefreshTable()
    end
end

function UI.OnAuctionScanFinished()
    SetStatus(L.ST_SCAN_DONE, 0.3,1,0.3)
    UI.RefreshTable()
end

function UI.OnThrottleDropped()
    SetStatus(L.ST_THROTTLE, 1,0.3,0.3)
end

function UI.RebuildRecipeList(showMessage)
    -- Новый принцип: добавляем рецепты из АКТИВНОГО окна профессии в таблицу (append, без дублей)
    local recipes, err, meta = DecorLumberProfitCore:FindWoodRecipesInActiveWindow()

    if err == "WOOD_ID_NOT_SET" then
        SetStatus(L.ST_ERR_WOOD_ID, 1,0.3,0.3)
        UI.RefreshTable()
        return
    elseif err == "NO_ACTIVE_WINDOW" then
        SetStatus(L.ST_NO_ACTIVE_WINDOW, 1,0.7,0.2)
        if showMessage then print(L.PREFIX_ERR .. L.ST_NO_ACTIVE_WINDOW) end
        UI.RefreshTable()
        return
    elseif err == "NO_RECIPES_IN_ACTIVE_WINDOW" then
        local dbg = meta and TL("DBG_META", table.concat(meta.activeSkillLines or {},","), tostring(meta.candidateCount or 0)) or ""
        SetStatus(L.ST_NO_RECIPES_IN_WINDOW .. dbg, 1,0.7,0.2)
        if showMessage then
            print(L.PREFIX_ERR .. TL("PRINT_NO_RECIPES_ACTIVE", dbg))
        end
        UI.RefreshTable()
        return
    elseif err == "NO_WOOD_IN_ACTIVE_CANDIDATES" then
        local dbg = meta and TL("DBG_META_NO_WOOD", meta.candidateCount or 0, meta.noOutput or 0, meta.noWood or 0, meta.bindSkipped or 0, meta.bindPending or 0, table.concat(meta.activeSkillLines or {},",")) or ""
        -- Fallback: пробуем глобальный поиск по всем профессиям и добавляем те, что содержат древесину
        local global, gErr, gMeta = DecorLumberProfitCore:FindWoodRecipes()
        if global and #global>0 then
            local existing = BuildExistingSet(currentRecipes)
            local added=0
            for _, r in ipairs(global) do if not existing[r.recipeSpellID] then table.insert(currentRecipes,r); added=added+1 end end
            table.sort(currentRecipes, function(a,b) return (a.name or "")<(b.name or "") end)
            SetStatus(TL("ST_GLOBAL_FALLBACK", meta and meta.candidateCount or 0, #global, added, #currentRecipes), 0.3,1,0.3)
            if showMessage then print(L.PREFIX_OK .. TL("PRINT_GLOBAL_FALLBACK", dbg, added)) end
            UI.RefreshTable()
            return
        end
        SetStatus(TL("ST_NO_WOOD_IN_WINDOW", tostring(meta and meta.candidateCount or "?"), dbg), 1,0.7,0.2)
        if showMessage then
            print(L.PREFIX_ERR .. TL("PRINT_NO_WOOD_DETAIL", tostring(meta and meta.candidateCount or "?"), tostring(meta and meta.noOutput or "?"), tostring(meta and meta.noWood or "?")))
            local ids = DecorLumberProfitCore:GetWoodIDs()
            print(L.PREFIX_DIM .. TL("PRINT_WOOD_IDS", table.concat(ids,", ")) .. "|r")
            if meta and meta.candidateCount and meta.candidateCount>0 then
                local debug = DecorLumberProfitCore:DebugActive()
                print(L.PREFIX_DIM .. TL("PRINT_ACTIVE_DEBUG", table.concat(debug.activeSkillLines or {},","), table.concat(debug.firstCandidates or {},",")) .. "|r")
            end
        end
        UI.RefreshTable()
        return
    elseif err == "NO_RECIPES_ENUMERATED" then
        SetStatus(L.ST_NO_RECIPES_ENUMERATED, 1,0.7,0.2)
        UI.RefreshTable()
        return
    end

    -- append без дублей + сохранение в общую (account-wide) базу
    local existing = BuildExistingSet(currentRecipes)
    local added = 0
    for _, r in ipairs(recipes or {}) do
        local ser = DecorLumberProfitCore:SaveRecipe(r)
        if r.learned == true then DecorLumberProfitCore:MarkLearnedBy(r.recipeSpellID); ser = DecorLumberProfitCore:GetSavedRecipe(r.recipeSpellID) end
        if ser then r.learnedBy = ser.learnedBy end
        if not existing[r.recipeSpellID] then
            table.insert(currentRecipes, r)
            existing[r.recipeSpellID]=true
            added = added + 1
        end
    end
    table.sort(currentRecipes, function(a,b) return (a.name or "") < (b.name or "") end)

    if #recipes == 0 then
        SetStatus(TL("ST_FOUND_ZERO", #currentRecipes), 1,0.7,0.2)
    elseif added == 0 then
        SetStatus(TL("ST_ALL_DUP", #recipes, #currentRecipes), 0.3,1,0.3)
        if showMessage then print(L.PREFIX_OK .. TL("PRINT_ALL_DUP", #recipes, #currentRecipes)) end
    else
        SetStatus(TL("ST_ADDED", added, #recipes, #currentRecipes), 0.3,1,0.3)
        if showMessage then print(L.PREFIX_OK .. TL("PRINT_ADDED", added, #currentRecipes)) end
    end
    UI.RefreshTable()
end

-- Поднимает накопленную общую базу рецептов из SavedVariables
function UI.LoadFromDB()
    local saved = DecorLumberProfitCore:LoadSavedRecipes()
    if not saved or #saved == 0 then return 0 end
    local existing = BuildExistingSet(currentRecipes)
    local loaded = 0
    for _, rec in ipairs(saved) do
        if not existing[rec.recipeSpellID] then
            table.insert(currentRecipes, rec)
            existing[rec.recipeSpellID]=true
            loaded = loaded + 1
        end
    end
    -- learned актуализируется под текущего персонажа (в т.ч. learnedBy)
    pcall(function() DecorLumberProfitCore:RefreshLearnedFlags(currentRecipes) end)
    table.sort(currentRecipes, function(a,b) return (a.name or "") < (b.name or "") end)
    return loaded
end

-- Полная перезагрузка таблицы (используется редко, например, при /reload)
function UI.RebuildAllRecipes()
    local recipes, err, meta = DecorLumberProfitCore:FindWoodRecipes()
    if err then
        SetStatus(L.ST_REBUILD_EMPTY, 1,0.7,0.2)
        UI.RefreshTable()
        return
    end
    currentRecipes = recipes or {}
    for _, r in ipairs(currentRecipes) do DecorLumberProfitCore:SaveRecipe(r) end
    table.sort(currentRecipes, function(a,b) return (a.name or "") < (b.name or "") end)
    SetStatus(TL("ST_REBUILD_LOADED", #currentRecipes), 0.3,1,0.3)
    UI.RefreshTable()
end

function UI.RequestAuctionUpdate()
    if #currentRecipes==0 then
        SetStatus(L.ST_NO_RECIPES_FOR_PRICES, 1,0.5,0)
        return
    end
    local _, need = DecorLumberProfitAuction.CollectPricesForRecipes(currentRecipes)
    if #need==0 then
        SetStatus(TL("ST_PRICES_CACHED", (DecorLumberProfitConfig.AUCTION.PRICE_TTL/60)), 0.7,0.7,1)
        UI.RefreshTable()
        return
    end
    -- Фильтруем только уникальные
    local uniq, seen = {}, {}
    for _, id in ipairs(need) do if not seen[id] then seen[id]=true; table.insert(uniq, id) end end
    SetStatus(TL("ST_PRICES_REQUESTED", #uniq), 0.3,0.8,1)
    DecorLumberProfitAuction.RequestPrices(uniq)
end

-- Применяет состояние фильтра «скрыть неизученное»
function UI.SetHideUnlearned(v)
    UI.hideUnlearned = v and true or false
    if DecorLumberProfitDB and DecorLumberProfitDB.settings then
        DecorLumberProfitDB.settings.hideUnlearned = UI.hideUnlearned or nil
    end
    if mainFrame then UI.RefreshTable() end
end

local function CreateMainFrame()
    local f = CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
    f:SetSize(DecorLumberProfitConfig.UI.WIDTH, DecorLumberProfitConfig.UI.HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    -- Рамка окна
    f:SetBackdrop({
        edgeFile="Interface\\DialogBox\\UI-DialogBox-Border",
        tile=true, tileSize=32, edgeSize=32,
        insets={left=11,right=12,top=12,bottom=11}
    })
    -- Общий фон окна
    local windowBG = f:CreateTexture(nil, "BACKGROUND")
    windowBG:SetPoint("TOPLEFT", 9, -9)
    windowBG:SetPoint("BOTTOMRIGHT", -10, 10)
    windowBG:SetColorTexture(0.04, 0.04, 0.06, 0.95)
    -- Тонкая внутренняя линия под шапкой
    local headerLine = f:CreateTexture(nil, "BACKGROUND")
    headerLine:SetPoint("TOPLEFT", 14, -58)
    headerLine:SetPoint("TOPRIGHT", -14, -58)
    headerLine:SetHeight(1)
    headerLine:SetColorTexture(1, 0.82, 0, 0.25)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()

    -- Заголовок
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText(L.TITLE)

    -- Кнопка закрытия (X)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Панель кнопок
    local btnRefresh = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnRefresh:SetSize(150, 22)
    btnRefresh:SetPoint("TOPLEFT", 18, -38)
    btnRefresh:SetText(L.BTN_REFRESH)
    btnRefresh:SetScript("OnClick", function() UI.RebuildRecipeList(true) end)
    btnRefresh:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.TIP_REFRESH_TITLE)
        GameTooltip:AddLine(L.TIP_REFRESH_L1, 1,1,1)
        GameTooltip:AddLine(L.TIP_REFRESH_L2, 0.7,0.7,0.7)
        GameTooltip:AddLine(L.TIP_REFRESH_L3, 0.6,0.9,0.6)
        GameTooltip:Show()
    end)
    btnRefresh:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local btnAuction = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnAuction:SetSize(150, 22)
    btnAuction:SetPoint("LEFT", btnRefresh, "RIGHT", 8, 0)
    btnAuction:SetText(L.BTN_PRICES)
    btnAuction:SetScript("OnClick", function() UI.RequestAuctionUpdate() end)
    btnAuction:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.TIP_PRICES_TITLE)
        GameTooltip:AddLine(L.TIP_PRICES_L1,1,1,1)
        GameTooltip:AddLine(L.TIP_PRICES_L2,0.7,0.7,0.7)
        GameTooltip:AddLine(L.TIP_PRICES_L3,1,0.6,0.6)
        GameTooltip:Show()
    end)
    btnAuction:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local btnClearCache = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnClearCache:SetSize(110, 22)
    btnClearCache:SetPoint("LEFT", btnAuction, "RIGHT", 8, 0)
    btnClearCache:SetText(L.BTN_CLEAR_CACHE)
    btnClearCache:SetScript("OnClick", function()
        DecorLumberProfitAuction.ClearPriceCache()
        SetStatus(L.PRINT_CACHE_RESET, 1,0.6,0.2)
        UI.RefreshTable()
    end)

    local btnClearTable = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnClearTable:SetSize(110, 22)
    btnClearTable:SetPoint("LEFT", btnClearCache, "RIGHT", 8, 0)
    btnClearTable:SetText(L.BTN_CLEAR_TABLE)
    btnClearTable:SetScript("OnClick", function()
        StaticPopup_Show("DECORLUMBERPROFIT_CLEAR_DB")
    end)
    btnClearTable:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.TIP_CLEAR_TABLE_TITLE)
        GameTooltip:AddLine(L.TIP_CLEAR_TABLE_L1,1,1,1)
        GameTooltip:AddLine(L.TIP_CLEAR_TABLE_L2,0.7,0.7,0.7)
        GameTooltip:Show()
    end)
    btnClearTable:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local btnTop = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnTop:SetSize(120, 22)
    btnTop:SetPoint("TOPRIGHT", -18, -38)
    btnTop:SetText(L.BTN_TOP)
    UI.btnTop = btnTop
    btnTop:SetScript("OnClick", function() UI.ToggleTop() end)
    btnTop:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.TIP_TOP_TITLE)
        GameTooltip:AddLine(L.TIP_TOP_L1, 1,1,1)
        GameTooltip:AddLine(L.TIP_TOP_L2, 0.7,0.7,0.7)
        GameTooltip:Show()
    end)
    btnTop:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Чекбокс «Скрыть неизученное»
    local chkHide = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    chkHide:SetSize(24, 24)
    chkHide:SetPoint("RIGHT", btnTop, "LEFT", -8, 0)
    if chkHide.Text then
        chkHide.Text:ClearAllPoints()
        chkHide.Text:SetPoint("RIGHT", chkHide, "LEFT", -2, 0)
        chkHide.Text:SetWordWrap(false)
        chkHide.Text:SetText(L.CHK_HIDE_UNLEARNED)
        chkHide.Text:SetFontObject("GameFontHighlightSmall")
    else
        local chkLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        chkLabel:SetPoint("RIGHT", chkHide, "LEFT", -2, 0)
        chkLabel:SetWordWrap(false)
        chkLabel:SetText(L.CHK_HIDE_UNLEARNED)
    end
    chkHide:SetChecked(UI.hideUnlearned)
    chkHide:SetScript("OnClick", function(self)
        UI.SetHideUnlearned(self:GetChecked() and true or false)
    end)
    chkHide:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L.TIP_HIDE_UNLEARNED, 1,1,1, true)
        GameTooltip:Show()
    end)
    chkHide:SetScript("OnLeave", function() GameTooltip:Hide() end)
    UI.chkHide = chkHide

    -- Статус
    statusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("TOPLEFT", 18, -62)
    statusText:SetPoint("TOPRIGHT", -18, -62)
    statusText:SetJustifyH("LEFT")
    statusText:SetHeight(24)
    statusText:SetWordWrap(true)
    statusText:SetText(L.ST_WELCOME)

    -- Заголовок таблицы
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 14, -88)
    header:SetSize(DecorLumberProfitConfig.UI.WIDTH-28, 20)
    -- Фон заголовка таблицы
    local headerBG = header:CreateTexture(nil, "BACKGROUND")
    headerBG:SetAllPoints()
    headerBG:SetColorTexture(0.12, 0.10, 0.05, 0.9)
    local labels = {
        recipe = L.HEAD_RECIPE,
        prof = L.HEAD_PROF,
        learned = L.HEAD_LEARNED,
        wood = L.HEAD_WOOD,
        sellPrice = L.HEAD_SELL,
        totalCost = L.HEAD_COST,
        woodQty = L.HEAD_WOODQTY,
        maxWoodPrice = L.HEAD_MAXPRICE,
        profit = L.HEAD_PROFIT,
    }
    local hints = {
        recipe = L.HINT_RECIPE,
        prof = L.HINT_PROF,
        learned = L.HINT_LEARNED,
        wood = L.HINT_WOOD,
        sellPrice = L.HINT_SELL,
        totalCost = L.HINT_COST,
        woodQty = L.HINT_WOODQTY,
        maxWoodPrice = L.HINT_MAXPRICE,
        profit = L.HINT_PROFIT,
    }
    local x=0
    UI.headerCells = {}
    for _,c in ipairs(COLUMNS) do
        local btn = CreateFrame("Button", nil, header)
        btn:SetSize(c.width, 20)
        btn:SetPoint("LEFT", x, 0)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", 2, 0)
        fs:SetPoint("RIGHT", -2, 0)
        fs:SetJustifyH(c.align == "CENTER" and "CENTER" or "LEFT")
        fs:SetWordWrap(false)
        fs:SetText(labels[c.key])
        fs:SetTextColor(1,0.82,0)
        btn:RegisterForClicks("LeftButtonUp")
        btn:SetScript("OnClick", function()
            if sortKey == c.key then
                sortDesc = not sortDesc
            else
                sortKey = c.key
                sortDesc = (c.key ~= "recipe" and c.key ~= "prof" and c.key ~= "wood")
            end
            UI.UpdateHeaderArrows()
            UI.RefreshTable()
        end)
        btn:SetScript("OnEnter", function(self)
            fs:SetTextColor(1,1,1)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(hints[c.key] or TL("HINT_SORT_GENERIC", labels[c.key]), 1,1,1, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            fs:SetTextColor(1,0.82,0)
            GameTooltip:Hide()
        end)
        table.insert(UI.headerCells, { key=c.key, text=labels[c.key], fs=fs })
        x=x+c.width
    end

    -- Скролл
    scrollFrame = CreateFrame("ScrollFrame", FRAME_NAME.."Scroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 14, -108)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 28)
    local child = CreateFrame("Frame", nil, scrollFrame)
    child:SetSize(DecorLumberProfitConfig.UI.WIDTH-30, 100)
    scrollFrame:SetScrollChild(child)
    scrollChild = child

    -- События фрейма
    f:SetScript("OnShow", function()
        -- Первый показ в сессии: поднимаем накопленную (общую) базу из SavedVariables
        if not UI._loadedFromDB then
            UI.LoadFromDB()
            UI._loadedFromDB = true
        end
        if #currentRecipes == 0 then
            SetStatus(L.ST_TABLE_EMPTY_ONSHOW, 1,0.82,0)
        end
        UI.RefreshTable()
    end)

    mainFrame = f
    return f
end

-- Очистка таблицы + общей базы (для кнопки и /dlp clear)
function UI.ClearAll()
    currentRecipes = {}
    table.wipe(displayList)
    lastRowCount = nil
    topMode = false
    if UI.btnTop then UI.btnTop:SetText(L.BTN_TOP) end
    DecorLumberProfitCore:ClearSavedRecipes()
    if mainFrame then UI.RefreshTable() end
end

-- Диалог регистрации статического попапа (после применения локали)
function UI.RegisterPopups()
    if not StaticPopupDialogs["DECORLUMBERPROFIT_CLEAR_DB"] then
        StaticPopupDialogs["DECORLUMBERPROFIT_CLEAR_DB"] = {
            text = L.POPUP_CLEAR_TEXT,
            button1 = L.POPUP_CLEAR_OK,
            button2 = L.POPUP_CLEAR_CANCEL,
            OnAccept = function()
                UI.ClearAll()
                print(L.PREFIX_ERR .. L.PRINT_TABLE_CLEARED)
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
end

function UI.Toggle()
    if not mainFrame then CreateMainFrame() end
    if mainFrame:IsShown() then mainFrame:Hide() else mainFrame:Show() end
end

function UI.Show()
    if not mainFrame then CreateMainFrame() end
    mainFrame:Show()
end

function UI.Hide()
    if mainFrame then mainFrame:Hide() end
end

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
        -- Миграция v1.4.0 (переименование LumberProfit → DecorLumberProfit): подхватываем сэйвы со старых имён, от нового к старому
        if DecorLumberProfitDB == nil and _G.LumberProfitDB ~= nil then DecorLumberProfitDB = _G.LumberProfitDB end
        if DecorLumberProfitDB == nil and _G.ThalassianWoodDB ~= nil then DecorLumberProfitDB = _G.ThalassianWoodDB end
        if DecorLumberProfitCharDB == nil and _G.LumberProfitCharDB ~= nil then DecorLumberProfitCharDB = _G.LumberProfitCharDB end
        if DecorLumberProfitCharDB == nil and _G.ThalassianWoodCharDB ~= nil then DecorLumberProfitCharDB = _G.ThalassianWoodCharDB end
        DecorLumberProfitDB = DecorLumberProfitDB or { priceCache={}, knownRecipes={} }
        DecorLumberProfitDB.priceCache = DecorLumberProfitDB.priceCache or {}
        DecorLumberProfitDB.knownRecipes = DecorLumberProfitDB.knownRecipes or {}
        DecorLumberProfitDB.settings = DecorLumberProfitDB.settings or {}
        DecorLumberProfitCharDB = DecorLumberProfitCharDB or { seenRecipes={} }
        DecorLumberProfitCharDB.seenRecipes = DecorLumberProfitCharDB.seenRecipes or {}

        -- Локаль: переопределение из settings или авто-определение по клиенту
        local loc = DecorLumberProfitDB.settings.locale
        if loc ~= "enUS" and loc ~= "ruRU" then loc = DecorLumberProfitL10n.DetectLocale() end
        DecorLumberProfitL10n.SetLocale(loc)
        UI.hideUnlearned = DecorLumberProfitDB.settings.hideUnlearned and true or false
        UI.RegisterPopups()

        SLASH_DECORLUMBERPROFIT1 = "/dlp"
        SLASH_DECORLUMBERPROFIT2 = "/lp"
        SLASH_DECORLUMBERPROFIT3 = "/twc"
        SLASH_DECORLUMBERPROFIT4 = "/thalwood"
        SLASH_DECORLUMBERPROFIT5 = "/древесина"
        SlashCmdList["DECORLUMBERPROFIT"] = function(msg)
            msg = (msg or ""):lower():gsub("^%s+",""):gsub("%s+$","")
            if msg=="help" or msg=="?" then
                print(L.PREFIX_OK .. L.PRINT_HELP)
            elseif msg=="reset" then
                DecorLumberProfitAuction.ClearPriceCache()
                print(L.PREFIX_ERR .. L.PRINT_CACHE_RESET)
                if mainFrame and mainFrame:IsShown() then UI.RefreshTable() end
            elseif msg=="clear" then
                UI.ClearAll()
                print(L.PREFIX_ERR .. L.PRINT_TABLE_CLEARED)
            elseif msg=="scan" then
                UI.RebuildRecipeList(true)
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
            else
                UI.Toggle()
            end
        end
        print(L.PREFIX_OK .. TL("PRINT_LOADED", #(DecorLumberProfitConfig.WOOD_ITEM_IDS or {})))

    elseif event == "PLAYER_LOGIN" then
        -- Грузим накопленную ОБЩУЮ базу аккаунта (все персонажи) и обновляем learned под текущего
        local saved = DecorLumberProfitCore:LoadSavedRecipes()
        if saved and #saved > 0 then
            currentRecipes = saved
            pcall(function() DecorLumberProfitCore:RefreshLearnedFlags(currentRecipes) end)
            table.sort(currentRecipes, function(a,b) return (a.name or "") < (b.name or "") end)
        end
        UI._loadedFromDB = true

    elseif event == "NEW_RECIPE_LEARNED" then
        local recipeID = arg1
        local recipeLevel = arg2
        if DecorLumberProfitCore and DecorLumberProfitCore.RememberRecipe then
            DecorLumberProfitCore:RememberRecipe(recipeID, recipeLevel)
        end
        if DecorLumberProfitCore and DecorLumberProfitCore.MarkLearnedBy then
            DecorLumberProfitCore:MarkLearnedBy(recipeID)
        end
        if mainFrame and mainFrame:IsShown() then
            C_Timer.After(0.5, function() UI.RebuildRecipeList(false) end)
        end

    elseif event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
        -- Запоминаем активный skillLine для кнопки «Обновить рецепты»
        if C_TradeSkillUI and C_TradeSkillUI.GetProfessionChildSkillLineID and DecorLumberProfitCore and DecorLumberProfitCore.SetActiveSkillLineID then
            local sid = nil
            local ok, val = pcall(C_TradeSkillUI.GetProfessionChildSkillLineID)
            if ok and type(val)=="number" and val~=0 then sid = val end
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
            if ok and type(val)=="number" and val~=0 then DecorLumberProfitCore:SetActiveSkillLineID(val) end
        end
        -- Подсказка если окно LP открыто
        if mainFrame and mainFrame:IsShown() then
            SetStatus(L.ST_PROF_WINDOW_FOUND, 0.6,1,0.6)
        end
    elseif event == "TRADE_SKILL_CLOSE" then
        -- skillLine остаётся запомненным до следующего открытия

    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- arg1=itemID, arg2=success. Если данных о предмете нет — убираем ждуны по нему.
        if arg2 == false then DecorLumberProfitCore:FailPendingForItem(arg1) end
        -- Предмет догрузился с сервера: проверяем отложенные рецепты (bindType был неизвестен)
        local resolved = DecorLumberProfitCore:ResolvePendingBind()
        if resolved and #resolved > 0 then
            local existing = BuildExistingSet(currentRecipes)
            local added = 0
            for _, rec in ipairs(resolved) do
                local ser = DecorLumberProfitCore:SaveRecipe(rec)
                if ser then rec.learnedBy = ser.learnedBy end
                if not existing[rec.recipeSpellID] then
                    table.insert(currentRecipes, rec)
                    existing[rec.recipeSpellID] = true
                    added = added + 1
                end
            end
            if added > 0 then
                if mainFrame and mainFrame:IsShown() then UI.RefreshTable() end
                print(L.PREFIX_OK .. TL("PRINT_ITEMS_RESOLVED", added))
            end
        end
    end
end)

-- Экспорт для Auction колбэков
_G.DecorLumberProfitUI = UI
