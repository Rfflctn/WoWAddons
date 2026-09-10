import lupa, re, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = ROOT / "addons" / "DecorLumberProfit"

lua = lupa.LuaRuntime()
lua.eval('load')(open(ADDON / 'Locales.lua', encoding='utf-8').read())()

def tbl(expr):
    t = lua.eval('(function() local r = {} for k, v in pairs(%s) do r[k] = v end return r end)()' % expr)
    out = {}
    for k in t.keys():
        v = t[k]
        out[str(k)] = str(v) if v is not None else None
    return out

en = tbl('DecorLumberProfitLocale.enUS')
ru = tbl('DecorLumberProfitLocale.ruRU')

fmt = lambda s: sorted(re.findall(r'%[-#0-9.]*[sd]', s or ''))
bad = [(k, fmt(en[k]), fmt(ru.get(k))) for k in en if fmt(en[k]) != fmt(ru.get(k))]
print('fmt mismatch:', bad)

ui = open(ADDON / 'UI.lua', encoding='utf-8').read()
used = set(re.findall(r'L\.([A-Z0-9_]+)', ui)) | set(re.findall(r'TL\("([A-Z0-9_]+)"', ui))
print('key diff en-ru:', sorted(set(en) - set(ru)))
print('key diff ru-en:', sorted(set(ru) - set(en)))
print('missing:', sorted(used - set(en)))
print('unused:', sorted(set(en) - used))

lua.eval('(function() DecorLumberProfitL10n.SetLocale("ruRU") return 1 end)()')
print('ru BTN_TOP:', lua.eval('(function() return DecorLumberProfitL10n.TL("BTN_TOP") end)()'))
print('unknown key ->', lua.eval('(function() return tostring(DecorLumberProfitL10n.L.NOPE_KEY) end)()'))
