-- UI/Popups.lua | DecorLumberProfit | Retail 12.1.0
-- StaticPopup-диалоги (Этап 8). Регистрируется из Commands при ADDON_LOADED.

local UI = _G.DecorLumberProfitUI or {}
local L = DecorLumberProfitL10n.L

-- Диалог подтверждения очистки (после применения локали)
function UI.RegisterPopups()
    if not StaticPopupDialogs["DECORLUMBERPROFIT_CLEAR_DB"] then
        StaticPopupDialogs["DECORLUMBERPROFIT_CLEAR_DB"] = {
            text = L.POPUP_CLEAR_TEXT,
            button1 = L.POPUP_CLEAR_OK,
            button2 = L.POPUP_CLEAR_CANCEL,
            OnAccept = function()
                UI.ClearAll()
                print(L.PREFIX_ERR .. L.PRINT_TABLE_CLEARED)
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
end
