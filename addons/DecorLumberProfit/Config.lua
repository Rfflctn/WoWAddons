-- Config.lua | DecorLumberProfit | Retail 12.1.0 Midnight
-- Центральная конфигурация, itemID и константы.

local ADDON_NAME = "DecorLumberProfit"

DecorLumberProfitConfig = {}

DecorLumberProfitConfig.WOOD_ITEM_IDS = {
    245586, -- Ironwood (Древесина железного дерева, Kalimdor/Eastern Kingdoms)
    242691, -- Olemba (Олембовая древесина, Outland)
    251762, -- Coldwind (Морозная древесина, Northrend)
    251764, -- Ashwood (Ясеневая древесина, Cataclysm)
    251763, -- Bamboo (Бамбуковая древесина, Pandaria)
    251766, -- Shadowmoon (Призрачнолунная древесина, Draenor)
    251767, -- Fel-Touched (Оскверненная древесина, Legion/Broken Isles+Argus)
    251768, -- Darkpine (Темнососновая древесина, BfA Zuldazar/Kul Tiras)
    251772, -- Arden (Арденвельдская древесина, Shadowlands)
    251773, -- Dragonpine (Древесина драконьих сосен, Dragon Isles)
    248012, -- Dornic Fir (Древесина дорнской ели, Khaz Algar)
    256963, -- Thalassian (Талассийская древесина, Quel'Thalas/Harandar)
}

-- Set для быстрого lookup: WOOD_IDS_SET[itemID]=true
DecorLumberProfitConfig.WOOD_IDS_SET = {}
for _, id in ipairs(DecorLumberProfitConfig.WOOD_ITEM_IDS) do
    DecorLumberProfitConfig.WOOD_IDS_SET[id] = true
end
-- обратная совместимость: WOOD_ITEM_ID уже как set
DecorLumberProfitConfig.WOOD_ITEM_ID = DecorLumberProfitConfig.WOOD_ITEM_ID or 256963 -- Thalassian (главная древесина по умолчанию)
DecorLumberProfitConfig.WOOD_IDS_SET[DecorLumberProfitConfig.WOOD_ITEM_ID] = true

-- Варианты названий для поиска (ruRU / enUS). Используются как fallback по имени.
DecorLumberProfitConfig.WOOD_NAMES = {
    -- Thalassian
    "Талассийская древесина",
    "Thalassian Lumber",
    -- Ironwood
    "Древесина железного дерева",
    "Ironwood Lumber",
    -- Olemba
    "Олембовая древесина",
    "Olemba Lumber",
    -- Coldwind / Морозная
    "Морозная древесина",
    "Coldwind Lumber",
    -- Ashwood / Ясеневая
    "Ясеневая древесина",
    "Ashwood Lumber",
    -- Bamboo
    "Бамбуковая древесина",
    "Bamboo Lumber",
    -- Shadowmoon / Призрачнолунная
    "Призрачнолунная древесина",
    "Shadowmoon Lumber",
    -- Fel-Touched / Оскверненная
    "Оскверненная древесина",
    "Fel-Touched Lumber",
    -- Darkpine / Темнососновая
    "Темнососновая древесина",
    "Darkpine Lumber",
    -- Arden
    "Арденвельдская древесина",
    "Arden Lumber",
    -- Dragonpine
    "Древесина драконьих сосен",
    "Dragonpine Lumber",
    -- Dornic Fir
    "Древесина дорнской ели",
    "Dornic Fir Lumber",
}

-- Настройки аукциона
DecorLumberProfitConfig.AUCTION = {
    QUERY_DELAY = 0.8, -- ~75 запросов/мин, запас под лимит Blizzard 100/мин
    PRICE_TTL = 900,
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