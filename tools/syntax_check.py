import sys, glob, pathlib
from lupa import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = ROOT / "addons" / "DecorLumberProfit"

lua = LuaRuntime(unpack_returned_tuples=True)
check = lua.eval('''
function(name, code)
    local chunk, err = load(code, name)
    if chunk then return true, nil end
    return false, err
end
''')
ok = True
# Recursive: covers Services/, UI/, Data/, Util/ after the split (Этап 0.1).
for f in sorted(glob.glob(str(ADDON / "**" / "*.lua"), recursive=True)):
    src = open(f, encoding='utf-8').read()
    okf, err = check(f, src)
    if okf:
        print('OK  ', f)
    else:
        print('FAIL', f)
        print('     ', err)
        ok = False
sys.exit(0 if ok else 1)
