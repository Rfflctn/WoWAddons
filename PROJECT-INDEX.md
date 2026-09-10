# PROJECT-INDEX.md — быстрый ориентир для агентов (читать ПЕРВЫМ, ~1 мин)

> Источник истины по маршрутизации — `AGENTS.md`. Этот файл — только карта.
> Патч: Retail 12.1.0 / Midnight. Обновлено: 2026-09-11 (релиз 2.0.0: 20×Lua, виртуализация, ресайз).
> **Правило слоёв:** §0–§2 — читать всегда. §3 (`wiki-lua/`) — ТОЛЬКО если задача прошла гейт ниже.

## 0. Дерево (корень `W:\Projects\WoW Addons\`)

```
AGENTS.md                  # маршрутизация и жёсткие правила (читать вторым)
PROJECT-INDEX.md           # этот файл
opencode.json              # конфиг модели (lmstudio, локалка)
addons/DecorLumberProfit/   # ЕДИНСТВЕННЫЙ аддон с кодом (TOC + 20×Lua: см. §2)
tools/                     # поиск API, проверки, тесты: run_tests.py + tests/test_*.py (11 сьютов)
wiki-lua/                  # архив доков (~8 тыс. файлов) — СМ. ГЕЙТ В §1, по умолчанию НЕ трогать
```

## 1. Гейт: нужна ли wiki-lua? (ответь за 5 секунд)

- **НЕ нужна (типично):** чистый Lua, вёрстка UI, локали, формулы экономики, рефакторинг без новых API, правки `Config/Locales/UI/Auction/Core` по уже известным сигнатурам → работай только в `addons/` + `tools/`, §3 не открывай.
- **Нужна:** новая функция `C_*`/`Get*`/`Unit*`, новое событие, метод виджета, taint/secure-вопрос, поле TOC, поведение патча → иди в §3, детали — в `AGENTS.md`.

## 2. Ядро (всегда достаточно для кодовых задач)

