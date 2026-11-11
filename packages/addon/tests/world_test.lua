local T = {}

local function eq(actual, expected)
    assert(actual == expected, ("%s ~= %s"):format(tostring(actual), tostring(expected)))
end

local function mapPoint(map, x, y)
    return { uiMapID = map, position = { x = x, y = y } }
end

local function withMap(Mock, fn)
    local oldMap, oldPoint, oldFrame = C_Map, UiMapPoint, WorldMapFrame
    local state = { map = 1, x = 0.3, y = 0.5, writes = 0, clears = 0 }
    C_Map = {
        GetBestMapForUnit = function() return state.map end,
        GetPlayerMapPosition = function()
            return { GetXY = function() return state.x, state.y end }
        end,
        GetMapInfo = function(map) return { name = map == 1 and "Vallée" or "Costa" } end,
        GetMapWorldSize = function() return 1000, 2000 end,
        GetUserWaypoint = function() return state.pin end,
        CanSetUserWaypointOnMap = function(map) return map ~= 99 end,
        SetUserWaypoint = function(point)
            state.writes = state.writes + 1
            state.pin = point
        end,
        ClearUserWaypoint = function()
            state.clears = state.clears + 1
            state.pin = nil
        end,
    }
    UiMapPoint = { CreateFromCoordinates = mapPoint }
    WorldMapFrame = nil
    local ok, err = pcall(fn, BadbUI.World, state)
    C_Map, UiMapPoint, WorldMapFrame = oldMap, oldPoint, oldFrame
    Mock.combat = false
    assert(ok, err)
end

