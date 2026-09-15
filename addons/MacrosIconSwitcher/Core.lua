-- Core.lua | MacrosIconSwitcher | Retail 12.1.0
-- Macro scan + icon application. No UI here (see UI.lua), no slash handling (see Commands.lua).
-- API used: GetNumMacros / GetMacroInfo / GetMacroIndexByName (globals), EditMacro (global),
-- GetMacroIcons / GetMacroItemIcons (icon list for the picker).
-- All optional calls guarded: a missing/blocked macro API degrades to a WARN, never a Lua error.

local Addon = _G.MacrosIconSwitcher
local Core = {}
Addon.Core = Core

local MAX_ACCOUNT_MACROS = 120
local MAX_CHAR_MACROS = 30

-- Re-entrancy guard: EditMacro fires UPDATE_MACROS synchronously, we must not
-- treat our own edit as an external change (would refresh the UI mid-edit).
Core._editDepth = 0
Core._pending = false -- apply was requested during combat lockdown

function Core.IsApplying()
    return Core._editDepth > 0
end

-- Macro indices are global slots 1..numGlobal and per-character slots 121..120+numPerChar.
local function getScanRanges()
    local numGlobal, numPerChar = 0, 0
    if type(GetNumMacros) == "function" then
        local ok, g, c = pcall(GetNumMacros)
        if ok then
            numGlobal = tonumber(g) or 0
            numPerChar = tonumber(c) or 0
        end
    end
    if numGlobal < 0 then numGlobal = 0 end
    if numGlobal > MAX_ACCOUNT_MACROS then numGlobal = MAX_ACCOUNT_MACROS end
    if numPerChar < 0 then numPerChar = 0 end
    if numPerChar > MAX_CHAR_MACROS then numPerChar = MAX_CHAR_MACROS end
    return numGlobal, numPerChar
end

-- Returns an array of { index = number, name = string, icon = number, body = string, perCharacter = bool }.
function Core.GetAllMacros()
    local macros = {}
    if type(GetMacroInfo) ~= "function" then return macros end
    local numGlobal, numPerChar = getScanRanges()

    local function scan(from, to, perChar)
        for i = from, to do
            local name, icon, body = GetMacroInfo(i)
            if name and name ~= "" then
                macros[#macros + 1] = {
                    index = i,
                    name = name,
                    icon = icon,
                    body = body,
                    perCharacter = perChar,
                }
            end
        end
    end

    scan(1, numGlobal, false)
    scan(MAX_ACCOUNT_MACROS + 1, MAX_ACCOUNT_MACROS + numPerChar, true)
    return macros
end

-- DB keys: global macros -> name; per-character macros -> "character|name"
-- (SavedVariables are account-wide, so the character must be part of the key).
local function charKey(name)
    local charName = Addon.SafeCall(UnitName, "player") or ""
    return charName .. "|" .. name
end

function Core.GetEntry(name, perChar)
    local db = _G.MacrosIconSwitcherDB
    if not db or type(db.icons) ~= "table" then return nil end
    local bucket = perChar and db.icons.char or db.icons.global
    if type(bucket) ~= "table" then return nil end
    return bucket[perChar and charKey(name) or name]
end

-- perChar: boolean; enabled: boolean|nil (nil = leave as-is); icon: number|string|nil (nil = leave as-is).
function Core.SetEntry(name, perChar, enabled, icon)
    local db = _G.MacrosIconSwitcherDB
    if not db or not name or name == "" then return end
    if type(db.icons) ~= "table" then db.icons = { global = {}, char = {} } end
    local bucket
    if perChar then
        db.icons.char = db.icons.char or {}
        bucket = db.icons.char
    else
        db.icons.global = db.icons.global or {}
        bucket = db.icons.global
    end
    local key = perChar and charKey(name) or name
    local entry = bucket[key]
    if not entry then
        entry = {}
        bucket[key] = entry
    end
    if enabled ~= nil then entry.enabled = enabled and true or false end
    if icon ~= nil then entry.icon = icon end
    if not entry.enabled and entry.icon == nil then bucket[key] = nil end
