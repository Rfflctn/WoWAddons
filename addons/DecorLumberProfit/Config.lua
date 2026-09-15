-- Config.lua | DecorLumberProfit | Retail 12.1.0 Midnight
-- Тюнинг аддона (аукцион/UI). Данные древесины — в Data/Wood.lua (грузится раньше).
-- НЕ пересоздавать таблицу: Wood.lua уже наполнил WOOD_* поля.

DecorLumberProfitConfig = DecorLumberProfitConfig or {}

-- Настройки сканирования рецептов
DecorLumberProfitConfig.SCAN = {
    ENABLE_BRUTEFORCE = true, -- перебор professionID как последний шанс (Recipes.TryGetAll / fallback TryGetActive)
    MAX_RESULTS = 500,        -- кап результатов Scan (меняется через /dlp debug set maxscan)
}

-- Настройки аукциона
DecorLumberProfitConfig.AUCTION = {
    QUERY_DELAY = 0.62, -- ~96 запросов/мин; лимит Blizzard 100/мин = 0.6с между запросами
    PRICE_TTL = 3600, -- свежесть цены 1 ч: гейтит только рескан; последняя известная
    -- цена (включая lastPrice при пустом АХ) хранится в SV до ручного сброса
    MAX_QUEUE = 500,   -- размер активной очереди; излишек копится в overflow и подгружается сам
    -- Быстрый предварительный browse-скан по категориям: пока идёт точный точечный
    -- скан, таблица сразу получает приблизительную минимальную цену (пометка "~").
    -- Значения только в памяти и не считаются свежим кэшем.
    PREVIEW_ENABLED = true,
    PREVIEW_CLASSES = { 5, 7, 20 }, -- Enum.ItemClass: Reagent, Tradegoods, Housing
    -- Источник цен: "auto" (Auctionator при наличии, иначе свой скан),
    -- "native" (только свой C_AuctionHouse-скан), "auctionator" (только Auctionator).
    -- Дефолт auto: без Auctionator поведение 1:1 как раньше. Персист —
    -- DB.settings.priceSource (переживает /reload, применяется в Store.Upgrade).
    PRICE_SOURCE = "auto",
}

-- Мультиреалм-гейт: весь кросс-реалмовый ПОКАЗ (блок «данные по серверам»
-- в тултипе, fallback "*" в колонках «На АХ»/«Мои», любые цены/количества
-- с чужих реалмов) — только при /dlp multirealm on.
-- По умолчанию выключен (версия для масс — один мир); включается командой
-- /dlp multirealm on (персист в DB.settings.multiRealm, переживает /reload).
-- Сбор и хранение realm-scoped данных при этом не останавливаются — гейтится
-- только отображение, поэтому включение сразу показывает накопленную историю.
DecorLumberProfitConfig.MULTI_REALM = false

-- Настройки UI
DecorLumberProfitConfig.UI = {
    WIDTH  = 950,
    HEIGHT = 550,
    ROW_HEIGHT = 20,
    MAX_ROWS = 50,
}

-- Справочник API
DecorLumberProfitConfig.API_CHECKLIST = {
    professions = {
        "C_TradeSkillUI.GetAllProfessionTradeSkillLines() -> table<number> skillLineIDs",
        "C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLineID) -> ProfessionInfo",
        "C_TradeSkillUI.GetRecipeInfo(recipeSpellID [,recipeLevel]) -> ?TradeSkillRecipeInfo",
        "C_TradeSkillUI.GetRecipeSchematic(recipeSpellID, isRecraft [,recipeLevel]) -> CraftingRecipeSchematic",
        "C_TradeSkillUI.GetRecipeOutputItemData(recipeSpellID) -> CraftingRecipeOutputInfo",
        "C_TradeSkillUI.OpenTradeSkill(skillLineID) -> bool -- принимает КЛАССИЧЕСКИЙ ID профы (164/165/171...), expansion-варианты (напр. 2907) возвращают false",
        "C_TradeSkillUI.GetProfessionSkillLineID(professionEnum) -> skillLineID -- точный ID текущей ветки для OpenTradeSkill",
        "C_TradeSkillUI.OpenRecipe(recipeID) -- запасной путь: открывает окно профы на рецепте",
    },
    auction = {
        "C_AuctionHouse.MakeItemKey(itemID, itemLevel, itemSuffix, battlePetSpeciesID) -> ItemKey",
        "C_AuctionHouse.SendSearchQuery(itemKey, sorts, separateOwnerItems [,minLevel, maxLevel]) -- 100/мин throttle",
        "C_AuctionHouse.SendBrowseQuery(query) -- query.itemClassFilters = {{classID = Enum.ItemClass.Reagent/Tradegoods/Housing}}",
        "Enum.AuctionHouseSortOrder.Price / AuctionHouseSortType{sortOrder, reverseSort}",
        "C_AuctionHouse.GetItemSearchResultsQuantity(itemKey) / GetItemSearchResultInfo",
        "C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID) / GetCommoditySearchResultInfo",
        "C_AuctionHouse.GetMaxItemSearchResultBuyout / GetMaxCommoditySearchResultPrice",
        "C_AuctionHouse.GetOwnedAuctions() -> table<OwnedAuctionInfo>",
        "C_AuctionHouse.GetNumOwnedAuctions() / GetOwnedAuctionInfo(index) -- fallback",
        "C_AuctionHouse.IsThrottledMessageSystemReady() -> bool",
        "Auctionator.API.v1.GetAuctionPriceByItemID(itemID) -> copper|nil -- optional external source",
        "C_Item.GetItemInfo(itemInfo)",
        "C_CurrencyInfo.GetCoinTextureString(money, fontHeight)",
    },
    realm = {
        "GetNormalizedRealmName() -> cstring",
        "GetRealmName() -> cstring",
    },
    events = {
        "TRADE_SKILL_LIST_UPDATE / TRADE_SKILL_DATA_SOURCE_CHANGED",
        "COMMODITY_SEARCH_RESULTS_UPDATED / ITEM_SEARCH_RESULTS_UPDATED",
        "COMMODITY_SEARCH_RESULTS_RECEIVED / ITEM_SEARCH_RESULTS_ADDED",
        "OWNED_AUCTIONS_UPDATED / AUCTION_HOUSE_SHOW",
        "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED / THROTTLED_SYSTEM_READY",
        "ADDON_LOADED / PLAYER_LOGIN",
    },
}

_G.DecorLumberProfitConfig = DecorLumberProfitConfig