T["salva posizione e coordinate manuali senza duplicati e usa dati indipendenti dai profili"] = function(Mock)
    withMap(Mock, function(world, state)
        local here = assert(world:AddPlayer("Accampamento"))
        eq(world:AddPlayer("Accampamento"), here)
        eq(world:Add(1, 0.3, 0.5), here)
        eq(#world:List(), 1)
        eq(world:Add(0, 0.3, 0.5), nil)
        eq(world:Add(1, math.huge, 0.5), nil)
        eq(world:Add(1, 0.3, 1.2), nil)
        eq(world:Add(1, Mock.Secret(), 0), nil)
        local other = assert(world:Add(2, 0, 1, "Confine"))
        local copy = world:List()
        eq(copy[1].id, other)
        eq(copy[2].x, state.x)
        copy[2].label = "Cambiato"
        eq(world:List()[2].label, "Accampamento")
        BadbUI.DB:SetProfile("Altro profilo")
        eq(world:List()[2].id, here)
        eq(BadbUI.DB:GetStore("world").points[2].label, "Accampamento")
    end)
end

T["importa un segnaposto e ripristina il precedente anche passando fra destinazioni"] = function(Mock)
    withMap(Mock, function(world, state)
        local previous = mapPoint(2, 0.11, 0.72)
        state.pin = previous
        local imported = assert(world:ImportNative("Precedente"))
        eq(world:List()[1].map, 2)
        eq(world:List()[1].y, 0.72)
        eq(world:PlaceNative(imported), true)
        eq(state.writes, 0)
        eq(world.native, nil)

        local first = assert(world:AddPlayer("Primo"))
        local second = assert(world:Add(1, 0.4, 0.5, "Secondo"))
        eq(world:PlaceNative(first), true)
        eq(world:PlaceNative(second), true)
        eq(state.writes, 2)
        eq(state.pin.position.x, 0.4)
        eq(world.target.id, second)
        eq(world:RestoreNative(), true)
        eq(state.pin.uiMapID, previous.uiMapID)
        eq(state.pin.position.x, previous.position.x)
        eq(state.pin.position.y, previous.position.y)
        eq(state.clears, 0)
        eq(world.native, nil)
    end)
end

T["rimuove il punto nativo soltanto se ancora riconoscibile come proprio"] = function(Mock)
    withMap(Mock, function(world, state)
        local first = assert(world:AddPlayer())
        assert(world:PlaceNative(first))
        assert(world:RestoreNative())
        eq(state.pin, nil)
        eq(state.clears, 1)

        assert(world:PlaceNative(first))
        local external = mapPoint(2, 0.3, 0.6)
        state.pin = external
        eq(world:Remove(first), true)
        eq(state.pin, external)
        eq(state.clears, 1)
        eq(world.native, nil)
        eq(world.target, nil)
        eq(#world:List(), 0)
    end)
end

T["rinvia il ripristino in combattimento e verifica il punto prima di scrivere"] = function(Mock)
    withMap(Mock, function(world, state)
        local id = assert(world:AddPlayer())
        Mock.combat = true
        eq(world:PlaceNative(id), false)
        eq(state.writes, 0)
        Mock.combat = false
        assert(world:PlaceNative(id))
        Mock.combat = true
        eq(world:Remove(id), false)
        eq(#world:List(), 1)
        BadbUI.Modules:Disable("World")
        eq(state.clears, 0)
        Mock.combat = false
        Mock.Fire("PLAYER_REGEN_ENABLED")
        eq(state.clears, 1)
        eq(#world:List(), 1)
        eq(world:Open(), false)
    end)
end

T["degrada con API assenti mappe escluse e valori segreti"] = function(Mock)
    withMap(Mock, function(world, state)
        state.x = Mock.Secret()
        eq(world:AddPlayer(), nil)
        state.x, state.y = 0, 0
        eq(world:AddPlayer(), nil)
        local blocked = assert(world:Add(99, 0.5, 0.5))
        eq(world:PlaceNative(blocked), false)
        eq(state.writes, 0)
        local id = assert(world:Add(1, 0.5, 0.5))
        state.pin = Mock.Secret()
        eq(world:ImportNative(), nil)
        eq(world:PlaceNative(id), false)
        eq(state.writes, 0)
        state.pin = nil
        C_Map.SetUserWaypoint = function() end
        eq(world:PlaceNative(id), false)
        eq(world.target, nil)
        C_Map = nil
        eq(world:PlaceNative(id), false)
        eq(world:Track(id), true)
        eq(world.target.id, id)
    end)
end

T["pulisce le righe corrotte e limita l'archivio"] = function(Mock)
    withMap(Mock, function(world)
        local store = BadbUI.DB:GetStore("world")
        store.points = {
            { id = 5, map = 1, x = 0, y = 1, label = "  |Tmalformed|t " },
            { id = 5, map = 1, x = 1, y = 0 },
            { id = 8, map = "1", x = 0, y = 1 },
            { id = 9, map = 1, x = 0/0, y = 1 },
        }
        world:OnInitialize()
        eq(#world:List(), 1)
        eq(world:List()[1].label, "Tmalformed t")
        for i = 1, 99 do assert(world:Add(1, i / 100, 0.5)) end
        eq(#world:List(), 100)
        eq(world:Add(1, 1, 0), nil)
        store.version = 2
        world:OnInitialize()
        eq(store.version, 2)
        eq(#store.points, 100)
    end)
end

T["comando accetta decimali con virgola e aggiorna finestra e HUD"] = function(Mock)
    withMap(Mock, function(world, state)
        Mock.Methods.GetHeight = function() return 200 end
        Mock.Methods.Disable = function() end
        assert(BadbUI.ConfigUI:FindPage("mod:World"))
        assert(BadbUI.Guides:Get("badb-world:waypoints"))
        WorldMapFrame = {
            IsShown = function() return true end,
            GetMapID = function() return 2 end,
        }
        local ok = BadbUI.Slash:Dispatch("waypoint 40,5 50 Passo")
        assert(ok, table.concat(Mock.chat, "\n"))
        local window = world.window
        eq(window:IsShown(), true)
        eq(world.target.label, "Passo")
        eq(world.target.x, 0.405)
        eq(window.mapInput:GetText(), "2")
        eq(window.destination:GetText(), "Passo  ·  105 iarde")
        eq(world.hud:IsShown(), true)
        assert(BadbUI.FrameManager.registry.BadbUIWaypointHUD)
        state.map = 2
        window:GetScript("OnUpdate")(window, 0.5)
        assert(window.destination:GetText():find("Vallée", 1, true))
        eq(window.destination:GetText():find("iarde", 1, true), nil)
        world:Set("hud", false)
        eq(world.hud:IsShown(), false)
        world.hud:Show()
        eq(world.hud:IsShown(), false)
    end)
end

T["registra solo TomTom come copertura parziale"] = function()
    local found = 0
    for _, entry in ipairs(BadbUI.Suite:ListCoverage()) do
        if entry.module == "World" then
            eq(entry.addon, "TomTom")
            eq(entry.coverage, "partial")
            eq(entry.removable, false)
            found = found + 1
        end
    end
    eq(found, 1)
end

return T
