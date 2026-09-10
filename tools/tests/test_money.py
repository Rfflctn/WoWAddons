# -*- coding: utf-8 -*-
# test_money.py — Util/Money.FormatMoney branches (+ Prices alias).

def run(lua, check, exec_):
    exec_('DecorLumberProfitDB = {}')
    check('Money direct g/s',
          'DecorLumberProfitMoney.FormatMoney(123456789)',
          '12345|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t 67|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t')
    check('Prices alias == Money table fn',
          'tostring(DecorLumberProfitPrices.FormatMoney(500) == DecorLumberProfitMoney.FormatMoney(500))', 'true')
    check('legacy Auction alias alive',
          'tostring(DecorLumberProfitAuction == DecorLumberProfitPrices)', 'true')
    check('FormatMoney(123456789) g/s',
          'DecorLumberProfitPrices.FormatMoney(123456789)',
          '12345|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t 67|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t')
    check('FormatMoney(500) s only',
          'DecorLumberProfitPrices.FormatMoney(500)',
          '5|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t')
    check('FormatMoney(7) c only',
          'DecorLumberProfitPrices.FormatMoney(7)',
          '7|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t')
    check('FormatMoney(-500) sign',
          'DecorLumberProfitPrices.FormatMoney(-500)',
          '-5|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t')
    check('FormatMoney(nil)', 'DecorLumberProfitPrices.FormatMoney(nil)', '—')
    check('FormatMoney(0)', 'DecorLumberProfitPrices.FormatMoney(0)',
          '0|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t')
