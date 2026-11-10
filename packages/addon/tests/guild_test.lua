local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function with(values, fn)
    local old = {}; for key, value in pairs(values) do old[key] = _G[key]; _G[key] = value end
    local ok, err = pcall(fn)
    for key in pairs(values) do _G[key] = old[key] end
    BadbUI.Player:Invalidate()
    if not ok then error(err) end
end
local T = {}
T["scansione: solo dati del client Forever, nome completo e metadati"] = function()
    with({
        UnitName = function() return "Niko Emme" end,
        UnitClass = function() return "Mago", "MAGE" end,
        UnitLevel = function() return 23 end,
        GetServerTime = function() return 1794260000 end,
        GetInventoryItemID = function(_, slot) if slot == 16 then return 35 end end,
        GetInventoryItemLink = function(_, slot) if slot == 16 then return "item:35" end end,
        GetItemInfo = function() return "Bastone letto in gioco", "item:35", 2, 21 end,
        GetProfessions = function() return 1 end,
        GetProfessionInfo = function() return "Sartoria", nil, 113 end,
    }, function()
        BadbUI.Player:Invalidate()
        assert(BadbUI.Guild:Capture())
        local c = BadbUI_GuildExport.characters["Niko Emme"]
        eq(c.level, 23); eq(c.gear[1].id, 35); eq(c.gear[1].name, "Bastone letto in gioco")
        eq(c.professions[1].rank, 113); eq(c.scanned, 1794260000)
        eq(BadbUI_GuildExport.client.interface, 16001)
    end)
end
T["cache oggetti incompleta: non pubblica una nuova scansione falsa"] = function()
    with({ UnitLevel = function() return 23 end, GetInventoryItemID = function(_, slot) if slot == 16 then return 35 end end,
        GetItemInfo = function() return nil end }, function()
        BadbUI.Player:Invalidate()
        eq(BadbUI.Guild:Capture(), false)
    end)
end
T["client diverso: niente scansione"] = function()
    with({ GetBuildInfo = function() return "retail", "1", "", 120000 end }, function()
        eq(BadbUI.Guild:Capture(), false)
    end)
end
T["ricevute: rimuove successi e rifiuti, conserva azioni non inviate"] = function()
    BadbUI_GuildExport.actions = { { id = "ok" }, { id = "no" }, { id = "pending" } }
    BadbUI_GuildSync = { week = "2026-11-09", applied = { "ok" }, rejected = { { id = "no", error = "Raid chiuso" } } }
    BadbUI.Guild:Import()
    eq(#BadbUI_GuildExport.actions, 1); eq(BadbUI_GuildExport.actions[1].id, "pending")
end
T["coda: settimana dal server, maschere validate e limite"] = function()
    local G = BadbUI.Guild
    G.bundle = { week = "2026-11-09" }
    assert(G:Availability("001001001001001001001"))
    eq(BadbUI_GuildExport.actions[1].week, "2026-11-09")
    eq(G:Availability("bad"), false)
    eq(G:Signup("id", "invalid"), false)
    for i = #BadbUI_GuildExport.actions + 1, 200 do BadbUI_GuildExport.actions[i] = { id = tostring(i) } end
    eq(G:Signup("id", "yes"), false)
end
return T
