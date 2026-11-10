-- BadbUI - Compat
-- Unico punto in cui si gestiscono le particolarita' del client.
-- Target: WoW Forever (interface 16001), che condivide l'architettura UI Mainline
-- ma con restrizioni "stile Midnight" (secret values, combat log non disponibile).
-- Il resto dell'addon usa Badb.Compat.* invece di sondare le API direttamente.
local _, ns = ...
local Badb = ns.Badb

local Compat = {}
Badb.Compat = Compat

local interface = select(4, GetBuildInfo()) or 0
Compat.interface = interface
-- Non fidarsi di WOW_PROJECT_ID da solo: sondiamo le funzionalita'.
Compat.isForever = interface >= 16000 and interface < 20000
Compat.hasEditMode = C_EditMode ~= nil and EditModeManagerFrame ~= nil
Compat.hasSettings = Settings ~= nil and Settings.RegisterCanvasLayoutCategory ~= nil

Compat.After = C_Timer.After
Compat.NewTicker = C_Timer.NewTicker

function Compat.CreateFrame(frameType, name, parent, template)
    template = template and (template .. ",BackdropTemplate") or "BackdropTemplate"
    return CreateFrame(frameType, name, parent, template)
end

function Compat.GetAddOnMetadata(addon, field)
    return C_AddOns.GetAddOnMetadata(addon, field)
end

-- Secret values: su Forever alcuni valori (es. UnitHealth, nomi) sono opachi in combattimento.
-- Confronti e aritmetica falliscono: usare sempre questo guard prima di leggerli.
function Compat.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end

function Compat.SafeValue(v, fallback)
    if Compat.IsSecret(v) then return fallback end
    return v
end

-- Pannello opzioni tramite Settings API (presente su Forever).
function Compat.RegisterOptionsPanel(panel, title, parentCategory)
    if Compat.hasSettings then
        local category
        if parentCategory then
            if type(Settings.RegisterCanvasLayoutSubcategory) ~= "function" then return end
            category = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, title)
        else
            category = Settings.RegisterCanvasLayoutCategory(panel, title)
            Settings.RegisterAddOnCategory(category)
        end
        panel.settingsCategory = category
        return category
    end
end

function Compat.OpenOptionsPanel(panel)
    if panel.settingsCategory then
        Settings.OpenToCategory(panel.settingsCategory:GetID())
    end
end

-- Un frame e' gestito dall'Edit Mode se ha il campo "system" (EditModeSystemMixin).
-- Su questi frame NON si fa SetPoint diretto: si passa da EditModeBridge, altrimenti
-- si combatte con Blizzard e si rischia taint.
function Compat.IsEditModeFrame(f)
    return Compat.hasEditMode and f ~= nil and f.system ~= nil
end
