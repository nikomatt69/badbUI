-- BadbUI - Configurazione guidata (onboarding)
-- Finestra a passi in stile "hub": rail di navigazione a sinistra, contenuto a destra,
-- barra di avanzamento in basso. Porta a un layout completo in pochi click:
--   Benvenuto -> Ruolo -> [Template classe] -> [Contenuto] -> Dettagli -> [Regole] -> [Integrazioni] -> Riepilogo
-- oppure "Applica consigliato" direttamente dal primo passo.
-- I passi tra parentesi quadre sono opzionali: vengono saltati se il modulo che li serve
-- (Presets con template di classe, Contexts, Integrations) non e' disponibile.
-- Classe e ruolo vengono SEMPRE da Badb.Player (vedi docs/FOREVER_FACTS.md): se la confidenza del
-- ruolo non e' alta il passo "Ruolo" chiede conferma e salva la scelta con Player:SetRoleOverride.
--
-- Struttura del file:
--   1. helper e stato persistente (sv.global.wizard) + rilevamento
--   2. logica (passi, validazione, piano di esecuzione, backup, annulla): nessuna dipendenza dalla UI
--   3. UI (tema, shell, pagine, navigazione)
--   4. modulo "Wizard" (pagina config, /badb wizard, avvio automatico al primo login)
-- Usa il design system (Badb.Theme / Badb.UI) se presente, altrimenti un fallback locale
-- con la stessa palette, cosi' il wizard funziona anche da solo.
local _, ns = ...
local Badb = ns.Badb
local DB, Events, Logger = Badb.DB, Badb.Events, Badb.Logger

local Wizard = { step = 1, choices = {}, mode = "full", visited = {} }
Badb.Wizard = Wizard

