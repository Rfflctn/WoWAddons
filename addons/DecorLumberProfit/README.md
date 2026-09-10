# DecorLumberProfit — калькулятор рентабельности Талассийской древесины

Retail 12.1.0 / Midnight. Аддон считает, выгодно ли крафтить предметы, требующие **«Талассийская древесина»**, исходя из актуальных цен аукциона.

## Возможности (по ТЗ)

1. Находит все доступные персонажу рецепты, где используется Талассийская древесина.
2. Для каждого рецепта: название и кол-во создаваемого предмета, кол-во древесины, список остальных реагентов.
3. Получает с аукциона цены реагентов (`C_AuctionHouse.SendSearchQuery` + `GetCommoditySearchResultInfo` / `GetItemSearchResultInfo`).
4. Считает себестоимость: `sum(цена реагента × кол-во)`.
5. Берёт цену готового предмета с аукциона.
6. Считает **макс. допустимую цену древесины**: `(цена_предмета − стоимость_остальных_реагентов) / кол_древесины` с учётом `quantityMin` (если рецепт даёт N предметов — умножает цену).
7. Таблица: рецепт | предмет | цена продажи | себестоимость | кол-во древесины | текущая цена древесины | макс. цена | прибыль | статус (Выгодно/Убыток).
8. Кнопка ручного обновления, сообщения: «нет на аукционе», «цена неизвестна», «рецепт недоступен», «аукцион не просканирован».
9. Только разрешённые API, учтён throttle 100 запросов/мин.
10. TOC + Lua + документация, без Lua-ошибок при отсутствии данных.

## Установка

