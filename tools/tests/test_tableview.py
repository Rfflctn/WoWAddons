# -*- coding: utf-8 -*-
# test_tableview.py — UI/TableView.lua: чистая математика видимости + масштаб колонок.

def run(lua, check, exec_):
    exec_('TV_F1, TV_C1 = DecorLumberProfitUI.VisibleRange(0, 400, 100, 20, 3)')
    check('visible start first', 'TV_F1', '1')
    check('visible start count 20+3', 'TV_C1', '23')
    exec_('TV_F2, TV_C2 = DecorLumberProfitUI.VisibleRange(100, 400, 100, 20, 3)')
    check('visible scrolled first', 'TV_F2', '6')
    check('visible scrolled count', 'TV_C2', '23')
    exec_('TV_F3, TV_C3 = DecorLumberProfitUI.VisibleRange(0, 400, 0, 20, 3)')
    check('visible empty total first', 'TV_F3', '1')
    check('visible empty total count', 'TV_C3', '0')
    exec_('TV_F4, TV_C4 = DecorLumberProfitUI.VisibleRange(10000, 400, 10, 20, 3)')
    check('visible past-end clamped first', 'TV_F4', '10')
    check('visible past-end count', 'TV_C4', '1')
    exec_('TV_F5, TV_C5 = DecorLumberProfitUI.VisibleRange(-50, 400, 100, 20, 3)')
    check('visible negative scroll first', 'TV_F5', '1')
    exec_('TV_F6, TV_C6 = DecorLumberProfitUI.VisibleRange(0, 15, 100, 20, 3)')
    check('visible tiny view count', 'TV_C6', '4')
    # масштаб колонок: 1.0 -> базовые ширины, 0.5 -> половина (min 30)
    exec_(r'''
DecorLumberProfitUI._colScale = 1
DecorLumberProfitUI.LayoutColumns()
TV_W1 = DecorLumberProfitUI.ColWidth("recipe", 150)
DecorLumberProfitUI._colScale = 0.5
DecorLumberProfitUI.LayoutColumns()
TV_W2 = DecorLumberProfitUI.ColWidth("recipe", 150)
TV_W3 = DecorLumberProfitUI.ColWidth("woodQty", 45)
DecorLumberProfitUI._colScale = 1
DecorLumberProfitUI.LayoutColumns()
''')
    check('colwidth scale 1', 'TV_W1', '150')
    check('colwidth scale 0.5', 'TV_W2', '75')
    check('colwidth min 30 clamps 22->30', 'TV_W3', '30')
    exec_(r'''
TV_HAS_MINE = DecorLumberProfitUI.IsColumnVisible("ahMineQty")
TV_HIDE_MINE = DecorLumberProfitUI.SetColumnVisible("ahMineQty", false)
TV_MINE_HIDDEN = DecorLumberProfitUI.IsColumnVisible("ahMineQty")
DecorLumberProfitUI.SetColumnVisible("ahMineQty", true)
''')
    check('mine column exists and visible', 'tostring(TV_HAS_MINE)', 'true')
    check('mine column can be hidden', 'tostring(TV_HIDE_MINE)', 'true')
    check('mine column hidden state', 'tostring(TV_MINE_HIDDEN)', 'false')
    # multirealm-переключатель: по умолчанию off, set персистит в DB.settings
    exec_(r'''
DecorLumberProfitDB = DecorLumberProfitDB or { settings = {} }
DecorLumberProfitDB.settings = DecorLumberProfitDB.settings or {}
DecorLumberProfitConfig.MULTI_REALM = false
TV_MR_DEFAULT = DecorLumberProfitUI.IsMultiRealmEnabled()
DecorLumberProfitUI.SetMultiRealm(true)
TV_MR_ON = DecorLumberProfitUI.IsMultiRealmEnabled()
TV_MR_SAVED = DecorLumberProfitDB.settings.multiRealm
DecorLumberProfitUI.SetMultiRealm(false)
TV_MR_OFF = DecorLumberProfitUI.IsMultiRealmEnabled()
''')
    check('multirealm default off', 'tostring(TV_MR_DEFAULT)', 'false')
    check('multirealm set on', 'tostring(TV_MR_ON)', 'true')
    check('multirealm persisted', 'tostring(TV_MR_SAVED)', 'true')
    check('multirealm set off', 'tostring(TV_MR_OFF)', 'false')
    # fallback "*" — чистая функция; сам ПОКАЗ чужого реалма гейтится флагом:
    # FillRow (колонки «На АХ»/«Мои»), AttachAuctionQuantity (eco.ahRealms)
    # и AddRealmAuctionLines (тултип-блок) читают чужие реалмы только при on
    exec_(r'''
TV_FB_QTY = DecorLumberProfitUI.FallbackRealmQuantity({ { qty = 7 } }, "qty")
TV_FB_OWN = DecorLumberProfitUI.FallbackRealmQuantity({ { ownQty = 3 } }, "ownQty")
TV_FB_EMPTY = DecorLumberProfitUI.FallbackRealmQuantity({}, "qty")
DecorLumberProfitUI.SetMultiRealm(false)
TV_MR_GATE = DecorLumberProfitUI.IsMultiRealmEnabled()
''')
    check('fallback qty other realm marks *', 'TV_FB_QTY', '7*')
    check('fallback own other realm marks *', 'TV_FB_OWN', '3*')
    check('fallback empty no data', 'tostring(TV_FB_EMPTY)', 'nil')
    check('multirealm gate stays off', 'tostring(TV_MR_GATE)', 'false')
    # высота строк: дефолт 20 (иконка 18), set 16..32 с персистом, мимо — reject
    exec_(r'''
DecorLumberProfitDB = DecorLumberProfitDB or { settings = {} }
DecorLumberProfitDB.settings = DecorLumberProfitDB.settings or {}
DecorLumberProfitUI._rowHeight = nil
TV_RH_DEFAULT = DecorLumberProfitUI.GetRowHeight()
TV_RH_ICON = DecorLumberProfitUI.RowIconSize()
TV_RH_SET = DecorLumberProfitUI.SetRowHeight(24)
TV_RH_NOW = DecorLumberProfitUI.GetRowHeight()
TV_RH_ICON2 = DecorLumberProfitUI.RowIconSize()
TV_RH_SAVED = DecorLumberProfitDB.settings.rowHeight
TV_RH_BAD = DecorLumberProfitUI.SetRowHeight(10)
TV_RH_STILL = DecorLumberProfitUI.GetRowHeight()
DecorLumberProfitUI._rowHeight = nil
TV_RH_LOADED = DecorLumberProfitUI.LoadRowHeight()
''')
    check('rowheight default 20', 'tostring(TV_RH_DEFAULT)', '20')
    check('rowheight default icon 18', 'tostring(TV_RH_ICON)', '18')
    check('rowheight set ok', 'tostring(TV_RH_SET)', 'true')
    check('rowheight applied', 'tostring(TV_RH_NOW)', '24')
    check('rowheight icon scales', 'tostring(TV_RH_ICON2)', '22')
    check('rowheight persisted', 'tostring(TV_RH_SAVED)', '24')
    check('rowheight reject low', 'tostring(TV_RH_BAD)', 'false')
    check('rowheight unchanged', 'tostring(TV_RH_STILL)', '24')
    check('rowheight load restores', 'tostring(TV_RH_LOADED)', '24')
    # LoadFromDB retry: флаг _loadedFromDB — только при реальной загрузке или
    # пустой базе; холодный вход (всё в pending) флага не ставит — OnShow повторит
    exec_(r'''
DB_REC_A = { recipeSpellID=424251, recipeID=1011, name="Relog Recipe A",
  profession="Carpentry", outputItemID=999002, outputQty=1,
  woodQty=2, woodItemID=256963, learned=true,
  reagents={ {itemID=256963, quantity=2, isWood=true} } }
DB_REC_B = { recipeSpellID=424252, recipeID=1012, name="Relog Recipe B",
  profession="Carpentry", outputItemID=999001, outputQty=1,
  woodQty=1, woodItemID=256963, learned=true,
  reagents={ {itemID=256963, quantity=1, isWood=true} } }
DecorLumberProfitCore:SaveRecipe(DB_REC_A)
DecorLumberProfitCore:SaveRecipe(DB_REC_B)
-- холодный вход: пустые кэши предметов (SaveRecipe выше их прогрел — сбрасываем)
DecorLumberProfitItemInfo._bindCache = {}
DecorLumberProfitItemInfo._nameCache = {}
DecorLumberProfitItemInfo._pending = {}
DecorLumberProfitItemInfo._loadRequested = {}
COLD2_CITEM = C_Item.GetItemInfo
COLD2_GI = GetItemInfo
C_Item.GetItemInfo = function(id) return nil end
GetItemInfo = function(id) return nil end
DecorLumberProfitUI._currentRecipes = {}
DecorLumberProfitUI._loadedFromDB = false
COLD_LOAD = DecorLumberProfitUI.LoadFromDB()
COLD_FLAG = DecorLumberProfitUI._loadedFromDB
COLD_MEM = #DecorLumberProfitUI._currentRecipes
COLD_PEND = DecorLumberProfitItemInfo.PendingCount()
C_Item.GetItemInfo = COLD2_CITEM
GetItemInfo = COLD2_GI
WARM_LOAD = DecorLumberProfitUI.LoadFromDB()
WARM_FLAG = DecorLumberProfitUI._loadedFromDB
WARM_MEM = #DecorLumberProfitUI._currentRecipes
''')
    check('cold load returns 0', 'COLD_LOAD', '0')
    check('cold load keeps flag false', 'tostring(COLD_FLAG)', 'false')
    check('cold load memory empty', 'COLD_MEM', '0')
    check('cold load parks both', 'COLD_PEND', '2')
    check('retry load returns 2', 'WARM_LOAD', '2')
    check('retry load sets flag', 'tostring(WARM_FLAG)', 'true')
    check('retry fills memory', 'WARM_MEM', '2')
    exec_(r'''
DecorLumberProfitCore:ClearSavedRecipes()
DecorLumberProfitUI._currentRecipes = {}
DecorLumberProfitUI._loadedFromDB = false
EMPTY_LOAD = DecorLumberProfitUI.LoadFromDB()
EMPTY_FLAG = DecorLumberProfitUI._loadedFromDB
''')
    check('empty db load returns 0', 'EMPTY_LOAD', '0')
    check('empty db sets flag (nothing to retry)', 'tostring(EMPTY_FLAG)', 'true')
