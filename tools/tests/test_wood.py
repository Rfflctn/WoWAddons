# -*- coding: utf-8 -*-
# test_wood.py — Data/Wood contract (currently served by Config.lua,
# after Этап 2 will be served by Data/Wood.lua — same assertions).

def run(lua, check, exec_):
    exec_(r'''
WOOD_IDS = DecorLumberProfitConfig.WOOD_ITEM_IDS
local seen, dups = {}, 0
for _, id in ipairs(WOOD_IDS) do if seen[id] then dups = dups + 1 end seen[id] = true end
WOOD_COUNT = #WOOD_IDS
WOOD_DUPS = dups
-- set matches array?
local setOk = true
for _, id in ipairs(WOOD_IDS) do
    if not DecorLumberProfitConfig.WOOD_IDS_SET[id] then setOk = false end
end
WOOD_SET_OK = setOk
WOOD_HAS_THAL = DecorLumberProfitConfig.WOOD_IDS_SET[256963] == true
WOOD_NAMES_N = (DecorLumberProfitConfig.WOOD_NAMES and #DecorLumberProfitConfig.WOOD_NAMES or 0)
''')
    check('wood count == 12', 'WOOD_COUNT', '12')
    check('wood ids unique', 'WOOD_DUPS', '0')
    check('wood set matches array', 'tostring(WOOD_SET_OK)', 'true')
    check('wood set has Thalassian 256963', 'tostring(WOOD_HAS_THAL)', 'true')
    check('wood names non-empty', 'tostring(WOOD_NAMES_N > 0)', 'true')
    # Этап 2: DecorLumberProfitWood namespace must mirror Config (same tables).
    check('wood namespace exists', 'tostring(DecorLumberProfitWood ~= nil)', 'true')
    check('wood IDS is Config table', 'tostring(DecorLumberProfitWood.IDS == DecorLumberProfitConfig.WOOD_ITEM_IDS)', 'true')
    check('wood SET is Config table', 'tostring(DecorLumberProfitWood.SET == DecorLumberProfitConfig.WOOD_IDS_SET)', 'true')
    check('wood NAMES is Config table', 'tostring(DecorLumberProfitWood.NAMES == DecorLumberProfitConfig.WOOD_NAMES)', 'true')
    check('wood default id Thalassian', 'DecorLumberProfitWood.DEFAULT_ID', '256963')
