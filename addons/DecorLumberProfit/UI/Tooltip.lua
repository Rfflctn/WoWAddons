-- UI/Tooltip.lua | DecorLumberProfit | Retail 12.1.0
-- Тултипы строк таблицы + мелкие хелперы отображения (Этап 8).

local UI = _G.DecorLumberProfitUI or {}
local L = DecorLumberProfitL10n.L
local TL = DecorLumberProfitL10n.TL

function UI.GetMoneyStr(copper)
    return DecorLumberProfitPrices.FormatMoney(copper)
end

function UI.GetWoodDisplayName(rec)
    if not rec.woodName and rec.woodItemID then
        rec.woodName = DecorLumberProfitCore:GetItemName(rec.woodItemID)
    end
    return rec.woodName or (rec.woodItemID and ("#" .. rec.woodItemID)) or "?"
end

-- Знает ли рецепт ХОТЬ КТО-ТО на аккаунте (явные true в learnedBy;
-- false-записи "проверено, не знает" игнорируем)
function UI.HasOtherLearners(rec)
    if type(rec.learnedBy) ~= "table" then return false end
    for _, v in pairs(rec.learnedBy) do if v == true then return true end end
    return false
end

-- Изучен ли рецепт хотя бы на одном персонаже аккаунта
function UI.IsLearnedAnywhere(rec)
    return rec.learned == true or UI.HasOtherLearners(rec)
end

-- Тултип строки: что создаёт, профессия, реагенты с ценами, missing-цены.
-- Этап 9: если предмет известен клиенту — полный тултип вещи (SetItemByID) + наши строки,
-- иначе текстовый фолбэк как раньше.
function UI.ShowRowTooltip(row, dataIndex)
    local pair = UI._displayList[dataIndex]
    local rec = pair and pair.rec
    if not rec then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local linked = false
    if rec.outputItemID and GameTooltip.SetItemByID then
        local known = DecorLumberProfitCore:GetItemName(rec.outputItemID)
        if known then
            GameTooltip:SetItemByID(rec.outputItemID)
            linked = true
        end
    end
    if not linked then
        GameTooltip:SetText(rec.name or L.TIP_RECIPE_FALLBACK, 1, 1, 1)
        if rec.outputItemID then
            local outName = DecorLumberProfitCore:GetItemName(rec.outputItemID)
            if outName then
                GameTooltip:AddLine(TL("TIP_CREATES", outName, rec.outputQty or 1), 0.6, 0.9, 1)
            else
                GameTooltip:AddLine(TL("TIP_CREATES_ITEM", rec.outputItemID, rec.outputQty or 1), 0.6, 0.9, 1)
            end
        end
    end
    if rec.profession then
        GameTooltip:AddLine(TL("TIP_PROFESSION", rec.profession), 0.6, 0.9, 1)
    end
    if rec.reagents then
        GameTooltip:AddLine(L.TIP_REAGENTS, 0.8, 0.8, 0.8)
        for _, r in ipairs(rec.reagents) do
            local name = r.itemID
            if type(r.itemID) == "number" then
                local n = DecorLumberProfitCore:GetItemName(r.itemID)
                if n then name = n end
            end
            local price = DecorLumberProfitPrices.GetCachedPrice(r.itemID)
            local priceStr = price and UI.GetMoneyStr(price) or L.CELL_NO_PRICE
            GameTooltip:AddLine(string.format("  %s x%d — %s", tostring(name), r.quantity, priceStr), 1, 1, 1)
        end
    end
    local eco = pair.eco
    if eco and eco.missingReagents and #eco.missingReagents > 0 then
        GameTooltip:AddLine(TL("TIP_NO_PRICE_FOR", table.concat(eco.missingReagents, ", ")), 1, 0.3, 0.3)
    end
    -- Конкуренция: сколько готового предмета висит на АХ (та же цифра, что в колонке «На АХ»)
    if rec.outputItemID then
        local P = _G.DecorLumberProfitPrices
        if P and P.GetCachedQuantity and UI.FormatAuctionQuantity then
            local ok, qty, listings = pcall(P.GetCachedQuantity, rec.outputItemID)
            if ok then
                local txt = UI.FormatAuctionQuantity(qty, listings)
                if txt then
                    GameTooltip:AddLine(TL("TIP_AHQTY_LINE", txt), 0.7, 0.9, 1)
                end
            end
        elseif eco and eco.ahQty ~= nil and UI.FormatAuctionQuantity then
            local txt = UI.FormatAuctionQuantity(eco.ahQty, eco.ahListings)
            if txt then GameTooltip:AddLine(TL("TIP_AHQTY_LINE", txt), 0.7, 0.9, 1) end
        end
    end
    GameTooltip:Show()
end
