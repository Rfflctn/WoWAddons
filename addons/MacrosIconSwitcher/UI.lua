-- UI.lua | MacrosIconSwitcher | Retail 12.1.0
-- The macro table window: one row per macro with a checkbox and an icon-ID field.
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
UI._frame = nil
UI._built = false
UI._rows = {}
UI._macros = {}

local C = Config.UI

-- Column origins relative to the content area (0 = left edge of the scroll child).
local function contentX(n)
    if n == 1 then return 0 end
    if n == 2 then return C.COL_CHECK end
    if n == 3 then return C.COL_CHECK + C.COL_NAME end
    return C.COL_CHECK + C.COL_NAME + C.COL_CURRENT
end

local CONTENT_WIDTH = C.COL_CHECK + C.COL_NAME + C.COL_CURRENT + C.COL_ICON

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
    local entry = Addon.Core.GetEntry(macro.name)
    local enabled = (entry and entry.enabled) and true or false

    row.check:SetChecked(enabled)
    row.nameText:SetText(macro.name)
    row.iconBox:SetShown(enabled)
    row.iconBox:SetText((entry and entry.icon) and tostring(entry.icon) or "")

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
        Addon.Core.SetEntry(macro.name, true, id)
        row.check:SetChecked(true)
        row.iconBox:SetShown(true)
        if Addon.Core.ApplyByName(macro.name) then
            UI.SetStatus(TL("ST_APPLIED", tostring(id), macro.name), Config.COLORS.OK)
        else
            UI.SetStatus(TL("ST_FAILED", macro.name), Config.COLORS.ERR)
        end
    else
        Addon.Core.SetEntry(macro.name, true, nil)
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
        Addon.Core.SetEntry(macro.name, checked, nil)
        row.iconBox:SetShown(checked)
        if checked then
            local entry = Addon.Core.GetEntry(macro.name)
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

    local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    box:SetHeight(20)
    box:SetWidth(C.COL_ICON - 14)
    box:SetPoint("LEFT", row, "LEFT", contentX(4), 0)
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

    return row
end

function UI.Refresh()
    if not UI._frame or not UI._scrollChild then return end
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
    headerLabel(4, "HEAD_ICON", C.COL_ICON - 6)

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
    status:SetWidth(300)
    status:SetJustifyH("LEFT")
    UI._status = status

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
    else
        UI._frame:Hide()
    end
end
