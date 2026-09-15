-- UI.lua | MacrosIconSwitcher | Retail 12.1.0
-- The macro table window: one row per macro with a checkbox, an icon-ID field,
-- a "pick from list" button and a preview of the icon that will be applied.
-- Window is created lazily on first /mis and then reused. No game logic here (see Core.lua).

local Addon = _G.MacrosIconSwitcher
local L10n = _G.MacrosIconSwitcherL10n
local L = L10n.L
local TL = L10n.TL
local Config = _G.MacrosIconSwitcherConfig

local UI = {}
Addon.UI = UI

local unpack = unpack or table.unpack

UI.FRAME_NAME = "MacrosIconSwitcherFrame"
UI.PICKER_NAME = "MacrosIconSwitcherPicker"
UI._frame = nil
UI._built = false
UI._rows = {}
UI._macros = {}
UI._picker = nil
UI._pickerTarget = nil
UI._pickerPool = {}
UI._iconList = nil

local C = Config.UI
local P = Config.PICKER

-- Column origins relative to the content area (0 = left edge of the scroll child).
local function contentX(n)
    if n == 1 then return 0 end
    if n == 2 then return C.COL_CHECK end
    if n == 3 then return C.COL_CHECK + C.COL_NAME end
    if n == 4 then return C.COL_CHECK + C.COL_NAME + C.COL_CURRENT end
    return C.COL_CHECK + C.COL_NAME + C.COL_CURRENT + C.COL_PREVIEW
end

local CONTENT_WIDTH = C.COL_CHECK + C.COL_NAME + C.COL_CURRENT + C.COL_PREVIEW + C.COL_ICON

function UI.IsShown()
    return UI._frame and UI._frame:IsShown()
end

function UI.SetStatus(msg, color)
    if not UI._status then return end
    UI._status:SetText(msg or "")
    if color then UI._status:SetTextColor(unpack(color)) end
end

-- Sync a single row with the saved variable + current macro state.
function UI.RefreshRow(row)
    local macro = row.macro
    if not macro then return end
    local entry = Addon.Core.GetEntry(macro.name, macro.perCharacter)
    local enabled = (entry and entry.enabled) and true or false

    row.check:SetChecked(enabled)
    row.nameText:SetText(macro.name)
    row.iconBox:SetShown(enabled)
    row.pickBtn:SetShown(enabled)
    row.iconBox:SetText((entry and entry.icon) and tostring(entry.icon) or "")

    -- Preview: the icon that will be applied.
    if enabled and entry and Addon.Core.IsValidIcon(entry.icon) then
        -- invalid user-entered FileDataIDs must not break the whole refresh
        if pcall(row.preview.SetTexture, row.preview, entry.icon) then
            row.preview:Show()
        else
            row.preview:Hide()
        end
    else
        row.preview:Hide()
    end

    if macro.icon and macro.icon ~= 0 then
        row.curIcon:SetTexture(macro.icon)
        row.curIcon:Show()
        row.curText:SetText(tostring(macro.icon))
    else
        row.curIcon:Hide()
        row.curText:SetText("?")
    end
end

local function commitIcon(row)
    if row._committing then return end
    local macro = row.macro
    if not macro then return end
    row._committing = true

    local text = row.iconBox:GetText() or ""
    local id = tonumber(text)
    if id and id > 0 then
        id = math.floor(id)
        Addon.Core.SetEntry(macro.name, macro.perCharacter, true, id)
        row.check:SetChecked(true)
        row.iconBox:SetShown(true)
        row.pickBtn:SetShown(true)
        if Addon.Core.ApplyMacro(macro) then
            UI.SetStatus(TL("ST_APPLIED", tostring(id), macro.name), Config.COLORS.OK)
        else
            UI.SetStatus(TL("ST_FAILED", macro.name), Config.COLORS.ERR)
        end
    else
        Addon.Core.SetEntry(macro.name, macro.perCharacter, true, nil)
        UI.SetStatus(L.ST_INVALID_ID, Config.COLORS.ERR)
    end

    UI.RefreshRow(row)
    row.iconBox:ClearFocus()
    row._committing = false
end

