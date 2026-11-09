-- Test del modulo Integrations + adapter (addon terzi finti dentro il test)
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "atteso valore vero", 2) end end
local function has(s, sub, msg)
    if type(s) ~= "string" or not s:find(sub, 1, true) then
        error((msg or "sottostringa assente") .. ": '" .. tostring(sub) .. "' non in '" .. tostring(s) .. "'", 2)
    end
end

local T = {}

-- Se la TOC non carica ancora i file del modulo (checkout vecchio / stub), li carichiamo qui.
local function ensureLoaded()
    if BadbUI.Integrations and BadbUI.IntegrationAdapterDefs then return end
    local root = (arg and arg[1]) or "."
    local ns = { Badb = BadbUI }
    for _, f in ipairs({ "Modules/IntegrationAdapters.lua", "Modules/Integrations.lua" }) do
        local fh = assert(io.open(root .. "/" .. f))
        local src = fh:read("*a")
        fh:close()
        assert((loadstring or load)(src, "@" .. f))("BadbUI", ns)
    end
    BadbUI.Integrations:OnInitialize()
    BadbUI.Modules:ApplyAll()
end

local GLOBALS = { "ElvUI", "Details", "Plater", "Bartender4", "BigWigs", "DBM", "DBM_AllSavedOptions",
    "DBM_UsedProfile", "WeakAuras", "Clique", "EllesmereUI", "C_ClickBindings", "MioAddon" }

-- Ambiente pulito: nessun addon terzo, IsAddOnLoaded controllato da `loaded`.
local function setup(Mock)
    for _, k in ipairs(GLOBALS) do _G[k] = nil end
    ensureLoaded()
    local env = { loaded = {}, chat = Mock.chat }
    C_AddOns.IsAddOnLoaded = function(n) return env.loaded[n] end
    env.I = BadbUI.Integrations
    return env
end

