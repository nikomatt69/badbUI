-- Osservazioni locali, isolate per reame, fazione, mercato e variante oggetto.
local _, ns = ...
local Badb = ns.Badb
local S = { MAX_SEARCH = 63 }
Badb.AuctionStore = S

local DAY = 86400
local DAYS = 21
local ITEM_LIMIT = 500
local SEARCH_LIMIT = 24

local function number(value, min, max)
    return not Badb.Compat.IsSecret(value) and type(value) == "number"
        and value >= min and value <= max and value == math.floor(value)
end
S.IsInteger = number

local function plain(value, limit)
    return not Badb.Compat.IsSecret(value) and type(value) == "string"
        and #value > 0 and #value <= limit and not value:find("[%c|]")
end
S.IsPlainText = plain

function S.NormalizeSearch(value)
    if Badb.Compat.IsSecret(value) or type(value) ~= "string" or #value > 256 then return end
    value = value:match("^%s*(.-)%s*$")
    if plain(value, S.MAX_SEARCH) then return value end
end

function S.ItemKey(value)
    if Badb.Compat.IsSecret(value) or type(value) ~= "table" or not number(value.itemID, 1, 2147483647) then return end
    local level, suffix, pet = value.itemLevel, value.itemSuffix, value.battlePetSpeciesID
    if Badb.Compat.IsSecret(level) or Badb.Compat.IsSecret(suffix) or Badb.Compat.IsSecret(pet) then return end
    if level == nil then level = 0 end
    if suffix == nil then suffix = 0 end
    if pet == nil then pet = 0 end
    if not number(level, 0, 2147483647) or not number(suffix, -2147483647, 2147483647)
        or not number(pet, 0, 2147483647) then return end
    return ("%d:%d:%d:%d"):format(value.itemID, level, suffix, pet)
end

local function store()
    return Badb.DB:GetStore("auction")
end

function S.Now()
    if type(GetServerTime) == "function" then
        local ok, value = pcall(GetServerTime)
        if ok and number(value, DAY * DAYS, 9007199254740991) then return value end
    end
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and number(value, DAY * DAYS, 9007199254740991) then return value end
    end
end

