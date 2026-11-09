-- BadbUI - Backups
-- Snapshot completi di BadbUIDB (profili, chiavi, spec, globali) con retention, restore
-- transazionale, export/import tipizzato e backup automatico al login.
-- I backup stanno in Badb.DB.sv.global.backups (lista in ordine cronologico, piu' vecchio per primo)
-- e NON entrano mai negli snapshot (altrimenti crescerebbero a spirale).
-- API (tutte "non lanciano"): Create, List, GetInfo, Restore, Delete, Export, Import, Prune.
local _, ns = ...
local Badb = ns.Badb
local Events, Logger = Badb.Events, Badb.Logger

local MAX_DEPTH = 40           -- profondita' massima accettata in uno snapshot
local MAX_NODES = 400000       -- tabelle visitate al massimo (anti-bomba)
local MAX_LABEL = 60
local SECTIONS = { "profiles", "profileKeys", "specProfiles", "global" }
-- Questi kind non vengono ruotati automaticamente (se non per mancanza di spazio sul conteggio).
local PROTECTED = { manual = true, imported = true }

local M = Badb.Modules:New("Backups", {
    title = "Backup",
    category = "Strumenti",
    defaults = {
        enabled = true,
        maxBackups = 20,       -- numero massimo di backup conservati
        maxSizeKB = 1024,      -- dimensione totale stimata massima di tutti i backup
        autoOnLogin = true,    -- backup automatico al login
        autoHours = 24,        -- eta' massima dell'ultimo backup automatico
    },
    options = {
        { type = "header", label = "Backup" },
        { type = "toggle", path = "autoOnLogin", label = "Backup automatico al login" },
        { type = "range", path = "autoHours", label = "Ore tra backup automatici", min = 1, max = 168, step = 1 },
        { type = "range", path = "maxBackups", label = "Backup conservati", min = 3, max = 50, step = 1 },
    },
})

Badb.Backups = M

---------------------------------------------------------------------------
-- Utilita'
---------------------------------------------------------------------------

-- Orologio: time() nel client, con fallback. Letto a ogni chiamata (i test lo simulano).
local function now()
    if type(time) == "function" then
        local ok, t = pcall(time)
        if ok and type(t) == "number" then return math.floor(t) end
    end
    if type(GetServerTime) == "function" then
        local ok, t = pcall(GetServerTime)
        if ok and type(t) == "number" then return math.floor(t) end
    end
    if type(os) == "table" and type(os.time) == "function" then
        local ok, t = pcall(os.time)
        if ok and type(t) == "number" then return math.floor(t) end
    end
    if type(GetTime) == "function" then
        local ok, t = pcall(GetTime)
        if ok and type(t) == "number" then return math.floor(t) end
    end
    return 0
end

local function opt(self, name, default, min, max)
    local ok, v = pcall(self.Get, self, name)
    v = ok and tonumber(v) or default
    if v ~= v then v = default end
    return math.floor(math.max(min, math.min(max, v)))
end

local function maxBackups(self) return opt(self, "maxBackups", 20, 1, 100) end
local function maxBytes(self) return opt(self, "maxSizeKB", 1024, 64, 16384) * 1024 end

-- Copia profonda: solo string/number/boolean, chiavi string/number, niente cicli, profondita' limitata.
local function deepCopy(v, depth, stack, counter)
    local tv = type(v)
    if tv ~= "table" then
        if tv == "number" or tv == "string" or tv == "boolean" then return v end
        return nil
    end
    if depth > MAX_DEPTH or stack[v] then return nil end
    counter.n = counter.n + 1
    if counter.n > MAX_NODES then error("struttura troppo grande") end
    stack[v] = true
    local out = {}
    for k, val in pairs(v) do
        local tk = type(k)
        if tk == "string" or tk == "number" then
            local c = deepCopy(val, depth + 1, stack, counter)
            if c ~= nil then out[k] = c end
        end
    end
    stack[v] = nil
    return out
end

-- Stima dei byte della serializzazione (stessa forma di Serializer, senza allocare stringhe).
local function estimate(v, depth, stack, counter)
    local tv = type(v)
    if tv == "string" then return #v + 4
    elseif tv == "number" then return 3 + #tostring(v)
    elseif tv == "boolean" then return 1
    elseif tv ~= "table" or depth > MAX_DEPTH or stack[v] then return 0 end
    counter.n = counter.n + 1
    if counter.n > MAX_NODES then return 0 end
    stack[v] = true
    local n = 2
    for k, val in pairs(v) do
        local tk, tval = type(k), type(val)
        if (tk == "string" or tk == "number") and tval ~= "function" and tval ~= "userdata" and tval ~= "thread" then
            n = n + estimate(k, depth + 1, stack, counter) + estimate(val, depth + 1, stack, counter)
        end
    end
    stack[v] = nil
    return n
end

function M.EstimateSize(tbl) return estimate(tbl, 0, {}, { n = 0 }) end

local function cleanLabel(label, fallback)
    label = type(label) == "string" and label or (label ~= nil and tostring(label)) or ""
    label = label:gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if label == "" then label = fallback end
    if #label > MAX_LABEL then label = label:sub(1, MAX_LABEL) end
    return label
end

local function cleanKind(kind)
    if type(kind) ~= "string" or kind == "" or #kind > 24 or not kind:match("^[%w%-_]+$") then return "manual" end
    return kind
end

local DEFAULT_LABELS = { manual = "Backup manuale", auto = "Backup automatico" }

---------------------------------------------------------------------------
-- Snapshot: costruzione e validazione
---------------------------------------------------------------------------

-- Costruisce uno snapshot (copia profonda) dal contenuto di BadbUIDB, escludendo i backup.
local function buildSnapshot(sv)
    local stack, counter = {}, { n = 0 }
    local snap = { schema = (type(sv.schema) == "number" and sv.schema >= 1) and sv.schema or 1 }
    for _, name in ipairs(SECTIONS) do
        local src, out = sv[name], {}
        if type(src) == "table" then
            for k, v in pairs(src) do
                local tk = type(k)
                if (tk == "string" or tk == "number") and not (name == "global" and k == "backups") then
                    local c = deepCopy(v, 2, stack, counter)
                    if c ~= nil then out[k] = c end
                end
            end
        end
        snap[name] = out
    end
    return snap
end

local function checkTree(v, depth, counter)
    local tv = type(v)
    if tv == "string" or tv == "number" or tv == "boolean" then return true end
    if tv ~= "table" then return false, "tipo non ammesso (" .. tv .. ")" end
    if depth > MAX_DEPTH then return false, "struttura troppo profonda" end
    counter.n = counter.n + 1
    if counter.n > MAX_NODES then return false, "struttura troppo grande" end
    if getmetatable(v) ~= nil then return false, "metatable non ammessa" end
    for k, val in pairs(v) do
        local tk = type(k)
        if tk ~= "string" and tk ~= "number" then return false, "chiave non valida" end
        local ok, err = checkTree(val, depth + 1, counter)
        if not ok then return false, err end
    end
    return true
end

-- Valida uno snapshot (schema, tipi). Non modifica nulla. -> true | false, motivo
function M.Validate(snap)
    if type(snap) ~= "table" then return false, "snapshot non valido" end
    local schema = snap.schema
    if type(schema) ~= "number" or schema < 1 or schema % 1 ~= 0 then return false, "schema mancante o non valido" end
    local cur = Badb.DB and Badb.DB.sv and Badb.DB.sv.schema
    if type(cur) == "number" and schema > cur then
        return false, "snapshot creato da una versione piu' recente di BadbUI (schema " .. schema .. ")"
    end
    for _, name in ipairs(SECTIONS) do
        if type(snap[name]) ~= "table" then return false, "sezione '" .. name .. "' mancante o di tipo errato" end
    end
    local counter = { n = 0 }
    for _, name in ipairs(SECTIONS) do
        local ok, err = checkTree(snap[name], 0, counter)
        if not ok then return false, name .. ": " .. tostring(err) end
    end
    for pname, p in pairs(snap.profiles) do
        if type(pname) ~= "string" or pname == "" then return false, "nome profilo non valido" end
        if type(p) ~= "table" then return false, "profilo '" .. pname .. "' non e' una tabella" end
        for _, sub in ipairs({ "modules", "frames" }) do
            local t = p[sub]
            if t ~= nil then
                if type(t) ~= "table" then return false, "profilo '" .. pname .. "': '" .. sub .. "' non e' una tabella" end
                for key, val in pairs(t) do
                    if type(key) ~= "string" or type(val) ~= "table" then
                        return false, "profilo '" .. pname .. "': voce '" .. tostring(key) .. "' di '" .. sub .. "' non valida"
                    end
                end
            end
        end
    end
    for ck, pname in pairs(snap.profileKeys) do
        if type(ck) ~= "string" or type(pname) ~= "string" or pname == "" then return false, "profileKeys non valido" end
    end
    for ck, map in pairs(snap.specProfiles) do
        if type(ck) ~= "string" or type(map) ~= "table" then return false, "specProfiles non valido" end
        for idx, pname in pairs(map) do
            if type(idx) ~= "number" or type(pname) ~= "string" then return false, "specProfiles non valido" end
        end
    end
    return true
end

-- Copia pulita e indipendente di uno snapshot valido (senza eventuali backup annidati).
local function normalizedCopy(snap)
    local ok, res = pcall(function()
        local stack, counter = {}, { n = 0 }
        local out = { schema = snap.schema }
        for _, name in ipairs(SECTIONS) do
            local sec = {}
            for k, v in pairs(snap[name]) do
                if not (name == "global" and k == "backups") then
                    local c = deepCopy(v, 2, stack, counter)
                    if c ~= nil then sec[k] = c end
                end
            end
            out[name] = sec
        end
        return out
    end)
    if not ok then return nil, tostring(res) end
    return res
end

---------------------------------------------------------------------------
-- Lista dei backup
---------------------------------------------------------------------------

-- Ritorna la lista persistente (creandola se create=true). Scarta solo voci palesemente inutilizzabili.
local function getList(create)
    local sv = Badb.DB and Badb.DB.sv
    if type(sv) ~= "table" then return nil, "database non inizializzato" end
    if type(sv.global) ~= "table" then
        if not create then return {} end
        sv.global = {}
    end
    local list = sv.global.backups
    if type(list) ~= "table" then
        if not create then return {} end
        list = {}
        sv.global.backups = list
    end
    for i = #list, 1, -1 do
        local e = list[i]
        if type(e) ~= "table" or type(e.id) ~= "string" then table.remove(list, i) end
    end
    return list
end

local function entryTime(e) return tonumber(e.time) or 0 end

local function entrySize(e)
    if type(e.size) ~= "number" then e.size = type(e.data) == "table" and M.EstimateSize(e.data) or 0 end
    return e.size
end

local function totalSize(list)
    local n = 0
    for _, e in ipairs(list) do n = n + entrySize(e) end
    return n
end

local function findEntry(list, id)
    for i, e in ipairs(list) do
        if e.id == id then return e, i end
    end
end

local function isProtected(e) return PROTECTED[e.kind] == true end

-- Indici delle voci da eliminare per rientrare nei limiti (extraCount/extraBytes = spazio richiesto per
-- un nuovo backup). Ruota prima i non protetti (piu' vecchi per primi); i protetti solo per il numero.
-- -> toRemove (set di indici) | nil, errore (limite dimensione non rispettabile).
local function planRotation(list, maxN, maxB, extraCount, extraBytes)
    local remove, count, bytes = {}, #list, totalSize(list)
    local auto, prot = {}, {}
    for i, e in ipairs(list) do
        if isProtected(e) then prot[#prot + 1] = i else auto[#auto + 1] = i end
    end
    local function byAge(a, b)
        local ta, tb = entryTime(list[a]), entryTime(list[b])
        if ta ~= tb then return ta < tb end
        return a < b
    end
    table.sort(auto, byAge); table.sort(prot, byAge)
    for _, i in ipairs(auto) do
        if count + extraCount > maxN or bytes + extraBytes > maxB then
            remove[i] = true; count = count - 1; bytes = bytes - entrySize(list[i])
        end
    end
    for _, i in ipairs(prot) do
        if count + extraCount > maxN then
            remove[i] = true; count = count - 1; bytes = bytes - entrySize(list[i])
        end
    end
    if bytes + extraBytes > maxB then
        return nil, string.format("spazio insufficiente per i backup (%d KB su %d KB): elimina qualche backup manuale",
            math.ceil((bytes + extraBytes) / 1024), math.floor(maxB / 1024))
    end
    return remove
end

local function applyRemoval(list, remove)
    local n = 0
    for i = #list, 1, -1 do
        if remove[i] then table.remove(list, i); n = n + 1 end
    end
    return n
end

-- Inserisce un nuovo backup mantenendo l'ordine per tempo (stabile a parita' di tempo).
local function addEntry(self, snap, label, kind)
    local size = M.EstimateSize(snap)
    local maxB = maxBytes(self)
    if size > maxB then
        return nil, string.format("backup troppo grande (%d KB, limite %d KB)", math.ceil(size / 1024), math.floor(maxB / 1024))
    end
    local list, err = getList(true)
    if not list then return nil, err end
    local remove, perr = planRotation(list, maxBackups(self), maxB, 1, size)
    if not remove then return nil, perr end
    local dropped = applyRemoval(list, remove)
    if dropped > 0 then Logger:Info("Backup: ruotati %d backup vecchi", dropped) end

    local t = now()
    local n = 1
    while findEntry(list, "bk" .. t .. "-" .. n) do n = n + 1 end
    local entry = { id = "bk" .. t .. "-" .. n, label = label, kind = kind, time = t, size = size, data = snap }
    local pos = #list + 1
    while pos > 1 and entryTime(list[pos - 1]) > t do pos = pos - 1 end
    table.insert(list, pos, entry)
    Events:Fire("BADB_BACKUP_CREATED", entry.id)
    return entry.id
end

---------------------------------------------------------------------------
-- API pubblica
---------------------------------------------------------------------------

-- Esegue fn senza mai propagare errori. Ritorna i risultati di fn oppure failA, failB.
local function pack(...) return { n = select("#", ...), ... } end

local function guarded(name, fn, ...)
    local res = pack(pcall(fn, ...))
    if res[1] then return unpack(res, 2, res.n) end
    Logger:Error("Backups:%s - %s", name, tostring(res[2]))
    return nil, tostring(res[2])
end

local function createLive(self, label, kind)
    local sv = Badb.DB and Badb.DB.sv
    if type(sv) ~= "table" then return nil, "database non inizializzato" end
    kind = cleanKind(kind)
    label = cleanLabel(label, DEFAULT_LABELS[kind] or kind)
    local snap = buildSnapshot(sv)
    return addEntry(self, snap, label, kind)
end

-- kind: "manual" | "auto" | "pre-import" | "pre-preset" | "pre-restore" ... -> id | nil, errore
function M:Create(label, kind)
    return guarded("Create", createLive, self, label, kind)
end

function M:List()
    local out = {}
    local ok, list = pcall(getList, false)
    if not ok or not list then return out end
    for i = #list, 1, -1 do
        local e = list[i]
        out[#out + 1] = { id = e.id, label = tostring(e.label or ""), kind = tostring(e.kind or "manual"),
            time = entryTime(e), size = entrySize(e) }
    end
    return out
end

function M:GetInfo(id)
    local list = getList(false)
    local e = list and findEntry(list, id)
    if not e then return nil, "backup inesistente" end
    local info = { id = e.id, label = tostring(e.label or ""), kind = tostring(e.kind or "manual"), time = entryTime(e),
        size = entrySize(e), profiles = {} }
    if type(e.data) == "table" then
        info.schema = e.data.schema
        if type(e.data.profiles) == "table" then
            for name in pairs(e.data.profiles) do info.profiles[#info.profiles + 1] = tostring(name) end
            table.sort(info.profiles)
        end
    end
    info.valid = M.Validate(e.data) and true or false
    return info
end

function M:Delete(id)
    local ok, a, b = pcall(function()
        local list = getList(false)
        local e, i = list and findEntry(list, id)
        if not e then return false, "backup inesistente" end
        table.remove(list, i)
        return true
    end)
    if ok then return a, b end
    return false, tostring(a)
end

-- Applica la politica di retention senza creare nulla. -> numero di backup eliminati
function M:Prune()
    local n = guarded("Prune", function()
        local list = getList(false)
        if not list or #list == 0 then return 0 end
        local remove = planRotation(list, maxBackups(self), maxBytes(self), 0, 0)
        return remove and applyRemoval(list, remove) or 0
    end)
    return n or 0
end

-- Contenuto di un backup -> stringa BADB1 (kind "backup")
function M:Export(id)
    return guarded("Export", function()
        local list = getList(false)
        local e = list and findEntry(list, id)
        if not e then return nil, "backup inesistente" end
        local ok, err = M.Validate(e.data)
        if not ok then return nil, "backup corrotto: " .. tostring(err) end
        return Badb.Serializer:Export("backup", {
            v = 1, label = tostring(e.label or ""), kind = tostring(e.kind or "manual"), time = entryTime(e),
            snapshot = e.data,
        })
    end)
end

-- Importa una stringa esportata: aggiunge un backup (kind "imported"), NON lo applica. -> id | nil, errore
function M:Import(str, label)
    return guarded("Import", function()
        if type(str) ~= "string" or str == "" then return nil, "input vuoto" end
        local limit = math.min(math.floor(maxBytes(self) * 1.5) + 4096, 16 * 1024 * 1024)
        if #str > limit then return nil, "stringa troppo grande per essere un backup valido" end
        local data, payload = Badb.Serializer:Import(str, "backup")
        if data == nil then return nil, payload end
        if type(data) ~= "table" then return nil, "dati del backup non validi" end
        local ok, err = M.Validate(data.snapshot)
        if not ok then return nil, "backup importato non valido: " .. tostring(err) end
        local snap, cerr = normalizedCopy(data.snapshot)
        if not snap then return nil, cerr end
        return addEntry(self, snap, cleanLabel(label ~= nil and label or data.label, "Importato"), "imported")
    end)
end

---------------------------------------------------------------------------
-- Restore transazionale
---------------------------------------------------------------------------

local function replaceContents(dst, src)
    for k in pairs(dst) do dst[k] = nil end
    for k, v in pairs(src) do dst[k] = v end
end

local function restoreNow(self, id)
    local sv = Badb.DB and Badb.DB.sv
    if type(sv) ~= "table" then return false, "database non inizializzato" end
    local list = getList(false)
    local entry = list and findEntry(list, id)
    if not entry then return false, "backup inesistente" end

    -- 1) costruisci e valida la copia nuova: se qualcosa non va il DB non e' stato toccato.
    local ok, err = M.Validate(entry.data)
    if not ok then return false, "backup corrotto: " .. tostring(err) end
    local snap, cerr = normalizedCopy(entry.data)
    if not snap then return false, "backup corrotto: " .. tostring(cerr) end

    -- 2) rete di sicurezza (la rotazione potrebbe eliminare `entry`, ma abbiamo gia' la copia).
    local pre, perr = createLive(self, "Prima del ripristino", "pre-restore")
    if not pre then return false, "impossibile creare il backup di sicurezza: " .. tostring(perr) end

    -- 3) scambio: assegnazioni semplici, nessuna operazione che possa fallire a meta'.
    snap.global.backups = type(sv.global) == "table" and sv.global.backups or nil
    for _, name in ipairs(SECTIONS) do
        if type(sv[name]) == "table" then replaceContents(sv[name], snap[name]) else sv[name] = snap[name] end
    end
    if type(sv.schema) ~= "number" or snap.schema < sv.schema then sv.schema = snap.schema end

    -- 4) ricarica DB e moduli sul profilo del personaggio (fallback "Default").
    local DB = Badb.DB
    local target = sv.profileKeys[DB.char]
    if type(target) ~= "string" or type(sv.profiles[target]) ~= "table" then target = "Default" end
    local keepFrames
    if type(sv.profiles[target]) == "table" and type(sv.profiles[target].frames) == "table" then
        keepFrames = deepCopy(sv.profiles[target].frames, 0, {}, { n = 0 })
    end
    local rok, rerr = pcall(DB.SetProfile, DB, target)
    if not rok then
        Logger:Error("Backups:Restore - ricarica profilo fallita: %s", tostring(rerr))
    end
    -- FrameManager azzera la config dei frame al cambio profilo: la ripristiniamo e riapplichiamo.
    if keepFrames and DB.profile and type(DB.profile.frames) == "table" then
        replaceContents(DB.profile.frames, keepFrames)
        if Badb.FrameManager and Badb.FrameManager.ApplyAll then pcall(Badb.FrameManager.ApplyAll, Badb.FrameManager) end
    end
    -- gli override di ruolo (sv.global.roleOverrides) fanno parte dello snapshot: ricalcola il ruolo
    if Badb.Player and Badb.Player.Invalidate then pcall(Badb.Player.Invalidate, Badb.Player) end
    Logger:Info("Backup '%s' ripristinato (profilo '%s')", tostring(entry.label or id), tostring(target))
    Events:Fire("BADB_BACKUP_RESTORED", id)
    return true
