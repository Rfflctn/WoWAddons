-- tools/tests/stub.lua | STUB v1
-- Shared WoW API stubs for lupa-based tests (no game client).
-- Extracted from tools/smoke_test.py preamble + minimal additions
-- (ProfessionsFrame, GameTooltip, Item) so future suites don't re-stub.
-- Load ONCE per test run, before any addon file.

function stub_frame()
    local f = {}
    f.children = {}
    local mt
    mt = {
        __index = function(t, k)
            if k == "GetChildren" then return function(self) return unpack(t.children or {}) end end
            if k == "IsVisible" then return function(self) return false end end
            return function(self, ...) return nil end  -- no-op for any other method
        end,
    }
    setmetatable(f, mt)
    return f
end
CreateFrame = function(...) return stub_frame() end
C_Timer = { After = function(delay, fn) end }
time = function() return 1000000 end
GetTime = function() return 100.0 end
UnitName = function() return "Tester" end
GetLocale = function() return "enUS" end
StaticPopupDialogs = {}
Gatherer = nil
GameTooltip = { SetOwner = function(...) end, SetText = function(...) end,
    AddLine = function(...) end, Show = function(...) end, Hide = function(...) end,
    SetItemByID = function(...) end }
ProfessionsFrame = { IsVisible = function() return false end }
UIParent = {}
Item = { CreateFromItemID = function(id) return { ContinueOnItemLoad = function(self, fn) end } end }

-- API namespaces
C_Item = { GetItemInfo = function(id)
    local names = {[256963]="Thalassian Lumber", [245586]="Ironwood Lumber",
        [999001]="Sturdy Handle", [999002]="Oak Output"}
    return names[id], nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 0 -- bindType 0 = sellable
end }
GetItemInfo = C_Item.GetItemInfo
C_TradeSkillUI = {
    GetRecipeSchematic = function(id, isRecraft, level)
        return {
            recipeID = id, name = "Craft Oak Output", outputItemID = 999002,
            quantityMin = 1, quantityMax = 1, icon = "icon",
            reagentSlotSchematics = {
                { quantityRequired = 2, required = true, dataSlotIndex = 1,
                  reagents = { { itemID = 256963 } } },
                { quantityRequired = 3, required = true, dataSlotIndex = 2,
                  reagents = { { itemID = 999001 } } },
            },
        }
    end,
    GetRecipeInfo = function(id) return { learned = true, craftable = true, name = "Craft Oak Output", unlockedRecipeLevel = 1 } end,
    GetRecipeOutputItemData = function(...) return nil end,
    GetProfessionInfoByRecipeID = function(id) return { professionName = "Carpentry" } end,
    GetAllRecipeIDs = function() return { 424242 } end,
}
C_AuctionHouse = {
    MakeItemKey = function(id) return { itemID = id } end,
    IsThrottledMessageSystemReady = function() return true end,
    HasFullCommoditySearchResults = function(id) return true end,
    GetCommoditySearchResultsQuantity = function(id) return 0 end,
    GetNumCommoditySearchResults = function(id) return 0 end,
}
SLASH_DECORLUMBERPROFIT1 = nil
