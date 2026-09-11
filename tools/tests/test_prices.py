# -*- coding: utf-8 -*-
# test_prices.py — Services/Prices.lua: collect / cache / queue dedup / overflow / stats.

def run(lua, check, exec_):
    exec_(r'''
local recipes = {
    { recipeSpellID=1, outputItemID=999002, woodItemID=256963, woodQty=2,
      reagents={ {itemID=256963, quantity=2}, {itemID=999001, quantity=3} } },
    { recipeSpellID=2, outputItemID=999001, woodItemID=256963, woodQty=1,
      reagents={ {itemID=999001, quantity=1}, {itemID=999002, quantity=2} } },
}
MAP, NEED = DecorLumberProfitPrices.CollectPricesForRecipes(recipes)
local seen, dups = {}, 0
for _, id in ipairs(NEED) do if seen[id] then dups = dups + 1 end seen[id] = true end
NEED_COUNT, NEED_DUPS = #NEED, dups
''')
    check('need count (2 uniq: 999002, 999001 — wood cache-only, не ищется)', 'NEED_COUNT', '2')
    check('need has no duplicates', 'NEED_DUPS', '0')
    # Self-contained: fill the cache explicitly (was implicitly filled by the
    # economy suite before the split - suites must not depend on each other).
    exec_(r'''
DecorLumberProfitPrices.SetPrice(256963, 50000, "test")
DecorLumberProfitPrices.SetPrice(999001, 30000, "test")
DecorLumberProfitPrices.SetPrice(999002, 200000, "test")
MAP2, NEED2 = DecorLumberProfitPrices.CollectPricesForRecipes({
    { recipeSpellID=1, outputItemID=999002, woodItemID=256963, woodQty=2,
      reagents={ {itemID=256963, quantity=2}, {itemID=999001, quantity=3} } },
})
NEED2_COUNT = #NEED2
MAP2_256963 = MAP2[256963]
''')
    check('need empty after cache filled', 'NEED2_COUNT', '0')
    check('map wood price', 'MAP2_256963', '50000')
    check('HasFreshPrice(256963)', 'tostring(DecorLumberProfitPrices.HasFreshPrice(256963))', 'true')
    exec_('DecorLumberProfitPrices.ClearPriceCache()')
    check('HasFreshPrice after clear', 'tostring(DecorLumberProfitPrices.HasFreshPrice(256963))', 'false')
    # TTL поднят до 1 ч (было 15 мин — цены слетали между сессиями)
    check('price ttl default 1h', 'DecorLumberProfitConfig.AUCTION.PRICE_TTL', '3600')
    exec_(r'''
TTL_SAVED_TIME = time
DecorLumberProfitPrices.SetPrice(700100, 12345, "test")
FRESH_NOW = DecorLumberProfitPrices.HasFreshPrice(700100)
time = function() return TTL_SAVED_TIME() + 3700 end
STALE_AFTER_TTL = DecorLumberProfitPrices.HasFreshPrice(700100)
time = TTL_SAVED_TIME
''')
    check('fresh right after set', 'tostring(FRESH_NOW)', 'true')
    check('stale after TTL (1h)', 'tostring(STALE_AFTER_TTL)', 'false')
    exec_(r'''
DecorLumberProfitPrices.Enqueue({700001, 700001, 700002})
DecorLumberProfitPrices.Enqueue({700001})
QUEUE_OK = (DecorLumberProfitPrices.HasFreshPrice(700001) == false)
''')
    check('enqueue dedup keeps item pending-or-queued (not fresh)', 'tostring(QUEUE_OK)', 'true')
    # Этап 7: overflow O(1) — 505 сверх капа 500 уходят в overflow, счётчики целы
    exec_(r'''
DecorLumberProfitPrices.ClearQueue()
local bulk = {}
for i = 1, 505 do bulk[i] = 800000 + i end
DecorLumberProfitPrices.Enqueue(bulk)
QI = DecorLumberProfitPrices.GetQueueInfo()
''')
    check('overflow queue capped 500', 'QI.queue', '500')
    check('overflow holds 5', 'QI.overflow', '5')
    check('stats requested 0 without OnUpdate', 'QI.requested', '0')
    check('stats resolved 0 without OnUpdate', 'QI.resolved', '0')
    exec_(r'''
DecorLumberProfitPrices.ClearQueue()
QI2 = DecorLumberProfitPrices.GetQueueInfo()
''')
    check('clearqueue zeroes queue', 'QI2.queue', '0')
    check('clearqueue zeroes overflow', 'QI2.overflow', '0')

    # Realm-scoped prices and account-wide snapshots of owned auctions.
    exec_(r'''
TEST_OWNED_AUCTIONS = {
    { itemKey = { itemID = 999002 }, quantity = 4 },
    { itemKey = { itemID = 999002 }, quantity = 2 },
    { itemKey = { itemID = 999001 }, quantity = 1 },
}
DecorLumberProfitPrices.InitializeRealm()
DecorLumberProfitPrices.RefreshOwnedAuctions()
OWNED_STATS = DecorLumberProfitPrices.GetAuctionStats(999002)
''')
    check('owned quantity aggregates lots', 'OWNED_STATS.ownQty', '6')
    check('owned listings aggregates lots', 'OWNED_STATS.ownListings', '2')
    check('owned data is known', 'tostring(OWNED_STATS.ownKnown)', 'true')
    exec_(r'''
TEST_REALM = "OtherRealm"
TEST_REALM_NAME = "Other Realm"
TEST_OWNED_AUCTIONS = { { itemKey = { itemID = 999002 }, quantity = 3 } }
DecorLumberProfitPrices.InitializeRealm()
DecorLumberProfitPrices.SetPrice(999002, 777000, "other")
DecorLumberProfitPrices.RefreshOwnedAuctions()
OTHER_STATS = DecorLumberProfitPrices.GetAuctionStats(999002)
TEST_REALM = "TestRealm"
TEST_REALM_NAME = "Test Realm"
DecorLumberProfitPrices.InitializeRealm()
DecorLumberProfitPrices.SetPrice(999002, 200000, "current")
UnitName = function() return "Alt" end
TEST_OWNED_AUCTIONS = { { itemKey = { itemID = 999002 }, quantity = 5 } }
DecorLumberProfitPrices.RefreshOwnedAuctions()
UnitName = function() return "Tester" end
CURRENT_STATS = DecorLumberProfitPrices.GetAuctionStats(999002)
REALM_STATS = DecorLumberProfitPrices.GetRealmAuctionInfo(999002)
''')
    check('other realm price isolated', 'OTHER_STATS.price', '777000')
    check('other realm owned quantity isolated', 'OTHER_STATS.ownQty', '3')
    check('current realm price remains separate', 'CURRENT_STATS.price', '200000')
    check('owned quantity sums characters', 'CURRENT_STATS.ownQty', '11')
    check('realm tooltip data has two realms', '#REALM_STATS', '2')