end

-- Ripristina un backup. In combattimento e' differito a fine combattimento (ritorna true, "differito").
function M:Restore(id)
    return guarded("Restore", function()
        if type(id) ~= "string" then return false, "id non valido" end
        local list = getList(false)
        local entry = list and findEntry(list, id)
        if not entry then return false, "backup inesistente" end
        local ok, err = M.Validate(entry.data)
        if not ok then return false, "backup corrotto: " .. tostring(err) end -- rifiuto immediato, anche in combat

        self._restoreToken = (self._restoreToken or 0) + 1
        local token, queued = self._restoreToken, true
        local r1, r2 = Events:RunOutOfCombat("Backups:Restore", function()
            queued = false
            if token ~= self._restoreToken then return false, "annullato" end
            local pok, a, b = pcall(restoreNow, self, id)
            if not pok then
                Logger:Error("Backups:Restore - %s", tostring(a))
                return false, tostring(a)
            end
            if not a then Logger:Warn("Ripristino non eseguito: %s", tostring(b)) end
            return a, b
        end)
        if queued then
            Logger:Info("Ripristino in coda: partira' a fine combattimento")
            return true, "differito"
        end
        return r1, r2
    end)
end

---------------------------------------------------------------------------
-- Backup automatico
---------------------------------------------------------------------------

