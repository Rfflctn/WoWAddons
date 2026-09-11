# -*- coding: utf-8 -*-
# repro_learned.py — диагностика "не сохраняется изучен рецепт между сессиями".
# Сценарии:
#  A. базовый roundtrip Save -> "рестарт" (свежий Lua runtime, DB перенесена) -> Load
#  B. NEW_RECIPE_LEARNED несёт recipeID (namespace Ã 9.0.1), а DB keyed by recipeSpellID
#  C. SerializeRecipe теряет recipeID -> мэппинг невозможен после рестарта
#  D. холодный item-кэш при логине паркует всё в pending -> Refresh пропускается
import io, sys, pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

def toc_lua_files():
    toc = (ROOT / "addons" / "DecorLumberProfit" / "DecorLumberProfit.toc").read_text(encoding='utf-8')
    out = []
    for line in toc.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line.lower().endswith('.lua'):
            out.append(line.replace('/', '\\'))
    return out

def make_runtime(extra_stub=""):
    from lupa import LuaRuntime
    lua = LuaRuntime(unpack_returned_tuples=True)
    stub = io.open(ROOT / "tools" / "tests" / "stub.lua", encoding='utf-8').read()
    lua.execute(stub + "\n" + extra_stub)
    for f in toc_lua_files():
        src = io.open(str(ROOT / "addons" / "DecorLumberProfit" / f), encoding='utf-8').read()
        lua.globals()['SRC'] = src
        lua.eval('function() local c, e = load(SRC, "@x") if not c then error(e) end c() return true end')()
    return lua

def dump_db(lua):
    # сериализуем только recipes.{spellID:{learned,learnedBy,recipeID,name}} как SavedVariables-файл
    return lua.eval('''(function()
        local parts = {}
        for sid, ser in pairs(DecorLumberProfitDB.recipes or {}) do
            local lb = {}
            for k, v in pairs(ser.learnedBy or {}) do
                lb[#lb+1] = k .. "=" .. tostring(v)
            end
            parts[#parts+1] = "spell=" .. tostring(sid)
                .. " recipeID=" .. tostring(ser.recipeID)
                .. " learned=" .. tostring(ser.learned)
                .. " learnedBy={" .. table.concat(lb, ",") .. "}"
        end
        return table.concat(parts, " | ")
    end)()''')

print("=== A. roundtrip Save(true) -> рестарт -> Load ===")
lua1 = make_runtime()
lua1.execute('DecorLumberProfitStore.Upgrade()')
lua1.execute('''DecorLumberProfitStore.SaveRecipe({ recipeSpellID=424242, name="R",
    outputItemID=999002, learned=true,
    reagents={ { itemID=256963, quantity=2 } } })''')
print("session1 DB:", dump_db(lua1))
# "рестарт": переносим DB через ТЕКСТ (как SavedVariables-файл при logout/login);
# заодно проверяем сериализуемость (функции/userdata сломали бы сейв целиком)
lua1.execute('''SVDUMP = (function()
    local function ser(v, seen)
        local t = type(v)
        if t == "number" or t == "boolean" then return tostring(v)
        elseif t == "string" then return string.format("%q", v)
        elseif t == "table" then
            if seen[v] then error("cycle") end
            seen[v] = true
            local parts = {}
            for k, val in pairs(v) do
                local ks
                if type(k) == "number" then ks = "[" .. k .. "]"
                elseif type(k) == "string" and k:match("^[A-Za-z_][A-Za-z0-9_]*$") then ks = k
                else ks = "[" .. ser(k, seen) .. "]" end
                parts[#parts+1] = ks .. "=" .. ser(val, seen)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        else error("nonserializable:" .. t) end
    end
    return "DecorLumberProfitDB=" .. ser(DecorLumberProfitDB, {})
end)()''')
svdump = lua1.eval('SVDUMP')
print("SavedVariables dump ok, bytes:", len(svdump))
lua2 = make_runtime()
lua2.execute(svdump)
lua2.execute('''DecorLumberProfitCharDB = { seenRecipes={} }
    DecorLumberProfitStore.Upgrade()''')
lua2.execute('LOADED = DecorLumberProfitStore.LoadSavedRecipes()')
print("session2 loaded learned:", lua2.eval('tostring(LOADED[1] and LOADED[1].learned)'),
      "count:", lua2.eval('tostring(#LOADED)'))

print()
print("=== B. NEW_RECIPE_LEARNED(recipeID) vs DB keyed by recipeSpellID ===")
lua3 = make_runtime()
lua3.execute('DecorLumberProfitStore.Upgrade()')
# скан сохранил рецепт под spellID 424242, текущий перс его НЕ знает
lua3.execute('''DecorLumberProfitStore.SaveRecipe({ recipeSpellID=424242, name="R",
    outputItemID=999002, learned=false,
    reagents={ { itemID=256963, quantity=2 } } })''')
print("before event:", dump_db(lua3))
# в игре schematic.recipeID (1001) != spellID (424242); событие несёт recipeID=1001
lua3.execute('DecorLumberProfitStore.MarkLearnedBy(1001)')
print("after MarkLearnedBy(1001):", dump_db(lua3))
print("--> learnedBy.Tester остался false/nil: пометка по recipeID НЕ попала в запись spellID (miss)")

print()
print("=== C. SerializeRecipe хранит recipeID? ===")
lua4 = make_runtime()
lua4.execute('DecorLumberProfitStore.Upgrade()')
lua4.execute('''SER = DecorLumberProfitStore.SerializeRecipe({ recipeSpellID=424242,
    recipeID=1001, name="R", outputItemID=999002, learned=true,
    reagents={ { itemID=256963, quantity=2 } } })''')
print("SER.recipeID =", lua4.eval('tostring(SER.recipeID)'), "(nil => мэппинг событие->запись после рестарта невозможен)")

print()
print("=== D. холодный кэш предметов при логине: Load паркует всё в pending ===")
cold = '''
C_Item.GetItemInfo = function(id) return nil end
GetItemInfo = function(id) return nil end
'''
lua5 = make_runtime(cold)
lua5.execute('DecorLumberProfitStore.Upgrade()')
lua5.execute('''DecorLumberProfitStore.SaveRecipe({ recipeSpellID=424242, name="R",
    outputItemID=999002, learned=true,
    reagents={ { itemID=256963, quantity=2 } } })''')
lua5.execute('LOADED5 = DecorLumberProfitStore.LoadSavedRecipes()')
print("loaded count (cold cache):", lua5.eval('tostring(#LOADED5)'),
      "pending:", lua5.eval('tostring(DecorLumberProfitItemInfo.PendingCount())'))
print("--> при PLAYER_LOGIN таблица пуста, RefreshLearnedFlags не вызывается (ветка #saved>0 false),")
print("    флаги оживают только через GET_ITEM_INFO_RECEIVED БЕЗ сверки с живым API learned")
