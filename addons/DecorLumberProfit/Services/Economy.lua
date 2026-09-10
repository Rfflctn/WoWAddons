-- Services/Economy.lua | DecorLumberProfit | Retail 12.1.0
-- Расчёт экономики рецепта (Этап 6): чистый переезд формулы из Core БЕЗ изменений.
-- Чистая функция (recipeData, priceMap) -> eco. Формулы НЕ менять (решение ПРИНЯТО).
-- Все функции — через точку (без self). Core держит тонкий :-враппер.
-- WoW Lua 5.1: no goto, no //, no bitwise ops. No WoW calls at top level.

DecorLumberProfitEconomy = {}
local Economy = DecorLumberProfitEconomy

local function GetWoodIDs()
    local W = _G.DecorLumberProfitWood
    if W and W.IDs then return W.IDs() end
    local cfg = _G.DecorLumberProfitConfig
    if cfg then return cfg.WOOD_ITEM_IDS, cfg.WOOD_IDS_SET end
    return nil, nil
end

function Economy.CalculateRecipeEconomy(recipeData, auctionPrices)
    auctionPrices = auctionPrices or {}
    local woodQty = recipeData.woodQty or 0
    local outputQty = recipeData.outputQty or recipeData.outputMin or 1
    if outputQty <=0 then outputQty = 1 end
    local otherCost = 0
    local totalCost = 0
    local woodCost = 0
    local missingReagents = {}
    local hasUnknownPrice = false
    for _, r in ipairs(recipeData.reagents) do
        local itemID = r.itemID
        if type(itemID) == "string" and itemID:find("^currency:") then
            hasUnknownPrice = true
            table.insert(missingReagents, itemID)
        else
            local unitPrice = auctionPrices[itemID]
            if unitPrice == nil then
                hasUnknownPrice = true
                table.insert(missingReagents, itemID)
                unitPrice = 0
            end
            local cost = unitPrice * r.quantity
            totalCost = totalCost + cost
            if r.isWood then
                woodCost = woodCost + cost
            else
                otherCost = otherCost + cost
            end
        end
    end
    local outputItemID = recipeData.outputItemID
    local outputUnitPrice = outputItemID and auctionPrices[outputItemID] or nil
    local outputTotalPrice = nil
    if outputUnitPrice then
        outputTotalPrice = outputUnitPrice * outputQty
    else
        hasUnknownPrice = true
    end
    local woodItemID = recipeData.woodItemID
    local woodPrice = nil
    if woodItemID and auctionPrices[woodItemID] then
        woodPrice = auctionPrices[woodItemID]
    elseif woodQty > 0 then
        local ids = GetWoodIDs()
        for _, wid in ipairs(ids or {}) do
            if auctionPrices[wid] then woodPrice = auctionPrices[wid]; break end
        end
    end
    local maxWoodPrice = nil
    local profit = nil
    if outputTotalPrice and woodQty > 0 then
        maxWoodPrice = (outputTotalPrice - otherCost) / woodQty
        profit = outputTotalPrice - totalCost
    end
    return {
        outputQty = outputQty,
        outputUnitPrice = outputUnitPrice,
        outputTotalPrice = outputTotalPrice,
        otherCost = otherCost,
        totalCost = totalCost,
        woodCost = woodCost,
        woodQty = woodQty,
        woodItemID = woodItemID,
        woodPrice = woodPrice,
        maxWoodPrice = maxWoodPrice,
        profit = profit,
        profitPerOutput = profit and (profit / outputQty) or nil,
        hasUnknownPrice = hasUnknownPrice,
        missingReagents = missingReagents,
        status = (function()
            if outputUnitPrice == nil then return "NO_OUTPUT_PRICE" end
            if hasUnknownPrice and totalCost==0 then return "NO_REAGENT_PRICES" end
            if maxWoodPrice == nil then return "UNKNOWN" end
            if profit and profit > 0 then return "PROFITABLE" end
            if profit and profit == 0 then return "BREAKEVEN" end
            return "UNPROFITABLE"
        end)(),
    }
end

function Economy.HealthCheck()
    -- дымовой прогон формулы на синтетике (те же числа, что в test_economy.py)
    local rec = { recipeSpellID = 1, outputItemID = 999002, woodItemID = 256963,
        woodQty = 2, outputQty = 1,
        reagents = { { itemID = 256963, quantity = 2, isWood = true },
                     { itemID = 999001, quantity = 3 } } }
    local ok, eco = pcall(Economy.CalculateRecipeEconomy, rec,
        { [256963] = 50000, [999001] = 30000, [999002] = 200000 })
    return { ok = ok and eco and eco.profit == 10000 and eco.status == "PROFITABLE" }
end

_G.DecorLumberProfitEconomy = Economy
