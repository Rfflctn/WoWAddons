-- Locales.lua | DecorLumberProfit | Retail 12.1.0
-- Все тексты аддона. Локали: enUS (базовая), ruRU.
-- Выбор локали: авто по GetLocale() или переопределение /dlp locale ru|en|auto
-- (хранится в DecorLumberProfitDB.settings.locale, применяется после /reload).
-- Использование: L["KEY"] — строка; TL("KEY", ...) — строка через string.format.

DecorLumberProfitLocale = {
    enUS = {
        -- Заголовок и кнопки
        TITLE = "Thalassian Lumber — Profitability Calculator",
        BTN_REFRESH = "Update recipes",
        BTN_PRICES = "Update prices",
        BTN_CLEAR_CACHE = "Reset cache",
        BTN_CLEAR_TABLE = "Clear table",
        BTN_TOP = "Top profit",
        BTN_SHOW_ALL = "Show all",
        CHK_HIDE_UNLEARNED = "Hide unlearned",
        BTN_COLUMNS = "Columns",
        BTN_SHOW_ALL_COLUMNS = "Show all",

        -- Тултипы кнопок
        TIP_REFRESH_TITLE = "Add recipes from the active window",
        TIP_REFRESH_L1 = "Open a profession window (K) and press again — recipes from that window are appended to the table without duplicates.",
        TIP_REFRESH_L2 = "Repeat for each profession to build up the list.",
        TIP_REFRESH_L3 = "Searches only for recipes with any lumber (12 types).",
        TIP_PRICES_TITLE = "Request prices from the auction house",
        TIP_PRICES_L1 = "Sends C_AuctionHouse.SendSearchQuery for every reagent and output item.",
        TIP_PRICES_L2 = "Blizzard limit: 100 queries/min. Partially cached.",
        TIP_PRICES_L3 = "The auction house may need to be open for best results (version dependent).",
        TIP_CLEAR_TABLE_TITLE = "Clear the accumulated table",
        TIP_CLEAR_TABLE_L1 = "Removes all recipes from the table and the account-wide database (all characters).",
        TIP_CLEAR_TABLE_L2 = "Auction price cache is kept.",
        TIP_TOP_TITLE = "Top profit",
        TIP_TOP_L1 = "For each lumber type shows 3 recipes with the highest \"max lumber price\" — the price per unit at which crafting still breaks even.",
        TIP_TOP_L2 = "The higher it is above the market lumber price, the more profitable the craft. Press again to switch to \"Show all\".",
        TIP_HIDE_UNLEARNED = "Hides recipes that are not learned by any character on the account.",
        TIP_COLUMNS_TITLE = "Table columns",
        TIP_COLUMNS_L1 = "Choose which columns to show. At least one must stay visible. Saved for the account.",

        -- Колонки таблицы
        HEAD_RECIPE = "Recipe",
        HEAD_PROF = "Profession",
        HEAD_LEARNED = "Learned",
        HEAD_WOOD = "Lumber",
        HEAD_SELL = "Sale",
        HEAD_AHQTY = "On AH",
        HEAD_WOODQTY = "Wood",
        HEAD_MAXPRICE = "Wood price",
        HEAD_PROFIT = "Profit",
        HINT_RECIPE = "Click to sort by recipe name.",
        HINT_PROF = "Profession that crafts the item. Click to sort.",
        HINT_LEARNED = "Is the recipe learned by this character (\"other\" — learned by another character on the account). Click to sort.",
        HINT_WOOD = "Which lumber the recipe consumes. Click to sort.",
        HINT_SELL = "Market price of the crafted item: per unit / total per craft. Click to sort.",
        HINT_AHQTY = "How many of the crafted item are listed on the auction house: total pieces (lots). High values mean high competition. Click to sort.",
        HINT_WOODQTY = "Lumber units consumed per craft. Click to sort.",
        HINT_MAXPRICE = "Economically acceptable lumber PRICE for this recipe: (sale − other reagents cost) / lumber qty. Crafting is profitable while lumber purchase/market price is BELOW this value. Click to sort.",
        HINT_PROFIT = "Profit per craft: sale − all reagents, including lumber at market price. Click to sort.",
        HINT_SORT_GENERIC = "Sort by column \"%s\".",

        -- Значения ячеек
        CELL_YES = "|cff00ff00yes|r",
        CELL_OTHER = "|cffffaa00other|r",
        CELL_NO = "|cffff5555no|r",
        CELL_UNKNOWN = "|cffffaa00?|r",
        CELL_PROF_UNKNOWN = "|cffffaa00?|r",
        CELL_NO_AH = "|cffff5555no AH|r",
        CELL_DASH = "|cffff5555—|r",
        CELL_NO_PRICE = "|cffff5555no price|r",

        -- Тултип строки
        TIP_RECIPE_FALLBACK = "Recipe",
        TIP_CREATES = "Creates: %s x%d",
        TIP_CREATES_ITEM = "Creates: Item %d x%d",
        TIP_PROFESSION = "Profession: %s",
        TIP_REAGENTS = "Reagents:",
        TIP_AHQTY_LINE = "On AH: %s",
        TIP_NO_PRICE_FOR = "No price for: %s",

        -- Статусы и сообщения
        ST_WELCOME = "Press \"Update recipes\" to scan.",
        ST_AT_LEAST_ONE_COLUMN = "At least one column must stay visible.",
        ST_EMPTY_TABLE = "|cffffd200No recipes with tracked lumber types|r",
        ST_ALL_HIDDEN = "|cffffd200All %d recipes hidden — not learned by any character|r",
        ST_HIDDEN_SUFFIX = "Hidden (unlearned): %d | ",
        ST_PRUNED = "Removed %d recipes with unsellable output (soulbound in group/raid etc.).",
        TOP_PREFIX = "Top-3 per lumber type (%d of %d) | ",
        ST_QUEUED = "Recipes: %d | Missing fresh price: %d | AH queue: %d — press \"Update prices\" in the auction house",
        ST_PARTIAL = "Recipes: %d | Partially no prices (%d) | Data from cache",
        ST_OK = "Recipes: %d | All prices fresh",
        ST_SCAN_DONE = "Auction scan finished",
        ST_THROTTLE = "Auction: query limit (100/min) — dropped queries will be retried automatically, scan continues...",
        ST_ERR_WOOD_ID = "Error: lumber ID not set (Config). Check Config.lua",
        ST_NO_ACTIVE_WINDOW = "Open a profession window (K → pick a profession), then press \"Update recipes\". Recipes from the active window will be added to the table.",
        ST_NO_RECIPES_IN_WINDOW = "No lumber recipes in the active profession window (or API not loaded yet). Try another profession tree or open a subcategory.",
        ST_NO_WOOD_IN_WINDOW = "Window matched %s recipes, but none contain lumber from the list (12 types). Check Config.lua.%s",
        ST_GLOBAL_FALLBACK = "Lumber not found in active window (candidates %d), but %d found globally — added %d. Total %d.",
        ST_NO_RECIPES_ENUMERATED = "Failed to read recipes. Open a profession window and press \"Update recipes\".",
        ST_FOUND_ZERO = "Found 0 lumber recipes in the active window. Total in table: %d.",
        ST_ALL_DUP = "All %d recipes from the active window are already in the table (total %d).",
        ST_ADDED = "Added %d new (of %d in window). Total in table: %d.",
        ST_REBUILD_EMPTY = "Open a profession window and press \"Update recipes\" to build up the table.",
        ST_REBUILD_LOADED = "Loaded %d lumber recipes from all professions.",
        ST_NO_RECIPES_FOR_PRICES = "No recipes to request prices for — find recipes first",
        ST_PRICES_CACHED = "All prices already cached (TTL %d min). To force update, reset the cache or wait.",
        ST_PRICES_REQUESTED = "Requested %d prices — auction queue (limit 100/min). Keep the auction house window open for best results.",
        ST_TABLE_EMPTY_ONSHOW = "Table is empty. Open a profession window (K) and press \"Update recipes\" — recipes from the active window will be added here.",
        ST_PROF_WINDOW_FOUND = "Profession window detected — press \"Update recipes\" to add its recipes to the table.",
        DBG_META = " [skillLines=%s candidates=%s]",
        DBG_META_NO_WOOD = " candidates %d, no output %d, no wood %d, bound/unsellable skipped %d, pending load %d, skillLines=%s",

        -- Print-сообщения
        PREFIX_ERR = "|cffffaa00[DecorLumberProfit]|r ",
        PREFIX_OK = "|cff88ff88[DecorLumberProfit]|r ",
        PREFIX_DIM = "|cffaaaaaa",
        PRINT_NO_RECIPES_ACTIVE = "No lumber recipes in the current window.%s |cffaaaaaa/dump DecorLumberProfitCore:DebugActive() for diagnostics|r",
        PRINT_GLOBAL_FALLBACK = "Active filter failed (%s). Globally added %d recipes.",
        PRINT_NO_WOOD_DETAIL = "Active window has %s recipes: no output %s, no lumber %s. |cffaaaaaa/dump DecorLumberProfitCore:DebugActive() — send a screenshot|r",
        PRINT_WOOD_IDS = "Checking WOOD_IDS: %s",
        PRINT_ACTIVE_DEBUG = "Active skillLines: %s | candidates first: %s",
        PRINT_ALL_DUP = "All recipes already added — no duplicates (in window %d, in table %d).",
        PRINT_ADDED = "Added %d recipes from the active window (total %d).",
        PRINT_ITEMS_RESOLVED = "Item data loaded: added %d recipes (bind checked).",
        PRINT_LOADED = "Loaded. Type /dlp to open the calculator. Lumber types tracked: %d",
        PRINT_HELP = "Commands: /dlp — open window, /dlp help — help, /dlp reset — reset cache, /dlp clear — clear table, /dlp scan — add from active window, /dlp locale ru|en|auto — language",
        DEBUG_HELP = "Diagnostics: /dlp debug — status, /dlp debug selftest — in-game checks, /dlp bug — copy-paste bundle",
        PRINT_VERBOSE_SET = "Verbose logging: %s (saved, no /reload needed).",
        PRINT_SCAN_SET = "Scan setting %s = %s (saved, no /reload needed).",
        PRINT_MAXSCAN_USAGE = "Usage: /dlp debug set maxscan <50-5000> | /dlp debug set bruteforce on|off",
        ST_QUEUE_PROGRESS = " | AH: %d/%d",
        ST_PRICES_TIME = " | Prices: %s",
        ST_PRICES_NEVER = " | Prices: —",
        PRINT_CACHE_RESET = "Price cache reset",
        PRINT_TABLE_CLEARED = "Table and account-wide recipe database cleared",
        PRINT_LOCALE_SET = "Locale: %s. Type /reload to apply.",
        PRINT_LOCALE_USAGE = "Usage: /dlp locale ru|en|auto",

        -- StaticPopup
        POPUP_CLEAR_TEXT = "Clear the table and the ACCOUNT-WIDE recipe database for all characters on this account? The auction price cache will be kept.",
        POPUP_CLEAR_OK = "Clear",
        POPUP_CLEAR_CANCEL = "CANCEL",
    },

    ruRU = {
        -- Заголовок и кнопки
        TITLE = "Талассийская древесина — калькулятор рентабельности",
        BTN_REFRESH = "Обновить рецепты",
        BTN_PRICES = "Обновить цены",
        BTN_CLEAR_CACHE = "Сбросить кэш",
        BTN_CLEAR_TABLE = "Очистить таблицу",
        BTN_TOP = "Топ выгода",
        BTN_SHOW_ALL = "Показать все",
        CHK_HIDE_UNLEARNED = "Скрыть неизученное",
        BTN_COLUMNS = "Столбцы",
        BTN_SHOW_ALL_COLUMNS = "Показать все",

        -- Тултипы кнопок
        TIP_REFRESH_TITLE = "Добавить рецепты из активного окна",
        TIP_REFRESH_L1 = "Откройте окно профессии (K) и нажмите снова — рецепты из этого окна добавятся в таблицу без дублей.",
        TIP_REFRESH_L2 = "Повторите для каждой профессии, чтобы накопить список.",
        TIP_REFRESH_L3 = "Ищет только рецепты с любой древесиной (12 типов).",
        TIP_PRICES_TITLE = "Запросить цены с аукциона",
        TIP_PRICES_L1 = "Отправляет C_AuctionHouse.SendSearchQuery для каждого реагента и предмета.",
        TIP_PRICES_L2 = "Лимит Blizzard: 100 запросов/мин. Частично кэшируется.",
        TIP_PRICES_L3 = "Аукцион может требовать открытый дом аукциона (зависит от версии).",
        TIP_CLEAR_TABLE_TITLE = "Очистить накопленную таблицу",
        TIP_CLEAR_TABLE_L1 = "Удаляет все рецепты из таблицы и общей базы аккаунта (для всех персонажей).",
        TIP_CLEAR_TABLE_L2 = "Кэш цен аукциона сохраняется.",
        TIP_TOP_TITLE = "Топ выгода",
        TIP_TOP_L1 = "Для каждого вида древесины показывает 3 рецепта с наивысшей «макс. ценой древ.» — ценой за штуку, при которой крафт ещё выходит в ноль.",
        TIP_TOP_L2 = "Чем она выше рыночной цены древесины, тем выгоднее крафт. Повторное нажатие — «Показать все».",
        TIP_HIDE_UNLEARNED = "Скрывает рецепты, которые не изучены ни на одном персонаже аккаунта.",
        TIP_COLUMNS_TITLE = "Столбцы таблицы",
        TIP_COLUMNS_L1 = "Выберите, какие столбцы показывать. Хотя бы один должен остаться видимым. Сохраняется для аккаунта.",

        -- Колонки таблицы
        HEAD_RECIPE = "Рецепт",
        HEAD_PROF = "Профессия",
        HEAD_LEARNED = "Изучен",
        HEAD_WOOD = "Древесина",
        HEAD_SELL = "Продажа",
        HEAD_AHQTY = "На АХ",
        HEAD_WOODQTY = "Древ.",
        HEAD_MAXPRICE = "Цена др.",
        HEAD_PROFIT = "Прибыль",
        HINT_RECIPE = "Клик — сортировка по имени рецепта.",
        HINT_PROF = "Профессия, в которой создаётся предмет. Клик — сортировка.",
        HINT_LEARNED = "Изучен ли рецепт текущим персонажем («др.перс» — изучен другим персонажем аккаунта). Клик — сортировка.",
        HINT_WOOD = "Какая древесина расходуется в рецепте. Клик — сортировка.",
        HINT_SELL = "Цена готового предмета на аукционе: за штуку / всего за один крафт. Клик — сортировка.",
        HINT_AHQTY = "Сколько готового предмета выставлено на аукционе: всего штук (лотов). Большие значения — высокая конкуренция. Клик — сортировка.",
        HINT_WOODQTY = "Сколько штук древесины уходит на один крафт. Клик — сортировка.",
        HINT_MAXPRICE = "Экономически допустимая ЦЕНА древесины для этого рецепта: (продажа − себестоимость прочих реагентов) / кол-во древесины. Крафт выгоден, пока закупочная/рыночная цена древесины НИЖЕ этого значения. Клик — сортировка.",
        HINT_PROFIT = "Прибыль с одного крафта: продажа − все реагенты, включая древесину по её рыночной цене. Клик — сортировка.",
        HINT_SORT_GENERIC = "Сортировка по колонке «%s».",

        -- Значения ячеек
        CELL_YES = "|cff00ff00да|r",
        CELL_OTHER = "|cffffaa00др.перс|r",
        CELL_NO = "|cffff5555нет|r",
        CELL_UNKNOWN = "|cffffaa00?|r",
        CELL_PROF_UNKNOWN = "|cffffaa00?|r",
        CELL_NO_AH = "|cffff5555нет на АХ|r",
        CELL_DASH = "|cffff5555—|r",
        CELL_NO_PRICE = "|cffff5555нет цены|r",

        -- Тултип строки
        TIP_RECIPE_FALLBACK = "Рецепт",
        TIP_CREATES = "Создаёт: %s x%d",
        TIP_CREATES_ITEM = "Создаёт: Item %d x%d",
        TIP_PROFESSION = "Профессия: %s",
        TIP_REAGENTS = "Реагенты:",
        TIP_AHQTY_LINE = "На АХ: %s",
        TIP_NO_PRICE_FOR = "Нет цены для: %s",

        -- Статусы и сообщения
        ST_WELCOME = "Нажмите «Обновить рецепты» для поиска.",
        ST_AT_LEAST_ONE_COLUMN = "Хотя бы один столбец должен остаться видимым.",
        ST_EMPTY_TABLE = "|cffffd200Нет рецептов с древесиной из отслеживаемых типов|r",
        ST_ALL_HIDDEN = "|cffffd200Скрыто все рецепты (%d шт.) — не изучены ни на одном персонаже|r",
        ST_HIDDEN_SUFFIX = "Скрыто (не изучено): %d | ",
        ST_PRUNED = "Убрано %d рецептов с непродаваемой продукцией (привязка к отряду/рейду и т.п.).",
        TOP_PREFIX = "Топ-3 по каждой древесине (%d из %d) | ",
        ST_QUEUED = "Рецептов: %d | Без актуальной цены: %d | В очереди АХ: %d — нажмите «Обновить цены» у аукциона",
        ST_PARTIAL = "Рецептов: %d | Частично без цен (%d) | Данные из кэша",
        ST_OK = "Рецептов: %d | Все цены актуальны",
        ST_SCAN_DONE = "Сканирование аукциона завершено",
        ST_THROTTLE = "Аукцион: лимит запросов (100/мин) — отброшенные запросы будут повторены автоматически, скан продолжается...",
        ST_ERR_WOOD_ID = "Ошибка: не задан ID древесины (Config). Проверьте Config.lua",
        ST_NO_ACTIVE_WINDOW = "Откройте окно профессии (K → выберите профессию), затем нажмите «Обновить рецепты». В таблицу добавятся рецепты из активного окна.",
        ST_NO_RECIPES_IN_WINDOW = "В активном окне профессии нет рецептов с древесиной (или API ещё не прогрузился). Попробуйте другое дерево профессий или откройте подкатегорию.",
        ST_NO_WOOD_IN_WINDOW = "В окне найдено %s рецептов, но ни один не содержит древесину из списка (12 типов). Проверьте Config.lua.%s",
        ST_GLOBAL_FALLBACK = "В активном окне древесина не найдена (кандидатов %d), но глобально найдено %d — добавлено %d. Всего %d.",
        ST_NO_RECIPES_ENUMERATED = "Не удалось прочитать рецепты. Откройте окно профессии и нажмите «Обновить рецепты».",
        ST_FOUND_ZERO = "В активном окне найдено 0 рецептов с древесиной. Всего в таблице: %d.",
        ST_ALL_DUP = "Все %d рецептов из активного окна уже в таблице (всего %d).",
        ST_ADDED = "Добавлено %d новых (из %d в окне). Всего в таблице: %d.",
        ST_REBUILD_EMPTY = "Откройте окно профессии и нажмите «Обновить рецепты» для накопления таблицы.",
        ST_REBUILD_LOADED = "Загружено %d рецептов с древесиной из всех профессий.",
        ST_NO_RECIPES_FOR_PRICES = "Нет рецептов для запроса цен — сначала найдите рецепты",
        ST_PRICES_CACHED = "Все цены уже в кэше (TTL %d мин). Для принудительного обновления удалите кэш или подождите.",
        ST_PRICES_REQUESTED = "Запрошено цен: %d — очередь аукциона (лимит 100/мин). Держите окно аукциона открытым для лучшего результата.",
        ST_TABLE_EMPTY_ONSHOW = "Таблица пуста. Откройте окно профессии (K) и нажмите «Обновить рецепты» — рецепты из активного окна добавятся сюда.",
        ST_PROF_WINDOW_FOUND = "Обнаружено окно профессии — нажмите «Обновить рецепты» чтобы добавить её рецепты в таблицу.",
        DBG_META = " [skillLines=%s candidates=%s]",
        DBG_META_NO_WOOD = " кандидатов %d, без output %d, без древесины %d, привязка/непродаваемые пропущено %d, ожидают загрузку %d, skillLines=%s",

        -- Print-сообщения
        PREFIX_ERR = "|cffffaa00[DecorLumberProfit]|r ",
        PREFIX_OK = "|cff88ff88[DecorLumberProfit]|r ",
        PREFIX_DIM = "|cffaaaaaa",
        PRINT_NO_RECIPES_ACTIVE = "Нет рецептов с древесиной в текущем окне.%s |cffaaaaaa/dump DecorLumberProfitCore:DebugActive() для диагностики|r",
        PRINT_GLOBAL_FALLBACK = "Активный фильтр не сработал (%s). Глобально добавлено %d рецептов.",
        PRINT_NO_WOOD_DETAIL = "В активном окне %s рецептов, из них без output %s, без древесины %s. |cffaaaaaa/dump DecorLumberProfitCore:DebugActive() — пришлите скрин|r",
        PRINT_WOOD_IDS = "Проверяемые WOOD_IDS: %s",
        PRINT_ACTIVE_DEBUG = "Active skillLines: %s | candidates first: %s",
        PRINT_ALL_DUP = "Все рецепты уже добавлены — дублей нет (в окне %d, в таблице %d).",
        PRINT_ADDED = "Добавлено %d рецептов из активного окна (всего %d).",
        PRINT_ITEMS_RESOLVED = "Догружены данные предметов: добавлено %d рецептов (привязка проверена).",
        PRINT_LOADED = "Загружен. Введите /dlp для открытия калькулятора. Типов древесины: %d",
        PRINT_HELP = "Команды: /dlp — открыть окно, /dlp help — справка, /dlp reset — сброс кэша, /dlp clear — очистить таблицу, /dlp scan — добавить из активного окна, /dlp locale ru|en|auto — язык",
        DEBUG_HELP = "Диагностика: /dlp debug — статус, /dlp debug selftest — проверки в игре, /dlp bug — блок для копипасты",
        PRINT_VERBOSE_SET = "Подробные логи: %s (сохранено, /reload не нужен).",
        PRINT_SCAN_SET = "Настройка сканирования %s = %s (сохранено, /reload не нужен).",
        PRINT_MAXSCAN_USAGE = "Использование: /dlp debug set maxscan <50-5000> | /dlp debug set bruteforce on|off",
        ST_QUEUE_PROGRESS = " | АХ: %d/%d",
        ST_PRICES_TIME = " | Цены: %s",
        ST_PRICES_NEVER = " | Цены: —",
        PRINT_CACHE_RESET = "Кэш цен сброшен",
        PRINT_TABLE_CLEARED = "Таблица и общая база рецептов очищены",
        PRINT_LOCALE_SET = "Локаль: %s. Введите /reload для применения.",
        PRINT_LOCALE_USAGE = "Использование: /dlp locale ru|en|auto",

        -- StaticPopup
        POPUP_CLEAR_TEXT = "Очистить таблицу и ОБЩУЮ базу рецептов для всех персонажей аккаунта? Кэш цен аукциона останется.",
        POPUP_CLEAR_OK = "Очистить",
        POPUP_CLEAR_CANCEL = "Отмена",
    },
}

