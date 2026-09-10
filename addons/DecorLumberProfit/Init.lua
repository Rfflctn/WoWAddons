-- Init.lua | DecorLumberProfit | Retail 12.1.0
-- Addon namespace (Этап 1). Грузится вторым, сразу после Locales.lua.
-- VERSION дублирует ## Version из TOC; общие SafeCall/CountTable/Log.
-- WoW Lua 5.1: no goto, no //, no bitwise ops. No WoW calls at top level.

_G.DecorLumberProfit = _G.DecorLumberProfit or {}
local Addon = _G.DecorLumberProfit

Addon.NAME = "DecorLumberProfit"
Addon.VERSION = "2.0.0" -- держать в sync с ## Version в .toc (чеклист релиза, Этап 10)
Addon.DB_SCHEMA = 1 -- владеет Services/DB.lua (с Этапа 5); константа живёт здесь

local unpack = unpack or table.unpack -- WoW: Lua 5.1 global; тесты: lupa 5.4 table.unpack

-- pcall-обёртка со СТАРЫМ контрактом Core (Этап 4 зафиксировал тестом):
-- возвращает ПЕРВЫЙ результат или nil (не бросает). Вторые+ возвраты отбрасываются —
-- кому нужен multi-return, тот использует raw pcall явно (как C_Item.GetItemInfo-коллы).
-- NB: НЕ возвращать ok первым значением — все колл-сайты пишут `local x = SafeCall(f)`.
function Addon.SafeCall(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, result = pcall(func, ...)
    if ok then return result end
    return nil
end

function Addon.CountTable(t)
    if type(t) ~= "table" then return 0 end
    local c = 0
    for _ in pairs(t) do c = c + 1 end
    return c
end

-- Лог: если Diag уже загружен — делегируем (уровни/verbose), иначе plain print.
function Addon.Log(level, module, fmt, ...)
    local Diag = _G.DecorLumberProfitDiag
    if Diag and Diag.Log then
        return Diag.Log(level, module, fmt, ...)
    end
    local msg = fmt or ""
    if select("#", ...) > 0 then
        local ok, s = pcall(string.format, fmt, ...)
        if ok then msg = s end
    end
    print("[" .. tostring(module or Addon.NAME) .. "/" .. tostring(level or "INFO") .. "] " .. tostring(msg))
end

_G.DecorLumberProfit = Addon
