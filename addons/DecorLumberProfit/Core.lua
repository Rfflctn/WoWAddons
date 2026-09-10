-- Core.lua | DecorLumberProfit | Retail 12.1.0
-- Слой совместимости (Этапы 3–6): тонкие :-врапперы над Services/*.
-- Вся логика живёт в Services/ItemInfo.lua, Services/Recipes.lua,
-- Services/Store.lua, Services/Economy.lua. Неймспейс — Init.lua.

DecorLumberProfitCore = {}
local Core = DecorLumberProfitCore

-- Данные и lookup древесины — в Data/Wood.lua (Этап 4). Врапперы для совместимости.
function Core:GetWoodIDs()
    local W = _G.DecorLumberProfitWood
    if W and W.IDs then return W.IDs() end
    return nil, nil
end
function Core:GetWoodID()
    local W = _G.DecorLumberProfitWood
    if W and W.DefaultID then return W.DefaultID() end
    return nil
end
function Core:IsWoodItem(itemID)
    local W = _G.DecorLumberProfitWood
    if W and W.IsWood then return W.IsWood(itemID) end
    return false
end

-- Bind/name кэши и tri-state живут в Services/ItemInfo.lua (Этап 3).
-- Локальный форвардер: остальной код Core не менялся.
local function OutputIsUnsellable(itemID)
    local M = _G.DecorLumberProfitItemInfo
    if M and M.IsUnsellable then return M.IsUnsellable(itemID) end
    return false
end

-- Хранилище pending живёт в ItemInfo (Этап 3); алиас таблицы для /dump-совместимости.
Core._pendingBind = (_G.DecorLumberProfitItemInfo and _G.DecorLumberProfitItemInfo._pending) or {}

-- Сервер сообщил, что данных о предмете нет (success=false) — сбрасываем ждущие по нему рецепты
function Core:FailPendingForItem(itemID)
    local M = _G.DecorLumberProfitItemInfo
    if M and M.FailPendingForItem then return M.FailPendingForItem(itemID) end
end

-- Вызывается из UI по GET_ITEM_INFO_RECEIVED: возвращает рецепты, ставшие known-продаваемыми
function Core:ResolvePendingBind()
    local M = _G.DecorLumberProfitItemInfo
    if M and M.ResolvePending then return M.ResolvePending() end
    return {}
end

-- Удаляет из списка рецепты с непродаваемой продукцией:
-- BoP (bind 1, "Становится персональным при получении") и Warband
-- (bind 8/9, "Привязывается к отряду") + прочие не из белого списка 0/2.
-- unsell==nil (данные ещё грузятся) оставляет, ждём ResolvePendingBind
function Core:PruneUnsellable(list)
    local M = _G.DecorLumberProfitItemInfo
    if M and M.PruneUnsellable then return M.PruneUnsellable(list) end
    return 0
end

-- Имена предметов кэширует ItemInfo (Этап 3).
local function GetItemName(itemID)
    local M = _G.DecorLumberProfitItemInfo
    if M and M.GetName then return M.GetName(itemID) end
    return nil
end

-- Схемы и реагенты — в Services/Recipes.lua (Этап 4).

-- Данные рецепта — в Services/Recipes.lua (Этап 4).
function Core:GetRecipeData(recipeSpellID)
    local R = _G.DecorLumberProfitRecipes
    if R and R.GetRecipeData then return R.GetRecipeData(recipeSpellID) end
    return nil
end

-- Перечисление кандидатов — в Services/Recipes.lua (Этап 4).

-- TryGetAllRecipeSpellIDs — в Services/Recipes.lua (Этап 4).

-- Активное окно профессии — состояние в Services/Recipes.lua (Этап 4).
function Core:SetActiveSkillLineID(skillLineID)
    local R = _G.DecorLumberProfitRecipes
    if R and R.SetActiveSkillLineID then return R.SetActiveSkillLineID(skillLineID) end
end

function Core:GetActiveSkillLineID()
    local R = _G.DecorLumberProfitRecipes
    if R and R.GetActiveSkillLineID then return R.GetActiveSkillLineID() end
    return nil
end

-- TryGetActiveRecipeSpellIDs — в Services/Recipes.lua (Этап 4).

-- Нормализация профессий — в Services/Recipes.lua (подвиды -> база). Тонкий враппер.
function Core:NormalizeProfessionName(name)
    local R = _G.DecorLumberProfitRecipes
    if R and R.NormalizeProfessionName then return R.NormalizeProfessionName(name) end
    return name
end

-- Диагностика активного окна — в Services/Recipes.lua (Этап 4). /dump-алиасы сохранены.
function Core:DebugActive()
    local R = _G.DecorLumberProfitRecipes
    if R and R.DebugActive then return R.DebugActive() end
    return {}
end

-- Прямой тест: /dump DecorLumberProfitCore:DebugSpell(123456)
function Core:DebugSpell(spellID)
    local R = _G.DecorLumberProfitRecipes
    if R and R.DebugSpell then return R.DebugSpell(spellID) end
    return { err = "recipes module missing", spellID = spellID }
end

-- Поиск — unified Recipes.Scan (Этап 4). Врапперы сохраняют коды ошибок.
function Core:FindWoodRecipesInActiveWindow()
    local R = _G.DecorLumberProfitRecipes
    if R and R.Scan then return R.Scan({ scope = "active" }) end
    return {}, "RECIPES_MODULE_MISSING"
end

function Core:ScanAndRememberCurrentProfession()
    local R = _G.DecorLumberProfitRecipes
    if R and R.ScanAndRememberCurrentProfession then return R.ScanAndRememberCurrentProfession() end
    return 0
end

function Core:FindWoodRecipes()
    local R = _G.DecorLumberProfitRecipes
    if R and R.Scan then return R.Scan({ scope = "all" }) end
    return {}, "RECIPES_MODULE_MISSING"
end

-- Экономика — в Services/Economy.lua (Этап 6, формула без изменений).
function Core:CalculateRecipeEconomy(recipeData, auctionPrices)
    local E = _G.DecorLumberProfitEconomy
    if E and E.CalculateRecipeEconomy then return E.CalculateRecipeEconomy(recipeData, auctionPrices) end
    return nil
end

-- knownRecipes — в Services/Store.lua (Этап 5).
function Core:RememberRecipe(recipeID, recipeLevel)
    local S = _G.DecorLumberProfitStore
    if S and S.RememberRecipe then return S.RememberRecipe(recipeID, recipeLevel) end
end

-- ==== Персистентность — в Services/Store.lua (Этап 5). Врапперы для совместимости. ====

function Core:SerializeRecipe(rec)
    local S = _G.DecorLumberProfitStore
    if S and S.SerializeRecipe then return S.SerializeRecipe(rec) end
    return nil
end

function Core:SaveRecipe(rec)
    local S = _G.DecorLumberProfitStore
    if S and S.SaveRecipe then return S.SaveRecipe(rec) end
    return nil
end

function Core:MarkLearnedBy(spellID)
    local S = _G.DecorLumberProfitStore
    if S and S.MarkLearnedBy then return S.MarkLearnedBy(spellID) end
end

function Core:LoadSavedRecipes()
    local S = _G.DecorLumberProfitStore
    if S and S.LoadSavedRecipes then return S.LoadSavedRecipes() end
    return {}
end

function Core:GetSavedRecipe(spellID)
    local S = _G.DecorLumberProfitStore
    if S and S.GetSavedRecipe then return S.GetSavedRecipe(spellID) end
    return nil
end

function Core:ClearSavedRecipes()
    local S = _G.DecorLumberProfitStore
    if S and S.ClearSavedRecipes then return S.ClearSavedRecipes() end
end

function Core:SavedRecipeCount()
    local S = _G.DecorLumberProfitStore
    if S and S.SavedRecipeCount then return S.SavedRecipeCount() end
    return 0
end

-- Число рецептов, ждущих догрузки данных предмета (для Diag). Этап 0.2, аддитивно.
function Core:GetPendingBindCount()
    local c = 0
    for _ in pairs(self._pendingBind or {}) do c = c + 1 end
    return c
end

-- Пересчитывает learned для загруженных рецептов по живому API (для текущего персонажа)
function Core:RefreshLearnedFlags(list)
    local S = _G.DecorLumberProfitStore
    if S and S.RefreshLearnedFlags then return S.RefreshLearnedFlags(list) end
end

function Core:GetItemName(itemID) return GetItemName(itemID) end
function Core:IsOutputUnsellable(itemID) return OutputIsUnsellable(itemID) end
