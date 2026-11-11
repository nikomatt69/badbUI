local T = {}

local NOW = 1800000000
local function eq(actual, expected)
    assert(actual == expected, ("%s ~= %s"):format(tostring(actual), tostring(expected)))
end

local function item(id, count, name, variant)
    return {
        itemID = id, stackCount = count, iconFileID = 134400,
        hyperlink = name and ("|cffffffff|Hitem:%d:%d|h[%s]|h|r"):format(id, variant or 0, name),
    }
end

local function withInventory(Mock, fn)
    local old = {}
    for _, name in ipairs({ "C_Container", "C_Item", "Enum", "GetServerTime", "GetKeyRingSize", "OpenAllBags" }) do
        old[name] = _G[name]
    end
    local originalAfter = BadbUI.Compat.After
    local originalBankFrame = BankFrame
    local originalUnitName = UnitName

    local slots = {
        [0] = { item(42, 3, "Mineràle di rame"), item(42, 2, "Mineràle di rame"), size = 5 },
        [5] = { item(77, 9, "Filo"), size = 2 },
        [-2] = { item(99, 1, "Chiave"), size = 3 },
        [6] = { item(42, 8, "Mineràle di rame"), size = 4 },
        [7] = { item(43, 1, "Minerale di stagno"), size = 2 },
    }
    local readBank, readBags = 0, 0
    Enum = { BagIndex = { Backpack = 0, ReagentBag = 5, Keyring = -2, CharacterBankTab_1 = 6, CharacterBankTab_2 = 7 } }
    GetKeyRingSize = function() return slots[-2].size end
    GetServerTime = function() return NOW end
    C_Item, BankFrame = nil, nil
    C_Container = {
        GetContainerNumSlots = function(bag)
            if bag == -2 then error("GetKeyRingSize deve essere usata per il portachiavi") end
            if bag == 6 or bag == 7 then readBank = readBank + 1 else readBags = readBags + 1 end
            return slots[bag] and slots[bag].size or 0
        end,
        GetContainerItemInfo = function(bag, slot) return slots[bag][slot] end,
    }
    local bags = BadbUI.Bags
    BadbUI.Modules:Disable("Bags")
    BadbUI.Modules:Enable("Bags")
    local ok, err = pcall(fn, bags, slots, function() return readBags, readBank end)
    for _, name in ipairs({ "C_Container", "C_Item", "Enum", "GetServerTime", "GetKeyRingSize", "OpenAllBags" }) do
        _G[name] = old[name]
    end
    BadbUI.Compat.After = originalAfter
    BankFrame, UnitName = originalBankFrame, originalUnitName
    Mock.combat = false
    assert(ok, err)
end

