-- Locales.lua | MacrosIconSwitcher | Retail 12.1.0
-- All addon strings. Locales: enUS (base), ruRU, deDE, frFR, esES, esMX, ptBR, itIT, zhCN, zhTW, koKR.
-- Chosen automatically by GetLocale(). Missing keys fall back to enUS.
-- Usage: L["KEY"] -- string; TL("KEY", ...) -- string.format.

MacrosIconSwitcherLocale = {
    enUS = {
        TITLE = "MacrosIconSwitcher",
        SUB = "Assign icons to macros - applied automatically on login",

        HEAD_ON = "On",
        HEAD_NAME = "Macro",
        HEAD_CURRENT = "Current",
        HEAD_TARGET = "New",
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
        ST_PICKER_EMPTY = "Icon list unavailable.",

        TIP_CHECK = "Tick to assign a custom icon to this macro.",
        TIP_ICON = "Icon FileDataID (e.g. 135432). Press Enter to apply.",
        TIP_CURRENT = "Current macro icon FileDataID.",
        TIP_PREVIEW = "Icon that will be applied.",
        TIP_PICKER = "Choose an icon from the list.",
        TIP_MINIMAP = "Show or hide the minimap button.",

        PICK_TITLE = "Select icon",
        CHK_MINIMAP = "Minimap",

        PRINT_HELP = "Commands: /mis - open window | /mis apply - apply icons | /mis on|off - toggle auto-apply | /mis reset - clear saved icons | /mis help",
    },
    ruRU = {
        TITLE = "MacrosIconSwitcher",
        SUB = "Назначение иконок макросам — применяется автоматически при входе",

        HEAD_ON = "Вкл",
        HEAD_NAME = "Макрос",
        HEAD_CURRENT = "Текущая",
        HEAD_TARGET = "Новая",
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
        ST_PICKER_EMPTY = "Список иконок недоступен.",

        TIP_CHECK = "Отметьте, чтобы задать макросу свою иконку.",
        TIP_ICON = "FileDataID иконки (например, 135432). Enter — применить.",
        TIP_CURRENT = "Текущий FileDataID иконки макроса.",
        TIP_PREVIEW = "Иконка, которая будет применена.",
        TIP_PICKER = "Выберите иконку из списка.",
        TIP_MINIMAP = "Показать или скрыть кнопку у миникарты.",

        PICK_TITLE = "Выбор иконки",
        CHK_MINIMAP = "Миникарта",

        PRINT_HELP = "Команды: /mis — открыть окно | /mis apply — применить иконки | /mis on|off — авто-смена при входе | /mis reset — очистить сохранённое | /mis help",
    },
    deDE = {
        TITLE = "MacrosIconSwitcher",
        SUB = "Makros Icons zuweisen — beim Login automatisch angewendet",

        HEAD_ON = "An",
        HEAD_NAME = "Makro",
        HEAD_CURRENT = "Aktuell",
        HEAD_TARGET = "Neu",
        HEAD_ICON = "Icon-ID",

        BTN_APPLY = "Anwenden",
        BTN_REFRESH = "Aktualisieren",
        BTN_CLOSE = "Schließen",

        ST_MACRO_COUNT = "Gefundene Makros: %d",
        ST_NO_MACROS = "Keine Makros gefunden.",
        ST_APPLIED = "Icon %s auf \"%s\" angewendet.",
        ST_APPLIED_ALL = "Angewendet: %d, fehlgeschlagen: %d.",
        ST_FAILED = "Icon konnte nicht auf \"%s\" angewendet werden.",
        ST_INVALID_ID = "Numerische Icon-ID größer 0 eingeben.",
        ST_COMBAT = "Makros sind im Kampf geschützt. Wiederholung nach dem Kampf.",
        ST_AUTO_ON = "Automatischer Icon-Wechsel beim Login: AN",
        ST_AUTO_OFF = "Automatischer Icon-Wechsel beim Login: AUS",
        ST_RESET = "Gespeicherte Icons gelöscht.",
        ST_PICKER_EMPTY = "Iconliste nicht verfügbar.",

        TIP_CHECK = "Aktivieren, um diesem Makro ein eigenes Icon zuzuweisen.",
        TIP_ICON = "Icon-FileDataID (z. B. 135432). Eingabetaste — anwenden.",
        TIP_CURRENT = "Aktuelle FileDataID des Makro-Icons.",
        TIP_PREVIEW = "Icon, das angewendet wird.",
        TIP_PICKER = "Icon aus der Liste wählen.",
        TIP_MINIMAP = "Minimap-Knopf anzeigen oder ausblenden.",

        PICK_TITLE = "Icon wählen",
        CHK_MINIMAP = "Minimap",

        PRINT_HELP = "Befehle: /mis — Fenster öffnen | /mis apply — Icons anwenden | /mis on|off — Auto-Wechsel | /mis reset — gespeicherte Icons löschen | /mis help",
    },
    frFR = {
        TITLE = "MacrosIconSwitcher",
        SUB = "Attribuer des icônes aux macros — appliqué automatiquement à la connexion",

        HEAD_ON = "Actif",
        HEAD_NAME = "Macro",
        HEAD_CURRENT = "Actuelle",
        HEAD_TARGET = "Nouvelle",
        HEAD_ICON = "ID d'icône",

        BTN_APPLY = "Appliquer",
        BTN_REFRESH = "Actualiser",
        BTN_CLOSE = "Fermer",

        ST_MACRO_COUNT = "Macros trouvées : %d",
        ST_NO_MACROS = "Aucune macro trouvée.",
        ST_APPLIED = "Icône %s appliquée à \"%s\".",
        ST_APPLIED_ALL = "Appliquées : %d, échecs : %d.",
        ST_FAILED = "Impossible d'appliquer l'icône à \"%s\".",
        ST_INVALID_ID = "Saisissez un ID d'icône numérique supérieur à 0.",
        ST_COMBAT = "Les macros sont protégées en combat. Nouvel essai après le combat.",
        ST_AUTO_ON = "Changement automatique des icônes à la connexion : ACTIVÉ",
        ST_AUTO_OFF = "Changement automatique des icônes à la connexion : DÉSACTIVÉ",
        ST_RESET = "Icônes enregistrées effacées.",
        ST_PICKER_EMPTY = "Liste d'icônes indisponible.",

        TIP_CHECK = "Cochez pour attribuer une icône personnalisée à cette macro.",
        TIP_ICON = "FileDataID de l'icône (ex. 135432). Entrée — appliquer.",
        TIP_CURRENT = "FileDataID actuel de l'icône de la macro.",
        TIP_PREVIEW = "Icône qui sera appliquée.",
        TIP_PICKER = "Choisissez une icône dans la liste.",
        TIP_MINIMAP = "Afficher ou masquer le bouton de la minicarte.",

        PICK_TITLE = "Choisir une icône",
        CHK_MINIMAP = "Minicarte",

        PRINT_HELP = "Commandes : /mis — ouvrir la fenêtre | /mis apply — appliquer les icônes | /mis on|off — changement auto | /mis reset — effacer les icônes | /mis help",
    },
    esES = {
        TITLE = "MacrosIconSwitcher",
        SUB = "Asignar iconos a las macros: se aplican automáticamente al entrar",

        HEAD_ON = "Act.",
        HEAD_NAME = "Macro",
        HEAD_CURRENT = "Actual",
        HEAD_TARGET = "Nueva",
        HEAD_ICON = "ID de icono",

        BTN_APPLY = "Aplicar",
        BTN_REFRESH = "Actualizar",
        BTN_CLOSE = "Cerrar",

        ST_MACRO_COUNT = "Macros encontradas: %d",
        ST_NO_MACROS = "No se encontraron macros.",
        ST_APPLIED = "Icono %s aplicado a \"%s\".",
        ST_APPLIED_ALL = "Aplicados: %d, fallidos: %d.",
        ST_FAILED = "No se pudo aplicar el icono a \"%s\".",
        ST_INVALID_ID = "Introduce un ID de icono numérico mayor que 0.",
        ST_COMBAT = "Las macros están protegidas en combate. Se reintentará después.",
        ST_AUTO_ON = "Cambio automático de iconos al entrar: ACTIVADO",
        ST_AUTO_OFF = "Cambio automático de iconos al entrar: DESACTIVADO",
        ST_RESET = "Iconos guardados borrados.",
        ST_PICKER_EMPTY = "Lista de iconos no disponible.",

        TIP_CHECK = "Marca para asignar un icono personalizado a esta macro.",
        TIP_ICON = "FileDataID del icono (p. ej. 135432). Intro — aplicar.",
        TIP_CURRENT = "FileDataID actual del icono de la macro.",
        TIP_PREVIEW = "Icono que se aplicará.",
        TIP_PICKER = "Elige un icono de la lista.",
        TIP_MINIMAP = "Mostrar u ocultar el botón del minimapa.",

        PICK_TITLE = "Elegir icono",
        CHK_MINIMAP = "Minimapa",

        PRINT_HELP = "Comandos: /mis — abrir ventana | /mis apply — aplicar iconos | /mis on|off — cambio automático | /mis reset — borrar iconos | /mis help",
    },
    esMX = {
        TITLE = "MacrosIconSwitcher",
        SUB = "Asignar íconos a las macros: se aplican automáticamente al entrar",

        HEAD_ON = "Act.",
        HEAD_NAME = "Macro",
        HEAD_CURRENT = "Actual",
        HEAD_TARGET = "Nueva",
        HEAD_ICON = "ID de ícono",

        BTN_APPLY = "Aplicar",
        BTN_REFRESH = "Actualizar",
        BTN_CLOSE = "Cerrar",

        ST_MACRO_COUNT = "Macros encontradas: %d",
        ST_NO_MACROS = "No se encontraron macros.",
        ST_APPLIED = "Ícono %s aplicado a \"%s\".",
        ST_APPLIED_ALL = "Aplicados: %d, fallidos: %d.",
        ST_FAILED = "No se pudo aplicar el ícono a \"%s\".",
        ST_INVALID_ID = "Escribe un ID de ícono numérico mayor que 0.",
        ST_COMBAT = "Las macros están protegidas en combate. Se reintentará después.",
        ST_AUTO_ON = "Cambio automático de íconos al entrar: ACTIVADO",
        ST_AUTO_OFF = "Cambio automático de íconos al entrar: DESACTIVADO",
        ST_RESET = "Íconos guardados borrados.",
        ST_PICKER_EMPTY = "Lista de íconos no disponible.",

        TIP_CHECK = "Marca para asignar un ícono personalizado a esta macro.",
        TIP_ICON = "FileDataID del ícono (p. ej. 135432). Intro — aplicar.",
        TIP_CURRENT = "FileDataID actual del ícono de la macro.",
        TIP_PREVIEW = "Ícono que se aplicará.",
        TIP_PICKER = "Elige un ícono de la lista.",
        TIP_MINIMAP = "Mostrar u ocultar el botón del minimapa.",

        PICK_TITLE = "Elegir ícono",
        CHK_MINIMAP = "Minimapa",

        PRINT_HELP = "Comandos: /mis — abrir ventana | /mis apply — aplicar íconos | /mis on|off — cambio automático | /mis reset — borrar íconos | /mis help",
    },
    ptBR = {
        TITLE = "MacrosIconSwitcher",
        SUB = "Atribuir ícones às macros — aplicado automaticamente ao entrar",

        HEAD_ON = "Ativo",
        HEAD_NAME = "Macro",
        HEAD_CURRENT = "Atual",
        HEAD_TARGET = "Nova",
        HEAD_ICON = "ID do ícone",

        BTN_APPLY = "Aplicar",
        BTN_REFRESH = "Atualizar",
        BTN_CLOSE = "Fechar",

        ST_MACRO_COUNT = "Macros encontradas: %d",
        ST_NO_MACROS = "Nenhuma macro encontrada.",
        ST_APPLIED = "Ícone %s aplicado a \"%s\".",
        ST_APPLIED_ALL = "Aplicados: %d, falhas: %d.",
        ST_FAILED = "Não foi possível aplicar o ícone a \"%s\".",
        ST_INVALID_ID = "Digite um ID de ícone numérico maior que 0.",
        ST_COMBAT = "As macros são protegidas em combate. Tentará novamente depois.",
        ST_AUTO_ON = "Troca automática de ícones ao entrar: LIGADA",
        ST_AUTO_OFF = "Troca automática de ícones ao entrar: DESLIGADA",
        ST_RESET = "Ícones salvos apagados.",
        ST_PICKER_EMPTY = "Lista de íconos indisponível.",

        TIP_CHECK = "Marque para atribuir um ícone personalizado a esta macro.",
        TIP_ICON = "FileDataID do ícone (ex.: 135432). Enter — aplicar.",
        TIP_CURRENT = "FileDataID atual do ícone da macro.",
        TIP_PREVIEW = "Ícone que será aplicado.",
        TIP_PICKER = "Escolha um ícone da lista.",
        TIP_MINIMAP = "Mostrar ou ocultar o botão do minimapa.",

        PICK_TITLE = "Escolher ícone",
        CHK_MINIMAP = "Minimapa",

        PRINT_HELP = "Comandos: /mis — abrir janela | /mis apply — aplicar ícones | /mis on|off — troca automática | /mis reset — apagar ícones | /mis help",
    },
    itIT = {
        TITLE = "MacrosIconSwitcher",
        SUB = "Assegna icone alle macro: applicate automaticamente al login",

        HEAD_ON = "Attiva",
        HEAD_NAME = "Macro",
        HEAD_CURRENT = "Attuale",
        HEAD_TARGET = "Nuova",
        HEAD_ICON = "ID icona",

        BTN_APPLY = "Applica",
        BTN_REFRESH = "Aggiorna",
        BTN_CLOSE = "Chiudi",

        ST_MACRO_COUNT = "Macro trovate: %d",
        ST_NO_MACROS = "Nessuna macro trovata.",
        ST_APPLIED = "Icona %s applicata a \"%s\".",
        ST_APPLIED_ALL = "Applicate: %d, fallite: %d.",
        ST_FAILED = "Impossibile applicare l'icona a \"%s\".",
        ST_INVALID_ID = "Inserisci un ID icona numerico maggiore di 0.",
        ST_COMBAT = "Le macro sono protette in combattimento. Riprova dopo la fine.",
        ST_AUTO_ON = "Cambio automatico icone al login: ATTIVO",
        ST_AUTO_OFF = "Cambio automatico icone al login: DISATTIVO",
        ST_RESET = "Icone salvate cancellate.",
        ST_PICKER_EMPTY = "Elenco icone non disponibile.",

        TIP_CHECK = "Seleziona per assegnare un'icona personalizzata a questa macro.",
        TIP_ICON = "FileDataID dell'icona (es. 135432). Invio — applica.",
        TIP_CURRENT = "FileDataID attuale dell'icona della macro.",
        TIP_PREVIEW = "Icona che verrà applicata.",
        TIP_PICKER = "Scegli un'icona dall'elenco.",
        TIP_MINIMAP = "Mostra o nascondi il pulsante della minimappa.",

        PICK_TITLE = "Scegli icona",
        CHK_MINIMAP = "Minimappa",

        PRINT_HELP = "Comandi: /mis — apri finestra | /mis apply — applica icone | /mis on|off — cambio automatico | /mis reset — cancella icone | /mis help",
    },
    zhCN = {
        TITLE = "MacrosIconSwitcher",
        SUB = "为宏指定图标 — 登录时自动应用",

        HEAD_ON = "启用",
        HEAD_NAME = "宏",
        HEAD_CURRENT = "当前",
        HEAD_TARGET = "新",
        HEAD_ICON = "图标ID",

        BTN_APPLY = "立即应用",
        BTN_REFRESH = "刷新",
        BTN_CLOSE = "关闭",

        ST_MACRO_COUNT = "找到宏：%d",
        ST_NO_MACROS = "未找到宏。",
        ST_APPLIED = "图标 %s 已应用到「%s」。",
        ST_APPLIED_ALL = "已应用：%d，失败：%d。",
        ST_FAILED = "无法将图标应用到「%s」。",
        ST_INVALID_ID = "请输入大于 0 的数字图标 ID。",
        ST_COMBAT = "战斗中宏受保护，战斗结束后自动重试。",
        ST_AUTO_ON = "登录时自动更换图标：开",
        ST_AUTO_OFF = "登录时自动更换图标：关",
        ST_RESET = "已清除保存的图标。",
        ST_PICKER_EMPTY = "图标列表不可用。",

        TIP_CHECK = "勾选后可为该宏指定自定义图标。",
        TIP_ICON = "图标 FileDataID（例如 135432），回车应用。",
        TIP_CURRENT = "宏当前图标的 FileDataID。",
        TIP_PREVIEW = "将要应用的图标。",
        TIP_PICKER = "从列表中选择图标。",
        TIP_MINIMAP = "显示或隐藏小地图按钮。",

        PICK_TITLE = "选择图标",
        CHK_MINIMAP = "小地图",

        PRINT_HELP = "命令：/mis — 打开窗口 | /mis apply — 应用图标 | /mis on|off — 登录自动更换 | /mis reset — 清除保存的图标 | /mis help",
    },
    zhTW = {
        TITLE = "MacrosIconSwitcher",
        SUB = "為巨集指定圖示 — 登入時自動套用",

        HEAD_ON = "開啟",
        HEAD_NAME = "巨集",
        HEAD_CURRENT = "目前",
        HEAD_TARGET = "新",
        HEAD_ICON = "圖示ID",

        BTN_APPLY = "立即套用",
        BTN_REFRESH = "重新整理",
        BTN_CLOSE = "關閉",

        ST_MACRO_COUNT = "找到巨集：%d",
        ST_NO_MACROS = "找不到任何巨集。",
        ST_APPLIED = "圖示 %s 已套用到「%s」。",
        ST_APPLIED_ALL = "已套用：%d，失敗：%d。",
        ST_FAILED = "無法將圖示套用到「%s」。",
        ST_INVALID_ID = "請輸入大於 0 的數字圖示 ID。",
        ST_COMBAT = "戰鬥中巨集受保護，戰鬥結束後自動重試。",
        ST_AUTO_ON = "登入時自動更換圖示：開",
        ST_AUTO_OFF = "登入時自動更換圖示：關",
        ST_RESET = "已清除儲存的圖示。",
        ST_PICKER_EMPTY = "圖示清單無法使用。",

        TIP_CHECK = "勾選後可為此巨集指定自訂圖示。",
        TIP_ICON = "圖示 FileDataID（例如 135432），按 Enter 套用。",
        TIP_CURRENT = "巨集目前圖示的 FileDataID。",
        TIP_PREVIEW = "將要套用的圖示。",
        TIP_PICKER = "從清單中選擇圖示。",
        TIP_MINIMAP = "顯示或隱藏小地圖按鈕。",

        PICK_TITLE = "選擇圖示",
        CHK_MINIMAP = "小地圖",

        PRINT_HELP = "指令：/mis — 開啟視窗 | /mis apply — 套用圖示 | /mis on|off — 登入自動更換 | /mis reset — 清除儲存的圖示 | /mis help",
    },
    koKR = {
        TITLE = "MacrosIconSwitcher",
        SUB = "매크로에 아이콘 지정 — 로그인 시 자동 적용",

        HEAD_ON = "사용",
        HEAD_NAME = "매크로",
        HEAD_CURRENT = "현재",
        HEAD_TARGET = "새",
        HEAD_ICON = "아이콘 ID",

        BTN_APPLY = "적용",
        BTN_REFRESH = "새로 고침",
        BTN_CLOSE = "닫기",

        ST_MACRO_COUNT = "발견된 매크로: %d",
        ST_NO_MACROS = "매크로를 찾을 수 없습니다.",
        ST_APPLIED = "아이콘 %s을(를) \"%s\"에 적용했습니다.",
        ST_APPLIED_ALL = "적용: %d, 실패: %d.",
        ST_FAILED = "\"%s\"에 아이콘을 적용할 수 없습니다.",
        ST_INVALID_ID = "0보다 큰 숫자 아이콘 ID를 입력하세요.",
        ST_COMBAT = "전투 중에는 매크로가 보호됩니다. 전투 후 자동으로 재시도합니다.",
        ST_AUTO_ON = "로그인 시 아이콘 자동 변경: 켜짐",
        ST_AUTO_OFF = "로그인 시 아이콘 자동 변경: 꺼짐",
        ST_RESET = "저장된 아이콘을 삭제했습니다.",
        ST_PICKER_EMPTY = "아이콘 목록을 사용할 수 없습니다.",

        TIP_CHECK = "체크하면 이 매크로에 사용자 지정 아이콘을 지정합니다.",
        TIP_ICON = "아이콘 FileDataID (예: 135432). Enter — 적용.",
        TIP_CURRENT = "매크로의 현재 아이콘 FileDataID.",
        TIP_PREVIEW = "적용될 아이콘입니다.",
        TIP_PICKER = "목록에서 아이콘을 선택하세요.",
        TIP_MINIMAP = "미니맵 버튼을 표시하거나 숨깁니다.",

        PICK_TITLE = "아이콘 선택",
        CHK_MINIMAP = "미니맵",

        PRINT_HELP = "명령어: /mis — 창 열기 | /mis apply — 아이콘 적용 | /mis on|off — 자동 변경 | /mis reset — 저장된 아이콘 삭제 | /mis help",
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
    -- Order matters: zhTW must be matched before the common "zh" prefix.
    local prefixes = {
        ru = "ruRU",
        de = "deDE",
        fr = "frFR",
        esMX = "esMX",
        es = "esES",
        pt = "ptBR",
        it = "itIT",
        zhTW = "zhTW",
        zh = "zhCN",
        ko = "koKR",
    }
    for prefix, code in pairs(prefixes) do
        if rl:find("^" .. prefix) then return code end
    end
    return "enUS"
end

_G.MacrosIconSwitcherL10n = MacrosIconSwitcherL10n
