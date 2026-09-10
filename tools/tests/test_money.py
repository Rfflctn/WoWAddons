# -*- coding: utf-8 -*-
# test_money.py — Util/Money.FormatMoney: только золото, округление до целых золотых.

GOLD = '|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t'

def run(lua, check, exec_):
    exec_('DecorLumberProfitDB = {}')
    check('Money direct gold rounded',
          'DecorLumberProfitMoney.FormatMoney(123456789)',
          '12346' + GOLD)
    check('Prices alias == Money table fn',
          'tostring(DecorLumberProfitPrices.FormatMoney(500) == DecorLumberProfitMoney.FormatMoney(500))', 'true')
    check('legacy Auction alias alive',
          'tostring(DecorLumberProfitAuction == DecorLumberProfitPrices)', 'true')
    check('FormatMoney(123456789) rounds to gold',
          'DecorLumberProfitPrices.FormatMoney(123456789)',
          '12346' + GOLD)
    check('FormatMoney(500) sub-gold rounds to 0g',
          'DecorLumberProfitPrices.FormatMoney(500)',
          '0' + GOLD)
    check('FormatMoney(7) sub-gold rounds to 0g',
          'DecorLumberProfitPrices.FormatMoney(7)',
          '0' + GOLD)
    check('FormatMoney(-500) rounds to 0g without minus',
          'DecorLumberProfitPrices.FormatMoney(-500)',
          '0' + GOLD)
    check('FormatMoney(nil)', 'DecorLumberProfitPrices.FormatMoney(nil)', '—')
    check('FormatMoney(0)', 'DecorLumberProfitPrices.FormatMoney(0)',
          '0' + GOLD)
    check('FormatMoney(15000) 1.5g rounds up to 2g',
          'DecorLumberProfitPrices.FormatMoney(15000)',
          '2' + GOLD)
    check('FormatMoney(14999) rounds down to 1g',
          'DecorLumberProfitPrices.FormatMoney(14999)',
          '1' + GOLD)
    check('FormatMoney(200000) exact 20g',
          'DecorLumberProfitPrices.FormatMoney(200000)',
          '20' + GOLD)
    check('FormatMoney(-15000) rounds to -2g',
          'DecorLumberProfitPrices.FormatMoney(-15000)',
          '-2' + GOLD)
