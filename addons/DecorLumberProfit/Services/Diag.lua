-- Services/Diag.lua | DecorLumberProfit | Retail 12.1.0
-- In-game diagnostics skeleton (Этап 0.2). Additive only: no behavior change.
-- Provides: leveled logging (Dbg.Log), lastError capture, subsystem status,
-- copy-paste bug bundle, and a client-side selftest (no AH/profession needed).
-- WoW Lua 5.1: no goto, no //, no bitwise ops.

local ADDON = "DecorLumberProfit"
DecorLumberProfitDiag = {}
local Diag = DecorLumberProfitDiag

Diag.ADDON_VERSION = ((_G.DecorLumberProfit and _G.DecorLumberProfit.VERSION) or "2.0.0") .. "+diag0"
Diag.lastError = nil -- { where=string, err=string, at=number(time()) }

Diag.LEVELS = { ERROR = 1, WARN = 2, INFO = 3, VERBOSE = 4 }

local unpack = unpack or table.unpack -- WoW: Lua 5.1 global; тесты: lupa 5.4 table.unpack

local function LPrefix(ok)
    local L10n = _G.DecorLumberProfitL10n and _G.DecorLumberProfitL10n.L
    if L10n then
        if ok then return L10n.PREFIX_OK end
        return L10n.PREFIX_ERR
    end
    return ok and "[DecorLumberProfit] " or "[DecorLumberProfit] "
end

local function Now()
    if _G.time then
        local ok, t = pcall(_G.time)
        if ok and type(t) == "number" then return t end
    end
    return 0
end

local function CountTable(t)
    if type(t) ~= "table" then return 0 end
    local c = 0
    for _ in pairs(t) do c = c + 1 end
    return c
end

function Diag.IsVerbose()
    local db = _G.DecorLumberProfitDB
    return db and db.settings and db.settings.verbose == true or false
end

function Diag.SetVerbose(v)
    _G.DecorLumberProfitDB = _G.DecorLumberProfitDB or {}
    _G.DecorLumberProfitDB.settings = _G.DecorLumberProfitDB.settings or {}
    _G.DecorLumberProfitDB.settings.verbose = v and true or nil
    return Diag.IsVerbose()
end

-- Leveled log. ERROR/WARN/INFO always print (as before); VERBOSE only with flag.
function Diag.Log(level, module, fmt, ...)
    local lv = Diag.LEVELS[level] or Diag.LEVELS.INFO
    if lv == Diag.LEVELS.VERBOSE and not Diag.IsVerbose() then return end
    local msg = fmt or ""
    if select("#", ...) > 0 then
        local ok, s = pcall(string.format, fmt, ...)
        if ok then msg = s end
    end
    local err = (lv == Diag.LEVELS.ERROR) or (lv == Diag.LEVELS.WARN)
    print(LPrefix(not err) .. "[" .. tostring(module or ADDON) .. "/" .. tostring(level) .. "] " .. tostring(msg))
end

function Diag.CaptureError(where, err)
    Diag.lastError = { where = tostring(where or "?"), err = tostring(err or "?"), at = Now() }
    Diag.Log("ERROR", "Diag", "%s: %s", Diag.lastError.where, Diag.lastError.err)
    return Diag.lastError
end

-- xpcall wrapper for event/OnUpdate handlers (пока не внедрён в хендлеры — хендлеры
-- используют raw pcall как раньше; принимать постепенно, начиная с новых мест). Never throws.
function Diag.Call(where, func, ...)
    if type(func) ~= "function" then return false, "not-a-function" end
    local args = { ... }
    local n = select("#", ...)
    local function invoke() return func(unpack(args, 1, n)) end
    local results = { xpcall(invoke, function(e) return tostring(e) end) }
    if results[1] then return unpack(results) end
    Diag.CaptureError(where, results[2])
    return false, results[2]
end

-- ==== Subsystem probes (all defensive: missing module => state UNKNOWN) ====

