# AGENTS.md — маршрутизация для AI-агентов

> **Старт за 1 минуту:** сначала прочитай `PROJECT-INDEX.md` (карта: где код, где доки, куда идти по типу задачи),
> затем этот файл (правила и детали маршрутизации). `PROJECT-INDEX.md` — обзор, этот файл — источник истины при расхождениях.

Проект: база знаний по разработке WoW-аддонов (Retail, патч 12.1.0 / Midnight)
+ код аддона в `addons/DecorLumberProfit/` (TOC + 20×Lua: Init, Config, Core, UI, Locales + Data/Wood + Services/ItemInfo, Recipes, Store, Economy, Prices, Diag + Util/Money + UI/Status, Tooltip, TableView, Actions, MainFrame, Popups, Commands; `DecorLumberProfitAuction` — legacy-алиас Prices).

## Карта источников (по убыванию приоритета)

| Задача | Куда идти |
|---|---|
| Сигнатура API-функции, события, константы (`C_*`, `Get*`, `Unit*`, методы виджетов) | **`tools/find-api.ps1 <имя>`** — точное имя, аргументы, возврат (из `wiki-lua/blizzard_api_doc/`) |
| Полный список имён (grep-индекс ~всего API) | `wiki-lua/INDEX-api.md` — ТОЛЬКО grep, не читать целиком |
| Как-то, концепции, best practices (taint, SavedVariables, TOC, якоря, меню, секреты) | тематические `wiki-lua/*.md` (см. ниже) |
| Инвентарь, аукцион, профессии — API соответствующих систем | `wiki-lua/blizzard_api_doc/` (C_Container, C_AuctionHouse, TradeSkill*) + `wiki-lua/pages/api/` |
| Развёрнутые страницы wiki по конкретным функциям (примеры, note'ы) | `wiki-lua/pages/api/API_*.md` — искать по имени файла |
| Краткие базовые гайды (33 файла, компактные) | `docs/wow_addons/*.md` |

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

1. **НЕ читать целиком файлы > 100 КБ.** Только grep/Select-String с контекстом ≤ 20 строк.
   Чёрный список (частые ловушки): `wiki-lua/14_world_of_warcraft_api.md`, `wiki-lua/22_scripts.md`,
   `wiki-lua/34_console_variables.md`, `wiki-lua/20_events.md`, `wiki-lua/15_widget_api.md`,
   `wiki-lua/pages/api/Global functions.md`, `wiki-lua/pages/api/World of Warcraft API*.md`,
   `wiki-lua/80_api_changes_12.1.0.md`, `wiki-lua/INDEX-api.md`.
2. **Игнорировать:** `docs/wow_addons/*.html` (мусор скрейпера, все по 580 КБ),
   `__pycache__/`, `wiki-lua/batch*.json`, `wiki-lua/pages/progress.log`.
3. Для поиска API **всегда сначала `tools/find-api.ps1`**, а не ручной grep по 612 файлам.
4. `wiki-lua/pages/api/` неполон (скрейп оборвался на ~125/6198) — если функции там нет,
   это НЕ значит, что её нет в игре; источник истины — `wiki-lua/blizzard_api_doc/`.
5. Ответы по API сверять с `Environment`/патчем: документы соответствуют Retail 12.1.0.
6. Новые методы фреймов/виджетов (`Frame:*`, `GameTooltip:*`, скрипт-хендлеры) — ТОЛЬКО после проверки существования: `C_*` через `tools/find-api.ps1`, виджеты — grep по `wiki-lua/15_widget_api.md` / `16_widget_script_handlers.md`. Midnight удаляет API без обратной совместимости (прецедент 2.0.0: `SetMinResize`/`SetMaxResize` → `SetResizeBounds`; lupa-стабы маскируют такие баги — любой метод существует в тестах). Критичные вызовы при создании окна — за гардами (`if f.Method then`), чтобы окно открывалось при любых изменениях API.

## Поддерживающие скрипты

- `tools/find-api.ps1 <query> [-Max N]` — поиск функции/события/метода виджета: имя, файл:строка, аргументы, возврат (~500 токенов вместо тысяч).
- `tools/build-index.ps1` — перегенерировать `wiki-lua/INDEX-api.md` (после обновления blizzard_api_doc).
- `wiki-lua/fetch_wiki.py`, `wiki-lua/fetch_pages.py`, `wiki-lua/fetch_blizzard_api_doc.py` — скачивание доков (нужен internet).
