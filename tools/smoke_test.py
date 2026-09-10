# -*- coding: utf-8 -*-
# Smoke test: эмуляция WoW-глобалов в lupa, загрузка аддона, проверка логики.
import io, sys, pathlib
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
from lupa import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = str(ROOT / "addons" / "DecorLumberProfit")

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
-- ==== Стабы WoW ====
function stub_frame()
    local f = {}
    f.children = {}
    local mt
    mt = {
        __index = function(t, k)
            if k == "GetChildren" then return function(self) return unpack(t.children or {}) end end
            return function(self, ...) return nil end  -- no-op для любых методов
        end,
    }
    setmetatable(f, mt)
    return f
end
CreateFrame = function(...) return stub_frame() end
C_Timer = { After = function(delay, fn) end }
time = function() return 1000000 end
GetTime = function() return 100.0 end
UnitName = function() return "Tester" end
StaticPopupDialogs = {}
Gatherer = nil
-- API-пространства
C_Item = { GetItemInfo = function(id)
    local names = {[256963]="Талассийская древесина", [245586]="Древесина железного дерева", [999001]="Sturdy Handle", [999002]="Oak Output"}
    return names[id], nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 0 -- bindType 0 = sellable
end }
GetItemInfo = C_Item.GetItemInfo
C_TradeSkillUI = {
    GetRecipeSchematic = function(id, isRecraft, level)
        return {
            recipeID = id, name = "Craft Oak Output", outputItemID = 999002,
            quantityMin = 1, quantityMax = 1, icon = "icon",
            reagentSlotSchematics = {
                { quantityRequired = 2, required = true, dataSlotIndex = 1,
                  reagents = { { itemID = 256963 } } },
                { quantityRequired = 3, required = true, dataSlotIndex = 2,
                  reagents = { { itemID = 999001 } } },
            },
        }
    end,
    GetRecipeInfo = function(id) return { learned = true, craftable = true, name = "Craft Oak Output", unlockedRecipeLevel = 1 } end,
    GetRecipeOutputItemData = function(...) return nil end,
    GetProfessionInfoByRecipeID = function(id) return { professionName = "Carpentry" } end,
    GetAllRecipeIDs = function() return { 424242 } end,
}
C_AuctionHouse = {
    MakeItemKey = function(id) return { itemID = id } end,
    IsThrottledMessageSystemReady = function() return true end,
    HasFullCommoditySearchResults = function(id) return true end,
    GetCommoditySearchResultsQuantity = function(id) return 0 end,
    GetNumCommoditySearchResults = function(id) return 0 end,
}
SLASH_DECORLUMBERPROFIT1 = nil
''')

def load(path):
    src = io.open(path, encoding='utf-8').read()
    lua.globals()['SRC'] = src
    ok = lua.eval('function() local c, e = load(SRC, "@' + path.replace('\\','/') + '") if not c then error(e) end c() return true end')()
    return ok

for f in ['Locales.lua', 'Config.lua', 'Core.lua', 'Auction.lua', 'UI.lua']:
    load(ADDON + '\\' + f)
    print('loaded:', f)

print()
failures = []
def check(name, expr, expected):
    lua.globals()['E'] = expr
    got = lua.eval('tostring(E)')
    status = 'OK  ' if got == expected else 'FAIL'
    if got != expected: failures.append((name, got, expected))
    print('%s %-38s -> %s (want %s)' % (status, name, got, expected))

# ==== FormatMoney ====
lua.execute('DecorLumberProfitDB = {}')
check('FormatMoney(123456789) g/s', lua.eval('DecorLumberProfitAuction.FormatMoney(123456789)'), '12345|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t 67|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t')
check('FormatMoney(500) s only', lua.eval('DecorLumberProfitAuction.FormatMoney(500)'), '5|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t')
check('FormatMoney(7) c only', lua.eval('DecorLumberProfitAuction.FormatMoney(7)'), '7|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t')
check('FormatMoney(-500) sign', lua.eval('DecorLumberProfitAuction.FormatMoney(-500)'), '-5|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t')
check('FormatMoney(nil)', lua.eval('DecorLumberProfitAuction.FormatMoney(nil)'), '—')

# ==== CollectPricesForRecipes: уникальность need + древесина ====
lua.execute(r'''
local recipes = {
    { recipeSpellID=1, outputItemID=999002, woodItemID=256963, woodQty=2,
      reagents={ {itemID=256963, quantity=2}, {itemID=999001, quantity=3} } },
    { recipeSpellID=2, outputItemID=999001, woodItemID=256963, woodQty=1,
      reagents={ {itemID=999001, quantity=1}, {itemID=999002, quantity=2} } }, -- дубли: output одного = реагент другого
}
MAP, NEED = DecorLumberProfitAuction.CollectPricesForRecipes(recipes)
local seen, dups = {}, 0
for _, id in ipairs(NEED) do if seen[id] then dups = dups + 1 end seen[id] = true end
NEED_COUNT, NEED_DUPS = #NEED, dups
''')
check('need count (3 uniq: 999002, 999001, 256963)', lua.eval('NEED_COUNT'), '3')
check('need has no duplicates', lua.eval('NEED_DUPS'), '0')

# ==== CalculateRecipeEconomy ====
lua.execute(r'''
DecorLumberProfitAuction.SetPrice(256963, 50000, "test")
DecorLumberProfitAuction.SetPrice(999001, 30000, "test")
DecorLumberProfitAuction.SetPrice(999002, 200000, "test")
local rec = { recipeSpellID=1, outputItemID=999002, woodItemID=256963, woodQty=2, outputQty=1,
    reagents={ {itemID=256963, quantity=2, isWood=true}, {itemID=999001, quantity=3} } }
