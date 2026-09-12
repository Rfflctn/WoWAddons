# AGENTS.md — маршрутизация для AI-агентов

> **Старт за 1 минуту:** сначала прочитай `PROJECT-INDEX.md` (карта: где код, где доки, куда идти по типу задачи),
> затем этот файл (правила и детали маршрутизации). `PROJECT-INDEX.md` — обзор, этот файл — источник истины при расхождениях.

Проект: база знаний по разработке WoW-аддонов (Retail, патч 12.1.0 / Midnight)
+ код аддона в `addons/DecorLumberProfit/` (TOC + 20×Lua: Init, Config, Core, UI, Locales + Data/Wood + Services/ItemInfo, Recipes, Store, Economy, Prices, Diag + Util/Money + UI/Status, Tooltip, TableView, Actions, MainFrame, Popups, Commands; `DecorLumberProfitAuction` — legacy-алиас Prices).

## Карта источников (по убыванию приоритета)

| Задача | Куда идти |
|---|---|
| Сигнатура `C_*`, глобальной функции, события, константы или Enum | **`tools/find-api.ps1 <имя>`** — имя, аргументы, возврат (из `wiki-lua/blizzard_api_doc/`) |
| Метод `Frame`/`Widget` или script handler | `wiki-lua/15_widget_api.md` и `wiki-lua/16_widget_script_handlers.md`; `find-api.ps1` использовать дополнительно, если метод есть в официальном API-архиве |
| Полный список имён (grep-индекс ~всего API) | `wiki-lua/INDEX-api.md` — ТОЛЬКО grep, не читать целиком |
| Концепции и best practices (taint, SavedVariables, TOC, якоря, меню, секреты) | тематические `wiki-lua/*.md` (см. ниже) |
| Инвентарь, аукцион, профессии — API соответствующих систем | `wiki-lua/blizzard_api_doc/` (C_Container, C_AuctionHouse, TradeSkill*) + `wiki-lua/pages/api/` |
| Развёрнутые страницы wiki по конкретным функциям (примеры, note'ы) | `wiki-lua/pages/api/API_*.md` — искать по имени файла |
| Краткие базовые гайды | тематические статьи в `wiki-lua/*.md` |

## Тематические файлы wiki-lua/ (выборочно)

- Старт: `01_addon_overview.md`, `02_create_addon_in_15_minutes.md`, `03_toc_format.md`
- Lua в WoW: `10_lua_overview.md`, `11_lua_variable_scoping.md`, `13_lua_functions.md`, `50_howto_intro_to_lua.md`, `51_howto_common_lua_shortcuts.md`
- События: `20_events.md` (полный список, большой — grep!), `55_howto_handling_events.md`, `74_combat_log_event.md`
- Виджеты/UI: `15_widget_api.md`, `16_widget_script_handlers.md`, `18_widget_anchors.md`, `21_frame.md`, `24_xml_user_interface.md`, `25_xml_reference.md`, `62_scriptobject_api.md`, `72_blizzard_menu_guide.md`, `67_howto_uidropdownmenu.md`, `65_howto_staticpopup.md`
- Taint / secure: `23_secure_execution_and_tainting.md`, `61_secret_values.md`, `84_restricted_environment.md`
- Сохранение: `04_saved_variables.md`, `56_howto_saving_variables.md`, `57_howto_creating_defaults.md`
- Хуки: `52_howto_hooking_functions.md`
- Изменения API: `41_api_change_summaries.md`, `80_api_changes_12.1.0.md`, `87_api_changes_12.0.1.md`
- Enum'ы: `82_enum_index.md`
- Политика Blizzard: `81_blizzard_addon_development_policy.md`
- Прочие how-to: префикс `NN_howto_*.md`, индекс — `40_howtos_index.md`

## ЖЁСТКИЕ ПРАВИЛА (экономия токенов)

1. **НЕ читать целиком файлы > 100 КБ.** Только `Grep`/`Select-String` с контекстом ≤ 20 строк.
   Чёрный список (частые ловушки): `wiki-lua/14_world_of_warcraft_api.md`, `wiki-lua/22_scripts.md`,
   `wiki-lua/34_console_variables.md`, `wiki-lua/20_events.md`, `wiki-lua/15_widget_api.md`,
   `wiki-lua/pages/api/Global functions.md`, `wiki-lua/pages/api/World of Warcraft API*.md`,
   `wiki-lua/80_api_changes_12.1.0.md`, `wiki-lua/INDEX-api.md`.
2. **Игнорировать:** `docs/wow_addons/` и `docs/wow_addons/*.html` (если появятся — мусор скрейпера),
    `__pycache__/`, `wiki-lua/batch*.json`, `wiki-lua/pages/progress.log`.
3. Для `C_*`, глобальных функций, событий, констант и Enum **всегда сначала
   `tools/find-api.ps1`**, а не ручной поиск по 612 файлам.
4. `wiki-lua/pages/api/` — вспомогательный и неполный архив; если функции там нет,
    это НЕ значит, что её нет в игре; источник истины — `wiki-lua/blizzard_api_doc/`.
5. Ответы по API сверять с patch/build: локальный архив соответствует Retail 12.1.0,
   build 69283. Для другого patch/build локальные документы недостаточны без отдельной проверки.
6. Новые методы фреймов/виджетов и script handlers проверять до написания кода.
   Midnight удаляет API без обратной совместимости (например, `SetMinResize`/
   `SetMaxResize` → `SetResizeBounds`), а lupa-стабы маскируют такие ошибки.
   Защищённый вызов должен иметь fallback или запись `WARN` в `Diag`; guard не
   должен молча скрывать поломку обязательного API.
7. CHANGELOG — только по версиям, одна сессия — одна версия.
   Старые `## [x.y.z]`-блоки append-only: не читать файл целиком, не переписывать
   и не переименовывать их. Поиск — через grep `^## `, чтение — только контекст
   ≤ 20 строк вокруг нужного заголовка.
   Каждая сессия, меняющая `addons/`, создаёт РОВНО ОДИН новый блок
   `## [X.Y.Z] - YYYY-MM-DD` сразу под шапкой (выше старых блоков, дата = день
   сессии); все user-facing изменения сессии — в него (`Added`/`Fixed`/`Changed`
   по Keep a Changelog). Второй версионный блок в той же сессии запрещён —
   правки дописывать в тот же блок.
   Пункты в `## [Unreleased]` не копить: если там висит чужой текст — туда НЕ
   дописывать, новый блок ставить выше него.
   Сессия без изменений в `addons/` (только доки/tools/wiki-lua) CHANGELOG не трогает.
8. Версия бампается в той же сессии, что и код (не откладывается в Unreleased).
   Источник — `.toc` (`## Version`); `Init.lua:VERSION` и новейший `## [x.y.z]`
   в CHANGELOG обязаны совпадать. Кодовую сессию начинать с
   `python tools/check_version.py`, заканчивать бампом во всех трёх местах
   (плюс `tools/tests/test_init.py` — там версия захардкожена дважды) и повторным
   `python tools/check_version.py` до ответа пользователю.
   Счёт `MAJOR.MINOR.PATCH`: MAJOR — несовместимые изменения,
   MINOR — новые возможности без поломки совместимости, PATCH — исправления.
   Дабл-бамп за сессию запрещён. Изменение `DB_SCHEMA`
   сопровождать описанием миграции и совместимости со старыми SavedVariables.
9. После правок выполнять минимально подходящие проверки: для Lua —
   `syntax_check.py`, для логики — `run_tests.py`, для локалей — `check_locales.py`,
   для версии — `check_version.py`. Новые WoW API, события, UI и аукцион требуют
   также ручного smoke-test в клиенте или явной отметки, что он не выполнен.
10. Не изменять несвязанные файлы, не откатывать существующие изменения, не запускать
    `wiki-lua/fetch_*.py`, не коммитить и не отправлять изменения без явного запроса пользователя.

## Поддерживающие скрипты

- `tools/find-api.ps1 <query> [-Max N]` — поиск функции/события/метода виджета: имя, файл:строка, аргументы, возврат (~500 токенов вместо тысяч).
- `tools/build-index.ps1` — перегенерировать `wiki-lua/INDEX-api.md` (после обновления blizzard_api_doc).
- `python tools/check_version.py` — проверить `.toc`, `Init.lua` и последний release CHANGELOG.
- `python tools/check_docs.py` — проверить дрейф доков: число `test_*.py` и их упоминания в PROJECT-INDEX, существование файлов `wiki-lua/*.md` и `tools/*`, на которые ссылаются AGENTS.md/PROJECT-INDEX.md.
- `wiki-lua/fetch_wiki.py`, `wiki-lua/fetch_pages.py`, `wiki-lua/fetch_blizzard_api_doc.py` — скачивание доков (нужен internet).
