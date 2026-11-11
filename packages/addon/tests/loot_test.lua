local T = {}

local function withAPIs(fn)
    local previous = { C_Item = C_Item, GetNumLootItems = GetNumLootItems, GetLootSlotLink = GetLootSlotLink, GetRealZoneText = GetRealZoneText }
    local values = {
        [11] = { "Spada", "INVTYPE_WEAPON", { ITEM_MOD_STRENGTH_SHORT = 12, ITEM_MOD_STAMINA_SHORT = 5 } },
        [22] = { "Altra spada", "INVTYPE_WEAPON", { ITEM_MOD_STRENGTH_SHORT = 7, ITEM_MOD_STAMINA_SHORT = 10 } },
        [33] = { "Anello", "INVTYPE_FINGER", { ITEM_MOD_STRENGTH_SHORT = 10 } },
    }
    local requested = {}
    C_Item = {
        GetItemInfo = function(item)
            local id = tonumber(item:match("^item:(%d+)"))
            local row = values[id]
            if row then return row[1], nil, nil, nil, nil, nil, nil, nil, row[2] end
        end,
        GetItemStats = function(item)
            local row = values[tonumber(item:match("^item:(%d+)"))]
            return row and row[3]
        end,
        RequestLoadItemDataByID = function(id) requested[#requested + 1] = id end,
    }
    GetNumLootItems = function() return 3 end
    GetLootSlotLink = function(slot)
        if slot < 3 then return "|cff00ff00|Hitem:11:0:0|h[Spada]|h|r" end
    end
    GetRealZoneText = function() return "Zona di prova" end
    local ok, err = pcall(fn, BadbUI.Loot, BadbUI.LootModel, requested, values)
    C_Item = previous.C_Item
    GetNumLootItems = previous.GetNumLootItems
    GetLootSlotLink = previous.GetLootSlotLink
    GetRealZoneText = previous.GetRealZoneText
    assert(ok, err)
end

T["pesi per profilo e confronto tra oggetti equivalenti"] = function()
    withAPIs(function(m)
        local _, reason = m:Compare(11)
        assert(reason == "weights")
        m:Set("weights.strength", 2)
        m:Set("weights.stamina", 1)
        local a, b, diff = m:Compare("|cff00ff00|Hitem:11:0|h[Spada]|h|r", "22")
        assert(a and b and a.score == 29 and b.score == 24 and diff == 5)
        local _, slot = m:Compare(11, 33)
        assert(slot == "slot")
        local _, bad = m:Compare("item:11--")
        assert(bad == "invalid")
        BadbUI.DB:SetProfile("Altro")
        local _, new = m:Compare(11)
        assert(new == "weights")
    end)
end

T["richiede i dati solo su azione esplicita e gestisce API non disponibili"] = function()
    withAPIs(function(m, _, requested)
        m:Set("weights.strength", 1)
        local _, missing = m:Compare(44)
        assert(missing == "loading" and #requested == 0)
        local _, loading = m:Compare(44, nil, true)
        assert(loading == "loading" and requested[1] == 44)
        C_Item.GetItemStats = function() error("API non disponibile") end
        local _, unavailable = m:Compare(11)
        assert(unavailable == "unavailable")
    end)
end

T["osserva senza duplicare e disattiva gli eventi col modulo"] = function(Mock)
    withAPIs(function(m)
        Mock.Fire("LOOT_OPENED")
        Mock.Fire("LOOT_OPENED")
        assert(#m.store.observed == 1 and m.store.observed[1].id == 11)
        assert(m.store.observed[1].area == "Zona di prova")
        BadbUI.Modules:SetEnabled("Loot", false)
        GetRealZoneText = function() return "Altra zona" end
        Mock.Fire("LOOT_OPENED")
        assert(#m.store.observed == 1)
        assert(not m:Open())
    end)
end

T["preferiti e archivio validano e limitano i dati"] = function()
    withAPIs(function(m, model)
        assert(m:ToggleFavorite("item:11"))
        assert(m:IsFavorite(11))
        assert(m:ToggleFavorite(11) == false and not m:IsFavorite(11))
        assert(m:ToggleFavorite("x") == nil)
        local store = model.Open({ version = 1, favorites = { 1, 1, -1, "2" },
            observed = { { id = 1, area = "OK", at = 900 }, { id = "x", area = "NO", at = 900 } } }, 1000)
        assert(#store.favorites == 2 and #store.observed == 1)
        for i = 1, 250 do model.Observe(store, i, "Nuova zona", 1000) end
        assert(#store.observed == 240 and store.observed[1].id == 250)
    end)
end

T["monta la finestra e pubblica la guida"] = function(Mock)
    Mock.Methods.GetStringWidth = function() return 100 end
    Mock.Methods.GetHeight = function() return 240 end
    withAPIs(function(m)
        assert(m:Open("11"))
        assert(m.window.compare.candidate:GetText() == "11")
        assert(BadbUI.Guides:Get("loot:confronto"))
    end)
end

return T