-- Crea un backup "auto" se l'ultimo ha piu' di autoHours ore (o non esiste). -> id | nil
function M:AutoCheck()
    if not self:Get("autoOnLogin") then return nil end
    local t = now()
    if t <= 0 then return nil end
    local limit = opt(self, "autoHours", 24, 1, 168) * 3600
    local list = getList(false)
    for _, e in ipairs(list or {}) do
        if e.kind == "auto" then
            local age = t - entryTime(e)
            if age >= 0 and age < limit then return nil end -- ce n'e' uno recente
        end
    end
    local id, err = self:Create("Automatico al login", "auto")
    if not id then Logger:Warn("Backup automatico non creato: %s", tostring(err)) end
    return id
end

function M:OnEnable()
    self:AutoCheck()
end

function M:OnDisable()
    -- Annulla un eventuale ripristino differito ancora in coda.
    self._restoreToken = (self._restoreToken or 0) + 1
end

---------------------------------------------------------------------------
-- Comandi /badb backup ...
---------------------------------------------------------------------------

local function fmtDate(t)
    local ok, s = pcall(date, "%d/%m/%Y %H:%M", t)
    return ok and s or tostring(t)
end

local function fmtKB(bytes) return string.format("%.1f KB", (bytes or 0) / 1024) end

-- Accetta un id oppure la posizione (1 = piu' recente) nell'elenco.
local function resolveId(arg)
    arg = arg or ""
    local list = M:List()
    for _, e in ipairs(list) do if e.id == arg then return e.id end end
    local n = tonumber(arg)
    if n and list[n] then return list[n].id end
end

local function say(fmt, ...) Logger:Info(fmt, ...) end

M.commands = {
    backup = {
        help = "backup create [etichetta] | list | restore <id|n> | delete <id|n>",
        fn = function(args)
            local sub, rest = (args or ""):match("^(%S*)%s*(.-)$")
            sub = (sub or ""):lower()
            if sub == "create" then
                local id, err = M:Create(rest ~= "" and rest or nil, "manual")
                if id then say("Backup creato: %s", id) else say("Backup non creato: %s", tostring(err)) end
            elseif sub == "restore" then
                local id = resolveId(rest)
                if not id then say("Backup non trovato: usa /badb backup list"); return end
                local ok, err = M:Restore(id)
                if ok then say(err == "differito" and "Ripristino differito a fine combattimento" or "Ripristino completato")
                else say("Ripristino fallito: %s", tostring(err)) end
            elseif sub == "delete" then
                local id = resolveId(rest)
                if not id then say("Backup non trovato: usa /badb backup list"); return end
                local ok, err = M:Delete(id)
                say(ok and "Backup eliminato" or ("Eliminazione fallita: " .. tostring(err)))
            else -- list (default)
                local list = M:List()
                if #list == 0 then say("Nessun backup"); return end
                for i, e in ipairs(list) do
                    say("%d. %s  %s [%s] %s  (%s)", i, fmtDate(e.time), e.label, e.kind, fmtKB(e.size), e.id)
                end
            end
        end,
    },
}

---------------------------------------------------------------------------
-- Pagina ConfigUI (category "Gestione")
---------------------------------------------------------------------------

local ROW_H = 26

local function newButton(parent, text, w, x, y, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22); b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    b:SetText(text)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

local function newText(parent, template, x, y)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    return fs
end

local function buildPage(parent, ctx)
    local UI = ctx and ctx.UI
    local state = { rows = {} }
    M._page = state

    local function notify(text, level)
        if UI and UI.Toast then pcall(UI.Toast, UI, text, level) else Logger:Info("%s", text) end
    end
    local function confirm(text, onYes)
        if UI and UI.Confirm then pcall(UI.Confirm, UI, text, onYes) else onYes() end
    end

    local title = newText(parent, "GameFontNormalLarge", 16, 0)
    title:SetText("Backup")
    state.info = newText(parent, "GameFontHighlightSmall", 16, 28)
    state.btnCreate = newButton(parent, "Crea backup", 120, 16, 48, function()
        local id, err = M:Create(nil, "manual")
        notify(id and "Backup creato" or ("Backup non creato: " .. tostring(err)), id and "info" or "error")
        state.render()
    end)
    state.btnImport = newButton(parent, "Importa...", 100, 142, 48, function()
        if UI and UI.TextBox then
            UI:TextBox("Importa backup", "", function(str)
                local id, err = M:Import(str, "Importato")
                notify(id and "Backup importato" or ("Import fallito: " .. tostring(err)), id and "info" or "error")
                state.render()
            end)
        else
            notify("Finestra di testo non disponibile", "error")
        end
    end)

    local function row(i)
        local r = state.rows[i]
        if r then return r end
        local y = 84 + (i - 1) * ROW_H
        r = {
            text = newText(parent, "GameFontHighlightSmall", 16, y + 4),
            restore = newButton(parent, "Ripristina", 80, 330, y),
            export = newButton(parent, "Esporta", 64, 414, y),
            delete = newButton(parent, "Elimina", 64, 482, y),
        }
        state.rows[i] = r
        return r
    end

    function state.render()
        local list = M:List()
        local total = 0
        for _, e in ipairs(list) do total = total + e.size end
        state.info:SetText(string.format("%d backup, %s su %s", #list, fmtKB(total), fmtKB(maxBytes(M))))
        local shown = math.min(#list, 100)
        for i = 1, math.max(shown, #state.rows) do
            local e = list[i]
            if e and i <= shown then
                local r = row(i)
                local id = e.id
                r.text:SetText(string.format("%s  %s |cff888888[%s] %s|r", fmtDate(e.time), e.label, e.kind, fmtKB(e.size)))
                r.restore:SetScript("OnClick", function()
                    confirm("Ripristinare il backup '" .. e.label .. "'? Verra' creato prima un backup di sicurezza.", function()
                        local ok, err = M:Restore(id)
                        notify(ok and (err == "differito" and "Ripristino differito a fine combattimento" or "Backup ripristinato")
                            or ("Ripristino fallito: " .. tostring(err)), ok and "info" or "error")
                        state.render()
                    end)
                end)
                r.export:SetScript("OnClick", function()
                    local str, err = M:Export(id)
                    if not str then notify("Export fallito: " .. tostring(err), "error"); return end
                    if UI and UI.TextBox then UI:TextBox("Esporta backup", str) else notify("Finestra di testo non disponibile", "error") end
                end)
                r.delete:SetScript("OnClick", function()
                    confirm("Eliminare il backup '" .. e.label .. "'?", function()
                        M:Delete(id)
                        state.render()
                    end)
                end)
                r.text:Show(); r.restore:Show(); r.export:Show(); r.delete:Show()
            elseif state.rows[i] then
                local r = state.rows[i]
                r.text:Hide(); r.restore:Hide(); r.export:Hide(); r.delete:Hide()
            end
        end
        local h = 84 + math.max(shown, 1) * ROW_H + 8
        if parent.SetHeight then parent:SetHeight(h) end
        state.height = h
        return h
    end

    return state.render()
end

M.page = {
    title = "Backup", order = 90, category = "Gestione",
    build = buildPage,
    refresh = function() if M._page and M._page.render then M._page.render() end end,
}
