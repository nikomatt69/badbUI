local T = {}
local DAY = 86400

local function eq(actual, expected)
    assert(actual == expected, ("atteso %s, ottenuto %s"):format(tostring(expected), tostring(actual)))
end

local function row(id, price, level, suffix)
    return { itemKey = { itemID = id, itemLevel = level or 0, itemSuffix = suffix or 0 },
        minPrice = price, totalQuantity = 4 }
end

local function client(Mock, run)
    local c = { sent = {}, timers = {}, result = {}, ready = true, full = true, now = DAY * 25000,
        zone = "Orgrimmar", faction = "Horde", tooltipLines = {} }
    local globals = {
        C_AuctionHouse = {
            SendBrowseQuery = function(query)
                c.sent[#c.sent + 1] = query
                if c.fail then error("unavailable") end
            end,
            GetBrowseResults = function() return c.result end,
            IsThrottledMessageSystemReady = function() return c.ready end,
            HasFullBrowseResults = function() return c.full end,
            GetItemKeyInfo = function(key)
                if c.loading then return end
                return { itemName = "Oggetto " .. key.itemID, isCommodity = key.itemLevel == 0 and key.itemSuffix == 0 }
            end,
        },
        GetServerTime = function() return c.now end,
        GetRealZoneText = function() return c.zone end,
        UnitFactionGroup = function() return c.faction end,
        GetCurrentRegion = function() return 3 end,
        TooltipDataProcessor = {
            AddTooltipPostCall = function(_, callback) c.tooltip = callback end,
        },
        Enum = { AuctionHouseSortOrder = { Price = 0 }, TooltipDataType = { Item = 0 } },
        GameTooltip = {
            IsForbidden = function() return false end,
            AddLine = function(_, text) c.tooltipLines[#c.tooltipLines + 1] = text end,
        },
    }

    local previous = {}
    for k, value in pairs(globals) do
        previous[k] = _G[k]
        _G[k] = value
    end
    local after = BadbUI.Compat.After
    BadbUI.Compat.After = function(_, callback) c.timers[#c.timers + 1] = callback end

    local module = BadbUI.Auction
    BadbUI.Modules:SetEnabled(module.name, false)
    BadbUI.Modules:SetEnabled(module.name, true)

    function c:Browse(term, results)
        self.result = results
        assert(module:Search(term))
        Mock.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    end

    local ok, err = pcall(run, c, module, BadbUI.AuctionStore)
    BadbUI.Compat.After = after
    for k in pairs(globals) do _G[k] = previous[k] end
    if not ok then error(err, 0) end
end

T["ricerca esplicita invia una richiesta e ordina i risultati validi"] = function(Mock)
    client(Mock, function(c, m, store)
        Mock.Fire("AUCTION_HOUSE_SHOW")
        c.full = false
        c.result = { row(3, 600), row(4, 100), row(5, Mock.Secret()), Mock.Secret(), { itemKey = {} } }
        eq(m:Search("   minerale  "), true)
        eq(m:Search("minerale"), false)
        eq(#c.sent, 1)
        eq(c.sent[1].searchString, "minerale")
        eq(c.sent[1].sorts[1].sortOrder, 0)
        Mock.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        eq(#m.results, 3)
        eq(m.results[1].itemID, 4)
        eq(m.results[3].price, nil)
        eq(m.partial, true)
        eq(#store:ListHistory(m.scope), 2)
    end)
end

T["throttle, combattimento e ricerca assente lasciano il client intatto"] = function(Mock)
    client(Mock, function(c, m)
        eq(m:Search("rame"), false)
        Mock.Fire("AUCTION_HOUSE_SHOW")
        eq(m:Search("   "), false)
        eq(m:Search(Mock.Secret()), false)
        c.ready = false
        eq(m:Search("rame"), false)
        c.ready, Mock.combat = true, true
        eq(m:Search("rame"), false)
        eq(#c.sent, 0)

        Mock.combat = false
        c.ready = Mock.Secret()
        eq(m:Search("rame"), false)
        eq(#c.sent, 0)
    end)
end

T["ricerca esterna, chiusura e timeout invalidano le risposte pendenti"] = function(Mock)
    client(Mock, function(c, m, store)
        Mock.Fire("AUCTION_HOUSE_SHOW")
        assert(m:Search("rame"))
        C_AuctionHouse.SendBrowseQuery({ searchString = "ferro", sorts = {} })
        c.result = { row(3, 100) }
        Mock.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        eq(#store:ListHistory(m.scope), 0)

        assert(m:Search("rame"))
        Mock.Fire("AUCTION_HOUSE_CLOSED")
        Mock.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        eq(#m.results, 0)

        Mock.Fire("AUCTION_HOUSE_SHOW")
        assert(m:Search("rame"))
        for _, callback in ipairs(c.timers) do callback() end
        eq(m.pending, nil)
        assert(m.status:find("tempo"))
    end)
end

T["errori e risultati secret non propagano dati né bloccano nuove ricerche"] = function(Mock)
    client(Mock, function(c, m, store)
        Mock.Fire("AUCTION_HOUSE_SHOW")
        c.fail = true
        eq(m:Search("rame"), false)
        eq(m.pending, nil)

        c.fail = false
        c.result = Mock.Secret()
        eq(m:Search("rame"), true)
        Mock.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        eq(m.pending, nil)
        eq(#store:ListHistory(m.scope), 0)
    end)
end

T["storico per mercato e variante conserva una rilevazione al giorno"] = function(Mock)
    client(Mock, function(c, m, store)
        Mock.Fire("AUCTION_HOUSE_SHOW")
        c:Browse("oggetto", { row(5, 200), row(5, 300, 10, -4) })
        c.now = c.now + 100
        c:Browse("oggetto", { row(5, 250) })
        c.now = c.now + DAY
        c:Browse("oggetto", { row(5, 400) })
        c.zone = "Gadgetzan"
        c:Browse("oggetto", { row(5, 999) })
        eq(#store:ListHistory(m.scope), 3)
        local entry, samples = store:GetHistory(m.scope .. "|Orgrimmar|5:0:0:0")
        eq(entry.market, "Orgrimmar")
        eq(#samples, 2)
        eq(samples[1].price, 400)
        eq(samples[2].price, 250)
        eq(#store:ListHistory("altro reame"), 0)
        eq(#store:ListHistory(m.scope, "inesistente"), 0)
        c.now = c.now + DAY * 21
        eq(#store:ListHistory(m.scope), 0)
        eq(store:GetTooltipQuote(m.scope, 5), nil)
    end)
end

T["prezzo nel tooltip è facoltativo, locale e limitato alle merci senza varianti"] = function(Mock)
    client(Mock, function(c, m)
        Mock.Fire("AUCTION_HOUSE_SHOW")
        c:Browse("oggetto", { row(5, 200), row(6, 300, 10, 2) })
        c.tooltip(GameTooltip, { id = 5 })
        eq(#c.tooltipLines, 0)
        m:Set("tooltipPrice", true)
        c.tooltip(GameTooltip, { id = 5 })
        c.tooltip(GameTooltip, { id = 6 })
        c.tooltip(GameTooltip, Mock.Secret())
        eq(#c.tooltipLines, 1)
        assert(c.tooltipLines[1]:find("Orgrimmar", 1, true))

        BadbUI.DB:SetProfile("Senza tooltip")
        c.tooltip(GameTooltip, { id = 5 })
        eq(#c.tooltipLines, 1)
        BadbUI.Modules:SetEnabled(m.name, false)
        c.tooltip(GameTooltip, { id = 5 })
        eq(#c.tooltipLines, 1)
    end)
end

T["metadati in ritardo arricchiscono la rilevazione senza una nuova ricerca"] = function(Mock)
    client(Mock, function(c, m, store)
        Mock.Fire("AUCTION_HOUSE_SHOW")
        c.loading = true
        c:Browse("oggetto", { row(5, 200) })
        eq(m.results[1].name, "Oggetto #5")
        eq(store:GetTooltipQuote(m.scope, 5), nil)
        c.loading = false
        Mock.Fire("ITEM_KEY_ITEM_INFO_RECEIVED", 5)
        eq(m.results[1].name, "Oggetto 5")
        eq(#c.sent, 1)
        assert(store:GetTooltipQuote(m.scope, 5))
    end)
end

T["archivio ripulisce dati corrotti e limita le ricerche salvate"] = function(Mock)
    client(Mock, function(_, _, store)
        local db = BadbUI.DB:GetStore("auction")
        db.searches = { 12, "|Hmalformed", "   rame", "Rame", "ferro" }
        db.items = { malformed = { samples = { {} } }, broken = 88 }
        store:Initialize()
        eq(#store:ListSearches(), 2)
        eq(next(db.items), nil)
        eq(store:SaveSearch("RAME"), false)
        for i = 1, 22 do eq(store:SaveSearch("termine " .. i), true) end
        local ok, reason = store:SaveSearch("extra")
        eq(ok, false)
        eq(reason, "full")
        eq(store:DeleteSearch("ferro"), true)
        eq(store:SaveSearch("extra"), true)
    end)
end

T["archivio tiene al massimo 500 combinazioni per i prezzi"] = function(Mock)
    client(Mock, function(c, m, store)
        Mock.Fire("AUCTION_HOUSE_SHOW")
        local rows = {}
        for i = 1, 505 do rows[i] = { item = i .. ":0:0:0", itemID = i, price = i, name = "Oggetto " .. i } end
        eq(store:Record(m.scope, c.zone, rows), true)
        eq(#store:ListHistory(m.scope), 500)
    end)
end

T["la finestra si apre fuori mercato e si aggiorna con i risultati"] = function(Mock)
    client(Mock, function(c, m)
        Mock.Methods.GetStringWidth = function(self) return #(self:GetText() or "") * 6 end
        Mock.Methods.GetHeight = function() return 320 end
        Mock.Methods.Disable = function() end
        Mock.Methods.CreateLine = function() return Mock.NewObject("Line") end
        Mock.Methods.SetStartPoint = function() end
        Mock.Methods.SetEndPoint = function() end
        Mock.Methods.GetValue = function() return 0 end
        Mock.Methods.GetText = function(self) return self.__text or "" end

        assert(m:Open())
        m.window:Refresh()
        Mock.Fire("AUCTION_HOUSE_SHOW")
        c:Browse("oggetto", { row(5, 200) })
        m.window:Refresh()
        eq(#m.results, 1)
    end)
end

T["modulo, pagina e guida disponibili anche senza API del mercato"] = function()
    eq(BadbUI.Auction:Search("rame"), false)
    assert(BadbUI.ConfigUI:FindPage("mod:Auction"))
    assert(BadbUI.Guides:Get("auction:market"))
    for _, row in ipairs(BadbUI.Suite:ListCoverage()) do
        if row.addon == "Auctionator" then
            eq(row.coverage, "partial")
            eq(row.removable, false)
            return
        end
    end
    error("copertura Auctionator assente")
end

return T
