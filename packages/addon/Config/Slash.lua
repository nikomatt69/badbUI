-- BadbUI - Router dei comandi slash: /badb e /bui
-- Comandi base (config, unlock, profile, export, enable, disable, setup, undo, debug, log, help) +
-- sottocomandi dei moduli (Badb.Modules.list[*].commands = { nome = { help, fn } }) scoperti a ogni invocazione +
-- comandi registrati con Slash:Register. Comando sconosciuto => suggerimento "intendevi X?".
local _, ns = ...
local Badb = ns.Badb
local DB, FM, Modules, Logger = Badb.DB, Badb.FrameManager, Badb.Modules, Badb.Logger

local Slash = { registered = {}, registeredOrder = {}, warned = {}, lastCollisions = {} }
Badb.Slash = Slash

---------------------------------------------------------------------------
-- Comandi base (comportamento invariato rispetto alla versione precedente)
---------------------------------------------------------------------------
local BASE = {}
local baseOrder = {}
local function base(name, help, fn)
    BASE[name] = { name = name, help = help, fn = fn, source = "base" }
    baseOrder[#baseOrder + 1] = name
end

local function openConfig(arg)
    arg = strtrim(arg or "")
    Badb.ConfigUI:Open(arg ~= "" and arg or nil)
end

-- Wizard e Presets sono moduli di altri agenti: guardia di esistenza (nessuna dipendenza hard).
local function toggleWizard()
    local w = Badb.Wizard
    if w and w.Toggle then w:Toggle() else Logger:Warn("Configurazione guidata non disponibile") end
end
local function undoPreset()
    local p = Badb.Presets
    if p and p.Undo then p:Undo() else Logger:Warn("Preset non disponibili") end
end

base("", "apre la finestra di configurazione", function() openConfig("") end)
base("config", "config [pagina|modulo] - apre la configurazione", openConfig)
base("unlock", "sblocca/blocca i frame per spostarli", function() FM:SetUnlocked(not FM.unlocked) end)
base("profile", "profile [nome] - elenca o cambia profilo", function(name)
    if name == "" then
        Logger:Info("Profili: %s (attivo: %s)", table.concat(DB:ListProfiles(), ", "), DB:GetProfileName())
    else
        DB:SetProfile(name)
    end
end)
base("export", "esporta il profilo attivo", function() Badb.ConfigUI.TextBox("Esporta profilo", DB:ExportProfile()) end)
base("enable", "enable <modulo> - attiva un modulo", function(name) Modules:SetEnabled(name, true) end)
base("disable", "disable <modulo> - disattiva un modulo", function(name) Modules:SetEnabled(name, false) end)
base("setup", "configurazione guidata", toggleWizard)
base("wizard", "alias di setup", toggleWizard)
base("undo", "annulla l'ultimo preset applicato", undoPreset)
base("debug", "attiva/disattiva i messaggi di debug", function()
    Logger.level = Logger.level == 1 and 2 or 1
    Logger:Info("Debug %s", Logger.level == 1 and "attivo" or "disattivo")
end)
base("log", "mostra il log", function()
    Badb.ConfigUI.TextBox("Log BadbUI", table.concat(Logger.buffer, "\n"))
end)
base("help", "elenco dei comandi", function() Slash:ShowHelp() end)

---------------------------------------------------------------------------
-- Logica pura
---------------------------------------------------------------------------
-- Distanza di Levenshtein (per i suggerimenti).
function Slash.EditDistance(a, b)
    a, b = tostring(a or ""), tostring(b or "")
    local la, lb = #a, #b
    if la == 0 then return lb end
    if lb == 0 then return la end
    local prev, cur = {}, {}
    for j = 0, lb do prev[j] = j end
    for i = 1, la do
        cur[0] = i
        local ca = a:byte(i)
        for j = 1, lb do
            local cost = (ca == b:byte(j)) and 0 or 1
            cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        end
        prev, cur = cur, prev
    end
    return prev[lb]
end

local function validName(name)
    return type(name) == "string" and name ~= "" and name:match("^[%w_%-]+$") ~= nil
end

local function warnOnce(key, fmt, ...)
    if Slash.warned[key] then return end
    Slash.warned[key] = true
    Logger:Warn(fmt, ...)
end

-- Costruisce la mappa dei comandi disponibili ADESSO. Ritorna map[nome] = entry, list (ordinata), collisioni.
-- Priorita': base > registrati > moduli (nell'ordine di caricamento). Chi arriva dopo con lo stesso nome perde (warning).
function Slash:Resolve()
    local map, list, collisions = {}, {}, {}
    local function add(entry)
        local prev = map[entry.name]
        if prev then
            local winner, loser = tostring(prev.module or prev.source), tostring(entry.module or entry.source)
            collisions[#collisions + 1] = { name = entry.name, winner = winner, loser = loser }
            warnOnce("c:" .. entry.name .. ":" .. loser, "Comando '%s' duplicato: vince %s, ignorato %s", entry.name, winner, loser)
            return
        end
        map[entry.name] = entry
        list[#list + 1] = entry
    end
    for _, name in ipairs(baseOrder) do add(BASE[name]) end
    for _, name in ipairs(self.registeredOrder) do
        local r = self.registered[name]
        if r then add({ name = name, help = r.help, fn = r.fn, source = "registered" }) end
    end
    local order, mlist = Modules.order or {}, Modules.list or {}
    for _, modName in ipairs(order) do
        local m = mlist[modName]
        local cmds = type(m) == "table" and m.commands
        if type(cmds) == "table" then
            local names = {}
            for name in pairs(cmds) do names[#names + 1] = tostring(name) end
            table.sort(names)
            for _, name in ipairs(names) do
                local c = cmds[name]
                if validName(name) and type(c) == "table" and type(c.fn) == "function" then
                    add({ name = name:lower(), help = type(c.help) == "string" and c.help or "", fn = c.fn,
                        source = "module", module = modName, enabled = m.enabled and true or false })
                else
                    warnOnce("i:" .. modName .. ":" .. name, "Comando '%s' del modulo %s non valido (serve { help, fn })", name, modName)
                end
            end
        end
    end
    self.lastCollisions = collisions
    return map, list, collisions
end

-- Elenco dei comandi disponibili: { {name, help, source, module}, ... } (il comando vuoto e' escluso).
function Slash:List()
    local _, list = self:Resolve()
    local out = {}
    for _, e in ipairs(list) do
        if e.name ~= "" then out[#out + 1] = { name = e.name, help = e.help, source = e.source, module = e.module } end
    end
    return out
end

-- Suggerimento per un comando sconosciuto: il piu' vicino per distanza di edit (o per prefisso), oppure nil.
function Slash:Suggest(cmd, map)
    cmd = tostring(cmd or ""):lower()
    if cmd == "" then return nil end
    if not map then map = self:Resolve() end
    local names = {}
    for name in pairs(map) do if name ~= "" then names[#names + 1] = name end end
    table.sort(names)
    local threshold = #cmd >= 4 and 2 or 1
    local best, bestD
    for _, name in ipairs(names) do
        local d = Slash.EditDistance(cmd, name)
        if #cmd >= 2 and name:sub(1, #cmd) == cmd then d = 0 end -- prefisso: "prof" -> profile
        if d <= threshold and (not bestD or d < bestD) then best, bestD = name, d end
    end
    return best
end

-- Registra un comando non di modulo. Ritorna ok, err.
function Slash:Register(name, fn, help)
    if not validName(name) then return false, "nome non valido" end
    if type(fn) ~= "function" then return false, "fn mancante" end
    name = name:lower()
    if BASE[name] then return false, "nome riservato ai comandi base" end
    if not self.registered[name] then self.registeredOrder[#self.registeredOrder + 1] = name end
    self.registered[name] = { fn = fn, help = type(help) == "string" and help or "" }
    return true
end

function Slash:Unregister(name)
    name = tostring(name or ""):lower()
    if not self.registered[name] then return false end
    self.registered[name] = nil
    for i, n in ipairs(self.registeredOrder) do if n == name then table.remove(self.registeredOrder, i); break end end
    return true
end

function Slash:ShowHelp()
    local _, list = self:Resolve()
    Logger:Info("Comandi /badb (alias /bui):")
    for _, e in ipairs(list) do
        if e.name ~= "" then
            local tag = (e.source == "module" and not e.enabled) and " |cff888888(modulo disattivato)|r" or ""
            Logger:Info("  /badb %s%s - %s", e.name, tag, e.help ~= "" and e.help or "-")
        end
    end
end

-- Esegue una riga di comando. Ritorna: true | false, "unknown", suggerimento | false, "error", messaggio.
function Slash:Dispatch(msg)
    local cmd, rest = strtrim(tostring(msg or "")):match("^(%S*)%s*(.-)$")
    cmd, rest = (cmd or ""):lower(), rest or ""
    local map = self:Resolve()
    local entry = map[cmd]
    if not entry then
        local suggestion = self:Suggest(cmd, map)
        if suggestion then
            Logger:Info("Comando sconosciuto '%s'. Intendevi '%s'? (/badb help)", cmd, suggestion)
        else
            Logger:Warn("Comando sconosciuto '%s'.", cmd)
            self:ShowHelp()
        end
        return false, "unknown", suggestion
    end
    local ok, err = pcall(entry.fn, rest)
    if not ok then
        Logger:Error("Comando '%s': %s", entry.name, tostring(err))
        return false, "error", tostring(err)
    end
    return true
end

SLASH_BADBUI1, SLASH_BADBUI2 = "/badb", "/bui"
SlashCmdList.BADBUI = function(msg) Slash:Dispatch(msg) end
