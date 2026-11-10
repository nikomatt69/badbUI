-- BadbUI - Diagnostics
-- "Doctor" dell'addon: controlli di integrita'/compatibilita', cattura non distruttiva degli errori Lua
-- riferiti a BadbUI, report copiabile (senza dati personali) e statistiche leggere.
-- API (non lanciano): RunChecks, Report, GetErrors, ClearErrors, GetStats.
-- Aggiungere un controllo = aggiungere { id, fn } a M.checks (fn ritorna una tabella-risultato o una lista).
local _, ns = ...
local L10n = ns.Badb.L
local Badb = ns.Badb
local Logger, Modules, Compat = Badb.Logger, Badb.Modules, Badb.Compat

---------------------------------------------------------------------------
-- Dati: addon di interfaccia noti che si sovrappongono a BadbUI.
-- modules = moduli BadbUI che possono confliggere (vuoto = solo informativo, finisce nel report).
---------------------------------------------------------------------------
-- addons = nomi cartella da sondare con IsAddOnLoaded (le varianti coprono le diverse grafie: i nomi reali
-- degli addon Forever non sono verificati, confidenza B in docs/FOREVER_FACTS.md).
local KNOWN_ADDONS = {
    { title = "ClassicUI", addons = { "ClassicUI" }, modules = { "ActionBars", "Hider", "Scaling", "EditModeBridge" },
      note = L10n["ridisegna barre, minimappa e frame Blizzard in stile classico"] },
    { title = "ClassicUI Forever", addons = { "ClassicUI_Forever", "ClassicUIForever", "ClassicUI-Forever", "ClassicUI Forever" },
      modules = { "ActionBars", "Hider", "Scaling", "EditModeBridge" },
      note = L10n["sposta e ridisegna i frame Blizzard (layout Edit Mode classico)"] },
    { title = "Classic UI Forever Reframed", addons = { "ClassicUI_Forever_Reframed", "ClassicUIForeverReframed", "Classic_UI_Forever_Reframed", "ClassicUI_Reframed", "Classic UI Forever Reframed" },
      modules = { "ActionBars", "Hider", "Scaling", "EditModeBridge" },
      note = L10n["riposiziona i frame Blizzard tramite Edit Mode"] },
    { title = "Forevermore Classic UI", addons = { "ForevermoreClassicUI", "Forevermore_ClassicUI", "Forevermore", "ForevermoreUI" },
      modules = { "ActionBars", "Hider", "Scaling" }, note = L10n["ridisegna l'interfaccia in stile classico"] },
    { title = "Forever Unit Frames", addons = { "ForeverUnitFrames", "Forever_UnitFrames", "ForeverUF", "Forever Unit Frames" },
      modules = { "GroupFrames", "Nameplates", "Scaling" }, note = L10n["sostituisce i frame unita' e di gruppo"] },
    { title = "EllesmereUI", addons = { "EllesmereUI", "Ellesmere" },
      modules = { "ActionBars", "Nameplates", "GroupFrames", "Cooldowns", "Hider" },
      note = L10n["suite UI completa: barre, nameplate, frame di gruppo e cooldown"] },
    { title = "ElvUI", addons = { "ElvUI" }, modules = { "ActionBars", "Nameplates", "GroupFrames", "Cooldowns", "Hider", "Scaling" },
      note = L10n["sostituisce barre azioni, nameplate, frame di gruppo, testo dei cooldown e molti frame Blizzard"] },
    { title = "Bartender4", addons = { "Bartender4" }, modules = { "ActionBars" }, note = L10n["gestisce le barre azioni"] },
    { title = "Dominos", addons = { "Dominos" }, modules = { "ActionBars" }, note = L10n["gestisce le barre azioni"] },
    { title = "Clique", addons = { "Clique" }, modules = { "GroupFrames" },
      note = L10n["click casting sui frame di gruppo (Forever ha anche il click casting integrato)"] },
    { title = "Masque", addons = { "Masque" }, modules = { "ActionBars" }, note = L10n["applica skin ai pulsanti delle barre"] },
    { title = "OmniCC", addons = { "OmniCC" }, modules = { "Cooldowns" }, note = L10n["disegna il testo dei cooldown (doppio numero)"] },
    { title = "Bagnon", addons = { "Bagnon" }, modules = { "Hider" }, note = L10n["sostituisce borse e barra borse"] },
    { title = "Plater", addons = { "Plater" }, modules = { "Nameplates" }, note = "nameplate" },
    { title = "TidyPlates", addons = { "TidyPlates", "TidyPlates_ThreatPlates" }, modules = { "Nameplates" }, note = "nameplate" },
    { title = "Shadowed Unit Frames", addons = { "ShadowedUnitFrames", "SUF" }, modules = { "GroupFrames", "Scaling" },
      note = L10n["sostituisce i frame unita'"] },
    { title = "X-Perl", addons = { "XPerl", "ZPerl", "MetaPerl", "CPerl", "FPerl", "XPerl_Player", "ZPerl_Player" },
      modules = { "UnitFrames", "GroupFrames", "Scaling" },
      note = L10n["sostituisce i frame unita' e di gruppo: spegni UnitFrames di BadbUI (/badb disable UnitFrames)"] },
    { title = "Details!", addons = { "Details" }, modules = {}, note = "meter" },
    { title = "WeakAuras", addons = { "WeakAuras" }, modules = {}, note = L10n["aura e icone"] },
}

local ERROR_BUFFER_MAX = 50
local DB_WARN_BYTES = 2 * 1024 * 1024
local MEMORY_REFRESH = 30            -- secondi minimi tra due UpdateAddOnMemoryUsage
local LEVEL_RANK = { error = 3, warn = 2, ok = 1 }

