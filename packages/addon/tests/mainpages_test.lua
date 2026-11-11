-- Test delle pagine principali: Principale, Aspetto, Addon (Config/MainPages.lua)
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "atteso valore vero", 2) end end

local T = {}
local function MP() return BadbUI.MainPages end

local function find(rows, text)
    for _, r in ipairs(rows) do if r.text:find(text, 1, true) then return r end end
end
local function act(row, label)
    for _, a in ipairs(row.actions or {}) do if a.label == label then return a end end
end

T["pagine registrate: Principale, Aspetto, Addon"] = function()
    local keys = {}
    for _, rec in ipairs(BadbUI.ConfigUI:CollectPages()) do keys[rec.key] = true end
    truthy(keys.home and keys.appearance and keys.addons, "pagine mancanti")
end

T["la finestra si apre sulla pagina Principale di default"] = function()
    truthy(BadbUI.ConfigUI:Open())
    eq(BadbUI.ConfigUI.current, "home", "pagina iniziale")
    truthy(BadbUI.ConfigUI:Open("home"), "pagina home non apribile")
    truthy(BadbUI.ConfigUI:Open("appearance"), "pagina aspetto non apribile")
    truthy(BadbUI.ConfigUI:Open("addons"), "pagina addon non apribile")
end

T["azioni rapide: elenco completo, ognuna con un'azione"] = function()
    local rows = MP().quickActions()
    eq(#rows, 8)
    for _, r in ipairs(rows) do truthy(r.actions and #r.actions == 1 and type(r.actions[1].func) == "function", r.text) end
    truthy(act(find(rows, "ElvUI"), "Apply").confirm, "lo stile ElvUI deve chiedere conferma")
    truthy(act(find(rows, "Reload"), "Reload").confirm, "il reload deve chiedere conferma")
end

T["azione Applica stile ElvUI: tema e moduli"] = function()
    BadbUI.Theme:SetScheme("night")
    BadbUI.Backups.Create = function() end
    act(find(MP().quickActions(), "ElvUI"), "Apply").func()
    eq(BadbUI.Theme.state.scheme, "elvui")
end

T["azione Sblocca: alterna lo sblocco dei frame"] = function()
    local FM = BadbUI.FrameManager
    eq(FM.unlocked, false)
    act(find(MP().quickActions(), "Move and resize"), "Unlock").func()
    eq(FM.unlocked, true)
    FM:SetUnlocked(false)
end

T["righe moduli: tutti i moduli, attiva/disattiva funziona, Opzioni solo se ci sono"] = function()
    local rows = MP().moduleRows()
    eq(#rows, #BadbUI.Modules.order, "una riga per modulo")
    local r = find(rows, "ElvUI style")
    truthy(r, "ElvLook non in elenco")
    truthy(r.detail:find("enabled"))
    act(r, "Turn off").func()
    eq(BadbUI.Modules:Get("ElvLook").enabled, false)
    r = find(MP().moduleRows(), "ElvUI style")
    truthy(r.detail:find("off"), "stato non aggiornato")
    act(r, "Turn on").func()
    eq(BadbUI.Modules:Get("ElvLook").enabled, true)
    truthy(act(r, "Options"), "manca Opzioni")
end

T["righe script: stato, esegui, accendi/spegni"] = function()
    local S = BadbUI.Scripts
    S:Save("demo", { code = "script.data.ran = true", trigger = "login", enabled = false })
    local row = find(MP().scriptRows(), "demo")
    truthy(row and row.detail:find("off"))
    act(row, "Run").func()
    eq(S:Record("demo").data.ran, true)
    act(find(MP().scriptRows(), "demo"), "Turn on").func()
    eq(S:Record("demo").enabled, true)
    S:Save("rotto", { code = "error('x')" }); S:Run("rotto")
    truthy(find(MP().scriptRows(), "rotto").detail:find("error"), "errore non mostrato")
end

T["nomi con barre verticali non rompono il testo colorato"] = function()
    BadbUI.Scripts:Save("a|cffff0000b", { code = "" })
    eq(BadbUI.Scripts:Record("a|cffff0000b"), nil, "nome con | accettato")
end

T["Aspetto: tema e accento passano da Theme, valori ignoti rifiutati"] = function()
    local opts = MP().appearanceOptions()
    local byLabel = {}
    for _, o in ipairs(opts) do if o.label then byLabel[o.label] = o end end
    local scheme, accent, op = byLabel["Color scheme"], byLabel["Accent color"], byLabel["Background opacity"]
    truthy(#scheme.values >= 4, "schemi")
    scheme.set("graphite"); eq(BadbUI.Theme.state.scheme, "graphite"); eq(scheme.get(), "graphite")
    scheme.set("inesistente"); eq(BadbUI.Theme.state.scheme, "graphite")
    accent.set("jade"); eq(accent.get(), "jade")
    accent.set("custom"); eq(BadbUI.Theme.state.accent, "jade", "custom non deve cambiare l'accento")
    op.set(0.5); eq(BadbUI.Theme.state.opacity, 0.5)
    byLabel["Restore the default ElvUI theme"].func()
    eq(BadbUI.Theme.state.scheme, "elvui"); eq(BadbUI.Theme.state.accent, "elvui"); eq(BadbUI.Theme.state.opacity, 1)
end

T["Aspetto: la scala della finestra passa da ConfigUI"] = function()
    local opts = MP().appearanceOptions()
    local scale
    for _, o in ipairs(opts) do if o.label == "Scale" then scale = o end end
    scale.set(1.2)
    eq(scale.get(), 1.2)
end

local function stubAddons(names)
    local state = {}
    for _, n in ipairs(names) do state[n] = 2 end
    C_AddOns.GetNumAddOns = function() return #names end
    C_AddOns.GetAddOnInfo = function(i) local n = names[i]; return n, "Titolo " .. n, "note" end
    C_AddOns.GetAddOnEnableState = function(n) return state[n] end
    C_AddOns.IsAddOnLoaded = function(n) return state[n] == 2 end
    C_AddOns.EnableAddOn = function(n) state[n] = 2 end
    C_AddOns.DisableAddOn = function(n) state[n] = 0 end
    return state
end

T["Addon: elenco ordinato con stato, attiva/disattiva e 'serve /reload'"] = function()
    local state = stubAddons({ "Zeta", "alfa", "BadbUI" })
    local rows = MP().addonRows()
    eq(#rows, 3)
    eq(rows[1].text, "Titolo alfa", "ordine alfabetico")
    truthy(rows[1].detail:find("loaded"))
    act(rows[1], "Turn off").func()
    eq(state.alfa, 0)
    rows = MP().addonRows()
    truthy(rows[1].detail:find("off") and rows[1].detail:find("reload"), "stato o avviso reload mancanti")
    act(rows[1], "Turn on").func()
    eq(state.alfa, 2)
end

T["Addon: BadbUI non si puo' spegnere da qui"] = function()
    local state = stubAddons({ "BadbUI", "Altro" })
    local row
    for _, r in ipairs(MP().addonRows()) do if r.text:find("BadbUI", 1, true) then row = r end end
    eq(row.actions, nil, "azione disponibile su BadbUI")
    eq(MP().setAddonEnabled("BadbUI", false), false)
    eq(state.BadbUI, 2)
end

T["Addon: API assente o in errore, nessuna eccezione"] = function()
    C_AddOns.GetNumAddOns = nil; C_AddOns.GetAddOnInfo = nil
    eq(#MP().addonRows(), 0)
    C_AddOns.GetNumAddOns = function() return 2 end
    C_AddOns.GetAddOnInfo = function(i) if i == 1 then error("boom") end return "Ok", "Ok" end
    eq(#MP().addonRows(), 1, "una riga in errore non deve nascondere le altre")
end

T["Addon: nuova firma con tabella e stato di abilitazione con personaggio"] = function()
    C_AddOns.GetNumAddOns = function() return 1 end
    C_AddOns.GetAddOnInfo = function() return { name = "Tab", title = "Tabella", notes = "" } end
    C_AddOns.GetAddOnEnableState = function(a, b) if b then return 1 end return nil end -- vecchia firma (personaggio, nome)
    local r = MP().addonList()[1]
    eq(r.name, "Tab"); eq(r.title, "Tabella"); eq(r.enabled, true)
end

return T
