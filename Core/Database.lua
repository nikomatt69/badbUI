-- AegisUI - Database e profili
-- Struttura di AegisUIDB:
--   schema        numero versione per le migrazioni
--   profiles      { [nome] = { modules = { [modulo] = {...} }, frames = { [frameKey] = {...} } } }
--   profileKeys   { ["Personaggio - Reame"] = nomeProfilo }
--   specProfiles  { ["Personaggio - Reame"] = { [specIndex] = nomeProfilo } } (dual spec)
--   global        impostazioni non legate al profilo
local _, ns = ...
local Aegis = ns.Aegis
local Events, Logger = Aegis.Events, Aegis.Logger

local DB = { defaults = { modules = {}, frames = {} }, migrations = {} }
Aegis.DB = DB

local SCHEMA = 1

local function charKey()
    return (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?")
end

-- Ogni modulo registra i propri default; vengono fusi nel profilo attivo.
function DB:RegisterDefaults(moduleName, defaults)
    self.defaults.modules[moduleName] = defaults
    if self.profile then
        self.profile.modules[moduleName] = self.profile.modules[moduleName] or {}
        Aegis.MergeDefaults(self.profile.modules[moduleName], defaults)
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
    AegisUIDB = AegisUIDB or {}
    local sv = AegisUIDB
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
    Aegis.MergeDefaults(p, self.defaults)
    sv.profileKeys[self.char] = name
    self.profileName, self.profile = name, p
    if not silent then Events:Fire("AEGIS_PROFILE_CHANGED", name) end
end

function DB:CopyProfile(from, to)
    local src = self.sv.profiles[from]
    if not src then return false, "profilo inesistente" end
    self.sv.profiles[to] = Aegis.CopyTable(src)
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
    Aegis.MergeDefaults(self.profile, self.defaults)
    Events:Fire("AEGIS_PROFILE_CHANGED", self.profileName)
end

-- Accesso tipizzato alle opzioni di un modulo
function DB:Get(moduleName, path)
    return Aegis.GetPath(self.profile.modules[moduleName], path)
end

function DB:Set(moduleName, path, value)
    Aegis.SetPath(self.profile.modules[moduleName], path, value)
    Events:Fire("AEGIS_OPTION_CHANGED", moduleName, path, value)
end

-- Import/export
function DB:ExportProfile(name)
    local p = self.sv.profiles[name or self.profileName]
    return Aegis.Serializer:Export("profile", p)
end

function DB:ImportProfile(str, newName)
    local data, err = Aegis.Serializer:Import(str, "profile")
    if not data then return false, err end
    if self.sv.profiles[newName] then return false, "esiste gia' un profilo con questo nome" end
    self.sv.profiles[newName] = Aegis.MergeDefaults(data, self.defaults)
    return true
end

-- Profilo per specializzazione (se il client supporta il dual spec)
function DB:SetSpecProfile(specIndex, profileName)
    self.sv.specProfiles[self.char] = self.sv.specProfiles[self.char] or {}
    self.sv.specProfiles[self.char][specIndex] = profileName
end

local function currentSpec()
    if GetSpecialization then return GetSpecialization() end
    if GetActiveTalentGroup then return GetActiveTalentGroup() end
end

local specEvent = GetSpecialization and "PLAYER_SPECIALIZATION_CHANGED" or "ACTIVE_TALENT_GROUP_CHANGED"
Events:On(DB, specEvent, function()
    local map = DB.sv and DB.sv.specProfiles[DB.char]
    local target = map and map[currentSpec()]
    if target and target ~= DB.profileName then
        Events:RunOutOfCombat("specProfile", function() DB:SetProfile(target) end)
    end
end)
