-- Commands.lua | MacrosIconSwitcher | Retail 12.1.0
-- Slash commands and client events. No macro logic here (see Core.lua).

local Addon = _G.MacrosIconSwitcher
local L10n = _G.MacrosIconSwitcherL10n
local L = L10n.L
local Core = Addon.Core
local UI = Addon.UI

local loginApply = false

local function doLoginApply()
    if not loginApply then return end
    local applied, failed, count = Core.ApplyAll()
    if count > 0 then
        loginApply = false
        Addon.Log("INFO", "Login", "icons applied=%d failed=%d", applied, failed)
    end
end

local function registerSlash()
    SLASH_MACROSICONSWITCHER1 = "/mis"
    SLASH_MACROSICONSWITCHER2 = "/macroicons"
    SlashCmdList["MACROSICONSWITCHER"] = function(msg)
        msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if msg == "" or msg == "show" or msg == "toggle" then
            UI.Toggle()
        elseif msg == "apply" then
            UI.ApplyAll()
        elseif msg == "refresh" then
            UI.Toggle(true)
        elseif msg == "reset" then
            Core.ClearAll()
            Core.SetAutoEnabled(true)
            if UI.IsShown() then UI.Refresh() end
            print("|cff33ff99" .. Addon.NAME .. "|r: " .. L.ST_RESET)
        elseif msg == "on" then
            Core.SetAutoEnabled(true)
            print("|cff33ff99" .. Addon.NAME .. "|r: " .. L.ST_AUTO_ON)
        elseif msg == "off" then
            Core.SetAutoEnabled(false)
            print("|cff33ff99" .. Addon.NAME .. "|r: " .. L.ST_AUTO_OFF)
        else
            print("|cff33ff99" .. Addon.NAME .. "|r: " .. L.PRINT_HELP)
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("UPDATE_MACROS")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= Addon.NAME then return end
        Addon.EnsureDB()
        L10n.SetLocale(L10n.DetectLocale())
    elseif event == "PLAYER_LOGIN" then
        Addon.EnsureDB()
        loginApply = Core.IsAutoEnabled()
        if loginApply then
            if C_Timer and C_Timer.After then
                C_Timer.After(1, doLoginApply)
                C_Timer.After(4, doLoginApply)
                C_Timer.After(8, function() loginApply = false end)
            else
                doLoginApply()
                loginApply = false
            end
        end
    elseif event == "UPDATE_MACROS" then
        if Core.IsApplying() then return end
        if loginApply then
            doLoginApply()
        elseif UI.IsShown() then
            UI.Refresh()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if Core._pending then
            local applied, failed = Core.ApplyAll()
            if UI.IsShown() then UI.Refresh() end
            Addon.Log("INFO", "Combat", "deferred apply: applied=%d failed=%d", applied, failed)
        end
    end
end)

registerSlash()
