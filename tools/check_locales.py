import lupa, re, sys, pathlib

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

# Scan ALL addon lua files (recursive — covers Services/, UI/, Data/, Util/ after split),
# not just UI.lua.
used = set()
for path in sorted(ADDON.rglob('*.lua')):
    if path.name == 'Locales.lua':
        continue
    try:
        src = path.read_text(encoding='utf-8')
    except OSError:
        continue
    used |= set(re.findall(r'L\.([A-Z0-9_]+)', src)) | set(re.findall(r'TL\("([A-Z0-9_]+)"', src))
key_diff_en_ru = sorted(set(en) - set(ru))
key_diff_ru_en = sorted(set(ru) - set(en))
missing = sorted(used - set(en))
print('key diff en-ru:', key_diff_en_ru)
print('key diff ru-en:', key_diff_ru_en)
print('missing:', missing)
print('unused:', sorted(set(en) - used))

lua.eval('(function() DecorLumberProfitL10n.SetLocale("ruRU") return 1 end)()')
print('ru BTN_TOP:', lua.eval('(function() return DecorLumberProfitL10n.TL("BTN_TOP") end)()'))
print('unknown key ->', lua.eval('(function() return tostring(DecorLumberProfitL10n.L.NOPE_KEY) end)()'))

# Strict gate (Этап 0.1): any real mismatch fails the release.
# 'unused' stays informational — keys may be reserved for future UI/Diag.
errors = []
if bad:
    errors.append('fmt-mismatch: %d' % len(bad))
if key_diff_en_ru:
    errors.append('en-ru diff: %s' % key_diff_en_ru)
if key_diff_ru_en:
    errors.append('ru-en diff: %s' % key_diff_ru_en)
if missing:
    errors.append('missing keys used in code: %s' % missing)
if errors:
    print('LOCALE CHECK FAILED:', '; '.join(errors))
    sys.exit(1)
print('LOCALE CHECK PASSED')
