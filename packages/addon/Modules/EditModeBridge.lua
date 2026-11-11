-- BadbUI - Edit Mode Bridge
-- Su Forever i frame principali (barre, unit frame, minimappa...) sono gestiti dall'Edit Mode.
-- Invece di combatterlo, BadbUI lo usa come motore: ogni profilo BadbUI incorpora un layout
-- Edit Mode (stringa ufficiale Blizzard) e lo attiva automaticamente al cambio profilo.
-- Risultato: un'unica stringa di import contiene layout Blizzard + tutte le opzioni BadbUI.
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local Compat, Logger, Events = Badb.Compat, Badb.Logger, Badb.Events

local M = Badb.Modules:New("EditModeBridge", {
    title = L["Layout Edit Mode"],
    category = "Layout",
    defaults = {
        enabled = true,
        layoutName = nil,     -- nome del layout Edit Mode associato al profilo
        layoutString = nil,   -- copia esportata del layout (per import/export portabile)
        autoActivate = true,
        useDefault = true,    -- installa una volta il layout predefinito di BadbUI se il profilo non ne ha uno
        defaultApplied = 0,   -- versione del layout predefinito gia' installata in questo profilo
    },
    options = {
        { type = "toggle", path = "autoActivate", label = L["Attiva il layout al cambio profilo"] },
        { type = "execute", label = L["Cattura layout attuale"], func = function() Badb.Modules:Get("EditModeBridge"):Capture() end },
        { type = "toggle", path = "useDefault", label = L["Usa il layout BadbUI predefinito nei profili senza layout"] },
        { type = "execute", label = L["Ripristina il layout BadbUI predefinito"],
          func = function() Badb.Modules:Get("EditModeBridge"):ApplyDefault(true) end },
    },
    commands = {
        editmode = { help = L["editmode [default] - mostra il layout Edit Mode o ripristina il predefinito di BadbUI"], fn = function(args)
            local m = Badb.Modules:Get("EditModeBridge")
            if strtrim(args or ""):lower() == "default" then
                local ok, err = m:ApplyDefault(true)
                if not ok and err then Logger:Warn("%s", err) end
            else
                Logger:Info(L["Layout Edit Mode del profilo: %s"], tostring(m:Get("layoutName") or L["nessuno"]))
            end
        end },
    },
})
Badb.EditModeBridge = M

local function getLayouts()
    return C_EditMode.GetLayouts()
end

local function findLayoutIndex(layouts, name)
    for i, info in ipairs(layouts.layouts) do
        if info.layoutName == name then return i end
    end
end

-- Salva nel profilo il layout Edit Mode attivo, come nome + stringa portabile.
function M:Capture()
    if not Compat.hasEditMode then return end
    local layouts = getLayouts()
    local info = layouts.layouts[layouts.activeLayout]
    if not info then
        Logger:Warn(L["Nessun layout Edit Mode attivo (i preset Blizzard non sono esportabili: creane una copia)"])
        return
    end
    self:Set("layoutName", info.layoutName)
    self:Set("layoutString", C_EditMode.ConvertLayoutInfoToString(info))
    Logger:Info(L["Layout '%s' associato al profilo %s"], info.layoutName, Badb.DB:GetProfileName())
end

-- Attiva il layout del profilo; se non esiste sull'account lo ricrea dalla stringa salvata.
function M:Activate()
    if not Compat.hasEditMode then return end
    local name, str = self:Get("layoutName"), self:Get("layoutString")
    if not name then return end
    Events:RunOutOfCombat("editModeActivate", function()
        local layouts = getLayouts()
        local idx = findLayoutIndex(layouts, name)
        if not idx and str then
            local info = C_EditMode.ConvertStringToLayoutInfo(str)
            if info then
                info.layoutName = name
                info.layoutType = Enum.EditModeLayoutType.Account
                table.insert(layouts.layouts, info)
                C_EditMode.SaveLayouts(layouts)
                layouts = getLayouts()
                idx = findLayoutIndex(layouts, name)
                Logger:Info(L["Layout Edit Mode '%s' ricreato dal profilo"], name)
            end
        end
        if idx then
            -- activeLayout conta anche i 2 preset Blizzard in testa alla lista.
            C_EditMode.SetActiveLayout(idx + (Enum.EditModePresetLayoutsMeta and Enum.EditModePresetLayoutsMeta.NumValues or 2))
        else
            Logger:Warn(L["Layout '%s' non trovato"], name)
        end
    end)
end

-- Layout predefinito (Data/EditModeDefault.lua). Ritorna la definizione solo se e' ben formata.
function M:GetDefault()
    local d = Badb.EditModeDefault
    if type(d) ~= "table" or type(d.name) ~= "string" or d.name == "" then return nil end
    if type(d.layout) ~= "string" or #d.layout < 16 or #d.layout > 20000 then return nil end
    return d
end

-- Installa il layout predefinito come layout di account e lo associa al profilo attivo.
--   force = false  solo se il profilo non ha ancora un layout e non l'ha gia' ricevuto (primo avvio)
--   force = true   richiesta esplicita dell'utente: sovrascrive il layout di account con lo stesso nome
-- Ritorna true se l'installazione e' partita (in combattimento viene rimandata a fine scontro), altrimenti false, err.
function M:ApplyDefault(force)
    if not Compat.hasEditMode then return false, L["Edit Mode non disponibile su questo client: modulo inattivo"] end
    local d = self:GetDefault()
    if not d then return false, L["Layout predefinito non disponibile"] end
    local version = type(d.version) == "number" and d.version or 1
    if not force then
        if not self:Get("useDefault") or self:Get("layoutName") ~= nil then return false end
        if (tonumber(self:Get("defaultApplied")) or 0) >= version then return false end
    end
    Events:RunOutOfCombat("editModeDefault", function()
        local ok, err = pcall(function()
            local layouts = getLayouts()
            local idx = findLayoutIndex(layouts, d.name)
            if force or not idx then
                local info = C_EditMode.ConvertStringToLayoutInfo(d.layout)
                if type(info) ~= "table" then error(L["stringa del layout non riconosciuta dal client"], 0) end
                info.layoutName = d.name
                info.layoutType = Enum.EditModeLayoutType.Account
                if idx then layouts.layouts[idx] = info else table.insert(layouts.layouts, info) end
                C_EditMode.SaveLayouts(layouts)
            end
        end)
        if not ok then
            Logger:Warn(L["Layout BadbUI predefinito non installato: %s"], tostring(err))
            return
        end
        self:Set("layoutName", d.name)
        self:Set("layoutString", d.layout)
        self:Set("defaultApplied", version)
        self:Activate()
        Logger:Info(L["Layout Edit Mode '%s' predefinito attivato"], d.name)
    end)
    return true
end

function M:OnEnable()
    if not Compat.hasEditMode then
        Logger:Warn(L["Edit Mode non disponibile su questo client: modulo inattivo"])
        return
    end
    -- I layout dell'account sono leggibili dopo l'ingresso nel mondo: il predefinito si installa li', una volta.
    self:On("PLAYER_ENTERING_WORLD", function()
        self:Off("PLAYER_ENTERING_WORLD")
        self:ApplyDefault(false)
    end)
    self:On("BADB_PROFILE_CHANGED", function()
        if self:ApplyDefault(false) then return end
        if self:Get("autoActivate") then self:Activate() end
    end)
end

function M:OnDisable() end
