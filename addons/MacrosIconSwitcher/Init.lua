-- Init.lua | MacrosIconSwitcher | Retail 12.1.0
-- Addon namespace. Loads right after Locales.lua.
-- VERSION must stay in sync with ## Version in the .toc.
-- WoW Lua 5.1: no goto, no //, no bitwise ops. No WoW calls at top level.

_G.MacrosIconSwitcher = _G.MacrosIconSwitcher or {}
local Addon = _G.MacrosIconSwitcher

Addon.NAME = "MacrosIconSwitcher"
Addon.VERSION = "1.0.0"
Addon.DB_SCHEMA = 1

-- pcall wrapper: first result or nil (never throws). Call sites use `local x = SafeCall(f)`.
function Addon.SafeCall(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, result = pcall(func, ...)
    if ok then return result end
    return nil
end

function Addon.Log(level, module, fmt, ...)
    local msg = fmt or ""
    if select("#", ...) > 0 then
        local ok, s = pcall(string.format, fmt, ...)
        if ok then msg = s end
    end
    print("|cff33ff99" .. tostring(Addon.NAME) .. "|r [" .. tostring(level or "INFO") .. "] " .. tostring(msg))
end

-- Create/repair the account-wide saved variables. Safe to call on every ADDON_LOADED.
function Addon.EnsureDB()
    if type(_G.MacrosIconSwitcherDB) ~= "table" then _G.MacrosIconSwitcherDB = {} end
    local db = _G.MacrosIconSwitcherDB
    if type(db.icons) ~= "table" then db.icons = {} end
    if db.enabled == nil then db.enabled = true end
    if type(db.schemaVersion) ~= "number" then db.schemaVersion = Addon.DB_SCHEMA end
    return db
end

_G.MacrosIconSwitcher = Addon
