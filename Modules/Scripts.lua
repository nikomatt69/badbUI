-- BadbUI - Scripts: motore di script Lua integrato. Un solo addon, scriptabile.
--
-- Uno script e' un record del profilo: { code, trigger, event, interval, enabled, data, ... }.
--   trigger  manual | login | event | combatStart | combatEnd | timer
--   Il codice gira in un ambiente isolato (le variabili globali create dallo script restano allo script)
--   che vede tutto _G meno le funzioni pericolose (DENY) e aggiunge:
--     Badb                tutta l'API di BadbUI (Modules, Theme, FrameManager, Events, ...)
--     script.name         nome dello script
--     script.on(ev, fn)   ascolta un evento di gioco (isolato con pcall, rimosso allo stop)
--     script.after(s, fn) / script.every(s, fn)   timer (max 5 attivi per script)
--     script.data         tabella salvata nel profilo: sopravvive a /reload
--     script.log(...) / print(...)   messaggi in chat con il nome dello script
--     script.stop()       ferma lo script
--   Con trigger event/combat/timer il codice e' richiamato a ogni occorrenza, con gli argomenti
--   dell'evento in `...`. Con login/manual gira una volta e puo' registrare i suoi handler con script.on.
--
-- Sicurezza (leggi docs/scripts.md): gli script sono CODICE DELL'UTENTE con i suoi stessi permessi.
-- La sandbox evita errori e usi accidentali, non e' un confine di sicurezza contro codice ostile.
-- Per questo gli script importati partono SEMPRE disattivati. Dopo 5 errori consecutivi uno script
-- si disattiva da solo. Il client non permette di limitare il tempo di esecuzione: un ciclo infinito
-- blocca il gioco (come qualunque addon).
local _, ns = ...
local Badb = ns.Badb
local Events, Logger, Modules = Badb.Events, Badb.Logger, Badb.Modules

local MAX_NAME, MAX_CODE, MAX_SCRIPTS, MAX_TICKERS, MAX_LISTENERS, AUTO_DISABLE = 40, 60000, 100, 5, 20, 5
local TRIGGERS = { "manual", "login", "event", "combatStart", "combatEnd", "timer" }
local TRIGGER_OK = {}
for _, t in ipairs(TRIGGERS) do TRIGGER_OK[t] = true end
local TRIGGER_CHOICES = {
    { value = "manual", label = "Solo manuale" }, { value = "login", label = "All'avvio / dopo /reload" },
    { value = "event", label = "A ogni evento di gioco" }, { value = "combatStart", label = "Entrando in combattimento" },
    { value = "combatEnd", label = "Uscendo dal combattimento" }, { value = "timer", label = "Ogni N secondi" },
}

-- Funzioni che uno script non deve poter chiamare: aggirano la sandbox o agiscono a nome del giocatore.
local DENY = {
    loadstring = true, load = true, dofile = true, loadfile = true, setfenv = true, getfenv = true, RunScript = true,
    SendChatMessage = true, SendMail = true, DeleteCursorItem = true, BuyMerchantItem = true, SellCursorItem = true,
    Logout = true, Quit = true, ForceQuit = true, AcceptTrade = true, AcceptGuild = true, DeclineGuild = true,
    BadbUIDB = true,
}

local M = Modules:New("Scripts", {
    title = "Script",
    category = "Interfaccia",
    description = "Script Lua salvati nel profilo, con trigger (avvio, evento, combattimento, timer) e API di BadbUI.",
    defaults = { enabled = true, scripts = {} },
    options = {
        { type = "execute", label = "Apri l'editor di script", func = function() if Badb.ScriptEditor then Badb.ScriptEditor:Open() end end,
          tooltip = "Come /badb script edit." },
    },
    page = { title = "Script", order = 90, category = "Interfaccia", keywords = { "script", "lua", "macro", "automazione" } },
    commands = {
        script = { help = "script list|edit|run|stop|enable|disable|delete|export|import <nome|stringa>", fn = function(a) M:Command(a) end },
        lua = { help = "lua <codice> - esegue una riga di Lua nella sandbox degli script", fn = function(a) M:RunSnippet(a) end },
    },
})
Badb.Scripts = M
M.TRIGGER_CHOICES, M.DENY = TRIGGER_CHOICES, DENY
M.running = {}

---------------------------------------------------------------------------
-- Archivio (nel profilo, ripulito se corrotto)
---------------------------------------------------------------------------

local function store()
    local t = M:Get("scripts")
    if type(t) ~= "table" then M:Set("scripts", {}); t = M:Get("scripts") end
    return t
