-- Util/Money.lua | DecorLumberProfit | Retail 12.1.0
-- Форматирование денег (Этап 7): переезд DecorLumberProfitAuction.FormatMoney 1:1.
-- Все функции — через точку (без self). No WoW calls at top level.

DecorLumberProfitMoney = {}
local Money = DecorLumberProfitMoney

local MONEY_ICON = {
    g = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t",
    s = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t",
    c = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t",
}

-- Компактно: >1g — «12g 34s», <1g — «56s 78c», <1s — «9c». Знак — текстом, цвет задаёт вызывающий.
function Money.FormatMoney(copper)
    if copper == nil then return "—" end
    copper = math.floor(tonumber(copper) or 0)
    local sign = ""
    if copper < 0 then sign = "-"; copper = -copper end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then
        parts[#parts + 1] = tostring(g) .. MONEY_ICON.g
        if s > 0 then parts[#parts + 1] = tostring(s) .. MONEY_ICON.s end
    elseif s > 0 then
        parts[#parts + 1] = tostring(s) .. MONEY_ICON.s
        if c > 0 then parts[#parts + 1] = tostring(c) .. MONEY_ICON.c end
    else
        parts[#parts + 1] = tostring(c) .. MONEY_ICON.c
    end
    return sign .. table.concat(parts, " ")
end

_G.DecorLumberProfitMoney = Money
