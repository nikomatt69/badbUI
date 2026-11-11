-- Test delle fondamenta Suite 1.0: API di estensione (Core/Extensions.lua) e registro coperture (Modules/Suite.lua)
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "atteso valore vero", 2) end end

local T = {}

-- Addon finti: installed = { Nome = { enabled = bool, loaded = bool } }
local function fakeAddons(installed)
    local off = {}
    C_AddOns.GetAddOnInfo = function(name)
        if installed[name] then return name, name, "", true, nil end
        return name, nil, nil, false, "MISSING"
    end
    C_AddOns.IsAddOnLoaded = function(name) return installed[name] and installed[name].loaded or false end
    C_AddOns.GetAddOnEnableState = function(name) return installed[name] and installed[name].enabled and 2 or 0 end
    C_AddOns.DisableAddOn = function(name) off[#off + 1] = name; if installed[name] then installed[name].enabled = false end end
    return off
end

T["API: plugin valido diventa un modulo attivo con default, comando e pagina"] = function()
    local API = BadbUI.API
    eq(API.version, 1)
    local enabledCalls = 0
    local p, err = API:RegisterPlugin({
        id = "Demo", title = "Demo plugin", version = "1.2", author = "Test", apiVersion = 1,
        module = { defaults = { size = 3 }, OnEnable = function() enabledCalls = enabledCalls + 1 end,
                   commands = { demo = { help = "demo", fn = function() end } } },
    })
    truthy(p, err)
    local m = BadbUI.Modules:Get("Plugin_Demo")
    truthy(m and m.enabled, "modulo del plugin non attivo dopo il login")
    eq(enabledCalls, 1)
    eq(m:Get("size"), 3)
    eq(m.plugin, "Demo")
    eq(API:ListPlugins()[1].id, "Demo")
    eq(API:ListPlugins()[1].enabled, true)
    BadbUI.Modules:SetEnabled("Plugin_Demo", false)
    eq(API:ListPlugins()[1].enabled, false)
end

T["API: input errati, duplicati e versione API futura rifiutati senza errori"] = function()
    local API = BadbUI.API
    for _, bad in ipairs({ false, 3, "x", {}, { id = "1abc" }, { id = "a" }, { id = "con spazi" },
                           { id = "Ok", module = "no" }, { id = "Ok", apiVersion = 99 }, { id = "Ok", apiVersion = "1" } }) do
        local p, err = API:RegisterPlugin(bad)
        eq(p, nil); eq(type(err), "string")
    end
    eq(API:RegisterPlugin(nil), nil)
    truthy(API:RegisterPlugin({ id = "Uno" }))
    local p, err = API:RegisterPlugin({ id = "Uno" })
    eq(p, nil); truthy(err:find("Uno", 1, true))
    eq(#API:ListPlugins(), 1)
end

T["API: un plugin che fallisce in OnEnable non rompe gli altri moduli"] = function()
    local p = BadbUI.API:RegisterPlugin({ id = "Rotto", module = { OnEnable = function() error("boom") end } })
    truthy(p)
    truthy(not BadbUI.Modules:Get("Plugin_Rotto").enabled)
    truthy(BadbUI.Modules:Get("Suite").enabled)
end

T["API: On isola gli errori del gestore, Off rimuove"] = function()
    local owner, hits = {}, 0
    truthy(BadbUI.API:On(owner, "BADB_TEST_EVT", function(_, v) hits = hits + v; error("boom") end))
    BadbUI.Events:Fire("BADB_TEST_EVT", 2)
    eq(hits, 2)
    BadbUI.API:Off(owner, "BADB_TEST_EVT")
    BadbUI.Events:Fire("BADB_TEST_EVT", 2)
    eq(hits, 2)
    eq(BadbUI.API:On("x", "E", function() end), nil)
end

T["API: RegisterCommand passa dal router e rifiuta i nomi riservati"] = function()
    truthy(BadbUI.API:RegisterCommand("demoext", function() end, "demo"))
    local ok = BadbUI.API:RegisterCommand("config", function() end)
    eq(ok, false)
end

T["Suite: copertura piena e parziale, addon mancanti, modulo spento"] = function()
    fakeAddons({ Borse = { enabled = true, loaded = true }, Mezzo = { enabled = true, loaded = true }, Spento = { enabled = false } })
    truthy(BadbUI.API:RegisterPlugin({ id = "Cov", module = { replaces = {
        { addon = "Borse", title = "Borse!", coverage = "full" },
        { addon = "Mezzo", coverage = "partial", note = "manca X" },
        { addon = "Spento" }, { addon = "Assente" }, { addon = "BadbUI" }, "rotto", { addon = 5 },
    } } }))
    local S = BadbUI.Suite
    local by = {}
    for _, r in ipairs(S:ListCoverage()) do by[r.addon] = r end
    eq(by.Borse.removable, true); eq(by.Borse.title, "Borse!"); eq(by.Borse.installed, true)
    eq(by.Mezzo.removable, false); eq(by.Mezzo.note, "manca X")
    eq(by.Spento.removable, false, "una copertura omessa non autorizza lo spegnimento")
    eq(by.Assente.installed, false)
    eq(by.BadbUI, nil)
    local rem = S:ListRemovable()
    eq(#rem, 1); eq(rem[1].addon, "Borse")
    eq(#S.rows(), 3)
    BadbUI.Modules:SetEnabled("Plugin_Cov", false)
    eq(#S:ListRemovable(), 0)
end

T["Suite: DisableCovered spegne solo gli addon coperti per intero e segnala il reload"] = function()
    local off = fakeAddons({ Borse = { enabled = true, loaded = true }, Mezzo = { enabled = true, loaded = true } })
    BadbUI.API:RegisterPlugin({ id = "Cov", module = { replaces = { { addon = "Borse", coverage = "full" }, { addon = "Mezzo", coverage = "partial" } } } })
    local done = BadbUI.Suite:DisableCovered()
    eq(#done, 1); eq(done[1], "Borse"); eq(off[1], "Borse")
    eq(BadbUI.Suite.pendingReload, true)
    eq(#BadbUI.Suite:DisableCovered(), 0)
end

T["Suite: inventario degli addon e azioni solo per copertura disponibile"] = function()
    fakeAddons({ Borse = { enabled = true, loaded = true }, Mezzo = { enabled = true, loaded = true } })
    BadbUI.API:RegisterPlugin({ id = "Cov", module = { replaces = {
        { addon = "Borse", coverage = "full", available = function() return false end },
        { addon = "Mezzo", coverage = "partial" },
    } } })
    BadbUI.MainPages.addonList = function()
        return { { name = "Assente", title = "Senza dichiarazione" }, { name = "BadbUI", title = "BadbUI" } }
    end
    eq(#BadbUI.Suite:ListRemovable(), 0)
    local rows = BadbUI.Suite.rows()
    eq(#rows, 3)
    eq(#rows[1].actions, 0)
    eq(#rows[2].actions, 0)
    eq(rows[3].detail, BadbUI.L["Copertura non dichiarata"])
end

T["Suite: sostituzione UIScalaMinima e ripristino scala originale"] = function(Mock)
    fakeAddons({ UIScalaMinima = { enabled = true, loaded = true } })
    local actual = 0.82
    local get, set = UIParent.GetScale, UIParent.SetScale
    UIParent.GetScale = function() return actual end
    UIParent.SetScale = function(_, value) actual = value; Mock.Fire("UI_SCALE_CHANGED") end
    local ok, err = pcall(function()
        eq(#BadbUI.Suite:ListRemovable(), 0)
        BadbUI.Slash:Dispatch("scale 0.38")
        eq(actual, 0.38)
        local removable = BadbUI.Suite:ListRemovable()
        eq(#removable, 1); eq(removable[1].addon, "UIScalaMinima")
        Mock.combat = true
        BadbUI.Slash:Dispatch("scale 0.2")
        eq(actual, 0.38)
        Mock.combat = false
        Mock.Fire("PLAYER_REGEN_ENABLED")
        eq(actual, 0.2)
        BadbUI.Modules:SetEnabled("Scaling", false)
        eq(actual, 0.82)
    end)
    UIParent.GetScale, UIParent.SetScale = get, set
    Mock.combat = false
    assert(ok, err)
end

T["Suite: API addon assenti non producono errori"] = function()
    local saved = C_AddOns
    C_AddOns = { GetAddOnMetadata = saved.GetAddOnMetadata }
    BadbUI.API:RegisterPlugin({ id = "Cov", module = { replaces = { { addon = "Borse" } } } })
    eq(#BadbUI.Suite:ListRemovable(), 0)
    eq(#BadbUI.Suite.rows(), 0)
    BadbUI.Suite.commands.suite.fn("")
    BadbUI.Suite.commands.suite.fn("disable")
    C_AddOns = saved
end

T["Suite: pagina nella categoria Gestione e nuova categoria Gioco nella sidebar"] = function()
    truthy(BadbUI.ConfigUI:FindPage("mod:Suite"), "pagina Suite non trovata")
    local found = false
    for _, c in ipairs(BadbUI.ConfigUI.CATEGORIES) do if c == BadbUI.L["Gioco"] then found = true end end
    truthy(found)
end
return T
