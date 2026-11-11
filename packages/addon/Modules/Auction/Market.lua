local _, ns = ...
local Badb = ns.Badb
local L, Compat, S = Badb.L, Badb.Compat, Badb.AuctionStore
local M = Badb.Modules:New("Auction", {
    title = L["Casa d'aste"],
    category = L["Gioco"],
    description = L["Cerca nel mercato attivo, salva le ricerche e consulta i prezzi osservati."],
    defaults = { enabled = true, tooltipPrice = false },
    replaces = {
        { addon = "Auctionator", title = "Auctionator", coverage = "partial",
          note = L["Ricerca per nome, ricerche salvate, storico locale e prezzo delle merci nel tooltip. Acquisti e inserzioni restano nella finestra Blizzard."] },
    },
})
Badb.Auction = M

local LIMIT = 120
local MAX_MONEY = 9007199254740991

local function read(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok then return Compat.SafeValue(value) end
end

function M:GetScope()
    local realm, faction = read(GetRealmName), read(UnitFactionGroup, "player")
    if S.IsPlainText(realm, 100) and S.IsPlainText(faction, 40) then
        local scope = realm .. " · " .. faction
        local region = read(GetCurrentRegion)
        if S.IsInteger(region, 1, 999) then scope = tostring(region) .. " · " .. scope end
        return scope
    end
end

function M:GetMarket()
    local zone = read(GetRealZoneText)
    if S.IsPlainText(zone, 100) then return zone end
end

function M:FormatMoney(value)
    if not S.IsInteger(value, 1, MAX_MONEY) then return L["—"] end
    local fn = C_CurrencyInfo and C_CurrencyInfo.GetCoinText
    local text = read(fn, value)
    if S.IsPlainText(text, 80) then return text end
    local gold, silver, copper = math.floor(value / 10000), math.floor(value / 100) % 100, value % 100
    return string.format(L["%d o %02d a %02d r"], gold, silver, copper)
end

function M:HasAPI()
    local api = C_AuctionHouse
    return api ~= nil and type(api.SendBrowseQuery) == "function" and type(api.GetBrowseResults) == "function"
        and type(api.IsThrottledMessageSystemReady) == "function" and type(Compat.After) == "function"
end

function M:CanSearch()
    if not self.active then return false, L["Modulo Casa d'aste disattivato."] end
    if not self:HasAPI() or not self:ObserveQueries() then return false, L["Ricerca non disponibile su questo client."] end
    if not self.atAuction then return false, L["Parla con un banditore per cercare prezzi aggiornati."] end
    if read(InCombatLockdown) ~= false then return false, L["Ricerca sospesa in combattimento."] end
    if self.pending or read(C_AuctionHouse.IsThrottledMessageSystemReady) ~= true then
        return false, L["La casa d'aste sta elaborando una richiesta. Riprova quando è pronta."]
    end
    return true
end

function M:Notify()
    Badb.Events:Fire("BADB_AUCTION_CHANGED")
end

function M:Cancel(message)
    if not self.pending then return end
    self.pending = nil
    self.status = message
    self:Notify()
end

function M:ObserveQueries()
    if self.observed == C_AuctionHouse then return true end
    if type(hooksecurefunc) ~= "function" then return false end
    local api = C_AuctionHouse
    local function external(query)
        if self.active and self.pending and (Compat.IsSecret(query) or not rawequal(query, self.pending.query)) then
            self:Cancel(L["Un'altra ricerca ha preso il controllo della casa d'aste. Avvia di nuovo la ricerca."])
        end
    end
    if not pcall(hooksecurefunc, api, "SendBrowseQuery", external) then return false end
    for _, method in ipairs({ "SearchForFavorites", "SearchForItemKeys", "RequestMoreBrowseResults", "RefreshBrowseResults" }) do
        if type(api[method]) == "function" then
            pcall(hooksecurefunc, api, method, function() external(nil) end)
        end
    end
    self.observed = api
    return true
end

function M:Search(text)
    local queryText = S.NormalizeSearch(text)
    if not queryText then return false, L["Scrivi un nome oggetto da cercare."] end
    local canSearch, reason = self:CanSearch()
    if not canSearch then return false, reason end

    local sorts = {}
    local key = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price
    if S.IsInteger(key, 0, 100) then sorts[1] = { sortOrder = key, reverseSort = false } end
    local request = {
        query = { searchString = queryText, sorts = sorts },
        scope = self:GetScope(),
        market = self:GetMarket(),
    }
    self.results, self.term, self.partial = {}, queryText, false
    self.pending, self.status = request, L["Ricerca in corso…"]
    local ok, result = pcall(C_AuctionHouse.SendBrowseQuery, request.query)
    if not ok or Compat.IsSecret(result) or result == false then
        self:Cancel(L["La casa d'aste ha rifiutato la ricerca. Riprova."])
        return false, self.status
    end

    Compat.After(12, function()
        if self.pending == request then self:Cancel(L["Il banditore non ha risposto in tempo. Riprova."]) end
    end)
    self:Notify()
    return true
end

local function metadata(key, item)
    local meta = read(C_AuctionHouse.GetItemKeyInfo, key)
    if type(meta) ~= "table" or not S.IsPlainText(meta.itemName, 150) then return end
    local commodity = Compat.SafeValue(meta.isCommodity) == true and item == (key.itemID .. ":0:0:0")
    return meta.itemName, commodity
end

local function describe(row)
    if Compat.IsSecret(row) or type(row) ~= "table" then return end
    local key = Compat.SafeValue(row.itemKey)
    local item = S.ItemKey(key)
    if not item then return end
    local name, commodity = metadata(key, item)
    local price = Compat.SafeValue(row.minPrice)
    local quantity = Compat.SafeValue(row.totalQuantity)
    return {
        item = item, itemID = key.itemID, name = name or string.format(L["Oggetto #%d"], key.itemID),
        pendingKey = not name and key or nil, commodity = commodity,
        price = S.IsInteger(price, 1, MAX_MONEY) and price or nil,
        quantity = S.IsInteger(quantity, 0, 2147483647) and quantity or nil,
    }
end

function M:RefreshMetadata(itemID)
    if not S.IsInteger(itemID, 1, 2147483647) or not C_AuctionHouse then return end
    local changed, reindex = false, false
    for _, row in ipairs(self.results) do
        if row.itemID == itemID and row.pendingKey then
            local name, commodity = metadata(row.pendingKey, row.item)
            if name then
                row.name, row.commodity, row.pendingKey = name, commodity, nil
                changed = true
                if self.resultSaved then
                    S:UpdateMetadata(self.resultScope, self.resultMarket, row)
                    reindex = reindex or commodity
                end
            end
        end
    end
    if reindex then S:Reindex() end
    if changed then self:Notify() end
end

function M:ReadResults()
    local request = self.pending
    if not request or not self.active or not self.atAuction then return end
    if read(InCombatLockdown) ~= false or request.scope ~= self:GetScope() or request.market ~= self:GetMarket() then
        self:Cancel(L["La ricerca è stata interrotta."])
        return
    end
    local raw = read(C_AuctionHouse.GetBrowseResults)
    if type(raw) ~= "table" then self:Cancel(L["Impossibile leggere i risultati della casa d'aste."]); return end

    local rows = {}
    for i = 1, math.min(#raw, LIMIT) do
        local row = describe(raw[i])
        if row then rows[#rows + 1] = row end
    end
    table.sort(rows, function(a, b)
        if a.price ~= b.price then return (a.price or math.huge) < (b.price or math.huge) end
        return a.item < b.item
    end)
    self.pending, self.status, self.results = nil, nil, rows
    self.resultScope, self.resultMarket = request.scope, request.market
    self.partial = #raw > LIMIT or read(C_AuctionHouse.HasFullBrowseResults) ~= true
    self.resultSaved = request.scope and request.market and S:Record(request.scope, request.market, rows)
    self:Notify()
end

function M:InstallTooltip()
    local processor = TooltipDataProcessor
    local itemType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    if self.tooltipHook or not processor or type(processor.AddTooltipPostCall) ~= "function"
        or not S.IsInteger(itemType, 0, 100) then return end
    self.tooltipHook = pcall(processor.AddTooltipPostCall, itemType, function(tooltip, data)
        if not self.active or self:Get("tooltipPrice") ~= true or read(InCombatLockdown) ~= false
            or tooltip ~= GameTooltip or not tooltip or read(tooltip.IsForbidden, tooltip) == true
            or Compat.IsSecret(data) or type(data) ~= "table" then return end
        local quote = S:GetTooltipQuote(self.scope, data.id)
        if not quote or type(tooltip.AddLine) ~= "function" then return end
        local sample = quote.samples[1]
        local text = string.format(L["Asta · %s (%s): %s"], quote.market, date("%Y-%m-%d", sample.at),
            self:FormatMoney(sample.price))
        local r, g, b = Badb.Theme:Get("accent")
        pcall(tooltip.AddLine, tooltip, text, r, g, b, true)
    end)
end

function M:OnInitialize()
    S:Initialize()
end

function M:OnEnable()
    self.active, self.results, self.scope = true, {}, self:GetScope()
    self.atAuction = AuctionHouseFrame and read(AuctionHouseFrame.IsVisible, AuctionHouseFrame) == true
    self:InstallTooltip()
    self:On("PLAYER_ENTERING_WORLD", function()
        self.scope = self:GetScope()
    end)
    self:On("AUCTION_HOUSE_SHOW", function()
        self.atAuction, self.status = true, nil
        self.scope = self:GetScope()
        if self:HasAPI() then self:ObserveQueries() end
        self:Notify()
    end)
    self:On("AUCTION_HOUSE_CLOSED", function()
        self.atAuction, self.pending, self.status, self.results, self.term = false, nil, nil, {}, nil
        self:Notify()
    end)
    self:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function() self:ReadResults() end)
    self:On("ITEM_KEY_ITEM_INFO_RECEIVED", function(_, itemID) self:RefreshMetadata(itemID) end)
    self:On("AUCTION_HOUSE_BROWSE_FAILURE", function()
        self:Cancel(L["La casa d'aste ha rifiutato la ricerca. Riprova."])
    end)
    self:On("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", function()
        self:Cancel(L["La casa d'aste ha rifiutato la ricerca. Riprova."])
    end)
    self:On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function() self:Notify() end)
    self:On("PLAYER_REGEN_DISABLED", function()
        self:Cancel(L["La ricerca è stata interrotta."])
        self:Notify()
    end)
    self:On("PLAYER_REGEN_ENABLED", function() self:Notify() end)
end

function M:OnDisable()
    self.active, self.pending, self.results, self.term, self.status = false, nil, {}, nil, nil
    if self.window then self.window:Hide() end
end
