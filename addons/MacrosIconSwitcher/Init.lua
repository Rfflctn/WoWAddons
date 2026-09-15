-- Init.lua | MacrosIconSwitcher | Retail 12.1.0
-- Addon namespace. Loads right after Locales.lua.
-- VERSION must stay in sync with ## Version in the .toc.
-- WoW Lua 5.1: no goto, no //, no bitwise ops. No WoW calls at top level.

_G.MacrosIconSwitcher = _G.MacrosIconSwitcher or {}
local Addon = _G.MacrosIconSwitcher

Addon.NAME = "MacrosIconSwitcher"
Addon.VERSION = "1.1.0"
Addon.DB_SCHEMA = 2

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
-- Schema 2: icons split into two buckets keyed by macro NAME (global macros) and
-- "character|name" (per-character macros). Old flat entries (schema 1) are kept in
-- db.legacyIcons and resolved to the right bucket on first login by Core.ReconcileLegacy().
function Addon.EnsureDB()
    if type(_G.MacrosIconSwitcherDB) ~= "table" then _G.MacrosIconSwitcherDB = {} end
    local db = _G.MacrosIconSwitcherDB
    if db.enabled == nil then db.enabled = true end
    if type(db.minimap) ~= "table" then db.minimap = {} end
    if db.minimap.hidden == nil then db.minimap.hidden = false end
    if type(db.minimap.angle) ~= "number" then db.minimap.angle = math.rad(-80) end

    if type(db.icons) ~= "table" then db.icons = {} end
    if db.schemaVersion == nil or db.schemaVersion < Addon.DB_SCHEMA then
        if next(db.icons) ~= nil then
            db.legacyIcons = db.icons -- flat schema 1 entries, resolved later
        end
        db.icons = { global = {}, char = {} }
        db.schemaVersion = Addon.DB_SCHEMA
    end
    if type(db.icons.global) ~= "table" then db.icons.global = {} end
    if type(db.icons.char) ~= "table" then db.icons.char = {} end
    return db
end

_G.MacrosIconSwitcher = Addon
