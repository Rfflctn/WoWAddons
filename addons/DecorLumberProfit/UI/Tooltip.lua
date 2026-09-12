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

-- Имена персонажей, знающих рецепт: отсортированный список ключей learnedBy == true.
-- Чистая функция (тесты). Пустой массив — никто не знает / данных нет.
function UI.GetLearnerNames(rec)
    local out = {}
    if type(rec) ~= "table" then return out end
    local lb = rec.learnedBy
    if type(lb) ~= "table" then return out end
    for name, v in pairs(lb) do
        if v == true and type(name) == "string" and name ~= "" then
            out[#out + 1] = name
        end
    end
    table.sort(out)
    return out
end

-- Текст ячейки «Изучен»: имена знающих через ", " (сразу видно, каким персом учить).
-- Фолбэки для legacy-записей без learnedBy: CELL_YES (learned==true),
-- CELL_NO (learned==false), иначе CELL_UNKNOWN.
function UI.FormatLearnedCell(rec)
    local names = UI.GetLearnerNames(rec)
    if #names > 0 then
        return table.concat(names, ", ")
    end
    if type(rec) == "table" and rec.learned == true then
        return L.CELL_YES
    elseif type(rec) == "table" and rec.learned == false then
        return L.CELL_NO
    else
        return L.CELL_UNKNOWN
    end
end

-- Изучен ли рецепт хотя бы на одном персонаже аккаунта
function UI.IsLearnedAnywhere(rec)
    return rec.learned == true or UI.HasOtherLearners(rec)
end

-- Мультиреалм-отображение: выключено по умолчанию (один мир для масс),
-- включается командой /dlp multirealm on. Гейтит только тултип-блок
-- «данные по серверам»; сбор и хранение данных по реалмам идут всегда,
-- поэтому включение сразу показывает накопленную историю.
function UI.IsMultiRealmEnabled()
    local cfg = _G.DecorLumberProfitConfig
    return cfg and cfg.MULTI_REALM == true or false
end

function UI.SetMultiRealm(enabled)
    _G.DecorLumberProfitConfig = _G.DecorLumberProfitConfig or {}
    _G.DecorLumberProfitConfig.MULTI_REALM = enabled and true or false
    if DecorLumberProfitDB and DecorLumberProfitDB.settings then
        DecorLumberProfitDB.settings.multiRealm = _G.DecorLumberProfitConfig.MULTI_REALM
    end
    return _G.DecorLumberProfitConfig.MULTI_REALM
end

local function AddRealmAuctionLines(itemID)
    local P = _G.DecorLumberProfitPrices
    if not (P and P.GetRealmAuctionInfo) then return end
    local ok, realms = pcall(P.GetRealmAuctionInfo, itemID)
    if not ok or type(realms) ~= "table" or #realms == 0 then return end
    -- Сравнение серверов (п.4): при данных с 2+ серверов блок показываем всегда,
    -- даже если /dlp multirealm off (массовый дефолт — один мир без лишних строк).
    -- При одном сервере — только если multirealm явно включён.
    if #realms < 2 and not UI.IsMultiRealmEnabled() then return end
    GameTooltip:AddLine(L.TIP_AH_REALMS_TITLE, 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L.TIP_AH_REALMS_NOTE, 0.6, 0.6, 0.6, true)
    for _, info in ipairs(realms) do
        local price = info.price and UI.GetMoneyStr(info.price) or L.CELL_DASH
        local total = UI.FormatAuctionQuantity(info.qty, info.listings) or L.CELL_DASH
        local mine = info.ownQty ~= nil and tostring(info.ownQty) or L.CELL_DASH
        local stale = info.stale and L.TIP_AH_REALM_STALE or ""
        GameTooltip:AddLine(TL("TIP_AH_REALM_LINE", info.name or info.key or "?", price, total, mine, stale), 0.7, 0.9, 1, true)
    end
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
    -- Кто изучил: имена персонажей (та же строка, что в колонке «Изучен»;
    -- в ячейке длинные списки могут резаться шириной колонки).
    if UI.GetLearnerNames then
        local learners = UI.GetLearnerNames(rec)
        if type(learners) == "table" and #learners > 0 then
            GameTooltip:AddLine(TL("TIP_LEARNED_BY", table.concat(learners, ", ")), 0.6, 1, 0.6)
        end
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
        if P and P.GetAuctionStats and UI.FormatAuctionQuantity then
            local ok, info = pcall(P.GetAuctionStats, rec.outputItemID)
            if ok and info then
                local txt = UI.FormatAuctionQuantity(info.qty, info.listings)
                if txt then GameTooltip:AddLine(TL("TIP_AHQTY_LINE", txt), 0.7, 0.9, 1) end
                if info.ownKnown then
                    GameTooltip:AddLine(TL("TIP_AH_MINE_LINE", tostring(info.ownQty or 0)), 0.7, 0.9, 1)
                end
            end
        elseif P and P.GetCachedQuantity and UI.FormatAuctionQuantity then
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
        AddRealmAuctionLines(rec.outputItemID)
    end
    GameTooltip:Show()
end
