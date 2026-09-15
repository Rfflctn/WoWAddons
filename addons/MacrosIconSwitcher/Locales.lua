-- Locales.lua | MacrosIconSwitcher | Retail 12.1.0
-- All addon strings. Locales: enUS (base), ruRU. Chosen automatically by GetLocale().
-- Usage: L["KEY"] -- string; TL("KEY", ...) -- string.format.

MacrosIconSwitcherLocale = {
    enUS = {
        TITLE = "MacrosIconSwitcher",
        SUB = "Assign icons to macros - applied automatically on login",

        HEAD_ON = "On",
        HEAD_NAME = "Macro",
        HEAD_CURRENT = "Current",
        HEAD_ICON = "New icon ID",

        BTN_APPLY = "Apply now",
        BTN_REFRESH = "Refresh",
        BTN_CLOSE = "Close",

        ST_MACRO_COUNT = "Macros found: %d",
        ST_NO_MACROS = "No macros found.",
        ST_APPLIED = "Icon %s applied to \"%s\".",
        ST_APPLIED_ALL = "Applied: %d, failed: %d.",
        ST_FAILED = "Could not apply icon to \"%s\".",
        ST_INVALID_ID = "Enter a numeric icon ID greater than 0.",
        ST_COMBAT = "Macros are protected in combat. Will retry after combat.",
        ST_AUTO_ON = "Automatic icon switching on login: ON",
        ST_AUTO_OFF = "Automatic icon switching on login: OFF",
        ST_RESET = "Saved icons cleared.",

        TIP_CHECK = "Tick to assign a custom icon to this macro.",
        TIP_ICON = "Icon FileDataID (e.g. 135432). Press Enter to apply.",
        TIP_CURRENT = "Current macro icon FileDataID.",

        PRINT_HELP = "Commands: /mis - open window | /mis apply - apply icons | /mis on|off - toggle auto-apply | /mis reset - clear saved icons | /mis help",
    },
    ruRU = {
        TITLE = "MacrosIconSwitcher",
        SUB = "Назначение иконок макросам — применяется автоматически при входе",

        HEAD_ON = "Вкл",
        HEAD_NAME = "Макрос",
        HEAD_CURRENT = "Текущая",
        HEAD_ICON = "ID иконки",

        BTN_APPLY = "Применить",
        BTN_REFRESH = "Обновить",
        BTN_CLOSE = "Закрыть",

        ST_MACRO_COUNT = "Найдено макросов: %d",
        ST_NO_MACROS = "Макросы не найдены.",
        ST_APPLIED = "Иконка %s применена к «%s».",
        ST_APPLIED_ALL = "Применено: %d, с ошибкой: %d.",
        ST_FAILED = "Не удалось применить иконку к «%s».",
        ST_INVALID_ID = "Введите числовой ID иконки больше 0.",
        ST_COMBAT = "В бою макросы защищены. Повтор автоматически после боя.",
        ST_AUTO_ON = "Автоматическая смена иконок при входе: ВКЛ",
        ST_AUTO_OFF = "Автоматическая смена иконок при входе: ВЫКЛ",
        ST_RESET = "Сохранённые иконки очищены.",

        TIP_CHECK = "Отметьте, чтобы задать макросу свою иконку.",
        TIP_ICON = "FileDataID иконки (например, 135432). Enter — применить.",
        TIP_CURRENT = "Текущий FileDataID иконки макроса.",

        PRINT_HELP = "Команды: /mis — открыть окно | /mis apply — применить иконки | /mis on|off — авто-смена при входе | /mis reset — очистить сохранённое | /mis help",
    },
}

local MacrosIconSwitcherL10n = { locales = MacrosIconSwitcherLocale }
local active = "enUS"

local function resolve(key)
    local t = MacrosIconSwitcherLocale[active]
    local s = t and t[key]
    if s == nil then s = MacrosIconSwitcherLocale.enUS[key] end
    if s == nil then return key end
    return s
end

MacrosIconSwitcherL10n.L = setmetatable({}, { __index = function(_, key) return resolve(key) end })

function MacrosIconSwitcherL10n.TL(key, ...)
    local s = resolve(key)
    if select("#", ...) > 0 then return string.format(s, ...) end
    return s
end

function MacrosIconSwitcherL10n.GetLocale() return active end

function MacrosIconSwitcherL10n.SetLocale(code)
    if code and MacrosIconSwitcherLocale[code] then active = code end
    return active
end

function MacrosIconSwitcherL10n.DetectLocale()
    local rl = (_G.GetLocale and GetLocale()) or "enUS"
    if rl:find("^ru") then return "ruRU" end
    return "enUS"
end

_G.MacrosIconSwitcherL10n = MacrosIconSwitcherL10n
