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
