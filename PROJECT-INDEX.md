# PROJECT-INDEX.md — быстрый ориентир для агентов (читать ПЕРВЫМ, ~1 мин)

> Источник истины по маршрутизации — `AGENTS.md`. Этот файл — только карта.
> Патч: Retail 12.1.0 / Midnight. Обновлено: 2026-09-09.
> **Правило слоёв:** §0–§2 — читать всегда. §3 (`wiki-lua/`) — ТОЛЬКО если задача прошла гейт ниже.

## 0. Дерево (корень `W:\Projects\WoW Addons\`)

```
AGENTS.md                  # маршрутизация и жёсткие правила (читать вторым)
PROJECT-INDEX.md           # этот файл
opencode.json              # конфиг модели (lmstudio, локалка)
addons/DecorLumberProfit/   # ЕДИНСТВЕННЫЙ аддон с кодом (TOC + 5×Lua)
tools/                     # 5 скриптов: поиск API, проверки, тесты
wiki-lua/                  # архив доков (~8 тыс. файлов) — СМ. ГЕЙТ В §1, по умолчанию НЕ трогать
```

## 1. Гейт: нужна ли wiki-lua? (ответь за 5 секунд)

- **НЕ нужна (типично):** чистый Lua, вёрстка UI, локали, формулы экономики, рефакторинг без новых API, правки `Config/Locales/UI/Auction/Core` по уже известным сигнатурам → работай только в `addons/` + `tools/`, §3 не открывай.
- **Нужна:** новая функция `C_*`/`Get*`/`Unit*`, новое событие, метод виджета, taint/secure-вопрос, поле TOC, поведение патча → иди в §3, детали — в `AGENTS.md`.

## 2. Ядро (всегда достаточно для кодовых задач)

- `addons/DecorLumberProfit/DecorLumberProfit.toc` — метаданные (`Interface: 120100`), порядок загрузки Lua.
- `addons/DecorLumberProfit/Config.lua` — константы, 12 ID древесины, `API_CHECKLIST` (какие API уже проверены — сверяйся до похода в доки).
- `addons/DecorLumberProfit/Core.lua` — поиск рецептов с древесиной + расчёт экономики.
- `addons/DecorLumberProfit/Auction.lua` — очередь `C_AuctionHouse.SendSearchQuery`, кэш цен (TTL 15 мин).
- `addons/DecorLumberProfit/UI.lua` — окно, таблица, тултипы.
- `addons/DecorLumberProfit/Locales.lua` — тексты `enUS`/`ruRU` (`L[]`/`TL()`).
- `addons/DecorLumberProfit/README.md` — ТЗ, формулы, установка.
- Проверки после правок Lua: `python tools/syntax_check.py` → `python tools/smoke_test.py` → `python tools/check_locales.py`.
- Пути относительные от корня; абсолютных `W:\...` быть не должно. Имя папки аддона = имени `.toc`.

## 3. wiki-lua/ — ON-DEMAND (читать раздел ТОЛЬКО при гейте «нужна»)

Состав (замерено): `*.md` (69) — статьи/how-to; `blizzard_api_doc/` (612×.lua) — официальные доки клиента;
`INDEX-api.md` (~9900 записей) — grep-индекс; `pages/api/` (6197×.md) — примеры; `pages/events/` (2054×.md).

| Нужно | Действие (не читать файлы целиком!) |
|---|---|
| Сигнатура `C_*` / событие / метод виджета | `powershell -File tools/find-api.ps1 "<Имя>"` — ЕДИНСТВЕННЫЙ вход, не грепать 612 файлов вручную |
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
