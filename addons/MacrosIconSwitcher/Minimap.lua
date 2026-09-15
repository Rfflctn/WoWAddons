-- Minimap.lua | MacrosIconSwitcher | Retail 12.1.0
-- Minimap button (draggable) + Addon Compartment registration.
-- Visibility lives in MacrosIconSwitcherDB.minimap.hidden (default: shown).
-- NOTE: the local table is named M on purpose -- a local named Minimap would
-- shadow the global minimap frame used for positioning.

local Addon = _G.MacrosIconSwitcher
local L10n = _G.MacrosIconSwitcherL10n
local L = L10n.L
local Config = _G.MacrosIconSwitcherConfig

local M = {}
Addon.Minimap = M

local btn = nil
local DEFAULT_ANGLE = math.rad(-80)
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function getDB()
    local db = _G.MacrosIconSwitcherDB
    if db and type(db.minimap) == "table" then return db end
    return nil
end

local function position(angle)
    if not btn then return end
    local db = getDB()
    if not db then return end
    db.minimap.angle = angle
    -- Dynamic radius: follows the minimap size AND its scale (GetWidth already
    -- includes the frame scale, SetPoint offsets scale with the button).
    local pad = (Config.MINIMAP and Config.MINIMAP.PADDING) or 4
    local radius = 84
    if Minimap and Minimap.GetWidth then
        radius = (Minimap:GetWidth() or 160) / 2 + pad
    end
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function M.IsHidden()
    local db = getDB()
    return (db and db.minimap.hidden) and true or false
end

function M.SetHidden(hidden)
    local db = _G.MacrosIconSwitcherDB or Addon.EnsureDB()
    db.minimap.hidden = hidden and true or false
    if btn then
        if db.minimap.hidden then
            btn:Hide()
        else
            position(type(db.minimap.angle) == "number" and db.minimap.angle or DEFAULT_ANGLE)
            btn:Show()
        end
    end
end

function M.Toggle()
    M.SetHidden(not M.IsHidden())
end

local function createButton()
    local mc = Config.MINIMAP or {}
    btn = CreateFrame("Button", "MacrosIconSwitcherMinimapButton", Minimap)
    btn:SetFrameStrata("MEDIUM")
    btn:SetSize(31, 31)
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("AnyUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    icon:SetTexture(mc.ICON or 134400)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = icon

    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 0)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    btn.overlay = overlay

    btn:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            M.Toggle()
        else
            Addon.UI.Toggle()
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(L.TITLE, 1, 1, 1, 1, true)
        GameTooltip:AddLine(L.TIP_MINIMAP, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local px, py = GetCursorPosition()
            px, py = px / scale, py / scale
            position(atan2(py - my, px - mx))
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:UnlockHighlight()
        self:SetScript("OnUpdate", nil)
    end)
end

-- Create/attach the button after SavedVariables are available. Safe to call repeatedly.
function M.Ensure()
    if btn then
        if M.IsHidden() then btn:Hide() else btn:Show() end
        return btn
    end
    local ok, result = pcall(createButton)
    if not ok then
        Addon.Log("WARN", "Minimap", "button creation failed: %s", tostring(result))
        btn = nil
        return nil
    end
    if M.IsHidden() then
        btn:Hide()
    else
        local db = getDB()
        position((db and type(db.minimap.angle) == "number") and db.minimap.angle or DEFAULT_ANGLE)
        btn:Show()
    end
    return btn
end

-- Addon Compartment (client addon menu). Guarded: failure degrades to WARN.
function M.RegisterCompartment()
    if M._compartment then return end
    if type(AddonCompartmentFrame) ~= "table" or type(AddonCompartmentFrame.RegisterAddon) ~= "function" then
        return
    end
    local ok = pcall(AddonCompartmentFrame.RegisterAddon, AddonCompartmentFrame, {
        name = Addon.NAME,
        icon = (Config.MINIMAP and Config.MINIMAP.ICON) or 134400,
        title = L.TITLE,
        onClick = function() Addon.UI.Toggle() end,
    })
    if ok then
        M._compartment = true
    else
        Addon.Log("WARN", "Minimap", "AddonCompartment registration failed")
    end
end
