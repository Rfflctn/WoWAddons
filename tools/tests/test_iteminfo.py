# -*- coding: utf-8 -*-
# test_iteminfo.py — Services/ItemInfo.lua: bind tri-state, names, pending, prune.

def run(lua, check, exec_):
    # stub bindType 0 (sellable) for known ids
    check('unsellable(999002)=false', 'tostring(DecorLumberProfitItemInfo.IsUnsellable(999002))', 'false')
    check('unsellable(nil)=false', 'tostring(DecorLumberProfitItemInfo.IsUnsellable(nil))', 'false')
    check('unsellable non-number=false', 'tostring(DecorLumberProfitItemInfo.IsUnsellable("x"))', 'false')
    # BoP item: swap stub to return bindType 1 for id 888001
    exec_(r'''
C_Item.GetItemInfo = function(id)
    if id == 888001 then return "Bound Sword", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 1 end
    local names = { [256963]="Thalassian Lumber", [999001]="Sturdy Handle", [999002]="Oak Output" }
    return names[id], nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 0
end
GetItemInfo = C_Item.GetItemInfo
''')
    check('unsellable BoP=true', 'tostring(DecorLumberProfitItemInfo.IsUnsellable(888001))', 'true')
    # unknown id, no data: GetItemInfo returns nils -> bind nil -> tri-state nil
    exec_(r'''
C_Item.GetItemInfo = function(id) return nil end
GetItemInfo = function(id) return nil end
TRI = DecorLumberProfitItemInfo.IsUnsellable(777001)
''')
    check('unsellable unknown=nil', 'tostring(TRI)', 'nil')
    # pending add / count / fail / resolve
    exec_(r'''
DecorLumberProfitItemInfo.PendingAdd(101, { recipeSpellID=101, outputItemID=777001 })
DecorLumberProfitItemInfo.PendingAdd(102, { recipeSpellID=102, outputItemID=777002 })
PEND1 = DecorLumberProfitItemInfo.PendingCount()
DecorLumberProfitItemInfo.FailPendingForItem(777001)
PEND2 = DecorLumberProfitItemInfo.PendingCount()
''')
    check('pending count 2', 'PEND1', '2')
    check('pending count 1 after fail', 'PEND2', '1')
    # prune: BoP-output recipe removed, sellable kept
    exec_(r'''
C_Item.GetItemInfo = function(id)
    if id == 888001 then return "Bound Sword", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 1 end
    return "Sellable", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 0
end
GetItemInfo = C_Item.GetItemInfo
PRUNE_LIST = {
    { recipeSpellID=201, outputItemID=888001 },
    { recipeSpellID=202, outputItemID=999002 },
}
PRUNED = DecorLumberProfitItemInfo.PruneUnsellable(PRUNE_LIST)
''')
    check('prune removed 1', 'PRUNED', '1')
    check('prune kept sellable', 'PRUNE_LIST[1].recipeSpellID', '202')
    check('prune nil list=0', 'DecorLumberProfitItemInfo.PruneUnsellable(nil)', '0')
    # Core wrappers still delegate (compat)
    check('core IsOutputUnsellable delegates', 'tostring(DecorLumberProfitCore:IsOutputUnsellable(888001))', 'true')
    check('core PruneUnsellable delegates', 'DecorLumberProfitCore:PruneUnsellable({ { recipeSpellID=301, outputItemID=888001 } })', '1')
    check('core pending alias shares store', 'tostring(DecorLumberProfitCore._pendingBind == DecorLumberProfitItemInfo._pending)', 'true')
    # names
    check('getname caches', 'DecorLumberProfitItemInfo.GetName(999002)', 'Sellable')
    check('healthcheck ok', 'tostring(DecorLumberProfitItemInfo.HealthCheck().ok)', 'true')
