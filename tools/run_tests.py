# -*- coding: utf-8 -*-
# run_tests.py — modular test runner (Этап 0.1).
# Gate: python tools/syntax_check.py -> python tools/run_tests.py -> python tools/check_locales.py
# - load order is read from addons/DecorLumberProfit/DecorLumberProfit.toc (not hardcoded),
# - WoW stubs come from tools/tests/stub.lua (STUB v1),
# - suites are tools/tests/test_*.py, each exposing run(lua, check, exec_).
import io
import sys
import pathlib
import importlib

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = ROOT / "addons" / "DecorLumberProfit"
TESTS_DIR = ROOT / "tools" / "tests"

sys.path.insert(0, str(ROOT / "tools"))


def toc_lua_files():
    toc = (ADDON / "DecorLumberProfit.toc").read_text(encoding='utf-8')
    files = []
    for line in toc.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line.lower().endswith('.lua'):
            files.append(line.replace('/', '\\'))
    return files


def main():
    from lupa import LuaRuntime

    ordered = toc_lua_files()
    if not ordered:
        print('FAIL: no lua files parsed from TOC')
        return 1

    stub_src = io.open(TESTS_DIR / "stub.lua", encoding='utf-8').read()
    addon_srcs = []
    for f in ordered:
        addon_srcs.append((f, io.open(str(ADDON / f), encoding='utf-8').read()))
        print('loaded:', f)
    print()

    failures = []
    total_checks = [0]

    def make_runtime():
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(stub_src)

        def load(name, src):
            lua.globals()['SRC'] = src
            lua.eval(
                'function() local c, e = load(SRC, "@' + name.replace('\\', '/')
                + '") if not c then error(e) end c() return true end')()

        for f, src in addon_srcs:
            load('addons/DecorLumberProfit/' + f, src)
        return lua

    # test order: stable alphabetical (money -> economy -> recipes -> prices -> wood).
    # Each suite gets a FRESH runtime (stub + addon reloaded) so suites are
    # order-independent: no shared priceCache / bindCache / DB between suites.
    for mod_path in sorted(TESTS_DIR.glob('test_*.py')):
        mod_name = 'tests.' + mod_path.stem
        mod = importlib.import_module(mod_name)
        lua = make_runtime()
        print('--- %s ---' % mod_path.name)

        def check(name, expr, expected, _lua=lua):
            got = _lua.eval('tostring(%s)' % expr)
            total_checks[0] += 1
            status = 'OK  ' if got == expected else 'FAIL'
            if got != expected:
                failures.append((mod_path.name + ':' + name, got, expected))
            print('%s %-52s -> %s (want %s)' % (status, name, got, expected))

        def exec_(code, _lua=lua):
            _lua.execute(code)

        mod.run(lua, check, exec_)

    print()
    if failures:
        print('FAILURES:', len(failures))
        for f in failures:
            print('  ', f)
        return 1
    print('ALL CHECKS PASSED (%d suites)' % len(list(TESTS_DIR.glob('test_*.py'))))
    return 0


if __name__ == '__main__':
    sys.exit(main())