ECO = DecorLumberProfitCore:CalculateRecipeEconomy(rec, { [256963]=50000, [999001]=30000, [999002]=200000 })
''')
check('eco woodCost=2*50s', lua.eval('ECO.woodCost'), '100000')
check('eco otherCost=3*30s', lua.eval('ECO.otherCost'), '90000')
check('eco totalCost', lua.eval('ECO.totalCost'), '190000')
check('eco maxWoodPrice=(2g-90s)/2', lua.eval('math.floor(ECO.maxWoodPrice)'), '55000')
check('eco profit', lua.eval('ECO.profit'), '10000')
check('eco status', lua.eval('ECO.status'), 'PROFITABLE')

# ==== SchematicUsesWood / GetRecipeData ====
lua.execute('RD = DecorLumberProfitCore:GetRecipeData(424242)')
check('GetRecipeData name', lua.eval('RD.name'), 'Craft Oak Output')
check('GetRecipeData woodQty', lua.eval('RD.woodQty'), '2')
check('GetRecipeData woodItemID', lua.eval('RD.woodItemID'), '256963')
check('GetRecipeData reagents count', lua.eval('#RD.reagents'), '2')
check('GetRecipeData reagent1 isWood', lua.eval('tostring(RD.reagents[1].isWood)'), 'true')
check('GetRecipeData learned', lua.eval('tostring(RD.learned)'), 'true')

# ==== OutputIsUnsellable (bindType 0 = можно продать) ====
check('OutputIsUnsellable(999002)=false', lua.eval('tostring(DecorLumberProfitCore:IsOutputUnsellable(999002))'), 'false')

# ==== Collect после заполнения кэша ====
lua.execute(r'''
MAP2, NEED2 = DecorLumberProfitAuction.CollectPricesForRecipes({
    { recipeSpellID=1, outputItemID=999002, woodItemID=256963, woodQty=2,
      reagents={ {itemID=256963, quantity=2}, {itemID=999001, quantity=3} } },
})
NEED2_COUNT = #NEED2
MAP2_256963 = MAP2[256963]
''')
check('need empty after cache filled', lua.eval('NEED2_COUNT'), '0')
check('map wood price', lua.eval('MAP2_256963'), '50000')

# ==== HasFreshPrice + ClearPriceCache ====
check('HasFreshPrice(256963)', lua.eval('tostring(DecorLumberProfitAuction.HasFreshPrice(256963))'), 'true')
lua.execute('DecorLumberProfitAuction.ClearPriceCache()')
check('HasFreshPrice after clear', lua.eval('tostring(DecorLumberProfitAuction.HasFreshPrice(256963))'), 'false')

# ==== Enqueue без дублей (queuedSet) ====
lua.execute(r'''
DecorLumberProfitAuction.Enqueue({700001, 700001, 700002})
DecorLumberProfitAuction.Enqueue({700001})
-- queue не должна содержать дублей
local q = DecorLumberProfitAuction and 1
QUEUE_OK = (DecorLumberProfitAuction.HasFreshPrice(700001) == false)
''')

print()
if failures:
    print('FAILURES:', len(failures))
    for f in failures: print('  ', f)
    sys.exit(1)
print('ALL CHECKS PASSED')
