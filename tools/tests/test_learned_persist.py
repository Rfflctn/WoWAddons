# -*- coding: utf-8 -*-
# test_learned_persist.py — флаг "изучен" переживает сессии.
# Регресс: NEW_RECIPE_LEARNED несёт recipeID (9.0.1+, НЕ spellID-ключ базы) —
# прямой MarkLearnedBy(eventID) промахивался, Serialize терял recipeID,
# а поднятые из pending записи сохранялись со stale-флагами без сверки с API.
# Свежий runtime на сьют (изоляция, см. run_tests.py).

REC_UNLEARNED = ('{ recipeSpellID=424242, recipeID=1001, name="Craft Oak Output",'
                 ' profession="Carpentry", outputItemID=999002, outputQty=1,'
                 ' reagents={ { itemID=256963, quantity=2 } }, learned=false }')


def run(lua, check, exec_):
    exec_('DecorLumberProfitStore.Upgrade()')

    # ---- Serialize хранит recipeID (мэппинг событие -> запись) ----
    exec_('SER_LP = DecorLumberProfitStore.SerializeRecipe(' + REC_UNLEARNED + ')')
    check('serialize keeps recipeID', 'SER_LP.recipeID', '1001')
    check('serialize keeps spellID', 'SER_LP.recipeSpellID', '424242')

    # ---- Save/Load roundtrip хранит recipeID ----
    exec_('DecorLumberProfitStore.SaveRecipe(' + REC_UNLEARNED + ')')
    check('saved keeps recipeID', 'DecorLumberProfitStore.GetSavedRecipe(424242).recipeID', '1001')

    # ---- ApplyLearnedByEvent: пометка по recipeID бьёт в запись spellID ----
    exec_('MARKS_DB = DecorLumberProfitStore.ApplyLearnedByEvent(nil, 1001)')
    check('event marks db entry', 'tostring(MARKS_DB >= 1)', 'true')
    check('db learned true', 'tostring(DecorLumberProfitDB.recipes[424242].learned)', 'true')
    check('db marks self learner', 'tostring(DecorLumberProfitDB.recipes[424242].learnedBy["Tester-TestRealm"])', 'true')
    exec_('LOAD_LP = DecorLumberProfitStore.LoadSavedRecipes()')
    check('load shows learned', 'tostring(LOAD_LP[1].learned)', 'true')

    # ---- пометка в памяти: совпадение по recipeSpellID / recipeID / recipeInfo.recipeID ----
    exec_(r'''
MEM_LP = {
    { recipeSpellID = 11, recipeID = 101, learned = false, isUnavailable = true },
    { recipeSpellID = 22, recipeID = 102, learned = false, isUnavailable = true },
    { recipeSpellID = 33, learned = false, isUnavailable = true,
      recipeInfo = { recipeID = 103 } },
}
MARKS_MEM = DecorLumberProfitStore.ApplyLearnedByEvent(MEM_LP, 102)
MARKS_MEM2 = DecorLumberProfitStore.ApplyLearnedByEvent(MEM_LP, 103)
MARKS_MEM3 = DecorLumberProfitStore.ApplyLearnedByEvent(MEM_LP, 11)
''')
    check('mem marked by recipeID', 'tostring(MEM_LP[2].learned)', 'true')
    check('mem clears unavailable', 'tostring(MEM_LP[2].isUnavailable)', 'false')
    check('mem marked by recipeInfo.recipeID', 'tostring(MEM_LP[3].learned)', 'true')
    check('mem marked by spellID', 'tostring(MEM_LP[1].learned)', 'true')
    check('all three mem entries marked', 'tostring(MEM_LP[1].learned and MEM_LP[2].learned)', 'true')

    # ---- чужой ID: no-op, базу не трогаем ----
    exec_('MARKS_MISS = DecorLumberProfitStore.ApplyLearnedByEvent(nil, 987654)')
    check('unknown event id no marks', 'MARKS_MISS', '0')
    exec_('MARKS_NIL = DecorLumberProfitStore.ApplyLearnedByEvent(nil, nil)')
    check('nil event id no marks', 'MARKS_NIL', '0')

    # ---- Core-враппер делегирует ----
    exec_('MARKS_CORE = DecorLumberProfitCore:ApplyLearnedByEvent(nil, 1001)')
    check('core delegates apply', 'tostring(MARKS_CORE >= 1)', 'true')

    # ---- сценарий пользователя: stale false чинится живым API после догрузки предметов ----
    # main знает рецепт (true), alt просканил как незнаемый (false); холодный логин
    # паркует запись в pending; после догрузки Refresh обязан вернуть true в память и в DB.
    exec_(r'''
OLD_UNITNAME_LP = UnitName
OLD_CITEM_LP = C_Item.GetItemInfo
OLD_GITEM_LP = GetItemInfo
DecorLumberProfitDB.recipes = {}
DecorLumberProfitStore.SaveRecipe({ recipeSpellID=424242, recipeID=1001, name="R",
    outputItemID=999002, learned=true,
    reagents={ { itemID=256963, quantity=2 } } })
UnitName = function() return "Alt" end
DecorLumberProfitStore.SaveRecipe({ recipeSpellID=424242, recipeID=1001, name="R",
    outputItemID=999002, learned=false,
    reagents={ { itemID=256963, quantity=2 } } })
UnitName = OLD_UNITNAME_LP
-- чистая сессия: bind-кэш пуст (в игре item-кэш холодный после логина)
DecorLumberProfitItemInfo._bindCache = {}
DecorLumberProfitItemInfo._loadRequested = {}
C_Item.GetItemInfo = function(id) return nil end
GetItemInfo = function(id) return nil end
LOAD_COLD = DecorLumberProfitStore.LoadSavedRecipes()
COLD_N = #LOAD_COLD
COLD_PENDING = DecorLumberProfitItemInfo.PendingCount()
C_Item.GetItemInfo = OLD_CITEM_LP
GetItemInfo = OLD_GITEM_LP
RESOLVED_LP = DecorLumberProfitItemInfo.ResolvePending()
DecorLumberProfitStore.RefreshLearnedFlags(RESOLVED_LP)
for _, rec in ipairs(RESOLVED_LP) do DecorLumberProfitStore.SaveRecipe(rec) end
''')
    check('cold login parks all', 'COLD_N', '0')
    check('cold login pending 1', 'COLD_PENDING', '1')
    check('resolved batch 1', '#RESOLVED_LP', '1')
    check('refresh restores true in memory', 'tostring(RESOLVED_LP[1].learned)', 'true')
    check('refresh persists true in db', 'tostring(DecorLumberProfitDB.recipes[424242].learnedBy["Tester-TestRealm"])', 'true')
    check('alt false preserved', 'tostring(DecorLumberProfitDB.recipes[424242].learnedBy["Alt-TestRealm"])', 'false')

    # ---- legacy-строка без learnedBy (сейвы до 2.1.0): чужой false не стирает anyone-флаг ----
    exec_(r'''
OLD_GETINFO_LP2 = C_TradeSkillUI.GetRecipeInfo
DecorLumberProfitDB.recipes[424244] = { recipeSpellID=424244, recipeID=1002, name="Legacy",
    outputItemID=999002, learned=true,
    reagents={ { itemID=256963, quantity=2 } } }
UnitName = function() return "Alt" end
C_TradeSkillUI.GetRecipeInfo = function(id) return { learned = false } end
RL_LEG2 = { { recipeSpellID = 424244, learned = true } }
DecorLumberProfitStore.RefreshLearnedFlags(RL_LEG2)
UnitName = OLD_UNITNAME_LP
C_TradeSkillUI.GetRecipeInfo = OLD_GETINFO_LP2
''')
    check('legacy anyone-flag survives alt refresh', 'tostring(DecorLumberProfitDB.recipes[424244].learned)', 'true')
    check('legacy alt refresh records alt', 'tostring(DecorLumberProfitDB.recipes[424244].learnedBy["Alt-TestRealm"])', 'false')

    # ---- legacy bare-ник читается текущим персонажем (фолбэк до пер-реалм учёта) ----
    exec_(r'''
OLD_U_BARE = UnitName
UnitName = function() return "Bob" end
DecorLumberProfitDB.recipes[424246] = { recipeSpellID=424246, recipeID=1003, name="Bare",
    outputItemID=999002, learned=true, learnedBy={ Bob=true },
    reagents={ { itemID=256963, quantity=2 } } }
LOAD_BARE = DecorLumberProfitStore.LoadSavedRecipes()
BARE_MINE = nil
for _, r in ipairs(LOAD_BARE) do if r.recipeSpellID == 424246 then BARE_MINE = r.learned end end
UnitName = OLD_U_BARE
''')
    check('legacy bare name matches current char', 'tostring(BARE_MINE)', 'true')

    # ---- GetLearnerNames: суффикс реалма скрывается, если имя однозначно ----
    check('learner display strips unique realm',
          'table.concat(DecorLumberProfitUI.GetLearnerNames({ learnedBy = { ["Tester-TestRealm"] = true } }), ",")',
          'Tester')
    check('learner display keeps realm on collision',
          'table.concat(DecorLumberProfitUI.GetLearnerNames({ learnedBy = { ["Bob-A"] = true, ["Bob-B"] = true } }), ",")',
          'Bob-A,Bob-B')
    check('learner display keeps legacy bare',
          'table.concat(DecorLumberProfitUI.GetLearnerNames({ learnedBy = { Bob = true } }), ",")',
          'Bob')