local function ProbeWood()
    local cfg = _G.DecorLumberProfitConfig
    local ids = cfg and cfg.WOOD_ITEM_IDS
    if type(ids) ~= "table" or #ids == 0 then
        return { key = "wood", state = "FAIL", detail = "WOOD_ITEM_IDS empty/missing" }
    end
    local setOk = true
    if cfg.WOOD_IDS_SET then
        for _, id in ipairs(ids) do
            if not cfg.WOOD_IDS_SET[id] then setOk = false break end
        end
    end
    -- NOTE: count assertion duplicated in tools/tests/test_wood.py — update together.
    return { key = "wood", state = setOk and "OK" or "WARN",
        detail = string.format("types=%d set=%s first=%s last=%s",
            #ids, setOk and "ok" or "MISMATCH", tostring(ids[1]), tostring(ids[#ids])) }
end

local function ProbeRecipes()
    local Core = _G.DecorLumberProfitCore
    if not Core then return { key = "recipes", state = "UNKNOWN", detail = "Core missing" } end
    local saved, pending = nil, nil
    if Core.SavedRecipeCount then
        local ok, c = pcall(Core.SavedRecipeCount, Core)
        if ok then saved = c end
    end
    if Core.GetPendingBindCount then
        local ok, c = pcall(Core.GetPendingBindCount, Core)
        if ok then pending = c end
    end
    return { key = "recipes", state = "OK",
        detail = string.format("saved=%s pendingBind=%s", tostring(saved), tostring(pending)) }
end

local function ProbePrices()
    local Auction = _G.DecorLumberProfitPrices or _G.DecorLumberProfitAuction
    if not Auction then return { key = "prices", state = "UNKNOWN", detail = "Prices missing" } end
    if Auction.GetQueueInfo then
        local ok, qi = pcall(Auction.GetQueueInfo)
        if ok and type(qi) == "table" then
            local active = (qi.queue or 0) + (qi.pending or 0)
            return { key = "prices", state = active == 0 and "OK" or "WARN",
                detail = string.format("realm=%s queue=%d overflow=%d pending=%d cached-note:see '/dlp debug queue'",
                    tostring(qi.realmName or qi.realm or "?"), qi.queue or 0, qi.overflow or 0, qi.pending or 0) }
        end
    end
    return { key = "prices", state = "UNKNOWN", detail = "no queue introspection" }
end

local function ProbeDB()
    local db = _G.DecorLumberProfitDB
    if not db then return { key = "db", state = "WARN", detail = "DB not loaded yet (ADDON_LOADED pending)" } end
    local realms, prices, owned = 0, 0, 0
    for realmKey, bucket in pairs(db.priceCache or {}) do
        if type(bucket) == "table" then
            realms = realms + 1
            for _ in pairs(bucket) do prices = prices + 1 end
        end
        if db.ownedAuctions and type(db.ownedAuctions[realmKey]) == "table" then
            for _ in pairs(db.ownedAuctions[realmKey]) do owned = owned + 1 end
        end
    end
    return { key = "db", state = "OK",
        detail = string.format("schema=%s realms=%d prices=%d ownedSnapshots=%d known=%d",
            tostring(db.schemaVersion or 1),
            realms, prices, owned, CountTable(db.recipes), CountTable(db.knownRecipes)) }
end

local function ProbeErrors()
    if Diag.lastError then
        return { key = "errors", state = "FAIL",
            detail = string.format("%s: %s", Diag.lastError.where, Diag.lastError.err) }
    end
    return { key = "errors", state = "OK", detail = "no captured errors" }
end

function Diag.SubsystemStatus()
    return { ProbeWood(), ProbeRecipes(), ProbePrices(), ProbeDB(), ProbeErrors() }
end

function Diag.StatusLines()
    local lines = {}
    lines[#lines + 1] = string.format("DecorLumberProfit %s status:", Diag.ADDON_VERSION)
    for _, s in ipairs(Diag.SubsystemStatus()) do
        lines[#lines + 1] = string.format("[%s] %s: %s", s.state, s.key, s.detail)
    end
    lines[#lines + 1] = "Next: /dlp debug selftest | /dlp bug (copy-paste bundle)"
    return lines
end

function Diag.PrintStatus()
    for _, line in ipairs(Diag.StatusLines()) do
        print(LPrefix(true) .. line)
    end
end

-- ==== Bug bundle: one copy-paste block for issue reports ====

local function ClientBuild()
    if _G.GetBuildInfo then
        local ok, v = pcall(_G.GetBuildInfo)
        if ok and v then return tostring(v) end
    end
    return "?"
end

local function ClientLocale()
    if _G.GetLocale then
        local ok, v = pcall(_G.GetLocale)
        if ok and v then return tostring(v) end
    end
    return "?"
end

function Diag.BugBundleLines()
    local lines = {}
    lines[#lines + 1] = "=== DecorLumberProfit bug bundle ==="
    lines[#lines + 1] = "addon=" .. Diag.ADDON_VERSION .. " build=" .. ClientBuild() .. " locale=" .. ClientLocale()
    local cfg = _G.DecorLumberProfitConfig
    if cfg and cfg.WOOD_ITEM_IDS then
        lines[#lines + 1] = "woodTypes=" .. #cfg.WOOD_ITEM_IDS
            .. " first=" .. tostring(cfg.WOOD_ITEM_IDS[1])
            .. " last=" .. tostring(cfg.WOOD_ITEM_IDS[#cfg.WOOD_ITEM_IDS])
    end
    for _, s in ipairs(Diag.SubsystemStatus()) do
        if s.key ~= "errors" then
            lines[#lines + 1] = string.format("%s: [%s] %s", s.key, s.state, s.detail)
        end
    end
    local dbgOwner = _G.DecorLumberProfitRecipes or _G.DecorLumberProfitCore
    if dbgOwner and dbgOwner._lastActiveDebug then
        local ok, dbg = pcall(function() return table.concat(dbgOwner._lastActiveDebug or {}, ",") end)
        lines[#lines + 1] = "lastActive: " .. (ok and dbg or "?")
    end
    if Diag.lastError then
        lines[#lines + 1] = "lastError: " .. Diag.lastError.where .. ": " .. Diag.lastError.err
    else
        lines[#lines + 1] = "lastError: none"
    end
    lines[#lines + 1] = "=== end bundle ==="
    return lines
end

function Diag.PrintBug()
    for _, line in ipairs(Diag.BugBundleLines()) do
        print(LPrefix(true) .. line)
    end
end

-- ==== In-game selftest (no AH / no profession window needed) ====
-- Mirrors tools/tests/test_money.py + test_economy.py cases.

function Diag.SelfTest()
    local results = {}
    local function add(name, want, fn)
        local ok, got = pcall(fn)
        local pass = ok and got == want
        results[#results + 1] = { name = name, pass = pass,
            got = ok and tostring(got) or ("ERR:" .. tostring(got)), want = tostring(want) }
    end
    local Auction = _G.DecorLumberProfitPrices or _G.DecorLumberProfitAuction
    local Core = _G.DecorLumberProfitCore
    add("money_gold_contains_12346", "true", function()
        if not (Auction and Auction.FormatMoney) then return "false" end
        local s = Auction.FormatMoney(123456789)
        return tostring(s and string.find(s, "12346", 1, true) ~= nil)
    end)
    add("money_nil_emdash", "true", function()
        if not (Auction and Auction.FormatMoney) then return "false" end
        return tostring(Auction.FormatMoney(nil) == "—")
    end)
    add("eco_profitable", "true", function()
        if not (Core and Core.CalculateRecipeEconomy) then return "false" end
        local rec = { recipeSpellID = 1, outputItemID = 999002, woodItemID = 256963,
            woodQty = 2, outputQty = 1,
            reagents = { { itemID = 256963, quantity = 2, isWood = true },
                         { itemID = 999001, quantity = 3 } } }
        local eco = Core:CalculateRecipeEconomy(rec,
            { [256963] = 50000, [999001] = 30000, [999002] = 200000 })
        return tostring(eco and eco.profit == 10000 and eco.status == "PROFITABLE")
    end)
    add("eco_no_output_price", "true", function()
        if not (Core and Core.CalculateRecipeEconomy) then return "false" end
        local rec = { recipeSpellID = 2, outputItemID = 999002, woodItemID = 256963,
            woodQty = 2, outputQty = 1,
            reagents = { { itemID = 256963, quantity = 2, isWood = true },
                         { itemID = 999001, quantity = 3 } } }
        local eco = Core:CalculateRecipeEconomy(rec, { [256963] = 50000, [999001] = 30000 })
        return tostring(eco and eco.status == "NO_OUTPUT_PRICE")
    end)
    add("wood_types_12", "true", function()
        local cfg = _G.DecorLumberProfitConfig
        return tostring(cfg and cfg.WOOD_ITEM_IDS and #cfg.WOOD_ITEM_IDS == 12)
    end)
    local passed, failed = 0, 0
    for _, r in ipairs(results) do
        if r.pass then passed = passed + 1 else failed = failed + 1 end
    end
    return { passed = passed, failed = failed, results = results }
end

function Diag.PrintSelfTest()
    local st = Diag.SelfTest()
    print(LPrefix(st.failed == 0) .. string.format("selftest: %d passed, %d failed",
        st.passed, st.failed))
    for _, r in ipairs(st.results) do
        print(LPrefix(r.pass) .. string.format("  [%s] %s (got %s, want %s)",
            r.pass and "PASS" or "FAIL", r.name, r.got, r.want))
    end
end

_G.DecorLumberProfitDiag = Diag
