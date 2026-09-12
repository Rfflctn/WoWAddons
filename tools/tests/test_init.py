# -*- coding: utf-8 -*-
# test_init.py — Init.lua: namespace, VERSION, SafeCall, CountTable, Log fallback.

def run(lua, check, exec_):
    check('addon namespace exists', 'tostring(DecorLumberProfit ~= nil)', 'true')
    check('addon name', 'DecorLumberProfit.NAME', 'DecorLumberProfit')
    check('addon version', 'DecorLumberProfit.VERSION', '2.1.0')
    check('addon db schema v2', 'DecorLumberProfit.DB_SCHEMA', '2')
    exec_('ADDON_SC_OK, ADDON_SC_VAL = DecorLumberProfit.SafeCall(function(a, b) return a + b end, 2, 3)')
    check('safecall ok', 'tostring(ADDON_SC_OK)', '5')
    check('safecall single extra return dropped', 'tostring(ADDON_SC_VAL)', 'nil')
    exec_('ADDON_SC_E = DecorLumberProfit.SafeCall(function() error("kablam") end)')
    check('safecall error -> nil', 'tostring(ADDON_SC_E)', 'nil')
    check('safecall non-function -> nil', 'tostring((function() local ok, _ = DecorLumberProfit.SafeCall(nil) return ok end)())', 'nil')
    check('count empty', 'DecorLumberProfit.CountTable({})', '0')
    check('count non-table', 'DecorLumberProfit.CountTable(nil)', '0')
    exec_('ADDON_CT = DecorLumberProfit.CountTable({ a = 1, b = 2, c = 3 })')
    check('count 3', 'ADDON_CT', '3')
    # Diag must report the version owned by Init (single source).
    check('diag version tracks init', 'tostring(string.find(DecorLumberProfitDiag.ADDON_VERSION, "2.1.0", 1, true) ~= nil)', 'true')