end

local function validName(name)
    return type(name) == "string" and #name >= 1 and #name <= MAX_NAME and name:match("^[%w _%-]+$") ~= nil
        and name:match("^%s") == nil and name:match("%s$") == nil
end

local function clampInterval(v)
    if type(v) ~= "number" or v ~= v then return 5 end
    return math.max(0.5, math.min(3600, v))
end

-- Riporta il record a una forma valida; ritorna nil se irrecuperabile.
local function sanitize(rec)
    if type(rec) ~= "table" or type(rec.code) ~= "string" or #rec.code > MAX_CODE then return nil end
    if not TRIGGER_OK[rec.trigger] then rec.trigger = "manual" end
    if type(rec.event) ~= "string" or not rec.event:match("^[A-Z0-9_]+$") then rec.event = "PLAYER_ENTERING_WORLD" end
    rec.interval = clampInterval(rec.interval)
    rec.enabled = rec.enabled and true or false
    if type(rec.data) ~= "table" then rec.data = {} end
    if type(rec.errors) ~= "number" then rec.errors = 0 end
    if type(rec.runs) ~= "number" then rec.runs = 0 end
    return rec
end

function M:List()
    local out = {}
    for name, rec in pairs(store()) do
        if validName(name) and sanitize(rec) then
            out[#out + 1] = { name = name, trigger = rec.trigger, enabled = rec.enabled, imported = rec.imported or false,
                              running = self.running[name] ~= nil, lastError = rec.lastError, runs = rec.runs }
        end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

function M:Record(name)
    local rec = validName(name) and store()[name]
    return rec and sanitize(rec) or nil
end

---------------------------------------------------------------------------
-- Compilazione e ambiente
---------------------------------------------------------------------------

function M:Compile(code, name)
    if type(code) ~= "string" then return nil, "codice non valido" end
    if #code > MAX_CODE then return nil, "codice troppo lungo (max " .. MAX_CODE .. " caratteri)" end
    if type(loadstring) ~= "function" then return nil, "questo client non permette di eseguire codice dinamico" end
    local fn, err = loadstring(code, "=BadbScript:" .. tostring(name or "?"))
    if not fn then return nil, err end
    return fn
end

local function say(name, text)
    local msg = "|cff3fa7ff[script " .. name .. "]|r " .. text
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage(msg) end
end