-- Presets viene risolto a ogni uso (puo' mancare o essere sostituito: es. nei test).
local function P() return Badb.Presets end

local WIZARD_VERSION = 1
local AUTO_DELAY = 3
local MAX_STR, MAX_NAME = 64, 40
local frame, pages, railItems, refreshers = nil, {}, {}, {}

------------------------------------------------------------------------------
-- Helper generici
------------------------------------------------------------------------------
local function trim(s)
    s = tostring(s or "")
    s = s:gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
end

local function now()
    if type(time) == "function" then return time() end
    if os and os.time then return os.time() end
    return 0
end

-- Modulo opzionale: ritorna la tabella solo se espone il metodo richiesto.
local function avail(name, method)
    local m = Badb[name]
    if type(m) == "table" and type(m[method]) == "function" then return m end
end

-- Chiama Badb.<name>:<method>(...) senza mai lanciare. Ritorna called, r1, r2
-- (called=false se il modulo manca o il metodo ha generato un errore: r2 e' il messaggio).
local function invoke(name, method, ...)
    local m = avail(name, method)
    if not m then return false, nil, "modulo non disponibile: " .. name end
    local ok, a, b = pcall(m[method], m, ...)
    if not ok then return false, nil, tostring(a) end
    return true, a, b
end

-- Convenzione del contratto: ok, err. nil senza errore = successo (metodi che non ritornano nulla).
local function success(called, r1, r2)
    return called and r1 ~= false and not (r1 == nil and r2 ~= nil)
end

local function errText(r1, r2)
    if r2 ~= nil then return tostring(r2) end
    return "operazione non riuscita"
end

local function profileExists(name)
    return type(name) == "string" and DB.sv ~= nil and DB.sv.profiles ~= nil and DB.sv.profiles[name] ~= nil
end

local function listProfiles()
    local ok, l = pcall(DB.ListProfiles, DB)
    return (ok and type(l) == "table") and l or {}
end

local function uniqueProfileName(base)
    local name, n = base, 2
    while profileExists(name) and n < 1000 do
        name = string.format("%s (%d)", base, n); n = n + 1
    end
    return name
end

-- Nome profilo valido: non vuoto, corto, senza caratteri di controllo/colore, non esistente.
local function validateProfileName(name)
    name = trim(name)
    if name == "" then return false, "Scrivi un nome per il profilo." end
    if #name > MAX_NAME then return false, "Il nome del profilo e' troppo lungo (max " .. MAX_NAME .. ")." end
    if name:find("[%c|]") then return false, "Il nome del profilo contiene caratteri non validi." end
    if profileExists(name) then return false, "Esiste gia' un profilo chiamato '" .. name .. "'." end
    return true
end

------------------------------------------------------------------------------
-- Stato persistente: Badb.DB.sv.global.wizard (per account)
--   { completed, skipped, version, step, answers = {...}, completedAt, chars = { [pg] = true }, lastProfile }
-- Letto sempre tramite state(): normalizza in place, quindi un valore corrotto non genera errori.
------------------------------------------------------------------------------
local STR_KEYS = { role = true, content = true, templatePve = true, templatePvp = true, raidVariant = true,
    charProfile = true, charName = true }
local BOOL_KEYS = { pixelPerfect = true, hideClutter = true, friendlyPlates = true, useTemplate = true,
    ruleRaid = true, rulePvp = true }
local ENUMS = {
    templateMode = { pve = true, pvp = true, both = true },
    charMode = { existing = true, new = true },
}

local function cleanStr(v, max)
    if type(v) ~= "string" then return nil end
    return #v > max and v:sub(1, max) or v
end

-- Normalizza le risposte in place (l'identita' della tabella resta stabile: la UI la tiene per riferimento).
local function sanitizeChoices(a, root)
    if type(a) ~= "table" or a == root then a = {} end
    for k in pairs(a) do
        if STR_KEYS[k] then a[k] = cleanStr(a[k], MAX_STR)
        elseif BOOL_KEYS[k] then if type(a[k]) ~= "boolean" then a[k] = nil end
        elseif ENUMS[k] then if type(a[k]) ~= "string" or not ENUMS[k][a[k]] then a[k] = nil end
        elseif k == "integrations" then
            local v = a[k]
            if type(v) ~= "table" or v == a then a[k] = nil
            else
                local n = 0
                for id, val in pairs(v) do
                    n = n + 1
                    if type(id) ~= "string" or #id > MAX_STR or type(val) ~= "boolean" or n > 32 then v[id] = nil end
                end
            end
        else
            a[k] = nil
        end
    end
    return a
end

local fallbackGlobal -- usato solo se il DB non e' ancora inizializzato
local function globalTable()
    local sv = DB.sv
    if type(sv) ~= "table" then
        fallbackGlobal = fallbackGlobal or {}
        return fallbackGlobal
    end
    if type(sv.global) ~= "table" then sv.global = {} end
    return sv.global
end

local function state()
    local g = globalTable()
    local s = g.wizard
    if type(s) ~= "table" then s = {}; g.wizard = s end
    s.completed = s.completed == true
    s.skipped = s.skipped == true
    if type(s.version) ~= "number" then s.version = WIZARD_VERSION end
    if type(s.step) ~= "string" or #s.step > 32 then s.step = nil end
    if type(s.completedAt) ~= "number" then s.completedAt = nil end
    s.lastProfile = cleanStr(s.lastProfile, MAX_NAME * 2)
    s.answers = sanitizeChoices(s.answers, s)
    if type(s.chars) == "table" and s.chars ~= s then
        local n = 0
        for k, v in pairs(s.chars) do
            n = n + 1
            if type(k) ~= "string" or v ~= true or n > 200 then s.chars[k] = nil end
        end
    else
        s.chars = nil
    end
    -- Migrazione: il vecchio wizard salvava solo global.wizardDone.
    if g.wizardDone == true and not s.completed then
        s.completed = true
        s.chars = s.chars or {}
        if DB.char then s.chars[DB.char] = true end
    end
    return s
end

local function markChar(s)
    s.chars = s.chars or {}
    if DB.char then s.chars[DB.char] = true end
    local ok, name = pcall(DB.GetProfileName, DB)
    if ok and type(name) == "string" then s.lastProfile = name end
end

local function markDone(skipped)
    local s = state()
    s.completed, s.skipped, s.version = true, skipped and true or false, WIZARD_VERSION
    s.completedAt, s.step = now(), nil
    markChar(s)
    globalTable().wizardDone = true -- compatibilita' con il wizard precedente
end

function Wizard:IsCompleted() return state().completed end

-- Riporta il wizard allo stato iniziale: riparte al prossimo accesso (o con Start).
function Wizard:Reset()
    local g = globalTable()
    g.wizard = nil
    g.wizardDone = nil
    self.lastRun, self.stepId, self.visited, self.mode = nil, nil, {}, "full"
    self.choices = state().answers
    self:Close()
    return true
end

-- Istantanea dello stato (copia: modificarla non cambia nulla).
function Wizard:GetState()
    local s = state()
    local answers = {}
    for k, v in pairs(s.answers) do answers[k] = v end
    local steps = self:GetSteps()
    local idx = self:StepIndex()
    return {
        completed = s.completed, skipped = s.skipped, version = s.version, completedAt = s.completedAt,
        mode = self.mode, active = self.wasOpen and true or false,
        step = steps[idx] and steps[idx].key or nil, stepIndex = idx, stepCount = #steps,
        answers = answers,
    }
end

-- "full" se non completato; "short" (solo scelta del profilo) per un personaggio nuovo quando
-- l'account ha gia' completato il wizard; nil se non c'e' nulla da proporre.
function Wizard:DetectMode()
    local s = state()
    if not s.completed then return "full" end
    if not s.skipped and type(s.chars) == "table" and DB.char and not s.chars[DB.char] then return "short" end
end

------------------------------------------------------------------------------
-- Rilevamento: classe e ruolo (da Badb.Player), template di classe, ambiente
------------------------------------------------------------------------------
local function playerSnapshot()
    local Pl = Badb.Player
    if type(Pl) ~= "table" or type(Pl.GetSnapshot) ~= "function" then return nil end
    local ok, snap = pcall(Pl.GetSnapshot, Pl)
    if ok and type(snap) == "table" then return snap end
end

-- Token della classe (WARRIOR, PRIEST, ...) dal servizio Badb.Player; nil se non disponibile.
function Wizard.DetectClass()
    local s = playerSnapshot()
    local c = s and s.class
    if type(c) == "string" and c ~= "" then return c end
end

local function classRolesSet(class)
    local Pl = Badb.Player
    if not class or type(Pl) ~= "table" then return nil end
    local info
    if type(Pl.GetClassInfo) == "function" then
        local ok, i = pcall(Pl.GetClassInfo, Pl, class)
        if ok then info = i end
    end
    if not info and type(Pl.CLASSES) == "table" then
        for _, c in ipairs(Pl.CLASSES) do if type(c) == "table" and c.token == class then info = c; break end end
    end
    if type(info) ~= "table" or type(info.roles) ~= "table" then return nil end
    local set = {}
    for _, r in ipairs(info.roles) do set[r] = true end
    return set
end

-- Ruolo rilevato: { role, source, confidence, needsConfirm, allowed = {ruolo=true}|nil, class }.
-- needsConfirm: confidenza non alta o ruolo ambiguo (Druido Feral, Paladino...).
function Wizard.RoleInfo()
    local s = playerSnapshot()
    if not s then return { needsConfirm = false } end
    local class = type(s.class) == "string" and s.class or nil
    return {
        role = s.role, source = s.roleSource, confidence = s.roleConfidence, class = class,
        needsConfirm = (s.roleConfidence ~= "high") or s.roleAmbiguous == true,
        allowed = classRolesSet(class),
    }
end

-- Template della classe del giocatore per modalita' ("pve" | "pvp"): massimo 3.
-- Degrada a lista vuota se Presets non supporta class/mode o Badb.Player manca.
local function classTemplates(mode)
    local Pr = P()
    if not (Pr and type(Pr.List) == "function" and type(Pr.Get) == "function") then return {} end
    local cls = Wizard.DetectClass()
    if not cls then return {} end
    local ok, list = pcall(Pr.List, Pr, { class = cls, mode = mode })
    if not ok or type(list) ~= "table" then return {} end
    local out = {}
    for _, def in ipairs(list) do
        -- filtro difensivo: se List ignora class/mode, selezioniamo noi
        if type(def) == "table" and type(def.key) == "string" and def.mode == mode
            and (def.class == nil or def.class == cls) then
            out[#out + 1] = def
            if #out >= 3 then break end
        end
    end
    return out
end
function Wizard:ClassTemplates(mode) return classTemplates(mode) end

local function templatesSupported()
    return #classTemplates("pve") > 0 or #classTemplates("pvp") > 0
end

local function usingTemplate()
    return Wizard.choices.useTemplate ~= false and templatesSupported()
end

local function findDef(list, key)
    for _, d in ipairs(list) do if d.key == key then return d end end
end

-- Dimensioni raid disponibili per un template (def.variants = { ["10"]=..., ["20"]=..., ["40"]=... }), ordinate.
local function variantsOf(def)
    local out = {}
    if type(def) == "table" and type(def.variants) == "table" then
        for k in pairs(def.variants) do if type(k) == "string" or type(k) == "number" then out[#out + 1] = tostring(k) end end
        table.sort(out, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
    end
    return out
end
Wizard.VariantsOf = variantsOf

local function contextsAvailable()
    return avail("Contexts", "AddRule") ~= nil or avail("Contexts", "AddRulesForClass") ~= nil
end

-- Integrazioni caricate e supportate (massimo 6).
local function integrationList()
    local called, list = invoke("Integrations", "List")
    local out = {}
    if called and type(list) == "table" then
        for _, it in ipairs(list) do
            if type(it) == "table" and type(it.id) == "string" and it.loaded and it.supported ~= false then
                out[#out + 1] = it
                if #out >= 6 then break end
            end
        end
    end
    return out
end

local function safeRecommend()
    local Pr = P()
    local ok, rec = false, nil
    if Pr and type(Pr.Recommend) == "function" then ok, rec = pcall(Pr.Recommend, Pr) end
    if not ok or type(rec) ~= "table" then
        rec = { content = "leveling", role = "dps", pixelPerfect = true, hideClutter = false, friendlyPlates = false }
    end
    return rec
end

-- Sceglie il template raccomandato: chiave esplicita, poi scenario coerente col contenuto consigliato.
local SCENARIO = { leveling = "solo", dungeon = "dungeon", raid = "raid", pvp = "bg" }
local function pickTemplate(list, rec)
    if #list == 0 then return nil end
    if type(rec.key) == "string" and findDef(list, rec.key) then return rec.key end
    local want = SCENARIO[rec.content]
    if want then
        for _, d in ipairs(list) do
            if d.scenario == want or (d.scenario == nil and d.key:find("-" .. want, 1, true)) then return d.key end
        end
    end
    return list[1].key
end

-- Completa le risposte mancanti con i valori consigliati (non sovrascrive mai scelte esistenti).
function Wizard:EnsureChoices()
    local c = self.choices
    local rec = safeRecommend()
    for _, k in ipairs({ "content", "pixelPerfect", "hideClutter", "friendlyPlates" }) do
        if c[k] == nil and rec[k] ~= nil then c[k] = rec[k] end
    end
    if c.role == nil then
        local ri = Wizard.RoleInfo()
        c.role = (ri.allowed and ri.role and ri.allowed[ri.role]) and ri.role or rec.role
    end
    if templatesSupported() then
        if c.useTemplate == nil then c.useTemplate = true end
        local pve, pvp = classTemplates("pve"), classTemplates("pvp")
        -- Presets:RecommendTemplate() (se esiste) sa gia' scegliere template e variante dal contesto attuale.
        local called, rkey, ropts = invoke("Presets", "RecommendTemplate")
        if called and type(rkey) == "string" then
            rec.key = rkey
            if findDef(pve, rkey) then rec.mode = "pve" elseif findDef(pvp, rkey) then rec.mode = "pvp" end
            if type(ropts) == "table" and ropts.variant ~= nil then rec.variant = tostring(ropts.variant) end
        end
        if c.templateMode == nil then
            local want = (rec.mode == "pvp" or rec.content == "pvp") and "pvp" or "pve"
            if want == "pve" and #pve == 0 then want = "pvp" end
            if want == "pvp" and #pvp == 0 then want = "pve" end
            c.templateMode = want
        end
        if not findDef(pve, c.templatePve) then c.templatePve = pickTemplate(pve, rec) end
        if not findDef(pvp, c.templatePvp) then c.templatePvp = pickTemplate(pvp, rec) end
        local vs = variantsOf(findDef(pve, c.templatePve))
        if #vs > 0 then
            local ok = false
            for _, v in ipairs(vs) do if v == c.raidVariant then ok = true end end
            if not ok then
                c.raidVariant = vs[math.min(2, #vs)]
                for _, v in ipairs(vs) do if v == rec.variant then c.raidVariant = v end end
            end
        end
    end
    if self.mode == "short" then
        local s = state()
        if c.charMode == nil then c.charMode = "existing" end
        if not profileExists(c.charProfile) then
            c.charProfile = profileExists(s.lastProfile) and s.lastProfile or DB:GetProfileName()
        end
        if c.charName == nil then
            c.charName = uniqueProfileName("Badb - " .. ((UnitName and UnitName("player")) or "Profilo"))
        end
    end
end

-- Ambiente rilevato (passo di benvenuto): versione client, Edit Mode, avvisi della diagnostica
-- (addon UI in conflitto come ClassicUI Forever, ElvUI... se Badb.Diagnostics esiste).
function Wizard:DetectEnvironment()
    local env = { addon = Badb.version, interface = Badb.Compat and Badb.Compat.interface,
        editMode = Badb.Compat and Badb.Compat.hasEditMode and true or false, issues = {}, diagnostics = false }
    local ok, v = pcall(GetBuildInfo)
    if ok then env.client = v end
    local called, res = invoke("Diagnostics", "RunChecks")
    if called then
        env.diagnostics = true
        if type(res) == "table" then
            for _, r in ipairs(res) do
                if type(r) == "table" and (r.level == "warn" or r.level == "error") then
                    env.issues[#env.issues + 1] = tostring(r.title or r.id or "?")
                    if #env.issues >= 8 then break end
                end
            end
        end
    end
    return env
end

------------------------------------------------------------------------------
-- Passi (data-driven)
--   key, title      identificativo e testo nella rail
--   modes           { full = true, short = true }: in quali modalita' compare
--   applicable(c)   opzionale: false = passo saltato automaticamente (modulo mancante, nulla da scegliere)
--   validate(c)     opzionale: ok, err. Se ok == false "Avanti" e' bloccato e err e' mostrato
--   plan(c, names)  opzionale: elenco di azioni { id, label, destructive, optional, run(rec) -> ok, err }
--   apply(c)        generata dal motore: esegue le azioni del passo (utile per usarlo da solo)
-- La UI di ogni passo e' in Builders[key] (sezione UI).
------------------------------------------------------------------------------
local CLUTTER = { "MicroMenu", "BagsBar", "StatusTracking" }

local function pushUndo(rec, label, fn)
    if #rec.undo < 60 then rec.undo[#rec.undo + 1] = { label = label, fn = fn } end
end

local function undoPresets()
    local called, r1, r2 = invoke("Presets", "Undo")
    if success(called, r1, r2) then return true end
    return false, errText(r1, r2)
end

local function validateRole(c)
    local Pr = P()
    if not c.role or (Pr and type(Pr.roles) == "table" and not Pr.roles[c.role]) then
        return false, "Scegli il tuo ruolo."
    end
    local allowed = Wizard.RoleInfo().allowed
    if allowed and not allowed[c.role] then return false, "La tua classe non puo' avere questo ruolo." end
    return true
end

local function validateContent(c)
    local Pr = P()
    if not c.content or (Pr and type(Pr.content) == "table" and not Pr.content[c.content]) then
        return false, "Scegli cosa giochi di piu'."
    end
    return true
end

local function validateTemplate(c)
    if not usingTemplate() then return true end
    local mode = c.templateMode
    if mode ~= "pve" and mode ~= "pvp" and mode ~= "both" then return false, "Scegli PvE, PvP o entrambi." end
    if mode ~= "pvp" then
        local def = findDef(classTemplates("pve"), c.templatePve)
        if not def then return false, "Scegli un template PvE." end
        local vs = variantsOf(def)
        if #vs > 0 then
            local ok = false
            for _, v in ipairs(vs) do if v == c.raidVariant then ok = true end end
            if not ok then return false, "Scegli la dimensione del raid." end
        end
    end
    if mode ~= "pve" and not findDef(classTemplates("pvp"), c.templatePvp) then
        return false, "Scegli un template PvP."
    end
    return true
end

local function validateCharProfile(c)
    if c.charMode == "new" then return validateProfileName(c.charName) end
    if not profileExists(c.charProfile) then return false, "Scegli un profilo esistente." end
    return true
end

------------------------------------------------------------------------------
-- Azioni del piano
------------------------------------------------------------------------------
local function describeTemplate(def, variant)
    local called, d = invoke("Presets", "Diff", def.key)
    local n = (called and type(d) == "table") and #d or nil
    local extra = variant and (" - raid a " .. variant) or ""
    return string.format("Template '%s'%s (%s) in un nuovo profilo", tostring(def.title or def.key), extra,
        n and (n .. " modifiche") or "anteprima non disponibile")
end

local function templateAction(def, slot, c, names, variant)
    local base = "Badb - " .. tostring(def.title or def.key) .. (variant and (" " .. variant) or "")
    return {
        id = "template-" .. slot, destructive = true, label = describeTemplate(def, variant),
        run = function(rec)
            local opts = { mode = "new-profile", profileName = uniqueProfileName(base), role = c.role, variant = variant }
            local called, r1, r2 = invoke("Presets", "Apply", def.key, opts)
            if not success(called, r1, r2) then return false, errText(r1, r2) end
            names[slot] = DB:GetProfileName()
            pushUndo(rec, "Annulla il template " .. def.key, undoPresets)
            return true
        end,
    }
end

local function genericPresetAction(c)
    local Pr = P()
    if not (Pr and type(Pr.Build) == "function" and type(Pr.Apply) == "function") then return nil end
    local okB, spec = pcall(Pr.Build, Pr, c)
    if not okB or type(spec) ~= "table" then return nil end
    return {
        id = "preset", destructive = true,
        label = string.format("Crea il profilo 'Badb - %s' dal preset", tostring(spec.title or "?")),
        run = function(rec)
            local ok, name = pcall(Pr.Apply, Pr, spec)
            if not ok then return false, tostring(name) end
            if not name then return false, "applicazione non riuscita (combattimento o errore)" end
            if type(Pr.Undo) == "function" then pushUndo(rec, "Annulla il preset", undoPresets) end
            return true
        end,
    }
end

local function roleAction(c)
    local ri = Wizard.RoleInfo()
    if not (ri.needsConfirm and c.role and avail("Player", "SetRoleOverride")) then return nil end
    return {
        id = "role", label = "Salva il ruolo confermato: " .. c.role,
        run = function(rec)
            local called, r1, r2 = invoke("Player", "SetRoleOverride", c.role)
            if not success(called, r1, r2) then return false, errText(r1, r2) end
            pushUndo(rec, "Rimuovi la conferma del ruolo", function()
                local c2, a, b = invoke("Player", "SetRoleOverride", nil)
                if success(c2, a, b) then return true end
                return false, errText(a, b)
            end)
            return true
        end,
    }
end

local function detailActions(c)
    local list = {}
    if c.hideClutter then
        list[#list + 1] = {
            id = "hide-clutter", destructive = true, label = "Nascondi micro menu, barra borse e barra esperienza",
            run = function(rec)
                local failed
                for _, key in ipairs(CLUTTER) do
                    local called, r1, r2 = invoke("FrameManager", "SetOption", key, "hidden", true)
                    if not called then failed = failed or r2 end
                    pushUndo(rec, "Mostra " .. key, function()
                        local c2, a, b = invoke("FrameManager", "Restore", key)
                        return c2 and true or false, b
                    end)
                end
                if failed then return false, failed end
                return true
            end,
        }
    end
    local function option(id, label, module, key, value)
        list[#list + 1] = {
            id = id, label = label,
            run = function()
                local ok, err = pcall(DB.Set, DB, module, key, value)
                if not ok then return false, tostring(err) end
                return true
            end,
        }
    end
    -- Con un template il profilo e' gia' completo: i toggle attivi si aggiungono, quelli spenti non lo sovrascrivono.
    if c.pixelPerfect then option("pixel", "Scala UI pixel perfect", "Scaling", "pixelPerfect", true) end
    if c.friendlyPlates then option("plates", "Mostra le nameplate degli alleati", "Nameplates", "showFriends", true) end
    return list
end

local function ruleNames()
    local set = {}
    local called, rules = invoke("Contexts", "ListRules")
    if called and type(rules) == "table" then
        for _, r in ipairs(rules) do if type(r) == "table" and r.name then set[r.name] = true end end
    end
    return set
end

-- Regola semplice "contesto -> profilo": crea (se serve) una copia del profilo attivo e la associa.
local function copyRuleAction(label, ruleName, instance, suffix)
    return {
        id = "rule-" .. instance, label = label,
        run = function(rec)
            if not avail("Contexts", "AddRule") then return false, "modulo non disponibile: Contexts" end
            local active = DB:GetProfileName()
            local target = uniqueProfileName(active .. suffix)
            local okc, errc = DB:CopyProfile(active, target)
            if not okc then return false, errc or "copia del profilo non riuscita" end
            pushUndo(rec, "Elimina il profilo " .. target, function()
                local ok, err = DB:DeleteProfile(target)
                return ok ~= false, err
            end)
            if ruleNames()[ruleName] then return true end
            local called, id, err = invoke("Contexts", "AddRule",
                { name = ruleName, when = { instance = instance }, profile = target, priority = 50, enabled = true })
            if not called or not id then return false, err or "regola non creata" end
            pushUndo(rec, "Rimuovi la regola " .. ruleName, function()
                local c2, a, b = invoke("Contexts", "RemoveRule", id)
                if success(c2, a, b) then return true end
                return false, errText(a, b)
            end)
            return true
        end,
    }
end

-- "Entrambi": regole automatiche della classe (campi di battaglia -> profilo PvP, raid/dungeon -> PvE).
local function classRulesAction(names)
    return {
        id = "rules-class",
        label = "Regole automatiche: campi di battaglia con il profilo PvP, il resto con il PvE",
        run = function(rec)
            local class = Wizard.DetectClass()
            local function removeUndo(id)
                pushUndo(rec, "Rimuovi la regola " .. tostring(id), function()
                    local c2, a, b = invoke("Contexts", "RemoveRule", id)
                    if success(c2, a, b) then return true end
                    return false, errText(a, b)
                end)
            end
            if avail("Contexts", "AddRulesForClass") then
                -- Nomi profilo scelti da noi: BG/AV -> PvP; raid, dungeon e mondo -> PvE.
                local called, r1, r2 = invoke("Contexts", "AddRulesForClass", class,
                    { pvp = names.pvp, raid = names.pve, party = names.pve, solo = names.pve })
                if not success(called, r1, r2) then return false, errText(r1, r2) end
                local ids = type(r1) == "table" and (r1.ids or r1) or nil
                if type(ids) == "table" then
                    for _, id in ipairs(ids) do if type(id) == "string" or type(id) == "number" then removeUndo(id) end end
                end
                return true
            end
            -- Fallback: una regola semplice per i campi di battaglia (nessuna arena su Forever).
            if not names.pvp then return false, "profilo PvP non disponibile" end
            if ruleNames()["Wizard: PvP"] then return true end
            local called, id, err = invoke("Contexts", "AddRule",
                { name = "Wizard: PvP", when = { instance = "pvp" }, profile = names.pvp, priority = 50, enabled = true })
            if not called or not id then return false, err or "regola non creata" end
            removeUndo(id)
            return true
        end,
    }
end

local function integrationActions(c)
    local list = {}
    if type(c.integrations) ~= "table" then return list end
    for _, it in ipairs(integrationList()) do
        if c.integrations[it.id] then
            list[#list + 1] = {
                id = "integration-" .. it.id, label = "Salva nel profilo la configurazione di " .. tostring(it.title or it.id),
                run = function()
                    local called, r1, r2 = invoke("Integrations", "Capture", it.id)
                    if success(called, r1, r2) then return true end
                    return false, errText(r1, r2)
                end,
            }
        end
    end
    return list
end

local function charProfileActions(c)
    local list = {}
    if c.charMode == "new" then
        local name = trim(c.charName)
        list[1] = {
            id = "char-profile", label = "Crea il profilo '" .. name .. "' e usalo per questo personaggio",
            run = function(rec)
                if profileExists(name) then return false, "esiste gia' un profilo con questo nome" end
                local before = DB:GetProfileName()
                DB:SetProfile(name)
                pushUndo(rec, "Torna al profilo " .. before, function()
                    if profileExists(before) then DB:SetProfile(before) end
                    return true
                end)
                return true
            end,
        }
    elseif c.charProfile and c.charProfile ~= DB:GetProfileName() then
        local name = c.charProfile
        list[1] = {
            id = "char-profile", label = "Usa il profilo esistente '" .. name .. "'",
            run = function(rec)
                if not profileExists(name) then return false, "il profilo non esiste piu'" end
                local before = DB:GetProfileName()
                DB:SetProfile(name)
                pushUndo(rec, "Torna al profilo " .. before, function()
                    if profileExists(before) then DB:SetProfile(before) end
                    return true
                end)
                return true
            end,
        }
    end
    return list
end

------------------------------------------------------------------------------
-- Definizione dei passi
------------------------------------------------------------------------------
local FULL, SHORT, BOTH = { full = true }, { short = true }, { full = true, short = true }

local STEPS = {
    { key = "welcome", title = "Benvenuto", modes = FULL },
    { key = "role", title = "Ruolo", modes = FULL, validate = validateRole,
      plan = function(c) local a = roleAction(c); return { a } end },
    { key = "template", title = "Template", modes = FULL, applicable = templatesSupported, validate = validateTemplate,
      plan = function(c, names)
          if not usingTemplate() then return {} end
          local list = {}
          local mode = c.templateMode
          if mode == "pvp" or mode == "both" then
              local def = findDef(classTemplates("pvp"), c.templatePvp)
              if def then list[#list + 1] = templateAction(def, "pvp", c, names) end
          end
          if mode == "pve" or mode == "both" then
              local def = findDef(classTemplates("pve"), c.templatePve)
              if def then
                  local variant = #variantsOf(def) > 0 and c.raidVariant or nil
                  list[#list + 1] = templateAction(def, "pve", c, names, variant)
              end
          end
          return list
      end },
    { key = "content", title = "Contenuto", modes = FULL, applicable = function() return not usingTemplate() end,
      validate = validateContent,
      plan = function(c)
          if usingTemplate() then return {} end
          local a = genericPresetAction(c)
          return { a }
      end },
    { key = "details", title = "Dettagli", modes = FULL,
      plan = function(c) if usingTemplate() then return detailActions(c) end return {} end },
    { key = "rules", title = "Regole", modes = FULL, applicable = contextsAvailable,
      plan = function(c, names)
          local list = {}
          if usingTemplate() and c.templateMode == "both" then list[#list + 1] = classRulesAction(names) end
          if c.ruleRaid and avail("Contexts", "AddRule") then
              list[#list + 1] = copyRuleAction("In raid usa un profilo dedicato (copia di quello scelto)", "Wizard: raid", "raid", " - Raid")
          end
          if c.rulePvp and avail("Contexts", "AddRule") and not (usingTemplate() and c.templateMode == "both") then
              list[#list + 1] = copyRuleAction("Nei campi di battaglia usa un profilo dedicato (copia di quello scelto)", "Wizard: PvP", "pvp", " - PvP")
          end
          return list
      end },
    { key = "integrations", title = "Integrazioni", modes = FULL,
      applicable = function() return #integrationList() > 0 end, plan = integrationActions },
    { key = "charprofile", title = "Profilo", modes = SHORT, validate = validateCharProfile, plan = charProfileActions },
    { key = "summary", title = "Riepilogo", modes = BOTH },
}
Wizard.STEPS = STEPS

local STEP_ORDER = {}
for i, st in ipairs(STEPS) do STEP_ORDER[st.key] = i end

-- apply(c) per ogni passo: esegue solo le sue azioni (senza backup).
for _, st in ipairs(STEPS) do
    st.apply = function(c)
        local actions = st.plan and st.plan(c, {}) or {}
        local rec = { done = {}, errors = {}, warnings = {}, undo = {} }
        for _, a in ipairs(actions) do
            if a then
                local ok, r1, r2 = pcall(a.run, rec)
                if ok and r1 ~= false and not (r1 == nil and r2 ~= nil) then rec.done[#rec.done + 1] = a.label
                else rec.errors[#rec.errors + 1] = { id = a.id, label = a.label, err = ok and errText(r1, r2) or tostring(r1) } end
            end
        end
        return #rec.errors == 0, rec
    end
end

-- Passi applicabili nella modalita' corrente, nell'ordine di STEPS.
function Wizard:GetSteps()
    local out, c = {}, self.choices
    for _, st in ipairs(STEPS) do
        if st.modes[self.mode or "full"] then
            local ok, app = true, true
            if st.applicable then ok, app = pcall(st.applicable, c) end
            if ok and app then out[#out + 1] = st end
        end
    end
    return out
end

-- Posizione (1..n) del passo corrente tra quelli applicabili. Se il passo corrente non e' piu'
-- applicabile (es. cambia la scelta del template) si passa al primo successivo.
function Wizard:StepIndex()
    local steps = self:GetSteps()
    for i, st in ipairs(steps) do if st.key == self.stepId then return i end end
    local pos = STEP_ORDER[self.stepId or ""]
    if pos then
        for i, st in ipairs(steps) do if STEP_ORDER[st.key] > pos then return i end end
        return math.max(1, #steps)
    end
    return 1
end

function Wizard:IsLastStep()
    return self:StepIndex() >= #self:GetSteps()
end

local function runValidate(st, c)
    if not st or not st.validate then return true end
    local ok, a, b = pcall(st.validate, c)
    if not ok then
        Logger:Error("Wizard: validazione del passo %s: %s", st.key, tostring(a))
        return true -- un validatore difettoso non deve bloccare l'utente
    end
    if a == false then return false, b or "Dati non validi." end
    return true
end

function Wizard:Validate(key)
    for _, st in ipairs(self:GetSteps()) do
        if not key or st.key == key then
            local ok, err = runValidate(st, self.choices)
            if not ok then return false, err, st.key end
        end
    end
    return true
end

function Wizard:GoId(key)
    local steps = self:GetSteps()
    for i, st in ipairs(steps) do
        if st.key == key then return self:Go(i) end
    end
end

function Wizard:Back()
    local idx = self:StepIndex()
    if idx > 1 then self:Go(idx - 1); return true end
    return false
end

-- Avanti: valida il passo corrente; sull'ultimo passo esegue (Finish).
function Wizard:Next()
    local steps = self:GetSteps()
    local idx = self:StepIndex()
    local ok, err = runValidate(steps[idx], self.choices)
    if not ok then self:SetError(err); return false, err end
    self:SetError(nil)
    if idx < #steps then self:Go(idx + 1); return true end
    return self:Finish()
end

------------------------------------------------------------------------------
-- Piano di esecuzione, esecuzione con fallimenti parziali, annulla
------------------------------------------------------------------------------
function Wizard:BuildPlan()
    local c, names = self.choices, {}
    local body = {}
    for _, st in ipairs(self:GetSteps()) do
        if st.plan then
            local ok, list = pcall(st.plan, c, names)
            if ok and type(list) == "table" then
                for _, a in ipairs(list) do body[#body + 1] = a end
            elseif not ok then
                Logger:Error("Wizard: piano del passo %s: %s", st.key, tostring(list))
            end
        end
    end
    local plan, destructive = {}, false
    for _, a in ipairs(body) do if a.destructive then destructive = true end end
    if destructive and avail("Backups", "Create") then
        plan[1] = {
            id = "backup", optional = true, label = "Backup di sicurezza: 'Prima del wizard'",
            run = function(rec)
                local called, id, err = invoke("Backups", "Create", "Prima del wizard", "pre-preset")
                if not called or not id then return false, err or "backup non creato" end
                rec.backup = id
                return true
            end,
        }
    end
    for _, a in ipairs(body) do plan[#plan + 1] = a end
    return plan
end

-- Esegue le azioni in ordine; un fallimento non ferma le altre. Ritorna il resoconto:
-- { done = {{id,label}}, errors = {{id,label,err}}, warnings = {...}, undo = {...}, backup, profileBefore }
function Wizard:Execute(plan)
    local ok0, before = pcall(DB.GetProfileName, DB)
    local rec = { done = {}, errors = {}, warnings = {}, undo = {}, profileBefore = ok0 and before or nil, time = now() }
    for _, a in ipairs(plan) do
        local ok, r1, r2 = pcall(a.run, rec)
        if ok and r1 ~= false and not (r1 == nil and r2 ~= nil) then
            rec.done[#rec.done + 1] = { id = a.id, label = a.label }
        else
            local t = a.optional and rec.warnings or rec.errors
            t[#t + 1] = { id = a.id, label = a.label, err = ok and errText(r1, r2) or tostring(r1) }
        end
    end
    return rec
end

-- Righe leggibili del resoconto (usate dalla UI e dal log).
function Wizard:FormatResult(rec)
    local lines = {}
    if not rec then return lines end
    for _, d in ipairs(rec.done) do lines[#lines + 1] = "|cff66cc99OK|r  " .. tostring(d.label) end
    for _, e in ipairs(rec.errors) do lines[#lines + 1] = "|cffff6060Errore|r  " .. tostring(e.label) .. ": " .. tostring(e.err) end
    for _, w in ipairs(rec.warnings) do lines[#lines + 1] = "|cffe6ba66Avviso|r  " .. tostring(w.label) .. ": " .. tostring(w.err) end
    return lines
end

function Wizard:CanUndo()
    local r = self.lastRun
    return r ~= nil and not r.undone and #r.undo > 0
end

-- "Annulla tutto": ripercorre al contrario le azioni riuscite (Presets:Undo, regole, frame, profili).
function Wizard:Undo()
    local r = self.lastRun
    if not r then return false, "nessuna esecuzione da annullare" end
    if r.undone then return false, "gia' annullato" end
    if #r.undo == 0 then return false, "nulla da annullare" end
    local errs = {}
    for i = #r.undo, 1, -1 do
        local u = r.undo[i]
        local ok, a, b = pcall(u.fn)
        if not ok then errs[#errs + 1] = u.label .. ": " .. tostring(a)
        elseif a == false then errs[#errs + 1] = u.label .. ": " .. tostring(b or "non riuscito") end
    end
    -- Rete di sicurezza: si torna comunque al profilo di partenza (Presets:Undo potrebbe essere a un solo livello).
    local before = r.profileBefore
    if before and profileExists(before) and DB:GetProfileName() ~= before then
        local ok = pcall(DB.SetProfile, DB, before)
        if not ok then errs[#errs + 1] = "profilo di partenza non ripristinato" end
    end
    r.undone = true
    if #errs > 0 then return false, table.concat(errs, "; ") end
    return true
end

-- Conclude: valida, esegue il piano (backup incluso), segna il completamento e annuncia BADB_WIZARD_DONE.
-- Ritorna true, resoconto | false, errore [, chiave del passo da correggere].
function Wizard:Finish()
    if InCombatLockdown() then
        -- Presets rifiuta di applicare in combattimento: nulla viene toccato, si riprova da soli a fine combattimento.
        local msg = "Sei in combattimento: la configurazione verra' applicata appena finisce."
        self:SetError(msg)
        Events:RunOutOfCombat("wizardFinish", function()
            if Wizard.wasOpen and not InCombatLockdown() then Wizard:Next() end
        end)
        return false, msg
    end
    self.choices = state().answers
    self:EnsureChoices()
    local ok, err, badStep = self:Validate()
    if not ok then
        self:GoId(badStep)
        self:SetError(err)
        return false, err, badStep
    end
    local rec = self:Execute(self:BuildPlan())
    self.lastRun = rec
    markDone(false)
    self.stepId, self.visited, self.mode = nil, {}, "full"
    if #rec.errors > 0 then
        Logger:Warn("Configurazione guidata: %d azioni riuscite, %d fallite (annulla dal riepilogo)", #rec.done, #rec.errors)
    else
        Logger:Info("Configurazione guidata completata")
    end
    Events:Fire("BADB_WIZARD_DONE")
    if self.wasOpen then self:ShowResult(rec) end
    return true, rec
end

-- "Non mostrare piu'": completato + saltato, persistente per account.
function Wizard:Skip()
    markDone(true)
    self.stepId, self.visited, self.mode = nil, {}, "full"
    self:Close()
    return true
end

-- "Applica consigliato": parte dai valori raccomandati e applica subito.
function Wizard:ApplyRecommended()
    local c = state().answers
    for k in pairs(c) do c[k] = nil end
    self.choices = c
    self:EnsureChoices()
    if Wizard.RoleInfo().needsConfirm then
        -- la conferma del ruolo non si puo' saltare
        self:GoId("role")
        self:SetError("Conferma il tuo ruolo prima di applicare il layout consigliato.")
        return false, "ruolo da confermare"
    end
    return self:Finish()
end

------------------------------------------------------------------------------
-- Tema: adattatore verso Badb.Theme con fallback "Dusk"
------------------------------------------------------------------------------
local FALLBACK = {
    bg = { 0.075, 0.086, 0.133, 0.97 }, sidebar = { 0.060, 0.068, 0.106, 1 },
    panel = { 0.110, 0.129, 0.200, 1 }, panelAlt = { 0.137, 0.165, 0.247, 1 },
    header = { 0.090, 0.105, 0.165, 1 }, border = { 0.180, 0.208, 0.314, 1 },
    hover = { 0.165, 0.196, 0.290, 1 }, selected = { 0.200, 0.180, 0.150, 1 },
    accent = { 0.902, 0.729, 0.400, 1 }, accentDim = { 0.55, 0.45, 0.27, 1 },
    text = { 0.91, 0.90, 0.87, 1 }, textDim = { 0.70, 0.71, 0.76, 1 }, textMuted = { 0.54, 0.56, 0.65, 1 },
    success = { 0.40, 0.80, 0.60, 1 }, danger = { 1, 0.38, 0.38, 1 },
}
local WHITE = "Interface\\Buttons\\WHITE8X8"
local W_WIDTH, W_HEIGHT, RAIL = 760, 500, 180
local BODY_W = W_WIDTH - RAIL - 48

-- Il design system (Badb.Theme) risolve le chiavi sconosciute con il colore del testo:
-- per questo si usa il suo colore solo se la chiave esiste davvero, altrimenti il fallback locale.
local function themeHas(key)
    local T = Badb.Theme
    return T ~= nil and type(T.GetColor) == "function" and T:GetColor(key) ~= nil
end

local function color(key)
    local T = Badb.Theme
    if themeHas(key) then
        local r, g, b, a = T:Get(key)
        if r then return r, g, b, a or 1 end
    end
    local c = FALLBACK[key] or FALLBACK.text
    return c[1], c[2], c[3], c[4]
end

local function fill(region, key, alphaMul)
    local r, g, b, a = color(key)
    region:SetColorTexture(r, g, b, (a or 1) * (alphaMul or 1))
end

local function skin(f, bgKey, borderKey)
    local T = Badb.Theme
    if T and T.Skin and themeHas(bgKey or "panel") and themeHas(borderKey or "border") then
        T:Skin(f, { bg = bgKey, border = borderKey })
        return
    end
    if not f.SetBackdrop then Mixin(f, BackdropTemplateMixin) end
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(color(bgKey or "panel"))
    f:SetBackdropBorderColor(color(borderKey or "border"))
end

local function setBorder(f, key)
    if f.SetBackdropBorderColor then f:SetBackdropBorderColor(color(key)) end
end

local function label(parent, text, size, key, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local T = Badb.Theme
    local font = (T and T.fonts and (size >= 16 and T.fonts.header or T.fonts.body)) or STANDARD_TEXT_FONT
    fs:SetFont(font, size, flags or "")
    fs:SetTextColor(color(key or "text"))
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end

local function button(parent, text, w, onClick, variant)
    local UI = Badb.UI
    if UI and UI.Button then return UI:Button(parent, text, w, 26, onClick, variant) end
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, 26)
    skin(b, variant == "primary" and "accent" or "panelAlt", variant == "primary" and "accent" or "border")
    b.text = label(b, text, 12, variant == "primary" and "bg" or "text")
    b.text:SetPoint("CENTER")
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) setBorder(self, "accent") end)
    b:SetScript("OnLeave", function(self) setBorder(self, variant == "primary" and "accent" or "border") end)
    function b:SetEnabled(on)
        self:EnableMouse(on); self:SetAlpha(on and 1 or 0.4)
    end
    function b:SetLabel(t) self.text:SetText(t) end
    return b
end

local function setButtonText(b, t)
    if b.SetLabel then b:SetLabel(t) elseif b.SetText then b:SetText(t) end
end

local function toggle(parent, text, get, set)
    local UI = Badb.UI
    if UI and UI.Toggle then
        local row = UI:Toggle(parent, text, get, set, { width = BODY_W })
        if row.Refresh then row:Refresh() end
        return row
    end
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    local t = cb.text or cb.Text
    if t then t:SetText(text); t:SetTextColor(color("text")) end
    cb.Refresh = function(self) self:SetChecked(get() and true or false) end
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    cb:Refresh()
    return cb
end

-- Pulsante a due stati (scelta esclusiva): bordo accento quando selezionato.
local function pill(parent, text, w, isSelected, onSelect)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, 26)
    skin(b, "panel", "border")
    b.text = label(b, text, 12, "text")
    b.text:SetPoint("CENTER")
    function b:Refresh()
        local sel = isSelected()
        setBorder(self, sel and "accent" or "border")
        if self.SetBackdropColor then self:SetBackdropColor(color(sel and "selected" or "panel")) end
        self.text:SetTextColor(color(sel and "accent" or "text"))
    end
    b:SetScript("OnClick", function() onSelect(); Wizard:Refresh() end)
    b:Refresh()
    return b
end

-- Campo di testo (nome profilo): InputBoxTemplate, con fallback a un EditBox semplice.
local function editBox(parent, w, onChange)
    local ok, eb = pcall(CreateFrame, "EditBox", nil, parent, "InputBoxTemplate")
    if not ok or not eb then
        eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
        skin(eb, "panelAlt", "border")
        pcall(eb.SetFontObject, eb, _G.ChatFontNormal)
        pcall(eb.SetTextInsets, eb, 6, 6, 0, 0)
    end
    eb:SetSize(w, 24)
    eb:SetAutoFocus(false)
    pcall(eb.SetMaxLetters, eb, MAX_NAME)
    eb:SetScript("OnTextChanged", function(self) onChange(self:GetText()) end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return eb
end

local function shorten(t, n)
    t = tostring(t or "")
    if #t > n then return t:sub(1, n - 3) .. "..." end
    return t
end

------------------------------------------------------------------------------
-- Card selezionabile (ruolo / contenuto / template)
------------------------------------------------------------------------------
local function selectCard(parent, w, h, spec, isSelected, onSelect)
    local c = CreateFrame("Button", nil, parent, "BackdropTemplate")
    c:SetSize(w, h)
    skin(c, "panel", "border")
    local icon = c:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36); icon:SetPoint("TOPLEFT", 12, -12)
    icon:SetTexture(spec.icon); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local title = label(c, spec.title, 15, "text")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    local desc = label(c, spec.description, 11, "textDim")
    desc:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("RIGHT", -12, 0)
    desc:SetWordWrap(true)
    local band = c:CreateTexture(nil, "OVERLAY") -- banda accento a sinistra quando selezionata
    band:SetPoint("TOPLEFT", 1, -1); band:SetPoint("BOTTOMLEFT", 1, 1); band:SetWidth(3)
    fill(band, "accent")
    function c:SetSpec(s)
        icon:SetTexture(s.icon); title:SetText(s.title or ""); desc:SetText(s.description or "")
    end
    function c:Refresh()
        local sel = isSelected()
        band:SetShown(sel)
        setBorder(self, sel and "accent" or "border")
        if self.SetBackdropColor then self:SetBackdropColor(color(sel and "selected" or "panel")) end
    end
    c:SetScript("OnClick", function() onSelect(); Wizard:Refresh() end)
    c:SetScript("OnEnter", function(self) if not isSelected() then setBorder(self, "accentDim") end end)
    c:SetScript("OnLeave", function(self) self:Refresh() end)
    c:Refresh()
    return c
end

------------------------------------------------------------------------------
-- Finestra
------------------------------------------------------------------------------

local function onRefresh(fn) refreshers[#refreshers + 1] = fn end

local function overlay(f, header)
    local ov = CreateFrame("Frame", nil, f, "BackdropTemplate")
    ov:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    ov:SetPoint("BOTTOMRIGHT", -1, 1)
    ov:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
    ov:EnableMouse(true)
    skin(ov, "bg", "border")
    ov:Hide()
    return ov
end

local function buildShell()
    local f = CreateFrame("Frame", "BadbUIWizard", UIParent, "BackdropTemplate")
    f:SetSize(W_WIDTH, W_HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    skin(f, "bg", "border")
    -- ESC non chiude in silenzio (non e' in UISpecialFrames): chiede se saltare o rimandare.
    f:EnableKeyboard(true)
    pcall(f.SetPropagateKeyboardInput, f, true)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            pcall(self.SetPropagateKeyboardInput, self, false)
            Wizard:AskSkip()
        else
            pcall(self.SetPropagateKeyboardInput, self, true)
        end
    end)

    -- Banda di intestazione con "stelle" (puntini accento) e titolo
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 1, -1); header:SetPoint("TOPRIGHT", -1, -1); header:SetHeight(48)
    local hbg = header:CreateTexture(nil, "BACKGROUND"); hbg:SetAllPoints(); fill(hbg, "header")
    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1); fill(line, "accent", 0.6)
    local seed = { 0.12, 0.31, 0.47, 0.58, 0.66, 0.79, 0.88, 0.95 }
    for i, x in ipairs(seed) do
        local s = header:CreateTexture(nil, "ARTWORK")
        local sz = (i % 3 == 0) and 2 or 1
        s:SetSize(sz, sz)
        s:SetPoint("TOPLEFT", math.floor(W_WIDTH * x), -6 - ((i * 7) % 30))
        fill(s, "accent", 0.35 + (i % 4) * 0.15)
    end
    local title = label(header, "BADB|cffe6ba66UI|r", 18, "text")
    title:SetPoint("LEFT", 18, 0)
    local subtitle = label(header, "Configurazione guidata", 12, "textMuted")
    subtitle:SetPoint("LEFT", title, "RIGHT", 12, -1)
    local close = CreateFrame("Button", nil, header, "UIPanelCloseButtonNoScripts")
    close:SetPoint("RIGHT", -6, 0)
    close:SetScript("OnClick", function() Wizard:AskSkip() end)

    -- Rail di navigazione: una voce per ogni passo possibile, mostrate solo quelle applicabili.
    local rail = CreateFrame("Frame", nil, f)
    rail:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    rail:SetPoint("BOTTOMLEFT", 1, 1)
    rail:SetWidth(RAIL)
    local rbg = rail:CreateTexture(nil, "BACKGROUND"); rbg:SetAllPoints(); fill(rbg, "sidebar")
    for _, s in ipairs(STEPS) do
        local item = CreateFrame("Button", nil, rail)
        item.stepKey = s.key
        item:SetSize(RAIL, 36)
        item:SetPoint("TOPLEFT", 0, -12)
        local hl = item:CreateTexture(nil, "BACKGROUND"); hl:SetAllPoints(); fill(hl, "hover")
        local mark = item:CreateTexture(nil, "ARTWORK")
        mark:SetPoint("TOPLEFT"); mark:SetPoint("BOTTOMLEFT"); mark:SetWidth(3); fill(mark, "accent")
        local num = label(item, "", 12, "textMuted")
        num:SetPoint("LEFT", 18, 0)
        local txt = label(item, s.title, 13, "textDim")
        txt:SetPoint("LEFT", 40, 0)
        item:SetScript("OnClick", function() if Wizard.visited[s.key] then Wizard:GoId(s.key) end end)
        item.Refresh = function(self, i, cur)
            local current, done = i == cur, i < cur
            hl:SetShown(current); mark:SetShown(current)
            txt:SetTextColor(color(current and "text" or (Wizard.visited[s.key] and "textDim" or "textMuted")))
            num:SetText(done and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t" or tostring(i))
            num:SetTextColor(color(current and "accent" or "textMuted"))
        end
        railItems[#railItems + 1] = item
    end
    local version = label(rail, "v" .. (Badb.version or "dev"), 10, "textMuted")
    version:SetPoint("BOTTOMLEFT", 18, 12)

    -- Corpo e piede
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", rail, "TOPRIGHT", 24, -20)
    body:SetPoint("BOTTOMRIGHT", -24, 64)
    f.body = body

    -- Messaggio di errore di validazione (sopra il piede)
    f.err = label(f, "", 11, "danger")
    f.err:SetPoint("BOTTOMLEFT", rail, "BOTTOMRIGHT", 24, 56)
    f.err:SetPoint("RIGHT", -24, 0)

    local footer = CreateFrame("Frame", nil, f)
    footer:SetPoint("BOTTOMLEFT", rail, "BOTTOMRIGHT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(52)
    local fline = footer:CreateTexture(nil, "ARTWORK")
    fline:SetPoint("TOPLEFT"); fline:SetPoint("TOPRIGHT"); fline:SetHeight(1); fill(fline, "border")
    local track = footer:CreateTexture(nil, "ARTWORK")
    track:SetPoint("LEFT", 24, 0); track:SetSize(180, 4); fill(track, "panelAlt")
    local prog = footer:CreateTexture(nil, "OVERLAY")
    prog:SetPoint("LEFT", track); prog:SetHeight(4); fill(prog, "accent")
    local progText = label(footer, "", 11, "textMuted")
    progText:SetPoint("LEFT", track, "RIGHT", 10, 0)
    onRefresh(function()
        local n = math.max(1, #Wizard:GetSteps())
        prog:SetWidth(math.max(1, 180 * Wizard.step / n))
        progText:SetFormattedText("Passo %d di %d", Wizard.step, n)
    end)

    f.next = button(footer, "Avanti", 120, function() Wizard:Next() end, "primary")
    f.next:SetPoint("RIGHT", -24, 0)
    f.back = button(footer, "Indietro", 100, function() Wizard:Back() end, "secondary")
    f.back:SetPoint("RIGHT", f.next, "LEFT", -8, 0)
    f.skip = button(footer, "Salta", 80, function() Wizard:AskSkip() end, "ghost")
    f.skip:SetPoint("RIGHT", f.back, "LEFT", -8, 0)

    -- Conferma "salta": non mostrare piu' / piu' tardi / continua
    local cf = overlay(f, header)
    local ct = label(cf, "Interrompere la configurazione guidata?", 18, "text")
    ct:SetPoint("TOPLEFT", 48, -56)
    local cd = label(cf, "Puoi non vederla piu' oppure rimandarla: la ritrovi con /badb wizard o dal pannello BadbUI.", 12, "textDim")
    cd:SetPoint("TOPLEFT", 48, -92); cd:SetWidth(620); cd:SetWordWrap(true)
    local c1 = button(cf, "Non mostrare piu'", 260, function() Wizard:Skip() end, "secondary")
    c1:SetPoint("TOPLEFT", 48, -150)
    local c2 = button(cf, "Piu' tardi", 260, function() Wizard:Close() end, "secondary")
    c2:SetPoint("TOPLEFT", 48, -188)
    local c3 = button(cf, "Continua la configurazione", 260, function() cf:Hide() end, "primary")
    c3:SetPoint("TOPLEFT", 48, -226)
    f.confirm = cf
    f.confirmButtons = { never = c1, later = c2, resume = c3 }

    -- Riepilogo finale: esito, errori, "Annulla tutto"
    local rs = overlay(f, header)
    rs.title = label(rs, "", 20, "text")
    rs.title:SetPoint("TOPLEFT", 48, -40)
    rs.body = label(rs, "", 12, "text")
    rs.body:SetPoint("TOPLEFT", 48, -84); rs.body:SetWidth(640); rs.body:SetWordWrap(true)
    rs.body:SetSpacing(4)
    rs.undo = button(rs, "Annulla tutto", 150, function()
        local ok, err = Wizard:Undo()
        rs.title:SetText(ok and "Modifiche annullate" or "Annullamento incompleto")
        rs.body:SetText(ok and "Tutto e' stato riportato com'era prima della configurazione." or tostring(err))
        rs.undo:SetShown(false)
    end, "ghost")
    rs.undo:SetPoint("BOTTOMLEFT", 48, 36)
    rs.close = button(rs, "Chiudi", 150, function() Wizard:Close() end, "primary")
    rs.close:SetPoint("BOTTOMRIGHT", -48, 36)
    f.result = rs

    -- Applica i cambi di tema del design system
    Events:On(Wizard, "BADB_THEME_CHANGED", function()
        if frame then frame:Hide(); frame = nil; pages = {}; railItems = {}; refreshers = {} end
        if Wizard.wasOpen then Wizard:Open() end
    end)
    return f
end

------------------------------------------------------------------------------
-- Pagine
------------------------------------------------------------------------------
local function pageHeading(page, title, text)
    local h = label(page, title, 20, "text")
    h:SetPoint("TOPLEFT", 0, 0)
    local p = label(page, text, 12, "textDim")
    p:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -8)
    p:SetPoint("RIGHT", 0, 0)
    p:SetWordWrap(true)
    return p
end

local Builders = {}

local CLASSIC_NOTICE = "Nota: al primo accesso Blizzard propone il preset Classic o Enhanced "
    .. "(Opzioni > Sistema > Preset). Sceglilo prima di proseguire: BadbUI lavora sopra quel layout."

Builders.welcome = function(page)
    local intro = pageHeading(page, "Il tuo layout in un minuto",
        "BadbUI configura nameplate, frame di raid e party, scala dell'interfaccia ed elementi superflui in base al tuo ruolo e al contenuto che giochi. Viene creato un nuovo profilo: quello attuale resta intatto e puoi tornare indietro in qualsiasi momento.")

    local quick = CreateFrame("Frame", nil, page, "BackdropTemplate")
    quick:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -20)
    quick:SetPoint("RIGHT", 0, 0)
    quick:SetHeight(112)
    skin(quick, "panel", "accentDim")
    local qt = label(quick, "Consigliato per questo personaggio", 14, "accent")
    qt:SetPoint("TOPLEFT", 16, -14)
    local qd = label(quick, "", 12, "textDim")
    qd:SetPoint("TOPLEFT", qt, "BOTTOMLEFT", 0, -8)
    qd:SetPoint("RIGHT", -16, 0)
    local apply = button(quick, "Applica consigliato", 170, function() Wizard:ApplyRecommended() end, "primary")
    apply:SetPoint("BOTTOMLEFT", 16, 14)
    onRefresh(function()
        local Pr = P()
        local r = safeRecommend()
        local c = Pr and Pr.content and Pr.content[r.content]
        local ri = Wizard.RoleInfo()
        local role = Pr and Pr.roles and Pr.roles[ri.role or r.role]
        local extra = ""
        if usingTemplate() then
            local def = findDef(classTemplates("pve"), Wizard.choices.templatePve)
            if Wizard.choices.templateMode == "pvp" then def = findDef(classTemplates("pvp"), Wizard.choices.templatePvp) end
            if def then extra = "\nTemplate: " .. tostring(def.title or def.key) end
        end
        qd:SetFormattedText("%s  ·  %s%s\nRilevato dal tuo personaggio (classe, talenti, livello e gruppo).",
            role and role.title or "?", c and c.title or "?", extra)
    end)

    local custom = label(page, "Oppure premi |cffe6ba66Avanti|r per scegliere tu ogni dettaglio.", 12, "textMuted")
    custom:SetPoint("TOPLEFT", quick, "BOTTOMLEFT", 0, -14)

    local notice = label(page, CLASSIC_NOTICE, 11, "textMuted")
    notice:SetPoint("TOPLEFT", custom, "BOTTOMLEFT", 0, -10)
    notice:SetPoint("RIGHT", 0, 0)
    notice:SetWordWrap(true)

    local envText = label(page, "", 11, "textDim")
    envText:SetPoint("TOPLEFT", notice, "BOTTOMLEFT", 0, -10)
    envText:SetPoint("RIGHT", 0, 0)
    envText:SetWordWrap(true)
    onRefresh(function()
        local env = Wizard.env or {}
        local parts = { "Client " .. tostring(env.client or "?"), env.editMode and "Edit Mode disponibile" or "Edit Mode non disponibile" }
        if env.issues and #env.issues > 0 then
            local shown = {}
            for i = 1, math.min(3, #env.issues) do shown[i] = env.issues[i] end
            local more = #env.issues > 3 and (" +" .. (#env.issues - 3)) or ""
            parts[#parts + 1] = "|cffe6ba66Avvisi: " .. shorten(table.concat(shown, ", "), 120) .. more .. "|r"
        end
        envText:SetText(table.concat(parts, "  ·  "))
    end)

    local undo = button(page, "Annulla ultimo preset", 170, function()
        local Pr = P()
        if Pr and Pr.Undo then Pr:Undo() end
        Wizard:Refresh()
    end, "ghost")
    undo:SetPoint("BOTTOMLEFT", 0, 0)
    onRefresh(function()
        local Pr = P()
        undo:SetShown(Pr ~= nil and type(Pr.CanUndo) == "function" and Pr:CanUndo() and true or false)
    end)
end

local function cardGrid(page, anchor, ids, registry, field, allowedFn)
    local cols = #ids == 3 and 3 or 2
    local gap = 12
    local w = math.floor((BODY_W - gap * (cols - 1)) / cols)
    local h = cols == 3 and 150 or 112
    for i, id in ipairs(ids) do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        local card = selectCard(page, w, h, registry[id],
            function() return Wizard.choices[field] == id end,
            function() Wizard.choices[field] = id end)
        card:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", col * (w + gap), -20 - row * (h + gap))
        onRefresh(function()
            card:Refresh()
            if allowedFn then card:SetShown(allowedFn(id)) end
        end)
    end
end

Builders.role = function(page)
    local Pr = P()
    local p = pageHeading(page, "Che ruolo giochi?",
        "Il ruolo decide dimensioni dei frame di gruppo, informazioni mostrate e quanto risaltano le nameplate.")
    -- Riquadro "Conferma il tuo ruolo": visibile solo se Badb.Player non e' sicuro (confidenza < alta o ruolo ambiguo).
    local banner = label(page, "", 12, "accent")
    banner:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 0, -10)
    banner:SetPoint("RIGHT", 0, 0)
    banner:SetWordWrap(true)
    onRefresh(function()
        local ri = Wizard.RoleInfo()
        if not ri.needsConfirm then banner:SetText(""); return end
        local rr = Pr and Pr.roles and Pr.roles[ri.role or ""]
        local conf = ri.confidence == "medium" and "media" or "bassa"
        banner:SetFormattedText("Conferma il tuo ruolo: rilevato %s (fonte %s, affidabilita' %s). Scegli quello giusto e premi Avanti.",
            rr and rr.title or tostring(ri.role or "?"), tostring(ri.source or "?"), conf)
    end)
    if Pr and Pr.roleOrder then
        cardGrid(page, banner, Pr.roleOrder, Pr.roles, "role", function(id)
            local allowed = Wizard.RoleInfo().allowed
            return allowed == nil or allowed[id] == true
        end)
    end
end

Builders.content = function(page)
    local Pr = P()
    local p = pageHeading(page, "Cosa giochi di piu'?",
        "Puoi rifare la configurazione per ogni attivita' e associare un profilo a ciascuna specializzazione.")
    if Pr and Pr.contentOrder then cardGrid(page, p, Pr.contentOrder, Pr.content, "content") end
end

local TEMPLATE_ICON = "Interface\\Icons\\INV_Misc_Map_01"

Builders.template = function(page)
    local p = pageHeading(page, "Il template della tua classe",
        "Ogni template e' pensato per la tua classe e il tuo ruolo. Scegli dove giochi: PvE, PvP o entrambi (con cambio profilo automatico).")
    local gap = 12
    local cw = math.floor((BODY_W - gap * 2) / 3)

    local function setMode(m) Wizard.choices.useTemplate = true; Wizard.choices.templateMode = m end
    local function modePill(text, mode, x, w)
        local b = pill(page, text, w, function() return usingTemplate() and Wizard.choices.templateMode == mode end,
            function() setMode(mode) end)
        b:SetPoint("TOPLEFT", p, "BOTTOMLEFT", x, -12)
        onRefresh(function()
            b:Refresh()
            local hasPve, hasPvp = #classTemplates("pve") > 0, #classTemplates("pvp") > 0
            b:SetShown(mode == "pve" and hasPve or mode == "pvp" and hasPvp or mode == "both" and hasPve and hasPvp)
        end)
        return b
    end
    modePill("PvE", "pve", 0, 100)
    modePill("PvP", "pvp", 108, 100)
    modePill("Entrambi", "both", 216, 110)
    local generic = pill(page, "Scelta generica", 140, function() return Wizard.choices.useTemplate == false end,
        function() Wizard.choices.useTemplate = false end)
    generic:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 334, -12)
    onRefresh(function() generic:Refresh() end)

    local function section(titleText, mode, field)
        local box = CreateFrame("Frame", nil, page)
        box:SetSize(BODY_W, 132)
        local t = label(box, titleText, 13, "accent")
        t:SetPoint("TOPLEFT", 0, 0)
        local cards = {}
        for i = 1, 3 do
            local card
            card = selectCard(box, cw, 80, { icon = TEMPLATE_ICON, title = "", description = "" },
                function() return card ~= nil and card.def ~= nil and Wizard.choices[field] == card.def.key end,
                function() if card.def then Wizard.choices[field] = card.def.key end end)
            card:SetPoint("TOPLEFT", box, "TOPLEFT", (i - 1) * (cw + gap), -20)
            cards[i] = card
        end
        box.cards = cards
        return box
    end
    local pveBox = section("PvE", "pve", "templatePve")
    local pvpBox = section("PvP", "pvp", "templatePvp")
    page.pveBox, page.pvpBox = pveBox, pvpBox

    -- Dimensione del raid (10 / 20 / 40) per i template con varianti
    local variantPills = {}
    for i = 1, 3 do
        local b
        b = pill(pveBox, "", 100, function() return b ~= nil and b.variant ~= nil and Wizard.choices.raidVariant == b.variant end,
            function() if b.variant then Wizard.choices.raidVariant = b.variant end end)
        b:SetPoint("TOPLEFT", pveBox, "TOPLEFT", (i - 1) * 108, -106)
        variantPills[i] = b
    end
    page.variantPills = variantPills

    onRefresh(function()
        local c = Wizard.choices
        local on = usingTemplate()
        local mode = c.templateMode
        local showPve = on and (mode == "pve" or mode == "both")
        local showPvp = on and (mode == "pvp" or mode == "both")
        local function fillBox(box, list)
            for i, card in ipairs(box.cards) do
                local def = list[i]
                card.def = def
                if def then
                    card:SetSpec({ icon = def.icon or TEMPLATE_ICON, title = shorten(def.title or def.key, 22),
                        description = shorten(def.rationale or def.description or "", 70) })
                    card:Show()
                else
                    card:Hide()
                end
                card:Refresh()
            end
        end
        fillBox(pveBox, classTemplates("pve"))
        fillBox(pvpBox, classTemplates("pvp"))
        local vs = showPve and variantsOf(findDef(classTemplates("pve"), c.templatePve)) or {}
        for i, b in ipairs(variantPills) do
            local v = vs[i]
            b.variant = v
            if v then b.text:SetText("Raid a " .. v); b:Show(); b:Refresh() else b:Hide() end
        end
        local y = 58
        pveBox:ClearAllPoints(); pvpBox:ClearAllPoints()
        pveBox:SetShown(showPve); pvpBox:SetShown(showPvp)
        if showPve then
            pveBox:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 0, -y)
            y = y + (#vs > 0 and 140 or 112)
        end
        if showPvp then pvpBox:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 0, -y) end
    end)
end

Builders.details = function(page)
    local p = pageHeading(page, "Ultimi ritocchi", "Opzioni generali, modificabili in seguito dal pannello BadbUI.")
    local items = {
        { "pixelPerfect", "Scala interfaccia pixel perfect (bordi nitidi a ogni risoluzione)" },
        { "hideClutter", "Nascondi micro menu, barra borse e barra esperienza" },
        { "friendlyPlates", "Mostra le nameplate degli alleati" },
    }
    local prev = p
    for _, it in ipairs(items) do
        local key = it[1]
        local t = toggle(page, it[2], function() return Wizard.choices[key] end,
            function(v) Wizard.choices[key] = v end)
        t:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", prev == p and 0 or 0, prev == p and -20 or -10)
        onRefresh(function() if t.Refresh then t:Refresh() end end)
        prev = t
    end
end

Builders.rules = function(page)
    local p = pageHeading(page, "Regole automatiche",
        "BadbUI puo' cambiare profilo da solo in base a dove ti trovi. Ogni regola usa una copia del profilo che stai creando, cosi' puoi ritoccarla senza toccare l'originale.")
    local note = label(page, "", 11, "accent")
    note:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 0, -14)
    note:SetPoint("RIGHT", 0, 0)
    note:SetWordWrap(true)
    local raid = toggle(page, "In raid usa un profilo dedicato", function() return Wizard.choices.ruleRaid end,
        function(v) Wizard.choices.ruleRaid = v end)
    raid:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -16)
    local pvp = toggle(page, "Nei campi di battaglia usa un profilo dedicato", function() return Wizard.choices.rulePvp end,
        function(v) Wizard.choices.rulePvp = v end)
    pvp:SetPoint("TOPLEFT", raid, "BOTTOMLEFT", 0, -10)
    onRefresh(function()
        local both = usingTemplate() and Wizard.choices.templateMode == "both"
        note:SetText(both and "Con 'Entrambi' le regole PvE/PvP della tua classe vengono create automaticamente (campi di battaglia -> profilo PvP)." or "")
        if raid.Refresh then raid:Refresh() end
        if pvp.Refresh then pvp:Refresh() end
        pvp:SetShown(not both)
    end)
end

Builders.integrations = function(page)
    local p = pageHeading(page, "Altri addon",
        "Ho trovato questi addon: puoi salvare la loro configurazione attuale nel profilo BadbUI (best-effort, non verificato in gioco).")
    local prev = p
    for _, it in ipairs(integrationList()) do
        local id = it.id
        local t = toggle(page, "Salva la configurazione di " .. tostring(it.title or id), function()
            return type(Wizard.choices.integrations) == "table" and Wizard.choices.integrations[id]
        end, function(v)
            if type(Wizard.choices.integrations) ~= "table" then Wizard.choices.integrations = {} end
            Wizard.choices.integrations[id] = v
        end)
        t:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, prev == p and -20 or -10)
        onRefresh(function() if t.Refresh then t:Refresh() end end)
        prev = t
    end
end

-- Personaggio nuovo (modalita' breve): usa un profilo esistente o creane uno.
Builders.charprofile = function(page)
    local p = pageHeading(page, "Personaggio nuovo",
        "Hai gia' configurato BadbUI su questo account. Vuoi usare un profilo esistente o crearne uno nuovo per questo personaggio?")
    local pe = pill(page, "Usa un profilo esistente", 230, function() return Wizard.choices.charMode ~= "new" end,
        function() Wizard.choices.charMode = "existing" end)
    pe:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 0, -20)
    local pn = pill(page, "Crea un nuovo profilo", 230, function() return Wizard.choices.charMode == "new" end,
        function() Wizard.choices.charMode = "new" end)
    pn:SetPoint("LEFT", pe, "RIGHT", 10, 0)

    local cycleLabel = label(page, "Profilo da usare (clic per cambiare):", 12, "textDim")
    cycleLabel:SetPoint("TOPLEFT", pe, "BOTTOMLEFT", 0, -24)
    local cycle = button(page, "", 280, function()
        local list = listProfiles()
        if #list == 0 then return end
        local idx = 0
        for i, n in ipairs(list) do if n == Wizard.choices.charProfile then idx = i end end
        Wizard.choices.charProfile = list[(idx % #list) + 1]
        Wizard:Refresh()
    end, "secondary")
    cycle:SetPoint("TOPLEFT", cycleLabel, "BOTTOMLEFT", 0, -8)

    local nameLabel = label(page, "Nome del nuovo profilo:", 12, "textDim")
    nameLabel:SetPoint("TOPLEFT", pe, "BOTTOMLEFT", 0, -24)
    local eb = editBox(page, 280, function(text) Wizard.choices.charName = cleanStr(text, MAX_STR) end)
    eb:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 6, -8)
    page.nameBox, page.cycle = eb, cycle

    onRefresh(function()
        local isNew = Wizard.choices.charMode == "new"
        cycleLabel:SetShown(not isNew); cycle:SetShown(not isNew)
        nameLabel:SetShown(isNew); eb:SetShown(isNew)
        setButtonText(cycle, tostring(Wizard.choices.charProfile or "?"))
        if isNew and eb:GetText() ~= (Wizard.choices.charName or "") then eb:SetText(Wizard.choices.charName or "") end
        pe:Refresh(); pn:Refresh()
    end)
end

Builders.summary = function(page)
    local p = pageHeading(page, "Riepilogo", "Ecco cosa verra' applicato. Premi |cffe6ba66Applica|r per procedere: viene creato prima un backup e puoi annullare tutto.")
    local box = CreateFrame("Frame", nil, page, "BackdropTemplate")
    box:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 0, -18)
    box:SetPoint("RIGHT", 0, 0)
    box:SetHeight(220)
    skin(box, "panel", "border")
    local profile = label(box, "", 13, "accent")
    profile:SetPoint("TOPLEFT", 16, -14)
    local lines = label(box, "", 12, "text")
    lines:SetPoint("TOPLEFT", profile, "BOTTOMLEFT", 0, -10)
    lines:SetPoint("RIGHT", -16, 0)
    lines:SetSpacing(6)
    local note = label(page, "Il profilo attuale non viene modificato. /badb undo per tornare indietro.", 11, "textMuted")
    note:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -10)
    page.summaryLines = lines
    onRefresh(function()
        local out = {}
        local function add(text) out[#out + 1] = "|cffe6ba66•|r  " .. text end
        local plan = Wizard:BuildPlan()
        local Pr = P()
        if Wizard.mode == "short" then
            profile:SetText("Profilo di questo personaggio")
            for _, a in ipairs(plan) do add(a.label) end
        elseif usingTemplate() then
            profile:SetText("Template della tua classe")
            for _, a in ipairs(plan) do add(a.label) end
        else
            local okS, spec = false, nil
            if Pr and Pr.Build then okS, spec = pcall(Pr.Build, Pr, Wizard.choices) end
            if okS and type(spec) == "table" then
                profile:SetText("Nuovo profilo: Badb - " .. tostring(spec.title))
                local okD, desc = pcall(Pr.Describe, Pr, spec)
                if okD and type(desc) == "table" then for _, l in ipairs(desc) do add(l) end end
            else
                profile:SetText("Configurazione")
            end
            for _, a in ipairs(plan) do
                if a.id ~= "preset" then add(a.label) end
            end
        end
        if #out == 0 then add("Nessuna modifica: l'interfaccia resta com'e'.") end
        if #out > 10 then
            local extra = #out - 9
            for i = #out, 10, -1 do out[i] = nil end
            out[10] = string.format("... e altre %d azioni", extra)
        end
        lines:SetText(table.concat(out, "\n"))
    end)
end

------------------------------------------------------------------------------
-- Navigazione e ciclo di vita della finestra
------------------------------------------------------------------------------
local function pageFor(key)
    if pages[key] then return pages[key] end
    local page = CreateFrame("Frame", nil, frame.body)
    page:SetAllPoints()
    local build = Builders[key]
    if build then
        local ok, err = pcall(build, page)
        if not ok then
            -- un passo che non si costruisce non deve bloccare il wizard: box d'errore al suo posto
            Logger:Error("Wizard: passo %s: %s", key, tostring(err))
            page.buildError = tostring(err)
            local msg = label(page, "|cffff6060Impossibile mostrare questo passo.|r\n" .. shorten(err, 300), 12, "textDim")
            msg:SetPoint("TOPLEFT", 0, 0); msg:SetPoint("RIGHT", 0, 0); msg:SetWordWrap(true)
        end
    end
    pages[key] = page
    return page
end

function Wizard:SetError(msg)
    self.lastError = msg
    if frame and frame.err then frame.err:SetText(msg or "") end
end

function Wizard:Refresh()
    if not frame then return end
    local steps = self:GetSteps()
    local idx = self:StepIndex()
    self.step = idx
    local pos = {}
    for i, st in ipairs(steps) do pos[st.key] = i end
    for _, item in ipairs(railItems) do
        local i = pos[item.stepKey]
        if i then
            item:Show(); item:ClearAllPoints(); item:SetPoint("TOPLEFT", 0, -12 - (i - 1) * 38)
            item:Refresh(i, idx)
        else
            item:Hide()
        end
    end
    for _, fn in ipairs(refreshers) do pcall(fn) end
    pcall(frame.back.SetEnabled, frame.back, idx > 1)
    setButtonText(frame.next, idx >= #steps and "Applica" or "Avanti")
end

function Wizard:Go(i)
    local steps = self:GetSteps()
    if i < 1 or i > #steps then return end
    local key = steps[i].key
    self.stepId, self.step = key, i
    self.visited[key] = true
    state().step = key
    if frame then
        for k, page in pairs(pages) do page:SetShown(k == key) end
        local ok, page = pcall(pageFor, key)
        if ok and page then page:Show() end
    end
    self:Refresh()
end

function Wizard:AskSkip()
    if not (frame and self.wasOpen) then return end
    if frame.result:IsShown() then self:Close(); return end
    frame.confirm:Show()
end

function Wizard:ShowResult(rec)
    if not frame or not rec then return end
    local rs = frame.result
    local nerr = #rec.errors
    rs.title:SetText(nerr == 0 and "Fatto!" or string.format("Completato con %d errori", nerr))
    local lines = self:FormatResult(rec)
    if #lines == 0 then lines[1] = "Nessuna modifica necessaria." end
    if #lines > 14 then
        local extra = #lines - 13
        for i = #lines, 14, -1 do lines[i] = nil end
        lines[14] = string.format("... e altre %d righe", extra)
    end
    if nerr > 0 then lines[#lines + 1] = "\nAlcune azioni non sono riuscite: le altre sono state applicate. Puoi annullare tutto."
    elseif rec.backup then lines[#lines + 1] = "\nBackup creato prima delle modifiche." end
    rs.body:SetText(table.concat(lines, "\n"))
    rs.undo:SetShown(self:CanUndo())
    frame.confirm:Hide()
    rs:Show()
end

-- Apre la finestra. mode: "full" (default) | "short" (personaggio nuovo). Non genera mai errori.
function Wizard:Open(mode)
    local m = Badb.Modules:Get("Wizard")
    if not (m and m.enabled) then return false, "modulo disattivato" end
    if not P() then
        Logger:Warn("Configurazione guidata: modulo Presets non disponibile")
        return false, "Presets non disponibile"
    end
    if InCombatLockdown() then
        Logger:Info("La configurazione guidata si aprira' a fine combattimento")
        Events:RunOutOfCombat("wizardOpen", function() Wizard:Open(mode) end)
        return false, "in combattimento"
    end
    if mode and mode ~= self.mode then self.mode, self.stepId, self.visited = mode, nil, {} end
    self.choices = state().answers
    self:EnsureChoices()
    local okE, env = pcall(self.DetectEnvironment, self)
    self.env = okE and env or nil
    if not frame then
        local ok, f = pcall(buildShell)
        if not ok then
            Logger:Error("Configurazione guidata: finestra non creata: %s", tostring(f))
            return false, tostring(f)
        end
        frame = f
    end
    self.wasOpen = true
    frame.confirm:Hide(); frame.result:Hide()
    frame:Show()
    self:SetError(nil)
    local steps = self:GetSteps()
    local target = self.stepId
    if not target then
        local saved = state().step
        for _, st in ipairs(steps) do if st.key == saved then target = saved end end
    end
    self.stepId = target or (steps[1] and steps[1].key)
    self:GoId(self.stepId)
    return true
end

-- "Piu' tardi": chiude senza segnare nulla (lo stato e le risposte restano).
function Wizard:Close()
    self.wasOpen = false
    if frame then
        frame:Hide()
        if frame.confirm then frame.confirm:Hide() end
        if frame.result then frame.result:Hide() end
    end
end

-- Accesso a finestra e pagine (per test e diagnostica).
function Wizard:GetFrame() return frame end
function Wizard:GetPage(key) return pages[key] end

function Wizard:Toggle()
    if frame and self.wasOpen then self:Close() else self:Open() end
end

-- Avvio esplicito. force = true ignora "completato" e riparte dal primo passo.
-- Ritorna true | false, motivo.
function Wizard:Start(force)
    local m = Badb.Modules:Get("Wizard")
    if not (m and m.enabled) then return false, "modulo disattivato" end
    local mode = force and "full" or self:DetectMode()
    if not mode then return false, "gia' completato" end
    if InCombatLockdown() then
        Events:RunOutOfCombat("wizardOpen", function() Wizard:Start(force) end)
        return false, "in combattimento: partira' a fine combattimento"
    end
    if force then self.stepId, self.visited, self.lastRun = nil, {}, nil end
    return self:Open(mode)
end

-- Avvio automatico (primo login): una sola volta per sessione, dopo un breve ritardo, mai in combattimento.
function Wizard:AutoStart(isLogin, isReload)
    if not (isLogin or isReload) or self.sessionStarted then return end
    if not self:DetectMode() then return end
    self.sessionStarted = true
    Badb.Compat.After(AUTO_DELAY, function()
        Events:RunOutOfCombat("wizardAutoStart", function()
            local m = Badb.Modules:Get("Wizard")
            if not (m and m.enabled) or self.wasOpen then return end
            local mode = self:DetectMode()
            if not mode then return end
            local ok, err = pcall(self.Open, self, mode)
            if not ok then Logger:Error("Configurazione guidata: %s", tostring(err)) end
        end)
    end)
end

------------------------------------------------------------------------------
-- Modulo "Wizard": pagina nella ConfigUI, comando /badb wizard, avvio automatico
------------------------------------------------------------------------------
local pageStatus
local function statusText()
    local s = state()
    if not s.completed then return "Stato: non ancora completato." end
    if s.skipped then return "Stato: saltato (non viene piu' proposto)." end
    return "Stato: completato."
end

local M = Badb.Modules:New("Wizard", {
    title = "Configurazione guidata",
    category = "Strumenti",
    defaults = { enabled = true },
    options = {
        { type = "execute", label = "Rilancia la configurazione guidata", func = function() Wizard:Start(true) end },
    },
    page = {
        title = "Setup guidato", order = 90, category = "Strumenti",
        build = function(parent)
            local h = label(parent, "Setup guidato", 18, "text")
            h:SetPoint("TOPLEFT", 0, 0)
            local d = label(parent, "Rilancia la configurazione guidata per scegliere ruolo, template della tua classe e regole automatiche. Prima di applicare viene creato un backup e puoi annullare tutto.", 12, "textDim")
            d:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -8); d:SetWidth(540); d:SetWordWrap(true)
            pageStatus = label(parent, statusText(), 12, "text")
            pageStatus:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -14)
            local b1 = button(parent, "Rilancia il setup guidato", 200, function() Wizard:Start(true) end, "primary")
            b1:SetPoint("TOPLEFT", pageStatus, "BOTTOMLEFT", 0, -16)
            local b2 = button(parent, "Reimposta lo stato", 160, function()
                Wizard:Reset(); pageStatus:SetText(statusText())
            end, "secondary")
            b2:SetPoint("LEFT", b1, "RIGHT", 10, 0)
            return 150
        end,
        refresh = function() if pageStatus then pageStatus:SetText(statusText()) end end,
    },
    -- "/badb wizard" e "/badb setup" sono comandi base di Slash.lua (aprono la finestra via Wizard:Toggle):
    -- qui solo i sottocomandi aggiuntivi, per non collidere con i base.
    commands = {
        wizardreset = {
            help = "wizardreset [status] - reimposta il setup guidato (o ne mostra lo stato)",
            fn = function(args)
                if trim(args):lower() == "status" then
                    Logger:Info("%s", statusText())
                    return
                end
                Wizard:Reset()
                Logger:Info("Setup guidato reimpostato: ripartira' al prossimo accesso.")
            end,
        },
    },
})
Wizard.module = M

function M:OnEnable()
    self:On("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload) Wizard:AutoStart(isLogin, isReload) end)
end

function M:OnDisable()
    Wizard:Close()
end
