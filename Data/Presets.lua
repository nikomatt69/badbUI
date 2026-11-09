-- BadbUI - Data/Presets: 54 template di interfaccia (9 classi x 3 PvE + 3 PvP), generati da dati.
-- Niente 54 tabelle copiate: ogni template nasce da
--   base dello scenario (mode x scenario)  ->  ritocchi della classe  ->  byRole (ruoli ammessi dalla classe)
--   ->  varianti raid 10/20/40 (con ritocchi per healer)
-- e ognuno porta il proprio layout Edit Mode dichiarativo (posizioni e impostazioni di barre, unit frame, cast bar),
-- costruito per "archetipo" (healer, tank, mischia, distanza) e adattato allo scenario.
--
-- Principi del layout (in stile UI pack curati, vedi docs/research/skillcapped.md):
--   * elementi chiave vicino al centro: giocatore e bersaglio ai lati del personaggio, cast bar sopra le barre;
--   * in PvP focus e frame del gruppo alla stessa distanza dal centro, simmetrici;
--   * micro menu e barra borse nascosti fuori dal leveling (si riaprono con i tasti rapidi).
-- Fatti di gioco usati: docs/FOREVER_FACTS.md (righe citate in `facts`). Posizioni in unita' UI: da rifinire in gioco.
local _, ns = ...
local Badb = ns.Badb
local P, Player = Badb.Presets, Badb.Player
if not (P and P.Register and Player and Player.CLASSES) then return end

local Data = {}
P.Data = Data

------------------------------------------------------------------------------
-- Fatti (riferimenti a docs/FOREVER_FACTS.md)
------------------------------------------------------------------------------
local FACT = {
    dungeon = "PvE: dungeon a 5 giocatori (FOREVER_FACTS, PvE)",
    raid = "PvE: raid da 10 / 20 / 40 (Barrow Deeps, Hyjal Summit, Onyxia) (FOREVER_FACTS, PvE)",
    solo = "Leveling 1-60 e mondo aperto; preset Classic/Enhanced di Blizzard al primo login (FOREVER_FACTS, Client)",
    bg = "PvP: Warsong Gulch 10v10, Arathi Basin e Darkspear Islands 15v15 (FOREVER_FACTS, PvP)",
    av = "PvP: Alterac Valley 40v40 (FOREVER_FACTS, PvP)",
    world = "PvP: world PvP nelle zone contese e duelli; nessuna arena (FOREVER_FACTS, PvP)",
    editMode = "Edit Mode integrato per barre e unit frame (FOREVER_FACTS, Client)",
    roles = "Ruoli per classe e dual spec al 40 (FOREVER_FACTS, Classi)",
    secret = "Salute e minaccia sono secret values: niente testi calcolati in combattimento (FOREVER_FACTS, Restrizioni)",
}

------------------------------------------------------------------------------
-- Layout Edit Mode per archetipo
------------------------------------------------------------------------------
-- Posizioni dei frame principali rispetto al centro dello schermo.
local ARCH = {
    healer = { player = { -290, -70 }, target = { 290, -70 }, focus = { 290, 20 }, cast = 205, icon = 90,
        party = { "TOP", "CENTER", 0, -120 }, raid = { "TOP", "CENTER", 0, -110 }, horizontal = true },
    tank   = { player = { -240, -140 }, target = { 240, -140 }, focus = { 240, -50 }, cast = 195, icon = 100,
        party = { "TOPLEFT", "TOPLEFT", 24, -220 }, raid = { "TOPLEFT", "TOPLEFT", 24, -220 } },
    melee  = { player = { -250, -170 }, target = { 250, -170 }, focus = { 250, -80 }, cast = 195, icon = 100,
        party = { "TOPLEFT", "TOPLEFT", 24, -220 }, raid = { "TOPLEFT", "TOPLEFT", 24, -220 } },
    ranged = { player = { -300, -190 }, target = { 300, -190 }, focus = { 300, -100 }, cast = 180, icon = 90,
        party = { "TOPLEFT", "TOPLEFT", 24, -220 }, raid = { "TOPLEFT", "TOPLEFT", 24, -220 } },
}
Data.ARCH = ARCH

