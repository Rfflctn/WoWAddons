-- UI/MainFrame.lua | DecorLumberProfit | Retail 12.1.0
-- Главное окно (Этап 8): каркас, кнопки, шапка таблицы, скролл. Рендер строк — TableView.

local UI = _G.DecorLumberProfitUI or {}
local L = DecorLumberProfitL10n.L
local TL = DecorLumberProfitL10n.TL

local FRAME_NAME = UI.FRAME_NAME

local function CreateMainFrame()
    local f = CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
    f:SetSize(DecorLumberProfitConfig.UI.WIDTH, DecorLumberProfitConfig.UI.HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    -- Рамка окна
    f:SetBackdrop({
        edgeFile = "Interface\\DialogBox\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
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

    -- Ресайз окна (Этап 9): grip в правом нижнем углу, перераскладка — в OnMainFrameSizeChanged.
    -- Midnight: SetMinResize/SetMaxResize УДАЛЕНЫ → SetResizeBounds. Все вызовы за гардами:
    -- окно обязано открыться, даже если Blizzard снова поменяет API (баг 2.0.0: краш на SetMinResize).
    if f.SetResizable then f:SetResizable(true) end
    if f.SetResizeBounds then f:SetResizeBounds(700, 400, 1400, 900) end
    if f.StartSizing then
        local grip = CreateFrame("Button", nil, f)
        grip:SetSize(16, 16)
        grip:SetPoint("BOTTOMRIGHT", -4, 4)
        grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        grip:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end
        end)
        grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)
    end
    f:SetScript("OnSizeChanged", function(self, w, h)
        UI.OnMainFrameSizeChanged(w, h)
    end)

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
        GameTooltip:AddLine(L.TIP_REFRESH_L1, 1, 1, 1)
        GameTooltip:AddLine(L.TIP_REFRESH_L2, 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L.TIP_REFRESH_L3, 0.6, 0.9, 0.6)
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
        GameTooltip:AddLine(L.TIP_PRICES_L1, 1, 1, 1)
        GameTooltip:AddLine(L.TIP_PRICES_L2, 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L.TIP_PRICES_L3, 1, 0.6, 0.6)
        GameTooltip:Show()
    end)
    btnAuction:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local btnClearCache = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnClearCache:SetSize(110, 22)
    btnClearCache:SetPoint("LEFT", btnAuction, "RIGHT", 8, 0)
    btnClearCache:SetText(L.BTN_CLEAR_CACHE)
    btnClearCache:SetScript("OnClick", function()
        DecorLumberProfitPrices.ClearPriceCache()
        UI.SetStatus(L.PRINT_CACHE_RESET, 1, 0.6, 0.2)
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
        GameTooltip:AddLine(L.TIP_CLEAR_TABLE_L1, 1, 1, 1)
        GameTooltip:AddLine(L.TIP_CLEAR_TABLE_L2, 0.7, 0.7, 0.7)
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
        GameTooltip:AddLine(L.TIP_TOP_L1, 1, 1, 1)
        GameTooltip:AddLine(L.TIP_TOP_L2, 0.7, 0.7, 0.7)
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
        GameTooltip:AddLine(L.TIP_HIDE_UNLEARNED, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    chkHide:SetScript("OnLeave", function() GameTooltip:Hide() end)
    UI.chkHide = chkHide

    -- Статус
    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("TOPLEFT", 18, -62)
    statusText:SetPoint("TOPRIGHT", -34, -62)
    statusText:SetJustifyH("LEFT")
    statusText:SetHeight(24)
    statusText:SetWordWrap(true)
    statusText:SetText(L.ST_WELCOME)
    UI._statusText = statusText
    -- Точка-индикатор здоровья (Этап 9): цвет дублирует цвет статуса (см. UI.SetStatus)
    local healthDot = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    healthDot:SetPoint("TOPRIGHT", -18, -62)
    healthDot:SetSize(12, 24)
    healthDot:SetJustifyH("CENTER")
    healthDot:SetText("●")
    healthDot:SetTextColor(0.5, 0.5, 0.5)
    UI._healthDot = healthDot

    -- Заголовок таблицы
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 14, -88)
    header:SetSize(DecorLumberProfitConfig.UI.WIDTH - 28, 20)
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
    local x = 0
    UI.headerCells = {}
    for _, c in ipairs(UI.COLUMNS) do
        local btn = CreateFrame("Button", nil, header)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", 2, 0)
        fs:SetPoint("RIGHT", -2, 0)
        fs:SetJustifyH(c.align == "CENTER" and "CENTER" or "LEFT")
        fs:SetWordWrap(false)
        fs:SetText(labels[c.key])
        fs:SetTextColor(1, 0.82, 0)
        btn:RegisterForClicks("LeftButtonUp")
        local colKey = c.key
        btn:SetScript("OnClick", function()
            UI.OnHeaderClick(colKey)
        end)
        btn:SetScript("OnEnter", function(self)
            fs:SetTextColor(1, 1, 1)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(hints[colKey] or TL("HINT_SORT_GENERIC", labels[colKey]), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            fs:SetTextColor(1, 0.82, 0)
            GameTooltip:Hide()
        end)
        table.insert(UI.headerCells, { key = c.key, text = labels[c.key], fs = fs, btn = btn })
        x = x + c.width
    end
    UI._headerFrame = header
    UI.LayoutHeaderCells()

    -- Скролл
    local scrollFrame = CreateFrame("ScrollFrame", FRAME_NAME .. "Scroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 14, -108)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 28)
    local child = CreateFrame("Frame", nil, scrollFrame)
    child:SetSize(DecorLumberProfitConfig.UI.WIDTH - 30, 100)
    scrollFrame:SetScrollChild(child)
    UI._scrollFrame = scrollFrame
    UI._scrollChild = child
    -- Виртуализация (Этап 9): перерендер видимого окна при скролле
    scrollFrame:SetScript("OnVerticalScroll", function()
        UI.RenderVisibleRows()
    end)

    -- События фрейма
    f:SetScript("OnShow", function()
        -- Первый показ в сессии: поднимаем накопленную (общую) базу из SavedVariables
        if not UI._loadedFromDB then
            UI.LoadFromDB()
            UI._loadedFromDB = true
        end
        if #UI._currentRecipes == 0 then
            UI.SetStatus(L.ST_TABLE_EMPTY_ONSHOW, 1, 0.82, 0)
        end
        UI.RefreshTable()
    end)

    UI._mainFrame = f
    return f
end

-- Перераскладка шапки под текущие ширины колонок (Этап 9: ресайз)
function UI.LayoutHeaderCells()
    if not UI.headerCells then return end
    local x = 0
    for _, cell in ipairs(UI.headerCells) do
        local w = UI.ColWidth(cell.key, 100)
        if cell.btn then
            cell.btn:SetSize(w, 20)
            cell.btn:ClearAllPoints()
            cell.btn:SetPoint("LEFT", x, 0)
        end
        x = x + w
    end
    if UI._headerFrame then UI._headerFrame:SetSize(x, 20) end
end

-- Ресайз главного окна (Этап 9): масштаб колонок + снос пула строк + перерендер.
-- Троттлинг: реагируем только на сдвиг ширины ≥20px (OnSizeChanged сыплет на каждый пиксель).
function UI.OnMainFrameSizeChanged(w, h)
    if not UI._mainFrame then return end
    if type(w) ~= "number" or w <= 0 then return end
    if UI._lastLayoutW and math.abs(w - UI._lastLayoutW) < 20 then return end
    UI._lastLayoutW = w
    local base = UI.BASE_WIDTH or 950
    UI._colScale = math.max(0.6, math.min(1.5, w / base))
    UI.LayoutColumns()
    UI.LayoutHeaderCells()
    for _, row in ipairs(UI._rows) do row:Hide() end
    table.wipe(UI._rows) -- пул пересоздастся под новые ширины
    local sf = UI._scrollFrame
    if sf then sf:SetVerticalScroll(0) end
    UI._lastRowCount = nil
    UI.RefreshTable()
end

function UI.Toggle()
    if not UI._mainFrame then CreateMainFrame() end
    if UI._mainFrame:IsShown() then UI._mainFrame:Hide() else UI._mainFrame:Show() end
end

function UI.Show()
    if not UI._mainFrame then CreateMainFrame() end
    UI._mainFrame:Show()
end

function UI.Hide()
    if UI._mainFrame then UI._mainFrame:Hide() end
end
