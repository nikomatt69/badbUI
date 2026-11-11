-- BadbUI - Pagine principali della finestra di configurazione (/badb):
--   Principale  azioni rapide + tutti i moduli (attiva/disattiva/apri opzioni) + script
--   Aspetto     tema, accento, trasparenza, scala della finestra
--   Addon       tutti gli addon installati: attiva/disattiva (serve /reload) e stato
-- Costruite con i descrittori di Badb.Widgets; la logica (righe, azioni) e' esposta in Badb.MainPages
-- per i test, senza UI.
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local UI, Modules, Logger = Badb.ConfigUI, Badb.Modules, Badb.Logger
local Theme = Badb.Theme

local MP = {}
Badb.MainPages = MP

local function esc(s) return (tostring(s or ""):gsub("|", "||")) end

---------------------------------------------------------------------------
-- Principale
---------------------------------------------------------------------------

local function closeThen(fn) return function() if UI.Close then UI:Close() end; fn() end end

function MP.quickActions()
    local A = {}
    local function add(text, label, fn, extra)
        local a = { text = text, actions = { { label = label, width = 80, func = fn, confirm = extra and extra.confirm, noRefresh = true } } }
        A[#A + 1] = a
    end
    add(L["Read the manual, explore all modules and find answers"], L["Help"], function()
        if Badb.Help then Badb.Help:Open("start") end
    end)
    add(L["Applica lo stile ElvUI a tutta l'interfaccia (tema, unit frame, barre, datatext)"], L["Applica"], function()
        local m = Modules:Get("ElvLook"); if m then m:ApplyElvStyle() end
    end, { confirm = L["Applicare lo stile ElvUI? Viene creato prima un backup."] })
    add(L["Sposta e ridimensiona i frame (trascina, frecce, Maiusc+rotella)"], L["Sblocca"], closeThen(function()
        Badb.FrameManager:SetUnlocked(not Badb.FrameManager.unlocked)
    end))
    add(L["Editor di script Lua (trigger, eventi, timer)"], L["Apri"], function()
        if Badb.ScriptEditor then Badb.ScriptEditor:Open() end
    end)
    add(L["Configurazione guidata (preset per classe e ruolo)"], L["Apri"], closeThen(function()
        if Badb.Wizard then Badb.Wizard:Open() end
    end))
    add(L["Controllo dei conflitti e degli errori"], L["Esegui"], function()
        local d = Badb.Diagnostics
        if d and d.commands and d.commands.doctor then d.commands.doctor.fn("run") end
    end)
    add(L["Backup del profilo attuale"], L["Crea"], function()
        local b = Badb.Backups
        if b and b.Create then
            local ok = b:Create(L["manuale"])
            if UI.Toast then UI:Toast(ok and L["Backup creato"] or L["Backup non riuscito"], ok and "ok" or "error") end
        end
    end)
    add(L["Ricarica l'interfaccia (/reload)"], L["Ricarica"], function() ReloadUI() end,
        { confirm = L["Ricaricare l'interfaccia ora?"] })
    return A
end

function MP.moduleRows()
    local rows = {}
    for _, name in ipairs(Modules.order or {}) do
        local m = Modules.list[name]
        if m then
            local on = m.enabled and true or false
            local acts = { { label = on and L["Spegni"] or L["Accendi"], width = 64, func = function() Modules:SetEnabled(name, not on) end } }
            if type(m.page) == "table" or (m.options and #m.options > 0) then
                acts[#acts + 1] = { label = L["Opzioni"], width = 64, noRefresh = true, func = function() UI:OpenPage(name) end }
            end
            rows[#rows + 1] = { text = esc(m.title or name), actions = acts,
                                detail = on and L["|cff5fd068attivo|r"] or L["|cff888888spento|r"] }
        end
    end
    return rows
end

function MP.scriptRows()
    local rows, S = {}, Badb.Scripts
    if not S then return rows end
    for _, s in ipairs(S:List()) do
        local state = s.lastError and L["|cffff6060errore|r"] or (s.running and L["|cff5fd068in esecuzione|r"])
            or (s.enabled and L["attivo"] or L["|cff888888spento|r"])
        rows[#rows + 1] = { text = esc(s.name), detail = state .. " - " .. s.trigger, actions = {
            { label = L["Modifica"], width = 64, noRefresh = true, func = function() if Badb.ScriptEditor then Badb.ScriptEditor:Open(s.name) end end },
            { label = L["Esegui"], width = 56, func = function() S:Run(s.name) end },
            { label = s.enabled and L["Spegni"] or L["Accendi"], width = 60, func = function() S:SetScriptEnabled(s.name, not s.enabled) end },
        } }
    end
    return rows
end

function MP.homeOptions()
    return {
        { type = "label", text = function()
            local on, total = 0, 0
            for _, n in ipairs(Modules.order or {}) do
                total = total + 1
                if Modules.list[n] and Modules.list[n].enabled then on = on + 1 end
            end
            return string.format(L["|cff3fa7ffBadbUI|r v%s  -  profilo |cff3fa7ff%s|r  -  moduli attivi %d/%d\n"]
                .. L["Da qui gestisci tutto: azioni rapide, moduli, script, aspetto e addon installati."],
                tostring(Badb.version), tostring(Badb.DB:GetProfileName()), on, total)
        end },
        { type = "header", label = L["Azioni rapide"] },
        { type = "list", height = 190, items = MP.quickActions },
        { type = "header", label = L["Moduli (Opzioni apre tutte le impostazioni del modulo)"] },
        { type = "list", height = 300, items = MP.moduleRows },
        { type = "header", label = L["Script"] },
        { type = "list", height = 120, empty = L["Nessuno script: apri l'editor per crearne uno"], items = MP.scriptRows },
    }
end

---------------------------------------------------------------------------
-- Aspetto
---------------------------------------------------------------------------

local ACCENT_LABELS = { polestar = "Polestar Amber", elvui = L["Azzurro ElvUI"], gold = L["Oro"], badb = L["Blu BadbUI"], jade = L["Giada"],
                        violet = L["Viola"], ember = L["Brace"], frost = L["Ghiaccio"] }

function MP.schemeChoices()
    local out = {}
    if Theme and Theme.ListSchemes then
        for _, s in ipairs(Theme:ListSchemes()) do out[#out + 1] = { value = s.value, label = s.text } end
    end
    return out
end

function MP.accentChoices()
    local out = {}
    for _, k in ipairs((Theme and Theme.ACCENT_ORDER) or {}) do out[#out + 1] = { value = k, label = ACCENT_LABELS[k] or k } end
    return out
end

function MP.appearanceOptions()
    return {
        { type = "header", label = L["Language"] },
        { type = "label", text = L["BadbUI is English-only on every client. Macro spell names stay in English."] },
        { type = "header", label = L["Tema"] },
        { type = "select", label = L["Schema colori"], values = MP.schemeChoices(),
          get = function() return Theme.state.scheme end, set = function(v) Theme:SetScheme(v) end },
        { type = "select", label = L["Colore d'accento"], values = MP.accentChoices(),
          get = function() return Theme.state.customAccent and "custom" or Theme.state.accent end,
          set = function(v) if v ~= "custom" then Theme:SetAccent(v) end end },
        { type = "range", label = L["Trasparenza degli sfondi"], min = 0.3, max = 1, step = 0.05,
          get = function() return Theme.state.opacity end, set = function(v) Theme:SetOpacity(v) end },
        { type = "execute", label = L["Ripristina il tema ElvUI predefinito"], func = function() Theme:Reset() end },
        { type = "header", label = L["Finestra di configurazione"] },
        { type = "range", label = L["Scala"], min = 0.6, max = 1.5, step = 0.05,
          get = function() return UI.State().scale or 1 end, set = function(v) UI:SetScale(v) end },
        { type = "label", text = L["Il tema vale per tutti i profili e si applica subito a finestre, pannelli e frame di BadbUI. "]
            .. L["Per i pannelli datatext, la minimappa e la chat apri la pagina 'Stile ElvUI'."] },
    }
end

---------------------------------------------------------------------------
-- Addon installati
---------------------------------------------------------------------------

MP.pending = {} -- addon attivati/disattivati in questa sessione: servono un /reload
local PROTECTED = { BadbUI = true }

local function addonApi() return C_AddOns or {} end

local function enableState(name)
    local f = addonApi().GetAddOnEnableState or GetAddOnEnableState
    if not f then return nil end
    local ok, v = pcall(f, name)
    if ok and type(v) == "number" then return v end
    ok, v = pcall(f, UnitName and UnitName("player"), name)
    if ok and type(v) == "number" then return v end
    return nil
end

function MP.addonList()
    local api = addonApi()
    local count = (api.GetNumAddOns and api.GetNumAddOns()) or (GetNumAddOns and GetNumAddOns()) or 0
    local info = api.GetAddOnInfo or GetAddOnInfo
    local isLoaded = api.IsAddOnLoaded or IsAddOnLoaded
    local out = {}
    if not info then return out end
    for i = 1, count do
        local ok, a, b = pcall(info, i)
        if ok then
            local name, title
            if type(a) == "table" then name, title = a.name, a.title else name, title = a, b end
            if type(name) == "string" then
                local st = enableState(name)
                out[#out + 1] = { name = name, title = (type(title) == "string" and title ~= "") and title or name,
                                  enabled = st == nil or st > 0, loaded = isLoaded and isLoaded(name) or false }
            end
        end
    end
    table.sort(out, function(x, y) return x.name:lower() < y.name:lower() end)
    return out
end

function MP.setAddonEnabled(name, value)
    local api = addonApi()
    local f = value and (api.EnableAddOn or EnableAddOn) or (api.DisableAddOn or DisableAddOn)
    if PROTECTED[name] or type(name) ~= "string" or not f then return false end
    local ok = pcall(f, name)
    if ok then MP.pending[name] = true end
    return ok
end

function MP.addonRows()
    local rows = {}
    for _, a in ipairs(MP.addonList()) do
        local detail = a.enabled and (a.loaded and L["|cff5fd068caricato|r"] or L["|cffffcc00attivo (da caricare)|r"]) or L["|cff888888spento|r"]
        if MP.pending[a.name] then detail = detail .. L["  |cff3fa7ffserve /reload|r"] end
        local acts
        if not PROTECTED[a.name] then
            acts = { { label = a.enabled and L["Spegni"] or L["Accendi"], width = 64, func = function() MP.setAddonEnabled(a.name, not a.enabled) end } }
        end
        rows[#rows + 1] = { text = esc(a.title), detail = detail, actions = acts }
    end
    return rows
end

function MP.addonOptions()
    local options = {
        { type = "label", text = L["Qui attivi o spegni gli addon gia' installati; le modifiche valgono dopo /reload. "]
            .. L["Il gioco non puo' scaricare file: per installare o aggiornare addon (X-Perl, BigWigs, Details!...) usa dal computer "]
            .. L["scripts/addons.py (vedi docs/addons.md)."] },
        { type = "list", height = 380, empty = L["API degli addon non disponibile su questo client"], items = MP.addonRows },
        { type = "execute", label = L["Ricarica l'interfaccia ora"], func = function()
            if UI.Confirm then UI:Confirm(L["Ricaricare l'interfaccia ora?"], function() ReloadUI() end) else ReloadUI() end
        end },
    }
    if Badb.Updates then
        local updateOptions = Badb.Updates:Options()
        for _, opt in ipairs(options) do updateOptions[#updateOptions + 1] = opt end
        return updateOptions
    end
    return options
end

---------------------------------------------------------------------------
-- Registrazione
---------------------------------------------------------------------------

local function build(optionsFn)
    return function(parent, ctx)
        local h, _, group = Badb.Widgets:Build(parent, nil, 8, optionsFn())
        if group and ctx and ctx.AddRefresh then ctx.AddRefresh(function() group:Refresh() end) end
        return h + 16
    end
end

UI:RegisterPage("home", { title = L["Principale"], category = L["Gestione"], order = -10,
    keywords = { "home", L["principale"], L["azioni"], L["rapide"], L["moduli"], "script" }, build = build(MP.homeOptions) })
UI:RegisterPage("appearance", { title = L["Aspetto"], category = L["Interfaccia"], order = 1,
    keywords = { L["tema"], L["colori"], L["accento"], L["trasparenza"], L["scala"], "elvui", L["stile"] }, build = build(MP.appearanceOptions) })
UI:RegisterPage("addons", { title = "Addon", category = L["Strumenti"], order = 10,
    keywords = { "addon", L["attiva"], L["disattiva"], "reload", "xperl", "bigwigs", "details" }, build = build(MP.addonOptions) })