local DecorLumberProfitL10n = { locales = DecorLumberProfitLocale }
local active = "enUS"

local function resolve(tbl, key)
    local t = DecorLumberProfitLocale[active]
    local s = t and t[key]
    if s == nil then s = DecorLumberProfitLocale.enUS[key] end
    if s == nil then return key end
    return s
end

-- L["KEY"] — текущая локаль, фолбэк на enUS, затем само имя ключа
DecorLumberProfitL10n.L = setmetatable({}, { __index = resolve })

-- TL("KEY", ...) — string.format от локализованной строки
function DecorLumberProfitL10n.TL(key, ...)
    local s = resolve(nil, key)
    if select("#", ...) > 0 then return string.format(s, ...) end
    return s
end

function DecorLumberProfitL10n.GetLocale() return active end

function DecorLumberProfitL10n.SetLocale(code)
    if code and DecorLumberProfitLocale[code] then active = code end
    return active
end

function DecorLumberProfitL10n.DetectLocale()
    local rl = (_G.GetLocale and GetLocale()) or "enUS"
    if rl:find("^ru") then return "ruRU" end
    return "enUS"
end

-- code|nil из аргумента /dlp locale
function DecorLumberProfitL10n.NormalizeLocaleArg(arg)
    if arg == "ru" then return "ruRU" end
    if arg == "en" then return "enUS" end
    if arg == "auto" then return "auto" end
    return nil
end

_G.DecorLumberProfitL10n = DecorLumberProfitL10n