end

-- Icons may be a FileDataID (number) or a texture path (string); both are accepted by EditMacro.
function Core.IsValidIcon(icon)
    if type(icon) == "number" then return icon > 0 end
    if type(icon) == "string" then return icon ~= "" end
    return false
end

function Core.ClearEntry(name, perChar)
    local db = _G.MacrosIconSwitcherDB
    if not db or type(db.icons) ~= "table" then return end
    local bucket = perChar and db.icons.char or db.icons.global
    if type(bucket) == "table" then bucket[perChar and charKey(name) or name] = nil end
end

function Core.ClearAll()
    local db = _G.MacrosIconSwitcherDB
    if db then db.icons = { global = {}, char = {} } end
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
    if type(index) ~= "number" or not Core.IsValidIcon(iconFileID) then return false end
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

-- Find the macro slot by name AND scope (global vs per-character), 0 if not found.
function Core.FindMacroIndex(name, perChar)
    if type(GetMacroInfo) ~= "function" then return 0 end
    local numGlobal, numPerChar = getScanRanges()
    if perChar then
        for i = MAX_ACCOUNT_MACROS + 1, MAX_ACCOUNT_MACROS + numPerChar do
            if GetMacroInfo(i) == name then return i end
        end
    else
        for i = 1, numGlobal do
            if GetMacroInfo(i) == name then return i end
        end
    end
    return 0
end

-- Apply the saved icon for a macro described by a GetAllMacros() row.
function Core.ApplyMacro(macro)
    if not macro or not macro.name then return false end
    local entry = Core.GetEntry(macro.name, macro.perCharacter)
    if not entry or not entry.enabled or not Core.IsValidIcon(entry.icon) then return false end
    local index = Core.FindMacroIndex(macro.name, macro.perCharacter)
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
        local entry = Core.GetEntry(macro.name, macro.perCharacter)
        if entry and entry.enabled and Core.IsValidIcon(entry.icon) then
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

-- Icon list for the picker: macro spell icons + item icons, deduplicated, as FileDataIDs.
function Core.GetIconList()
    local list = {}
    local seen = {}
    local sources = { "GetMacroIcons", "GetMacroItemIcons" }
    for _, fname in ipairs(sources) do
        local f = _G[fname]
        if type(f) == "function" then
            local ok, icons = pcall(f)
            if ok and type(icons) == "table" then
                for _, id in ipairs(icons) do
                    if Core.IsValidIcon(id) and not seen[id] then
                        seen[id] = true
                        list[#list + 1] = id
                    end
                end
            end
        end
    end
    return list
end

-- Schema 1 -> 2 migration: assign each flat (name-keyed) entry to a bucket by matching
-- it against the live macro list. Runs on PLAYER_LOGIN / before the first UI refresh,
-- because the macro list is not available at ADDON_LOADED.
function Core.ReconcileLegacy()
    local db = _G.MacrosIconSwitcherDB
    if not db or type(db.legacyIcons) ~= "table" then return end
    if type(db.icons) ~= "table" or type(db.icons.global) ~= "table" or type(db.icons.char) ~= "table" then return end

    local macros = Core.GetAllMacros()
    for name, entry in pairs(db.legacyIcons) do
        if type(entry) == "table" then
            local placedGlobal = false
            local placedAny = false
            for _, macro in ipairs(macros) do
                if macro.name == name then
                    if macro.perCharacter then
                        local key = charKey(name)
                        if db.icons.char[key] == nil then db.icons.char[key] = entry end
                        placedAny = true
                    elseif not placedGlobal then
                        if db.icons.global[name] == nil then db.icons.global[name] = entry end
                        placedGlobal = true
                        placedAny = true
                    end
                end
            end
            if not placedAny and db.icons.global[name] == nil then
                db.icons.global[name] = entry -- unknown yet: default to global bucket
            end
        end
    end
    db.legacyIcons = nil
    Addon.Log("INFO", "Core", "legacy icons migrated to schema 2")
end
