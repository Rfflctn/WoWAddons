-- Data/Wood.lua | DecorLumberProfit | Retail 12.1.0 Midnight
-- Владелец данных древесины (Этап 2): ID, set для lookup, варианты названий.
-- Грузится ДО Config.lua. Наполняет DecorLumberProfitConfig.WOOD_* для
-- обратной совместимости (Core читает Config) + публикует DecorLumberProfitWood.
-- No WoW calls at top level. Только древесина (обобщение под руду/травы — позже).

DecorLumberProfitConfig = DecorLumberProfitConfig or {}

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

-- Канонический неймспейс данных (те же таблицы, без копий).
DecorLumberProfitWood = {
    IDS = DecorLumberProfitConfig.WOOD_ITEM_IDS,
    SET = DecorLumberProfitConfig.WOOD_IDS_SET,
    NAMES = DecorLumberProfitConfig.WOOD_NAMES,
    DEFAULT_ID = DecorLumberProfitConfig.WOOD_ITEM_ID,
}

-- Функции доступа (Этап 4): с фолбэком на Config, если Wood загружен частично.
function DecorLumberProfitWood.IDs()
    if DecorLumberProfitWood.IDS and #DecorLumberProfitWood.IDS > 0 then
        return DecorLumberProfitWood.IDS, DecorLumberProfitWood.SET
    end
    local cfg = _G.DecorLumberProfitConfig
    if cfg and cfg.WOOD_ITEM_IDS and #cfg.WOOD_ITEM_IDS > 0 then
        return cfg.WOOD_ITEM_IDS, cfg.WOOD_IDS_SET
    end
    return nil, nil
end

function DecorLumberProfitWood.IsWood(itemID)
    if type(itemID) ~= "number" then return false end
    local _, set = DecorLumberProfitWood.IDs()
    return set and set[itemID] or false
end

function DecorLumberProfitWood.Names()
    if DecorLumberProfitWood.NAMES and #DecorLumberProfitWood.NAMES > 0 then
        return DecorLumberProfitWood.NAMES
    end
    local cfg = _G.DecorLumberProfitConfig
    if cfg and cfg.WOOD_NAMES and #cfg.WOOD_NAMES > 0 then return cfg.WOOD_NAMES end
    return { "Талассийская древесина" }
end

function DecorLumberProfitWood.DefaultID()
    return DecorLumberProfitWood.DEFAULT_ID
end

_G.DecorLumberProfitConfig = DecorLumberProfitConfig
_G.DecorLumberProfitWood = DecorLumberProfitWood