local function joinArgs(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    return table.concat(parts, " ")
end

local function recordError(name, err)
    local rec = store()[name]
    if not rec then return end
    rec.lastError = tostring(err)
    rec.errors = (rec.errors or 0) + 1
    Logger:Error("script %s: %s", name, tostring(err))
    if rec.errors >= AUTO_DISABLE then
        rec.enabled = false
        M:Stop(name)
        Logger:Warn("script %s disattivato dopo %d errori consecutivi", name, AUTO_DISABLE)
    end
end

local function buildEnv(name, run, rec)
    local env = {}
    local api = { name = name, data = rec and rec.data or {} }
    function api.on(event, fn)
        if type(event) ~= "string" or not event:match("^[A-Z0-9_]+$") or type(fn) ~= "function" then return false end
        if run.listeners >= MAX_LISTENERS then return false end
        run.listeners = run.listeners + 1
        Events:On(run.owner, event, function(ev, ...)
            local ok, err = pcall(fn, ev, ...)
            if not ok then recordError(name, err) end
        end)
        return true
    end
    local function timer(sec, fn, repeating)
        if type(fn) ~= "function" or type(sec) ~= "number" or sec ~= sec or not (C_Timer and C_Timer.After) then return false end
        local safe = function() local ok, err = pcall(fn); if not ok then recordError(name, err) end end
        sec = math.max(0.1, sec)
        if repeating then
            if #run.tickers >= MAX_TICKERS or not C_Timer.NewTicker then return false end
            local tk = C_Timer.NewTicker(sec, safe)
            run.tickers[#run.tickers + 1] = tk or false
        else
            C_Timer.After(sec, function() if M.running[name] == run then safe() end end)
        end
        return true
    end
    function api.after(sec, fn) return timer(sec, fn, false) end
    function api.every(sec, fn) return timer(sec, fn, true) end
    function api.log(...) say(name, joinArgs(...)) end
    function api.stop() M:Stop(name) end
    env.script, env.Badb, env.print = api, Badb, function(...) say(name, joinArgs(...)) end
    env._G = env
    return setmetatable(env, { __index = function(_, k) if DENY[k] then return nil end return _G[k] end })
end

---------------------------------------------------------------------------
-- Ciclo di vita
---------------------------------------------------------------------------

function M:Stop(name)
    local run = self.running[name]
    if not run then return false end
    self.running[name] = nil
    Events:OffAll(run.owner)
    for _, tk in ipairs(run.tickers) do if tk and tk.Cancel then pcall(tk.Cancel, tk) end end
    return true
end

function M:StopAll()
    local names = {}
    for name in pairs(self.running) do names[#names + 1] = name end
    for _, name in ipairs(names) do self:Stop(name) end
end

local function invoke(name, run, ...)
    if M.running[name] ~= run then return end
    local ok, err = pcall(run.fn, ...)
    local rec = store()[name]
    if ok then
        if rec then rec.runs = (rec.runs or 0) + 1; rec.errors = 0; rec.lastError = nil end
    else
        recordError(name, err)
    end
    return ok, err
end

-- Prepara l'esecuzione (compila, crea ambiente e trigger). `manual` = avvio esplicito dell'utente.
function M:Start(name, manual)
    local rec = self:Record(name)
    if not rec then return false, "script inesistente" end
    if not manual and not rec.enabled then return false, "disattivato" end
    local fn, err = self:Compile(rec.code, name)
    if not fn then
        rec.lastError = tostring(err)
        return false, err
    end
    self:Stop(name)
    local run = { owner = { name = "script:" .. name }, tickers = {}, listeners = 0 }
    run.fn = setfenv(fn, buildEnv(name, run, rec))
    self.running[name] = run
    local t = rec.trigger
    if t == "event" then
        Events:On(run.owner, rec.event, function(ev, ...) invoke(name, run, ev, ...) end)
    elseif t == "combatStart" then
        Events:On(run.owner, "PLAYER_REGEN_DISABLED", function(ev) invoke(name, run, ev) end)
    elseif t == "combatEnd" then
        Events:On(run.owner, "PLAYER_REGEN_ENABLED", function(ev) invoke(name, run, ev) end)
    elseif t == "timer" and C_Timer and C_Timer.NewTicker then
        local tk = C_Timer.NewTicker(rec.interval, function() invoke(name, run, "TIMER") end)
        run.tickers[#run.tickers + 1] = tk or false
    end
    if manual or t == "login" then invoke(name, run) end
    return true
end

function M:Run(name) return self:Start(name, true) end

-- Una riga di Lua nella stessa sandbox, senza salvarla.
function M:RunSnippet(code)
    code = tostring(code or "")
    if code:match("^%s*$") then return false, "nessun codice" end
    local fn, err = self:Compile(code, "lua")
    if not fn then Logger:Error("lua: %s", tostring(err)); return false, err end
    local run = { owner = { name = "script:lua" }, tickers = {}, listeners = 0 }
    setfenv(fn, buildEnv("lua", run, nil))
    local ok, res = pcall(fn)
    if not ok then Logger:Error("lua: %s", tostring(res)); return false, res end
    return true, res
end

function M:StartAll()
    for _, info in ipairs(self:List()) do
        if info.enabled and info.trigger ~= "manual" then self:Start(info.name) end
    end
end

---------------------------------------------------------------------------
-- Gestione
---------------------------------------------------------------------------

-- fields: code, trigger, event, interval, enabled. Crea o aggiorna; se e' in esecuzione la riavvia.
function M:Save(name, fields)
    if not validName(name) then return false, "nome non valido (1-" .. MAX_NAME .. " caratteri: lettere, numeri, spazio, - _)" end
    fields = type(fields) == "table" and fields or {}
    local scripts = store()
    local rec = scripts[name]
    if not rec then
        local n = 0
        for _ in pairs(scripts) do n = n + 1 end
        if n >= MAX_SCRIPTS then return false, "troppi script (max " .. MAX_SCRIPTS .. ")" end
        rec = { code = "", trigger = "manual", enabled = false, data = {} }
        scripts[name] = rec
    end
    if fields.code ~= nil then
        if type(fields.code) ~= "string" then return false, "codice non valido" end
        if #fields.code > MAX_CODE then return false, "codice troppo lungo (max " .. MAX_CODE .. ")" end
        rec.code = fields.code
    end
    for _, k in ipairs({ "trigger", "event", "interval", "enabled" }) do
        if fields[k] ~= nil then rec[k] = fields[k] end
    end
    if rec.trigger ~= nil and not TRIGGER_OK[rec.trigger] then return false, "trigger sconosciuto" end
    sanitize(rec)
    rec.errors, rec.lastError = 0, nil
    local wasRunning = self.running[name] ~= nil
    if wasRunning or (rec.enabled and rec.trigger ~= "manual" and self.enabled) then
        if rec.enabled then self:Start(name) else self:Stop(name) end
    end
    return true
end

function M:SetScriptEnabled(name, value)
    local rec = self:Record(name)
    if not rec then return false, "script inesistente" end
    rec.enabled = value and true or false
    rec.errors = 0
    if rec.enabled then
        if rec.trigger ~= "manual" then return self:Start(name) end
        return true
    end
    self:Stop(name)
    return true
end

function M:Delete(name)
    if not validName(name) or not store()[name] then return false, "script inesistente" end
    self:Stop(name)
    store()[name] = nil
    return true
end

function M:Export(name)
    local rec = self:Record(name)
    if not rec then return nil, "script inesistente" end
    return Badb.Serializer:Export("script", { name = name, code = rec.code, trigger = rec.trigger,
                                              event = rec.event, interval = rec.interval })
end

-- Gli script importati non partono mai da soli: l'utente deve leggerli e attivarli.
function M:Import(str)
    local d, err = Badb.Serializer:Import(tostring(str or ""), "script") -- ritorna i dati (o nil, errore)
    if not d then return nil, err end
    if type(d) ~= "table" or type(d.code) ~= "string" then return nil, "contenuto non valido" end
    local base = validName(d.name) and d.name or "Importato"
    local name, i = base, 2
    while store()[name] do name = string.sub(base, 1, MAX_NAME - 4) .. " " .. i; i = i + 1 end
    local ok, e2 = self:Save(name, { code = d.code, trigger = d.trigger, event = d.event, interval = d.interval, enabled = false })
    if not ok then return nil, e2 end
    store()[name].imported = true
    return name
end

---------------------------------------------------------------------------
-- Comandi slash
---------------------------------------------------------------------------

function M:Command(args)
    args = strtrim(args or "")
    local cmd, rest = args:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    local function out(fmt, ...) Logger:Info(fmt, ...) end
    if cmd == "" or cmd == "list" then
        local list = self:List()
        if #list == 0 then out("Nessuno script. /badb script edit per crearne uno.") end
        for _, s in ipairs(list) do
            out("%s [%s] %s%s%s", s.name, s.trigger, s.enabled and "attivo" or "spento", s.running and ", in esecuzione" or "",
                s.lastError and (", ultimo errore: " .. s.lastError) or "")
        end
    elseif cmd == "edit" or cmd == "new" then
        if Badb.ScriptEditor then Badb.ScriptEditor:Open(rest ~= "" and rest or nil) else Logger:Warn("Editor non disponibile") end
    elseif cmd == "run" then
        local ok, err = self:Run(rest); if not ok then Logger:Warn("%s", tostring(err)) end
    elseif cmd == "stop" then
        if not self:Stop(rest) then Logger:Warn("Non in esecuzione: %s", rest) end
    elseif cmd == "enable" or cmd == "disable" then
        local ok, err = self:SetScriptEnabled(rest, cmd == "enable"); if not ok then Logger:Warn("%s", tostring(err)) end
    elseif cmd == "delete" then
        local ok, err = self:Delete(rest); if not ok then Logger:Warn("%s", tostring(err)) end
    elseif cmd == "export" then
        local s, err = self:Export(rest)
        if s then
            out("Export di %s:", rest); out("%s", s)
        else Logger:Warn("%s", tostring(err)) end
    elseif cmd == "import" then
        local name, err = self:Import(rest)
        if name then out("Importato come '%s' (spento: leggilo e poi /badb script enable %s)", name, name)
        else Logger:Warn("Import fallito: %s", tostring(err)) end
    else
        Logger:Warn("Uso: /badb script list|edit|run|stop|enable|disable|delete|export|import")
    end
end

---------------------------------------------------------------------------
-- Ciclo di vita del modulo
---------------------------------------------------------------------------

function M:OnEnable()
    store() -- ripulisce / crea l'archivio
    self.worldReady = self.worldReady or false
    if self.worldReady then self:StartAll() end
    self:On("PLAYER_ENTERING_WORLD", function()
        if not M.worldReady then M.worldReady = true; M:StartAll() end
    end)
end

function M:OnProfileChanged()
    self:StopAll()
    if self.worldReady then self:StartAll() end
end

function M:OnDisable() self:StopAll() end
