-- BadbUI - Adapter per gli addon terzi (ElvUI, Details!, Plater, Bartender4, BigWigs, DBM, WeakAuras).
-- Caricato PRIMA di Modules/Integrations.lua: espone le definizioni in Badb.IntegrationAdapterDefs
-- (lista ordinata) e gli helper in Badb.IntegrationAdapterHelpers; il modulo le registra a OnInitialize.
--
-- Definizione di un adapter:
--   { id, title, addon, detect = fn -> bool, capture = fn -> tabella | nil, err,
--     apply = fn(payload) -> true | false, err | "skipped", motivo,   reset = fn? -> ok, err,
--     supported = false + unsupportedReason = "..." (solo stato, nessuna API da usare) }
--
-- ATTENZIONE: le API degli addon terzi qui sotto sono "best-effort, non verificate in gioco".
-- Ogni accesso e' sondato (esistenza del metodo) e protetto da pcall; se l'API non c'e' l'adapter
-- degrada con un errore chiaro invece di lanciare. Gli adapter AceDB salvano il NOME del profilo
-- attivo, non il contenuto del profilo (vedi docs/integrations.md).
local _, ns = ...
local Badb = ns.Badb

local H = {}
Badb.IntegrationAdapterHelpers = H

local Defs = {}
Badb.IntegrationAdapterDefs = Defs

local MAX_NAME_LEN = 128
local MAX_EXPORT_STRING = 40 * 1024 -- stringhe di export opzionali oltre questa soglia vengono scartate

-- ---------------------------------------------------------------------------------------
-- Helper difensivi
-- ---------------------------------------------------------------------------------------

local function isSecret(v)
    return Badb.Compat ~= nil and Badb.Compat.IsSecret(v) or false
end

-- Lettura di un campo che non lancia mai (metatable ostili, __index che fallisce).
local function safeGet(t, key)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(function() return t[key] end)
    if ok then return v end
    return nil
end

-- Chiama obj:method(...) in pcall. Ritorna ok, r1, r2, r3. Metodo mancante => false + messaggio.
local function callMethod(obj, method, ...)
    local fn = safeGet(obj, method)
    if type(fn) ~= "function" then return false, "metodo non disponibile: " .. tostring(method) end
    local ok, a, b, c = pcall(fn, obj, ...)
    if not ok then return false, tostring(a) end
    return true, a, b, c
end

local function validName(name)
    return type(name) == "string" and name ~= "" and #name <= MAX_NAME_LEN and not isSecret(name)
end

-- true/false se l'API lo sa dire, nil se non c'e' modo di saperlo.
local function addOnLoadedKnown(addon)
    local api = C_AddOns and C_AddOns.IsAddOnLoaded or _G.IsAddOnLoaded
    if type(api) ~= "function" then return nil end
    local ok, loaded = pcall(api, addon)
    if not ok then return nil end
    return loaded and true or false
end

-- Rilevamento: se il client sa dire se l'addon e' caricato ci si fida, altrimenti basta il globale.
local function detectAddon(addon, globalName)
    local known = addOnLoadedKnown(addon)
    if known == false then return false end
    return type(rawget(_G, globalName)) == "table"
end

H.safeGet, H.callMethod, H.validName = safeGet, callMethod, validName
H.isAddOnLoaded = addOnLoadedKnown
H.detectAddon = detectAddon

local function nameOf(db, methods)
    for _, m in ipairs(methods) do
        local ok, name = callMethod(db, m)
        if ok and validName(name) then return name end
    end
    return nil
end

