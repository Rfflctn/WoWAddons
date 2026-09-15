-- Core.lua | MacrosIconSwitcher | Retail 12.1.0
-- Macro scan + icon application. No UI here (see UI.lua), no slash handling (see Commands.lua).
-- API used: GetNumMacros / GetMacroInfo / GetMacroIndexByName (globals), EditMacro (global).
-- All optional calls guarded: a missing/blocked macro API degrades to a WARN, never a Lua error.

local Addon = _G.MacrosIconSwitcher
local Core = {}
Addon.Core = Core

local MAX_ACCOUNT_MACROS = 120
local MAX_MACRO_SLOTS = 150

-- Re-entrancy guard: EditMacro fires UPDATE_MACROS synchronously, we must not
-- treat our own edit as an external change (would refresh the UI mid-edit).
Core._editDepth = 0
Core._pending = false -- apply was requested during combat lockdown

function Core.IsApplying()
    return Core._editDepth > 0
end

local function getNumSlots()
    local numGlobal, numPerChar = 0, 0
    if type(GetNumMacros) == "function" then
        local ok, g, c = pcall(GetNumMacros)
        if ok then
            numGlobal = tonumber(g) or 0
            numPerChar = tonumber(c) or 0
        end
    end
    local total = numGlobal + numPerChar
    if total <= 0 or total > MAX_MACRO_SLOTS then total = MAX_MACRO_SLOTS end
    return total
end

-- Returns an array of { index = number, name = string, icon = number, body = string, perCharacter = bool }.
function Core.GetAllMacros()
    local macros = {}
    if type(GetMacroInfo) ~= "function" then return macros end
    for i = 1, getNumSlots() do
        local name, icon, body = GetMacroInfo(i)
        if name and name ~= "" then
            macros[#macros + 1] = {
                index = i,
                name = name,
                icon = icon,
                body = body,
                perCharacter = i > MAX_ACCOUNT_MACROS,
            }
        end
    end
    return macros
end

function Core.GetEntry(name)
    local db = _G.MacrosIconSwitcherDB
    if not db or not db.icons then return nil end
    return db.icons[name]
end

-- enabled: boolean|nil (nil = leave as-is); icon: number|nil (nil = leave as-is).
function Core.SetEntry(name, enabled, icon)
    local db = _G.MacrosIconSwitcherDB
    if not db or not name or name == "" then return end
    db.icons = db.icons or {}
    local entry = db.icons[name]
    if not entry then
        entry = {}
        db.icons[name] = entry
    end
    if enabled ~= nil then entry.enabled = enabled and true or false end
    if icon ~= nil then entry.icon = icon end
    if not entry.enabled and entry.icon == nil then db.icons[name] = nil end
end

function Core.ClearEntry(name)
    local db = _G.MacrosIconSwitcherDB
    if db and db.icons then db.icons[name] = nil end
end

function Core.ClearAll()
    local db = _G.MacrosIconSwitcherDB
    if db then db.icons = {} end
end

function Core.IsAutoEnabled()
    local db = _G.MacrosIconSwitcherDB
    return not (db and db.enabled == false)
end

function Core.SetAutoEnabled(on)
    local db = _G.MacrosIconSwitcherDB or Addon.EnsureDB()
    db.enabled = on and true or false
    return db.enabled
end

-- Apply one icon to the macro in slot `index`. Returns true on success (or if already set).
function Core.ApplyIcon(index, iconFileID)
    if type(index) ~= "number" or type(iconFileID) ~= "number" or iconFileID <= 0 then return false end
    if type(GetMacroInfo) ~= "function" or type(EditMacro) ~= "function" then
        Addon.Log("WARN", "Core", "macro API unavailable (GetMacroInfo/EditMacro)")
        return false
    end
    local name, currentIcon = GetMacroInfo(index)
    if not name then return false end
    if currentIcon == iconFileID then return true end -- idempotent: nothing to do

    Core._editDepth = Core._editDepth + 1
    local ok, newIndex = pcall(EditMacro, index, nil, iconFileID, nil)
    Core._editDepth = Core._editDepth - 1
    if not ok then
        Addon.Log("WARN", "Core", "EditMacro failed for slot %d: %s", index, tostring(newIndex))
        return false
    end
    if not newIndex or newIndex == 0 then return false end
    return true
end

-- Apply the saved icon for a macro looked up by name.
function Core.ApplyByName(name)
    local entry = Core.GetEntry(name)
    if not entry or not entry.enabled or type(entry.icon) ~= "number" or entry.icon <= 0 then return false end
    local index = 0
    if type(GetMacroIndexByName) == "function" then
        index = GetMacroIndexByName(name) or 0
    end
    if index == 0 then return false end
    return Core.ApplyIcon(index, entry.icon)
end

-- Apply every enabled entry. Returns applied, failed, macroCount.
-- During combat lockdown it sets Core._pending and returns 0, 0, macroCount.
function Core.ApplyAll()
    local macros = Core.GetAllMacros()
    if #macros == 0 then return 0, 0, 0 end

    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        Core._pending = true
        return 0, 0, #macros
    end

    local applied, failed = 0, 0
    for _, macro in ipairs(macros) do
        local entry = Core.GetEntry(macro.name)
        if entry and entry.enabled and type(entry.icon) == "number" and entry.icon > 0 then
            if Core.ApplyIcon(macro.index, entry.icon) then
                applied = applied + 1
            else
                failed = failed + 1
            end
        end
    end
    Core._pending = false
    return applied, failed, #macros
end
