-- Test del modulo Backups
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end

local function truthy(v, msg) if not v then error(msg or "atteso valore vero", 2) end end

local function deepEq(a, b, path)
    path = path or "root"
    if type(a) ~= type(b) then error("tipo diverso in " .. path, 3) end
    if type(a) ~= "table" then
        if a ~= b then error("valore diverso in " .. path .. ": " .. tostring(a) .. " vs " .. tostring(b), 3) end
        return
    end
    for k, v in pairs(a) do deepEq(v, b[k], path .. "." .. tostring(k)) end
    for k in pairs(b) do if a[k] == nil then error("chiave extra in " .. path .. "." .. tostring(k), 3) end end
end

local function copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = copy(v) end
    return o
end

local T0 = 1700000000
local savedTime -- il globale `time` simulato non deve trapelare nelle altre suite

-- Orologio simulato + DB pulito dai backup creati al login.
local function setup(Mock)
    Mock.time = T0
    if not savedTime then savedTime = { time } end
    time = function() return Mock.time end
    BadbUIDB.global.backups = nil
    return BadbUI.Backups, BadbUI.Modules:Get("Backups")
end

local T = {}

T["il modulo e' registrato e crea il backup automatico al login"] = function()
    local B = BadbUI.Backups
    truthy(B, "Badb.Backups mancante")
    eq(BadbUI.Modules:Get("Backups"), B, "stesso oggetto del modulo")
    local list = B:List()
    eq(#list, 1, "un backup al primo login")
    eq(list[1].kind, "auto", "kind auto")
    truthy(B.page and B.page.category == "Gestione", "pagina Gestione")
    truthy(B.commands and B.commands.backup, "comando backup")
end

T["Create/List: campi, ordine e copia profonda"] = function(Mock)
    local B = setup(Mock)
    BadbUI.DB.profile.modules.Hider.custom = { a = 1 }
    local id1 = B:Create("Primo", "manual")
    truthy(type(id1) == "string", "id stringa")
    Mock.time = T0 + 10
    local id2 = B:Create("Secondo")
    truthy(id1 ~= id2, "id univoci")
    local list = B:List()
    eq(#list, 2)
    eq(list[1].id, id2, "piu' recente prima")
    eq(list[1].label, "Secondo"); eq(list[1].kind, "manual", "kind di default")
    eq(list[2].label, "Primo"); eq(list[2].time, T0)
    truthy(list[1].size > 0, "dimensione stimata")
    -- copia profonda: modificare il DB non cambia lo snapshot
    BadbUI.DB.profile.modules.Hider.custom.a = 99
    local entry = BadbUIDB.global.backups[1]
    eq(entry.data.profiles.Default.modules.Hider.custom.a, 1, "snapshot indipendente dal DB")
    -- i backup non finiscono negli snapshot
    eq(BadbUIDB.global.backups[2].data.global.backups, nil, "niente backup nei backup")
    local info = B:GetInfo(id1)
    eq(info.profiles[1], "Default"); eq(info.valid, true)
end

T["id univoci anche con lo stesso timestamp"] = function(Mock)
    local B = setup(Mock)
    local seen = {}
    for i = 1, 6 do
        local id = B:Create("x" .. i)
        truthy(not seen[id], "id duplicato " .. tostring(id))
        seen[id] = true
    end
end

T["ordine per tempo con orologio che torna indietro"] = function(Mock)
    local B = setup(Mock)
    B:Create("nuovo")
    Mock.time = T0 - 500
    B:Create("vecchio")
    local list = B:List()
    eq(list[1].label, "nuovo"); eq(list[2].label, "vecchio")
end

T["rotazione: ruota prima gli auto e conserva i manual"] = function(Mock)
    local B, M = setup(Mock)
    M:Set("maxBackups", 5)
    for i = 1, 3 do Mock.time = T0 + i; B:Create("man" .. i, "manual") end
    for i = 1, 6 do Mock.time = T0 + 10 + i; B:Create("auto" .. i, "auto") end
    local list = B:List()
    eq(#list, 5, "limite rispettato")
    local manual, auto = 0, 0
    for _, e in ipairs(list) do if e.kind == "manual" then manual = manual + 1 else auto = auto + 1 end end
    eq(manual, 3, "i manual restano"); eq(auto, 2, "solo gli auto ruotano")
    eq(list[1].label, "auto6", "gli auto rimasti sono i piu' recenti")
    eq(list[2].label, "auto5")
end

T["rotazione: senza altro spazio ruota il manual piu' vecchio"] = function(Mock)
    local B, M = setup(Mock)
    M:Set("maxBackups", 3)
    for i = 1, 4 do Mock.time = T0 + i; B:Create("m" .. i, "manual") end
    local list = B:List()
    eq(#list, 3)
    eq(list[3].label, "m2", "m1 e' stato ruotato")
end

T["Prune applica la retention e le opzioni"] = function(Mock)
    local B, M = setup(Mock)
    for i = 1, 8 do Mock.time = T0 + i; B:Create("a" .. i, "auto") end
    M:Set("maxBackups", 3)
    eq(B:Prune(), 5, "backup eliminati")
    eq(#B:List(), 3)
end

T["limite dimensione: rifiuto chiaro, nulla eliminato"] = function(Mock)
    local B, M = setup(Mock)
    M:Set("maxSizeKB", 64)
    BadbUI.DB.profile.modules.Hider.blob = string.rep("x", 40 * 1024)
    local id1 = B:Create("uno", "manual")
    truthy(id1, "primo entra")
    local id2, err = B:Create("due", "manual")
    eq(id2, nil, "secondo rifiutato")
    truthy(tostring(err):find("spazio insufficiente"), "messaggio chiaro: " .. tostring(err))
    eq(#B:List(), 1, "il manual esistente e' intatto")
    -- un backup auto, invece, viene ruotato per fare spazio a un altro
    B:Delete(id1)
    local a1 = B:Create("auto", "auto")
    truthy(a1)
    local m = B:Create("manuale", "manual")
    truthy(m, "il manual prende il posto dell'auto")
    local list = B:List()
    eq(#list, 1); eq(list[1].kind, "manual")
    -- singolo snapshot oltre il limite
    BadbUI.DB.profile.modules.Hider.blob = string.rep("y", 70 * 1024)
    local id3, err3 = B:Create("enorme", "manual")
    eq(id3, nil); truthy(tostring(err3):find("troppo grande"), tostring(err3))
end

T["Restore: ripristina, crea pre-restore, evento e profilo"] = function(Mock)
    local B = setup(Mock)
    local DB = BadbUI.DB
    DB.profile.modules.Hider.marker = "originale"
    DB.sv.global.userNote = "nota"
    DB.sv.profiles.Altro = { modules = { Hider = { marker = "altro" } }, frames = {} }
    local id = B:Create("base", "manual")
    -- modifiche successive
    DB.profile.modules.Hider.marker = "modificato"
    DB.sv.global.userNote = "cambiata"
    DB.sv.profiles.Altro = nil
    DB.sv.profiles.Nuovo = { modules = {}, frames = {} }
    local fired
    BadbUI.Events:On(fired or {}, "BADB_BACKUP_RESTORED", function(_, rid) fired = rid end)
    Mock.time = T0 + 60
    local ok, err = B:Restore(id)
    eq(ok, true, tostring(err))
    eq(DB.profile.modules.Hider.marker, "originale", "valore ripristinato nel profilo attivo")
    eq(DB.sv.global.userNote, "nota", "globali ripristinati")
    truthy(DB.sv.profiles.Altro, "profilo riportato")
    eq(DB.sv.profiles.Nuovo, nil, "profilo successivo rimosso")
    eq(fired, id, "evento BADB_BACKUP_RESTORED(id)")
    eq(DB:GetProfileName(), "Default")
    eq(DB.profile, DB.sv.profiles.Default, "DB.profile ricaricato")
    local kinds = {}
    for _, e in ipairs(B:List()) do kinds[e.kind] = (kinds[e.kind] or 0) + 1 end
    eq(kinds["pre-restore"], 1, "backup di sicurezza creato")
    eq(kinds.manual, 1, "il backup originale resta")
    -- il pre-restore permette di tornare indietro
    local pre
    for _, e in ipairs(B:List()) do if e.kind == "pre-restore" then pre = e.id end end
    eq(B:Restore(pre), true)
    eq(DB.profile.modules.Hider.marker, "modificato", "annullato il ripristino")
end

T["Restore: profilo del personaggio da profileKeys, fallback Default"] = function(Mock)
    local B = setup(Mock)
    local DB = BadbUI.DB
    DB.sv.profiles.Tank = { modules = { Hider = { marker = "tank" } }, frames = {} }
    DB.sv.profileKeys[DB.char] = "Tank"
    local id = B:Create("con tank", "manual")
    DB:SetProfile("Default", true)
    eq(B:Restore(id), true)
    eq(DB:GetProfileName(), "Tank")
    eq(DB.profile.modules.Hider.marker, "tank")
    -- profilo puntato inesistente -> Default
    BadbUIDB.global.backups[1].data.profileKeys[DB.char] = "Fantasma"
    local list = B:List()
    local manualId
    for _, e in ipairs(list) do if e.kind == "manual" then manualId = e.id end end
    eq(B:Restore(manualId), true)
    eq(DB:GetProfileName(), "Default")
end

T["Restore: la configurazione dei frame sopravvive al cambio profilo"] = function(Mock)
    local B = setup(Mock)
    local DB, FM = BadbUI.DB, BadbUI.FrameManager
    local f = CreateFrame("Frame", "BadbTestFrame")
    FM:Register("TestFrame", { frame = f, title = "Test" })
    FM:SetOption("TestFrame", "alpha", 0.5)
    FM:SetOption("TestFrame", "point", "CENTER")
    eq(DB.profile.frames.TestFrame.alpha, 0.5)
    local id = B:Create("frame", "manual")
    FM:SetOption("TestFrame", "alpha", 0.9)
    eq(B:Restore(id), true)
    truthy(DB.profile.frames.TestFrame, "config frame presente dopo il restore")
    eq(DB.profile.frames.TestFrame.alpha, 0.5, "config ripristinata")
    eq(f:GetAlpha(), 0.5, "e riapplicata al frame")
end

T["Restore atomico: snapshot corrotto lascia il DB intatto"] = function(Mock)
    local B = setup(Mock)
    local DB = BadbUI.DB
    DB.profile.modules.Hider.marker = "vivo"
    local id = B:Create("da corrompere", "manual")
    local entry = BadbUIDB.global.backups[1]
    local before = copy(BadbUIDB)
    local cases = {
        function(d) d.profiles = "non una tabella" end,
        function(d) d.profiles.Default = 5 end,
        function(d) d.schema = nil end,
        function(d) d.schema = 999 end,
        function(d) d.global.f = function() end end,
        function(d) d.profileKeys = { [1] = 2 } end,
        function(d) d.profiles.Default.modules = { Hider = "x" } end,
        function(d) d.specProfiles = { pg = { "a", [2] = 7 } } end,
        function(d) local c = {}; c.self = c; d.global.ciclo = c end,
        function(d) d.global = nil end,
    }
    for i, corrupt in ipairs(cases) do
        entry.data = copy(before.global.backups[1].data)
        corrupt(entry.data)
        local ok, err = B:Restore(id)
        eq(ok, false, "caso " .. i .. " doveva fallire")
        truthy(tostring(err):find("corrotto"), "errore chiaro (caso " .. i .. "): " .. tostring(err))
        eq(#B:List(), 1, "nessun pre-restore creato (caso " .. i .. ")")
        eq(DB.profile.modules.Hider.marker, "vivo", "DB intatto (caso " .. i .. ")")
        eq(BadbUIDB.global.userNote, before.global.userNote)
    end
    -- Export di un backup corrotto rifiutato
    eq(B:Export(id), nil)
end

T["Restore: id inesistente o non valido non lanciano"] = function(Mock)
    local B = setup(Mock)
    local ok, err = B:Restore("nope")
    eq(ok, false); truthy(err)
    eq(B:Restore(nil), false); eq(B:Restore(42), false); eq(B:Restore({}), false)
    eq(B:Delete(nil), false); eq(B:Delete("nope"), false)
    eq(B:Export(nil), nil); eq(B:GetInfo("nope"), nil)
end

T["Restore in combattimento: differito a fine combattimento"] = function(Mock)
    local B = setup(Mock)
    local DB = BadbUI.DB
    DB.profile.modules.Hider.marker = "prima"
    local id = B:Create("c", "manual")
    DB.profile.modules.Hider.marker = "dopo"
    Mock.combat = true
    local ok, res = B:Restore(id)
    eq(ok, true); eq(res, "differito")
    eq(DB.profile.modules.Hider.marker, "dopo", "nulla cambia in combattimento")
    eq(#B:List(), 1, "nessun backup pre-restore ancora")
    Mock.combat = false
    Mock.Fire("PLAYER_REGEN_ENABLED")
    eq(DB.profile.modules.Hider.marker, "prima", "eseguito a fine combattimento")
    eq(#B:List(), 2, "pre-restore creato al momento dell'esecuzione")
    -- uno snapshot corrotto viene rifiutato subito, anche in combattimento
    BadbUIDB.global.backups[1].data.schema = nil
    Mock.combat = true
    eq((B:Restore(id)), false)
end

T["la disattivazione annulla il ripristino differito"] = function(Mock)
    local B = setup(Mock)
    local DB = BadbUI.DB
    DB.profile.modules.Hider.marker = "prima"
    local id = B:Create("c", "manual")
    DB.profile.modules.Hider.marker = "dopo"
    Mock.combat = true
    eq((B:Restore(id)), true)
    BadbUI.Modules:SetEnabled("Backups", false)
    Mock.combat = false
    Mock.Fire("PLAYER_REGEN_ENABLED")
    eq(DB.profile.modules.Hider.marker, "dopo", "ripristino annullato")
    -- le API restano utilizzabili (altri moduli le usano per i backup di sicurezza)
    truthy(B:Create("ancora", "pre-preset"), "Create funziona da disattivato")
    local added = 0
    BadbUI.Modules:SetEnabled("Backups", true)
    truthy(BadbUI.Events.listeners.PLAYER_REGEN_ENABLED, "listener del core intatto")
end

T["Export/Import: round-trip"] = function(Mock)
    local B = setup(Mock)
    local DB = BadbUI.DB
    DB.profile.modules.Hider.marker = "xyz"
    DB.profile.modules.Hider.nested = { 1, 2, { k = "v" }, flag = true, pi = 3.25 }
    DB.sv.profiles.Secondo = { modules = {}, frames = { F = { x = 5 } } }
    DB.sv.specProfiles[DB.char] = { [1] = "Default", [2] = "Secondo" }
    local id = B:Create("da esportare", "manual")
    local str, err = B:Export(id)
    truthy(type(str) == "string" and str:match("^BADB1:"), "stringa esportata: " .. tostring(err))
    eq(BadbUI.Serializer:Import(str, "profile"), nil, "il kind e' 'backup', non 'profile'")
    local original = copy(BadbUIDB.global.backups[1].data)
    B:Delete(id)
    eq(#B:List(), 0)
    local nid, nerr = B:Import(str, "Importato da amico")
    truthy(nid, tostring(nerr))
    local list = B:List()
    eq(#list, 1); eq(list[1].kind, "imported"); eq(list[1].label, "Importato da amico")
    deepEq(BadbUIDB.global.backups[1].data, original)
    -- l'import NON applica nulla
    DB.profile.modules.Hider.marker = "cambiato"
    eq(B:Restore(nid), true)
    eq(DB.profile.modules.Hider.marker, "xyz")
    eq(DB.profile.modules.Hider.nested[3].k, "v")
    eq(DB.sv.specProfiles[DB.char][2], "Secondo")
    -- gli imported non sono ruotati come gli auto
    local B2, M = B, BadbUI.Modules:Get("Backups")
    M:Set("maxBackups", 3)
    for i = 1, 4 do Mock.time = T0 + 100 + i; B:Create("a" .. i, "auto") end
    local kinds = {}
    for _, e in ipairs(B:List()) do kinds[e.kind] = true end
    truthy(kinds.imported, "imported conservato dalla rotazione")
end

T["Import malevolo: nessun errore, nessuna modifica"] = function(Mock)
    local B = setup(Mock)
    B:Create("esistente", "manual")
    local S = BadbUI.Serializer
    local good = B:Export(B:List()[1].id)
    local before = copy(BadbUIDB)
    local function rejected(str, why)
        local id, err = B:Import(str, "x")
        eq(id, nil, why .. ": doveva essere rifiutato")
        truthy(type(err) == "string" and err ~= "", why .. ": serve un motivo")
    end
    rejected(nil, "nil"); rejected("", "vuoto"); rejected(42, "numero"); rejected({}, "tabella")
    rejected("return os.exit(1)", "codice lua")
    rejected("BADB1:!!!!:zzzz", "base64 rotto")
    rejected(string.rep("A", 5 * 1024 * 1024), "stringa enorme")
    rejected(good:sub(1, #good - 3), "checksum rotto")
    rejected(good:gsub("^BADB1:", "BADB1:AAAA"), "corpo alterato")
    rejected(S:Export("profile", { modules = {} }), "kind sbagliato")
    rejected(S:Export("backup", "stringa"), "payload non tabella")
    rejected(S:Export("backup", { snapshot = "x" }), "snapshot non tabella")
    rejected(S:Export("backup", { snapshot = { schema = 1, profiles = "x", profileKeys = {}, specProfiles = {}, global = {} } }), "profiles non tabella")
    rejected(S:Export("backup", { snapshot = { schema = 99, profiles = {}, profileKeys = {}, specProfiles = {}, global = {} } }), "schema futuro")
    rejected(S:Export("backup", { snapshot = { profiles = {}, profileKeys = {}, specProfiles = {}, global = {} } }), "schema mancante")
    rejected(S:Export("backup", { snapshot = { schema = 1, profiles = { P = { modules = "x" } }, profileKeys = {}, specProfiles = {}, global = {} } }), "modules non tabella")
    -- struttura troppo profonda
    local deep = {}
    local cur = deep
    for i = 1, 60 do cur.n = {}; cur = cur.n end
    rejected(S:Export("backup", { snapshot = { schema = 1, profiles = { P = { modules = { M = deep } } }, profileKeys = {}, specProfiles = {}, global = {} } }), "troppo profonda")
    eq(#B:List(), 1, "nessun backup aggiunto")
    deepEq(copy(BadbUIDB), before)
    -- il payload con backup annidati viene ripulito
    local nested = S:Export("backup", { snapshot = { schema = 1, profiles = { P = { modules = {}, frames = {} } },
        profileKeys = {}, specProfiles = {}, global = { backups = { { id = "evil", data = {} } }, ok = 1 } } })
    local id = B:Import(nested)
    truthy(id)
    local info
    for _, e in ipairs(BadbUIDB.global.backups) do if e.id == id then info = e end end
    eq(info.data.global.backups, nil, "backup annidati scartati")
    eq(info.data.global.ok, 1)
end

T["backup automatico: orologio simulato, soglia e opzioni"] = function(Mock)
    local B, M = setup(Mock)
    local id = M:AutoCheck()
    truthy(id, "primo auto")
    eq(B:List()[1].kind, "auto")
    Mock.time = T0 + 3600
    eq(M:AutoCheck(), nil, "dopo 1h non serve")
    Mock.time = T0 + 23 * 3600
    eq(M:AutoCheck(), nil, "dopo 23h non serve")
    Mock.time = T0 + 25 * 3600
    truthy(M:AutoCheck(), "dopo 25h ne serve uno nuovo")
    eq(#B:List(), 2)
    -- soglia configurabile
    M:Set("autoHours", 1)
    Mock.time = T0 + 25 * 3600 + 2 * 3600
    truthy(M:AutoCheck(), "soglia 1h")
    -- disattivato da opzione
    M:Set("autoOnLogin", false)
    Mock.time = T0 + 100 * 3600
    eq(M:AutoCheck(), nil, "opzione disattiva")
    -- un manual recente non sostituisce l'auto
    M:Set("autoOnLogin", true)
    B:Create("manuale", "manual")
    truthy(M:AutoCheck(), "il manual non conta come auto")
end

T["backup automatico al login: riabilitare il modulo ricontrolla"] = function(Mock)
    local B = setup(Mock)
    BadbUI.Modules:SetEnabled("Backups", false)
    eq(#B:List(), 0, "da disattivato niente auto")
    BadbUI.Modules:SetEnabled("Backups", true)
    eq(#B:List(), 1, "OnEnable crea l'auto")
    BadbUI.Modules:SetEnabled("Backups", false)
    BadbUI.Modules:SetEnabled("Backups", true)
    eq(#B:List(), 1, "non duplica")
    Mock.time = T0 + 48 * 3600
    BadbUI.Modules:SetEnabled("Backups", false)
    BadbUI.Modules:SetEnabled("Backups", true)
    eq(#B:List(), 2, "dopo 48h ne crea un altro")
end

T["Create robusto: argomenti strani, DB assente, dati sporchi"] = function(Mock)
    local B = setup(Mock)
    truthy(B:Create({}, 5), "label/kind non stringa")
    truthy(B:Create(string.rep("e", 500), "kind con spazi!"))
    local list = B:List()
    eq(list[1].kind, "manual", "kind non valido -> manual")
    truthy(#list[1].label <= 60, "etichetta troncata")
    eq(B:Create("a\nb\tc"), B:List()[1].id)
    eq(B:List()[1].label, "a b c", "caratteri di controllo ripuliti")
    -- global.backups corrotto
    BadbUIDB.global.backups = "rotto"
    eq(#B:List(), 0)
    truthy(B:Create("dopo il danno"))
    BadbUIDB.global.backups = { "x", 5, { id = 7 }, { id = "ok", data = {}, time = "boh" } }
    eq(#B:List(), 1, "voci inutilizzabili scartate")
    -- DB non inizializzato
    local sv = BadbUI.DB.sv
    BadbUI.DB.sv = nil
    local id, err = B:Create("senza db")
    eq(id, nil); truthy(err)
    eq(#B:List(), 0)
    eq(B:Restore("x"), false)
    BadbUI.DB.sv = sv
    -- dati con cicli e funzioni
    local cyc = {}; cyc.me = cyc; cyc.fn = print
    BadbUI.DB.profile.modules.Hider.cyc = cyc
    local cid = B:Create("ciclo")
    truthy(cid, "i cicli non bloccano il backup")
    local data
    for _, e in ipairs(BadbUIDB.global.backups) do if e.id == cid then data = e.data end end
    eq(data.profiles.Default.modules.Hider.cyc.fn, nil, "funzioni scartate")
    eq(data.profiles.Default.modules.Hider.cyc.me, nil, "ciclo troncato")
    BadbUI.DB.profile.modules.Hider.cyc = nil
end

T["comandi /badb backup"] = function(Mock)
    local B, M = setup(Mock)
    local cmd = M.commands.backup.fn
    cmd("create la mia etichetta")
    eq(B:List()[1].label, "la mia etichetta"); eq(B:List()[1].kind, "manual")
    cmd("create")
    eq(#B:List(), 2)
    Mock.chat = {}
    cmd("list")
    truthy(#Mock.chat >= 2, "elenco stampato")
    truthy(Mock.chat[1]:find("1%."), "numerazione")
    BadbUI.DB.profile.modules.Hider.marker = "m"
    cmd("restore 1")
    eq(#B:List(), 3, "restore per posizione crea il pre-restore")
    local id = B:List()[3].id
    cmd("delete " .. id)
    eq(#B:List(), 2)
    cmd("delete 99"); cmd("restore nope"); cmd(""); cmd("boh"); cmd(nil)
    eq(#B:List(), 2)
end

T["pagina: crea, ripristina, esporta, importa, elimina"] = function(Mock)
    local B, M = setup(Mock)
    local log = { toasts = {}, boxes = {} }
    local UI = {
        Confirm = function(_, text, onYes) log.confirm = text; onYes() end,
        Toast = function(_, text, level) log.toasts[#log.toasts + 1] = text end,
        TextBox = function(_, title, text, onAccept) log.boxes[#log.boxes + 1] = { title, text, onAccept } end,
    }
    local parent = CreateFrame("Frame")
    local h = M.page.build(parent, { UI = UI })
    truthy(type(h) == "number" and h > 0, "altezza ritornata")
    local st = M._page
    st.btnCreate.__scripts.OnClick()
    eq(#B:List(), 1, "Crea")
    truthy(st.rows[1], "riga creata")
    BadbUI.DB.profile.modules.Hider.marker = "pagina"
    st.rows[1].restore.__scripts.OnClick()
    truthy(log.confirm and log.confirm:find("Ripristinare"), "chiede conferma")
    eq(#B:List(), 2, "ripristino eseguito (pre-restore creato)")
    st.rows[1].export.__scripts.OnClick()
    local box = log.boxes[#log.boxes]
    eq(box[1], "Esporta backup"); truthy(box[2]:match("^BADB1:"))
    st.btnImport.__scripts.OnClick()
    local ib = log.boxes[#log.boxes]
    eq(type(ib[3]), "function", "import con callback")
    ib[3](box[2])
    eq(#B:List(), 3, "import")
    ib[3]("spazzatura")
    eq(#B:List(), 3, "import fallito non aggiunge")
    st.rows[1].delete.__scripts.OnClick()
    eq(#B:List(), 2, "Elimina")
    eq(st.rows[3].text:IsShown(), false, "righe in eccesso nascoste")
    M.page.refresh()
    -- senza UI: nessun errore
    local parent2 = CreateFrame("Frame")
    M.page.build(parent2, {})
    M._page.btnCreate.__scripts.OnClick()
    M._page.btnImport.__scripts.OnClick()
    M._page.rows[1].restore.__scripts.OnClick()
    M._page.rows[1].export.__scripts.OnClick()
end

T["override di ruolo: ripristinati col backup e ruolo ricalcolato"] = function(Mock)
    local B = setup(Mock)
    local P = BadbUI.Player
    truthy(P, "Badb.Player presente")
    eq(P:SetRoleOverride("healer"), true)
    local id = B:Create("con ruolo", "manual")
    P:SetRoleOverride("tank")
    eq(select(1, P:GetRole()), "tank")
    local invalidated = 0
    local orig = P.Invalidate
    P.Invalidate = function(self) invalidated = invalidated + 1; return orig(self) end
    eq(B:Restore(id), true)
    P.Invalidate = orig
    truthy(invalidated >= 1, "Player:Invalidate chiamato dopo il restore")
    eq(select(1, P:GetRole()), "healer", "override ripristinato nello snapshot")
    -- senza Badb.Player il restore funziona comunque
    local keep = BadbUI.Player
    BadbUI.Player = nil
    local id2 = B:Create("senza player", "manual")
    eq(B:Restore(id2), true)
    BadbUI.Player = keep
end

for name, fn in pairs(T) do
    T[name] = function(Mock)
        savedTime = nil
        local ok, err = pcall(fn, Mock)
        if savedTime then time = savedTime[1] end
        if not ok then error(err, 0) end
    end
end

return T
