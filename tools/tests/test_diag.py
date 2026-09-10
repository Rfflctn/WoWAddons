# -*- coding: utf-8 -*-
# test_diag.py — Services/Diag.lua: selftest, queue/bind introspection, error capture.

def run(lua, check, exec_):
    exec_(r'''
ST = DecorLumberProfitDiag.SelfTest()
QI = DecorLumberProfitAuction.GetQueueInfo()
PBC = DecorLumberProfitCore:GetPendingBindCount()
SS = DecorLumberProfitDiag.SubsystemStatus()
-- verbose gated: must not error with or without flag
DecorLumberProfitDiag.Log("VERBOSE", "test", "quiet %d", 1)
DecorLumberProfitDiag.SetVerbose(true)
VB_ON = DecorLumberProfitDiag.IsVerbose()
DecorLumberProfitDiag.Log("VERBOSE", "test", "loud %d", 2)
DecorLumberProfitDiag.SetVerbose(false)
VB_OFF = DecorLumberProfitDiag.IsVerbose()
-- error capture roundtrip
DecorLumberProfitDiag.CaptureError("test_where", "boom")
LE = DecorLumberProfitDiag.lastError
SS2 = DecorLumberProfitDiag.SubsystemStatus()
BL = DecorLumberProfitDiag.BugBundleLines()
''')
    check('diag selftest passed', 'ST.passed', '5')
    check('diag selftest failed', 'ST.failed', '0')
    check('diag queue info has queue field', 'tostring(QI.queue ~= nil)', 'true')
    check('diag queue initially empty', 'QI.queue', '0')
    check('diag pendingBind initially 0', 'PBC', '0')
    check('diag status 5 subsystems', '#SS', '5')
    check('diag verbose on', 'tostring(VB_ON)', 'true')
    check('diag verbose off', 'tostring(VB_OFF)', 'false')
    check('diag lastError where', 'LE.where', 'test_where')
    check('diag lastError err', 'LE.err', 'boom')
    check('diag errors subsystem FAIL after capture', 'SS2[5].state', 'FAIL')
    check('diag bug bundle non-empty', 'tostring(#BL > 5)', 'true')