-- AceDB finto: SetProfile crea il profilo se manca (come il vero), ResetProfile conta le chiamate.
local function fakeAce(current, profiles)
    local db = { calls = {}, current = current, sv = { profiles = {} } }
    for _, n in ipairs(profiles or { current }) do db.sv.profiles[n] = {} end
    function db:GetCurrentProfile() return self.current end
    function db:SetProfile(n)
        self.calls[#self.calls + 1] = n
        self.sv.profiles[n] = self.sv.profiles[n] or {}
        self.current = n
    end
    function db:ResetProfile() self.resets = (self.resets or 0) + 1 end
    return db
end

local function installElvUI(env, current, profiles)
    local db = fakeAce(current, profiles)
    _G.ElvUI = { { data = db } }
    env.loaded.ElvUI = true
    return db
end

local function installBackups()
    local B = { created = {} }
    function B:Create(label, kind) self.created[#self.created + 1] = { label = label, kind = kind }; return "bk" .. #self.created end
    BadbUI.Backups = B
    return B
end

local function listen(event)
    local got, owner = {}, { name = "test" }
    BadbUI.Events:On(owner, event, function(_, ...) got[#got + 1] = { ... } end)
    return got
end

local function find(list, id)
    for _, r in ipairs(list) do if r.id == id then return r end end
end

-- ---------------------------------------------------------------------------------------

T["addon assenti: loaded=false, nessun errore"] = function(Mock)
    local env = setup(Mock)
    local list = env.I:List()
    eq(#list, 10, "dieci adapter integrati")
    for _, r in ipairs(list) do eq(r.loaded, false, r.id .. " non caricato") end
    local ok, err = env.I:Capture("elvui")
    eq(ok, false); has(err, "non e' caricato")
    ok, err = env.I:Apply("elvui")
    eq(ok, false); has(err, "non e' caricato")
    ok, err = env.I:Reset("elvui")
    eq(ok, false); has(err, "non e' caricato")
    eq(env.I:Status("elvui").state, "missing")
end

T["List: ordine, campi e WeakAuras non supportato con motivo"] = function(Mock)
    local env = setup(Mock)
    local ids = {}
    for _, r in ipairs(env.I:List()) do ids[#ids + 1] = r.id end
    eq(table.concat(ids, ","), "elvui,details,plater,bartender4,bigwigs,dbm,clique,weakauras,ellesmereui,xperl", "ordine")
    local wa = find(env.I:List(), "weakauras")
    eq(wa.supported, false, "supported=false")
    truthy(wa.reason and #wa.reason > 10, "motivazione presente")
    eq(wa.hasProfile, false)
    local el = find(env.I:List(), "elvui")
    eq(el.supported, true)
    eq(el.canReset, true)
    eq(find(env.I:List(), "dbm").canReset, false, "DBM senza reset")
end

T["WeakAuras: rilevato ma solo stato"] = function(Mock)
    local env = setup(Mock)
    _G.WeakAuras = {}
    env.loaded.WeakAuras = true
    local s = env.I:Status("weakauras")
    eq(s.loaded, true); eq(s.supported, false); eq(s.state, "unsupported")
    local ok, err = env.I:Capture("weakauras")
    eq(ok, false); has(err, "WeakAuras")
    ok = env.I:Apply("weakauras")
    eq(ok, false)
end

T["ElvUI: round-trip Capture -> Apply con backup ed evento"] = function(Mock)
    local env = setup(Mock)
    local db = installElvUI(env, "Tank", { "Tank", "Healer", "Default" })
    local B = installBackups()
    local fired = listen("BADB_INTEGRATION_APPLIED")

    local ok, err = env.I:Capture("elvui")
    eq(ok, true, tostring(err))
    local rec = BadbUI.Modules:Get("Integrations"):Get("data").elvui
    eq(rec.version, 1); eq(rec.payload.profile, "Tank"); eq(type(rec.capturedAt), "number")
    eq(env.I:Status("elvui").state, "captured")
    eq(env.I:Status("elvui").hasProfile, true)

    db.current = "Healer"
    ok, err = env.I:Apply("elvui")
    eq(ok, true, tostring(err))
    eq(db.current, "Tank", "profilo ElvUI riapplicato")
    eq(#B.created, 1, "backup pre-azione"); eq(B.created[1].kind, "pre-import")
    eq(#fired, 1); eq(fired[1][1], "elvui")
end

T["Apply non modifica i dati catturati (copia del payload)"] = function(Mock)
    local env = setup(Mock)
    installElvUI(env, "Tank")
    env.I:Capture("elvui")
    env.I:RegisterAdapter({ id = "mut", addon = "M", detect = function() return true end,
        capture = function() return { profile = "A" } end,
        apply = function(p) p.profile = "MUTATO"; return true end })
    env.I:Capture("mut")
    env.I:Apply("mut")
    eq(BadbUI.Modules:Get("Integrations"):Get("data").mut.payload.profile, "A")
end

T["profilo mancante: warning, nessun errore, nessun SetProfile"] = function(Mock)
    local env = setup(Mock)
    local db = installElvUI(env, "Tank", { "Tank", "Default" })
    local fired = listen("BADB_INTEGRATION_APPLIED")
    env.I:Capture("elvui")
    db.sv.profiles.Tank = nil
    db.current = "Default"
    local ok, err, warn = env.I:Apply("elvui")
    eq(ok, true, "non e' un errore"); eq(err, nil)
    has(warn, "profilo mancante")
    eq(#db.calls, 0, "SetProfile non chiamato (creerebbe un profilo vuoto)")
    eq(#fired, 0, "nessun evento: nulla applicato")
    has(env.I:Status("elvui").lastWarning, "profilo mancante")
end

T["ElvUI: stringa di export (Distributor) per ricreare un profilo mancante"] = function(Mock)
    local env = setup(Mock)
    local db = installElvUI(env, "Tank", { "Tank", "Default" })
    local imported
    _G.ElvUI[1].GetModule = function()
        return {
            ExportProfile = function(_, name) return name, "EXPORT:" .. name end,
            ImportProfile = function(_, str) imported = str; db.sv.profiles[str:match(":(.+)")] = {}; return true end,
        }
    end
    env.I:Capture("elvui")
    eq(BadbUI.Modules:Get("Integrations"):Get("data").elvui.payload.exportString, "EXPORT:Tank")
    db.sv.profiles.Tank = nil
    db.current = "Default"
    local ok, err = env.I:Apply("elvui")
    eq(ok, true, tostring(err))
    eq(imported, "EXPORT:Tank"); eq(db.current, "Tank")
    -- export troppo grande: scartato ma la cattura riesce
    _G.ElvUI[1].GetModule = function()
        return { ExportProfile = function() return "x", string.rep("z", 50 * 1024) end }
    end
    ok = env.I:Capture("elvui")
    eq(ok, true)
    eq(BadbUI.Modules:Get("Integrations"):Get("data").elvui.payload.exportString, nil)
end

T["API parziali: metodi mancanti, nil, errori lanciati"] = function(Mock)
    local env = setup(Mock)
    env.loaded.ElvUI = true
    -- addon presente ma senza ElvUI[1]
    _G.ElvUI = {}
    local ok, err = env.I:Capture("elvui")
    eq(ok, false); has(err, "non disponibile")
    -- data senza metodi
    _G.ElvUI = { { data = {} } }
    ok, err = env.I:Capture("elvui"); eq(ok, false); has(err, "non leggibile")
    -- GetCurrentProfile ritorna nil
    _G.ElvUI = { { data = { GetCurrentProfile = function() return nil end } } }
    ok = env.I:Capture("elvui"); eq(ok, false)
    -- GetCurrentProfile lancia
    _G.ElvUI = { { data = { GetCurrentProfile = function() error("boom") end } } }
    ok = env.I:Capture("elvui"); eq(ok, false)
    -- metatable ostile: nessun errore verso il chiamante
    _G.ElvUI = setmetatable({}, { __index = function() error("ostile") end })
    ok = env.I:Capture("elvui"); eq(ok, false)
    eq(env.I:Status("elvui").loaded, true)
    -- SetProfile mancante in Apply
    local db = installElvUI(env, "Tank")
    eq(env.I:Capture("elvui"), true)
    db.SetProfile = nil
    db.current = "Altro"
    ok, err = env.I:Apply("elvui")
    eq(ok, false); has(err, "SetProfile")
    -- SetProfile che non cambia il profilo
    db.SetProfile = function() end
    db.current = "Altro"
    ok, err = env.I:Apply("elvui")
    eq(ok, false); has(err, "non ha cambiato")
    -- SetProfile che lancia
    db.SetProfile = function() error("kaboom") end
    ok, err = env.I:Apply("elvui")
    eq(ok, false); has(err, "kaboom")
end

T["Details!: profilo, ApplyProfile, API parziale e reset"] = function(Mock)
    local env = setup(Mock)
    local D = { current = "Default", profiles = { Default = true, Tank = true }, applied = {} }
    function D:GetCurrentProfileName() return self.current end
    function D:GetProfileList() return self.profiles end
    function D:ApplyProfile(n) self.applied[#self.applied + 1] = n; self.current = n end
    function D:ResetProfile(n) self.resetName = n end
    _G.Details = D
    env.loaded.Details = true
    D.current = "Tank"
    eq(env.I:Capture("details"), true)
    D.current = "Default"
    eq(env.I:Apply("details"), true)
    eq(D.current, "Tank")
    -- profilo scomparso
    D.profiles.Tank = nil; D.current = "Default"
    local ok, err, warn = env.I:Apply("details")
    eq(ok, true); has(warn, "profilo mancante"); eq(#D.applied, 1)
    -- reset
    eq(env.I:Reset("details"), true); eq(D.resetName, "Default")
    -- variante con solo GetCurrentProfile e senza ApplyProfile
    local D2 = { GetCurrentProfile = function() return "Solo" end }
    _G.Details = D2
    eq(env.I:Capture("details"), true)
    ok, err = env.I:Apply("details"); eq(ok, false); has(err, "ApplyProfile")
    ok, err = env.I:Reset("details"); eq(ok, false); has(err, "ResetProfile")
end

T["Plater, Bartender4, BigWigs: AceDB round-trip e reset"] = function(Mock)
    local env = setup(Mock)
    local dbs = {}
    for _, spec in ipairs({ { "plater", "Plater" }, { "bartender4", "Bartender4" }, { "bigwigs", "BigWigs" } }) do
        local id, glob = spec[1], spec[2]
        dbs[id] = fakeAce("Raid " .. id, { "Raid " .. id, "Altro" })
        _G[glob] = { db = dbs[id] }
        env.loaded[glob] = true
        eq(env.I:Capture(id), true, id)
        dbs[id].current = "Altro"
        eq(env.I:Apply(id), true, id)
        eq(dbs[id].current, "Raid " .. id, id)
        eq(env.I:Reset(id), true, id)
        eq(dbs[id].resets, 1, id .. " reset")
    end
end

T["DBM: profilo da DBM_UsedProfile, ApplyProfile, nessuna scrittura diretta"] = function(Mock)
    local env = setup(Mock)
    _G.DBM = { ApplyProfile = function(_, n) _G.DBM_UsedProfile = n end }
    _G.DBM_AllSavedOptions = { Default = {}, Tank = {} }
    _G.DBM_UsedProfile = "Tank"
    env.loaded["DBM-Core"] = true
    eq(env.I:Capture("dbm"), true)
    _G.DBM_UsedProfile = "Default"
    eq(env.I:Apply("dbm"), true)
    eq(_G.DBM_UsedProfile, "Tank")
    -- profilo assente
    _G.DBM_AllSavedOptions.Tank = nil; _G.DBM_UsedProfile = "Default"
    local ok, _, warn = env.I:Apply("dbm")
    eq(ok, true); has(warn, "profilo mancante"); eq(_G.DBM_UsedProfile, "Default")
    -- ApplyProfile assente: errore pulito, nessuna scrittura diretta sulle SavedVariables
    _G.DBM_AllSavedOptions.Tank = {}
    _G.DBM.ApplyProfile = nil
    local ok2, err = env.I:Apply("dbm")
    eq(ok2, false); has(err, "ApplyProfile"); eq(_G.DBM_UsedProfile, "Default")
    -- DBM_UsedProfile mancante
    _G.DBM_UsedProfile = nil
    ok2, err = env.I:Capture("dbm"); eq(ok2, false); has(err, "non determinabile")
end

T["payload troppo grande, ciclico, profondo: rifiuto chiaro, dati intatti"] = function(Mock)
    local env = setup(Mock)
    local payload
    env.I:RegisterAdapter({ id = "big", title = "Big", addon = "Big", detect = function() return true end,
        capture = function() return payload end, apply = function() return true end })
    payload = { blob = string.rep("x", 70 * 1024) }
    local ok, err = env.I:Capture("big")
    eq(ok, false); has(err, "troppo grande")
    eq(BadbUI.Modules:Get("Integrations"):Get("data").big, nil, "nulla salvato")
    -- limite rispettato appena sotto la soglia
    payload = { blob = string.rep("x", 40 * 1024) }
    eq(env.I:Capture("big"), true)
    -- ciclico
    local c = {}; c.me = c
    payload = c
    ok, err = env.I:Capture("big"); eq(ok, false); has(err, "ciclico")
    -- troppo profondo
    local deep = {}; local cur = deep
    for _ = 1, 30 do cur.n = {}; cur = cur.n end
    payload = deep
    ok, err = env.I:Capture("big"); eq(ok, false); has(err, "profonda")
    -- il record valido precedente e' ancora li'
    eq(env.I:Status("big").hasProfile, true)
    -- non-tabella e nil
    payload = "stringa"
    ok = env.I:Capture("big"); eq(ok, false)
    payload = nil
    ok = env.I:Capture("big"); eq(ok, false)
end

T["payload ripulito: funzioni, secret e NaN scartati"] = function(Mock)
    local env = setup(Mock)
    env.I:RegisterAdapter({ id = "dirty", addon = "D", detect = function() return true end,
        capture = function()
            return { keep = "si", n = 5, f = function() end, s = Mock.Secret(), nan = 0 / 0, inf = math.huge,
                nested = { a = 1, g = print }, [1] = "uno", [true] = "chiave-non-valida" }
        end, apply = function() return true end })
    eq(env.I:Capture("dirty"), true)
    local p = BadbUI.Modules:Get("Integrations"):Get("data").dirty.payload
    eq(p.keep, "si"); eq(p.n, 5); eq(p.nested.a, 1); eq(p[1], "uno")
    eq(p.f, nil); eq(p.s, nil); eq(p.nan, nil); eq(p.inf, nil); eq(p.nested.g, nil); eq(p[true], nil)
end

T["export/import del profilo BadbUI contiene i dati catturati"] = function(Mock)
    local env = setup(Mock)
    local db = installElvUI(env, "Tank", { "Tank", "Healer" })
    eq(env.I:Capture("elvui"), true)
    local DB = BadbUI.DB
    local str = DB:ExportProfile()
    eq(type(str), "string")
    local ok, err = DB:ImportProfile(str, "Copia")
    eq(ok, true, tostring(err))
    local rec = DB.sv.profiles.Copia.modules.Integrations.data.elvui
    eq(rec.payload.profile, "Tank"); eq(rec.version, 1)
    -- passando al profilo importato il payload e' riapplicabile
    DB:SetProfile("Copia", true)
    db.current = "Healer"
    eq(env.I:Apply("elvui"), true)
    eq(db.current, "Tank")
end

T["combattimento: Apply e Reset differiti a fine combattimento"] = function(Mock)
    local env = setup(Mock)
    local db = installElvUI(env, "Tank", { "Tank", "Healer" })
    eq(env.I:Capture("elvui"), true)
    db.current = "Healer"
    Mock.combat = true
    local ok, err, note = env.I:Apply("elvui")
    eq(ok, true); eq(err, nil); has(note, "differito")
    eq(db.current, "Healer", "non applicato in combattimento")
    ok, _, note = env.I:Reset("elvui")
    eq(ok, true); has(note, "differito"); eq(db.resets, nil)
    -- Capture e' di sola lettura: consentita
    db.current = "Tank"
    eq(env.I:Capture("elvui"), true)
    db.current = "Healer"
    Mock.combat = false
    Mock.Fire("PLAYER_REGEN_ENABLED")
    eq(db.current, "Tank", "applicato a fine combattimento")
    eq(db.resets, 1, "reset eseguito a fine combattimento")
end

T["combattimento: errori immediati restano immediati"] = function(Mock)
    local env = setup(Mock)
    installElvUI(env, "Tank")
    Mock.combat = true
    local ok, err = env.I:Apply("elvui")
    eq(ok, false); has(err, "nessun dato catturato")
    ok, err = env.I:Apply("nonesiste")
    eq(ok, false); has(err, "sconosciuta")
end

T["auto-apply al cambio profilo (default disattivo)"] = function(Mock)
    local env = setup(Mock)
    local db = installElvUI(env, "Tank", { "Tank", "Healer", "Default" })
    local M = BadbUI.Modules:Get("Integrations")
    eq(M:Get("autoApplyOnProfileChange"), false, "default false")
    eq(env.I:Capture("elvui"), true)
    BadbUI.DB:CopyProfile("Default", "Alt")
    db.current = "Healer"
    BadbUI.DB:SetProfile("Alt")
    eq(#db.calls, 0, "auto-apply disattivo: nessuna azione")

    BadbUI.DB:SetProfile("Default", true)
    M:Set("autoApplyOnProfileChange", true)
    BadbUI.DB:CopyProfile("Default", "Alt2")
    BadbUI.DB:SetProfile("Alt2")
    eq(#db.calls, 1, "riapplicato al cambio profilo")
    eq(db.current, "Tank")

    -- profilo senza dati catturati: niente da fare
    BadbUI.DB:SetProfile("Vuoto", true)
    BadbUI.Modules:Get("Integrations"):Set("autoApplyOnProfileChange", true)
    db.current = "Healer"
    BadbUI.DB:SetProfile("Vuoto")
    eq(db.current, "Healer")
end

T["auto-apply: differito in combattimento"] = function(Mock)
    local env = setup(Mock)
    local db = installElvUI(env, "Tank", { "Tank", "Healer" })
    local M = BadbUI.Modules:Get("Integrations")
    M:Set("autoApplyOnProfileChange", true)
    env.I:Capture("elvui")
    BadbUI.DB:CopyProfile("Default", "Alt")
    db.current = "Healer"
    Mock.combat = true
    BadbUI.DB:SetProfile("Alt")
    eq(#db.calls, 0, "in combattimento nulla")
    Mock.combat = false
    Mock.Fire("PLAYER_REGEN_ENABLED")
    eq(db.current, "Tank")
end

T["auto-apply: anti-ricorsione se l'apply provoca un cambio profilo"] = function(Mock)
    local env = setup(Mock)
    local count = 0
    env.I:RegisterAdapter({ id = "loop", addon = "L", detect = function() return true end,
        capture = function() return { x = 1 } end,
        apply = function()
            count = count + 1
            if count < 50 then BadbUI.DB:SetProfile(BadbUI.DB:GetProfileName()) end -- rilancia BADB_PROFILE_CHANGED
            return true
        end })
    BadbUI.Modules:Get("Integrations"):Set("autoApplyOnProfileChange", true)
    eq(env.I:Capture("loop"), true)
    BadbUI.DB:CopyProfile("Default", "Alt")
    BadbUI.DB:SetProfile("Alt")
    eq(count, 1, "una sola applicazione, nessun loop")
    -- Apply manuale rientrante rifiutato
    local inner
    env.I:RegisterAdapter({ id = "re", addon = "R", detect = function() return true end,
        capture = function() return { x = 1 } end,
        apply = function() inner = { env.I:Apply("re") }; return true end })
    env.I:Capture("re")
    eq(env.I:Apply("re"), true)
    eq(inner[1], false); has(inner[2], "gia' in corso")
end

T["modulo disattivato: nessun auto-apply, API ancora sicure"] = function(Mock)
    local env = setup(Mock)
    local db = installElvUI(env, "Tank", { "Tank", "Healer" })
    BadbUI.Modules:Get("Integrations"):Set("autoApplyOnProfileChange", true)
    env.I:Capture("elvui")
    BadbUI.DB:CopyProfile("Default", "Alt")
    BadbUI.DB.sv.profiles.Alt.modules.Integrations.enabled = false -- anche Alt lo tiene disattivo
    BadbUI.Modules:SetEnabled("Integrations", false)
    db.current = "Healer"
    BadbUI.DB:SetProfile("Alt")
    eq(#db.calls, 0)
    eq(#env.I:List(), 10)
end

T["adapter di terze parti e registrazione non valida"] = function(Mock)
    local env = setup(Mock)
    local applied
    local tp = { id = "tp", title = "Terzo", addon = "TP", detect = function() return true end,
        capture = function() return { v = 7 } end,
        apply = function(p) applied = p.v; return true end,
        reset = function() return true end }
    eq(env.I:RegisterAdapter(tp), true)
    local r = find(env.I:List(), "tp")
    truthy(r, "in elenco"); eq(r.loaded, true); eq(r.title, "Terzo")
    eq(env.I:Capture("tp"), true); eq(env.I:Apply("tp"), true); eq(applied, 7)
    eq(env.I:Reset("tp"), true)
    -- sostituzione: stessa posizione, nuovo comportamento
    local n = #env.I:List()
    env.I:RegisterAdapter({ id = "tp", addon = "TP", detect = function() return false end,
        capture = tp.capture, apply = tp.apply })
    eq(#env.I:List(), n); eq(find(env.I:List(), "tp").loaded, false)
    -- definizioni non valide
    for _, bad in ipairs({ "x", {}, { id = "a.b", capture = tp.capture, apply = tp.apply },
        { id = "", capture = tp.capture, apply = tp.apply }, { id = "ok", capture = tp.capture },
        { id = "ok", capture = tp.capture, apply = tp.apply, detect = 5 },
        { id = "ok", capture = tp.capture, apply = tp.apply, reset = "no" } }) do
        local ok, err = env.I:RegisterAdapter(bad)
        eq(ok, false, "definizione respinta"); truthy(err)
    end
    -- adapter solo-stato di terze parti
    eq(env.I:RegisterAdapter({ id = "info", title = "Info", supported = false, unsupportedReason = "solo stato",
        detect = function() return true end }), true)
    eq(find(env.I:List(), "info").supported, false)
    eq(select(2, env.I:Capture("info")), "solo stato")
end

T["un adapter che lancia errore non blocca gli altri"] = function(Mock)
    local env = setup(Mock)
    local db = installElvUI(env, "Tank", { "Tank", "Healer" })
    env.I:RegisterAdapter({ id = "boom", title = "Boom", addon = "B", detect = function() return true end,
        capture = function() return { a = 1 } end, apply = function() error("esplosione") end })
    env.I:RegisterAdapter({ id = "dbad", title = "DBad", addon = "D", detect = function() error("detect rotto") end,
        capture = function() return {} end, apply = function() return true end })
    eq(env.I:Capture("elvui"), true)
    eq(env.I:Capture("boom"), true)
    db.current = "Healer"
    local ok, err, applied, failed = env.I:ApplyAll({ noBackup = true })
    eq(ok, false); has(err, "esplosione")
    eq(applied, 1, "ElvUI applicato nonostante l'errore"); eq(failed, 1)
    eq(db.current, "Tank")
    has(env.I:Status("boom").lastError, "esplosione")
    -- detect che lancia: loaded=false, lastError, nessuna eccezione
    local s = env.I:Status("dbad")
    eq(s.loaded, false); has(s.lastError, "detect rotto")
    eq(#env.I:List(), 12)
    -- il Logger ha registrato l'errore
    local found = false
    for _, line in ipairs(BadbUI.Logger.buffer) do if line:find("esplosione", 1, true) then found = true end end
    truthy(found, "errore nel Logger")
    -- un apply riuscito azzera lastError
    env.I:RegisterAdapter({ id = "boom", title = "Boom", addon = "B", detect = function() return true end,
        capture = function() return { a = 1 } end, apply = function() return true end })
    eq(env.I:Apply("boom"), true)
    eq(env.I:Status("boom").lastError, nil)
end

T["apply: valori di ritorno degli adapter interpretati"] = function(Mock)
    local env = setup(Mock)
    local mode
    env.I:RegisterAdapter({ id = "ret", addon = "R", detect = function() return true end,
        capture = function() return { a = 1 } end,
        apply = function()
            if mode == "nil" then return nil end
            if mode == "nilerr" then return nil, "fallito" end
            if mode == "false" then return false end
            return true
        end })
    env.I:Capture("ret")
    mode = "nil"; eq(env.I:Apply("ret"), true, "nil = successo")
    mode = "nilerr"; local ok, err = env.I:Apply("ret"); eq(ok, false); eq(err, "fallito")
    mode = "false"; ok, err = env.I:Apply("ret"); eq(ok, false); truthy(err)
end

T["dati corrotti nel profilo: nessun errore, Cattura ripara"] = function(Mock)
    local env = setup(Mock)
    local db = installElvUI(env, "Tank")
    local mod = BadbUI.DB.profile.modules.Integrations
    -- data non e' una tabella
    mod.data = "spazzatura"
    local list = env.I:List()
    eq(find(list, "elvui").hasProfile, false)
    local ok, err = env.I:Apply("elvui")
    eq(ok, false); has(err, "corrott")
    eq(env.I:Capture("elvui"), true, "ripara data")
    eq(type(mod.data), "table"); eq(mod.data.elvui.payload.profile, "Tank")
    -- record con forme sbagliate
    local bad = { 42, "x", { version = "1", payload = {} }, { version = 1, payload = "no" }, { version = 1 }, { version = 0, payload = {} },
        { version = 1.5, payload = { profile = "Tank" } } }
    for i, rec in ipairs(bad) do
        mod.data.elvui = rec
        local s = env.I:Status("elvui")
        eq(s.hasProfile, false, "record " .. i)
        if not s.hasProfile then
            ok, err = env.I:Apply("elvui")
            eq(ok, false, "apply record " .. i)
        end
    end
    -- payload valido ma con profilo di tipo sbagliato: l'adapter rifiuta senza lanciare
    mod.data.elvui = { version = 1, payload = { profile = 5 } }
    ok, err = env.I:Apply("elvui")
    eq(ok, false); has(err, "nome profilo non valido"); eq(#db.calls, 0)
    -- versione piu' recente
    mod.data.elvui = { version = 99, payload = { profile = "Tank" } }
    ok, err = env.I:Apply("elvui")
    eq(ok, false); has(err, "piu' recente")
    -- Forget elimina il record
    eq(env.I:Forget("elvui"), true)
    eq(mod.data.elvui, nil)
    -- profilo senza tabella modulo
    BadbUI.DB.profile.modules.Integrations = nil
    eq(#env.I:List(), 10)
    ok = env.I:Capture("elvui")
    eq(ok, false, "nessun errore Lua anche senza tabella modulo")
end

T["id sconosciuti o non stringa"] = function(Mock)
    local env = setup(Mock)
    for _, bad in ipairs({ "nope", 42, true }) do
        eq(env.I:Capture(bad), false); eq(env.I:Apply(bad), false); eq(env.I:Reset(bad), false)
        eq(env.I:Forget(bad), false); eq((env.I:Status(bad)), nil)
    end
    eq(env.I:Capture(nil), false)
end

T["senza Backups l'Apply funziona; backup fallito non blocca"] = function(Mock)
    local env = setup(Mock)
    local db = installElvUI(env, "Tank", { "Tank", "Healer" })
    BadbUI.Backups = nil
    env.I:Capture("elvui")
    db.current = "Healer"
    eq(env.I:Apply("elvui"), true); eq(db.current, "Tank")
    BadbUI.Backups = { Create = function() error("disco pieno") end }
    db.current = "Healer"
    eq(env.I:Apply("elvui"), true); eq(db.current, "Tank")
    BadbUI.Backups = { Create = function() return nil end }
    db.current = "Healer"
    eq(env.I:Apply("elvui"), true)
end

T["ConfigUI: pagina con una riga per integrazione"] = function(Mock)
    local env = setup(Mock)
    local texs, btns = {}, {}
    Mock.Methods.CreateTexture = function() local t = Mock.NewObject("Texture"); texs[#texs + 1] = t; return t end
    Mock.Methods.SetEnabled = function(self, v) self.__enabled = v end
    local origCF = CreateFrame
    CreateFrame = function(kind, name, parent, tpl)
        local o = origCF(kind, name, parent, tpl)
        if kind == "Button" then btns[#btns + 1] = o end
        return o
    end
    installElvUI(env, "Tank", { "Tank", "Healer" })
    local page = env.I.page
    eq(page.category, "Strumenti"); eq(type(page.title), "string"); eq(type(page.order), "number")
    local h = page.build(Mock.NewObject("Frame"), { UI = BadbUI.ConfigUI, W = BadbUI.Widgets })
    CreateFrame = origCF
    eq(h, 34 + 10 * 46, "altezza = toggle + 10 righe")
    eq(#btns, 30, "3 pulsanti per riga")
    has(texs[1].__texture, "Waiting", "ElvUI installato ma non catturato")
end

T["ConfigUI: stati icona e pulsanti Cattura/Applica/Reset"] = function(Mock)
    local env = setup(Mock)
    local texs, btns = {}, {}
    Mock.Methods.CreateTexture = function() local t = Mock.NewObject("Texture"); texs[#texs + 1] = t; return t end
    Mock.Methods.SetEnabled = function(self, v) self.__enabled = v end
    local origCF = CreateFrame
    CreateFrame = function(kind, name, parent, tpl)
        local o = origCF(kind, name, parent, tpl)
        if kind == "Button" then btns[#btns + 1] = o end
        return o
    end
    local db = installElvUI(env, "Tank", { "Tank", "Healer" })
    local page = env.I.page
    page.build(Mock.NewObject("Frame"), {})
    CreateFrame = origCF
    local function button(row, label)
        local b = btns[(row - 1) * 3 + ({ Cattura = 1, Applica = 2, Reset = 3 })[label]]
        eq(b.__text, label)
        return b
    end
    -- riga 1 = ElvUI: installato, non catturato
    has(texs[1].__texture, "Waiting")
    eq(button(1, "Cattura").__enabled, true); eq(button(1, "Applica").__enabled, false); eq(button(1, "Reset").__enabled, true)
    -- riga 2 = Details: non installato
    has(texs[2].__texture, "NotReady")
    eq(button(2, "Cattura").__enabled, false); eq(button(2, "Applica").__enabled, false)
    -- riga 8 = WeakAuras: non supportato, reset nascosto
    eq(button(8, "Cattura").__enabled, false); eq(button(8, "Reset").__shown, false)
    -- click su Cattura
    button(1, "Cattura").__scripts.OnClick()
    has(texs[1].__texture, "Ready"); truthy(not texs[1].__texture:find("NotReady", 1, true))
    eq(button(1, "Applica").__enabled, true)
    -- click su Applica
    db.current = "Healer"
    button(1, "Applica").__scripts.OnClick()
    eq(db.current, "Tank")
    -- click su Reset (senza ConfigUI.Confirm: esegue direttamente)
    local keep = BadbUI.ConfigUI
    BadbUI.ConfigUI = nil
    button(1, "Reset").__scripts.OnClick()
    eq(db.resets, 1)
    -- con Confirm: chiede conferma prima
    local asked
    BadbUI.ConfigUI = { Confirm = function(_, text, onYes) asked = text; onYes() end, Toast = function() error("toast rotto") end }
    button(1, "Reset").__scripts.OnClick()
    has(asked, "ElvUI"); eq(db.resets, 2)
    BadbUI.ConfigUI = keep
    -- refresh dopo cambio profilo non solleva errori
    page.refresh()
end

T["comandi /badb integration"] = function(Mock)
    local env = setup(Mock)
    local db = installElvUI(env, "Tank", { "Tank", "Healer" })
    local cmd = BadbUI.Modules:Get("Integrations").commands.integration
    truthy(cmd.help and cmd.help:find("capture", 1, true))
    local function out() return table.concat(Mock.chat, "\n") end
    cmd.fn("list")
    has(out(), "elvui"); has(out(), "installato"); has(out(), "weakauras"); has(out(), "non supportato")
    cmd.fn("capture elvui")
    eq(env.I:Status("elvui").hasProfile, true)
    db.current = "Healer"
    cmd.fn({ "apply", "elvui" }) -- anche come lista
    eq(db.current, "Tank")
    cmd.fn("reset elvui")
    eq(db.resets, 1)
    cmd.fn("apply nonesiste"); has(out(), "sconosciuta")
    cmd.fn("capture"); has(out(), "uso:")
    cmd.fn("boh"); cmd.fn(nil); cmd.fn(42)
    cmd.fn("forget elvui")
    eq(env.I:Status("elvui").hasProfile, false)
end

T["gli adapter built-in sono esposti come lista in IntegrationAdapterDefs"] = function(Mock)
    local env = setup(Mock)
    local defs = BadbUI.IntegrationAdapterDefs
    eq(type(defs), "table"); eq(#defs, 10)
    for _, d in ipairs(defs) do truthy(d.id and d.title and d.detect, "def " .. tostring(d.id)) end
    eq(type(BadbUI.IntegrationAdapterHelpers.aceDBAdapter), "function")
    -- un adapter di terze parti registrato prima di OnInitialize ha la precedenza
    local M = BadbUI.Integrations
    local custom = { id = "elvui", title = "ElvUI custom", addon = "ElvUI", detect = function() return true end,
        capture = function() return {} end, apply = function() return true end }
    M:RegisterAdapter(custom)
    M:OnInitialize()
    eq(find(M:List(), "elvui").title, "ElvUI custom")
end

T["aceDBAdapter riutilizzabile per addon AceDB di terze parti"] = function(Mock)
    local env = setup(Mock)
    local db = fakeAce("P1", { "P1", "P2" })
    _G.MioAddon = { db = db }
    env.loaded.MioAddon = true
    local a = BadbUI.IntegrationAdapterHelpers.aceDBAdapter("mio", "Mio", "MioAddon", function() return _G.MioAddon.db end)
    eq(env.I:RegisterAdapter(a), true)
    eq(env.I:Capture("mio"), true)
    db.current = "P2"
    eq(env.I:Apply("mio"), true); eq(db.current, "P1")
    _G.MioAddon = nil
end

T["note e confidence esposte da List per ogni voce"] = function(Mock)
    local env = setup(Mock)
    local expect = {
        elvui = { "build Forever segnalata da una fonte", "B" },
        details = { "meter real-time limitato nelle istanze (combat log non leggibile)", "B" },
        plater = { "non verificato", "C" },
        bigwigs = { "timer dalla timeline nativa, si cattura solo il profilo", "B" },
        dbm = { "timer dalla timeline nativa, si cattura solo il profilo", "B" },
        weakauras = { "stato incerto su Forever (restrizioni stile Midnight, build non ufficiali)", "C" },
    }
    for _, r in ipairs(env.I:List()) do
        eq(type(r.note), "string", r.id .. " note"); truthy(r.note ~= "", r.id .. " nota non vuota")
        truthy(r.confidence == "A" or r.confidence == "B" or r.confidence == "C", r.id .. " confidence")
        truthy(r.confidence ~= "A", r.id .. ": tutte best-effort, mai A")
        local e = expect[r.id]
        if e then eq(r.note, e[1], r.id); eq(r.confidence, e[2], r.id) end
    end
    eq(env.I:Status("weakauras").note, expect.weakauras[1])
    -- adapter di terze parti: default "" / "C"; confidence non valida => "C"
    env.I:RegisterAdapter({ id = "tp1", detect = function() return true end, capture = function() return {} end,
        apply = function() return true end })
    local r = find(env.I:List(), "tp1")
    eq(r.note, ""); eq(r.confidence, "C")
    env.I:RegisterAdapter({ id = "tp2", note = "ciao", confidence = "B", detect = function() return true end,
        capture = function() return {} end, apply = function() return true end })
    r = find(env.I:List(), "tp2"); eq(r.note, "ciao"); eq(r.confidence, "B")
    env.I:RegisterAdapter({ id = "tp3", note = 5, confidence = "Z", detect = function() return true end,
        capture = function() return {} end, apply = function() return true end,
    })
    r = find(env.I:List(), "tp3"); eq(r.note, ""); eq(r.confidence, "C")
    -- noteFn che lancia: nessun errore
    env.I:RegisterAdapter({ id = "tp4", note = "base", noteFn = function() error("x") end,
        detect = function() return true end, capture = function() return {} end, apply = function() return true end })
    eq(find(env.I:List(), "tp4").note, "base")
end

T["Clique: AceDB round-trip e nota su C_ClickBindings"] = function(Mock)
    local env = setup(Mock)
    local db = fakeAce("Healer", { "Healer", "Altro" })
    _G.Clique = { db = db }
    env.loaded.Clique = true
    eq(env.I:Status("clique").loaded, true)
    eq(env.I:Capture("clique"), true)
    db.current = "Altro"
    eq(env.I:Apply("clique"), true); eq(db.current, "Healer")
    eq(find(env.I:List(), "clique").note, "non verificato; solo il profilo Clique")
    -- con C_ClickBindings la nota dichiara che il click casting Blizzard non e' catturabile
    _G.C_ClickBindings = {}
    has(find(env.I:List(), "clique").note, "non e' catturabile")
    -- il click casting Blizzard non viene mai letto ne' scritto da BadbUI
    _G.C_ClickBindings = setmetatable({}, { __index = function() error("non toccare") end })
    eq(env.I:Capture("clique"), true)
    _G.C_ClickBindings = nil
    _G.Clique = nil
    -- assente
    eq(env.I:Status("clique").loaded, false)
end

T["EllesmereUI: solo rilevamento"] = function(Mock)
    local env = setup(Mock)
    local s = env.I:Status("ellesmereui")
    eq(s.loaded, false); eq(s.supported, false); eq(s.state, "unsupported")
    env.loaded.EllesmereUI = true
    _G.EllesmereUI = {}
    s = env.I:Status("ellesmereui")
    eq(s.loaded, true); eq(s.supported, false)
    local ok, err = env.I:Capture("ellesmereui")
    eq(ok, false); has(err, "EllesmereUI")
    eq(env.I:Apply("ellesmereui"), false); eq(env.I:Reset("ellesmereui"), false)
    _G.EllesmereUI = nil
    -- senza IsAddOnLoaded si usa il globale
    C_AddOns.IsAddOnLoaded = nil
    _G.IsAddOnLoaded = nil
    eq(env.I:Status("ellesmereui").loaded, false)
    _G.EllesmereUI = {}
    eq(env.I:Status("ellesmereui").loaded, true)
    _G.EllesmereUI = nil
end

return T
