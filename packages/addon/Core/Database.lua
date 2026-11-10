-- BadbUI - Database e profili
-- Struttura di BadbUIDB:
--   schema        numero versione per le migrazioni
--   profiles      { [nome] = { modules = { [modulo] = {...} }, frames = { [frameKey] = {...} } } }
--   profileKeys   { ["Personaggio - Reame"] = nomeProfilo }
--   specProfiles  { ["Personaggio - Reame"] = { [specIndex] = nomeProfilo } } (dual spec)
--   global        impostazioni non legate al profilo
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local Events, Logger = Badb.Events, Badb.Logger

local DB = { defaults = { modules = {}, frames = {} }, migrations = {} }
Badb.DB = DB

local SCHEMA = 1

local function charKey()
    return (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?")
end

-- Ogni modulo registra i propri default; vengono fusi nel profilo attivo.
function DB:RegisterDefaults(moduleName, defaults)
    self.defaults.modules[moduleName] = defaults
    if self.profile then
        self.profile.modules[moduleName] = self.profile.modules[moduleName] or {}
        Badb.MergeDefaults(self.profile.modules[moduleName], defaults)
    end
end

-- Le migrazioni si eseguono in ordine: DB:AddMigration(2, function(sv) ... end)
function DB:AddMigration(version, fn)
    self.migrations[version] = fn
end

local function migrate(sv)
    sv.schema = sv.schema or SCHEMA
    while sv.schema < SCHEMA do
        local nextVer = sv.schema + 1
        local fn = DB.migrations[nextVer]
        if fn then
            local ok, err = pcall(fn, sv)
            if not ok then Logger:Error(L["Migrazione %d fallita: %s"], nextVer, err); return end
        end
        sv.schema = nextVer
        Logger:Info(L["Database aggiornato allo schema %d"], nextVer)
    end
end

function DB:Initialize()
    BadbUIDB = BadbUIDB or {}
    local sv = BadbUIDB
    sv.profiles = sv.profiles or {}
    sv.profileKeys = sv.profileKeys or {}
    sv.specProfiles = sv.specProfiles or {}
    sv.global = sv.global or {}
    migrate(sv)
    self.sv = sv
    self.char = charKey()
    self:SetProfile(sv.profileKeys[self.char] or "Default", true)
end

function DB:GetProfileName() return self.profileName end

function DB:ListProfiles()
    local list = {}
    for name in pairs(self.sv.profiles) do list[#list + 1] = name end
    table.sort(list)
    return list
end

function DB:SetProfile(name, silent)
    local sv = self.sv
    sv.profiles[name] = sv.profiles[name] or {}
    local p = sv.profiles[name]
    Badb.MergeDefaults(p, self.defaults)
    sv.profileKeys[self.char] = name
    self.profileName, self.profile = name, p
    if not silent then Events:Fire("BADB_PROFILE_CHANGED", name) end
end

-- Nomi profilo: stringa non vuota (dopo trim), max 48 caratteri, senza codici colore/escape.
DB.MAX_NAME = 48
function DB.NormalizeName(name)
    if type(name) ~= "string" then return nil, L["nome non valido"] end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil, L["il nome non puo' essere vuoto"] end
    if #name > DB.MAX_NAME then return nil, L["nome troppo lungo (max "] .. DB.MAX_NAME .. L[" caratteri)"] end
    if name:find("|", 1, true) or name:find("[%c]") then return nil, L["il nome contiene caratteri non ammessi"] end
    return name
end

function DB:ProfileExists(name) return type(name) == "string" and self.sv.profiles[name] ~= nil end

local function forEachReference(sv, fn)
    for k, v in pairs(sv.profileKeys) do fn(sv.profileKeys, k, v) end
    for _, map in pairs(sv.specProfiles) do
        if type(map) == "table" then
            for i, v in pairs(map) do fn(map, i, v) end
        end
    end
end

function DB:CopyProfile(from, to)
    local src = self.sv.profiles[from]
    if not src then return false, L["profilo inesistente"] end
    local name, err = DB.NormalizeName(to)
    if not name then return false, err end
    if self.sv.profiles[name] then return false, L["esiste gia' un profilo con questo nome"] end
    self.sv.profiles[name] = Badb.CopyTable(src)
    Events:Fire("BADB_PROFILES_UPDATED")
    return true, name
end

-- Profilo nuovo con i soli valori predefiniti (non viene attivato).
function DB:NewProfile(name)
    local n, err = DB.NormalizeName(name)
    if not n then return false, err end
    if self.sv.profiles[n] then return false, L["esiste gia' un profilo con questo nome"] end
    self.sv.profiles[n] = Badb.MergeDefaults({}, self.defaults)
    Events:Fire("BADB_PROFILES_UPDATED")
    return true, n
end

-- Rinomina mantenendo la stessa tabella (nessuna copia) e riallineando personaggi e spec.
function DB:RenameProfile(old, new)
    local sv = self.sv
    if not sv.profiles[old] then return false, L["profilo inesistente"] end
    local name, err = DB.NormalizeName(new)
    if not name then return false, err end
    if name == old then return false, L["il nome e' uguale a quello attuale"] end
    if sv.profiles[name] then return false, L["esiste gia' un profilo con questo nome"] end
    sv.profiles[name], sv.profiles[old] = sv.profiles[old], nil
    forEachReference(sv, function(t, k, v) if v == old then t[k] = name end end)
    if self.profileName == old then self.profileName = name end
    Events:Fire("BADB_PROFILES_UPDATED")
    return true, name
end

-- Elimina e pulisce ogni riferimento: un'assegnazione per spec rimasta orfana ricreerebbe
-- un profilo vuoto con lo stesso nome al successivo cambio di specializzazione.
function DB:DeleteProfile(name)
    if name == self.profileName then return false, L["non puoi eliminare il profilo attivo"] end
    if not self.sv.profiles[name] then return false, L["profilo inesistente"] end
    self.sv.profiles[name] = nil
    forEachReference(self.sv, function(t, k, v) if v == name then t[k] = nil end end)
    Events:Fire("BADB_PROFILES_UPDATED")
    return true
end

-- Personaggi ("Nome - Reame") che usano il profilo.
function DB:GetProfileUsers(name)
    local users = {}
    for k, v in pairs(self.sv.profileKeys) do if v == name then users[#users + 1] = k end end
    table.sort(users)
    return users
end

function DB:ResetProfile()
    wipe(self.profile)
    Badb.MergeDefaults(self.profile, self.defaults)
    Events:Fire("BADB_PROFILE_CHANGED", self.profileName)
end

-- Accesso tipizzato alle opzioni di un modulo
function DB:Get(moduleName, path)
    return Badb.GetPath(self.profile.modules[moduleName], path)
end

function DB:Set(moduleName, path, value)
    Badb.SetPath(self.profile.modules[moduleName], path, value)
    Events:Fire("BADB_OPTION_CHANGED", moduleName, path, value)
end

-- Import/export
function DB:ExportProfile(name)
    local p = self.sv.profiles[name or self.profileName]
    return Badb.Serializer:Export("profile", p)
end

-- Un profilo importato deve avere la forma attesa: tabelle per modules/frames, ogni voce una tabella.
local function sanitizeProfile(data)
    if type(data) ~= "table" then return nil, L["contenuto del profilo non valido"] end
    for _, key in ipairs({ "modules", "frames" }) do
        if data[key] ~= nil and type(data[key]) ~= "table" then return nil, L["campo '"] .. key .. L["' non valido"] end
        for k, v in pairs(data[key] or {}) do
            if type(k) ~= "string" or type(v) ~= "table" then data[key][k] = nil end
        end
    end
    return data
end

function DB:ImportProfile(str, newName)
    local data, err = Badb.Serializer:Import(str, "profile")
    if not data then return false, err end
    data, err = sanitizeProfile(data)
    if not data then return false, err end
    local name, nerr = DB.NormalizeName(newName)
    if not name then return false, nerr end
    if self.sv.profiles[name] then return false, L["esiste gia' un profilo con questo nome"] end
    self.sv.profiles[name] = Badb.MergeDefaults(data, self.defaults)
    Events:Fire("BADB_PROFILES_UPDATED")
    return true, name
end

-- Sostituisce il contenuto del profilo attivo (la UI chiede conferma prima).
function DB:ImportIntoActive(str)
    local data, err = Badb.Serializer:Import(str, "profile")
    if not data then return false, err end
    data, err = sanitizeProfile(data)
    if not data then return false, err end
    wipe(self.profile)
    Badb.CopyTable(data, self.profile)
    Badb.MergeDefaults(self.profile, self.defaults)
    Events:Fire("BADB_PROFILE_CHANGED", self.profileName)
    return true
end

-- Export/import delle sole opzioni di un modulo: tipo "module:<Nome>".
function DB:ExportModule(moduleName, profileName)
    local p = self.sv.profiles[profileName or self.profileName]
    local m = p and p.modules and p.modules[moduleName]
    if type(m) ~= "table" then return nil, L["modulo inesistente: "] .. tostring(moduleName) end
    return Badb.Serializer:Export("module:" .. moduleName, m)
end

function DB:ImportModule(str)
    local data, payload = Badb.Serializer:Import(str)
    if not data then return false, payload end
    local name = type(payload.kind) == "string" and payload.kind:match("^module:(.+)$")
    if not name then return false, L["la stringa non contiene le opzioni di un modulo"] end
    if not self.defaults.modules[name] then return false, L["modulo sconosciuto: "] .. name end
    if type(data) ~= "table" then return false, L["contenuto del modulo non valido"] end
    self.profile.modules[name] = Badb.MergeDefaults(data, self.defaults.modules[name])
    Events:Fire("BADB_PROFILE_CHANGED", self.profileName)
    return true, name
end

-- Analizza una stringa senza applicare nulla (anteprima di import).
-- -> { kind, addon, modules = {installati}, unknown = {non installati}, frames = n, hasLayout } | nil, errore
function DB:PreviewImport(str)
    local data, payload = Badb.Serializer:Import(str)
    if not data then return nil, payload end
    local info = { kind = payload.kind, addon = payload.addon, modules = {}, unknown = {}, frames = 0, hasLayout = false }
    if payload.kind == "profile" then
        if type(data) ~= "table" then return nil, L["contenuto del profilo non valido"] end
        for name, v in pairs(type(data.modules) == "table" and data.modules or {}) do
            if type(name) == "string" and type(v) == "table" then
                local list = self.defaults.modules[name] and info.modules or info.unknown
                list[#list + 1] = name
            end
        end
        for _, v in pairs(type(data.frames) == "table" and data.frames or {}) do
            if type(v) == "table" then info.frames = info.frames + 1 end
        end
        local em = type(data.modules) == "table" and data.modules.EditModeBridge
        info.hasLayout = type(em) == "table" and type(em.layoutString) == "string" or false
        table.sort(info.modules); table.sort(info.unknown)
    elseif type(payload.kind) == "string" and payload.kind:match("^module:") then
        local name = payload.kind:match("^module:(.+)$")
        local list = self.defaults.modules[name] and info.modules or info.unknown
        list[1] = name
    else
        return nil, L["tipo di stringa non supportato: "] .. tostring(payload.kind)
    end
    return info
end

-- Profilo per specializzazione (se il client supporta il dual spec)
function DB:SetSpecProfile(specIndex, profileName)
    self.sv.specProfiles[self.char] = self.sv.specProfiles[self.char] or {}
    self.sv.specProfiles[self.char][specIndex] = profileName
end

function DB:GetSpecProfile(specIndex)
    local map = self.sv.specProfiles[self.char]
    return map and map[specIndex]
end

local function currentSpec()
    -- PlayerInfo (caricato dopo) risolve dual spec Forever / spec Mainline in modo difensivo.
    if Badb.Player then return Badb.Player:GetTalentGroup() end
    if GetActiveTalentGroup then return GetActiveTalentGroup() end
    if GetSpecialization then return GetSpecialization() end
end

local function onSpecChanged()
    local map = DB.sv and DB.sv.specProfiles[DB.char]
    local target = map and map[currentSpec()]
    -- Un profilo eliminato nel frattempo (anche da un altro personaggio) non va ricreato vuoto.
    if target and not DB.sv.profiles[target] then
        map[currentSpec()] = nil
        Logger:Warn(L["Il profilo '%s' associato alla specializzazione non esiste piu'"], tostring(target))
        return
    end
    if target and target ~= DB.profileName then
        Events:RunOutOfCombat("specProfile", function() DB:SetProfile(target) end)
    end
end
-- Si registrano entrambi: l'evento non presente sul client viene scartato da Events:On (pcall su RegisterEvent).
Events:On(DB, "ACTIVE_TALENT_GROUP_CHANGED", onSpecChanged)
Events:On(DB, "PLAYER_SPECIALIZATION_CHANGED", onSpecChanged)