- `addons/DecorLumberProfit/DecorLumberProfit.toc` — метаданные (`Interface: 120100`), порядок загрузки Lua: Locales → Init → Data/Wood → Config → Services/ItemInfo → Services/Recipes → Services/Store → Services/Economy → Util/Money → Services/Prices (держит legacy-алиас `DecorLumberProfitAuction`) → Core → UI → UI/Status → UI/Tooltip → UI/TableView → UI/Actions → UI/MainFrame → UI/Popups → UI/Commands → Services/Diag.
- `addons/DecorLumberProfit/Init.lua` — неймспейс `DecorLumberProfit`: `VERSION` (sync с `.toc`), `DB_SCHEMA`, `SafeCall`/`CountTable`/`Log` (Log делегирует в Diag, если загружен). Контракт SafeCall: первый результат или nil (НЕ ok-первым!). Совместимость: `local unpack = unpack or table.unpack`.
- `addons/DecorLumberProfit/Data/Wood.lua` — владелец данных древесины: 12 ID + `WOOD_IDS_SET` + `WOOD_NAMES`; наполняет `Config.WOOD_*` (совместимость, Core читает Config) + публикует `DecorLumberProfitWood` (те же таблицы, без копий).
- `addons/DecorLumberProfit/Config.lua` — тюнинг AUCTION/UI/SCAN (`ENABLE_BRUTEFORCE`, `MAX_RESULTS` — меняются через `/dlp debug set`) + `API_CHECKLIST`. НЕ пересоздавать таблицу (`or {}`) — Wood грузится раньше.
- `addons/DecorLumberProfit/Services/ItemInfo.lua` — bind tri-state (`IsUnsellable`), имена (`GetName`), pending (`PendingAdd/ResolvePending/FailPendingForItem/PendingCount`), `PruneUnsellable`, `HealthCheck`. Core держит форвардеры + алиас `_pendingBind` (shared table).
- `addons/DecorLumberProfit/Services/Recipes.lua` — схемы (`GetRecipeData`), перечисление, unified `Scan({scope="active"|"all"})` (коды ошибок сохранены), `DebugActive/DebugSpell`, `HealthCheck`. Все функции через точку (без self); Core — `:`-врапперы.
- `addons/DecorLumberProfit/Services/Store.lua` — персистентность: `Upgrade` (adopt legacy имён + ensure + stamp `schemaVersion`), `RememberRecipe`, `SaveRecipe` (`savedAt/updatedAt`), `LoadSavedRecipes`, `MarkLearnedBy`, `RefreshLearnedFlags`, `EnforceCap` (1000, режет только timestamped). priceCache владеет Prices, settings — UI.
- `addons/DecorLumberProfit/Services/Economy.lua` — чистая `CalculateRecipeEconomy` (формулы НЕ менять!). Core — `:`-враппер.
- `addons/DecorLumberProfit/Util/Money.lua` — `FormatMoney` (владелец; Prices держит алиас).
- `addons/DecorLumberProfit/Services/Prices.lua` — очередь АХ (`SendSearchQuery`, O(1)-overflow, батч-sweep `sentAt`, coalesce UI-обновлений, `GetQueueInfo` requested/resolved); legacy-алиас `DecorLumberProfitAuction`.
- `addons/DecorLumberProfit/Core.lua` — только тонкие врапперы над Services/* (логики нет).
- `addons/DecorLumberProfit/UI.lua` — неймспейс + общее состояние таблицы (`UI._x`, `UI.displayList`-алиас).
- `addons/DecorLumberProfit/UI/TableView.lua` — колонки (`UI.COLUMNS`, `LayoutColumns/ColWidth`), сортировка (`OnHeaderClick`), пул строк с виртуализацией (`VisibleRange`, `RenderVisibleRows`, фолбэк «всё» без высоты), `RefreshTable` (прогресс `ST_QUEUE_PROGRESS` из `Prices.GetQueueInfo`), иконки, `SetHideUnlearned`.
- `addons/DecorLumberProfit/UI/MainFrame.lua` — окно: ресайз 700–1400 (`OnMainFrameSizeChanged`, троттлинг 20px, снос пула), health-dot (`UI._healthDot`), шапка (`LayoutHeaderCells`, фикс захвата loop-var), скролл + `OnVerticalScroll`-хук.
- `addons/DecorLumberProfit/UI/Actions.lua` — скан/DB/цены/очистка; `UI/Commands.lua` — slash + события; `UI/Status.lua` — `SetStatus` (+цвет точки); `UI/Tooltip.lua` — тултипы (item-ссылки `SetItemByID` с фолбэком); `UI/Popups.lua` — StaticPopup.
- `addons/DecorLumberProfit/Services/Diag.lua` — диагностика: `Diag.Log` (уровни ERROR/WARN/INFO/VERBOSE), `lastError`, `SubsystemStatus`, `/dlp debug status|selftest|verbose on|off`, `/dlp bug` (бандл для issue).
- `addons/DecorLumberProfit/Locales.lua` — тексты `enUS`/`ruRU` (`L[]`/`TL()`).
- `addons/DecorLumberProfit/README.md` — ТЗ, формулы, установка; `CHANGELOG.md` — история релизов и изменений.
- Проверки после правок Lua: `python tools/syntax_check.py` → `python tools/run_tests.py` → `python tools/check_locales.py` (строгий: missing/diff/fmt = FAIL). При изменении версии запускать `python tools/check_version.py`. `tools/smoke_test.py` — legacy (загрузчик синхронизирован с `.toc`, гейтом не является).
- Тесты: `tools/tests/stub.lua` (стабы WoW, STUB v1) + `tools/tests/test_*.py`: `test_money`, `test_economy`, `test_recipes` (Scan active/all, ветки ошибок, флаги), `test_prices`, `test_wood` (+parity Wood≡Config), `test_diag`, `test_init` (контракт SafeCall!), `test_iteminfo`, `test_store` (Upgrade/adopt/cap), `test_tableview` (VisibleRange, ColWidth), `test_removed_apis` (denylist удалённых Midnight-API: lupa-стабы их не ловят). Порядок загрузки Lua читается из `.toc`, у каждого сьюта свежий рантайм (изоляции, зависимости между сьютами запрещены).
- Пути относительные от корня; абсолютных `W:\...` быть не должно. Имя папки аддона = имени `.toc`.

## 3. wiki-lua/ — ON-DEMAND (читать раздел ТОЛЬКО при гейте «нужна»)

Состав (замерено): `*.md` (69) — статьи/how-to; `blizzard_api_doc/` (612×.lua) — официальные доки клиента;
`INDEX-api.md` (~9900 записей) — grep-индекс; `pages/api/` (6197×.md) — примеры; `pages/events/` (2054×.md).

| Нужно | Действие (не читать файлы целиком!) |
|---|---|
| Сигнатура `C_*` / глобальная функция / событие / Enum | `powershell -File tools/find-api.ps1 "<Имя>"` — первый вход, не грепать 612 файлов вручную |
| Метод виджета / script handler | `wiki-lua/15_widget_api.md` и `wiki-lua/16_widget_script_handlers.md`; `find-api.ps1` — дополнительно при наличии записи в официальном архиве |
| Концепция (taint, SavedVariables, TOC, якоря, меню) | `wiki-lua/<тема>.md` по списку из `AGENTS.md` |
| Пример / patch changes функции | `wiki-lua/pages/api/API_<Имя>.md` — поиск по имени файла |
| Аргументы события | `wiki-lua/pages/events/<Имя>.md` — поиск по имени файла |
| Каталог всех статей | `wiki-lua/README.md` |
| Перегенерация индекса | `tools/build-index.ps1` (после обновления `blizzard_api_doc/`) |

Запреты (полный список — `AGENTS.md`): НЕ читать целиком файлы > 100 КБ
(`14_world_of_warcraft_api.md`, `22_scripts.md`, `34_console_variables.md`, `20_events.md`,
`15_widget_api.md`, `80_api_changes_12.1.0.md`, `INDEX-api.md`, `pages/api/Global functions.md`) —
только `Select-String` с контекстом ≤ 20 строк. Игнор: `__pycache__/`, `wiki-lua/batch*.json`,
`wiki-lua/pages/progress.log`, `docs/wow_addons/*.html`. Отсутствие функции в `pages/api/`
НЕ значит отсутствие в игре — истина в `blizzard_api_doc/`. `wiki-lua/fetch_*.py` — только для
перекачки доков (нужен internet), в обычной работе не запускать.