local M = Badb.Modules:New("Diagnostics", {
    title = L10n["Diagnostica"],
    category = L10n["Strumenti"],
    defaults = { enabled = true },
    options = {},
})
Badb.Diagnostics = M

---------------------------------------------------------------------------
-- Utilita'
---------------------------------------------------------------------------

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
    return 0
end

local function result(id, level, title, detail, fix)
    return { id = id, level = level, title = title, detail = detail, fix = fix }
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function listNames(names, max)
    max = max or 8
    local out = {}
    for i = 1, math.min(#names, max) do out[i] = names[i] end
    local s = table.concat(out, ", ")
    if #names > max then s = s .. string.format(" (+%d)", #names - max) end
    return s
end

-- Stima dei byte di una tabella (stessa forma della serializzazione), con guardia su cicli/profondita'.
local function estimate(v, depth, stack, counter)
    local tv = type(v)
    if tv == "string" then return #v + 4
    elseif tv == "number" then return 3 + #tostring(v)
    elseif tv == "boolean" then return 1
    elseif tv ~= "table" or depth > 40 or stack[v] then return 0 end
    counter.n = counter.n + 1
    if counter.n > 400000 then return 0 end
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

local function estimateSize(t) return estimate(t, 0, {}, { n = 0 }) end

local function simpleCopy(v, depth, stack)
    if type(v) ~= "table" then
        local tv = type(v)
        if tv == "string" or tv == "number" or tv == "boolean" then return v end
        return nil
    end
    if depth > 40 or stack[v] then return nil end
    stack[v] = true
    local o = {}
    for k, val in pairs(v) do
        local tk = type(k)
        if tk == "string" or tk == "number" then
            local c = simpleCopy(val, depth + 1, stack)
            if c ~= nil then o[k] = c end
        end
    end
    stack[v] = nil
    return o
end

local function isAddonLoaded(name)
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if type(fn) ~= "function" then return nil end
    local ok, loaded = pcall(fn, name)
    if not ok then return nil end
    return loaded and true or false
end

---------------------------------------------------------------------------
-- Errori Lua: buffer circolare con deduplica
---------------------------------------------------------------------------
local errs = { list = {}, index = {} }

local function moduleFromMessage(msg)
    local name = msg:match("^([%w_]+):") or msg:match("^Listener ([%w_]+) su ") or msg:match("^Listener ([%w_]+) on ") or msg:match("^%[([%w_]+)%]")
    if name and Modules.list[name] then return name end
    local file = msg:match("[/\\]Modules[/\\]([%w_]+)%.lua")
    if file and Modules.list[file] then return file end
    return nil
end

local function recordError(msg, stack)
    msg = tostring(msg)
    if #msg > 1000 then msg = msg:sub(1, 1000) end
    local key = msg:sub(1, 400)
    local t = now()
    local e = errs.index[key]
    if e then
        e.count = e.count + 1
        e.last = t
        return e
    end
    if #errs.list >= ERROR_BUFFER_MAX then
        local old = table.remove(errs.list, 1)
        errs.index[old.key] = nil
    end
    e = { key = key, msg = msg, count = 1, first = t, last = t, module = moduleFromMessage(msg),
        stack = type(stack) == "string" and stack:sub(1, 600) or nil }
    errs.list[#errs.list + 1] = e
    errs.index[key] = e
    return e
end

-- Decide se l'errore riguarda BadbUI (testo del messaggio o stack) e lo registra.
local function consider(msg)
    local text = type(msg) == "string" and msg or tostring(msg)
    local stack
    local relevant = text:find("BadbUI", 1, true) ~= nil
    if not relevant and type(debugstack) == "function" then
        local ok, st = pcall(debugstack, 3)
        if ok and type(st) == "string" then
            stack = st
            relevant = st:find("BadbUI", 1, true) ~= nil
        end
    end
    if relevant then recordError(text, stack) end
end

-- Copia degli errori catturati, piu' recente prima: { msg, count, first, last, module }
function M:GetErrors()
    local out = {}
    for i = #errs.list, 1, -1 do
        local e = errs.list[i]
        out[#out + 1] = { msg = e.msg, count = e.count, first = e.first, last = e.last, module = e.module }
    end
    return out
end

function M:ClearErrors()
    errs.list, errs.index = {}, {}
end

-- Handler concatenato: registra e poi inoltra SEMPRE al precedente. Mai lancia.
local function installHandler(self)
    if self._hook or type(seterrorhandler) ~= "function" then return end
    local prev = type(geterrorhandler) == "function" and geterrorhandler() or nil
    local hook = { prev = prev, active = true, busy = false }
    hook.fn = function(msg, ...)
        if hook.active and not hook.busy then
            hook.busy = true
            pcall(consider, msg)
            hook.busy = false
        end
        if prev then
            local ok, r = pcall(prev, msg, ...)
            if ok then return r end
        end
    end
    local ok = pcall(seterrorhandler, hook.fn)
    if ok then self._hook = hook end
end

local function removeHandler(self)
    local hook = self._hook
    if not hook then return end
    hook.active = false
    if type(geterrorhandler) == "function" and geterrorhandler() == hook.fn and hook.prev then
        pcall(seterrorhandler, hook.prev)
    end
    -- se qualcuno si e' concatenato dopo di noi restiamo in catena ma inerti (active = false).
    self._hook = nil
end

function M:OnEnable() installHandler(self) end
function M:OnDisable() removeHandler(self) end

---------------------------------------------------------------------------
-- Errori nel Logger, per modulo
---------------------------------------------------------------------------
local function loggedErrorsByModule()
    local map = {}
    local buf = Logger.buffer or {}
    for _, line in ipairs(buf) do
        local msg = type(line) == "string" and line:match("^%[[^%]]*%] ERROR: (.*)$")
        if msg then
            local name = moduleFromMessage(msg) or "(generico)"
            local m = map[name]
            if not m then m = { count = 0 }; map[name] = m end
            m.count = m.count + 1
            m.last = msg
        end
    end
    return map
end

---------------------------------------------------------------------------
-- Riparazione sicura del DB: backup prima, poi la correzione
---------------------------------------------------------------------------
local function repair(label, fn)
    local B = Badb.Backups
    if B and B.Create then
        local id, err = B:Create(L10n["Prima della riparazione: "] .. label, "pre-repair")
        if not id then return false, L10n["backup di sicurezza non creato: "] .. tostring(err) end
    elseif Badb.DB and Badb.DB.sv then
        M._safetySnapshot = simpleCopy(Badb.DB.sv, 0, {}) -- senza Backups: copia locale in memoria
    end
    local ok, err = pcall(fn)
    if not ok then return false, tostring(err) end
    Logger:Info(L10n["Diagnostica: riparato (%s)"], label)
    return true, label
end

local function relinkActive(name)
    local DB = Badb.DB
    if DB and DB.profileName == name then pcall(DB.SetProfile, DB, name, true) end
end

---------------------------------------------------------------------------
-- Controlli
---------------------------------------------------------------------------

-- (a) integrita' del database
local function checkDB()
    local DB = Badb.DB
    local sv = DB and DB.sv
    if type(sv) ~= "table" then
        return result("db", "error", L10n["Database non inizializzato"], L10n["BadbUIDB non e' disponibile"])
    end
    local issues = {}
    local function issue(id, title, detail, fn)
        issues[#issues + 1] = result("db:" .. id, "error", title, detail, function() return repair(title, fn) end)
    end

    if sv.schema ~= nil and (type(sv.schema) ~= "number" or sv.schema < 1) then
        issue("schema", L10n["Schema del database non valido"], L10n["valore '"] .. tostring(sv.schema) .. "'", function() sv.schema = nil end)
    end
    if type(sv.profiles) ~= "table" then
        issue("profiles", L10n["Tabella dei profili mancante o corrotta"], L10n["tipo "] .. type(sv.profiles), function()
            sv.profiles = {}
            if DB.profileName then relinkActive(DB.profileName) end
        end)
    else
        for _, name in ipairs(sortedKeys(sv.profiles)) do
            local p = sv.profiles[name]
            local label = L10n["profilo '"] .. tostring(name) .. "'"
            if type(p) ~= "table" then
                issue("profile:" .. tostring(name), L10n["Profilo corrotto: "] .. tostring(name), L10n["il profilo e' di tipo "] .. type(p) .. L10n[" (nessun dato recuperabile)"],
                    function() sv.profiles[name] = {}; relinkActive(name) end)
            else
                for _, sub in ipairs({ "modules", "frames" }) do
                    local t = p[sub]
                    if t ~= nil and type(t) ~= "table" then
                        issue("profile:" .. tostring(name) .. ":" .. sub, L10n["Sezione '"] .. sub .. L10n["' corrotta in "] .. label,
                            L10n["tipo "] .. type(t), function() p[sub] = {}; relinkActive(name) end)
                    elseif type(t) == "table" then
                        local bad = {}
                        for k, v in pairs(t) do if type(v) ~= "table" then bad[#bad + 1] = tostring(k) end end
                        if #bad > 0 then
                            table.sort(bad)
                            issue("profile:" .. tostring(name) .. ":" .. sub .. ":entries",
                                L10n["Voci non valide in "] .. sub .. " di " .. label, listNames(bad),
                                function()
                                    for k, v in pairs(t) do if type(v) ~= "table" then t[k] = nil end end
                                    relinkActive(name)
                                end)
                        end
                    end
                end
            end
        end
    end

    if sv.profileKeys ~= nil and type(sv.profileKeys) ~= "table" then
        issue("profileKeys", L10n["profileKeys corrotto"], L10n["tipo "] .. type(sv.profileKeys), function() sv.profileKeys = {} end)
    elseif type(sv.profileKeys) == "table" then
        local dangling = {}
        for k, v in pairs(sv.profileKeys) do
            if type(v) ~= "string" or type(sv.profiles) ~= "table" or type(sv.profiles[v]) ~= "table" then
                dangling[#dangling + 1] = tostring(k)
            end
        end
        if #dangling > 0 then
            table.sort(dangling)
            issue("profileKeys:dangling", L10n["Personaggi con un profilo inesistente"], #dangling .. L10n[" voce/i: i personaggi useranno 'Default'"],
                function()
                    for k, v in pairs(sv.profileKeys) do
                        if type(v) ~= "string" or type(sv.profiles[v]) ~= "table" then sv.profileKeys[k] = nil end
                    end
                end)
        end
    end

    if sv.specProfiles ~= nil and type(sv.specProfiles) ~= "table" then
        issue("specProfiles", L10n["specProfiles corrotto"], L10n["tipo "] .. type(sv.specProfiles), function() sv.specProfiles = {} end)
    elseif type(sv.specProfiles) == "table" then
        local function broken()
            local n = 0
            for ck, map in pairs(sv.specProfiles) do
                if type(map) ~= "table" then n = n + 1
                else
                    for idx, pname in pairs(map) do
                        if type(idx) ~= "number" or type(pname) ~= "string" or type(sv.profiles) ~= "table"
                            or type(sv.profiles[pname]) ~= "table" then n = n + 1 end
                    end
                end
            end
            return n
        end
        local n = broken()
        if n > 0 then
            issue("specProfiles:entries", L10n["Profili per specializzazione non validi"], n .. L10n[" voce/i errata/e"], function()
                for ck, map in pairs(sv.specProfiles) do
                    if type(map) ~= "table" then sv.specProfiles[ck] = nil
                    else
                        for idx, pname in pairs(map) do
                            if type(idx) ~= "number" or type(pname) ~= "string" or type(sv.profiles[pname]) ~= "table" then map[idx] = nil end
                        end
                    end
                end
            end)
        end
    end

    if sv.global ~= nil and type(sv.global) ~= "table" then
        issue("global", L10n["Impostazioni globali corrotte"], L10n["tipo "] .. type(sv.global), function() sv.global = {} end)
    elseif type(sv.global) == "table" and sv.global.backups ~= nil then
        local list = sv.global.backups
        if type(list) ~= "table" then
            issue("backups", L10n["Elenco backup corrotto"], L10n["tipo "] .. type(list), function() sv.global.backups = {} end)
        else
            local n = 0
            for _, e in pairs(list) do if type(e) ~= "table" or type(e.id) ~= "string" or type(e.data) ~= "table" then n = n + 1 end end
            if n > 0 then
                issue("backups:entries", L10n["Backup inutilizzabili nell'elenco"], n .. L10n[" voce/i da scartare"], function()
                    for i = #list, 1, -1 do
                        local e = list[i]
                        if type(e) ~= "table" or type(e.id) ~= "string" or type(e.data) ~= "table" then table.remove(list, i) end
                    end
                end)
            end
        end
    end

    if #issues == 0 then
        local count = 0
        if type(sv.profiles) == "table" then for _ in pairs(sv.profiles) do count = count + 1 end end
        return result("db", "ok", L10n["Database integro"], count .. L10n[" profilo/i, profilo attivo '"] .. tostring(DB.profileName) .. "'")
    end
    return issues
end

-- (b) client / interface / API
local function checkClient()
    local out = {}
    local iface = Compat.interface
    local tocRaw
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        local ok, v = pcall(C_AddOns.GetAddOnMetadata, Badb.name, "Interface")
        if ok then tocRaw = v end
    end
    local toc = tonumber(type(tocRaw) == "string" and tocRaw:match("^%s*(%d+)") or tocRaw)
    if toc and iface and toc ~= iface then
        out[#out + 1] = result("client", "warn", L10n["Versione interface diversa dal TOC"],
            string.format(L10n["client %s, TOC %s: aggiorna la riga '## Interface' del TOC"], tostring(iface), tostring(toc)))
    elseif not Compat.isForever then
        out[#out + 1] = result("client", "warn", L10n["Client non riconosciuto come WoW Forever"],
            "interface " .. tostring(iface) .. L10n[": alcune funzioni potrebbero non essere disponibili"])
    else
        out[#out + 1] = result("client", "ok", L10n["Client compatibile"],
            "interface " .. tostring(iface) .. (toc and L10n[" (TOC allineato)"] or L10n[" (TOC non leggibile)"]))
    end
    local missing = {}
    if not Compat.hasEditMode then missing[#missing + 1] = "Edit Mode" end
    if not Compat.hasSettings then missing[#missing + 1] = "Settings API" end
    if #missing > 0 then
        out[#out + 1] = result("api", "warn", L10n["API del client mancanti"], table.concat(missing, ", ") .. L10n[": funzioni correlate disattivate"])
    else
        out[#out + 1] = result("api", "ok", L10n["Edit Mode e Settings API disponibili"])
    end
    return out
end

-- (c) moduli: stato ed errori recenti
local function checkModules()
    local out = {}
    local logged = loggedErrorsByModule()
    local total, running = 0, 0
    for _, name in ipairs(Modules.order) do
        local m = Modules.list[name]
        total = total + 1
        if m.enabled then running = running + 1 end
        local wanted = Badb.DB and Badb.DB.profile and Badb.DB:Get(name, "enabled")
        local le = logged[name]
        if le then
            out[#out + 1] = result("module:" .. name, "error", L10n["Errori nel modulo "] .. name,
                le.count .. L10n[" errore/i recente/i, ultimo: "] .. tostring(le.last))
        elseif wanted and not m.enabled then
            out[#out + 1] = result("module:" .. name, "warn", L10n["Modulo "] .. name .. L10n[" non in esecuzione"],
                L10n["attivo nel profilo ma non avviato (dipendenza disattiva o errore in OnEnable)"])
        end
    end
    if logged["(generico)"] then
        local le = logged["(generico)"]
        out[#out + 1] = result("module:generic", "warn", L10n["Errori non attribuiti a un modulo"],
            le.count .. L10n[" errore/i, ultimo: "] .. tostring(le.last))
    end
    if #out == 0 then
        out[1] = result("modules", "ok", L10n["Moduli in ordine"], running .. L10n[" attivi su "] .. total)
    end
    return out
end

-- Ritorna le voci di KNOWN_ADDONS caricate (con il nome cartella trovato).
local function loadedKnownAddons()
    local list = {}
    for _, k in ipairs(KNOWN_ADDONS) do
        for _, folder in ipairs(k.addons) do
            if isAddonLoaded(folder) then list[#list + 1] = { def = k, folder = folder }; break end
        end
    end
    return list
end

-- (d) conflitti con altri addon di interfaccia
local function checkConflicts()
    if isAddonLoaded("BadbUI") == nil then
        return result("conflicts", "warn", L10n["Conflitti non verificabili"], L10n["API IsAddOnLoaded non disponibile"])
    end
    local out, loaded = {}, loadedKnownAddons()
    for _, item in ipairs(loaded) do
        local k = item.def
        local active = {}
        for _, mname in ipairs(k.modules) do
            local m = Modules.list[mname]
            if m and m.enabled then active[#active + 1] = mname end
        end
        if #active > 0 then
            out[#out + 1] = result("conflict:" .. k.title, "warn", k.title .. L10n[" puo' confliggere con BadbUI"],
                k.note .. L10n[". Moduli BadbUI coinvolti e attivi: "] .. table.concat(active, ", ")
                .. L10n[". Disattiva i moduli o la funzione equivalente nell'altro addon."])
        elseif #k.modules > 0 then
            out[#out + 1] = result("conflict:" .. k.title, "ok", k.title .. L10n[" caricato, nessun conflitto"],
                L10n["i moduli BadbUI coinvolti ("] .. table.concat(k.modules, ", ") .. L10n[") sono disattivi"])
        end
    end
    if #out == 0 then
        return result("conflicts", "ok", L10n["Nessun conflitto noto"], #loaded > 0 and L10n["addon informativi rilevati (vedi report)"] or nil)
    end
    return out
end

-- Informazioni sul giocatore (classe/ruolo/talenti) da Badb.Player
local function checkPlayerInfo()
    local P = Badb.Player
    if not (P and P.GetSnapshot) then return nil end
    local snap = P:GetSnapshot()
    local out = {}
    if snap.trees == nil then
        out[#out + 1] = result("playerinfo:talents", "warn", L10n["Talenti non leggibili"],
            L10n["il client non espone i talenti in modo leggibile: il ruolo e' stimato dalla classe. Imposta il ruolo con /badb role <tank|healer|dps>"])
    end
    if snap.roleConfidence == "low" then
        out[#out + 1] = result("playerinfo:role", "warn", L10n["Ruolo rilevato con confidenza bassa"],
            string.format(L10n["ruolo '%s' da '%s'. Conferma con /badb role <tank|healer|dps>"], tostring(snap.role), tostring(snap.roleSource)))
    end
    if #out == 0 then
        return result("playerinfo", "ok", L10n["Classe e ruolo rilevati"],
            string.format(L10n["%s, ruolo %s (fonte %s, confidenza %s)"], tostring(snap.class), tostring(snap.role),
                tostring(snap.roleSource), tostring(snap.roleConfidence)))
    end
    return out
end

-- Informativo: restrizioni note del client Forever (docs/FOREVER_FACTS.md, confidenza A/B, non verificate in gioco)
local function checkRestrictions()
    local hasSecret = type(issecretvalue) == "function"
    local hasLog = type(CombatLogGetCurrentEventInfo) == "function"
    return result("restrictions", "ok", L10n["Restrizioni note del client Forever"],
        L10n["salute unita', minaccia e chat nelle istanze possono essere secret values (BadbUI li confronta solo dopo Compat.IsSecret); "]
        .. L10n["il combat log non e' leggibile dagli addon (nessun modulo lo usa). Sondato: issecretvalue "]
        .. (hasSecret and L10n["presente"] or L10n["assente"]) .. ", CombatLogGetCurrentEventInfo " .. (hasLog and L10n["presente"] or L10n["assente"]) .. ".")
end

-- (e) CVar del countdown coerente col modulo Cooldowns
local function checkCVar()
    local cd = Modules.list.Cooldowns
    if not cd then return nil end
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if type(get) ~= "function" then
        return result("cvar", "warn", L10n["CVar countdownForCooldowns non leggibile"], L10n["API CVar non disponibile"])
    end
    local value = get("countdownForCooldowns")
    local wantOn = cd.enabled and Badb.DB and Badb.DB.profile and Badb.DB:Get("Cooldowns", "numbers")
    if wantOn and tostring(value) ~= "1" then
        return result("cvar", "warn", L10n["CVar countdownForCooldowns incoerente"],
            L10n["il modulo Cooldowns mostra i numeri ma la CVar vale '"] .. tostring(value) .. L10n["' (atteso '1')"],
            type(set) == "function" and function()
                set("countdownForCooldowns", "1")
                return true, L10n["CVar impostata a 1"]
            end or nil)
    end
    return result("cvar", "ok", L10n["CVar countdownForCooldowns coerente"], L10n["valore '"] .. tostring(value) .. "'")
end

-- (f) dimensione del DB
local function checkSize()
    local sv = Badb.DB and Badb.DB.sv
    if type(sv) ~= "table" then return nil end
    local total = estimateSize(sv)
    local backups = (type(sv.global) == "table" and sv.global.backups) and estimateSize(sv.global.backups) or 0
    local detail = string.format(L10n["~%.0f KB totali, di cui ~%.0f KB di backup"], total / 1024, backups / 1024)
    if total > DB_WARN_BYTES then
        return result("size", "warn", L10n["Database molto grande"], detail .. L10n[" (soglia "] .. math.floor(DB_WARN_BYTES / 1024) .. L10n[" KB): riduci i backup o i profili"])
    end
    return result("size", "ok", L10n["Dimensione database nella norma"], detail)
end

-- (g) frame registrati che non si risolvono
local function checkFrames()
    local FM = Badb.FrameManager
    if not FM or type(FM.registry) ~= "table" then return nil end
    local missing, total = {}, 0
    for key, desc in pairs(FM.registry) do
        total = total + 1
        local f = desc.frame
        if type(f) == "string" then f = _G[f] end
        if f == nil then missing[#missing + 1] = tostring(key) end
    end
    table.sort(missing)
    if #missing > 0 then
        return result("frames", "warn", L10n["Frame registrati non trovati"],
            #missing .. " su " .. total .. ": " .. listNames(missing) .. L10n[" (inesistenti in questo client o rimossi da un altro addon)"])
    end
    return result("frames", "ok", L10n["Frame registrati risolti"], total .. " frame")
end

-- errori Lua catturati
local function checkLuaErrors()
    if #errs.list == 0 then return result("luaerrors", "ok", L10n["Nessun errore Lua catturato"]) end
    local n = 0
    for _, e in ipairs(errs.list) do n = n + e.count end
    local last = errs.list[#errs.list]
    return result("luaerrors", "error", L10n["Errori Lua riferiti a BadbUI"],
        n .. L10n[" occorrenza/e ("] .. #errs.list .. L10n[" distinti), ultimo: "] .. tostring(last.msg):sub(1, 160) .. " - /badb doctor errors")
end

M.checks = {
    { id = "db", fn = checkDB },
    { id = "client", fn = checkClient },
    { id = "modules", fn = checkModules },
    { id = "conflicts", fn = checkConflicts },
    { id = "playerinfo", fn = checkPlayerInfo },
    { id = "restrictions", fn = checkRestrictions },
    { id = "cvar", fn = checkCVar },
    { id = "size", fn = checkSize },
    { id = "frames", fn = checkFrames },
    { id = "luaerrors", fn = checkLuaErrors },
}

-- Esegue tutti i controlli; ognuno e' isolato: se lancia diventa un risultato "error".
-- -> { {id, level = "ok|warn|error", title, detail, fix = fn|nil}, ... }
function M:RunChecks()
    local out = {}
    for _, c in ipairs(self.checks) do
        local ok, res = pcall(c.fn)
        if not ok then
            out[#out + 1] = result(tostring(c.id), "error", L10n["Check fallito: "] .. tostring(c.id), tostring(res))
        elseif type(res) == "table" then
            local list = res.level and { res } or res
            for _, r in ipairs(list) do
                if type(r) == "table" then
                    r.id = r.id or tostring(c.id)
                    if not LEVEL_RANK[r.level] then r.level = "warn" end
                    r.title = tostring(r.title or r.id)
                    if r.fix ~= nil and type(r.fix) ~= "function" then r.fix = nil end
                    out[#out + 1] = r
                end
            end
        end
    end
    self.lastResults = out
    return out
end

---------------------------------------------------------------------------
-- Statistiche leggere
---------------------------------------------------------------------------

-- La memoria si misura solo per l'intero addon (non esiste per modulo): per i moduli stimiamo
-- i dati salvati. UpdateAddOnMemoryUsage al massimo ogni 30 secondi.
function M:GetStats()
    local stats = { modules = {}, errors = #errs.list }
    if type(GetAddOnMemoryUsage) == "function" then
        local t = type(GetTime) == "function" and GetTime() or 0
        if not self._memAt or t - self._memAt >= MEMORY_REFRESH then
            if type(UpdateAddOnMemoryUsage) == "function" then pcall(UpdateAddOnMemoryUsage) end
            local ok, kb = pcall(GetAddOnMemoryUsage, Badb.name)
            if ok and type(kb) == "number" then self._mem = kb end
            self._memAt = t
        end
        stats.addonMemoryKB = self._mem
    end
    local logged = loggedErrorsByModule()
    for _, name in ipairs(Modules.order) do
        local m = Modules.list[name]
        local data = Badb.DB and Badb.DB.profile and Badb.DB.profile.modules and Badb.DB.profile.modules[name]
        stats.modules[name] = { enabled = m.enabled and true or false, errors = logged[name] and logged[name].count or 0,
            dataBytes = data and estimateSize(data) or 0 }
    end
    return stats
end

---------------------------------------------------------------------------
-- Report (privacy: niente nome/reame in chiaro, niente payload dei profili)
---------------------------------------------------------------------------
local function shortHash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 16777216 end
    return string.format("%06x", h)
end

local function replaceName(text, word, repl)
    if type(word) ~= "string" or #word < 2 then return text end
    local strict = #word < 4 -- nomi molto corti solo come parola intera, per non rovinare il testo
    local out, pos = {}, 1
    while true do
        local s, e = text:find(word, pos, true)
        if not s then break end
        local ok = true
        if strict then
            ok = not text:sub(s - 1, s - 1):match("%w") and not text:sub(e + 1, e + 1):match("%w")
        end
        out[#out + 1] = text:sub(pos, s - 1)
        out[#out + 1] = ok and repl or word
        pos = e + 1
    end
    out[#out + 1] = text:sub(pos)
    return table.concat(out)
end

local function scrub(text)
    local name = type(UnitName) == "function" and UnitName("player") or nil
    local realm = type(GetRealmName) == "function" and GetRealmName() or nil
    local realmNorm = type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName() or nil
    if realm and realm ~= "" then text = replaceName(text, realm, "<reame>") end
    if realmNorm and realmNorm ~= realm then text = replaceName(text, realmNorm, "<reame>") end
    if name and name ~= "" then text = replaceName(text, name, "<pg>") end
    return text
end

local function fmtDate(t)
    local ok, s = pcall(date, "%Y-%m-%d %H:%M", t)
    return ok and s or tostring(t)
end

function M:Report()
    local ok, text = pcall(function()
        local L = {}
        local function add(fmt, ...)
            local ok2, line = pcall(string.format, fmt, ...)
            L[#L + 1] = ok2 and line or tostring(fmt)
        end
        local DB = Badb.DB
        add(L10n["BadbUI - report diagnostico"])
        add(L10n["Generato: %s"], fmtDate(now()))
        add("Addon: BadbUI v%s", tostring(Badb.version))
        local version, build, bdate = "?", "?", "?"
        if type(GetBuildInfo) == "function" then
            local ok2, v, b, d = pcall(GetBuildInfo)
            if ok2 then version, build, bdate = tostring(v), tostring(b), tostring(d) end
        end
        add("Client: %s (build %s, %s) interface %s", version, build, bdate, tostring(Compat.interface))
        add("Locale: %s", type(GetLocale) == "function" and tostring(GetLocale()) or "?")
        add("forever: %s | Edit Mode: %s | Settings API: %s", Compat.isForever and L10n["si'"] or "no",
            Compat.hasEditMode and L10n["si'"] or "no", Compat.hasSettings and L10n["si'"] or "no")
        local charKey = DB and DB.char or ((type(UnitName) == "function" and UnitName("player") or "?") .. "-" .. (type(GetRealmName) == "function" and GetRealmName() or "?"))
        add(L10n["Personaggio: #%s"], shortHash(tostring(charKey)))
        local profileCount = 0
        if DB and DB.sv and type(DB.sv.profiles) == "table" then for _ in pairs(DB.sv.profiles) do profileCount = profileCount + 1 end end
        add(L10n["Profilo attivo: %s (%d profili)"], tostring(DB and DB.profileName), profileCount)

        local P = Badb.Player
        if P and P.GetSnapshot then
            local snap = P:GetSnapshot()
            add(L10n["Giocatore: classe %s, livello %s, ruolo %s (fonte %s, confidenza %s)"], tostring(snap.class), tostring(snap.level),
                tostring(snap.role), tostring(snap.roleSource), tostring(snap.roleConfidence))
            add(L10n["Talenti: gruppo %s/%s, albero %s, lettura %s"], tostring(snap.talentGroup), tostring(snap.numTalentGroups),
                tostring(snap.tree or L10n["n/d"]), snap.trees and ("ok (" .. tostring(snap.treeSource) .. ")") or L10n["non leggibili"])
        end

        local stats = self:GetStats()
        if stats.addonMemoryKB then add(L10n["Memoria addon: %.0f KB"], stats.addonMemoryKB) end
        add("")
        add(L10n["Moduli:"])
        for _, name in ipairs(Modules.order) do
            local st = stats.modules[name] or {}
            add("  %s: %s%s", name, st.enabled and L10n["attivo"] or L10n["spento"], (st.errors or 0) > 0 and (L10n[", errori: "] .. st.errors) or "")
        end

        add("")
        add(L10n["Controlli:"])
        local results = self:RunChecks()
        local tags = { ok = "OK", warn = L10n["AVVISO"], error = L10n["ERRORE"] }
        for _, r in ipairs(results) do
            add("  [%s] %s%s", tags[r.level] or r.level, r.title, r.detail and (" - " .. r.detail) or "")
        end

        add("")
        local logs = Logger.buffer or {}
        local first = math.max(1, #logs - 19)
        add(L10n["Ultimi log (%d):"], #logs - first + 1 < 0 and 0 or (#logs - first + 1))
        for i = first, #logs do add("  %s", tostring(logs[i])) end

        add("")
        local errors = self:GetErrors()
        add(L10n["Errori Lua catturati (%d):"], #errors)
        for i = 1, math.min(#errors, 10) do
            local e = errors[i]
            add("  x%d %s%s", e.count, e.module and ("[" .. e.module .. "] ") or "", tostring(e.msg):sub(1, 300))
        end

        add("")
        local loaded = {}
        for _, item in ipairs(loadedKnownAddons()) do loaded[#loaded + 1] = item.def.title end
        add(L10n["Addon di interfaccia caricati: %s"], #loaded > 0 and table.concat(loaded, ", ") or L10n["nessuno tra quelli noti"])
        return scrub(table.concat(L, "\n"))
    end)
    if ok then return text end
    Logger:Error("Diagnostics:Report - %s", tostring(text))
    return L10n["Impossibile generare il report: "] .. tostring(text)
end

---------------------------------------------------------------------------
-- Comandi /badb doctor ...
---------------------------------------------------------------------------
local ICONS = { ok = "OK", warn = "!", error = "X" }

local function showText(title, text)
    local UI = Badb.ConfigUI
    if UI and UI.TextBox then
        UI:TextBox(title, text)
    else
        for line in (text .. "\n"):gmatch("(.-)\n") do Logger:Info("%s", line) end
    end
end

M.commands = {
    doctor = {
        help = "doctor run | report | errors",
        fn = function(args)
            local sub = ((args or ""):match("^(%S*)") or ""):lower()
            if sub == "report" then
                showText(L10n["Report BadbUI"], M:Report())
            elseif sub == "errors" then
                local list = M:GetErrors()
                if #list == 0 then Logger:Info(L10n["Nessun errore Lua catturato"]); return end
                for i, e in ipairs(list) do
                    Logger:Info("%d. x%d %s%s", i, e.count, e.module and ("[" .. e.module .. "] ") or "", tostring(e.msg):sub(1, 200))
                end
            else -- run (default)
                local counts = { ok = 0, warn = 0, error = 0 }
                for _, r in ipairs(M:RunChecks()) do
                    counts[r.level] = counts[r.level] + 1
                    if r.level ~= "ok" then
                        Logger:Info("[%s] %s%s", ICONS[r.level], r.title, r.detail and (" - " .. r.detail) or "")
                    end
                end
                Logger:Info(L10n["Diagnostica: %d ok, %d avvisi, %d errori"], counts.ok, counts.warn, counts.error)
            end
        end,
    },
}

-- /badb role <tank|healer|dps|auto>: override del ruolo, validato contro i ruoli ammessi dalla classe.
M.commands.role = {
    help = "role <tank|healer|dps|auto>",
    fn = function(args)
        local P = Badb.Player
        if not (P and P.SetRoleOverride) then Logger:Warn(L10n["Servizio PlayerInfo non disponibile"]); return end
        local role = ((args or ""):match("^(%S*)") or ""):lower()
        local snap = P:GetSnapshot()
        if role == "" then
            Logger:Info(L10n["Ruolo attuale: %s (fonte %s, confidenza %s). Uso: /badb role <tank|healer|dps|auto>"],
                tostring(snap.role), tostring(snap.roleSource), tostring(snap.roleConfidence))
            return
        end
        if role == "auto" or role == "reset" then
            local ok, err = P:SetRoleOverride(nil)
            Logger:Info(ok and L10n["Override del ruolo rimosso"] or (L10n["Operazione fallita: "] .. tostring(err)))
            return
        end
        local info = snap.class and P.GetClassInfo and P:GetClassInfo(snap.class)
        if info then
            local allowed = false
            for _, r in ipairs(info.roles) do if r == role then allowed = true end end
            if not allowed then
                Logger:Warn(L10n["La classe %s non puo' avere il ruolo '%s' (ammessi: %s)"], tostring(snap.class), role, table.concat(info.roles, ", "))
                return
            end
        elseif role ~= "tank" and role ~= "healer" and role ~= "dps" then
            Logger:Warn(L10n["Ruolo non valido: usa tank, healer o dps"])
            return
        end
        local ok, err = P:SetRoleOverride(role)
        Logger:Info(ok and (L10n["Ruolo impostato: "] .. role) or (L10n["Operazione fallita: "] .. tostring(err)))
    end,
}

---------------------------------------------------------------------------
-- Pagina ConfigUI (category "Strumenti")
---------------------------------------------------------------------------
local ROW_H = 40
local TEXTURES = {
    ok = "Interface\\RaidFrame\\ReadyCheck-Ready",
    warn = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
    error = "Interface\\RaidFrame\\ReadyCheck-NotReady",
}

local function buildPage(parent, ctx)
    local UI = ctx and ctx.UI
    local state = { rows = {} }
    M._page = state

    local function notify(text, level)
        if UI and UI.Toast then pcall(UI.Toast, UI, text, level) else Logger:Info("%s", text) end
    end

    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, 0)
    title:SetText(L10n["Diagnostica"])

    state.btnRun = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    state.btnRun:SetSize(110, 22); state.btnRun:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -30)
    state.btnRun:SetText(L10n["Esegui"])
    state.btnRun:SetScript("OnClick", function() state.render() end)

    state.btnReport = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    state.btnReport:SetSize(130, 22); state.btnReport:SetPoint("TOPLEFT", parent, "TOPLEFT", 132, -30)
    state.btnReport:SetText(L10n["Copia report"])
    state.btnReport:SetScript("OnClick", function()
        if UI and UI.TextBox then UI:TextBox(L10n["Report BadbUI"], M:Report()) else notify(L10n["Finestra di testo non disponibile"], "error") end
    end)

    state.summary = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    state.summary:SetPoint("TOPLEFT", parent, "TOPLEFT", 270, -34)

    local function row(i)
        local r = state.rows[i]
        if r then return r end
        local y = 64 + (i - 1) * ROW_H
        r = {}
        r.icon = parent:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(18, 18); r.icon:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -y - 2)
        r.text = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        r.text:SetPoint("TOPLEFT", parent, "TOPLEFT", 42, -y)
        r.text:SetWidth(400); r.text:SetJustifyH("LEFT")
        r.fix = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        r.fix:SetSize(80, 22); r.fix:SetPoint("TOPLEFT", parent, "TOPLEFT", 460, -y)
        r.fix:SetText(L10n["Ripara"])
        state.rows[i] = r
        return r
    end

    function state.render()
        local results = M:RunChecks()
        -- piu' gravi in alto, a parita' di livello l'ordine dei controlli
        local idx = {}
        for i, r in ipairs(results) do idx[r] = i end
        table.sort(results, function(a, b)
            local ra, rb = LEVEL_RANK[a.level], LEVEL_RANK[b.level]
            if ra ~= rb then return ra > rb end
            return idx[a] < idx[b]
        end)
        local counts = { ok = 0, warn = 0, error = 0 }
        for i = 1, math.max(#results, #state.rows) do
            local res = results[i]
            if res then
                counts[res.level] = counts[res.level] + 1
                local r = row(i)
                r.icon:SetTexture(TEXTURES[res.level])
                r.text:SetText(res.title .. (res.detail and ("\n|cff999999" .. res.detail .. "|r") or ""))
                r.icon:Show(); r.text:Show()
                if res.fix then
                    r.fix:SetScript("OnClick", function()
                        local ok, msg = res.fix()
                        notify(ok and (L10n["Riparato: "] .. tostring(msg)) or (L10n["Riparazione fallita: "] .. tostring(msg)), ok and "info" or "error")
                        state.render()
                    end)
                    r.fix:Show()
                else
                    r.fix:Hide()
                end
            elseif state.rows[i] then
                state.rows[i].icon:Hide(); state.rows[i].text:Hide(); state.rows[i].fix:Hide()
            end
        end
        state.summary:SetText(string.format(L10n["%d ok, %d avvisi, %d errori"], counts.ok, counts.warn, counts.error))
        state.results = results
        local h = 64 + math.max(#results, 1) * ROW_H + 8
        if parent.SetHeight then parent:SetHeight(h) end
        state.height = h
        return h
    end

    return state.render()
end

M.page = {
    title = L10n["Diagnostica"], order = 95, category = L10n["Strumenti"],
    build = buildPage,
    refresh = function() if M._page and M._page.render then M._page.render() end end,
}
