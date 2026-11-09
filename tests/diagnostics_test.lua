-- Test del modulo Diagnostics
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end

local function truthy(v, msg) if not v then error(msg or "atteso valore vero", 2) end end

-- Sostituzioni di globali/campi con ripristino automatico a fine test (i globali non devono trapelare
-- nelle altre suite).
local saved = {}
local function set(tbl, key, value)
    saved[#saved + 1] = { tbl, key, tbl[key] }
    tbl[key] = value
end
local function restoreAll()
    for i = #saved, 1, -1 do local s = saved[i]; s[1][s[2]] = s[3] end
    saved = {}
end

local function find(results, id)
    for _, r in ipairs(results) do if r.id == id then return r end end
end

local function findPrefix(results, prefix)
    for _, r in ipairs(results) do if r.id:sub(1, #prefix) == prefix then return r end end
end

-- IsAddOnLoaded finto: loaded = { NomeCartella = true }
local function fakeAddons(loaded)
    set(C_AddOns, "IsAddOnLoaded", function(n) return loaded[n] == true end)
end

-- Error handler finto con stato osservabile.
local function fakeErrorHandler()
    local st = { calls = {} }
    st.prev = function(msg) st.calls[#st.calls + 1] = msg end
    st.current = st.prev
    set(_G, "geterrorhandler", function() return st.current end)
    set(_G, "seterrorhandler", function(f) st.current = f end)
    BadbUI.Modules:SetEnabled("Diagnostics", false)
    BadbUI.Modules:SetEnabled("Diagnostics", true)
    return st
end

local T = {}

T["il modulo e' registrato con pagina e comandi"] = function()
    local D = BadbUI.Diagnostics
    truthy(D, "Badb.Diagnostics mancante")
    eq(BadbUI.Modules:Get("Diagnostics"), D)
    eq(D.page.category, "Strumenti")
    truthy(D.commands.doctor and D.commands.role, "comandi doctor e role")
end

T["RunChecks: struttura dei risultati e DB integro"] = function()
    local D = BadbUI.Diagnostics
    local res = D:RunChecks()
    truthy(#res >= 6, "piu' controlli")
    for _, r in ipairs(res) do
        truthy(type(r.id) == "string" and r.id ~= "", "id")
        truthy(r.level == "ok" or r.level == "warn" or r.level == "error", "livello " .. tostring(r.level))
        truthy(type(r.title) == "string", "titolo")
        truthy(r.fix == nil or type(r.fix) == "function", "fix funzione o nil")
    end
    eq(find(res, "db").level, "ok", "DB sano")
    truthy(find(res, "restrictions"), "check restrizioni Forever")
    eq(find(res, "restrictions").level, "ok", "informativo")
end

T["DB corrotto: rilevato e riparato con backup, senza perdere dati utente"] = function()
    local D, B = BadbUI.Diagnostics, BadbUI.Backups
    local sv, DB = BadbUIDB, BadbUI.DB
    DB.profile.modules.Hider.marker = "dato utente"
    sv.profiles.Rotto = 5
    sv.profiles.Parziale = { modules = "x", frames = { A = { x = 1 }, B = "no" } }
    sv.profileKeys["Altro - Reame"] = "Inesistente"
    sv.specProfiles["Altro - Reame"] = { [1] = "Default", [2] = "Inesistente", x = "Default" }
    sv.global.backups = "rotto"
    local res = D:RunChecks()
    local issues = {}
    for _, r in ipairs(res) do if r.id:sub(1, 3) == "db:" then issues[#issues + 1] = r end end
    truthy(#issues >= 6, "tutti i problemi segnalati, trovati " .. #issues)
    for _, r in ipairs(issues) do
        eq(r.level, "error"); truthy(r.fix, "fix presente per " .. r.id)
    end
    local before = #B:List()
    -- ogni riparazione crea prima un backup
    local first = issues[1]
    local ok, msg = first.fix()
    eq(ok, true, tostring(msg))
    -- (il backup si fa su dati gia' sporchi ma validi come snapshot: profili non-tabella vengono scartati dalla copia)
    local kinds = {}
    for _, e in ipairs(B:List()) do kinds[e.kind] = (kinds[e.kind] or 0) + 1 end
    truthy((kinds["pre-repair"] or 0) >= 1, "backup pre-repair creato")
    truthy(#B:List() > before)
    for i = 2, #issues do
        local ok2, m2 = issues[i].fix()
        eq(ok2, true, issues[i].id .. ": " .. tostring(m2))
    end
    local again = D:RunChecks()
    eq(find(again, "db").level, "ok", "DB riparato")
    eq(DB.profile.modules.Hider.marker, "dato utente", "i dati utente restano")
    eq(type(sv.profiles.Rotto), "table"); eq(sv.profiles.Parziale.frames.A.x, 1, "voci valide conservate")
    eq(sv.profiles.Parziale.frames.B, nil)
    eq(sv.profileKeys["Altro - Reame"], nil)
    eq(sv.specProfiles["Altro - Reame"][1], "Default")
    eq(sv.specProfiles["Altro - Reame"][2], nil)
    eq(type(sv.global.backups), "table")
end

T["riparazione del profilo attivo corrotto ricollega DB.profile"] = function()
    local D, DB = BadbUI.Diagnostics, BadbUI.DB
    DB.sv.profiles.Default.modules = "guasto"
    local r = findPrefix(D:RunChecks(), "db:profile:Default")
    truthy(r, "problema rilevato")
    eq(r.fix(), true)
    eq(type(DB.profile.modules), "table")
    eq(DB.profile, DB.sv.profiles.Default)
    eq(DB:Get("Hider", "enabled"), true, "default rimessi")
    eq(find(D:RunChecks(), "db").level, "ok")
end

T["riparazione: senza Backups copia locale; con backup fallito si ferma"] = function()
    local D, DB = BadbUI.Diagnostics, BadbUI.DB
    DB.sv.profileKeys.Fantasma = "Nulla"
    local B = BadbUI.Backups
    set(B, "Create", function() return nil, "disco pieno" end)
    local r = findPrefix(D:RunChecks(), "db:profileKeys")
    local ok, err = r.fix()
    eq(ok, false); truthy(tostring(err):find("disco pieno"))
    eq(DB.sv.profileKeys.Fantasma, "Nulla", "nulla modificato se il backup fallisce")
    restoreAll()
    set(BadbUI, "Backups", nil)
    r = findPrefix(D:RunChecks(), "db:profileKeys")
    eq(r.fix(), true)
    eq(DB.sv.profileKeys.Fantasma, nil)
    truthy(D._safetySnapshot and D._safetySnapshot.profiles, "snapshot locale in memoria")
end

T["client: interface vs TOC, Edit Mode e Settings"] = function()
    local D, Compat = BadbUI.Diagnostics, BadbUI.Compat
    set(C_AddOns, "GetAddOnMetadata", function(_, field) if field == "Interface" then return "16001" end return "test" end)
    set(Compat, "hasEditMode", true); set(Compat, "hasSettings", true)
    local res = D:RunChecks()
    eq(find(res, "client").level, "ok"); eq(find(res, "api").level, "ok")
    set(Compat, "interface", 99999)
    res = D:RunChecks()
    eq(find(res, "client").level, "warn"); truthy(find(res, "client").detail:find("TOC"))
    set(Compat, "interface", 16001); set(Compat, "isForever", false)
    eq(find(D:RunChecks(), "client").level, "warn", "client non Forever")
    set(Compat, "hasEditMode", false); set(Compat, "hasSettings", false)
    local api = find(D:RunChecks(), "api")
    eq(api.level, "warn"); truthy(api.detail:find("Edit Mode") and api.detail:find("Settings API"))
end

T["moduli: stato nel profilo ed errori del Logger per modulo"] = function()
    local D = BadbUI.Diagnostics
    eq(find(D:RunChecks(), "modules").level, "ok", "tutto in ordine")
    -- attivo nel profilo ma non in esecuzione
    BadbUI.Modules:Disable("Hider")
    local res = D:RunChecks()
    eq(find(res, "module:Hider").level, "warn")
    BadbUI.Modules:Enable("Hider")
    -- errori nel buffer del Logger, attribuiti per prefisso
    BadbUI.Logger:Error("Cooldowns:OnEnable - boom %s", "x")
    BadbUI.Logger:Error("Cooldowns:ApplyAll - boom 2")
    BadbUI.Logger:Error("Listener Hider su QUALCOSA: errore")
    BadbUI.Logger:Error("messaggio senza modulo")
    res = D:RunChecks()
    local cd = find(res, "module:Cooldowns")
    eq(cd.level, "error"); truthy(cd.title:find("Cooldowns")); truthy(cd.detail:find("2 errore"))
    eq(find(res, "module:Hider").level, "error", "formato Listener riconosciuto")
    truthy(find(res, "module:generic"), "errori non attribuiti")
    eq(find(res, "modules"), nil)
    local stats = D:GetStats()
    eq(stats.modules.Cooldowns.errors, 2)
    truthy(stats.modules.Cooldowns.dataBytes > 0)
end

T["conflitti: addon di interfaccia simulati con IsAddOnLoaded finto"] = function()
    local D = BadbUI.Diagnostics
    fakeAddons({})
    local res = D:RunChecks()
    eq(find(res, "conflicts").level, "ok"); eq(find(res, "conflicts").title, "Nessun conflitto noto")

    fakeAddons({ ElvUI = true, Bartender4 = true, OmniCC = true, ClassicUI_Forever = true, EllesmereUI = true, Clique = true })
    res = D:RunChecks()
    local elv = find(res, "conflict:ElvUI")
    eq(elv.level, "warn"); truthy(elv.detail:find("ActionBars") and elv.detail:find("Cooldowns"))
    local bt = find(res, "conflict:Bartender4")
    eq(bt.level, "warn"); truthy(bt.detail:find("ActionBars"))
    local omni = find(res, "conflict:OmniCC")
    eq(omni.level, "warn"); truthy(omni.detail:find("Cooldowns"))
    truthy(find(res, "conflict:ClassicUI Forever"), "variante del nome cartella")
    truthy(find(res, "conflict:EllesmereUI"), "EllesmereUI")
    eq(find(res, "conflict:Dominos"), nil, "non caricato -> nessuna voce")
    eq(find(res, "conflicts"), nil)
    -- con il modulo spento il conflitto non c'e' piu'
    BadbUI.Modules:Disable("Cooldowns")
    res = D:RunChecks()
    eq(find(res, "conflict:OmniCC").level, "ok")
    eq(find(res, "conflict:ElvUI").level, "warn", "ElvUI tocca anche altri moduli")
    -- API assente
    set(C_AddOns, "IsAddOnLoaded", nil)
    set(_G, "IsAddOnLoaded", nil)
    eq(find(D:RunChecks(), "conflicts").level, "warn")
end

T["CVar countdownForCooldowns coerente col modulo Cooldowns"] = function(Mock)
    local D = BadbUI.Diagnostics
    eq(Mock.cvars.countdownForCooldowns, "1")
    eq(find(D:RunChecks(), "cvar").level, "ok")
    Mock.cvars.countdownForCooldowns = "0"
    local r = find(D:RunChecks(), "cvar")
    eq(r.level, "warn"); truthy(r.fix)
    eq(r.fix(), true)
    eq(Mock.cvars.countdownForCooldowns, "1")
    eq(find(D:RunChecks(), "cvar").level, "ok")
    -- modulo spento: nessuna pretesa sulla CVar
    BadbUI.Modules:SetEnabled("Cooldowns", false)
    Mock.cvars.countdownForCooldowns = "0"
    eq(find(D:RunChecks(), "cvar").level, "ok")
end

T["dimensione DB: avviso oltre ~2 MB"] = function()
    local D, DB = BadbUI.Diagnostics, BadbUI.DB
    eq(find(D:RunChecks(), "size").level, "ok")
    DB.sv.global.blob = string.rep("x", 2.2 * 1024 * 1024)
    local r = find(D:RunChecks(), "size")
    eq(r.level, "warn"); truthy(r.detail:find("KB"))
end

T["frame registrati che non si risolvono"] = function()
    local D, FM = BadbUI.Diagnostics, BadbUI.FrameManager
    FM:Register("OkFrame", { frame = CreateFrame("Frame", "BadbDiagOk") })
    FM:Register("OkByName", { frame = "BadbDiagOk" })
    local base = find(D:RunChecks(), "frames")
    -- i frame Blizzard non esistono nel mock: baseline gia' con avviso, ma i nostri non sono elencati
    eq(base.level, "warn")
    truthy(not base.detail:find("OkFrame") and not base.detail:find("OkByName"), "frame esistenti non segnalati")
    FM:Register("Fantasma", { frame = "FrameCheNonEsiste" })
    truthy(find(D:RunChecks(), "frames").detail:find("Fantasma"), "frame inesistente segnalato")
    -- registro vuoto
    FM.registry = {}
    eq(find(D:RunChecks(), "frames").level, "ok")
end

T["un check che lancia errore diventa un risultato 'check fallito'"] = function()
    local D = BadbUI.Diagnostics
    table.insert(D.checks, { id = "boom", fn = function() error("kaboom") end })
    table.insert(D.checks, { id = "strano", fn = function() return { 1, "x", { level = "boh", title = 5, fix = "non funzione" } } end })
    table.insert(D.checks, { id = "nil", fn = function() return nil end })
    local res
    local ok = pcall(function() res = D:RunChecks() end)
    eq(ok, true, "RunChecks non propaga")
    local r = find(res, "boom")
    eq(r.level, "error"); truthy(r.title:find("Check fallito")); truthy(r.detail:find("kaboom"))
    truthy(find(res, "db"), "gli altri controlli girano comunque")
    local weird = find(res, "strano")
    eq(weird.level, "warn", "livello sconosciuto normalizzato"); eq(weird.fix, nil)
    eq(D:Report():find("Check fallito") ~= nil, true, "visibile anche nel report")
end

T["handler errori: non distruttivo, filtra BadbUI, inoltra, ripristina"] = function()
    local D = BadbUI.Diagnostics
    local st = fakeErrorHandler()
    truthy(st.current ~= st.prev, "handler concatenato installato")
    st.current("Interface\\AddOns\\BadbUI\\Core\\Foo.lua:10: boom")
    st.current("Interface\\AddOns\\AltroAddon\\x.lua:3: non nostro")
    eq(#st.calls, 2, "tutto inoltrato all'handler precedente")
    eq(#D:GetErrors(), 1, "solo l'errore BadbUI e' catturato")
    -- stack con BadbUI anche se il messaggio non lo cita
    set(_G, "debugstack", function() return "[string]:1\nInterface\\AddOns\\BadbUI\\Modules\\X.lua:5" end)
    st.current("errore generico senza percorso")
    eq(#D:GetErrors(), 2, "filtrato per stack")
    -- ripristino
    BadbUI.Modules:SetEnabled("Diagnostics", false)
    eq(st.current, st.prev, "handler originale ripristinato in OnDisable")
    st.prev("x")
end

T["handler errori: deduplica e buffer circolare da 50"] = function()
    local D = BadbUI.Diagnostics
    local st = fakeErrorHandler()
    for _ = 1, 3 do st.current("BadbUI: stesso errore") end
    local list = D:GetErrors()
    eq(#list, 1); eq(list[1].count, 3, "contatore")
    for i = 1, 60 do st.current("BadbUI: errore " .. i) end
    list = D:GetErrors()
    eq(#list, 50, "massimo 50")
    eq(list[1].msg, "BadbUI: errore 60", "piu' recente prima")
    eq(list[50].msg, "BadbUI: errore 11", "i piu' vecchi scartati")
    st.current("BadbUI: errore 60")
    eq(D:GetErrors()[1].count, 2, "dedup anche dopo la rotazione")
    D:ClearErrors()
    eq(#D:GetErrors(), 0)
    -- il check segnala gli errori
    st.current("Interface\\AddOns\\BadbUI\\Modules\\Hider.lua:12: boom")
    local r = find(D:RunChecks(), "luaerrors")
    eq(r.level, "error"); truthy(r.detail:find("boom"))
    eq(D:GetErrors()[1].module, "Hider", "associato al modulo dal percorso")
end

T["handler errori: mai crash (input strani, handler precedente che lancia)"] = function()
    local D = BadbUI.Diagnostics
    local st = fakeErrorHandler()
    st.prev = nil
    local boomPrev = function() error("il precedente esplode") end
    st.current = boomPrev
    BadbUI.Modules:SetEnabled("Diagnostics", false)
    BadbUI.Modules:SetEnabled("Diagnostics", true)
    local h = st.current
    eq(pcall(h, nil), true); eq(pcall(h, {}), true); eq(pcall(h, 42), true)
    eq(pcall(h, setmetatable({}, { __tostring = function() error("x") end })), true)
    eq(pcall(h, string.rep("BadbUI", 5000)), true)
    truthy(#D:GetErrors()[1].msg <= 1000, "messaggi troncati")
    -- nessun handler precedente
    BadbUI.Modules:SetEnabled("Diagnostics", false)
    st.current = nil
    BadbUI.Modules:SetEnabled("Diagnostics", true)
    eq(pcall(st.current, "BadbUI: x"), true)
    BadbUI.Modules:SetEnabled("Diagnostics", false)
end

T["handler errori: se qualcuno si concatena dopo di noi non lo rimuoviamo"] = function()
    local D = BadbUI.Diagnostics
    local st = fakeErrorHandler()
    local ours = st.current
    local seen = 0
    local theirs = function(msg, ...) seen = seen + 1; return ours(msg, ...) end
    st.current = theirs
    BadbUI.Modules:SetEnabled("Diagnostics", false)
    eq(st.current, theirs, "l'handler altrui resta")
    local before = #D:GetErrors()
    st.current("BadbUI: dopo la disattivazione")
    eq(#D:GetErrors(), before, "il nostro e' inerte")
    eq(seen, 1); eq(#st.calls, 1, "ma la catena originale funziona ancora")
end

T["senza seterrorhandler il modulo si abilita comunque"] = function()
    set(_G, "seterrorhandler", nil); set(_G, "geterrorhandler", nil)
    BadbUI.Modules:SetEnabled("Diagnostics", false)
    BadbUI.Modules:SetEnabled("Diagnostics", true)
    eq(BadbUI.Modules:Get("Diagnostics").enabled, true)
end

T["PlayerInfo: avvisi con talenti illeggibili e ruolo incerto, ok quando noto"] = function()
    local D, P = BadbUI.Diagnostics, BadbUI.Player
    set(_G, "UnitClass", function() return "Paladino", "PALADIN", 2 end)
    P:Invalidate()
    local res = D:RunChecks()
    local tal, role = find(res, "playerinfo:talents"), find(res, "playerinfo:role")
    eq(tal.level, "warn"); truthy(tal.detail:find("/badb role"))
    eq(role.level, "warn"); truthy(role.detail:find("/badb role"))
    -- con talenti leggibili il ruolo e' dedotto dall'albero
    set(_G, "GetNumTalentTabs", function() return 3 end)
    local pts = { 0, 31, 0 }
    local names = { "Holy", "Protection", "Retribution" }
    set(_G, "GetTalentTabInfo", function(i) return names[i], "icon", pts[i] end)
    P:Invalidate()
    res = D:RunChecks()
    eq(find(res, "playerinfo").level, "ok")
    truthy(find(res, "playerinfo").detail:find("tank"))
    eq(find(res, "playerinfo:talents"), nil)
    -- un override esplicito porta la confidenza ad alta anche senza talenti
    set(_G, "GetNumTalentTabs", nil)
    P:SetRoleOverride("healer")
    res = D:RunChecks()
    eq(find(res, "playerinfo:role"), nil, "confidenza alta con override")
    truthy(find(res, "playerinfo:talents"), "talenti ancora illeggibili")
end

T["comando role: validato contro i ruoli della classe"] = function()
    local D, P = BadbUI.Diagnostics, BadbUI.Player
    local cmd = D.commands.role.fn
    set(_G, "UnitClass", function() return "Paladino", "PALADIN", 2 end)
    P:Invalidate()
    cmd("tank")
    eq(P:GetRole(), "tank"); eq(select(2, P:GetRole()), "override")
    cmd("healer")
    eq(P:GetRole(), "healer")
    cmd("auto")
    eq(select(2, P:GetRole()), "class", "override rimosso")
    cmd("boh"); cmd("  "); cmd(nil)
    eq(select(2, P:GetRole()), "class", "ruolo invalido ignorato")
    -- un Mago non puo' essere tank
    set(_G, "UnitClass", function() return "Mago", "MAGE", 8 end)
    P:Invalidate()
    cmd("tank")
    eq(P:GetRole(), "dps"); eq(select(2, P:GetRole()), "class")
    cmd("dps")
    eq(select(2, P:GetRole()), "override")
end

T["Report: completo e senza dati personali"] = function(Mock)
    local D, DB, L = BadbUI.Diagnostics, BadbUI.DB, BadbUI.Logger
    set(_G, "UnitName", function() return "Tester" end)
    set(_G, "GetRealmName", function() return "Azeroth Prime" end)
    set(_G, "UnitClass", function() return "Paladino", "PALADIN", 2 end)
    BadbUI.Player:Invalidate()
    DB.profile.modules.Hider.segreto = "SEGRETO123"
    DB.sv.profiles.Default.modules.Hider.altro = { x = "PAYLOAD987" }
    fakeAddons({ ElvUI = true })
    L:Warn("sessione di Tester su Azeroth Prime")
    L:Error("Hider: fallito per Tester-Azeroth Prime")
    local st = fakeErrorHandler()
    st.current("BadbUI: errore con Tester dentro")
    for i = 1, 40 do L:Info("LOGLINE %d", i) end
    set(_G, "GetAddOnMemoryUsage", function() return 1234.5 end)
    set(_G, "UpdateAddOnMemoryUsage", function() end)
    local rep = D:Report()
    eq(type(rep), "string")
    truthy(rep:find("BadbUI v", 1, true), "versione addon")
    truthy(rep:find("interface 16001", 1, true), "interface")
    truthy(rep:find("Locale: itIT", 1, true), "locale")
    truthy(rep:find("Profilo attivo: Default", 1, true), "profilo attivo")
    truthy(rep:find("Moduli:", 1, true) and rep:find("Hider: ", 1, true), "moduli")
    truthy(rep:find("Controlli:", 1, true) and rep:find("[OK]", 1, true), "controlli")
    truthy(rep:find("ElvUI", 1, true), "addon di interfaccia")
    truthy(rep:find("Personaggio: #%x%x%x%x%x%x"), "hash corto del personaggio")
    truthy(rep:find("PALADIN", 1, true) and rep:find("ruolo", 1, true), "snapshot PlayerInfo")
    truthy(rep:find("Talenti:", 1, true), "talenti")
    truthy(rep:find("Memoria addon: 1235 KB") or rep:find("Memoria addon: 1234 KB"), "memoria")
    truthy(rep:find("LOGLINE 40", 1, true) and rep:find("LOGLINE 21", 1, true), "ultimi log")
    truthy(not rep:find("LOGLINE 20", 1, true) and not rep:find("LOGLINE 19", 1, true), "solo gli ultimi 20 log")
    truthy(rep:find("Errori Lua catturati (1)", 1, true), "errori catturati")
    -- privacy
    truthy(not rep:find("Tester", 1, true), "nome del personaggio assente")
    truthy(not rep:find("Azeroth", 1, true), "reame assente")
    truthy(not rep:find("SEGRETO123", 1, true) and not rep:find("PAYLOAD987", 1, true), "nessun payload di profilo")
    truthy(rep:find("<pg>", 1, true), "nome sostituito")
    -- con il mock di default (reame = nome del prodotto) non lancia
    restoreAll()
    eq(type(D:Report()), "string")
end

T["Report non lancia nemmeno con dati strani"] = function()
    local D = BadbUI.Diagnostics
    set(BadbUI.Logger, "buffer", { 1, nil, "x", {} })
    set(BadbUI.DB, "profileName", nil)
    set(BadbUI, "Player", nil)
    set(BadbUI.Compat, "interface", nil)
    eq(type(D:Report()), "string")
    set(_G, "GetBuildInfo", function() error("niente") end)
    eq(type(D:Report()), "string")
end

T["statistiche: memoria solo se disponibile, aggiornata al massimo ogni 30s"] = function(Mock)
    local D = BadbUI.Diagnostics
    eq(D:GetStats().addonMemoryKB, nil, "senza GetAddOnMemoryUsage nessun dato")
    local updates, mem = 0, 100
    set(_G, "UpdateAddOnMemoryUsage", function() updates = updates + 1 end)
    set(_G, "GetAddOnMemoryUsage", function(name) eq(name, "BadbUI"); return mem end)
    Mock.time = 1000
    eq(D:GetStats().addonMemoryKB, 100); eq(updates, 1)
    mem = 200
    Mock.time = 1010
    eq(D:GetStats().addonMemoryKB, 100, "valore in cache"); eq(updates, 1)
    Mock.time = 1031
    eq(D:GetStats().addonMemoryKB, 200); eq(updates, 2)
    -- senza UpdateAddOnMemoryUsage funziona lo stesso
    set(_G, "UpdateAddOnMemoryUsage", nil)
    Mock.time = 2000
    mem = 300
    eq(D:GetStats().addonMemoryKB, 300)
    -- errore nell'API: nessuna propagazione
    set(_G, "GetAddOnMemoryUsage", function() error("x") end)
    Mock.time = 3000
    eq(type(D:GetStats()), "table")
end

T["comandi doctor: run, report, errors"] = function()
    local D = BadbUI.Diagnostics
    local boxes = {}
    set(BadbUI, "ConfigUI", { TextBox = function(_, title, text) boxes[#boxes + 1] = { title, text } end })
    local cmd = D.commands.doctor.fn
    cmd("run"); cmd(""); cmd("report")
    eq(#boxes, 1); truthy(boxes[1][2]:find("BadbUI - report diagnostico", 1, true))
    cmd("errors")
    local st = fakeErrorHandler()
    st.current("BadbUI: per il comando")
    cmd("errors")
    cmd("sconosciuto")
    -- senza ConfigUI il report finisce nel log
    set(BadbUI, "ConfigUI", nil)
    cmd("report")
end

T["pagina: elenco, esegui, ripara, copia report"] = function(Mock)
    local D, DB = BadbUI.Diagnostics, BadbUI.DB
    local boxes, toasts = {}, {}
    local UI = {
        TextBox = function(_, title, text) boxes[#boxes + 1] = { title, text } end,
        Toast = function(_, text) toasts[#toasts + 1] = text end,
    }
    DB.sv.profileKeys.Fantasma = "Nulla"
    local parent = CreateFrame("Frame")
    local h = D.page.build(parent, { UI = UI })
    truthy(type(h) == "number" and h > 0)
    local st = D._page
    truthy(#st.results >= 6, "righe")
    eq(st.results[1].level, "error", "errori in cima")
    local TEX = "Interface\\RaidFrame\\ReadyCheck-NotReady"
    eq(st.rows[1].icon.__texture, TEX, "icona di livello")
    truthy(st.rows[1].fix:IsShown(), "pulsante Ripara dove c'e' fix")
    local fixRow
    for i, r in ipairs(st.results) do if r.fix == nil and r.level == "ok" then fixRow = i; break end end
    eq(st.rows[fixRow].fix:IsShown(), false, "nessun Ripara senza fix")
    -- Ripara
    local nBefore = #D._page.results
    st.rows[1].fix.__scripts.OnClick()
    eq(DB.sv.profileKeys.Fantasma, nil, "riparato")
    truthy(toasts[#toasts]:find("Riparato"))
    eq(find(D._page.results, "db").level, "ok", "ri-eseguito dopo la riparazione")
    -- Esegui e Copia report
    st.btnRun.__scripts.OnClick()
    st.btnReport.__scripts.OnClick()
    eq(boxes[1][1], "Report BadbUI"); truthy(boxes[1][2]:find("Controlli:", 1, true))
    D.page.refresh()
    -- senza UI
    local p2 = CreateFrame("Frame")
    D.page.build(p2, {})
    D._page.btnReport.__scripts.OnClick()
end

T["disattivazione: handler ripristinato e API ancora utilizzabili"] = function()
    local D = BadbUI.Diagnostics
    local st = fakeErrorHandler()
    BadbUI.Modules:SetEnabled("Diagnostics", false)
    eq(st.current, st.prev)
    BadbUI.Modules:SetEnabled("Diagnostics", false)
    eq(st.current, st.prev, "doppia disattivazione innocua")
    truthy(#D:RunChecks() > 0); eq(type(D:Report()), "string")
    BadbUI.Modules:SetEnabled("Diagnostics", true)
    BadbUI.Modules:SetEnabled("Diagnostics", true)
    local h = st.current
    BadbUI.Modules:SetEnabled("Diagnostics", false)
    BadbUI.Modules:SetEnabled("Diagnostics", true)
    truthy(st.current ~= h, "nuova installazione dopo la riattivazione")
    BadbUI.Modules:SetEnabled("Diagnostics", false)
    eq(st.current, st.prev)
end

-- Ripristina sempre i globali sostituiti, anche se il test fallisce.
for name, fn in pairs(T) do
    T[name] = function(Mock)
        saved = {}
        local ok, err = pcall(fn, Mock)
        restoreAll()
        if not ok then error(err, 0) end
    end
end

return T