-- Il profilo esiste? ritorna exists, known (known=false se l'API non permette di verificarlo).
local function aceProfileExists(db, name)
    local sv = safeGet(db, "sv")
    local profiles = safeGet(sv, "profiles") or safeGet(db, "profiles")
    if type(profiles) == "table" then
        return safeGet(profiles, name) ~= nil, true
    end
    local ok, list = callMethod(db, "GetProfiles")
    if ok and type(list) == "table" then
        for _, n in ipairs(list) do
            if n == name then return true, true end
        end
        return false, true
    end
    return false, false
end
H.aceProfileExists = aceProfileExists

-- ---------------------------------------------------------------------------------------
-- Adapter generico AceDB: cattura il nome del profilo attivo, lo riapplica con db:SetProfile.
--   dbGetter() -> istanza AceDB (o nil)
--   extra (opzionale): { captureExtra = fn(db, payload), applyMissing = fn(db, payload, name),
--                        reset = fn }  per addon con funzioni aggiuntive (es. ElvUI)
-- ---------------------------------------------------------------------------------------
local function aceDBAdapter(id, title, addon, dbGetter, extra)
    extra = extra or {}
    local globalName = extra.global or addon

    local function getDB()
        local ok, db = pcall(dbGetter)
        if ok and type(db) == "table" then return db end
        return nil
    end

    local a = {
        id = id, title = title, addon = addon,
        detect = function() return detectAddon(addon, globalName) end,
        capture = function()
            local db = getDB()
            if not db then return nil, "database di " .. title .. " non disponibile" end
            local name = nameOf(db, { "GetCurrentProfile" })
            if not name then return nil, "profilo attivo di " .. title .. " non leggibile (API AceDB assente?)" end
            local payload = { profile = name }
            if extra.captureExtra then pcall(extra.captureExtra, db, payload) end
            return payload
        end,
        apply = function(payload)
            local db = getDB()
            if not db then return false, "database di " .. title .. " non disponibile" end
            local name = type(payload) == "table" and payload.profile
            if not validName(name) then return false, "nome profilo non valido nei dati catturati" end
            local current = nameOf(db, { "GetCurrentProfile" })
            local exists, known = aceProfileExists(db, name)
            if known and not exists then
                if extra.applyMissing then
                    local ok, r1, r2 = pcall(extra.applyMissing, db, payload, name)
                    if ok and r1 ~= nil then return r1, r2 end
                end
                -- Un SetProfile creerebbe un profilo vuoto: meglio non toccare nulla.
                return "skipped", "profilo mancante: '" .. name .. "' non esiste su questo account (" .. title .. ")"
            end
            if current == name then return true end
            local ok, err = callMethod(db, "SetProfile", name)
            if not ok then return false, err end
            local after = nameOf(db, { "GetCurrentProfile" })
            if after and after ~= name then
                return false, "SetProfile non ha cambiato il profilo di " .. title
            end
            return true
        end,
        reset = function()
            local db = getDB()
            if not db then return false, "database di " .. title .. " non disponibile" end
            local ok, err = callMethod(db, "ResetProfile")
            if not ok then return false, err end
            return true
        end,
    }
    return a
end
H.aceDBAdapter = aceDBAdapter

-- ---------------------------------------------------------------------------------------
-- ElvUI: ElvUI[1] = E, E.data = AceDB. Se il modulo Distributor offre ExportProfile/ImportProfile
-- (best-effort, firma non verificata) si cattura anche la stringa di export per i profili mancanti.
-- ---------------------------------------------------------------------------------------
local function elvuiEngine()
    local root = rawget(_G, "ElvUI")
    return safeGet(root, 1)
end

local function elvuiDistributor()
    local E = elvuiEngine()
    if not E then return nil end
    local ok, D = callMethod(E, "GetModule", "Distributor", true)
    if ok and type(D) == "table" then return D end
    return nil
end

Defs[#Defs + 1] = aceDBAdapter("elvui", "ElvUI", "ElvUI", function()
    return safeGet(elvuiEngine(), "data")
end, {
    captureExtra = function(db, payload)
        local D = elvuiDistributor()
        if not D then return end
        local ok, _, export = callMethod(D, "ExportProfile", payload.profile, "profile", "text")
        if ok and type(export) == "string" and export ~= "" and #export <= MAX_EXPORT_STRING and not isSecret(export) then
            payload.exportString = export
        end
    end,
    applyMissing = function(db, payload, name)
        local D = elvuiDistributor()
        if not D or type(payload.exportString) ~= "string" then return nil end
        local ok, err = callMethod(D, "ImportProfile", payload.exportString)
        if not ok then return false, "import del profilo ElvUI fallito: " .. tostring(err) end
        local exists, known = aceProfileExists(db, name)
        if known and not exists then
            return "skipped", "profilo mancante: '" .. name .. "' non creato dall'import di ElvUI"
        end
        local okSet, errSet = callMethod(db, "SetProfile", name)
        if not okSet then return false, errSet end
        return true
    end,
})

-- ---------------------------------------------------------------------------------------
-- Details!: Details:GetCurrentProfileName() (o GetCurrentProfile) / Details:ApplyProfile(nome).
-- ---------------------------------------------------------------------------------------
local function detailsObj() return rawget(_G, "Details") end

Defs[#Defs + 1] = {
    id = "details", title = "Details!", addon = "Details",
    detect = function() return detectAddon("Details", "Details") end,
    capture = function()
        local D = detailsObj()
        local name = nameOf(D, { "GetCurrentProfileName", "GetCurrentProfile" })
        if not name then return nil, "profilo attivo di Details! non leggibile (API assente?)" end
        return { profile = name }
    end,
    apply = function(payload)
        local D = detailsObj()
        local name = type(payload) == "table" and payload.profile
        if not validName(name) then return false, "nome profilo non valido nei dati catturati" end
        if type(safeGet(D, "ApplyProfile")) ~= "function" then
            return false, "Details:ApplyProfile non disponibile"
        end
        -- Esistenza del profilo: elenco se disponibile (best-effort).
        local ok, list = callMethod(D, "GetProfileList")
        if ok and type(list) == "table" then
            local found = false
            for k, v in pairs(list) do
                if v == name or k == name then found = true; break end
            end
            if not found then
                return "skipped", "profilo mancante: '" .. name .. "' non esiste su questo account (Details!)"
            end
        end
        if nameOf(D, { "GetCurrentProfileName", "GetCurrentProfile" }) == name then return true end
        local okA, err = callMethod(D, "ApplyProfile", name)
        if not okA then return false, err end
        return true
    end,
    reset = function()
        local D = detailsObj()
        local name = nameOf(D, { "GetCurrentProfileName", "GetCurrentProfile" })
        if not name then return false, "profilo attivo di Details! non leggibile" end
        local ok, err = callMethod(D, "ResetProfile", name)
        if not ok then return false, err end
        return true
    end,
}

-- ---------------------------------------------------------------------------------------
-- Plater, Bartender4, BigWigs: tutti AceDB.
-- ---------------------------------------------------------------------------------------
Defs[#Defs + 1] = aceDBAdapter("plater", "Plater", "Plater", function()
    return safeGet(rawget(_G, "Plater"), "db")
end)

Defs[#Defs + 1] = aceDBAdapter("bartender4", "Bartender4", "Bartender4", function()
    return safeGet(rawget(_G, "Bartender4"), "db")
end)

Defs[#Defs + 1] = aceDBAdapter("bigwigs", "BigWigs", "BigWigs", function()
    return safeGet(rawget(_G, "BigWigs"), "db")
end)

-- ---------------------------------------------------------------------------------------
-- DBM: DBM_UsedProfile (profilo in uso), DBM_AllSavedOptions[nome] (tutti i profili),
-- DBM:ApplyProfile(nome). Nessuna scrittura diretta sulle SavedVariables di DBM.
-- ---------------------------------------------------------------------------------------
Defs[#Defs + 1] = {
    id = "dbm", title = "Deadly Boss Mods", addon = "DBM-Core",
    detect = function() return detectAddon("DBM-Core", "DBM") end,
    capture = function()
        local name = rawget(_G, "DBM_UsedProfile")
        if not validName(name) then return nil, "profilo attivo di DBM non determinabile (DBM_UsedProfile assente)" end
        return { profile = name }
    end,
    apply = function(payload)
        local name = type(payload) == "table" and payload.profile
        if not validName(name) then return false, "nome profilo non valido nei dati catturati" end
        local all = rawget(_G, "DBM_AllSavedOptions")
        if type(all) == "table" and safeGet(all, name) == nil then
            return "skipped", "profilo mancante: '" .. name .. "' non esiste su questo personaggio (DBM)"
        end
        if rawget(_G, "DBM_UsedProfile") == name then return true end
        local ok, err = callMethod(rawget(_G, "DBM"), "ApplyProfile", name)
        if not ok then return false, err end
        return true
    end,
}

-- ---------------------------------------------------------------------------------------
-- WeakAuras: solo stato. Nessuna API pubblica documentata per esportare/applicare l'insieme delle
-- aura: non se ne inventa una. L'utente usa l'export nativo di WeakAuras.
-- ---------------------------------------------------------------------------------------
Defs[#Defs + 1] = {
    id = "weakauras", title = "WeakAuras", addon = "WeakAuras",
    supported = false,
    unsupportedReason = "WeakAuras non espone un'API pubblica per catturare o riapplicare le aura: usa l'export/import nativo di WeakAuras",
    detect = function() return detectAddon("WeakAuras", "WeakAuras") end,
}
