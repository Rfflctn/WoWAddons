-- UI/Status.lua | DecorLumberProfit | Retail 12.1.0
-- Статус-строка главного окна (Этап 8). Пишет в UI._statusText (создаётся в MainFrame).

local UI = _G.DecorLumberProfitUI or {}

function UI.SetStatus(msg, r, g, b)
    local st = UI._statusText
    if st then
        st:SetText(msg or "")
        if r then st:SetTextColor(r, g, b) end
    end
    -- Точка-индикатор здоровья (Этап 9): дублирует цвет статуса
    local dot = UI._healthDot
    if dot then
        if r then dot:SetTextColor(r, g, b) else dot:SetTextColor(0.5, 0.5, 0.5) end
    end
end
