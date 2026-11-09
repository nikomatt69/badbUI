-- BadbUI - Sistema moduli
-- Ogni funzionalita' e' un modulo isolato con ciclo di vita esplicito:
--   OnInitialize()  una volta, dopo il caricamento del DB
--   OnEnable()      quando il modulo viene attivato (anche a runtime)
--   OnDisable()     quando viene disattivato: deve ripristinare lo stato Blizzard
--   OnProfileChanged() dopo un cambio profilo
-- Dipendenze dichiarate: un modulo non si abilita se una dipendenza e' disattivata.
local ADDON_NAME, ns = ...
local Badb = ns.Badb
local Events, Logger, DB = Badb.Events, Badb.Logger, Badb.DB

local Modules = { list = {}, order = {} }
Badb.Modules = Modules

local ModuleProto = {}
ModuleProto.__index = ModuleProto

function ModuleProto:On(event, fn) Events:On(self, event, fn) end
function ModuleProto:Off(event) Events:Off(self, event) end
function ModuleProto:Get(path) return DB:Get(self.name, path) end
function ModuleProto:Set(path, value) DB:Set(self.name, path, value) end
function ModuleProto:IsEnabled() return self.enabled end
function ModuleProto:Debug(...) Logger:Debug("[" .. self.name .. "] " .. tostring((...)), select(2, ...)) end

--[[ Esempio:
local M = Badb.Modules:New("Hider", {
    title = "Nascondi elementi", category = "Interfaccia",
    defaults = { enabled = true, ... },
    dependencies = { "Layout" },
})
]]
function Modules:New(name, info)
    assert(not self.list[name], "Modulo duplicato: " .. name)
    local m = setmetatable(info or {}, ModuleProto)
    m.name = name
    m.title = m.title or name
    m.defaults = m.defaults or {}
    if m.defaults.enabled == nil then m.defaults.enabled = true end
    m.dependencies = m.dependencies or {}
    m.options = m.options or {} -- descrittori per la ConfigUI (vedi Config/Widgets.lua)
    self.list[name] = m
    self.order[#self.order + 1] = name
    DB:RegisterDefaults(name, m.defaults)
    return m
end

function Modules:Get(name) return self.list[name] end

local function safeCall(m, method, ...)
    if not m[method] then return true end
    local ok, err = pcall(m[method], m, ...)
    if not ok then Logger:Error("%s:%s - %s", m.name, method, err) end
    return ok
end

function Modules:Enable(name)
    local m = self.list[name]
    if not m or m.enabled then return end
    for _, dep in ipairs(m.dependencies) do
        local d = self.list[dep]
        if not d or not d.enabled then
            Logger:Warn("%s richiede %s, non attivo", name, dep)
            return
        end
    end
    if safeCall(m, "OnEnable") then
        m.enabled = true
        Events:Fire("BADB_MODULE_ENABLED", name)
    end
end

function Modules:Disable(name)
    local m = self.list[name]
    if not m or not m.enabled then return end
    -- Prima disattiva chi dipende da questo modulo
    for _, other in pairs(self.list) do
        for _, dep in ipairs(other.dependencies) do
            if dep == name then self:Disable(other.name) end
        end
    end
    safeCall(m, "OnDisable")
    Events:OffAll(m)
    m.enabled = false
    Events:Fire("BADB_MODULE_DISABLED", name)
end

function Modules:SetEnabled(name, value)
    DB:Set(name, "enabled", value and true or false)
    if value then self:Enable(name) else self:Disable(name) end
end

function Modules:ApplyAll()
    for _, name in ipairs(self.order) do
        local m = self.list[name]
        local want = DB:Get(name, "enabled")
        if want and not m.enabled then self:Enable(name)
        elseif not want and m.enabled then self:Disable(name)
        elseif m.enabled then safeCall(m, "OnProfileChanged") end
    end
end

-- Bootstrap: ADDON_LOADED -> DB + OnInitialize; PLAYER_LOGIN -> abilitazione moduli.
Events:On(Modules, "ADDON_LOADED", function(_, addon)
    if addon ~= ADDON_NAME then return end
    Events:Off(Modules, "ADDON_LOADED")
    DB:Initialize()
    for _, name in ipairs(Modules.order) do safeCall(Modules.list[name], "OnInitialize") end
end)

Events:On(Modules, "PLAYER_LOGIN", function()
    Modules:ApplyAll()
    Logger:Info("v%s caricato - profilo '%s'. Digita /badb", Badb.version, DB:GetProfileName())
end)

Events:On(Modules, "BADB_PROFILE_CHANGED", function()
    Events:RunOutOfCombat("applyModules", function() Modules:ApplyAll() end)
end)