1. Скопируйте папку `DecorLumberProfit` в `World of Warcraft\_retail_\Interface\AddOns\`
2. Проверьте что путь выглядит как `...\AddOns\DecorLumberProfit\DecorLumberProfit.toc`
3. В игре: Esc → Модификации → включите аддон → Перезагрузка (`/reload`)

## Использование

```
/dlp             — открыть/закрыть окно
/dlp help        — справка
/dlp reset       — сбросить кэш цен
/dlp scan        — добавить рецепты из активного окна
/dlp locale ru   — переключить язык на русский (после /reload)
/dlp locale en   — переключить язык на английский (после /reload)
/dlp locale auto — язык по локали клиента (по умолчанию)
/lp, /twc, /thalwood — легаси-алиасы (остались от старых имён)
/древесина      — алиас RU
/dlp debug      — статус подсистем (где сломалось — видно за 5 секунд)
/dlp debug selftest — встроенные проверки без аукциона и профессий
/dlp bug        — блок для копипасты в issue
```

1. Откройте окно профессии (любой) — аддон кэширует рецепты.
2. Введите `/dlp` → «Обновить рецепты» — найдёт рецепты с древесиной.
3. У аукциона нажмите «Обновить цены» — запросит цены (соблюдает лимит Blizzard, показывает прогресс).
4. Наведите на строку — тултип со списком реагентов и их ценами.
5. Галочка «Скрыть неизученное» (справа сверху) — скрывает рецепты, не изученные ни на одном персонаже аккаунта (учитывается общая база `learnedBy`); настройка сохраняется между сессиями. Режим «Топ выгода» фильтрует так же.

## Отслеживаемая древесина (12 типов)

Список задаётся в `Config.lua` массивом `DecorLumberProfitConfig.WOOD_ITEM_IDS` (и set-дублем `WOOD_IDS_SET`):

```lua
DecorLumberProfitConfig.WOOD_ITEM_IDS = {
    245586, -- Ironwood (Древесина железного дерева)
    242691, -- Olemba (Олембовая древесина)
    251762, -- Coldwind (Морозная древесина)
    251764, -- Ashwood (Ясеневая древесина)
    251763, -- Bamboo (Бамбуковая древесина)
    251766, -- Shadowmoon (Призрачнолунная древесина)
    251767, -- Fel-Touched (Оскверненная древесина)
    251768, -- Darkpine (Темнососновая древесина)
    251772, -- Arden (Арденвельдская древесина)
    251773, -- Dragonpine (Древесина драконьих сосен)
    248012, -- Dornic Fir (Древесина дорнской ели)
    256963, -- Thalassian (Талассийская древесина)
}
```

ID можно перепроверить через `GetItemInfo(ссылка на предмет)` или:
```
/dump C_Item.GetItemInfoInstant("Thalassian Lumber")
```

При появлении новых видов древесины добавьте itemID в массив и варианты названий (ru/en) в `WOOD_NAMES` — они используются как fallback-поиск по имени.

## Как считается

```
otherCost = sum(цена_реагента × кол-во) для всех кроме древесины
totalCost = otherCost + (цена_древесины × кол_древесины)
outputTotal = цена_предмета_за_шт × quantityMin
maxWoodPrice = (outputTotal - otherCost) / woodQty
profit = outputTotal - totalCost
```
Если `woodQty` вариативен — берётся `quantityRequired` из `CraftingRecipeSchematic.reagentSlotSchematics`.

## Ограничения WoW API (честно)

| Требование | Реальность Retail 12.1.0 | Решение аддона |
|---|---|---|
| Перечислить все рецепты персонажа | В `TradeSkillUIDocumentation.lua` **нет** `GetFilteredRecipeIDs`/`GetCategoryIDs` — полный перебор не задокументирован. `GetAllProfessionTradeSkillLines` + `GetRecipeInfo/Schematic` дают только прямой доступ по ID. | Аддон использует `GetAllProfessionTradeSkillLines` + перебор через `GetProfessionSpells` (если доступен) и **кэш** `DecorLumberProfitDB.knownRecipes` пополняемый по событию `NEW_RECIPE_LEARNED` + `TRADE_SKILL_LIST_UPDATE`. Если список пуст — показывает инструкцию открыть профессии. Не выдумывает рецепты. |
| Цены аукциона | Нет единого `GetReagentPrice`. Только поштучные `SendSearchQuery` → `GetCommoditySearchResultInfo`/`GetItemSearchResultInfo` с throttle 100/мин и требованием `IsThrottledMessageSystemReady`. Полный скан АХ возможен только через `ReplicateItems` (весь аукцион одним вызовом) — для набора предметов аддона избыточен. | Очередь с `QUERY_DELAY 0.65s` (упор в лимит 100/мин), обработка событий `COMMODITY_SEARCH_RESULTS_UPDATED`/`ITEM_SEARCH_RESULTS_UPDATED`, TTL кэша 15 мин, fallback к `GetBrowseResults` через O(1)-индекс. Древесина на АХ не ищется (не продаётся; только кэш для колонки «цена др.»). Честно показывает «нет на АХ» / «цена неизвестна». |
| Событие завершения сканирования | Нет `AUCTION_SCAN_COMPLETE`. | Слушаем `COMMODITY_SEARCH_RESULTS_UPDATED`, `ITEM_SEARCH_RESULTS_UPDATED`, `AUCTION_HOUSE_THROTTLED_SYSTEM_READY` и считаем очередь завершённой когда `queue==0`. |
| Защищённые API | `C_AuctionHouse.StartCommoditiesPurchase` помечен `HasRestrictions=true` — не используем. | Используем только `AllowedWhenUntainted` функции. |

Полный список проверенных API см. `Config.lua:API_CHECKLIST`.

## Файлы

- `DecorLumberProfit.toc` — метаданные, `Interface: 120100`, `SavedVariables`, порядок загрузки (Locales → Init → Data/Wood → Config → Services/* → Util/Money → Core → UI/* → Diag)
- `Locales.lua` — все тексты аддона (`DecorLumberProfitLocale.enUS` / `.ruRU`); доступ через `L["KEY"]` и `TL("KEY", ...)`, ключ `auto`/ru/en в `DecorLumberProfitDB.settings.locale`
- `Init.lua` — неймспейс `DecorLumberProfit`: `VERSION`, `DB_SCHEMA`, `SafeCall`/`CountTable`/`Log`
- `Data/Wood.lua` — владелец данных древесины (12 ID + set + имена); наполняет `Config.WOOD_*`
- `Config.lua` — тюнинг AUCTION/UI/SCAN + `API_CHECKLIST`
- `Services/ItemInfo.lua` — кэш имён/bindType (tri-state), отложенные рецепты, `PruneUnsellable`
- `Services/Recipes.lua` — перечисление рецептов, схемы, unified `Scan({scope})`, `DebugActive/DebugSpell`
- `Services/Store.lua` — персистентность (`Upgrade`, `SaveRecipe` с `savedAt/updatedAt`, `EnforceCap` 1000)
- `Services/Economy.lua` — чистая формула `CalculateRecipeEconomy` (не менять!)
- `Util/Money.lua` — `FormatMoney` (золото/серебро/медь с иконками)
- `Services/Prices.lua` — очередь аукциона (`C_AuctionHouse.*`, события throttle, батч-таймер, coalesce UI-обновлений, `GetQueueInfo`); `DecorLumberProfitAuction` — legacy-алиас
- `Core.lua` — только тонкие `:`-врапперы над Services/* (для совместимости `/dump` и UI)
- `UI.lua` — неймспейс + общее состояние таблицы (`UI._x`)
- `UI/TableView.lua` — колонки, сортировка, пул строк с виртуализацией (`VisibleRange`), `RefreshTable`
- `UI/MainFrame.lua` — окно (ресайз с перераскладкой колонок, health-dot, шапка, скролл)
- `UI/Actions.lua` — скан, загрузка из DB, цены, очистка
- `UI/Commands.lua` — slash `/dlp` и события клиента
- `UI/Status.lua` — статус-строка (+health-dot), `UI/Tooltip.lua` — тултипы строк (item-ссылки), `UI/Popups.lua` — StaticPopup
- `Services/Diag.lua` — диагностика: `Diag.Log`, `lastError`, `/dlp debug status|selftest|verbose`, `/dlp bug`
- `README.md` — эта документация

## Отладка

- `/dlp debug` — статус подсистем, `/dlp debug selftest` — проверки в игре, `/dlp bug` — бандл для issue
- `/dump DecorLumberProfitDB` — кэш цен и известных рецептов
- `/dump DecorLumberProfitCore:FindWoodRecipes()` — ручной тест поиска
- Если таблица пуста — откройте книгу профессий, изучите хотя бы один рецепт с древесиной, перезапустите скан.

## API, которые нельзя протестировать без игры

- `C_TradeSkillUI.GetAllProfessionTradeSkillLines / GetRecipeSchematic / GetRecipeInfo` — требует залогиненного персонажа с профессиями.
- `C_AuctionHouse.SendSearchQuery / MakeItemKey / GetCommoditySearchResultInfo` — требует активного аукциона и реальных лотов.
- События `NEW_RECIPE_LEARNED`, `TRADE_SKILL_LIST_UPDATE`, `COMMODITY_SEARCH_RESULTS_UPDATED` — только в клиенте.
- `C_Item.GetItemInfo` для Midnight-предметов — данные появляются только с клиентом 12.1.0.

Проверка синтаксиса без клиента: `luac -p *.lua` (в репо) — ошибок нет.

## Лицензия

MIT — делайте что хотите, но указывайте авторство.