local function attachTooltip(widget, text)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function CreateRow(parent, i)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(C.ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((i - 1) * C.ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((i - 1) * C.ROW_HEIGHT))

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    bg:SetColorTexture(unpack(Config.COLORS.ROW_B))
    row.bg = bg

    local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("LEFT", row, "LEFT", contentX(1) + 2, 0)
    check:SetScript("OnClick", function(cb)
        local macro = row.macro
        if not macro then return end
        local checked = cb:GetChecked() and true or false
        Addon.Core.SetEntry(macro.name, macro.perCharacter, checked, nil)
        row.iconBox:SetShown(checked)
        row.pickBtn:SetShown(checked)
        if checked then
            local entry = Addon.Core.GetEntry(macro.name, macro.perCharacter)
            if not (entry and entry.icon) then row.iconBox:SetText("") end
            row.iconBox:SetFocus()
        end
    end)
    attachTooltip(check, L.TIP_CHECK)
    row.check = check

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", row, "LEFT", contentX(2), 0)
    name:SetWidth(C.COL_NAME - 6)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    row.nameText = name

    local curIcon = row:CreateTexture(nil, "ARTWORK")
    curIcon:SetSize(18, 18)
    curIcon:SetPoint("LEFT", row, "LEFT", contentX(3), 0)
    row.curIcon = curIcon

    local curText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    curText:SetPoint("LEFT", row, "LEFT", contentX(3) + 24, 0)
    curText:SetWidth(C.COL_CURRENT - 30)
    curText:SetJustifyH("LEFT")
    curText:SetTextColor(unpack(Config.COLORS.MUTED))
    row.curText = curText
    attachTooltip(curText, L.TIP_CURRENT)

    local preview = row:CreateTexture(nil, "ARTWORK")
    preview:SetSize(18, 18)
    preview:SetPoint("LEFT", row, "LEFT", contentX(4), 0)
    row.preview = preview
    attachTooltip(preview, L.TIP_PREVIEW)

    local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    box:SetHeight(20)
    box:SetWidth(C.COL_ICON - 44)
    box:SetPoint("LEFT", row, "LEFT", contentX(5), 0)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(10)
    box:SetScript("OnEnterPressed", function() commitIcon(row) end)
    box:SetScript("OnEscapePressed", function(eb)
        row._skipCommit = true
        eb:ClearFocus()
        row._skipCommit = false
    end)
    box:SetScript("OnEditFocusLost", function()
        if row._skipCommit or row._committing then return end
        commitIcon(row)
    end)
    attachTooltip(box, L.TIP_ICON)
    row.iconBox = box

    local pick = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    pick:SetSize(24, 24)
    pick:SetPoint("LEFT", box, "RIGHT", 4, 0)
    pick:SetText("…")
    pick:SetScript("OnClick", function() UI.OpenPicker(row) end)
    attachTooltip(pick, L.TIP_PICKER)
    row.pickBtn = pick

    return row
end

function UI.Refresh()
    if not UI._frame or not UI._scrollChild then return end
    Addon.Core.ReconcileLegacy()
    local macros = Addon.Core.GetAllMacros()
    UI._macros = macros

    for _, row in ipairs(UI._rows) do
        row:Hide()
        row.macro = nil
    end

    for i = 1, #macros do
        local row = UI._rows[i]
        if not row then
            row = CreateRow(UI._scrollChild, i)
            UI._rows[i] = row
        end
        row.macro = macros[i]
        row.bg:SetColorTexture(unpack((i % 2 == 0) and Config.COLORS.ROW_A or Config.COLORS.ROW_B))
        row:Show()
        UI.RefreshRow(row)
    end

    UI._scrollChild:SetHeight(math.max(#macros * C.ROW_HEIGHT, 1))
    if #macros == 0 then
        UI.SetStatus(L.ST_NO_MACROS, Config.COLORS.MUTED)
    else
        UI.SetStatus(TL("ST_MACRO_COUNT", #macros), Config.COLORS.MUTED)
    end
end

function UI.ApplyAll()
    local applied, failed, count = Addon.Core.ApplyAll()
    UI.Refresh()
    if Addon.Core._pending then
        UI.SetStatus(L.ST_COMBAT, Config.COLORS.ERR)
    elseif count == 0 then
        UI.SetStatus(L.ST_NO_MACROS, Config.COLORS.MUTED)
    else
        UI.SetStatus(TL("ST_APPLIED_ALL", applied, failed),
            (failed > 0) and Config.COLORS.ERR or Config.COLORS.OK)
    end
end

-- ---------------------------------------------------------------------------
-- Icon picker popup (shared, one instance, opened from a row).
-- ---------------------------------------------------------------------------

function UI.ClosePicker()
    if UI._picker then UI._picker:Hide() end
    UI._pickerTarget = nil
end

local function pickerCommit(row, id)
    local macro = row.macro
    if not macro then return end
    Addon.Core.SetEntry(macro.name, macro.perCharacter, true, id)
    row.check:SetChecked(true)
    if Addon.Core.ApplyMacro(macro) then
        UI.SetStatus(TL("ST_APPLIED", tostring(id), macro.name), Config.COLORS.OK)
    else
        UI.SetStatus(TL("ST_FAILED", macro.name), Config.COLORS.ERR)
    end
    UI.RefreshRow(row)
end

-- Virtualized grid: a fixed pool of buttons renders only the visible rows
-- (GetMacroIcons/GetMacroItemIcons return thousands of icons; creating a button
-- per icon froze the client). Updated on scroll via UI.RenderPickerGrid.
local POOL_ROWS = math.ceil((P.HEIGHT - 40) / P.CELL) + 2

local function renderPickerGrid()
    local child = UI._pickerChild
    if not child then return end
    local icons = UI._iconList or {}
    local total = #icons
    local totalRows = math.ceil(total / P.COLS)
    child:SetHeight(P.PAD * 2 + totalRows * P.CELL)

    if total == 0 then
        for _, b in ipairs(UI._pickerPool) do b:Hide() end
        return
    end

    local offset = 0
    if UI._pickerScroll and UI._pickerScroll.GetVerticalScroll then
        offset = UI._pickerScroll:GetVerticalScroll() or 0
    end
    local firstRow = math.floor(math.max(offset - P.PAD, 0) / P.CELL)
    if firstRow < 0 then firstRow = 0 end
    if firstRow > totalRows then firstRow = totalRows end

    local pool = UI._pickerPool
    local needed = POOL_ROWS * P.COLS
    for k = #pool + 1, needed do
        local b = CreateFrame("Button", nil, child)
        b:SetSize(P.CELL, P.CELL)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints(b)
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b:SetScript("OnClick", function(self)
            if UI._pickerTarget then pickerCommit(UI._pickerTarget, self.iconID) end
            UI.ClosePicker()
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(tostring(self.iconID), 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pool[k] = b
    end

    local used = 0
    for r = 0, POOL_ROWS - 1 do
        local rowIdx = firstRow + r
        if rowIdx >= totalRows then break end
        for c = 0, P.COLS - 1 do
            local idx = rowIdx * P.COLS + c + 1
            used = used + 1
            local b = pool[used]
            if idx <= total then
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", child, "TOPLEFT",
                    P.PAD + c * P.CELL, -(P.PAD + rowIdx * P.CELL))
                b.iconID = icons[idx]
                -- hide rows with invalid fileIDs instead of erroring mid-render
                if pcall(b.icon.SetTexture, b.icon, icons[idx]) then
                    b:Show()
                else
                    b:Hide()
                end
            else
                b:Hide()
            end
        end
    end
    for j = used + 1, #pool do pool[j]:Hide() end
end

function UI.RenderPickerGrid() renderPickerGrid() end

function UI.OpenPicker(row)
    if not UI._picker then return end
    UI._pickerTarget = row
    UI._iconList = Addon.Core.GetIconList() -- rescan: the icon pool may have changed
    if #UI._iconList == 0 then
        UI.SetStatus(L.ST_PICKER_EMPTY, Config.COLORS.ERR)
        UI._pickerTarget = nil
        return
    end
    if UI._pickerScroll and UI._pickerScroll.SetVerticalScroll then
        UI._pickerScroll:SetVerticalScroll(0)
    end
    -- Anchor to the left of the main window so the macro table stays readable;
    -- if there is no room the frame is clamped to the screen. Draggable anyway.
    UI._picker:ClearAllPoints()
    UI._picker:SetPoint("TOPRIGHT", UI._frame, "TOPLEFT", -8, -4)
    UI._picker:Show()
    renderPickerGrid()
end

local function BuildPicker(parent)
    local pf = CreateFrame("Frame", UI.PICKER_NAME, parent, "BackdropTemplate")
    pf:SetSize(P.WIDTH, P.HEIGHT)
    pf:SetFrameStrata("DIALOG")
    pf:SetToplevel(true)
    pf:SetClampedToScreen(true)
    pf:SetMovable(true)
    pf:EnableMouse(true)
    pf:RegisterForDrag("LeftButton")
    pf:SetScript("OnDragStart", pf.StartMoving)
    pf:SetScript("OnDragStop", pf.StopMovingOrSizing)
    pf:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })

    local title = pf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", pf, "TOP", 0, -10)
    title:SetText(L.PICK_TITLE)

    local close = CreateFrame("Button", nil, pf, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() UI.ClosePicker() end)

    local scroll = CreateFrame("ScrollFrame", "$parentScroll", pf, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", pf, "TOPLEFT", 8, -28)
    scroll:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -(8 + 16), 8)
    UI._pickerScroll = scroll
    scroll:HookScript("OnVerticalScroll", function() UI.RenderPickerGrid() end)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(P.WIDTH - 32, 1)
    scroll:SetScrollChild(child)
    UI._pickerChild = child

    pf:Hide()
    UI._picker = pf
    table.insert(UISpecialFrames, UI.PICKER_NAME)
end

-- ---------------------------------------------------------------------------
-- Main window
-- ---------------------------------------------------------------------------

function UI.Build()
    if UI._built and UI._frame then return UI._frame end

    local f = CreateFrame("Frame", UI.FRAME_NAME, UIParent, "BackdropTemplate")
    f:SetSize(C.WIDTH, C.HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -14)
    title:SetText(L.TITLE)

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -2)
    sub:SetText(L.SUB)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", C.LEFT, -54)
    header:SetSize(CONTENT_WIDTH, C.HEADER_HEIGHT)
    UI._header = header

    local function headerLabel(col, key, width)
        local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", header, "LEFT", contentX(col), 0)
        if width then fs:SetWidth(width) end
        fs:SetJustifyH("LEFT")
        fs:SetText(L[key])
        fs:SetTextColor(unpack(Config.COLORS.HEADER))
        return fs
    end
    headerLabel(1, "HEAD_ON")
    headerLabel(2, "HEAD_NAME", C.COL_NAME - 6)
    headerLabel(3, "HEAD_CURRENT", C.COL_CURRENT - 6)
    headerLabel(4, "HEAD_TARGET")
    headerLabel(5, "HEAD_ICON", C.COL_ICON - 6)

    local scroll = CreateFrame("ScrollFrame", "$parentScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", C.LEFT, -(54 + C.HEADER_HEIGHT))
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(C.LEFT + C.SCROLLBAR), 46)
    UI._scrollFrame = scroll

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(CONTENT_WIDTH, 1)
    scroll:SetScrollChild(child)
    UI._scrollChild = child

    local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", C.LEFT + 4, 16)
    status:SetWidth(220)
    status:SetJustifyH("LEFT")
    UI._status = status

    -- Minimap button visibility toggle.
    local lblMini = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lblMini:SetPoint("LEFT", status, "RIGHT", 8, 0)
    lblMini:SetText(L.CHK_MINIMAP)
    local chkMini = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    chkMini:SetSize(20, 20)
    chkMini:SetPoint("LEFT", lblMini, "RIGHT", 2, 0)
    chkMini:SetScript("OnClick", function(cb)
        if Addon.Minimap then
            Addon.Minimap.SetHidden(not (cb:GetChecked() and true or false))
        end
    end)
    attachTooltip(chkMini, L.TIP_MINIMAP)
    UI._chkMinimap = chkMini

    local btnApply = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnApply:SetSize(120, 24)
    btnApply:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -140, 10)
    btnApply:SetText(L.BTN_APPLY)
    btnApply:SetScript("OnClick", function() UI.ApplyAll() end)

    local btnRefresh = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnRefresh:SetSize(120, 24)
    btnRefresh:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    btnRefresh:SetText(L.BTN_REFRESH)
    btnRefresh:SetScript("OnClick", function() UI.Refresh() end)

    -- Publish only once fully built: a mid-build error must not leave a
    -- half-initialised frame behind (otherwise the next Build returns early).
    BuildPicker(f)
    UI._frame = f
    UI._built = true
    table.insert(UISpecialFrames, UI.FRAME_NAME)
    return f
end

function UI.Toggle(show)
    UI.Build()
    if show == nil then show = not UI._frame:IsShown() end
    if show then
        UI.Refresh()
        UI._frame:Show()
        if UI._chkMinimap and Addon.Minimap then
            UI._chkMinimap:SetChecked(not Addon.Minimap.IsHidden())
        end
    else
        UI.ClosePicker()
        UI._frame:Hide()
    end
end
