-- BadbUI - Database e profili
-- Struttura di BadbUIDB:
--   schema        numero versione per le migrazioni
--   profiles      { [nome] = { modules = { [modulo] = {...} }, frames = { [frameKey] = {...} } } }
--   profileKeys   { ["Personaggio - Reame"] = nomeProfilo }
--   specProfiles  { ["Personaggio - Reame"] = { [specIndex] = nomeProfilo } } (dual spec)
--   global        impostazioni non legate al profilo
local _, ns = ...
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
            if not ok then Logger:Error("Migrazione %d fallita: %s", nextVer, err); return end
        end
        sv.schema = nextVer
        Logger:Info("Database aggiornato allo schema %d", nextVer)
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

function DB:CopyProfile(from, to)
    local src = self.sv.profiles[from]
    if not src then return false, "profilo inesistente" end
    self.sv.profiles[to] = Badb.CopyTable(src)
    return true
end

function DB:DeleteProfile(name)
    if name == self.profileName then return false, "non puoi eliminare il profilo attivo" end
    self.sv.profiles[name] = nil
    for k, v in pairs(self.sv.profileKeys) do
        if v == name then self.sv.profileKeys[k] = nil end
    end
    return true
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

function DB:ImportProfile(str, newName)
    local data, err = Badb.Serializer:Import(str, "profile")
    if not data then return false, err end
    if self.sv.profiles[newName] then return false, "esiste gia' un profilo con questo nome" end
    self.sv.profiles[newName] = Badb.MergeDefaults(data, self.defaults)
    return true
end

-- Profilo per specializzazione (se il client supporta il dual spec)
function DB:SetSpecProfile(specIndex, profileName)
    self.sv.specProfiles[self.char] = self.sv.specProfiles[self.char] or {}
    self.sv.specProfiles[self.char][specIndex] = profileName
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
    if target and target ~= DB.profileName then
        Events:RunOutOfCombat("specProfile", function() DB:SetProfile(target) end)
    end
end
-- Si registrano entrambi: l'evento non presente sul client viene scartato da Events:On (pcall su RegisterEvent).
Events:On(DB, "ACTIVE_TALENT_GROUP_CHANGED", onSpecChanged)
Events:On(DB, "PLAYER_SPECIALIZATION_CHANGED", onSpecChanged)
