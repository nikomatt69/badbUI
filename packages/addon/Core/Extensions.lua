-- BadbUI - API pubblica di estensione (BadbUI.API).
-- Un addon esterno (o un file aggiuntivo) registra un plugin: diventa un modulo BadbUI a tutti gli effetti,
-- con default nel profilo, pagina nella finestra /badb, sottocomandi, guide e ciclo di vita isolato.
-- Contratto stabile e versionato: API.version cambia solo per rotture incompatibili. Vedi docs/extending.md.
--
--   BadbUI.API:RegisterPlugin({
--       id = "MioPlugin", title = "Il mio plugin", version = "1.0", author = "Io", apiVersion = 1,
--       module = { defaults = { enabled = true }, options = { ... }, page = { ... }, commands = { ... },
--                  OnEnable = function(self) end, OnDisable = function(self) end },
--       guides = { id = "mio", title = "Guide", entries = { ... } },   -- opzionale (Badb.Guides:Register)
--   })
--
-- Nessuna funzione lancia errori verso il chiamante: ritorna `valore` oppure `nil, errore`.
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local Events, Logger, Modules = Badb.Events, Badb.Logger, Badb.Modules

local API = { version = 1, plugins = {}, order = {} }
Badb.API = API

local MAX_PLUGINS = 64
local MODULE_PREFIX = "Plugin_"
-- Campi del modulo che un plugin non puo' impostare: appartengono al registro dei moduli.
local RESERVED = { name = true, enabled = true }

local started = false -- true dopo PLAYER_LOGIN: i plugin tardivi vanno inizializzati e abilitati a mano

local function validId(id)
    return type(id) == "string" and #id >= 2 and #id <= 32 and id:match("^[%a][%w_]*$") ~= nil
end

local function text(v, fallback, max)
    if type(v) ~= "string" or v == "" then return fallback end
    return v:sub(1, max or 80)
end

function API:GetPlugin(id) return self.plugins[id] end

-- Elenco in ordine di registrazione: { {id, title, version, author, description, module, enabled}, ... }
function API:ListPlugins()
    local out = {}
    for _, id in ipairs(self.order) do
        local p = self.plugins[id]
        local m = p.module and Modules:Get(p.module)
        out[#out + 1] = { id = p.id, title = p.title, version = p.version, author = p.author,
                          description = p.description, module = p.module, enabled = m and m.enabled or false }
    end
    return out
end

function API:RegisterPlugin(def)
    if type(def) ~= "table" then return nil, L["il plugin deve essere una tabella"] end
    if not validId(def.id) then return nil, L["id del plugin non valido (2-32 caratteri: lettere, numeri, _)"] end
    if self.plugins[def.id] then return nil, L["plugin gia' registrato: "] .. def.id end
    if #self.order >= MAX_PLUGINS then return nil, L["troppi plugin registrati"] end
    local wanted = def.apiVersion
    if wanted ~= nil and (type(wanted) ~= "number" or wanted > self.version or wanted < 1) then
        return nil, string.format(L["il plugin richiede l'API %s, disponibile la %d"], tostring(wanted), self.version)
    end
    if def.module ~= nil and type(def.module) ~= "table" then return nil, L["module deve essere una tabella"] end

    local plugin = {
        id = def.id,
        title = text(def.title, def.id),
        version = text(def.version, "?", 24),
        author = text(def.author, "?", 48),
        description = text(def.description, "", 400),
    }

    if def.module then
        local name = MODULE_PREFIX .. def.id
        if Modules:Get(name) then return nil, L["plugin gia' registrato: "] .. def.id end
        local info = {}
        for k, v in pairs(def.module) do
            if not RESERVED[k] then info[k] = v end
        end
        info.title = text(info.title, plugin.title)
        info.description = text(info.description, plugin.description, 400)
        info.plugin = plugin.id
        if type(info.defaults) ~= "table" then info.defaults = {} end
        if type(info.dependencies) ~= "table" then info.dependencies = {} end
        local ok, m = pcall(Modules.New, Modules, name, info)
        if not ok then return nil, tostring(m) end
        plugin.module = name
        if Badb.DB.sv then
            -- Un addon dipendente può registrarsi tra ADDON_LOADED di BadbUI e PLAYER_LOGIN.
            if type(m.OnInitialize) == "function" then
                local okInit, err = pcall(m.OnInitialize, m)
                if not okInit then Logger:Error("%s:OnInitialize - %s", name, tostring(err)) end
            end
            if started and Badb.DB:Get(name, "enabled") then Modules:Enable(name) end
        end
    end

    if type(def.guides) == "table" and Badb.Guides and Badb.Guides.Register then
        local ok, err = pcall(Badb.Guides.Register, Badb.Guides, def.guides)
        if not ok then Logger:Warn(L["Guide del plugin %s non registrate: %s"], plugin.id, tostring(err)) end
    end

    self.plugins[plugin.id] = plugin
    self.order[#self.order + 1] = plugin.id
    Events:Fire("BADB_PLUGIN_REGISTERED", plugin.id)
    return plugin
end

-- Eventi del client e messaggi interni BADB_*: owner e' una tabella qualsiasi (di solito il plugin).
function API:On(owner, event, fn)
    if type(owner) ~= "table" or type(event) ~= "string" or type(fn) ~= "function" then
        return nil, L["uso: API:On(owner, evento, funzione)"]
    end
    Events:On(owner, event, fn) -- fn(evento, ...): il bus isola gia' gli errori di ogni gestore
    return true
end

function API:Off(owner, event)
    if type(owner) ~= "table" then return nil end
    if type(event) == "string" then Events:Off(owner, event) else Events:OffAll(owner) end
    return true
end

function API:GetModule(name) return type(name) == "string" and Modules:Get(name) or nil end

-- Sottocomando di /badb. Ritorna ok, err come Badb.Slash:Register.
function API:RegisterCommand(name, fn, help)
    local slash = Badb.Slash
    if not (slash and slash.Register) then return nil, L["router dei comandi non disponibile"] end
    return slash:Register(name, fn, help)
end

-- Traduzioni di un plugin: stesse regole di Badb.Localization (enUS e itIT).
function API:RegisterLocale(locale, translations)
    local ok, err = pcall(Badb.Localization.RegisterLocale, Badb.Localization, locale, translations)
    if not ok then return nil, tostring(err) end
    return true
end

-- Archivio dati voluminosi di un'area (inventari, prezzi, nodi, storico): BadbUIDB.data[area].
-- Vive fuori da profili e `global`, quindi NON entra in backup, export e cambio profilo.
-- Disponibile da OnInitialize in poi (prima ritorna nil). Chi lo usa versiona i dati e ne limita la dimensione.
function Badb.DB:GetStore(area)
    if type(area) ~= "string" or not area:match("^[%a][%w_]*$") then return nil end
    local sv = self.sv
    if type(sv) ~= "table" then return nil end
    if type(sv.data) ~= "table" then sv.data = {} end
    if type(sv.data[area]) ~= "table" then sv.data[area] = {} end
    return sv.data[area]
end
API.GetStore = function(_, area) return Badb.DB:GetStore(area) end

Events:On(API, "PLAYER_LOGIN", function() started = true end)