local function bar(index, anchor, icon, vertical, extra)
    local s = { NumRows = 1, NumIcons = 12, IconSize = icon, IconPadding = 2,
        Orientation = vertical and "Vertical" or "Horizontal" }
    for k, v in pairs(extra or {}) do s[k] = v end
    return { system = "ActionBar", index = index, anchor = anchor, settings = s }
end

local function unit(index, anchor, settings)
    return { system = "UnitFrame", index = index, anchor = anchor, settings = settings }
end

local cache = {}
-- Layout completo per archetipo + scenario (+ variante raid). Le tabelle sono condivise in sola lettura:
-- Presets:Resolve lavora sempre su copie.
function Data.Layout(arch, scenario, variant)
    local id = arch .. ":" .. scenario .. ":" .. tostring(variant)
    if cache[id] then return cache[id] end
    local a = ARCH[arch]
    local pvp = scenario == "bg" or scenario == "av" or scenario == "world"
    local icon = a.icon
    if pvp and arch ~= "healer" then icon = 100 end
    local step = icon >= 100 and 44 or 40
    local systems = {
        bar("MainBar", { "BOTTOM", "BOTTOM", 0, 24 }, icon, false, { HideBarArt = true, HideBarScrolling = true }),
        bar("Bar2", { "BOTTOM", "BOTTOM", 0, 24 + step }, icon),
        bar("Bar3", { "BOTTOM", "BOTTOM", 0, 24 + 2 * step }, icon),
        bar("RightBar1", { "RIGHT", "RIGHT", -4, 0 }, icon, true),
        bar("RightBar2", { "RIGHT", "RIGHT", -4 - step, 0 }, icon, true),
        { system = "CastBar", anchor = { "BOTTOM", "BOTTOM", 0, 24 + 3 * step + (a.cast - 180) }, settings = { ShowCastTime = true } },
    }
    local px, py, tx, ty, fx, fy = a.player[1], a.player[2], a.target[1], a.target[2], a.focus[1], a.focus[2]
    local party, raid = a.party, a.raid
    if pvp then
        -- PvP: bersaglio piu' in alto e focus simmetrico al gruppo, alla stessa distanza dal centro.
        ty = ty + 40
        fx, fy = 380, 60
        party = { "RIGHT", "CENTER", -380, 60 }
        raid = { "RIGHT", "CENTER", -380, 60 }
    end
    if scenario == "av" or (scenario == "raid" and variant ~= "10" and arch ~= "healer") then
        raid = { "TOPLEFT", "TOPLEFT", 24, -200 }
    elseif scenario == "raid" and arch == "healer" and variant == "40" then
        raid = { "TOP", "CENTER", 0, -40 } -- 40 compatti: piu' righe, si parte piu' in alto
    end
    systems[#systems + 1] = unit("Player", { "CENTER", "CENTER", px, py })
    systems[#systems + 1] = unit("Target", { "CENTER", "CENTER", tx, ty }, { BuffsOnTop = true })
    systems[#systems + 1] = unit("Focus", { "CENTER", "CENTER", fx, fy }, { UseLargerFrame = pvp })
    systems[#systems + 1] = unit("Party", party, { UseRaidStylePartyFrames = true, UseHorizontalGroups = a.horizontal == true })
    systems[#systems + 1] = unit("Raid", raid, { UseHorizontalGroups = a.horizontal == true and scenario ~= "av" })
    if scenario == "solo" or scenario == "world" then
        systems[#systems + 1] = { system = "ObjectiveTracker", anchor = { "TOPRIGHT", "TOPRIGHT", -40, -240 } }
    end
    local l = { base = "modern", systems = systems }
    cache[id] = l
    return l
end

------------------------------------------------------------------------------
-- Basi per scenario
------------------------------------------------------------------------------
local HIDE = { hidden = true }
local BASE = {
    dungeon = {
        title = "Dungeon", mode = "pve",
        description = "Gruppo da 5: nameplate impilate sempre visibili, party in stile raid leggibile, HUD centrato.",
        why = "In dungeon conta leggere i 5 del gruppo e i pack di nemici: party in stile raid e nameplate impilate sempre visibili.",
        modules = {
            Nameplates = { enabled = true, showEnemies = true, showFriends = false, showAlways = true, showMinions = true,
                stacking = "stack", overlapV = 1.1, selectedScale = 1.25, minAlpha = 0.55, targetBorder = true },
            NameplateAuras = { enabled = true, ownDebuffs = "curated", friendly = "cc" },
            GroupFrames = { enabled = true, raidStyleParty = true, powerBars = true, aggroHighlight = true,
                resizeFrames = true, partyWidth = 132, partyHeight = 64, healthText = "none" },
            ActionBars = { fade = { right = true, left = true }, fadeShowInCombat = true },
            Cooldowns = { pulse = true, pulseMinDuration = 8 },
            Scaling = { enabled = true, pixelPerfect = true },
        },
        frames = { MicroMenu = HIDE, BagsBar = HIDE },
    },
    raid = {
        title = "Raid", mode = "pve", defaultVariant = "20",
        description = "Molte unita' a schermo: raid frame dimensionati per 10/20/40, solo debuff utili, nameplate essenziali.",
        why = "Nei raid da 10/20/40 la dimensione dei raid frame segue il numero di giocatori; nameplate essenziali per non coprire le meccaniche.",
        modules = {
            Nameplates = { enabled = true, showEnemies = true, showFriends = false, showAlways = true, showMinions = false,
                stacking = "stack", overlapV = 1.0, globalScale = 0.9, minAlpha = 0.5, occludedAlpha = 0.3 },
            NameplateAuras = { enabled = true, ownDebuffs = "curated", friendly = "off", maxBuffs = 2, maxOwn = 4 },
            GroupFrames = { enabled = true, raidStyleParty = true, powerBars = false, showPets = false,
                mainTankAssist = true, onlyDispellable = true, resizeFrames = true, raidWidth = 96, raidHeight = 48 },
            ActionBars = { fade = { right = true, left = true }, fadeShowInCombat = true },
            Cooldowns = { pulse = true, pulseMinDuration = 10 },
            Scaling = { enabled = true, pixelPerfect = true },
        },
        frames = { MicroMenu = HIDE, BagsBar = HIDE, StatusTracking = HIDE },
        variants = {
            ["10"] = { modules = { GroupFrames = { raidWidth = 112, raidHeight = 56, powerBars = true } } },
            ["20"] = { modules = { GroupFrames = { raidWidth = 96, raidHeight = 48 } } },
            ["40"] = { modules = { GroupFrames = { raidWidth = 76, raidHeight = 38, onlyDispellable = true },
                Nameplates = { globalScale = 0.85, minAlpha = 0.45 } } },
        },
    },
    solo = {
        title = "Solo e leveling", mode = "pve",
        description = "Quest e mondo aperto: HUD pulito, tracker missioni ed esperienza visibili, nameplate solo in combattimento.",
        why = "Durante il leveling servono tracker missioni e barra esperienza; il resto resta pulito e le nameplate compaiono solo in combattimento.",
        modules = {
            Nameplates = { enabled = true, showEnemies = true, showFriends = false, showAlways = false, showMinions = false,
                stacking = "stack", minAlpha = 0.7, maxDistance = 41 },
            NameplateAuras = { enabled = true, ownDebuffs = "curated", friendly = "off", maxBuffs = 2 },
            GroupFrames = { enabled = true, raidStyleParty = true, powerBars = false, resizeFrames = true,
                partyWidth = 120, partyHeight = 56 },
            ActionBars = { fade = { bottomRight = true, right = true, left = true }, fadeShowInCombat = true, fadeShowWithTarget = true },
            Cooldowns = { pulse = true, pulseMinDuration = 6 },
            Scaling = { enabled = true, pixelPerfect = true },
        },
        frames = { MicroMenu = HIDE },
    },
    bg = {
        title = "Campo di battaglia", mode = "pvp",
        description = "Warsong, Arathi, Darkspear (10-15 giocatori): nameplate nemiche grandi e lontane, alleati ridotti.",
        why = "Nei BG da 10-15 contano i nemici: nameplate grandi con colore di classe fino a 60 yard, alleati senza nameplate e gruppo compatto.",
        modules = {
            Nameplates = { enabled = true, showEnemies = true, showFriends = false, showAlways = true, showMinions = true,
                classColorEnemies = true, maxDistance = 60, stacking = "stack", globalScale = 1.1, selectedScale = 1.35,
                minAlpha = 0.65, targetBorder = true },
            NameplateAuras = { enabled = true, ownDebuffs = "curated", friendly = "cc", ccSize = 34, buffSize = 26,
                categories = { snare = true, utility = true } },
            Alerts = { enabled = true, healerCC = true, when = "pvp" },
            GroupFrames = { enabled = true, raidStyleParty = true, powerBars = true, showPets = false,
                resizeFrames = true, partyWidth = 120, partyHeight = 52, raidWidth = 88, raidHeight = 40 },
            ActionBars = { fade = { right = false, left = false } },
            Cooldowns = { pulse = true, pulseMinDuration = 10, expiringThreshold = 3 },
            Scaling = { enabled = true, pixelPerfect = true },
        },
        frames = { MicroMenu = HIDE, BagsBar = HIDE },
    },
    av = {
        title = "Alterac Valley", mode = "pvp",
        description = "40 contro 40: raid frame compatti, nameplate solo nemiche e senza pet per restare leggibili nella mischia.",
        why = "In Alterac 40v40 le unita' sono troppe: raid frame compatti in alto a sinistra e nameplate solo nemiche, senza pet e totem.",
        modules = {
            Nameplates = { enabled = true, showEnemies = true, showFriends = false, showAlways = true, showMinions = false,
                classColorEnemies = true, maxDistance = 60, stacking = "stack", globalScale = 1.0, selectedScale = 1.3,
                minAlpha = 0.55, occludedAlpha = 0.3 },
            NameplateAuras = { enabled = true, ownDebuffs = "curated", friendly = "off", ccSize = 32, maxBuffs = 2, maxOwn = 4 },
            Alerts = { enabled = true, healerCC = true, when = "pvp" },
            GroupFrames = { enabled = true, raidStyleParty = true, powerBars = false, showPets = false,
                resizeFrames = true, raidWidth = 74, raidHeight = 36 },
            Cooldowns = { pulse = true, pulseMinDuration = 15, expiringThreshold = 3 },
            Scaling = { enabled = true, pixelPerfect = true },
        },
        frames = { MicroMenu = HIDE, BagsBar = HIDE, StatusTracking = HIDE },
    },
    world = {
        title = "World PvP e duelli", mode = "pvp",
        description = "Zone contese e duelli: nameplate nemiche sempre visibili con pet e totem, tracker missioni a portata.",
        why = "Nel world PvP e nei duelli si combatte mentre si questa: nemici sempre visibili con pet e totem, tracker missioni mantenuto.",
        modules = {
            Nameplates = { enabled = true, showEnemies = true, showFriends = false, showAlways = true, showMinions = true,
                classColorEnemies = true, maxDistance = 60, stacking = "stack", globalScale = 1.05, selectedScale = 1.35,
                minAlpha = 0.7, targetBorder = true },
            NameplateAuras = { enabled = true, ownDebuffs = "curated", friendly = "cc", ccSize = 34, buffSize = 26,
                categories = { snare = true, utility = true } },
            Alerts = { enabled = true, healerCC = true, focusCC = true, when = "always" },
            GroupFrames = { enabled = true, raidStyleParty = true, powerBars = true, resizeFrames = true,
                partyWidth = 120, partyHeight = 56 },
            ActionBars = { fade = { right = true, left = true }, fadeShowInCombat = true },
            Cooldowns = { pulse = true, pulseMinDuration = 10, expiringThreshold = 3 },
            Scaling = { enabled = true, pixelPerfect = true },
        },
        frames = { MicroMenu = HIDE },
    },
}
Data.BASE = BASE

------------------------------------------------------------------------------
-- Ruoli (sopra la base) e ritocchi per classe
------------------------------------------------------------------------------
local ROLE = {
    healer = {
        why = "Da healer i frame di gruppo sono il centro dell'interfaccia: grandi, con risorse, cure in arrivo e solo debuff dissipabili.",
        modules = {
            Nameplates = { globalScale = 0.9, minAlpha = 0.45 },
            GroupFrames = { powerBars = true, incomingHeals = true, onlyDispellable = true, partyWidth = 144, partyHeight = 72 },
        },
        pvpModules = { Nameplates = { globalScale = 1.0 } },
    },
    tank = {
        why = "Da tank servono i nemici: nameplate piu' grandi con pet e guardiani, aggro evidente e pulse dei cooldown difensivi.",
        modules = {
            Nameplates = { showMinions = true, globalScale = 1.15, minAlpha = 0.75, selectedScale = 1.2 },
            GroupFrames = { aggroHighlight = true },
            Cooldowns = { pulseMinDuration = 4, pulseSize = 64 },
            ActionBars = { fade = { bottomRight = false } },
        },
    },
    dps = {
        why = "Da DPS conta il bersaglio: scala maggiore sul bersaglio e unita' secondarie attenuate.",
        modules = {
            Nameplates = { selectedScale = 1.3, minAlpha = 0.5, targetBorder = true },
        },
    },
}

-- Distanza di combattimento del ruolo DPS per classe. Sciamano e Druido: si presume Potenziamento/Ferino (mischia);
-- chi gioca Elementale/Equilibrio puo' scegliere il template e spostare le barre (conf. C, vedi docs/presets.md).
local DPS_RANGE = { WARRIOR = "melee", PALADIN = "melee", HUNTER = "ranged", ROGUE = "melee", PRIEST = "ranged",
    SHAMAN = "melee", MAGE = "ranged", WARLOCK = "ranged", DRUID = "melee" }
Data.DPS_RANGE = DPS_RANGE

local CLASS = {
    WARRIOR = { why = "Il Guerriero vive di posture: barra delle posture sempre visibile.",
        modules = { ActionBars = { fade = { stance = false } } } },
    PALADIN = { why = "Il Paladino ibrido tiene visibili le barre laterali per aure e benedizioni.",
        modules = { ActionBars = { fade = { right = false } } } },
    HUNTER = { why = "Il Cacciatore combatte a distanza col famiglio: barra del pet visibile e nameplate fino a 60 yard.",
        modules = { ActionBars = { fade = { pet = false } }, Nameplates = { maxDistance = 60 } } },
    ROGUE = { why = "Il Ladro non usa la barra delle forme: nascosta, piu' spazio per i cooldown.",
        modules = { ActionBars = { fade = { stance = true } }, Cooldowns = { expiringThreshold = 3 } } },
    PRIEST = { why = "Il Sacerdote alterna cure e Ombra: barre compatte e risorse dei compagni sempre visibili.",
        modules = { GroupFrames = { powerBars = true } } },
    SHAMAN = { why = "Lo Sciamano gestisce i totem: pet e totem nemici visibili per distinguerli dai propri.",
        modules = { Nameplates = { showMinions = true } } },
    MAGE = { why = "Il Mago combatte a distanza: barre compatte e nameplate leggibili da lontano.",
        modules = { Nameplates = { maxDistance = 60 } } },
    WARLOCK = { why = "Lo Stregone ha sempre un demone: barra del pet visibile e nameplate a lunga distanza.",
        modules = { ActionBars = { fade = { pet = false } }, Nameplates = { maxDistance = 60 } } },
    DRUID = { why = "Il Druido cambia forma di continuo: barra delle forme sempre visibile.",
        modules = { ActionBars = { fade = { stance = false } } } },
}
Data.CLASS = CLASS

local SCEN_NAMES = { dungeon = "Dungeon", raid = "Raid", solo = "Solo", bg = "Campo di battaglia", av = "Alterac", world = "World PvP" }

local function merge(dst, src)
    for k, v in pairs(src or {}) do
        if type(v) == "table" then
            dst[k] = merge(type(dst[k]) == "table" and dst[k] or {}, v)
        else
            dst[k] = v
        end
    end
    return dst
end

local function archFor(token, role)
    if role == "healer" or role == "tank" then return role end
    return DPS_RANGE[token] or "melee"
end
Data.ArchFor = archFor

local function roleBlock(token, role, scenario, mode)
    local r = ROLE[role]
    local mods = merge({}, r.modules)
    if mode == "pvp" and r.pvpModules then merge(mods, r.pvpModules) end
    if archFor(token, role) == "ranged" then merge(mods, { Nameplates = { maxDistance = 60 } }) end
    local block = { modules = mods, editMode = Data.Layout(archFor(token, role), scenario, scenario == "raid" and "20" or nil) }
    return block
end

-- Varianti raid: dimensioni per numero di giocatori, healer piu' grandi; layout per variante e ruolo.
local HEALER_RAID = { ["10"] = { 128, 64 }, ["20"] = { 108, 54 }, ["40"] = { 88, 44 } }
local function raidVariants(token, roles)
    local out = {}
    for v, vb in pairs(BASE.raid.variants) do
        local block = { modules = merge({}, vb.modules), byRole = {} }
        for _, role in ipairs(roles) do
            local rb = { editMode = Data.Layout(archFor(token, role), "raid", v) }
            if role == "healer" then
                rb.modules = { GroupFrames = { raidWidth = HEALER_RAID[v][1], raidHeight = HEALER_RAID[v][2], powerBars = true } }
            end
            block.byRole[role] = rb
        end
        out[v] = block
    end
    return out
end

function Data.Build(classInfo, scenario)
    local token, base = classInfo.token, BASE[scenario]
    local mode = base.mode
    local cls = CLASS[token] or {}
    local primary = classInfo.primary
    local roles = classInfo.roles
    local def = {
        key = token:lower() .. "-" .. mode .. "-" .. scenario,
        title = string.format("%s · %s", P.CLASS_NAMES[token] or token, SCEN_NAMES[scenario]),
        description = base.description,
        class = token, mode = mode, scenario = scenario, role = primary,
        version = 1, author = "BadbUI",
        tags = { mode, scenario, token:lower() },
        facts = { FACT[scenario], FACT.editMode, FACT.roles },
        modules = merge(merge({}, base.modules), cls.modules),
        frames = merge({}, base.frames),
        editMode = Data.Layout(archFor(token, primary), scenario, scenario == "raid" and "20" or nil),
        byRole = {},
    }
    if scenario == "raid" then
        def.defaultVariant = base.defaultVariant
        def.variants = raidVariants(token, roles)
    end
    local roleWhy = {}
    for _, role in ipairs(roles) do
        def.byRole[role] = roleBlock(token, role, scenario, mode)
        roleWhy[#roleWhy + 1] = role
    end
    def.rationale = string.format("%s %s %s", base.why, cls.why or "", ROLE[primary].why)
    if #roles > 1 then
        def.rationale = def.rationale .. " Ruoli alternativi della classe: " .. table.concat(roleWhy, ", ") .. "."
    end
    if mode == "pvp" then def.facts[#def.facts + 1] = FACT.world end
    if scenario == "raid" then def.facts[#def.facts + 1] = FACT.secret end
    return def
end

------------------------------------------------------------------------------
-- Registrazione: per ogni classe 3 PvE + 3 PvP, nell'ordine delle classi
------------------------------------------------------------------------------
Data.SCENARIOS = { "dungeon", "raid", "solo", "bg", "av", "world" }
Data.failed = {}
for _, c in ipairs(Player.CLASSES) do
    for _, scenario in ipairs(Data.SCENARIOS) do
        local ok, def = pcall(Data.Build, c, scenario)
        local key, err
        if ok then key, err = P:Register(def) else err = def end
        if not key then Data.failed[#Data.failed + 1] = tostring(c.token) .. "/" .. scenario .. ": " .. tostring(err) end
    end
end

------------------------------------------------------------------------------
-- Layout Edit Mode anche per il wizard (contenuto + ruolo): layout dell'archetipo del ruolo.
------------------------------------------------------------------------------
local WIZARD_SCENARIO = { leveling = "solo", dungeon = "dungeon", raid = "raid", pvp = "bg" }
for content, scenario in pairs(WIZARD_SCENARIO) do
    local spec = P.content[content]
    if spec and spec.editMode == nil then
        spec.editMode = {
            default = Data.Layout("melee", scenario, scenario == "raid" and "20" or nil),
            tank = Data.Layout("tank", scenario, scenario == "raid" and "20" or nil),
            healer = Data.Layout("healer", scenario, scenario == "raid" and "20" or nil),
            dps = Data.Layout("melee", scenario, scenario == "raid" and "20" or nil),
        }
    end
end