function S:Initialize()
    self.ready, self.commodities = false, nil
    local db = store()
    if not db then return end
    if db.version ~= 1 then
        db.version = 1
        db.items = {}
        db.searches = {}
    end
    if type(db.items) ~= "table" then db.items = {} end
    if type(db.searches) ~= "table" then db.searches = {} end

    local valid, seen = {}, {}
    for i = 1, SEARCH_LIMIT do
        local query = self.NormalizeSearch(db.searches[i])
        if query and not seen[query:lower()] then
            valid[#valid + 1] = query
            seen[query:lower()] = true
        end
    end
    db.searches = valid
    self:Prune()
end

local function validSample(sample, oldestDay, now)
    if type(sample) ~= "table" or not number(sample.at, oldestDay * DAY, now)
        or not number(sample.price, 1, 9007199254740991) then return false end
    return true
end

function S:Prune()
    local db, now = store(), self.Now()
    if not db or not now or type(db.items) ~= "table" then return end
    local oldestDay = math.floor(now / DAY) - DAYS + 1
    local ranked = {}
    local seen = 0

    for _, entry in pairs(db.items) do
        if seen >= ITEM_LIMIT * 2 then break end
        seen = seen + 1
        if type(entry) == "table" and plain(entry.scope, 180) and plain(entry.market, 100)
            and plain(entry.item, 60) and plain(entry.name, 150) and number(entry.itemID, 1, 2147483647)
            and type(entry.samples) == "table" then
            local byDay = {}
            for i = 1, DAYS do
                local sample = entry.samples[i]
                if validSample(sample, oldestDay, now) then
                    local day = math.floor(sample.at / DAY)
                    if not byDay[day] or sample.at > byDay[day].at then
                        byDay[day] = { at = sample.at, price = sample.price }
                    end
                end
            end
            local samples = {}
            for _, sample in pairs(byDay) do samples[#samples + 1] = sample end
            table.sort(samples, function(a, b) return a.at > b.at end)
            if #samples > 0 then
                ranked[#ranked + 1] = {
                    scope = entry.scope, market = entry.market, item = entry.item, name = entry.name,
                    itemID = entry.itemID, commodity = entry.commodity == true, samples = samples,
                }
            end
        end
    end

    table.sort(ranked, function(a, b)
        local at, bt = a.samples[1].at, b.samples[1].at
        if at ~= bt then return at > bt end
        if a.scope ~= b.scope then return a.scope < b.scope end
        if a.market ~= b.market then return a.market < b.market end
        return a.item < b.item
    end)
    local bounded = {}
    for i = 1, math.min(ITEM_LIMIT, #ranked) do
        local entry = ranked[i]
        local key = entry.scope .. "|" .. entry.market .. "|" .. entry.item
        if not bounded[key] then bounded[key] = entry end
    end
    db.items = bounded
    self.ready = true
    self:Reindex()
end

function S:Reindex()
    local index = {}
    for _, entry in pairs(store().items) do
        if entry.commodity then
            local key = entry.scope .. "|" .. entry.itemID
            local old = index[key]
            if not old or entry.samples[1].at > old.samples[1].at then index[key] = entry end
        end
    end
    self.commodities = index
end

function S:GetTooltipQuote(scope, itemID)
    if not plain(scope, 180) or not number(itemID, 1, 2147483647) then return end
    if not self.ready then self:Prune() end
    if not self.commodities then return end
    local entry = self.commodities[scope .. "|" .. itemID]
    local now = self.Now()
    if entry and now and validSample(entry.samples[1], math.floor(now / DAY) - DAYS + 1, now) then
        return entry
    end
end

function S:Record(scope, market, rows)
    local db, now = store(), self.Now()
    if not db or not now or not plain(scope, 180) or not plain(market, 100) or type(rows) ~= "table" then return false end
    if not self.ready then self:Prune() end
    local day = math.floor(now / DAY)
    for _, row in ipairs(rows) do
        if type(row) == "table" and number(row.price, 1, 9007199254740991) and plain(row.name, 150)
            and plain(row.item, 60) and number(row.itemID, 1, 2147483647) then
            local key = scope .. "|" .. market .. "|" .. row.item
            local entry = db.items[key]
            if not entry then
                entry = { scope = scope, market = market, item = row.item, itemID = row.itemID, samples = {} }
                db.items[key] = entry
            end
            entry.name, entry.commodity = row.name, row.commodity
            local samples = entry.samples
            local first = samples[1]
            if first and math.floor(first.at / DAY) == day then
                first.at, first.price = now, row.price
            else
                table.insert(samples, 1, { at = now, price = row.price })
                samples[DAYS + 1] = nil
            end
        end
    end
    self:Prune()
    return true
end

function S:UpdateMetadata(scope, market, row)
    local entry = store().items[scope .. "|" .. market .. "|" .. row.item]
    if not entry then return end
    entry.name, entry.commodity = row.name, row.commodity == true
end

function S:ListHistory(scope, filter)
    local rows, now = {}, self.Now()
    if not now or not scope then return rows end
    if not self.ready then self:Prune() end
    local term = (self.NormalizeSearch(filter) or ""):lower()
    local oldestDay = math.floor(now / DAY) - DAYS + 1
    for key, entry in pairs(store().items) do
        if entry.scope == scope and validSample(entry.samples[1], oldestDay, now)
            and (term == "" or entry.name:lower():find(term, 1, true) or tostring(entry.itemID) == term) then
            rows[#rows + 1] = { key = key, entry = entry }
        end
    end
    table.sort(rows, function(a, b)
        local aTime, bTime = a.entry.samples[1].at, b.entry.samples[1].at
        if aTime ~= bTime then return aTime > bTime end
        return a.key < b.key
    end)
    return rows
end

function S:GetHistory(key)
    local db, now = store(), self.Now()
    if type(key) ~= "string" or not db or not now then return end
    if not self.ready then self:Prune() end
    local entry = db.items[key]
    if not entry then return end
    local oldestDay = math.floor(now / DAY) - DAYS + 1
    local samples = {}
    for _, sample in ipairs(entry.samples) do
        if validSample(sample, oldestDay, now) then samples[#samples + 1] = sample end
    end
    return entry, samples
end

function S:ListSearches()
    local db = store()
    return db and db.searches or {}
end

function S:SaveSearch(text)
    local value = self.NormalizeSearch(text)
    if not value then return false, "invalid" end
    local saved = self:ListSearches()
    for _, query in ipairs(saved) do
        if query:lower() == value:lower() then return false, "duplicate" end
    end
    if #saved >= SEARCH_LIMIT then return false, "full" end
    saved[#saved + 1] = value
    table.sort(saved, function(a, b) return a:lower() < b:lower() end)
    return true
end

function S:DeleteSearch(value)
    local saved = self:ListSearches()
    for i, query in ipairs(saved) do
        if query == value then table.remove(saved, i); return true end
    end
    return false
end
