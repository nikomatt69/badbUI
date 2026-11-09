-- AegisUI - Edit Mode Bridge
-- Su Forever i frame principali (barre, unit frame, minimappa...) sono gestiti dall'Edit Mode.
-- Invece di combatterlo, AegisUI lo usa come motore: ogni profilo AegisUI incorpora un layout
-- Edit Mode (stringa ufficiale Blizzard) e lo attiva automaticamente al cambio profilo.
-- Risultato: un'unica stringa di import contiene layout Blizzard + tutte le opzioni AegisUI.
local _, ns = ...
local Aegis = ns.Aegis
local Compat, Logger, Events = Aegis.Compat, Aegis.Logger, Aegis.Events

local M = Aegis.Modules:New("EditModeBridge", {
    title = "Layout Edit Mode",
    category = "Layout",
    defaults = {
        enabled = true,
        layoutName = nil,     -- nome del layout Edit Mode associato al profilo
        layoutString = nil,   -- copia esportata del layout (per import/export portabile)
        autoActivate = true,
    },
    options = {
        { type = "toggle", path = "autoActivate", label = "Attiva il layout al cambio profilo" },
        { type = "execute", label = "Cattura layout attuale", func = function() Aegis.Modules:Get("EditModeBridge"):Capture() end },
    },
})

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
        Logger:Warn("Nessun layout Edit Mode attivo (i preset Blizzard non sono esportabili: creane una copia)")
        return
    end
    self:Set("layoutName", info.layoutName)
    self:Set("layoutString", C_EditMode.ConvertLayoutInfoToString(info))
    Logger:Info("Layout '%s' associato al profilo %s", info.layoutName, Aegis.DB:GetProfileName())
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
                Logger:Info("Layout Edit Mode '%s' ricreato dal profilo", name)
            end
        end
        if idx then
            -- activeLayout conta anche i 2 preset Blizzard in testa alla lista.
            C_EditMode.SetActiveLayout(idx + (Enum.EditModePresetLayoutsMeta and Enum.EditModePresetLayoutsMeta.NumValues or 2))
        else
            Logger:Warn("Layout '%s' non trovato", name)
        end
    end)
end

function M:OnEnable()
    if not Compat.hasEditMode then
        Logger:Warn("Edit Mode non disponibile su questo client: modulo inattivo")
        return
    end
    self:On("AEGIS_PROFILE_CHANGED", function()
        if self:Get("autoActivate") then self:Activate() end
    end)
end

function M:OnDisable() end
