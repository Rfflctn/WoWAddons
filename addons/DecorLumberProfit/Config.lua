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
    QUERY_DELAY = 0.65, -- ~92 запроса/мин; лимит Blizzard 100/мин = 0.6с между запросами
    PRICE_TTL = 3600, -- свежесть цены 1 ч (SV-окно чтения x2 = 2 ч); было 900 — цены слетали между сессиями
    MAX_QUEUE = 500,   -- размер активной очереди; излишек копится в overflow и подгружается сам
}

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
        "C_TradeSkillUI.OpenTradeSkill(skillLineID) -> bool",
    },
    auction = {
        "C_AuctionHouse.MakeItemKey(itemID, itemLevel, itemSuffix, battlePetSpeciesID) -> ItemKey",
        "C_AuctionHouse.SendSearchQuery(itemKey, sorts, separateOwnerItems [,minLevel, maxLevel]) -- 100/мин throttle",
        "C_AuctionHouse.SendBrowseQuery(query)",
        "C_AuctionHouse.GetItemSearchResultsQuantity(itemKey) / GetItemSearchResultInfo",
        "C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID) / GetCommoditySearchResultInfo",
        "C_AuctionHouse.GetMaxItemSearchResultBuyout / GetMaxCommoditySearchResultPrice",
        "C_AuctionHouse.IsThrottledMessageSystemReady() -> bool",
        "C_Item.GetItemInfo(itemInfo)",
        "C_CurrencyInfo.GetCoinTextureString(money, fontHeight)",
    },
    events = {
        "TRADE_SKILL_LIST_UPDATE / TRADE_SKILL_DATA_SOURCE_CHANGED",
        "COMMODITY_SEARCH_RESULTS_UPDATED / ITEM_SEARCH_RESULTS_UPDATED",
        "COMMODITY_SEARCH_RESULTS_RECEIVED / ITEM_SEARCH_RESULTS_ADDED",
        "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED / THROTTLED_SYSTEM_READY",
        "ADDON_LOADED / PLAYER_LOGIN",
    },
}

_G.DecorLumberProfitConfig = DecorLumberProfitConfig