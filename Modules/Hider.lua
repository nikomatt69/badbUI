-- AegisUI - Hider: nasconde/mostra elementi dell'interfaccia Blizzard tramite FrameManager.
-- Aggiungere un elemento = aggiungere una riga a TARGETS. Tutto il resto (UI, profili,
-- import/export, ripristino) e' automatico.
local _, ns = ...
local Aegis = ns.Aegis
local FM = Aegis.FrameManager

local TARGETS = {
    { key = "MicroMenu",      frame = "MicroMenuContainer", title = "Micro menu",        category = "Barre" },
    { key = "BagsBar",        frame = "BagsBar",            title = "Barra borse",       category = "Barre" },
    { key = "StatusTracking", frame = "StatusTrackingBarManager", title = "Barra esperienza", category = "Barre" },
    { key = "ObjectiveTracker", frame = "ObjectiveTrackerFrame", title = "Tracker missioni", category = "HUD" },
    { key = "BuffFrame",      frame = "BuffFrame",          title = "Buff",              category = "HUD" },
    { key = "Minimap",        frame = "MinimapCluster",     title = "Minimappa",         category = "HUD" },
}

local options = {}
for _, t in ipairs(TARGETS) do
    options[#options + 1] = {
        type = "toggle", label = "Nascondi: " .. t.title,
        get = function() local c = Aegis.DB.profile.frames[t.key]; return c and c.hidden end,
        set = function(v)
            if v then FM:SetOption(t.key, "hidden", true) else FM:Restore(t.key) end
        end,
    }
end

local M = Aegis.Modules:New("Hider", {
    title = "Nascondi elementi",
    category = "Interfaccia",
    defaults = { enabled = true },
    options = options,
})

function M:OnInitialize()
    for _, t in ipairs(TARGETS) do
        FM:Register(t.key, { frame = t.frame, title = t.title, category = t.category, hideable = true })
    end
end

function M:OnEnable() FM:ApplyAll() end

function M:OnDisable()
    for _, t in ipairs(TARGETS) do
        local c = Aegis.DB.profile.frames[t.key]
        if c and c.hidden then FM:Restore(t.key) end
    end
end
