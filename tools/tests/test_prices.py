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

    # Persist: пустой АХ не стирает последнюю цену (lastPrice переживает noauction).
    exec_(r'''
DecorLumberProfitPrices.SetPrice(700200, 50000, "commodity")
DecorLumberProfitPrices.MarkNoAuction(700200, "commodity-empty")
NOAUC_PRICE = DecorLumberProfitPrices.GetCachedPrice(700200)
MAP_NOAUC, NEED_NOAUC = DecorLumberProfitPrices.CollectPricesForRecipes({
    { recipeSpellID=9, outputItemID=700200, reagents={} },
})
STATS_NOAUC = DecorLumberProfitPrices.GetAuctionStats(700200)
REALMS_NOAUC = DecorLumberProfitPrices.GetRealmAuctionInfo(700200)
NOAUC_RP, NOAUC_RS = nil, nil
for _, info in ipairs(REALMS_NOAUC) do
    if info.key == "TestRealm" then NOAUC_RP = info.price; NOAUC_RS = info.stale end
end
''')
    check('noauction keeps last price', 'NOAUC_PRICE', '50000')
    check('noauction last price in map', 'MAP_NOAUC[700200]', '50000')
    check('noauction not re-requested while fresh', '#NEED_NOAUC', '0')
    check('noauction stats price is last', 'STATS_NOAUC.price', '50000')
    check('noauction stats stale', 'tostring(STATS_NOAUC.stale)', 'true')
    check('noauction realm line price is last', 'NOAUC_RP', '50000')
    check('noauction realm line stale', 'tostring(NOAUC_RS)', 'true')

    # Persist: протухшая цена видна в таблице, пока идёт фоновый рескан.
    exec_(r'''
DecorLumberProfitPrices.SetPrice(700201, 60000, "test")
TTL_S2 = time
time = function() return TTL_S2() + 3700 end
MAP_STALE, NEED_STALE = DecorLumberProfitPrices.CollectPricesForRecipes({
    { recipeSpellID=10, outputItemID=700201, reagents={} },
})
time = TTL_S2
''')
    check('stale price stays in map', 'MAP_STALE[700201]', '60000')
    check('stale price re-requested', '#NEED_STALE', '1')

    # Persist: SV другого реалма читается независимо от давности (стирается только сбросом).
    exec_(r'''
TEST_REALM = "OtherRealm"
TEST_REALM_NAME = "Other Realm"
DecorLumberProfitPrices.InitializeRealm()
TTL_S3 = time
time = function() return TTL_S3() - 8000 end
DecorLumberProfitPrices.SetPrice(700203, 71000, "other")
time = TTL_S3
TEST_REALM = "TestRealm"
TEST_REALM_NAME = "Test Realm"
DecorLumberProfitPrices.InitializeRealm()
OLD_OTHER_PRICE = DecorLumberProfitPrices.GetCachedPrice(700203, "OtherRealm")
''')
    check('other realm old price persists', 'OLD_OTHER_PRICE', '71000')

    # ---- write-path: qty из того же чтения, что и цена (построчный фолбэк) ----
    exec_(r'''
OLD_CQ = C_AuctionHouse.GetCommoditySearchResultsQuantity
OLD_CN = C_AuctionHouse.GetNumCommoditySearchResults
OLD_CI = C_AuctionHouse.GetCommoditySearchResultInfo
OLD_IQ = C_AuctionHouse.GetItemSearchResultsQuantity
OLD_IN = C_AuctionHouse.GetNumItemSearchResults
OLD_II = C_AuctionHouse.GetItemSearchResultInfo
-- totals-qty молчит, строки есть (3 лота x2 шт): построчная сумма 6
C_AuctionHouse.GetCommoditySearchResultsQuantity = function(id) return nil end
C_AuctionHouse.GetNumCommoditySearchResults = function(id)
    if id == 700310 then return 3 end
    return 0
end
C_AuctionHouse.GetCommoditySearchResultInfo = function(id, i)
    if id == 700310 and i >= 1 and i <= 3 then return { unitPrice = 1000 * i, quantity = 2 } end
    return nil
end
P_ROWQ = DecorLumberProfitPrices.TryUpdateFromCache(700310)
E_ROWQ = DecorLumberProfitDB.priceCache.TestRealm[700310]
''')
    check('row fallback price', 'P_ROWQ', '1000')
    check('row fallback qty is row sum', 'E_ROWQ.qty', '6')
    check('row fallback listings is row count', 'E_ROWQ.listings', '3')
    exec_(r'''
-- totals есть: побеждают totals, построчная сумма не используется
C_AuctionHouse.GetCommoditySearchResultsQuantity = function(id)
    if id == 700311 then return 100 end
    return nil
end
C_AuctionHouse.GetNumCommoditySearchResults = function(id)
    if id == 700311 then return 3 end
    return 0
end
C_AuctionHouse.GetCommoditySearchResultInfo = function(id, i)
    if id == 700311 and i >= 1 and i <= 3 then return { unitPrice = 500, quantity = 2 } end
    return nil
end
DecorLumberProfitPrices.TryUpdateFromCache(700311)
E_TOTQ = DecorLumberProfitDB.priceCache.TestRealm[700311]
''')
    check('totals qty wins over rows', 'E_TOTQ.qty', '100')
    exec_(r'''
-- лотов > 15 и totals-qty нет: неполную сумму не пишем, цена пишется
C_AuctionHouse.GetNumCommoditySearchResults = function(id)
    if id == 700312 then return 20 end
    return 0
end
C_AuctionHouse.GetCommoditySearchResultInfo = function(id, i)
    if id == 700312 and i >= 1 and i <= 20 then return { unitPrice = 700, quantity = 5 } end
    return nil
end
DecorLumberProfitPrices.TryUpdateFromCache(700312)
E_BIGQ = DecorLumberProfitDB.priceCache.TestRealm[700312]
''')
    check('big result price written', 'E_BIGQ.price', '700')
    check('big result partial sum not used', 'tostring(E_BIGQ.qty)', 'nil')
    exec_(r'''
-- item-путь: totals-qty молчит, 2 строки: цена min(buyout), qty = сумма
C_AuctionHouse.GetCommoditySearchResultsQuantity = function(id) return 0 end
C_AuctionHouse.GetNumCommoditySearchResults = function(id) return 0 end
C_AuctionHouse.GetItemSearchResultsQuantity = function(key) return nil end
C_AuctionHouse.GetNumItemSearchResults = function(key)
    if key and key.itemID == 700313 then return 2 end
    return 0
end
C_AuctionHouse.GetItemSearchResultInfo = function(key, i)
    if key and key.itemID == 700313 and i == 1 then return { buyoutAmount = 900, quantity = 1 } end
    if key and key.itemID == 700313 and i == 2 then return { buyoutAmount = 1500, quantity = 4 } end
    return nil
end
P_IROWQ = DecorLumberProfitPrices.TryUpdateFromCache(700313)
E_IROWQ = DecorLumberProfitDB.priceCache.TestRealm[700313]
C_AuctionHouse.GetCommoditySearchResultsQuantity = OLD_CQ
C_AuctionHouse.GetNumCommoditySearchResults = OLD_CN
C_AuctionHouse.GetCommoditySearchResultInfo = OLD_CI
C_AuctionHouse.GetItemSearchResultsQuantity = OLD_IQ
C_AuctionHouse.GetNumItemSearchResults = OLD_IN
C_AuctionHouse.GetItemSearchResultInfo = OLD_II
''')
    check('item row fallback price', 'P_IROWQ', '900')
    check('item row fallback qty is row sum', 'E_IROWQ.qty', '5')

    # ---- external source: Auctionator (optional, auto with native fallback) ----
    exec_(r'''
Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(id)
    if id == 900101 then return 45000 end
    if id == 900105 then return 77000 end
    if id == 900102 then return "garbage" end
    return nil
end } } }
DecorLumberProfitPrices.ClearPriceCache()
EXT_AVAIL = DecorLumberProfitPrices.IsAuctionatorAvailable()
EXT_P1 = DecorLumberProfitPrices.GetExternalPrice(900101)
EXT_P2 = DecorLumberProfitPrices.GetExternalPrice(900102)
EXT_P3 = DecorLumberProfitPrices.GetExternalPrice(900103)
EXT_SRC = DecorLumberProfitPrices.GetConfiguredPriceSource()
EXT_ACTIVE = DecorLumberProfitPrices.IsExternalActive()
MAPX, NEEDX, EXTN = DecorLumberProfitPrices.CollectPricesForRecipes({
    { recipeSpellID=51, outputItemID=900101, reagents={ {itemID=900103, quantity=1} } },
})
EXT_ENTRY_SRC = DecorLumberProfitDB.priceCache.TestRealm[900101].source
EXT_IMP, EXT_MISS = DecorLumberProfitPrices.ImportFromAuctionator({ 900101, 900105, 900103 })
''')
    check('auctionator detected', 'tostring(EXT_AVAIL)', 'true')
    check('external price hit', 'EXT_P1', '45000')
    check('external garbage -> nil', 'tostring(EXT_P2)', 'nil')
    check('external miss -> nil', 'tostring(EXT_P3)', 'nil')
    check('default source auto', 'EXT_SRC', 'auto')
    check('external active in auto', 'tostring(EXT_ACTIVE)', 'true')
    check('collect imports external price', 'MAPX[900101]', '45000')
    check('collect leaves unknown out of map', 'tostring(MAPX[900103])', 'nil')
    check('collect external import count', 'EXTN', '1')
    check('collect need only misses', '#NEEDX', '1')
    check('collect need miss id', 'NEEDX[1]', '900103')
    check('external entry tagged', 'EXT_ENTRY_SRC', 'auctionator')
    check('batch import count (fresh skipped)', 'EXT_IMP', '1')
    check('batch import missing', '#EXT_MISS', '1')
    check('batch import missing id', 'EXT_MISS[1]', '900103')
    exec_(r'''
DecorLumberProfitPrices.ClearPriceCache()
SETNATIVE_OK = DecorLumberProfitPrices.SetPriceSource("native")
EXT_ACTIVE_N = DecorLumberProfitPrices.IsExternalActive()
MAPN, NEEDN = DecorLumberProfitPrices.CollectPricesForRecipes({
    { recipeSpellID=51, outputItemID=900101, reagents={ {itemID=900103, quantity=1} } },
})
SETBAD_OK = DecorLumberProfitPrices.SetPriceSource("bogus")
SETAUTO_OK = DecorLumberProfitPrices.SetPriceSource("auto")
SETSRC_SAVED = DecorLumberProfitDB.settings.priceSource
''')
    check('set native ok', 'tostring(SETNATIVE_OK)', 'true')
    check('native disables external', 'tostring(EXT_ACTIVE_N)', 'false')
    check('native collect needs both', '#NEEDN', '2')
    check('native collect map empty', 'tostring(MAPN[900101])', 'nil')
    check('invalid source rejected', 'tostring(SETBAD_OK)', 'false')
    check('set auto ok', 'tostring(SETAUTO_OK)', 'true')
    check('source persisted to settings', 'SETSRC_SAVED', 'auto')
    exec_(r'''
Auctionator.API.v1.GetAuctionPriceByItemID = function(id) error("boom") end
EXT_ERR = DecorLumberProfitPrices.GetExternalPrice(900101)
Auctionator = nil
EXT_AVAIL_OFF = DecorLumberProfitPrices.IsAuctionatorAvailable()
EXT_ACTIVE_OFF = DecorLumberProfitPrices.IsExternalActive()
QIX = DecorLumberProfitPrices.GetQueueInfo()
''')
    check('broken auctionator api -> nil (no throw)', 'tostring(EXT_ERR)', 'nil')
    check('missing auctionator not available', 'tostring(EXT_AVAIL_OFF)', 'false')
    check('auto without auctionator falls back', 'tostring(EXT_ACTIVE_OFF)', 'false')
    check('queueinfo exposes source', 'QIX.source', 'auto')
    check('queueinfo exposes external flag', 'tostring(QIX.external)', 'false')

    # ---- owned snapshots: speculative refresh must not clobber good data ----
    exec_(r'''
TEST_OWNED_AUCTIONS = { { itemKey = { itemID = 900201 }, quantity = 7 } }
DecorLumberProfitPrices.RefreshOwnedAuctions(true)
OWN_AUTH = DecorLumberProfitPrices.GetAuctionStats(900201)
TEST_OWNED_AUCTIONS = {}
SPEC_KEEP_OK = DecorLumberProfitPrices.RefreshOwnedAuctions(false)
OWN_SPEC = DecorLumberProfitPrices.GetAuctionStats(900201)
AUTH_CLEAR_OK = DecorLumberProfitPrices.RefreshOwnedAuctions(true)
OWN_AUTH_EMPTY = DecorLumberProfitPrices.GetAuctionStats(900201)
''')
    check('authoritative write stores lots', 'OWN_AUTH.ownQty', '7')
    check('speculative empty keeps snapshot', 'tostring(SPEC_KEEP_OK)', 'true')
    check('speculative empty keeps qty', 'OWN_SPEC.ownQty', '7')
    check('speculative empty keeps known', 'tostring(OWN_SPEC.ownKnown)', 'true')
    check('authoritative empty clears', 'tostring(AUTH_CLEAR_OK)', 'true')
    check('authoritative empty qty zero', 'OWN_AUTH_EMPTY.ownQty', '0')
    check('authoritative empty still known', 'tostring(OWN_AUTH_EMPTY.ownKnown)', 'true')
    exec_(r'''
DecorLumberProfitDB.ownedAuctions = {}
TEST_OWNED_AUCTIONS = {}
SPEC_FIRST_OK = DecorLumberProfitPrices.RefreshOwnedAuctions(false)
OWN_SPEC_FIRST = DecorLumberProfitPrices.GetAuctionStats(900201)
TEST_OWNED_AUCTIONS = nil
''')
    check('speculative empty on blank writes snapshot', 'tostring(SPEC_FIRST_OK)', 'true')
    check('blank snapshot known', 'tostring(OWN_SPEC_FIRST.ownKnown)', 'true')
    check('blank snapshot qty zero', 'OWN_SPEC_FIRST.ownQty', '0')

    # ---- reset clears owned snapshots too ("Мои" не переживает сброс кэша) ----
    exec_(r'''
TEST_OWNED_AUCTIONS = { { itemKey = { itemID = 900301 }, quantity = 3 } }
DecorLumberProfitPrices.RefreshOwnedAuctions(true)
OWN_PRE_RESET = DecorLumberProfitPrices.GetAuctionStats(900301)
DecorLumberProfitPrices.ClearPriceCache()
OWN_POST_RESET = DecorLumberProfitPrices.GetAuctionStats(900301)
-- чтение через OwnedRoot пересоздаёт пустую realm-корзину: проверяем её пустоту
OWNED_BUCKET_EMPTY = DecorLumberProfit.CountTable(DecorLumberProfitDB.ownedAuctions.TestRealm)
TEST_OWNED_AUCTIONS = nil
''')
    check('owned present before reset', 'OWN_PRE_RESET.ownQty', '3')
    check('reset wipes owned stats', 'tostring(OWN_POST_RESET)', 'nil')
    check('reset wipes owned bucket', 'OWNED_BUCKET_EMPTY', '0')
    exec_(r'''
TEST_OWNED_AUCTIONS = { { itemKey = { itemID = 900301 }, quantity = 3 } }
DecorLumberProfitPrices.RefreshOwnedAuctions(true)
TEST_REALM = "OtherRealm"
TEST_REALM_NAME = "Other Realm"
DecorLumberProfitPrices.InitializeRealm()
TEST_OWNED_AUCTIONS = { { itemKey = { itemID = 900302 }, quantity = 5 } }
DecorLumberProfitPrices.RefreshOwnedAuctions(true)
DecorLumberProfitPrices.ClearPriceCache("TestRealm")
OWN_SCOPED_KEPT = DecorLumberProfitPrices.GetAuctionStats(900302)
OWN_SCOPED_GONE = DecorLumberProfitPrices.GetAuctionStats(900301, "TestRealm")
TEST_REALM = "TestRealm"
TEST_REALM_NAME = "Test Realm"
DecorLumberProfitPrices.InitializeRealm()
TEST_OWNED_AUCTIONS = nil
''')
    check('scoped reset keeps other realm owned', 'OWN_SCOPED_KEPT.ownQty', '5')
    check('scoped reset wipes realm owned', 'tostring(OWN_SCOPED_GONE)', 'nil')
    exec_(r'''
TEST_OWNED_AUCTIONS = { { itemKey = { itemID = 900303 }, quantity = 2 } }
DecorLumberProfitPrices.RefreshOwnedAuctions(true)
DecorLumberProfitPrices.ClearOwnedAuctions("TestRealm")
OWN_DIRECT_GONE = DecorLumberProfitPrices.GetAuctionStats(900303)
TEST_OWNED_AUCTIONS = nil
''')
    check('direct owned clear wipes realm', 'tostring(OWN_DIRECT_GONE)', 'nil')
