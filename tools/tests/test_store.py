# -*- coding: utf-8 -*-
# test_store.py — Services/Store.lua: Upgrade, Remember, Save/Load, cap, wrappers.

REC = ('{ recipeSpellID=424242, name="Craft Oak Output", profession="Carpentry",'
       ' outputItemID=999002, outputQty=1, outputMin=1, outputMax=1, icon="icon",'
       ' woodQty=2, woodItemID=256963, woodName="Thalassian Lumber",'
       ' reagents={ { itemID=256963, quantity=2, isWood=true }, { itemID=999001, quantity=3 } },'
       ' learned=true }')


def run(lua, check, exec_):
    # ---- Upgrade on empty globals ----
    exec_(r'''
DecorLumberProfitDB = nil
DecorLumberProfitCharDB = nil
DecorLumberProfitStore.Upgrade()
''')
    check('upgrade creates DB', 'tostring(DecorLumberProfitDB ~= nil)', 'true')
    check('upgrade schema stamped', 'DecorLumberProfitDB.schemaVersion', '1')
    check('upgrade recipes table', 'tostring(DecorLumberProfitDB.recipes ~= nil)', 'true')
    check('upgrade known table', 'tostring(DecorLumberProfitDB.knownRecipes ~= nil)', 'true')
    check('upgrade settings table', 'tostring(DecorLumberProfitDB.settings ~= nil)', 'true')
    check('upgrade chardb seen', 'tostring(DecorLumberProfitCharDB.seenRecipes ~= nil)', 'true')

    # ---- legacy adoption (v1.4.0 rename) ----
    exec_(r'''
DecorLumberProfitDB = nil
DecorLumberProfitCharDB = nil
LumberProfitDB = { priceCache = {}, knownRecipes = { [111] = true } }
LumberProfitCharDB = { seenRecipes = { [111] = true } }
DecorLumberProfitStore.Upgrade()
''')
    check('legacy DB adopted', 'tostring(DecorLumberProfitDB.knownRecipes[111] ~= nil)', 'true')
    check('legacy CharDB adopted', 'tostring(DecorLumberProfitCharDB.seenRecipes[111] ~= nil)', 'true')
    exec_('LumberProfitDB = nil; LumberProfitCharDB = nil')

    # ---- RememberRecipe ----
    exec_(r'''
DecorLumberProfitStore.RememberRecipe(424242, 3)
''')
    check('remember known level', 'DecorLumberProfitDB.knownRecipes[424242].level', '3')
    check('remember seen', 'tostring(DecorLumberProfitCharDB.seenRecipes[424242])', 'true')
    check('remember nil safe', 'tostring(DecorLumberProfitStore.RememberRecipe(nil) == nil)', 'true')

    # ---- Save / Load roundtrip (stub bind 0 = sellable) ----
    exec_('DecorLumberProfitStore.SaveRecipe(' + REC + ')')
    check('saved count 1', 'DecorLumberProfitStore.SavedRecipeCount()', '1')
    check('saved has savedAt', 'tostring(DecorLumberProfitDB.recipes[424242].savedAt ~= nil)', 'true')
    exec_(r'''
LOADED = DecorLumberProfitStore.LoadSavedRecipes()
DecorLumberProfitStore.MarkLearnedBy(424242)
''')
    check('loaded count 1', '#LOADED', '1')
    check('loaded name', 'LOADED[1].name', 'Craft Oak Output')
    check('mark learnedBy Tester', 'tostring(DecorLumberProfitDB.recipes[424242].learnedBy.Tester)', 'true')
    check('get saved recipe', 'DecorLumberProfitStore.GetSavedRecipe(424242).name', 'Craft Oak Output')
    check('get saved nil', 'tostring(DecorLumberProfitStore.GetSavedRecipe(1) == nil)', 'true')

    # ---- RefreshLearnedFlags (stub GetRecipeInfo learned=true) ----
    exec_(r'''
RL = { { recipeSpellID = 424242, learned = false } }
DecorLumberProfitStore.RefreshLearnedFlags(RL)
''')
    check('refresh learned true', 'tostring(RL[1].learned)', 'true')

    # ---- Core wrappers delegate ----
    check('core SaveRecipe delegates', 'DecorLumberProfitCore:SaveRecipe(' + REC + ').name', 'Craft Oak Output')
    check('core SavedRecipeCount delegates', 'DecorLumberProfitCore:SavedRecipeCount()', '1')
    check('core LoadSavedRecipes delegates', '#(DecorLumberProfitCore:LoadSavedRecipes())', '1')
    exec_('DecorLumberProfitCore:RememberRecipe(555, 1)')
    check('core RememberRecipe delegates', 'tostring(DecorLumberProfitDB.knownRecipes[555] ~= nil)', 'true')
    exec_('DecorLumberProfitCore:ClearSavedRecipes()')
    check('core ClearSavedRecipes delegates', 'DecorLumberProfitCore:SavedRecipeCount()', '0')

    # ---- Upgrade применяет сохранённые настройки сканирования поверх Config ----
    exec_(r'''
DecorLumberProfitConfig.SCAN.ENABLE_BRUTEFORCE = true
DecorLumberProfitConfig.SCAN.MAX_RESULTS = 500
DecorLumberProfitDB.settings.scan = { bruteforce = false, maxscan = 100 }
DecorLumberProfitStore.Upgrade()
''')
    check('upgrade applies saved bruteforce', 'tostring(DecorLumberProfitConfig.SCAN.ENABLE_BRUTEFORCE)', 'false')
    check('upgrade applies saved maxscan', 'DecorLumberProfitConfig.SCAN.MAX_RESULTS', '100')
    check('recipes flag follows persisted', 'tostring(DecorLumberProfitRecipes.BruteForceEnabled())', 'false')
    check('recipes cap follows persisted', 'DecorLumberProfitRecipes.MaxResults()', '100')
    exec_(r'''
DecorLumberProfitDB.settings.scan = nil
DecorLumberProfitConfig.SCAN.ENABLE_BRUTEFORCE = true
DecorLumberProfitConfig.SCAN.MAX_RESULTS = 500
''')

    # ---- LoadSavedRecipes переживает битые записи ----
    exec_(r'''
DecorLumberProfitDB.recipes[600001] = true
DecorLumberProfitDB.recipes[600002] = "garbage"
LOAD2 = DecorLumberProfitStore.LoadSavedRecipes()
''')
    check('load skips corrupt entries', 'tostring(LOAD2 ~= nil)', 'true')
    exec_('DecorLumberProfitDB.recipes[600001] = nil; DecorLumberProfitDB.recipes[600002] = nil')

    # ---- HealthCheck ----
    check('store health ok', 'tostring(DecorLumberProfitStore.HealthCheck().ok)', 'true')
    check('store health schema', 'DecorLumberProfitStore.HealthCheck().schema', '1')

    # ---- EnforceCap: 1005 timestamped + 3 untimestamped -> keep 1000 + 3 ----
    exec_(r'''
for i = 1, 1005 do
    DecorLumberProfitDB.recipes[900000 + i] = { recipeSpellID = 900000 + i, savedAt = i }
end
DecorLumberProfitDB.recipes[700001] = { recipeSpellID = 700001 }
DecorLumberProfitDB.recipes[700002] = { recipeSpellID = 700002 }
DecorLumberProfitDB.recipes[700003] = { recipeSpellID = 700003 }
CAP_BEFORE = DecorLumberProfitStore.SavedRecipeCount()
CAP_REMOVED = DecorLumberProfitStore.EnforceCap()
CAP_AFTER = DecorLumberProfitStore.SavedRecipeCount()
''')
    check('cap before 1008', 'CAP_BEFORE', '1008')
    check('cap removed 8 oldest stamped', 'CAP_REMOVED', '8')
    check('cap after 1000', 'CAP_AFTER', '1000')
    check('cap kept untimestamped', 'tostring(DecorLumberProfitDB.recipes[700001] ~= nil)', 'true')
    check('cap dropped oldest stamped', 'tostring(DecorLumberProfitDB.recipes[900001] == nil)', 'true')

    # ---- per-character learned: скан одного перса не затирает флаг другого ----
    exec_(r'''
DecorLumberProfitDB.recipes = {}
DecorLumberProfitStore.SaveRecipe({ recipeSpellID=424242, name="R", learned=true })
''')
    check('save learned=true persists', 'tostring(DecorLumberProfitDB.recipes[424242].learned)', 'true')
    check('save marks self learner', 'tostring(DecorLumberProfitDB.recipes[424242].learnedBy.Tester)', 'true')
    exec_(r'''
OLD_UNITNAME = UnitName
UnitName = function() return "Alt" end
DecorLumberProfitStore.SaveRecipe({ recipeSpellID=424242, name="R", learned=false })
UnitName = OLD_UNITNAME
''')
    check('alt scan keeps anyone-learned', 'tostring(DecorLumberProfitDB.recipes[424242].learned)', 'true')
    check('alt recorded unlearned', 'tostring(DecorLumberProfitDB.recipes[424242].learnedBy.Alt)', 'false')
    check('self still learner', 'tostring(DecorLumberProfitDB.recipes[424242].learnedBy.Tester)', 'true')
    exec_(r'''
LOAD_ME = DecorLumberProfitStore.LoadSavedRecipes()
UnitName = function() return "Alt" end
LOAD_ALT = DecorLumberProfitStore.LoadSavedRecipes()
UnitName = OLD_UNITNAME
''')
    check('load restores self learned', 'tostring(LOAD_ME[1].learned)', 'true')
    check('load restores alt unlearned', 'tostring(LOAD_ALT[1].learned)', 'false')
    exec_(r'''
DecorLumberProfitStore.SaveRecipe({ recipeSpellID=424242, name="R" })
''')
    check('nil learned does not wipe', 'tostring(DecorLumberProfitDB.recipes[424242].learned)', 'true')
    check('nil learned keeps learners', 'tostring(DecorLumberProfitDB.recipes[424242].learnedBy.Tester)', 'true')

    # ---- RefreshLearnedFlags сохраняет оба направления в DB ----
    exec_(r'''
OLD_GETINFO = C_TradeSkillUI.GetRecipeInfo
UnitName = function() return "Alt" end
C_TradeSkillUI.GetRecipeInfo = function(id) return { learned = false } end
RL_ALT = { { recipeSpellID = 424242, learned = true } }
DecorLumberProfitStore.RefreshLearnedFlags(RL_ALT)
UnitName = OLD_UNITNAME
C_TradeSkillUI.GetRecipeInfo = OLD_GETINFO
''')
    check('refresh persists unlearned in-memory', 'tostring(RL_ALT[1].learned)', 'false')
    check('refresh records alt unlearned', 'tostring(DecorLumberProfitDB.recipes[424242].learnedBy.Alt)', 'false')
    check('refresh keeps anyone-learned', 'tostring(DecorLumberProfitDB.recipes[424242].learned)', 'true')

    # ---- HasOtherLearners игнорирует false-записи ----
    check('other learners ignores false',
          'tostring(DecorLumberProfitUI.HasOtherLearners({ learnedBy = { Alt = false } }))', 'false')
    check('other learners sees true',
          'tostring(DecorLumberProfitUI.HasOtherLearners({ learnedBy = { Alt = false, Tester = true } }))', 'true')