T["raggruppa le pile identiche e cerca parole, accenti, ID e varianti"] = function(Mock)
    withInventory(Mock, function(bags, slots, reads)
        eq(select(2, reads()), 0)
        local rows = bags:Find("TESTER minerale rame", "bags")
        eq(#rows, 1)
        eq(rows[1].item.count, 5)
        eq(rows[1].live, true)
        eq(#bags:Find("99", "bags"), 1)
        eq(#bags:Find("FILO", "bags"), 1)
        eq(#bags:Find("42 stagno", "bags"), 0)
        eq(#bags:Find("[rame]", "bags"), 0)
        slots[0][3] = item(42, 1, "Mineràle di rame", 1)
        Mock.Fire("BAG_UPDATE", 0)
        rows = bags:Find("42", "bags")
        eq(#rows, 2)
        eq(rows[1].item.count, 5)
        eq(rows[2].item.count, 1)
    end)
end

T["legge le schede banca solo mentre sono aperte e ripropone l'ultima acquisizione"] = function(Mock)
    withInventory(Mock, function(bags, slots, reads)
        eq(#bags:Find("", "bank"), 0)
        Mock.Fire("BANKFRAME_OPENED")
        local rows = bags:Find("", "bank")
        eq(#rows, 2)
        eq(rows[1].live, true)
        slots[6][1].stackCount = 4
        Mock.Fire("PLAYERBANKSLOTS_CHANGED", 1)
        eq(bags:Find("42", "bank")[1].item.count, 4)
        Mock.Fire("BANKFRAME_CLOSED")
        local _, count = reads()
        slots[6][1] = nil
        Mock.Fire("PLAYERBANKSLOTS_CHANGED", 1)
        eq(select(2, reads()), count)
        rows = bags:Find("42", "bank")
        eq(rows[1].live, false)
        eq(rows[1].item.count, 4)
        eq(#bags:Find("42", "all"), 2)
        eq(BadbUI.DB:GetStore("bags").characters["Tester-Forever"].bank.time, NOW)
    end)
end

T["conserva l'archivio tra personaggi e profili senza duplicare i dati live"] = function(Mock)
    withInventory(Mock, function(bags, slots)
        local cache = BadbUI.DB:GetStore("bags")
        eq(#bags:Find("42", "all", "all"), 1)
        UnitName = function() return "Secondo" end
        slots[0][1].stackCount = 14
        Mock.Fire("PLAYER_ENTERING_WORLD")
        eq(#bags:Find("42", "all", "all"), 2)
        eq(bags:Find("42", "all", "Tester-Forever")[1].item.count, 5)
        eq(bags:Find("42", "all")[1].item.count, 16)
        BadbUI.DB:SetProfile("Inventario Due")
        eq(BadbUI.DB:GetStore("bags"), cache)
        eq(bags:Find("42", "all", "Tester-Forever")[1].live, false)
        eq(#bags:Find("42", "all", "all"), 2)
    end)
end

T["preserva l'ultima acquisizione se le API non rispondono, lanciano o espongono segreti"] = function(Mock)
    withInventory(Mock, function(bags, slots)
        slots[0][1].stackCount = Mock.Secret()
        Mock.combat = true
        Mock.Fire("BAG_UPDATE", 0)
        eq(bags:Find("42", "bags")[1].item.count, 5)
        eq(bags:Find("42", "bags")[1].live, false)
        slots[0][1].stackCount = 9
        Mock.combat = false
        Mock.Fire("PLAYER_REGEN_ENABLED")
        eq(bags:Find("42", "bags")[1].item.count, 11)
        eq(bags:Find("42", "bags")[1].live, true)
        C_Container.GetContainerNumSlots = function() error("API transitoriamente indisponibile") end
        Mock.Fire("BAG_UPDATE", 0)
        eq(bags:Find("42", "bags")[1].live, false)
        C_Container = nil
        Mock.Fire("BAG_UPDATE", 0)
        eq(bags:Find("42", "bags")[1].item.count, 11)
    end)
end

T["aggiorna il nome quando il client ha caricato i dati dell'oggetto"] = function(Mock)
    withInventory(Mock, function(bags, slots, reads)
        slots[0][3] = item(345, 1)
        Mock.Fire("BAG_UPDATE", 0)
        eq(bags:Find("345")[1].label, "Oggetto 345")
        local previousReads = reads()
        Mock.Fire("ITEM_DATA_LOAD_RESULT", 222, true)
        eq(reads(), previousReads)
        C_Item = { GetItemNameByID = function(id) if id == 345 then return "Gemma" end end }
        Mock.Fire("ITEM_DATA_LOAD_RESULT", 345, true)
        eq(bags:Find("Gemma")[1].item.id, 345)
    end)
end

T["raccoglie gli eventi a raffica e annulla gli aggiornamenti alla disattivazione"] = function(Mock)
    withInventory(Mock, function(bags, slots, reads)
        local timers = {}
        BadbUI.Compat.After = function(_, callback) timers[#timers + 1] = callback end
        local beforeBags, beforeBank = reads()
        Mock.Fire("BAG_UPDATE", 0)
        Mock.Fire("BAG_UPDATE_DELAYED")
        Mock.Fire("BANKFRAME_OPENED")
        Mock.Fire("BANKFRAME_CLOSED")
        eq(#timers, 1)
        timers[1]()
        assert(reads() > beforeBags)
        eq(select(2, reads()), beforeBank)

        Mock.Fire("BAG_UPDATE", 0)
        beforeBags = reads()
        BadbUI.Modules:Disable("Bags")
        timers[2]()
        eq(reads(), beforeBags)
        eq(#bags:Find("", "all"), 0)
        eq(bags:Open(), false)
        eq(BadbUI.DB:GetStore("bags").characters["Tester-Forever"].bags.occupied, 4)
    end)
end

T["ripulisce dati corrotti e limita la conservazione per eta e numero"] = function(Mock)
    withInventory(Mock, function(bags)
        local cache = BadbUI.DB:GetStore("bags")
        cache.characters = {}
        for i = 1, 30 do
            cache.characters["Alt" .. i] = {
                name = "Alt" .. i, realm = "Forever",
                bags = { time = NOW - i, capacity = 4, occupied = 1, items = { { id = 42, count = 1 } } },
            }
        end
        cache.characters.Expired = {
            name = "Expired", realm = "Forever",
            bags = { time = NOW - 91 * 86400, capacity = 1, occupied = 0, items = {} },
        }
        cache.characters.Broken = {
            name = "|Tbad|t", realm = "Forever",
            bags = { time = NOW, capacity = math.huge, occupied = 1, items = {} },
        }
        cache.characters.Alt1.bags.items[1].link = "|cffffffff|Hitem:123:0|h[Wrong ID]|h|r"
        bags:OnInitialize()
        eq(#bags:Find("42", "all", "all"), 25)
        eq(cache.characters.Expired, nil)
        eq(cache.characters.Broken, nil)
        eq(cache.characters.Alt30, nil)
        eq(cache.characters.Alt1.bags.items[1].link, nil)
        Mock.Fire("BAG_UPDATE", 0)
        eq(#bags:Find("42", "all", "all"), 24)
    end)
end

T["apre dalla configurazione e dalla slash con filtri e pulsante nativo combat-safe"] = function(Mock)
    withInventory(Mock, function(bags)
        Mock.Methods.GetStringWidth = function(frame) return #(frame:GetText() or "") * 6 end
        Mock.Methods.GetHeight = function() return 200 end
        local foundPage = BadbUI.ConfigUI:FindPage("mod:Bags")
        eq(foundPage.title, "Inventario")
        assert(BadbUI.Guides:Get("badb-bags:inventory"))
        assert(BadbUI.Slash:Dispatch("bags rame"))
        local window = bags.window
        eq(window.scope, "bags")
        eq(window.query, "rame")
        eq(#window.list.data, 1)

        window.tabs:Select("bank", true)
        eq(#window.list.data, 0)
        Mock.Fire("BANKFRAME_OPENED")
        eq(#window.list.data, 1)
        local called = 0
        OpenAllBags = function() called = called + 1 end
        Mock.combat = true
        window.native:GetScript("OnClick")(window.native)
        eq(called, 0)
        eq(window:IsShown(), true)
        Mock.combat = false
        window.native:GetScript("OnClick")(window.native)
        eq(called, 1)
        eq(window:IsShown(), false)
    end)
end

T["dichiara Baganator e Syndicator come coperture parziali"] = function()
    local found = {}
    for _, row in ipairs(BadbUI.Suite:ListCoverage()) do
        if row.module == "Bags" then
            eq(row.coverage, "partial")
            eq(row.removable, false)
            found[row.addon] = true
        end
    end
    assert(found.Baganator and found.Syndicator)
end

return T
