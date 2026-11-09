-- BadbUI - Contexts
-- Motore di regole che cambia profilo in automatico in base al contesto di gioco
-- (istanza, gruppo, ruolo, spec, classe, riposo). Vedi docs/contexts.md.
--
-- Principi:
--  * Le regole vivono in Badb.DB.sv.global.contextRules (per account, non per profilo).
--  * Le API del client sono sondate in modo difensivo (su Forever alcune possono mancare):
--    ogni API assente o che fallisce => valore di default, mai errore.
--  * Classe, ruolo e gruppo talenti ("spec") NON si leggono dal client: arrivano da Badb.Player
--    (Core/PlayerInfo.lua). Su Forever le spec sono i 3 alberi classici con dual spec: `spec` = talentGroup.
--  * Su Forever non esistono arene: `instance` genera none|party|raid|pvp|scenario; "arena" resta
--    un valore valido per le regole (compatibilita' futura) ma non viene mai generato.
--  * Valutazione con debounce (raffiche di eventi => una sola valutazione), mai in
--    combattimento (differita con Events:RunOutOfCombat), con isteresi anti-flapping.
--  * Un cambio profilo causato dal motore non rilancia mai una valutazione (flag di origine).
--  * Un cambio profilo manuale sospende l'auto-switch fino al prossimo cambio di contesto reale.
local _, ns = ...
local Badb = ns.Badb
local Events, Logger = Badb.Events, Badb.Logger

local VERSION = 1
local MAX_RULES = 40
local MAX_NAME = 48
local MAX_PROFILE = 64
local DEBOUNCE = 0.5

local M = Badb.Modules:New("Contexts", {
    title = "Contesti",
    category = "Gestione",
    defaults = {
        enabled = true,
        autoSwitch = true,      -- il motore puo' cambiare profilo
        respectManual = true,   -- un cambio manuale sospende il motore fino al prossimo cambio di contesto
        switchCooldown = 3,     -- secondi minimi tra due cambi automatici (isteresi)
        fallbackProfile = "",   -- profilo se nessuna regola corrisponde ("" = lascia l'attuale)
    },
    options = {
        { type = "toggle", path = "autoSwitch", label = "Cambio profilo automatico per contesto" },
        { type = "toggle", path = "respectManual", label = "Rispetta il cambio manuale (sospende fino al prossimo cambio di contesto)" },
        { type = "range", path = "switchCooldown", label = "Pausa minima tra due cambi (s)", min = 0, max = 30, step = 1 },
    },
})
Badb.Contexts = M

M.stats = { evals = 0, switches = 0 }
M.DEBOUNCE = DEBOUNCE
M.MAX_RULES = MAX_RULES

---------------------------------------------------------------------------
-- Valori ammessi e testi
---------------------------------------------------------------------------
local INSTANCES = { "none", "party", "raid", "pvp", "arena", "scenario" }
local ROLES = { "tank", "healer", "dps", "none" }
local GROUPS = { "solo", "party", "raid" }
-- Contesti che il rilevamento puo' davvero generare (niente "arena" su Forever).
local GENERATED_INSTANCES = { "none", "party", "raid", "pvp", "scenario" }
-- Le 9 classi di Forever; la lista viva viene da Badb.Player quando disponibile.
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
M.INSTANCES, M.GENERATED_INSTANCES, M.ROLES, M.GROUPS, M.CLASSES = INSTANCES, GENERATED_INSTANCES, ROLES, GROUPS, CLASSES

local function toSet(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end
local INSTANCE_SET, ROLE_SET, GROUP_SET = toSet(INSTANCES), toSet(ROLES), toSet(GROUPS)

local LABELS = {
    instance = { none = "Mondo aperto", party = "Dungeon", raid = "Istanza raid", pvp = "Campo di battaglia",
        arena = "Arena", scenario = "Scenario" },
    role = { tank = "Tank", healer = "Guaritore", dps = "DPS", none = "Nessun ruolo" },
    group = { solo = "Solo", party = "Gruppo", raid = "Raid" },
}
local WHEN_ORDER = { "instance", "pvpKind", "group", "role", "spec", "class", "resting", "pvpFlag" }

local function describeWhen(when)
    local parts = {}
    for _, key in ipairs(WHEN_ORDER) do
        local v = when[key]
        if v ~= nil then
            if key == "spec" then parts[#parts + 1] = "spec " .. v
            elseif key == "class" then parts[#parts + 1] = v
            elseif key == "resting" then parts[#parts + 1] = v and "a riposo" or "non a riposo"
            elseif key == "pvpKind" then parts[#parts + 1] = v == "av" and "Alterac Valley" or "campo di battaglia 10-15"
            elseif key == "pvpFlag" then parts[#parts + 1] = v and "flag PvP" or "senza flag PvP"
            else parts[#parts + 1] = (LABELS[key] and LABELS[key][v]) or tostring(v) end
        end
    end
    if #parts == 0 then return "sempre" end
    return table.concat(parts, " + ")
end

---------------------------------------------------------------------------
-- Utilita'
---------------------------------------------------------------------------
local function clock()
    local f = _G.GetTime
    local ok, t = pcall(f or function() return 0 end)
    return (ok and type(t) == "number") and t or 0
end

local function isNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isSecret(v)
    local C = Badb.Compat
    if not C or not C.IsSecret then return false end
    local ok, r = pcall(C.IsSecret, v)
    return ok and r == true
end

-- Chiama una API del client in modo difensivo: assente/errore/secret => nil.
local function probe(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a, b, c = pcall(f, ...)
    if not ok then return nil end
    if isSecret(a) then a = nil end
    if isSecret(b) then b = nil end
    if isSecret(c) then c = nil end
    return a, b, c
end

local function copyTable(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and copyTable(v) or v end
    return out
end

---------------------------------------------------------------------------
-- Rilevamento del contesto
---------------------------------------------------------------------------
local function playerSnapshot()
    local P = Badb.Player
    if type(P) ~= "table" or type(P.GetSnapshot) ~= "function" then return nil end
    local ok, snap = pcall(P.GetSnapshot, P)
    if ok and type(snap) == "table" then return snap end
end

local function detectInstance()
    local _, itype = probe(_G.IsInInstance)
    local inst = "none"
    if type(itype) == "string" then
        itype = itype:lower()
        if itype == "arena" then
            inst = "pvp" -- Forever non ha arene: non si genera mai "arena"
        elseif INSTANCE_SET[itype] then
            inst = itype
        end
    end
    if inst == "none" then
        local pvp = _G.C_PvP
        if type(pvp) == "table" and probe(pvp.IsBattleground) == true then inst = "pvp" end
    end
    return inst
end

-- Distingue Alterac Valley (40v40) dagli altri campi di battaglia (WSG, AB, Darkspear Islands: 10-15 giocatori).
-- NON VERIFICATO in gioco: si usa l'ID istanza storico di Alterac (30) oppure il nome della zona ("Alterac"
-- vale per en e it: "Alterac Valley" / "Valle d'Alterac"). Se l'API manca si ricade su "bg".
local ALTERAC_INSTANCE_ID = 30
local function detectPvpKind(instance)
    if instance ~= "pvp" then return "" end
    local name, _, _, _, _, _, _, instanceID = probe(_G.GetInstanceInfo)
    if isNumber(instanceID) and instanceID == ALTERAC_INSTANCE_ID then return "av" end
    if type(name) == "string" and not isSecret(name) and name:lower():find("alterac", 1, true) then return "av" end
    return "bg"
end

local function detectGroup()
    local inRaid = probe(_G.IsInRaid) == true
    local inGroup = probe(_G.IsInGroup) == true
    local instCat = _G.LE_PARTY_CATEGORY_INSTANCE
    if instCat ~= nil then
        if not inRaid and probe(_G.IsInRaid, instCat) == true then inRaid = true end
        if not inGroup and probe(_G.IsInGroup, instCat) == true then inGroup = true end
    end
    if not inRaid and not inGroup then
        -- API vecchie / parziali
        local n = probe(_G.GetNumGroupMembers)
        if isNumber(n) and n > 1 then inGroup = true end
        local r = probe(_G.GetNumRaidMembers)
        if isNumber(r) and r > 0 then inRaid = true end
        local p = probe(_G.GetNumPartyMembers)
        if isNumber(p) and p > 0 then inGroup = true end
    end
    if inRaid then return "raid" end
    if inGroup then return "party" end
    return "solo"
end

local CONFIDENCE = { high = true, medium = true, low = true }

function M:GetCurrent()
    local snap = playerSnapshot()
    local ctx = {
        instance = detectInstance(),
        group = detectGroup(),
        pvpKind = "",
        role = "none", spec = 0, class = "", roleConfidence = "low",
        resting = probe(_G.IsResting) == true,
        pvpFlag = probe(_G.UnitIsPVP, "player") == true,
    }
    ctx.pvpKind = detectPvpKind(ctx.instance)
    if snap then
        if snap.role == "tank" or snap.role == "healer" or snap.role == "dps" then ctx.role = snap.role end
        if CONFIDENCE[snap.roleConfidence] then ctx.roleConfidence = snap.roleConfidence end
        local g = snap.talentGroup
        if isNumber(g) and g >= 1 and g == math.floor(g) then ctx.spec = g end
        if type(snap.class) == "string" and snap.class ~= "" and not isSecret(snap.class) then
            ctx.class = snap.class:upper()
        end
    end
    return ctx
end

local function ctxEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    return a.instance == b.instance and a.group == b.group and a.role == b.role
        and a.spec == b.spec and a.class == b.class and a.resting == b.resting and a.pvpFlag == b.pvpFlag and a.pvpKind == b.pvpKind
end

---------------------------------------------------------------------------
-- Dati: validazione e persistenza (Badb.DB.sv.global.contextRules)
---------------------------------------------------------------------------
local function oneOf(set)
    return function(v)
        if type(v) ~= "string" then return nil end
        v = v:lower()
        return set[v] and v or nil
    end
end

local CONDITIONS = {
    instance = oneOf(INSTANCE_SET),
    role = oneOf(ROLE_SET),
    group = oneOf(GROUP_SET),
    spec = function(v)
        if isNumber(v) and v == math.floor(v) and v >= 1 and v <= 10 then return v end
    end,
    class = function(v)
        if type(v) ~= "string" then return nil end
        v = v:upper()
        if #v <= 20 and v:match("^%u+$") then return v end
    end,
    resting = function(v) if type(v) == "boolean" then return v end end,
    pvpFlag = function(v) if type(v) == "boolean" then return v end end,
    pvpKind = oneOf({ bg = true, av = true }), -- solo con instance = "pvp"
}

-- Ritorna (when pulito, errore|nil). Le chiavi non valide sono scartate e segnalate.
local function normalizeWhen(when)
    if when == nil then return {} end
    if type(when) ~= "table" then return {}, "condizioni non valide" end
    local out, err = {}, nil
    for k, v in pairs(when) do
        local check = type(k) == "string" and CONDITIONS[k] or nil
        if not check then
            err = err or ("condizione sconosciuta: " .. tostring(k))
        else
            local nv = check(v)
            if nv == nil then err = err or ("valore non valido per " .. k) else out[k] = nv end
        end
    end
    return out, err
end

local function cleanPriority(p)
    if type(p) ~= "number" or p ~= p then return 0 end
    return math.max(-1000, math.min(1000, math.floor(p)))
end

local function newStore() return { version = VERSION, seq = 0, rules = {} } end

local function nextId(store, used)
    local id
    repeat
        store.seq = store.seq + 1
        id = "r" .. store.seq
    until not used[id]
    return id
end

-- Ripulisce una regola letta dal database (dato non fidato). nil = da scartare.
local function cleanRule(r, store, used)
    if type(r) ~= "table" then return nil end
    local out = {}
    local id = r.id
    if type(id) ~= "string" or id == "" or #id > 40 or used[id] then id = nextId(store, used) end
    used[id] = true
    out.id = id
    out.name = (type(r.name) == "string" and r.name ~= "") and r.name:sub(1, MAX_NAME) or id
    local when, err = normalizeWhen(r.when)
    out.when = when
    if err then out.invalid = err
    elseif type(r.invalid) == "string" then out.invalid = r.invalid:sub(1, 80) end
    out.profile = (type(r.profile) == "string" and #r.profile <= MAX_PROFILE) and r.profile or ""
    out.priority = cleanPriority(r.priority)
    if r.enabled == nil then out.enabled = true else out.enabled = r.enabled == true end
    return out
end

local function sanitizeStore(s)
    if not isNumber(s.version) or s.version < 1 then s.version = VERSION end
    if not isNumber(s.seq) or s.seq < 0 or s.seq > 1e9 then s.seq = 0 end
    s.seq = math.floor(s.seq)
    local list, used = {}, {}
    local raw = s.rules
    if type(raw) == "table" then
        local keys = {}
        for k in pairs(raw) do
            if type(k) == "number" and k >= 1 and k == math.floor(k) and k < 1e6 then keys[#keys + 1] = k end
        end
        table.sort(keys)
        for _, k in ipairs(keys) do
            if #list >= MAX_RULES then break end
            local r = cleanRule(raw[k], s, used)
            if r then list[#list + 1] = r end
        end
    end
    s.rules = list
end

-- Store sanitizzato (o nil se il database non e' pronto).
local function getStore()
    local DB = Badb.DB
    local sv = DB and DB.sv
    if type(sv) ~= "table" then return nil end
    if type(sv.global) ~= "table" then sv.global = {} end
    local s = sv.global.contextRules
    if type(s) ~= "table" then
        s = newStore()
        sv.global.contextRules = s
    end
    sanitizeStore(s)
    return s
end

local function profileExists(name)
    local sv = Badb.DB and Badb.DB.sv
    return type(name) == "string" and name ~= "" and type(sv) == "table"
        and type(sv.profiles) == "table" and type(sv.profiles[name]) == "table"
end

local function brokenReason(rule)
    if rule.invalid then return rule.invalid end
    if not profileExists(rule.profile) then return "profilo inesistente" end
    return nil
end

local function publicRule(rule)
    local out = copyTable(rule)
    out.broken = brokenReason(rule) ~= nil
    out.brokenReason = brokenReason(rule)
    out.invalid = nil
    return out
end

local function matches(when, ctx)
    for key, want in pairs(when) do
        local have = ctx[key]
        if key == "resting" or key == "pvpFlag" then have = have and true or false end
        -- Un ruolo solo ipotizzato dalla classe (talenti illeggibili, confidenza bassa) non basta per scegliere un
        -- profilo: un Sacerdote Shadow letto come "healer" cambierebbe profilo sbagliato. L'utente lo sblocca
        -- impostando il ruolo a mano (/badb role), che ha confidenza alta.
        if key == "role" and ctx.roleConfidence == "low" and have ~= "none" then return false end
        if have ~= want then return false end
    end
    return true
end

-- Valida i campi di una regola (completa per AddRule, parziale per UpdateRule).
local function validateFields(src, partial)
    if type(src) ~= "table" then return nil, "regola non valida" end
    local out = {}
    if src.when ~= nil or not partial then
        local when, err = normalizeWhen(src.when)
        if err then return nil, err end
        out.when = when
    end
    if src.profile ~= nil or not partial then
        if type(src.profile) ~= "string" or src.profile == "" or #src.profile > MAX_PROFILE then
            return nil, "profilo mancante o non valido"
        end
        out.profile = src.profile
    end
    if src.priority ~= nil then
        if not isNumber(src.priority) then return nil, "priorita' non valida" end
        out.priority = cleanPriority(src.priority)
    elseif not partial then out.priority = 0 end
    if src.enabled ~= nil then
        if type(src.enabled) ~= "boolean" then return nil, "enabled deve essere booleano" end
        out.enabled = src.enabled
    elseif not partial then out.enabled = true end
    if src.name ~= nil then
        if type(src.name) ~= "string" then return nil, "nome non valido" end
        out.name = src.name:sub(1, MAX_NAME)
    end
    return out
end

local function indexOf(store, id)
    if type(id) ~= "string" then return nil end
    for i, r in ipairs(store.rules) do
        if r.id == id then return i end
    end
end

---------------------------------------------------------------------------
-- API pubblica delle regole
---------------------------------------------------------------------------
function M:ListRules()
    local store = getStore()
    local list = {}
    if not store then return list end
    for i, r in ipairs(store.rules) do list[i] = publicRule(r) end
    return list
end

function M:GetRule(id)
    local store = getStore()
    local i = store and indexOf(store, id)
    return i and publicRule(store.rules[i]) or nil
end

-- Segnala che le regole sono cambiate: conta come cambio reale (azzera l'override manuale).
function M:Touch()
    self._dirty = true
    self:Request()
end

function M:AddRule(rule)
    local store = getStore()
    if not store then return nil, "database non pronto" end
    local f, err = validateFields(rule, false)
    if not f then return nil, err end
    if #store.rules >= MAX_RULES then return nil, "limite di regole raggiunto" end
    local used = {}
    for _, r in ipairs(store.rules) do used[r.id] = true end
    local id = rule.id
    if id ~= nil then
        if type(id) ~= "string" or id == "" or #id > 40 then return nil, "id non valido" end
        if used[id] then return nil, "id duplicato" end
    else
        id = nextId(store, used)
    end
    f.id = id
    f.name = (f.name and f.name ~= "") and f.name or describeWhen(f.when)
    store.rules[#store.rules + 1] = f
    self:Touch()
    return id
end

function M:UpdateRule(id, patch)
    local store = getStore()
    if not store then return false, "database non pronto" end
    local i = indexOf(store, id)
    if not i then return false, "regola inesistente" end
    local f, err = validateFields(patch, true)
    if not f then return false, err end
    local r = store.rules[i]
    for k, v in pairs(f) do r[k] = v end
    if f.when then r.invalid = nil end
    self:Touch()
    return true
end

function M:SetEnabled(id, value)
    if type(value) ~= "boolean" then return false, "valore non booleano" end
    return self:UpdateRule(id, { enabled = value })
end

function M:RemoveRule(id)
    local store = getStore()
    if not store then return false, "database non pronto" end
    local i = indexOf(store, id)
    if not i then return false, "regola inesistente" end
    table.remove(store.rules, i)
    self:Touch()
    return true
end

function M:MoveRule(id, delta)
    local store = getStore()
    if not store then return false, "database non pronto" end
    local i = indexOf(store, id)
    if not i then return false, "regola inesistente" end
    if not isNumber(delta) then return false, "spostamento non valido" end
    local n = #store.rules
    local j = math.max(1, math.min(n, i + math.floor(delta)))
    if j ~= i then
        local r = table.remove(store.rules, i)
        table.insert(store.rules, j, r)
        self:Touch()
    end
    return true
end

-- Regola vincente per un contesto: abilitata, non rotta, condizioni in AND,
-- priorita' piu' alta; a parita' vince l'ordine di lista.
local function pick(ctx)
    local store = getStore()
    if not store then return nil end
    local best
    for _, r in ipairs(store.rules) do
        if r.enabled and not brokenReason(r) and matches(r.when, ctx) then
            if not best or r.priority > best.priority then best = r end
        end
    end
    return best
end

-- Valutazione "a secco": non cambia nulla. ctx opzionale (tabella) per simulazioni.
-- Ritorna profileName, ruleId (nil se nessuna regola corrisponde).
function M:Evaluate(ctx)
    local ok, rule = pcall(function()
        return pick(type(ctx) == "table" and ctx or self:GetCurrent())
    end)
    if ok and rule then return rule.profile, rule.id end
    if not ok then Logger:Error("Contexts:Evaluate - %s", tostring(rule)) end
    return nil
end

---------------------------------------------------------------------------
-- Regole base per classe
---------------------------------------------------------------------------
-- Schema: kind, condizioni, priorita', chiave template Presets "<classe>-<mode>-<scenario>"
local CLASS_RULE_KINDS = {
    { kind = "av", when = { instance = "pvp", pvpKind = "av" }, priority = 30, preset = "pvp-av", label = "Alterac Valley" },
    { kind = "pvp", when = { instance = "pvp" }, priority = 20, preset = "pvp-bg", label = "Campo di battaglia" },
    { kind = "raid", when = { instance = "raid" }, priority = 20, preset = "pve-raid", label = "Raid" },
    { kind = "party", when = { instance = "party" }, priority = 10, preset = "pve-dungeon", label = "Dungeon" },
    { kind = "solo", when = { instance = "none", group = "solo" }, priority = 0, preset = "pve-solo", label = "Solo" },
}

-- Crea (o aggiorna, mai duplica) le regole base di una classe: BG -> PvP, raid -> PvE raid,
-- dungeon -> dungeon, (opz.) mondo da solo. `profiles` = { pvp=, raid=, party=, solo= } con i NOMI profilo
-- scelti dal chiamante (es. quelli creati da Presets:Apply in modalita' "new-profile"); i tipi senza nome
-- sono saltati. Alterac (kind "av", condizione pvpKind=av, priorita' maggiore) ha un profilo a parte; senza `profiles.av` vale la regola "pvp" anche li'. Il rilevamento di Alterac non e' verificato in gioco.
-- Ritorna { ids = {...}, skipped = {...} } oppure nil, err.
function M:AddRulesForClass(classToken, profiles)
    if type(classToken) ~= "string" then return nil, "classe non valida" end
    classToken = classToken:upper()
    if not classToken:match("^%u+$") or #classToken > 20 then return nil, "classe non valida" end
    local P = Badb.Player
    if type(P) == "table" and type(P.GetClassInfo) == "function" then
        local ok, info = pcall(P.GetClassInfo, P, classToken)
        if ok and not info then return nil, "classe sconosciuta: " .. classToken end
    end
    if type(profiles) ~= "table" then return nil, "profili mancanti" end
    local result = { ids = {}, skipped = {} }
    for _, def in ipairs(CLASS_RULE_KINDS) do
        local profile = profiles[def.kind]
        if type(profile) ~= "string" or profile == "" then
            result.skipped[#result.skipped + 1] = def.kind
        else
            local when = copyTable(def.when)
            when.class = classToken
            local name = def.label .. " " .. classToken
            -- Titolo del template (se esiste il modulo Presets): solo per etichettare la regola.
            local Pr = Badb.Presets
            if type(Pr) == "table" and type(Pr.Get) == "function" then
                local ok, d = pcall(Pr.Get, Pr, classToken:lower() .. "-" .. def.preset)
                if ok and type(d) == "table" and type(d.title) == "string" then name = d.title:sub(1, MAX_NAME) end
            end
            local id = "cls-" .. classToken:lower() .. "-" .. def.kind
            local ok, err
            if self:GetRule(id) then
                ok, err = self:UpdateRule(id, { name = name, when = when, profile = profile, priority = def.priority })
            else
                ok, err = self:AddRule({ id = id, name = name, when = when, profile = profile, priority = def.priority })
            end
            if ok then
                result.ids[#result.ids + 1] = id
            else
                result.skipped[#result.skipped + 1] = def.kind .. " (" .. tostring(err) .. ")"
            end
        end
    end
    return result
end

---------------------------------------------------------------------------
-- Motore: eventi, debounce, isteresi, combattimento
---------------------------------------------------------------------------
local function coreTalentGroup()
    -- Stessa lettura del core (Database.lua): Badb.Player se c'e'.
    local P = Badb.Player
    if type(P) == "table" and type(P.GetTalentGroup) == "function" then
        local ok, g = pcall(P.GetTalentGroup, P)
        if ok and isNumber(g) then return g end
    end
    local g = probe(_G.GetActiveTalentGroup)
    if not isNumber(g) then g = probe(_G.GetSpecialization) end
    return g
end

local function coreSpecProfile()
    -- Profilo-per-spec del core (DB:SetSpecProfile) per il gruppo talenti attuale, se esiste.
    local DB = Badb.DB
    local sv = DB and DB.sv
    local map = type(sv) == "table" and type(sv.specProfiles) == "table" and sv.specProfiles[DB.char]
    if type(map) ~= "table" then return nil end
    local group = coreTalentGroup()
    local name = group ~= nil and map[group] or nil
    if profileExists(name) then return name end
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function M:Option(path, default)
    local DB = Badb.DB
    if not DB or not DB.profile or not DB.profile.modules or type(DB.profile.modules[self.name]) ~= "table" then
        return default
    end
    local v = self:Get(path)
    if v == nil then return default end
    return v
end

-- Pianifica una valutazione (debounce a fronte iniziale: gli eventi entro la finestra
-- vengono assorbiti dal timer gia' in corso).
function M:Schedule(delay)
    if not self._active then return end
    local due = clock() + delay
    if self._timerOn and self._timerDue <= due + 0.001 then return end
    self._timerTok = (self._timerTok or 0) + 1
    local tok, gen = self._timerTok, self._gen
    self._timerOn, self._timerDue = true, due
    local function fire()
        if gen ~= M._gen or tok ~= M._timerTok then return end
        M._timerOn = false
        local ok, err = pcall(M.Run, M)
        if not ok then Logger:Error("Contexts: %s", tostring(err)) end
    end
    local timer = _G.C_Timer
    if type(timer) == "table" and type(timer.After) == "function" then
        if not pcall(timer.After, delay, fire) then fire() end
    else
        fire()
    end
end

function M:Request()
    self:Schedule(DEBOUNCE)
end

-- Esegue la valutazione fuori dal combattimento (in combattimento resta in coda).
function M:Run()
    if not self._active then return end
    local gen = self._gen
    Events:RunOutOfCombat("contextEval", function() M:_run(gen, false) end)
end

function M:_switchTo(profile, ruleId)
    local DB = Badb.DB
    self._applying = true
    local ok, err = pcall(DB.SetProfile, DB, profile)
    self._applying = false
    if not ok then
        Logger:Error("Contexts: cambio profilo fallito - %s", tostring(err))
        return false
    end
    self._lastSwitch = clock()
    self._manual = false
    self.stats.switches = self.stats.switches + 1
    Logger:Debug("Contesto: profilo '%s'%s", profile, ruleId and (" (regola " .. ruleId .. ")") or " (profilo base)")
    if ruleId then Events:Fire("BADB_RULE_MATCHED", ruleId, profile) end
    return true
end

function M:_run(gen, force)
    if not self._active or gen ~= self._gen then return end
    local DB = Badb.DB
    if not DB or not DB.sv or not DB.profile then return end
    self.stats.evals = self.stats.evals + 1

    -- Cambio profilo avvenuto fuori dal motore: spec-profile del core oppure scelta manuale.
    local foreign = self._foreign
    self._foreign = nil
    if foreign then
        if self._specPending and coreSpecProfile() == foreign then
            self._specPending = false
        else
            self._manual = true
        end
    end

    local ctx = self:GetCurrent()
    local changed = not ctxEqual(self._ctx, ctx)
    local dirty = self._dirty
    self._dirty = false
    if changed then
        self._ctx = ctx
        self._manual = false
        Events:Fire("BADB_CONTEXT_CHANGED", copyTable(ctx))
        if not self._active or gen ~= self._gen then return end
    elseif dirty then
        self._manual = false
    end

    local cs = coreSpecProfile()
    if not cs or cs == DB:GetProfileName() then self._specPending = false end

    if force then self._manual = false end
    if not force and self:Option("autoSwitch", true) ~= true then return end
    if not force and self._manual and self:Option("respectManual", true) ~= false then return end

    local rule = pick(ctx)
    local profile, ruleId
    if rule then
        profile, ruleId = rule.profile, rule.id
    else
        if cs then return end -- nessuna regola: decide il profilo-per-spec del core
        local fb = self:Option("fallbackProfile", "")
        if profileExists(fb) then profile = fb end
    end
    if not profile or profile == DB:GetProfileName() then return end

    if not force then
        local cooldown = clamp(tonumber(self:Option("switchCooldown", 3)) or 3, 0, 60)
        local elapsed = self._lastSwitch and (clock() - self._lastSwitch)
        if elapsed and elapsed < cooldown then
            self:Schedule(cooldown - elapsed + 0.05) -- riprova a isteresi scaduta, con contesto fresco
            return
        end
    end
    self:_switchTo(profile, ruleId)
end

-- Valutazione immediata (ignora debounce, isteresi, override manuale e opzione auto-switch).
function M:Apply()
    if not self._active then return false, "modulo disattivo" end
    local gen = self._gen
    Events:RunOutOfCombat("contextEval", function() M:_run(gen, true) end)
    return true
end

---------------------------------------------------------------------------
-- Ciclo di vita
---------------------------------------------------------------------------
-- Ruolo/classe/talenti: li segnala Badb.Player con BADB_PLAYER_CHANGED (nessun evento di spec/ruolo nostro).
local RELEVANT_EVENTS = {
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "PLAYER_UPDATE_RESTING",
    "PLAYER_FLAGS_CHANGED", "BADB_PLAYER_CHANGED",
}

function M:OnEnable()
    self._gen = (self._gen or 0) + 1
    self._active = true
    self._timerOn, self._manual, self._dirty = false, false, true
    self._foreign, self._specPending, self._applying = nil, false, false
    self._ctx, self._lastSwitch = nil, nil

    for _, ev in ipairs(RELEVANT_EVENTS) do
        self:On(ev, function() self:Request() end)
    end
    -- Eventi di spec: servono SOLO a riconoscere lo switch del profilo-per-spec del core (che li ascolta
    -- entrambi) e a non scambiarlo per un override manuale. La valutazione arriva da BADB_PLAYER_CHANGED.
    local function onSpec(_, unit)
        if unit ~= nil and unit ~= "player" then return end
        self._specPending = true
        self:Request()
    end
    self:On("UNIT_FACTION", function(_, unit)
        if unit == nil or unit == "player" then self:Request() end
    end)
    self:On("PLAYER_SPECIALIZATION_CHANGED", onSpec)
    self:On("ACTIVE_TALENT_GROUP_CHANGED", onSpec)

    self:On("BADB_PROFILE_CHANGED", function(_, name)
        if self._applying then return end -- l'ha causato il motore: nessuna rivalutazione
        self._foreign = name or ""
        self:Request()
    end)
    self:On("BADB_OPTION_CHANGED", function(_, module)
        if module == self.name then self:Touch() end
    end)
    self:On("BADB_CONTEXT_CHANGED", function() self:RefreshPage() end)
    self:On("BADB_RULE_MATCHED", function() self:RefreshPage() end)

    self:Request()
end

function M:OnDisable()
    self._active = false
    self._gen = (self._gen or 0) + 1 -- invalida timer e azioni differite
    self._timerOn, self._dirty, self._manual = false, false, false
    self._foreign, self._specPending, self._applying = nil, false, false
    Events:OffAll(self)
end

---------------------------------------------------------------------------
-- Comandi: /badb context status | list | eval [apply]
---------------------------------------------------------------------------
local function ctxText(ctx)
    return string.format("istanza=%s gruppo=%s ruolo=%s%s spec=%s classe=%s riposo=%s flagPvP=%s",
        ctx.instance, ctx.group, ctx.role, ctx.roleConfidence ~= "high" and ("(" .. tostring(ctx.roleConfidence) .. ")") or "",
        tostring(ctx.spec), ctx.class ~= "" and ctx.class or "?", ctx.resting and "si" or "no",
        ctx.pvpFlag and "si" or "no")
end

function M:StatusText()
    local ctx = self:GetCurrent()
    local profile, ruleId = self:Evaluate(ctx)
    local rule = ruleId and self:GetRule(ruleId)
    local win = rule and string.format("%s -> %s", rule.name, rule.profile) or "nessuna"
    return ctxText(ctx), win, profile
end

M.commands = {
    context = {
        help = "context status | list | eval [apply]",
        fn = function(args)
            local sub, rest = strtrim(tostring(args or "")):match("^(%S*)%s*(.-)$")
            sub = (sub or ""):lower()
            if sub == "" or sub == "status" then
                local c, win = M:StatusText()
                local DB = Badb.DB
                Logger:Info("Contesti: auto-switch %s%s", M:Option("autoSwitch", true) == true and "attivo" or "spento",
                    M._manual and " (sospeso: cambio manuale)" or "")
                Logger:Info("Contesto: %s", c)
                Logger:Info("Regola vincente: %s (profilo attivo: %s)", win, DB and DB:GetProfileName() or "?")
            elseif sub == "list" then
                local rules = M:ListRules()
                if #rules == 0 then Logger:Info("Nessuna regola. Creala dalla pagina Contesti.") end
                for i, r in ipairs(rules) do
                    Logger:Info("%d. [%s] %s: %s -> %s (priorita' %d)%s%s", i, r.id, r.name, describeWhen(r.when),
                        r.profile ~= "" and r.profile or "?", r.priority, r.enabled and "" or " [disattivata]",
                        r.broken and (" [ROTTA: " .. tostring(r.brokenReason) .. "]") or "")
                end
            elseif sub == "eval" then
                if rest:lower() == "apply" then
                    local ok, err = M:Apply()
                    Logger:Info(ok and "Valutazione eseguita." or ("Valutazione non eseguita: " .. tostring(err)))
                else
                    local c, win, profile = M:StatusText()
                    Logger:Info("Contesto: %s", c)
                    Logger:Info("Valutazione: %s (profilo %s). Usa 'eval apply' per applicarlo.", win, profile or "-")
                end
            else
                Logger:Info("/badb context status | list | eval [apply]")
            end
        end,
    },
}

---------------------------------------------------------------------------
-- Pagina ConfigUI (widget costruiti localmente: serve solo CreateFrame)
---------------------------------------------------------------------------
local ROW_H = 24
local page -- stato della pagina costruita (nil finche' non viene aperta)

local function text(parent, x, y, w, template)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    fs:SetWidth(w)
    fs:SetJustifyH("LEFT")
    return fs
end

local function button(parent, x, y, w, label, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

-- Bottone ciclico: ogni click passa al valore successivo (nil = "Qualsiasi").
local function cycle(parent, x, y, w, label, values, get, set, fmt, nilText)
    local b
    local function show()
        local v = get()
        b:SetText(label .. ": " .. (v == nil and (nilText or "qualsiasi") or fmt(v)))
    end
    b = button(parent, x, y, w, label, function()
        local list = values()
        local cur, idx = get(), 0
        for i, v in ipairs(list) do if v == cur then idx = i end end
        set(list[idx + 1]) -- oltre l'ultimo => nil
        show()
    end)
    b.Refresh = show
    show()
    return b
end

function M:RefreshPage()
    if not page then return end
    pcall(function()
        local c, win = self:StatusText()
        page.ctxLine:SetText("Contesto: " .. c)
        page.winLine:SetText("Regola vincente: " .. win)
        local rules = self:ListRules()
        for i, row in ipairs(page.rows) do
            local r = rules[i]
            if r then
                row.rule = r.id
                row.check:SetChecked(r.enabled)
                local label = string.format("%s  |  %s -> %s  (prio %d)", r.name, describeWhen(r.when),
                    r.profile ~= "" and r.profile or "?", r.priority)
                if r.broken then
                    label = label .. "  [ROTTA: " .. tostring(r.brokenReason) .. "]"
                    row.label:SetTextColor(1, 0.3, 0.3)
                else
                    row.label:SetTextColor(r.enabled and 1 or 0.55, r.enabled and 1 or 0.55, r.enabled and 1 or 0.55)
                end
                row.label:SetText(label)
                row.frame:Show()
            else
                row.rule = nil
                row.frame:Hide()
            end
        end
        for _, b in ipairs(page.cycles) do b.Refresh() end
    end)
end

local function buildPage(parent)
    local form = { priority = 0 }
    page = { rows = {}, cycles = {}, form = form }
    M._page = page -- esposta per i test
    local DB = Badb.DB
    local y = 0

    page.ctxLine = text(parent, 0, y, 560); y = y + 18
    page.winLine = text(parent, 0, y, 560); y = y + 28

    local header = text(parent, 0, y, 560, "GameFontNormal")
    header:SetText("Nuova regola (le condizioni scelte valgono tutte insieme)")
    y = y + 24

    local function profiles()
        return (DB and DB.ListProfiles and DB:ListProfiles()) or {}
    end
    local function add(x, yy, label, values, key, fmt)
        page.cycles[#page.cycles + 1] = cycle(parent, x, yy, 180, label, values,
            function() return form[key] end, function(v) form[key] = v end, fmt or tostring)
    end
    local function labelFor(kind) return function(v) return LABELS[kind][v] or tostring(v) end end

    add(0, y, "Istanza", function() return GENERATED_INSTANCES end, "instance", labelFor("instance"))
    add(190, y, "Gruppo", function() return GROUPS end, "group", labelFor("group"))
    add(380, y, "Ruolo", function() return ROLES end, "role", labelFor("role"))
    y = y + 26
    add(0, y, "Spec", function() return { 1, 2, 3, 4 } end, "spec")
    add(190, y, "Classe", function()
        local P = Badb.Player
        if type(P) == "table" and type(P.ListClasses) == "function" then
            local ok, list = pcall(P.ListClasses, P, true)
            if ok and type(list) == "table" and #list > 0 then
                local tokens = {}
                for i, c in ipairs(list) do tokens[i] = c.token end
                return tokens
            end
        end
        return CLASSES
    end, "class")
    add(380, y, "Riposo", function() return { true, false } end, "resting", function(v) return v and "si" or "no" end)
    y = y + 26
    -- Il profilo non e' mai "qualsiasi": il ciclo riparte dal primo.
    local profileBtn
    profileBtn = cycle(parent, 0, y, 180, "Profilo", profiles,
        function() return form.profile or (DB and DB:GetProfileName()) end,
        function(v) form.profile = v or profiles()[1] end, tostring)
    page.cycles[#page.cycles + 1] = profileBtn
    page.cycles[#page.cycles + 1] = cycle(parent, 190, y, 180, "Priorita'",
        function() return { 0, 10, 20, 30, 40, 50, -10 } end,
        function() return form.priority end, function(v) form.priority = v or 0 end, tostring)
    add(380, y, "Flag PvP", function() return { true, false } end, "pvpFlag", function(v) return v and "si" or "no" end)
    y = y + 26
    page.feedback = text(parent, 190, y + 4, 370)
    page.createBtn = button(parent, 0, y, 180, "Crea regola", function()
        local when = { instance = form.instance, group = form.group, role = form.role,
            spec = form.spec, class = form.class, resting = form.resting, pvpFlag = form.pvpFlag }
        local id, err = M:AddRule({ when = when, profile = form.profile or (DB and DB:GetProfileName()),
            priority = form.priority })
        page.feedback:SetText(id and "Regola creata." or ("Errore: " .. tostring(err)))
        M:RefreshPage()
    end)
    y = y + 32

    local fallback = text(parent, 0, y + 4, 180)
    fallback:SetText("Se nessuna regola corrisponde:")
    page.cycles[#page.cycles + 1] = cycle(parent, 190, y, 250, "Profilo base",
        profiles,
        function()
            local v = M:Option("fallbackProfile", "")
            return v ~= "" and v or nil
        end,
        function(v) M:Set("fallbackProfile", v or "") end, tostring, "nessuno (lascia l'attuale)")
    y = y + 34

    local rulesHeader = text(parent, 0, y, 560, "GameFontNormal")
    rulesHeader:SetText("Regole (a parita' di priorita' vince la prima)")
    y = y + 24

    for i = 1, MAX_RULES do
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetSize(560, ROW_H)
        frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
        local row = { frame = frame }
        local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        check:SetScript("OnClick", function(self)
            if row.rule then M:SetEnabled(row.rule, self:GetChecked() and true or false) end
            M:RefreshPage()
        end)
        row.check = check
        row.label = text(frame, 28, 6, 368)
        row.up = button(frame, 400, 0, 40, "Su", function() if row.rule then M:MoveRule(row.rule, -1) end; M:RefreshPage() end)
        row.down = button(frame, 444, 0, 40, "Giu", function() if row.rule then M:MoveRule(row.rule, 1) end; M:RefreshPage() end)
        row.del = button(frame, 488, 0, 28, "X", function() if row.rule then M:RemoveRule(row.rule) end; M:RefreshPage() end)
        frame:Hide()
        page.rows[i] = row
        y = y + ROW_H
    end

    M:RefreshPage()
    return y + 10
end

M.page = {
    title = "Contesti",
    order = 30,
    category = "Gestione",
    build = function(parent) return buildPage(parent) end,
    refresh = function() M:RefreshPage() end,
}
