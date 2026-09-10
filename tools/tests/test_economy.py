# -*- coding: utf-8 -*-
# test_economy.py — Core:CalculateRecipeEconomy pure cases (table-driven).

def run(lua, check, exec_):
    exec_(r'''
DecorLumberProfitAuction.SetPrice(256963, 50000, "test")
DecorLumberProfitAuction.SetPrice(999001, 30000, "test")
DecorLumberProfitAuction.SetPrice(999002, 200000, "test")
local rec = { recipeSpellID=1, outputItemID=999002, woodItemID=256963, woodQty=2, outputQty=1,
    reagents={ {itemID=256963, quantity=2, isWood=true}, {itemID=999001, quantity=3} } }
ECO = DecorLumberProfitCore:CalculateRecipeEconomy(rec, { [256963]=50000, [999001]=30000, [999002]=200000 })
-- missing output price -> profit nil, status NO_OUTPUT_PRICE
local recNoOut = { recipeSpellID=2, outputItemID=999002, woodItemID=256963, woodQty=2, outputQty=1,
    reagents={ {itemID=256963, quantity=2, isWood=true}, {itemID=999001, quantity=3} } }
ECO_NOOUT = DecorLumberProfitCore:CalculateRecipeEconomy(recNoOut, { [256963]=50000, [999001]=30000 })
-- breakeven: output == total
ECO_BE = DecorLumberProfitCore:CalculateRecipeEconomy(rec, { [256963]=50000, [999001]=30000, [999002]=190000 })
-- unprofitable: output < total
ECO_LOSS = DecorLumberProfitCore:CalculateRecipeEconomy(rec, { [256963]=50000, [999001]=30000, [999002]=100000 })
''')
    check('eco woodCost=2*50s', 'ECO.woodCost', '100000')
    check('eco otherCost=3*30s', 'ECO.otherCost', '90000')
    check('eco totalCost', 'ECO.totalCost', '190000')
    check('eco maxWoodPrice=(2g-90s)/2', 'math.floor(ECO.maxWoodPrice)', '55000')
    check('eco profit', 'ECO.profit', '10000')
    check('eco status', 'ECO.status', 'PROFITABLE')
    check('eco no-output status', 'ECO_NOOUT.status', 'NO_OUTPUT_PRICE')
    check('eco no-output profit nil', 'tostring(ECO_NOOUT.profit)', 'nil')
    check('eco breakeven status', 'ECO_BE.status', 'BREAKEVEN')
    check('eco loss status', 'ECO_LOSS.status', 'UNPROFITABLE')
    # Этап 6: прямой вызов модуля + healthcheck (тот же контракт, что через Core)
    exec_(r'''
ECO_DIRECT = DecorLumberProfitEconomy.CalculateRecipeEconomy(
    { recipeSpellID=1, outputItemID=999002, woodItemID=256963, woodQty=2, outputQty=1,
      reagents={ {itemID=256963, quantity=2, isWood=true}, {itemID=999001, quantity=3} } },
    { [256963]=50000, [999001]=30000, [999002]=200000 })
''')
    check('economy direct call', 'ECO_DIRECT.profit', '10000')
    check('economy healthcheck', 'tostring(DecorLumberProfitEconomy.HealthCheck().ok)', 'true')
