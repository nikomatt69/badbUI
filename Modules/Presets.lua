-- BadbUI - Preset di layout
-- Un preset e' un insieme di opzioni per piu' moduli, applicabile in un click.
-- Applicare un preset crea SEMPRE un nuovo profilo (il profilo attuale non viene toccato),
-- quindi e' annullabile: Presets:Undo() torna al profilo precedente.
--
-- I preset si compongono: base per tipo di contenuto + ritocchi per ruolo + scelte del wizard.
-- I dati per moduli non ancora caricati (es. UnitFrames, ActionBars sviluppati a parte)
-- restano nel profilo e vengono letti quando quei moduli si registrano.
local _, ns = ...
local Badb = ns.Badb
local DB, Logger, Events = Badb.DB, Badb.Logger, Badb.Events

local Presets = { content = {}, roles = {}, contentOrder = {}, roleOrder = {} }
Badb.Presets = Presets

------------------------------------------------------------------------------
-- Registri
------------------------------------------------------------------------------
-- spec = { title, description, icon, modules = { [Modulo] = { opzioni } },
--          editMode = "<stringa layout Edit Mode>" oppure { default = "...", tank = "...", healer = "...", dps = "..." } }
-- Il layout Edit Mode del ruolo vince su quello del contenuto; per ciascuno, la voce del ruolo
-- scelto vince su "default".
function Presets:RegisterContent(id, spec)
    spec.id = id
    if not self.content[id] then self.contentOrder[#self.contentOrder + 1] = id end
    self.content[id] = spec
end

function Presets:RegisterRole(id, spec)
    spec.id = id
    if not self.roles[id] then self.roleOrder[#self.roleOrder + 1] = id end
    self.roles[id] = spec
end

local function deepMerge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = deepMerge(type(dst[k]) == "table" and dst[k] or {}, v)
        else
            dst[k] = v
        end
    end
    return dst
end

------------------------------------------------------------------------------
-- Contenuti
------------------------------------------------------------------------------
Presets:RegisterContent("leveling", {
    title = "Leveling",
    description = "Pulito e leggero per quest e mondo aperto: nameplate solo nemiche, interfaccia ordinata.",
    icon = "Interface\\Icons\\INV_Misc_Map_01",
    modules = {
        Nameplates = { enabled = true, showEnemies = true, showFriends = false, showAlways = false,
            showMinions = false, maxDistance = 41, stacking = "stack", globalScale = 1.0, minAlpha = 0.7 },
        NameplateAuras = { enabled = true, ownDebuffs = "curated", friendly = "off", maxBuffs = 2 },
        GroupFrames = { enabled = true, raidStyleParty = true, powerBars = false, showPets = false,
            resizeFrames = true, partyWidth = 120, partyHeight = 56 },
        Scaling = { enabled = true, pixelPerfect = true },
    },
})

Presets:RegisterContent("dungeon", {
    title = "Dungeon",
    description = "Gruppi da 5: nameplate impilate e sempre visibili, party in stile raid ben leggibili.",
    icon = "Interface\\Icons\\INV_Misc_Key_13",
    modules = {
        Nameplates = { enabled = true, showEnemies = true, showAlways = true, showMinions = true,
            stacking = "stack", overlapV = 1.1, selectedScale = 1.25, minAlpha = 0.55, targetBorder = true },
        NameplateAuras = { enabled = true, ownDebuffs = "curated", friendly = "cc" },
        GroupFrames = { enabled = true, raidStyleParty = true, powerBars = true, aggroHighlight = true,
            resizeFrames = true, partyWidth = 132, partyHeight = 64, healthText = "none" },
        Scaling = { enabled = true, pixelPerfect = true },
    },
})

Presets:RegisterContent("raid", {
    title = "Raid",
    description = "Molte unita' a schermo: frame raid compatti, solo debuff utili, nameplate essenziali.",
    icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    modules = {
        Nameplates = { enabled = true, showEnemies = true, showAlways = true, showMinions = false,
            stacking = "stack", overlapV = 1.0, globalScale = 0.9, minAlpha = 0.5, occludedAlpha = 0.3 },
        NameplateAuras = { enabled = true, ownDebuffs = "curated", friendly = "off", maxBuffs = 2, maxOwn = 4 },
        GroupFrames = { enabled = true, raidStyleParty = true, powerBars = false, showPets = false,
            mainTankAssist = true, onlyDispellable = true, resizeFrames = true,
            raidWidth = 88, raidHeight = 44, partyWidth = 120, partyHeight = 56 },
        Scaling = { enabled = true, pixelPerfect = true },
    },
})

Presets:RegisterContent("pvp", {
    title = "PvP",
    description = "Battleground e duelli: nameplate grandi con colore di classe, pet e totem nemici visibili.",
    icon = "Interface\\Icons\\Achievement_BG_winWSG",
    modules = {
        Nameplates = { enabled = true, showEnemies = true, showFriends = true, showAlways = true,
            showMinions = true, classColorEnemies = true, classColorFriends = true, maxDistance = 41,
            stacking = "stack", globalScale = 1.1, selectedScale = 1.3, minAlpha = 0.6, targetBorder = true },
        NameplateAuras = { enabled = true, ownDebuffs = "curated", friendly = "cc", ccSize = 34, buffSize = 26,
            maxBuffs = 3, categories = { snare = true, utility = true } },
        Alerts = { enabled = true, healerCC = true, when = "pvp", sound = true },
        GroupFrames = { enabled = true, raidStyleParty = true, powerBars = true, showPets = false,
            resizeFrames = true, partyWidth = 128, partyHeight = 60, raidWidth = 92, raidHeight = 44 },
        Scaling = { enabled = true, pixelPerfect = true },
    },
})

------------------------------------------------------------------------------
-- Ruoli
------------------------------------------------------------------------------
Presets:RegisterRole("tank", {
    title = "Tank",
    description = "Vedi tutto quello che hai addosso: nameplate piu' grandi e aggro evidente.",
    icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
    modules = {
        Nameplates = { showMinions = true, globalScale = 1.1, minAlpha = 0.75 },
        GroupFrames = { aggroHighlight = true },
    },
})

Presets:RegisterRole("healer", {
    title = "Healer",
    description = "Frame di gruppo piu' grandi, barre risorse, cure in arrivo e debuff dissipabili.",
    icon = "Interface\\Icons\\Spell_Holy_FlashHeal",
    modules = {
        Nameplates = { globalScale = 0.9, minAlpha = 0.45 },
        GroupFrames = { powerBars = true, incomingHeals = true, onlyDispellable = true, healthText = "losthealth",
            partyWidth = 144, partyHeight = 72, raidWidth = 100, raidHeight = 52 },
        NameplateAuras = { maxOwn = 3 },
    },
})

Presets:RegisterRole("dps", {
    title = "DPS",
    description = "Focus sul bersaglio: scala bersaglio maggiore e unita' secondarie attenuate.",
    icon = "Interface\\Icons\\Ability_DualWield",
    modules = {
        Nameplates = { selectedScale = 1.3, minAlpha = 0.5, targetBorder = true },
        GroupFrames = { powerBars = false },
    },
})

------------------------------------------------------------------------------
-- Composizione e applicazione
------------------------------------------------------------------------------
local function pickLayout(def, roleId)
    if type(def) == "string" then return def end
    if type(def) == "table" then return def[roleId] or def.default end
end

-- choices = { content = "dungeon", role = "healer", hideClutter = bool, pixelPerfect = bool, friendlyPlates = bool }
function Presets:Build(choices)
    choices = choices or {}
    local spec = { modules = {} }
    local c = self.content[choices.content or "leveling"]
    local r = self.roles[choices.role or "dps"]
    if c then deepMerge(spec.modules, c.modules) end
    if r then deepMerge(spec.modules, r.modules) end
    local m = spec.modules
    if choices.pixelPerfect ~= nil then
        m.Scaling = m.Scaling or {}
        m.Scaling.enabled = true
        m.Scaling.pixelPerfect = choices.pixelPerfect
    end
    if choices.friendlyPlates ~= nil then
        m.Nameplates = m.Nameplates or {}
        m.Nameplates.showFriends = choices.friendlyPlates
    end
    spec.hideClutter = choices.hideClutter
    spec.title = string.format("%s %s", c and c.title or "?", r and r.title or "")
    spec.editMode = pickLayout(r and r.editMode, r and r.id) or pickLayout(c and c.editMode, r and r.id)
    return spec
end

-- Elenco leggibile delle modifiche, per il riepilogo del wizard.
function Presets:Describe(spec)
    local lines = {}
    local function add(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end
    local np, gf, sc = spec.modules.Nameplates, spec.modules.GroupFrames, spec.modules.Scaling
    if np then
        add("Nameplate %s, %s, scala %.0f%%", np.stacking == "overlap" and "sovrapposte" or "impilate",
            np.showFriends and "nemici + alleati" or "solo nemici", (np.globalScale or 1) * 100)
        if np.showMinions then add("Pet, totem e guardiani nemici visibili") end
    end
    if gf then
        add("Party %dx%d, raid %dx%d (layout Edit Mode)", gf.partyWidth or 120, gf.partyHeight or 60,
            gf.raidWidth or 90, gf.raidHeight or 45)
        if gf.powerBars then add("Barre risorse sui frame di gruppo") end
        if gf.onlyDispellable then add("Solo debuff dissipabili") end
    end
    local na, al = spec.modules.NameplateAuras, spec.modules.Alerts
    if na and na.enabled then
        add("Aure curate sulle nameplate: CC grande, difensivi nemici, i tuoi debuff %s",
            na.ownDebuffs == "all" and "(tutti)" or "curati per classe")
    end
    if al and al.enabled and al.healerCC then add("Avviso quando l'healer del gruppo finisce in CC") end
    if sc and sc.enabled then add(sc.pixelPerfect and "Scala UI pixel perfect" or "Scala UI manuale") end
    if spec.editMode then add("Layout Edit Mode dedicato (posizioni di barre e frame)") end
    if spec.hideClutter then add("Nasconde micro menu, barra borse e barra esperienza") end
    return lines
end

local CLUTTER = { "MicroMenu", "BagsBar", "StatusTracking" }

local function uniqueProfileName(base)
    local name, n = base, 2
    while DB.sv.profiles[name] do name = string.format("%s (%d)", base, n); n = n + 1 end
    return name
end

-- Crea un nuovo profilo dal preset e lo attiva. Restituisce il nome del profilo.
function Presets:Apply(spec)
    if InCombatLockdown() then
        Logger:Warn("Preset: impossibile applicare in combattimento, riprova dopo")
        return
    end
    local previous = DB:GetProfileName()
    local name = uniqueProfileName("Badb - " .. (spec.title or "Preset"))
    -- Parte da una copia del profilo attuale: mantiene layout Edit Mode e opzioni non coperte.
    DB:CopyProfile(previous, name)
    local p = DB.sv.profiles[name]
    p.modules = p.modules or {}
    for module, opts in pairs(spec.modules) do
        p.modules[module] = deepMerge(p.modules[module] or {}, opts)
    end
    if spec.hideClutter then
        p.frames = p.frames or {}
        p.modules.Hider = p.modules.Hider or {}
        p.modules.Hider.enabled = true
        for _, key in ipairs(CLUTTER) do
            p.frames[key] = p.frames[key] or {}
            p.frames[key].hidden = true
        end
    end
    if spec.editMode then
        -- EditModeBridge ricrea il layout dalla stringa e lo attiva al cambio profilo.
        p.modules.EditModeBridge = p.modules.EditModeBridge or {}
        local bridge = p.modules.EditModeBridge
        bridge.enabled, bridge.autoActivate = true, true
        bridge.layoutName, bridge.layoutString = name, spec.editMode
    end
    DB.sv.global.presetUndo = previous
    DB:SetProfile(name)
    Logger:Info("Preset applicato: profilo '%s' (annulla con /badb undo)", name)
    Events:Fire("BADB_PRESET_APPLIED", name, spec)
    return name
end

function Presets:CanUndo()
    local prev = DB.sv.global.presetUndo
    return prev ~= nil and DB.sv.profiles[prev] ~= nil
end

function Presets:Undo()
    if not self:CanUndo() then Logger:Info("Nessun preset da annullare"); return end
    local prev = DB.sv.global.presetUndo
    DB.sv.global.presetUndo = nil
    DB:SetProfile(prev)
    Logger:Info("Tornato al profilo '%s'", prev)
end

-- Raccomandazione automatica in base al personaggio: usata da "Applica consigliato".
function Presets:Recommend()
    local role = "dps"
    local spec = GetSpecialization and GetSpecialization()
    local assigned = spec and GetSpecializationRole and GetSpecializationRole(spec)
    if not assigned and UnitGroupRolesAssigned then assigned = UnitGroupRolesAssigned("player") end
    if assigned == "TANK" then role = "tank" elseif assigned == "HEALER" then role = "healer" end
    local level = UnitLevel("player") or 1
    local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 60
    local content = level < maxLevel and "leveling" or (IsInRaid() and "raid" or "dungeon")
    return { content = content, role = role, pixelPerfect = true, hideClutter = false, friendlyPlates = false }
end

------------------------------------------------------------------------------
-- Modulo (per la ConfigUI: apre il wizard e annulla)
------------------------------------------------------------------------------
local M = Badb.Modules:New("Presets", {
    title = "Preset e configurazione guidata",
    category = "Layout",
    defaults = { enabled = true },
    options = {
        { type = "execute", label = "Apri configurazione guidata", func = function()
            if Badb.Wizard then Badb.Wizard:Open() end
        end },
        { type = "execute", label = "Applica layout consigliato", func = function()
            Presets:Apply(Presets:Build(Presets:Recommend()))
        end },
        { type = "execute", label = "Annulla ultimo preset", func = function() Presets:Undo() end },
    },
})

function M:OnEnable() end
function M:OnDisable() end
