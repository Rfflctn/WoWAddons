-- Util/Money.lua | DecorLumberProfit | Retail 12.1.0
-- Форматирование денег: только золото (округление до целых золотых).
-- Все функции — через точку (без self). No WoW calls at top level.

DecorLumberProfitMoney = {}
local Money = DecorLumberProfitMoney

local MONEY_ICON = {
    g = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t",
}

-- Только золото: все цены округляются до целых золотых (математически, +50s).
-- Серебро и медь не показываем.
function Money.FormatMoney(copper)
    if copper == nil then return "—" end
    copper = tonumber(copper) or 0
    local sign = ""
    if copper < 0 then sign = "-"; copper = -copper end
    local g = math.floor((copper + 5000) / 10000)
    if g == 0 then sign = "" end -- округление дало ноль: "-0" не показываем
    return sign .. tostring(g) .. MONEY_ICON.g
end

_G.DecorLumberProfitMoney = Money
