# -*- coding: utf-8 -*-
# test_recipes.py — GetRecipeData / wood detection / unified Scan / debug.

def run(lua, check, exec_):
    exec_('RD = DecorLumberProfitCore:GetRecipeData(424242)')
    check('GetRecipeData name', 'RD.name', 'Craft Oak Output')
    check('GetRecipeData woodQty', 'RD.woodQty', '2')
    check('GetRecipeData woodItemID', 'RD.woodItemID', '256963')
    check('GetRecipeData reagents count', '#RD.reagents', '2')
    check('GetRecipeData reagent1 isWood', 'tostring(RD.reagents[1].isWood)', 'true')
    check('GetRecipeData learned', 'tostring(RD.learned)', 'true')
    # bindType 0 (stub) = sellable -> IsOutputUnsellable false
    check('OutputIsUnsellable(999002)=false',
          'tostring(DecorLumberProfitCore:IsOutputUnsellable(999002))', 'false')
    # non-number input must not error, returns false
    check('OutputIsUnsellable(nil)=false',
          'tostring(DecorLumberProfitCore:IsOutputUnsellable(nil))', 'false')
    check('IsWoodItem(256963)', 'tostring(DecorLumberProfitCore:IsWoodItem(256963))', 'true')
    check('IsWoodItem(999001)', 'tostring(DecorLumberProfitCore:IsWoodItem(999001))', 'false')

    # ---- unified Scan, scope=active (stub primary path: GetAllRecipeIDs) ----
    exec_(r'''
SCAN_RES, SCAN_ERR, SCAN_META = DecorLumberProfitCore:FindWoodRecipesInActiveWindow()
SCAN_ALL, SCAN_ALL_ERR, SCAN_ALL_META = DecorLumberProfitCore:FindWoodRecipes()
''')
    check('scan active found 1', '#SCAN_RES', '1')
    check('scan active no err', 'tostring(SCAN_ERR)', 'nil')
    check('scan active meta scanned', 'SCAN_META.scanned', '1')
    check('scan active meta found', 'SCAN_META.found', '1')
    check('scan active result name', 'SCAN_RES[1].name', 'Craft Oak Output')
    check('scan all found 1', '#SCAN_ALL', '1')
    check('scan all no err', 'tostring(SCAN_ALL_ERR)', 'nil')
    check('scan all meta scanned', 'SCAN_ALL_META.scanned', '1')

    # ---- Debug smoke ----
    exec_(r'''
DA = DecorLumberProfitCore:DebugActive()
DS = DecorLumberProfitCore:DebugSpell(424242)
''')
    check('debug active candidates', 'DA.candidateCount', '1')
    check('debug active wood count', '#DA.woodIDs', '12')
    check('debug spell name', 'DS.name', 'Craft Oak Output')
    check('debug spell woodQty', 'DS.woodQty', '2')

    # ---- flags ----
    check('bruteforce default on', 'tostring(DecorLumberProfitRecipes.BruteForceEnabled())', 'true')
    check('maxresults default 500', 'DecorLumberProfitRecipes.MaxResults()', '500')
    exec_(r'''
DecorLumberProfitConfig.SCAN.MAX_RESULTS = 5
CLAMP_LO = DecorLumberProfitRecipes.MaxResults()
DecorLumberProfitConfig.SCAN.MAX_RESULTS = 999999
CLAMP_HI = DecorLumberProfitRecipes.MaxResults()
DecorLumberProfitConfig.SCAN.MAX_RESULTS = 500
''')
    check('maxresults clamps low to 50', 'CLAMP_LO', '50')
    check('maxresults clamps high to 5000', 'CLAMP_HI', '5000')
    exec_('DecorLumberProfitConfig.SCAN.ENABLE_BRUTEFORCE = false')
    check('bruteforce off', 'tostring(DecorLumberProfitRecipes.BruteForceEnabled())', 'false')
    exec_(r'''
DecorLumberProfitConfig.SCAN.ENABLE_BRUTEFORCE = true
SCAN_NOBRUTE, SCAN_NOBRUTE_ERR = DecorLumberProfitCore:FindWoodRecipesInActiveWindow()
''')
    check('scan works with bruteforce on (primary path)', '#SCAN_NOBRUTE', '1')
    check('recipes healthcheck ok', 'tostring(DecorLumberProfitRecipes.HealthCheck().ok)', 'true')

    # ---- active skill line roundtrip ----
    exec_(r'''
DecorLumberProfitCore:SetActiveSkillLineID(1234)
GOT_SID = DecorLumberProfitCore:GetActiveSkillLineID()
''')
    check('active skillline roundtrip', 'GOT_SID', '1234')
    check('scanremember no GetProfessionSpells=0',
          'DecorLumberProfitCore:ScanAndRememberCurrentProfession()', '0')

    # ---- error branches (stub API emptied) ----
    # NOTE: _activeSkillLineID=1234 was set above and Scan remembered 424242 into
    # DB.knownRecipes — both persist in this runtime, so:
    # active+empty candidates => NO_RECIPES_IN_ACTIVE_WINDOW (skill line known),
    # all+DB evidence => still finds; clear DB first for the truly-empty case.
    exec_(r'''
C_TradeSkillUI.GetAllRecipeIDs = function() return {} end
E1, E1E = DecorLumberProfitCore:FindWoodRecipesInActiveWindow()
DecorLumberProfitDB = { knownRecipes = {} }
DecorLumberProfitCharDB = { seenRecipes = {} }
E2, E2E = DecorLumberProfitCore:FindWoodRecipes()
''')
    check('scan active empty window err', 'E1E', 'NO_RECIPES_IN_ACTIVE_WINDOW')
    check('scan all empty err', 'E2E', 'NO_RECIPES_ENUMERATED')

    # ---- WOOD_ID_NOT_SET (both Wood and Config emptied) ----
    exec_(r'''
SAVED_WOOD_IDS = DecorLumberProfitWood.IDS
SAVED_CFG_IDS = DecorLumberProfitConfig.WOOD_ITEM_IDS
DecorLumberProfitWood.IDS = {}
DecorLumberProfitConfig.WOOD_ITEM_IDS = {}
E3, E3E = DecorLumberProfitCore:FindWoodRecipes()
DecorLumberProfitWood.IDS = SAVED_WOOD_IDS
DecorLumberProfitConfig.WOOD_ITEM_IDS = SAVED_CFG_IDS
''')
    check('scan no wood ids err', 'E3E', 'WOOD_ID_NOT_SET')
