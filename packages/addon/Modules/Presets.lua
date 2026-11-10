-- BadbUI - Preset di interfaccia
-- Un preset e' un'interfaccia completa applicabile in un click: layout Edit Mode (posizione e impostazioni di barre,
-- unit frame, cast bar...) + opzioni dei moduli BadbUI + frame nascosti. Due livelli:
--   * template per classe/modalita'/scenario (Presets:Register, dati in Data/Presets.lua), con override per ruolo
--     e varianti raid 10/20/40: Presets:Apply("mage-pvp-bg", { role =, variant =, mode =, only = });
--   * composizione contenuto + ruolo usata dal wizard (RegisterContent/RegisterRole/Build).
-- Ogni Apply mostra un Diff in anteprima, crea un backup "pre-preset", di default crea un NUOVO profilo
-- e si annulla con Presets:Undo() (/badb undo), layout Edit Mode compreso.
--
-- I preset si compongono: base per tipo di contenuto + ritocchi per ruolo + scelte del wizard.
-- I dati per moduli non ancora caricati (es. UnitFrames, ActionBars sviluppati a parte)
-- restano nel profilo e vengono letti quando quei moduli si registrano.
local _, ns = ...
local L = ns.Badb.L
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
    description = L["Pulito e leggero per quest e mondo aperto: nameplate solo nemiche, interfaccia ordinata."],
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
    description = L["Gruppi da 5: nameplate impilate e sempre visibili, party in stile raid ben leggibili."],
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
    description = L["Molte unita' a schermo: frame raid compatti, solo debuff utili, nameplate essenziali."],
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
    description = L["Battleground e duelli: nameplate grandi con colore di classe, pet e totem nemici visibili."],
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
    description = L["Vedi tutto quello che hai addosso: nameplate piu' grandi e aggro evidente."],
    icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
    modules = {
        Nameplates = { showMinions = true, globalScale = 1.1, minAlpha = 0.75 },
        GroupFrames = { aggroHighlight = true },
    },
})

Presets:RegisterRole("healer", {
    title = "Healer",
    description = L["Frame di gruppo piu' grandi, barre risorse, cure in arrivo e debuff dissipabili."],
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
    description = L["Focus sul bersaglio: scala bersaglio maggiore e unita' secondarie attenuate."],
    icon = "Interface\\Icons\\Ability_DualWield",
    modules = {
        Nameplates = { selectedScale = 1.3, minAlpha = 0.5, targetBorder = true },
        GroupFrames = { powerBars = false },
    },
})

------------------------------------------------------------------------------
-- Utilita'
------------------------------------------------------------------------------
local MAX_DEPTH, MAX_NODES = 12, 5000

-- Copia profonda difensiva: niente cicli, profondita' e numero di nodi limitati, solo chiavi/valori semplici.
local function deepCopy(v, depth, seen, budget)
    if type(v) ~= "table" then return v end
    depth, seen, budget = depth or 0, seen or {}, budget or { n = 0 }
    if depth > MAX_DEPTH then error(L["struttura troppo profonda"]) end
    if seen[v] then error(L["struttura ciclica"]) end
    seen[v] = true
    local out = {}
    for k, val in pairs(v) do
        budget.n = budget.n + 1
        if budget.n > MAX_NODES then error(L["struttura troppo grande"]) end
        local tk, tv = type(k), type(val)
        if (tk == "string" or tk == "number") and (tv == "string" or tv == "number" or tv == "boolean" or tv == "table") then
            out[k] = deepCopy(val, depth + 1, seen, budget)
        end
    end
    seen[v] = nil
    return out
end
Presets.DeepCopy = deepCopy

local function isFiniteNumber(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

local function slug(s)
    s = tostring(s or ""):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    if s == "" then s = "preset" end
    return s:sub(1, 40)
end

local function cleanText(s, max)
    if type(s) ~= "string" then return nil end
    s = s:gsub("[%c]", " "):gsub("|", "/")
    s = strtrim and strtrim(s) or s:match("^%s*(.-)%s*$")
    if s == "" then return nil end
    return s:sub(1, max)
end

local function toSet(list)
    if type(list) ~= "table" then return nil end
    local set, any = {}, false
    for _, v in ipairs(list) do if type(v) == "string" then set[v] = true; any = true end end
    return any and set or nil
end

local function inCombat() return InCombatLockdown and InCombatLockdown() and true or false end

local function editModeOpen()
    local f = EditModeManagerFrame
    if type(f) ~= "table" then return false end
    if type(f.IsEditModeActive) == "function" then
        local ok, v = pcall(f.IsEditModeActive, f)
        if ok and v then return true end
    end
    if type(f.IsShown) == "function" then
        local ok, v = pcall(f.IsShown, f)
        return ok and v == true
    end
    return false
end

------------------------------------------------------------------------------
-- Motore layout Edit Mode dichiarativo
------------------------------------------------------------------------------
-- Un layout si descrive per NOME, mai con numeri Blizzard scritti a mano:
--   { base = "modern"|"classic"|"active", systems = {
--       { system = "UnitFrame", index = "Player", anchor = { "CENTER", "CENTER", -220, -140 },
--         settings = { UseLargerFrame = true } },
--       { system = "ActionBar", index = "MainBar", anchor = { "BOTTOM", "BOTTOM", 0, 24 },
--         settings = { IconSize = 90, NumRows = 1, Orientation = "Horizontal", HideBarArt = true } } } }
-- I nomi si risolvono a runtime negli Enum del client (Enum.EditModeSystem, Enum.EditMode<Sistema>SystemIndices,
-- Enum.EditMode<Sistema>Setting). Cio' che il client non conosce viene SALTATO e riportato, mai inventato:
-- su Forever alcuni sistemi Retail possono mancare. Si modificano solo sistemi e impostazioni gia' presenti nel
-- layout base, cosi' il layout salvato resta sempre completo e valido per Blizzard.
local Layout = {}
Presets.Layout = Layout

local POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }

-- Valori testuali -> Enum del client (solo per le impostazioni a scelta).
local VALUE_ENUMS = {
    Orientation = "ActionBarOrientation",
    VisibleSetting = "ActionBarVisibleSetting",
    RaidGroupDisplayType = "RaidGroupDisplayType",
    SortPlayersBy = "SortPlayersBy",
}

-- Slider: il layout salva un valore "grezzo". Per IconSize/BarSize/FrameSize/Size Blizzard salva
-- (valore - minimo) / passo; per gli altri il valore stesso. Valori in unita' visibili nell'Edit Mode (es. 90 = 90%).
-- Fonte: struttura dei layout preset Mainline (IconSize 100% = 5). Conf. C su Forever: da verificare in gioco.
local SLIDERS = {
    IconSize  = { min = 50, max = 200, step = 10 },
    BarSize   = { min = 100, max = 150, step = 10 },
    FrameSize = { min = 100, max = 200, step = 5 },
    Size      = { min = 50, max = 200, step = 10 },
}
local DIRECT_LIMITS = {
    NumRows = { 1, 4 }, NumIcons = { 6, 12 }, IconPadding = { 2, 10 },
    FrameWidth = { 36, 300 }, FrameHeight = { 18, 200 }, RowSize = { 1, 10 }, ViewRaidSize = { 0, 10 },
}

function Layout.Available()
    return type(C_EditMode) == "table" and type(C_EditMode.GetLayouts) == "function"
        and type(C_EditMode.SaveLayouts) == "function" and type(Enum) == "table"
        and type(Enum.EditModeSystem) == "table"
end

local function enumValue(enumName, key)
    local e = type(Enum) == "table" and Enum[enumName]
    if type(e) ~= "table" then return nil end
    local v = e[key]
    if type(v) == "number" then return v end
end

-- Validazione della SOLA forma (nessuna API del client): usata da Register e dagli import.
function Layout.Validate(spec, where)
    where = where or "editMode"
    if type(spec) == "string" then
        if #spec > 20000 then return false, where .. L[": stringa layout troppo lunga"] end
        return true
    end
    if type(spec) ~= "table" then return false, where .. L[": deve essere una stringa o una tabella"] end
    if spec.base ~= nil and spec.base ~= "modern" and spec.base ~= "classic" and spec.base ~= "active" then
        return false, where .. L[".base non valido (modern|classic|active)"]
    end
    if type(spec.systems) ~= "table" then return false, where .. L[".systems mancante"] end
    local n = 0
    for i, s in pairs(spec.systems) do
        n = n + 1
        if n > 64 then return false, where .. L[": troppi sistemi (max 64)"] end
        local w = where .. ".systems[" .. tostring(i) .. "]"
        if type(i) ~= "number" or type(s) ~= "table" then return false, w .. L[" non valido"] end
        if type(s.system) ~= "string" or not s.system:match("^%a+$") or #s.system > 40 then
            return false, w .. L[".system non valido"]
        end
        if s.index ~= nil and not ((type(s.index) == "string" and s.index:match("^%w+$") and #s.index <= 40)
            or (isFiniteNumber(s.index) and s.index >= 0 and s.index <= 100)) then
            return false, w .. L[".index non valido"]
        end
        if s.anchor ~= nil then
            local a = s.anchor
            if type(a) ~= "table" or not POINTS[a[1]] or not POINTS[a[2]] or not isFiniteNumber(a[3]) or not isFiniteNumber(a[4])
                or math.abs(a[3]) > 4000 or math.abs(a[4]) > 4000 then
                return false, w .. L[".anchor deve essere { punto, puntoRelativo, x, y }"]
            end
        end
        if s.settings ~= nil then
            if type(s.settings) ~= "table" then return false, w .. L[".settings non valido"] end
            local c = 0
            for k, v in pairs(s.settings) do
                c = c + 1
                if c > 32 then return false, w .. L[": troppe impostazioni"] end
                if type(k) ~= "string" or not k:match("^%a+$") or #k > 40 then return false, w .. L[": nome impostazione non valido"] end
                local tv = type(v)
                local okv = tv == "boolean" or isFiniteNumber(v) or (tv == "string" and v:match("^%a+$") and #v <= 40)
                    or (tv == "table" and isFiniteNumber(v.raw))
                if not okv then return false, w .. ".settings." .. k .. L[" valore non valido"] end
            end
        end
    end
    return true
end

-- Converte un valore dichiarato nel valore grezzo da salvare. -> numero | nil, motivo
-- Slider: prima il convertitore dell'Edit Mode del client (come GroupFrames), poi min/passo dichiarati dal client,
-- infine la tabella SLIDERS; gli altri numeri sono salvati cosi' come sono (entro limiti ragionevoli).
local function clientSlider(sysId, setId, v)
    local mgr = EditModeSettingDisplayInfoManager
    local infos = type(mgr) == "table" and type(mgr.systemSettingDisplayInfo) == "table" and mgr.systemSettingDisplayInfo[sysId]
    if type(infos) ~= "table" then return nil end
    for _, info in ipairs(infos) do
        if type(info) == "table" and info.setting == setId then
            if type(info.ConvertValue) == "function" then
                local ok, raw = pcall(info.ConvertValue, info, v, false)
                if ok and isFiniteNumber(raw) then return math.floor(raw + 0.5) end
            end
            if isFiniteNumber(info.minValue) and isFiniteNumber(info.stepSize) and info.stepSize > 0 then
                local lo, hi = info.minValue, isFiniteNumber(info.maxValue) and info.maxValue or math.huge
                return math.floor((math.max(lo, math.min(hi, v)) - lo) / info.stepSize + 0.5)
            end
        end
    end
end

local function rawSettingValue(name, v, sysId, setId)
    if type(v) == "table" then return v.raw end
    if type(v) == "boolean" then return v and 1 or 0 end
    if type(v) == "string" then
        local enumName = VALUE_ENUMS[name]
        local raw = enumName and enumValue(enumName, v)
        if raw == nil then return nil, L["valore '"] .. v .. L["' sconosciuto al client"] end
        return raw
    end
    local fromClient = clientSlider(sysId, setId, v)
    if fromClient then return fromClient end
    local sl = SLIDERS[name]
    if sl then
        local clamped = math.max(sl.min, math.min(sl.max, v))
        return math.floor((clamped - sl.min) / sl.step + 0.5)
    end
    local lim = DIRECT_LIMITS[name]
    if lim then v = math.max(lim[1], math.min(lim[2], v)) end
    return math.floor(v + 0.5)
end

-- Copia del layout base. -> info | nil, err
function Layout.GetBase(baseName)
    local candidates = {}
    local mgr = EditModePresetLayoutManager
    if baseName ~= "active" and type(mgr) == "table" and type(mgr.GetCopyOfPresetLayouts) == "function" then
        local ok, list = pcall(mgr.GetCopyOfPresetLayouts, mgr)
        if ok and type(list) == "table" then
            local presetsEnum = type(Enum) == "table" and Enum.EditModePresetLayouts
            local wanted = baseName == "classic" and "Classic" or "Modern"
            local idx = type(presetsEnum) == "table" and presetsEnum[wanted]
            if type(idx) == "number" and type(list[idx + 1]) == "table" then candidates[#candidates + 1] = list[idx + 1] end
            for _, l in ipairs(list) do candidates[#candidates + 1] = l end
        end
    end
    local ok, layouts = pcall(C_EditMode.GetLayouts)
    if ok and type(layouts) == "table" and type(layouts.layouts) == "table" then
        local n = #layouts.layouts
        local presetCount = (type(Enum) == "table" and type(Enum.EditModePresetLayoutsMeta) == "table"
            and Enum.EditModePresetLayoutsMeta.NumValues) or 2
        local active = layouts.layouts[(tonumber(layouts.activeLayout) or 0) - presetCount]
        if type(active) == "table" then candidates[#candidates + 1] = active end
        if n > 0 then candidates[#candidates + 1] = layouts.layouts[1] end
    end
    for _, c in ipairs(candidates) do
        if type(c) == "table" and type(c.systems) == "table" and #c.systems > 0 then
            local okc, copy = pcall(deepCopy, c)
            if okc then return copy end
        end
    end
    return nil, L["nessun layout Edit Mode di partenza disponibile"]
end

local function findSystem(info, sysId, index)
    for _, s in ipairs(info.systems) do
        if s.system == sysId and (index == nil or s.systemIndex == index) then return s end
    end
end

-- Costruisce un layoutInfo Blizzard dalla specifica. -> info, report | nil, err
-- report = { applied = n, skipped = { "motivo", ... } }
function Layout.Build(spec)
    if not Layout.Available() then return nil, L["Edit Mode non disponibile su questo client"] end
    local okv, err = Layout.Validate(spec)
    if not okv then return nil, err end
    if type(spec) == "string" then
        local ok, info = pcall(C_EditMode.ConvertStringToLayoutInfo, spec)
        if not ok or type(info) ~= "table" then return nil, L["stringa layout Edit Mode non valida"] end
        return info, { applied = 0, skipped = {} }
    end
    local info, berr = Layout.GetBase(spec.base or "modern")
    if not info then return nil, berr end
    local report = { applied = 0, skipped = {} }
    local function skip(fmt, ...) report.skipped[#report.skipped + 1] = string.format(fmt, ...) end
    for _, s in ipairs(spec.systems) do
        local sysId = enumValue("EditModeSystem", s.system)
        local index
        if sysId == nil then
            skip(L["sistema %s assente"], s.system)
        else
            if type(s.index) == "string" then
                index = enumValue("EditMode" .. s.system .. "SystemIndices", s.index)
                if index == nil then skip(L["%s %s assente"], s.system, s.index) end
            elseif type(s.index) == "number" then
                index = s.index
            end
            local target = (s.index == nil or index ~= nil) and findSystem(info, sysId, index) or nil
            if (s.index == nil or index ~= nil) and not target then
                skip(L["%s %s non presente nel layout base"], s.system, tostring(s.index or ""))
            end
            if target then
                if s.anchor then
                    target.anchorInfo = { point = s.anchor[1], relativeTo = "UIParent", relativePoint = s.anchor[2],
                        offsetX = s.anchor[3], offsetY = s.anchor[4] }
                    target.anchorInfo2 = nil
                    target.isInDefaultPosition = false
                end
                if s.settings and type(target.settings) == "table" then
                    local names = {}
                    for name in pairs(s.settings) do names[#names + 1] = name end
                    table.sort(names) -- ordine stabile (report deterministico)
                    for _, name in ipairs(names) do
                        local setId = enumValue("EditMode" .. s.system .. "Setting", name)
                        if setId == nil then
                            skip(L["%s: impostazione %s assente"], s.system, name)
                        else
                            local raw, why = rawSettingValue(name, s.settings[name], sysId, setId)
                            local entry
                            for _, e in ipairs(target.settings) do if e.setting == setId then entry = e end end
                            if raw == nil then skip("%s.%s: %s", s.system, name, why or "?")
                            elseif not entry then skip(L["%s.%s non presente nel layout base"], s.system, name)
                            else entry.value = raw end
                        end
                    end
                end
                report.applied = report.applied + 1
            end
        end
    end
    return info, report
end

local function maxLayouts()
    local c = type(Constants) == "table" and type(Constants.EditModeConsts) == "table" and Constants.EditModeConsts
    return (c and tonumber(c.EditModeMaxLayoutsPerType)) or 5
end

local function accountType()
    return enumValue("EditModeLayoutType", "Account") or 1
end

-- Installa (o sostituisce per nome) un layout tra quelli dell'account. -> record per Uninstall | nil, err
function Layout.Install(info, name)
    local layouts = C_EditMode.GetLayouts()
    if type(layouts) ~= "table" or type(layouts.layouts) ~= "table" then return nil, L["layout Edit Mode non leggibili"] end
    local record = { name = name, prevActive = layouts.activeLayout }
    info.layoutName = name
    local idx
    for i, l in ipairs(layouts.layouts) do if l.layoutName == name then idx = i end end
    if idx then
        record.replaced = deepCopy(layouts.layouts[idx])
        info.layoutType = layouts.layouts[idx].layoutType or accountType()
        layouts.layouts[idx] = info
    else
        local count, acct = 0, accountType()
        for _, l in ipairs(layouts.layouts) do if l.layoutType == acct then count = count + 1 end end
        if count >= maxLayouts() then
            return nil, string.format(L["limite di %d layout Edit Mode dell'account raggiunto: eliminane uno dall'Edit Mode"], maxLayouts())
        end
        info.layoutType = acct
        layouts.layouts[#layouts.layouts + 1] = info
        record.created = true
    end
    C_EditMode.SaveLayouts(layouts)
    return record
end

function Layout.Uninstall(record)
    if type(record) ~= "table" or type(record.name) ~= "string" or not Layout.Available() then return false end
    local layouts = C_EditMode.GetLayouts()
    if type(layouts) ~= "table" or type(layouts.layouts) ~= "table" then return false end
    local idx
    for i, l in ipairs(layouts.layouts) do if l.layoutName == record.name then idx = i end end
    if idx then
        if record.created then table.remove(layouts.layouts, idx)
        elseif type(record.replaced) == "table" then layouts.layouts[idx] = record.replaced end
        C_EditMode.SaveLayouts(layouts)
    end
    if type(record.prevActive) == "number" and type(C_EditMode.SetActiveLayout) == "function" then
        pcall(C_EditMode.SetActiveLayout, record.prevActive)
    end
    return true
end

-- Fonde due specifiche: i sistemi di `b` sostituiscono ancora/impostazioni di quelli di `a` (stesso sistema+indice).
function Layout.Merge(a, b)
    if b == nil then return a end
    if a == nil or type(b) == "string" or type(a) == "string" then return b end
    local out = { base = b.base or a.base, systems = {} }
    local pos = {}
    local function put(s)
        local id = s.system .. ":" .. tostring(s.index)
        local cur = pos[id] and out.systems[pos[id]]
        if not cur then
            cur = { system = s.system, index = s.index }
            out.systems[#out.systems + 1] = cur
            pos[id] = #out.systems
        end
        if s.anchor then cur.anchor = { s.anchor[1], s.anchor[2], s.anchor[3], s.anchor[4] } end
        if s.settings then
            cur.settings = cur.settings or {}
            for k, v in pairs(s.settings) do cur.settings[k] = v end
        end
    end
    for _, s in ipairs(a.systems or {}) do put(s) end
    for _, s in ipairs(b.systems or {}) do put(s) end
    return out
end

------------------------------------------------------------------------------
-- Template (contratto v0.2): Register / Validate / List / Get / Resolve / Diff
------------------------------------------------------------------------------
Presets.templates, Presets.templateOrder = {}, {}
Presets.MODES = { pve = { "dungeon", "raid", "solo" }, pvp = { "bg", "av", "world" } }
Presets.VARIANTS = { "10", "20", "40" }
local SCENARIO_MODE = {}
for mode, list in pairs(Presets.MODES) do for _, s in ipairs(list) do SCENARIO_MODE[s] = mode end end
local VALID_ROLES = { tank = true, healer = true, dps = true }
local VARIANT_OK = { ["10"] = true, ["20"] = true, ["40"] = true }
local MAX_CUSTOM = 50

local function classInfo(token)
    local P = Badb.Player
    if type(P) ~= "table" or type(P.GetClassInfo) ~= "function" then return nil end
    local ok, info = pcall(P.GetClassInfo, P, token)
    return ok and info or nil
end

local function classAllowsRole(token, role)
    if not token then return VALID_ROLES[role] == true end
    local info = classInfo(token)
    if not info then return VALID_ROLES[role] == true end
    for _, r in ipairs(info.roles or {}) do if r == role then return true end end
    return false
end

-- Confronta le opzioni con i default del modulo (chiavi esistenti, tipi coerenti, tabelle annidate).
-- strict=false: invece di fallire scarta la voce e la annota (import di preset utente).
local function checkOptions(opts, defaults, where, errs, strict, depth)
    local clean = {}
    if depth > 6 then errs[#errs + 1] = where .. L[": troppo annidato"]; return clean end
    for k, v in pairs(opts) do
        local w = where .. "." .. tostring(k)
        local d
        if type(k) == "string" then d = defaults[k] end
        local bad
        if d == nil then bad = L["non e' un'opzione del modulo"]
        elseif type(d) == "table" then
            if type(v) ~= "table" then bad = L["deve essere una tabella"]
            else clean[k] = checkOptions(v, d, w, errs, strict, depth + 1) end
        elseif type(v) ~= type(d) then bad = L["tipo "] .. type(v) .. L[", atteso "] .. type(d)
        elseif type(v) == "number" and not isFiniteNumber(v) then bad = L["numero non valido"]
        elseif type(v) == "string" and #v > 64 then bad = L["stringa troppo lunga"]
        else clean[k] = v end
        if bad then errs[#errs + 1] = w .. ": " .. bad end
    end
    return clean
end

local function checkModules(mods, where, errs, strict)
    local clean = {}
    if mods == nil then return clean end
    if type(mods) ~= "table" then errs[#errs + 1] = where .. L[".modules deve essere una tabella"]; return clean end
    for name, opts in pairs(mods) do
        local w = where .. ".modules." .. tostring(name)
        local m = type(name) == "string" and Badb.Modules:Get(name) or nil
        if name == "EditModeBridge" then errs[#errs + 1] = w .. L[": usa il campo editMode per il layout"]
        elseif not m then errs[#errs + 1] = w .. L[": modulo sconosciuto"]
        elseif type(opts) ~= "table" then errs[#errs + 1] = w .. L[" deve essere una tabella"]
        else clean[name] = checkOptions(opts, m.defaults or {}, w, errs, strict, 0) end
    end
    return clean
end

local FRAME_FIELDS = { hidden = "boolean", alpha = "number", scale = "number" }
local function checkFrames(frames, where, errs)
    local clean = {}
    if frames == nil then return clean end
    if type(frames) ~= "table" then errs[#errs + 1] = where .. L[".frames deve essere una tabella"]; return clean end
    for key, f in pairs(frames) do
        local w = where .. ".frames." .. tostring(key)
        if type(key) ~= "string" or not key:match("^[%w_]+$") or #key > 64 or type(f) ~= "table" then
            errs[#errs + 1] = w .. L[" non valido"]
        else
            clean[key] = {}
            for field, v in pairs(f) do
                if FRAME_FIELDS[field] ~= type(v) or (type(v) == "number" and (not isFiniteNumber(v) or v < 0 or v > 3)) then
                    errs[#errs + 1] = w .. "." .. tostring(field) .. L[" non valido"]
                else clean[key][field] = v end
            end
        end
    end
    return clean
end

-- Controlla un blocco { modules, frames, editMode, byRole?, variants? }.
local function checkBlock(b, where, errs, strict, def, allowNested)
    if type(b) ~= "table" then errs[#errs + 1] = where .. L[" deve essere una tabella"]; return {} end
    local out = { modules = checkModules(b.modules, where, errs, strict), frames = checkFrames(b.frames, where, errs) }
    if b.editMode ~= nil then
        local ok, err = Layout.Validate(b.editMode, where .. ".editMode")
        if ok then out.editMode = b.editMode else errs[#errs + 1] = err end
    end
    if b.byRole ~= nil then
        if type(b.byRole) ~= "table" then errs[#errs + 1] = where .. L[".byRole deve essere una tabella"]
        else
            out.byRole = {}
            for role, rb in pairs(b.byRole) do
                if not VALID_ROLES[role] then errs[#errs + 1] = where .. ".byRole." .. tostring(role) .. L[": ruolo sconosciuto"]
                elseif not classAllowsRole(def.class, role) then
                    errs[#errs + 1] = where .. ".byRole." .. role .. L[": ruolo non disponibile per "] .. tostring(def.class)
                else out.byRole[role] = checkBlock(rb, where .. ".byRole." .. role, errs, strict, def, false) end
            end
        end
    end
    if b.variants ~= nil then
        if not allowNested then errs[#errs + 1] = where .. L[".variants non ammesso qui"]
        elseif def.scenario ~= "raid" then errs[#errs + 1] = where .. L[".variants ammesso solo per lo scenario raid"]
        elseif type(b.variants) ~= "table" then errs[#errs + 1] = where .. L[".variants deve essere una tabella"]
        else
            out.variants = {}
            for v, vb in pairs(b.variants) do
                if not VARIANT_OK[v] then errs[#errs + 1] = where .. ".variants." .. tostring(v) .. L[": usa 10, 20 o 40"]
                else out.variants[v] = checkBlock(vb, where .. ".variants." .. v, errs, strict, def, false) end
            end
        end
    end
    return out
end

-- -> def normalizzato, errori (lista). def normalizzato e' nil se ci sono errori in modalita' strict.
local function normalize(def, strict)
    local errs = {}
    if type(def) ~= "table" then return nil, { L["il preset deve essere una tabella"] } end
    local ok, copy = pcall(deepCopy, def)
    if not ok then return nil, { L["preset non valido: "] .. tostring(copy) } end
    def = copy
    local where = "preset"
    if type(def.key) ~= "string" or not def.key:match("^[%w%-_]+$") or #def.key > 64 then
        errs[#errs + 1] = L["key mancante o non valida (lettere, numeri, - e _; max 64)"]
    else where = def.key end
    local out = { key = def.key, version = isFiniteNumber(def.version) and def.version or 1, custom = def.custom == true }
    out.title = cleanText(def.title, 64)
    if not out.title then errs[#errs + 1] = where .. L[": title mancante"] end
    out.description = cleanText(def.description, 300)
    out.rationale = cleanText(def.rationale, 400)
    out.author = cleanText(def.author, 48)
    out.icon = type(def.icon) == "string" and #def.icon <= 200 and def.icon or nil
    if def.class ~= nil then
        if type(def.class) ~= "string" or not def.class:match("^%u+$") then errs[#errs + 1] = where .. L[": class non valida"]
        elseif Badb.Player and not classInfo(def.class) then errs[#errs + 1] = where .. L[": classe sconosciuta "] .. def.class
        else out.class = def.class end
    end
    if def.mode ~= nil and not Presets.MODES[def.mode] then errs[#errs + 1] = where .. L[": mode deve essere pve o pvp"]
    else out.mode = def.mode end
    if def.scenario ~= nil then
        if not SCENARIO_MODE[def.scenario] then errs[#errs + 1] = where .. L[": scenario sconosciuto "] .. tostring(def.scenario)
        elseif def.mode and SCENARIO_MODE[def.scenario] ~= def.mode then errs[#errs + 1] = where .. L[": scenario incoerente con mode"]
        else out.scenario = def.scenario end
    end
    if def.role ~= nil then
        if def.role ~= "any" and not VALID_ROLES[def.role] then errs[#errs + 1] = where .. L[": ruolo sconosciuto"]
        elseif VALID_ROLES[def.role] and not classAllowsRole(def.class or out.class, def.role) then
            errs[#errs + 1] = where .. L[": ruolo non disponibile per la classe"]
        else out.role = def.role end
    end
    if def.defaultVariant ~= nil then
        if not VARIANT_OK[def.defaultVariant] then errs[#errs + 1] = where .. L[": defaultVariant non valido"]
        else out.defaultVariant = def.defaultVariant end
    end
    out.tags, out.facts = {}, {}
    for _, f in ipairs({ "tags", "facts" }) do
        if type(def[f]) == "table" then
            for _, t in ipairs(def[f]) do
                local s = cleanText(t, 120)
                if s and #out[f] < 16 then out[f][#out[f] + 1] = s end
            end
        end
    end
    local block = checkBlock(def, where, errs, strict, out, true)
    out.modules, out.frames, out.editMode, out.byRole, out.variants =
        block.modules, block.frames, block.editMode, block.byRole, block.variants
    if strict and #errs > 0 then return nil, errs end
    return out, errs
end

function Presets:Validate(def)
    local ok, out, errs = pcall(normalize, def, true)
    if not ok then return false, { tostring(out) } end
    return out ~= nil, errs
end

-- Registra (o sostituisce per key) un template. -> key | nil, err
function Presets:Register(def)
    local ok, out, errs = pcall(normalize, def, true)
    if not ok then return nil, tostring(out) end
    if not out then
        Logger:Warn(L["Preset non valido: %s"], errs[1] or "?")
        return nil, table.concat(errs, "; ")
    end
    if not self.templates[out.key] then self.templateOrder[#self.templateOrder + 1] = out.key end
    self.templates[out.key] = out
    return out.key
end

function Presets:Unregister(key)
    if not self.templates[key] then return false end
    self.templates[key] = nil
    for i = #self.templateOrder, 1, -1 do if self.templateOrder[i] == key then table.remove(self.templateOrder, i) end end
    return true
end

function Presets:Get(key)
    if type(key) ~= "string" then return nil end
    return self.templates[key]
end

local function roleMatches(def, role)
    if def.role == role then return true end
    return def.byRole ~= nil and def.byRole[role] ~= nil
end

-- filter = { class=, mode=, scenario=, role=, tag=, search=, custom= }
function Presets:List(filter)
    filter = type(filter) == "table" and filter or {}
    local out = {}
    local search = type(filter.search) == "string" and filter.search:lower() or nil
    for _, key in ipairs(self.templateOrder) do
        local d = self.templates[key]
        local keep = d ~= nil
        if keep and filter.class and d.class ~= nil and d.class ~= filter.class then keep = false end
        if keep and filter.class and filter.strictClass and d.class ~= filter.class then keep = false end
        if keep and filter.mode and d.mode ~= filter.mode then keep = false end
        if keep and filter.scenario and d.scenario ~= filter.scenario then keep = false end
        if keep and filter.role and not roleMatches(d, filter.role) then keep = false end
        if keep and filter.custom ~= nil and (d.custom == true) ~= (filter.custom == true) then keep = false end
        if keep and filter.tag then
            local found = false
            for _, t in ipairs(d.tags) do if t == filter.tag then found = true end end
            keep = found
        end
        if keep and search then
            local hay = (d.key .. " " .. d.title .. " " .. (d.description or "")):lower()
            keep = hay:find(search, 1, true) ~= nil
        end
        if keep then out[#out + 1] = d end
    end
    return out
end

local function playerRole()
    local P = Badb.Player
    if type(P) == "table" and type(P.GetRole) == "function" then
        local ok, role, source, confidence = pcall(P.GetRole, P)
        if ok and VALID_ROLES[role] then return role, source, confidence end
    end
end

local function raidSizeVariant()
    local n = 0
    if GetNumGroupMembers then
        local ok, v = pcall(GetNumGroupMembers)
        if ok and isFiniteNumber(v) and not Badb.Compat.IsSecret(v) then n = v end
    end
    if n == 0 then return nil end
    if n <= 10 then return "10" elseif n <= 20 then return "20" end
    return "40"
end

local function mergeBlock(r, b)
    if type(b) ~= "table" then return end
    if b.modules then deepMerge(r.modules, deepCopy(b.modules)) end
    if b.frames then deepMerge(r.frames, deepCopy(b.frames)) end
    if b.editMode ~= nil then r.editMode = Layout.Merge(r.editMode, b.editMode) end
end

-- Calcola il preset effettivo: template -> byRole[ruolo] -> variante -> variante.byRole[ruolo].
-- opts = { role=, variant= }. -> resolved | nil, err
function Presets:Resolve(key, opts)
    local def = self:Get(key)
    if not def then return nil, L["preset sconosciuto: "] .. tostring(key) end
    opts = type(opts) == "table" and opts or {}
    local role = VALID_ROLES[opts.role] and opts.role or nil
    if role and not classAllowsRole(def.class, role) then role = nil end
    local source = role and "scelto" or nil
    if not role then
        local pr = playerRole()
        if pr and classAllowsRole(def.class, pr) then role, source = pr, "rilevato" end
    end
    if not role then role, source = VALID_ROLES[def.role] and def.role or "dps", "template" end
    local variant
    if def.scenario == "raid" then
        variant = VARIANT_OK[opts.variant] and opts.variant or raidSizeVariant() or def.defaultVariant or "20"
    end
    local r = { key = def.key, title = def.title, role = role, roleSource = source, variant = variant,
        modules = {}, frames = {}, editMode = nil }
    mergeBlock(r, def)
    if def.byRole then mergeBlock(r, def.byRole[role]) end
    local vb = variant and def.variants and def.variants[variant]
    if vb then
        mergeBlock(r, vb)
        if vb.byRole then mergeBlock(r, vb.byRole[role]) end
    end
    if variant then r.title = string.format("%s %s", def.title, variant) end
    return r
end

local function flatten(prefix, t, out, depth)
    depth = depth or 0
    if depth > 8 then return out end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        local v, path = t[k], prefix == "" and tostring(k) or (prefix .. "." .. tostring(k))
        if type(v) == "table" then flatten(path, v, out, depth + 1) else out[#out + 1] = { path = path, value = v } end
    end
    return out
end

local function allowed(only, name) return only == nil or only[name] == true end

-- Anteprima: cosa cambierebbe applicando il preset al profilo attivo, senza toccare nulla.
-- -> { {module=, path=, from=, to=}, ... } | nil, err.  module = "frames" per i frame, "EditMode" per il layout.
function Presets:Diff(key, opts)
    local ok, res, err = pcall(function()
        local r, e = self:Resolve(key, opts)
        if not r then return nil, e end
        local only = toSet(type(opts) == "table" and opts.only or nil)
        local profile = DB.profile or {}
        local out = {}
        local mods = {}
        for name in pairs(r.modules) do mods[#mods + 1] = name end
        table.sort(mods)
        for _, name in ipairs(mods) do
            if allowed(only, name) then
                local cur = profile.modules and profile.modules[name] or {}
                for _, leaf in ipairs(flatten("", r.modules[name], {})) do
                    local from = Badb.GetPath(cur, leaf.path)
                    if from ~= leaf.value then out[#out + 1] = { module = name, path = leaf.path, from = from, to = leaf.value } end
                end
            end
        end
        if allowed(only, "frames") then
            for _, leaf in ipairs(flatten("", r.frames, {})) do
                local from = Badb.GetPath(profile.frames or {}, leaf.path)
                if from ~= leaf.value then out[#out + 1] = { module = "frames", path = leaf.path, from = from, to = leaf.value } end
            end
        end
        if r.editMode ~= nil and allowed(only, "EditMode") then
            local bridge = profile.modules and profile.modules.EditModeBridge or {}
            local n = type(r.editMode) == "table" and #r.editMode.systems or 0
            out[#out + 1] = { module = "EditMode", path = "layout", from = bridge.layoutName,
                to = string.format("Badb - %s (%s)", r.title, n > 0 and (n .. L[" elementi posizionati"]) or L["stringa"]) }
        end
        return out
    end)
    if not ok then return nil, tostring(res) end
    return res, err
end

-- Riepilogo leggibile di un Diff (per anteprime e TextBox).
function Presets:FormatDiff(diff, max)
    if type(diff) ~= "table" then return "" end
    max = max or 200
    local lines = {}
    for i, d in ipairs(diff) do
        if i > max then lines[#lines + 1] = string.format(L["... e altre %d modifiche"], #diff - max); break end
        lines[#lines + 1] = string.format("%s.%s: %s -> %s", tostring(d.module), tostring(d.path), tostring(d.from), tostring(d.to))
    end
    if #lines == 0 then lines[1] = L["Nessuna modifica: il profilo e' gia' allineato al preset."] end
    return table.concat(lines, "\n")
end

------------------------------------------------------------------------------
-- Applicazione (template per key e specifiche del wizard)
------------------------------------------------------------------------------
local CLUTTER = { "MicroMenu", "BagsBar", "StatusTracking" }
local APPLY_MODES = { ["new-profile"] = true, merge = true, replace = true }

local function uniqueProfileName(base)
    local name, n = base, 2
    while DB.sv.profiles[name] do name = string.format("%s (%d)", base, n); n = n + 1 end
    return name
end

local function backup(label)
    local B = Badb.Backups
    if type(B) ~= "table" or type(B.Create) ~= "function" then return nil end
    local ok, id = pcall(B.Create, B, label, "pre-preset")
    return ok and id or nil
end

-- Nucleo comune: r = { key?, title, modules, frames, editMode }, opts = { mode, profileName, only }.
-- -> nomeProfilo, report | nil, err. Annulla ogni modifica se un passo fallisce.
local function applyResolved(self, r, opts)
    opts = opts or {}
    if inCombat() then return nil, L["impossibile applicare un preset in combattimento"] end
    if editModeOpen() then return nil, L["chiudi l'Edit Mode prima di applicare un preset"] end
    local mode = opts.mode or "new-profile"
    if not APPLY_MODES[mode] then return nil, L["modalita' non valida: "] .. tostring(mode) end
    local only = toSet(opts.only)
    local report = { warnings = {}, layout = nil, backup = nil }

    report.backup = backup(L["Prima del preset "] .. tostring(r.title))
    local previous = DB:GetProfileName()
    local target, created, snapshot, layoutRecord
    local ok, err = pcall(function()
        if mode == "new-profile" then
            local base = cleanText(opts.profileName, 48) or ("Badb - " .. tostring(r.title or "Preset"))
            target = uniqueProfileName(base)
            assert(DB:CopyProfile(previous, target))
            created = true
        else
            target = previous
            snapshot = Badb.CopyTable(DB.sv.profiles[target]) -- dato interno: copia senza limiti
        end
        local p = DB.sv.profiles[target]
        p.modules, p.frames = p.modules or {}, p.frames or {}
        for name, o in pairs(r.modules or {}) do
            if allowed(only, name) then
                if mode == "replace" then p.modules[name] = deepCopy(DB.defaults.modules[name] or {}) end
                p.modules[name] = deepMerge(type(p.modules[name]) == "table" and p.modules[name] or {}, deepCopy(o))
            end
        end
        if allowed(only, "frames") then
            local anyHidden = false
            for key, f in pairs(r.frames or {}) do
                if mode == "replace" then p.frames[key] = {} end
                p.frames[key] = deepMerge(type(p.frames[key]) == "table" and p.frames[key] or {}, deepCopy(f))
                if f.hidden then anyHidden = true end
            end
            if anyHidden then
                p.modules.Hider = type(p.modules.Hider) == "table" and p.modules.Hider or {}
                p.modules.Hider.enabled = true
            end
        end
        if r.editMode ~= nil and allowed(only, "EditMode") then
            local layoutName = created and target or ("Badb - " .. tostring(r.title or "Preset"))
            local layoutString
            if type(r.editMode) == "string" then
                -- Stringa ufficiale: la conserva comunque, l'EditModeBridge la ricrea/attiva al cambio profilo.
                layoutString = r.editMode
            end
            if type(r.editMode) == "table" or Layout.Available() then
                local info, rep = Layout.Build(r.editMode)
                if not info then
                    if not layoutString then
                        report.warnings[#report.warnings + 1] = L["Layout Edit Mode saltato: "] .. tostring(rep)
                    end
                else
                    report.layout = rep
                    local rec, ierr = Layout.Install(info, layoutName)
                    if not rec then
                        report.warnings[#report.warnings + 1] = L["Layout Edit Mode non installato: "] .. tostring(ierr)
                    else
                        layoutRecord = rec
                        if type(r.editMode) == "string" then layoutString = r.editMode
                        elseif type(C_EditMode.ConvertLayoutInfoToString) == "function" then
                            local okS, s = pcall(C_EditMode.ConvertLayoutInfoToString, info)
                            if okS and type(s) == "string" then layoutString = s end
                        end
                    end
                end
            end
            if layoutRecord or layoutString then
                local bridge = type(p.modules.EditModeBridge) == "table" and p.modules.EditModeBridge or {}
                p.modules.EditModeBridge = bridge
                bridge.enabled, bridge.autoActivate = true, true
                bridge.layoutName, bridge.layoutString = layoutName, layoutString
            end
        end
        DB.sv.global.presetUndo = { profile = previous, target = target, mode = mode, key = r.key,
            snapshot = snapshot, layout = layoutRecord, created = created, time = time and time() or 0 }
        DB:SetProfile(target)
        if layoutRecord then
            -- Attiva subito il layout installato (l'EditModeBridge lo fa gia' al cambio profilo: e' idempotente).
            local bridge = Badb.Modules:Get("EditModeBridge")
            if bridge and type(bridge.Activate) == "function" then pcall(bridge.Activate, bridge) end
        end
    end)
    if not ok then
        -- Rollback: nessuno stato a meta'.
        pcall(function()
            if layoutRecord then Layout.Uninstall(layoutRecord) end
            if created and target and target ~= previous then DB.sv.profiles[target] = nil end
            if snapshot then DB.sv.profiles[target] = snapshot end
            DB.sv.global.presetUndo = nil
            if DB:GetProfileName() ~= previous or snapshot then DB:SetProfile(previous) end
        end)
        Logger:Error(L["Preset '%s' non applicato: %s"], tostring(r.title), tostring(err))
        return nil, tostring(err)
    end
    for _, w in ipairs(report.warnings) do Logger:Warn("%s", w) end
    if report.layout and #report.layout.skipped > 0 then
        Logger:Debug(L["Layout: %d elementi saltati (%s)"], #report.layout.skipped, table.concat(report.layout.skipped, ", "))
    end
    return target, report
end

local function pickLayout(def, roleId)
    if type(def) == "string" then return def end
    if type(def) == "table" then
        if def.systems then return def end
        return def[roleId] or def.default
    end
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
    local roleLayout = pickLayout(r and r.editMode, r and r.id)
    local contentLayout = pickLayout(c and c.editMode, r and r.id)
    if type(roleLayout) == "table" and type(contentLayout) == "table" then
        spec.editMode = Layout.Merge(contentLayout, roleLayout)
    else
        spec.editMode = roleLayout or contentLayout
    end
    return spec
end

-- Elenco leggibile delle modifiche, per il riepilogo del wizard.
function Presets:Describe(spec)
    local lines = {}
    local function add(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end
    local mods = spec.modules or {}
    local np, gf, sc = mods.Nameplates, mods.GroupFrames, mods.Scaling
    if np then
        add(L["Nameplate %s, %s, scala %.0f%%"], np.stacking == "overlap" and L["sovrapposte"] or L["impilate"],
            np.showFriends and L["nemici + alleati"] or L["solo nemici"], (np.globalScale or 1) * 100)
        if np.showMinions then add(L["Pet, totem e guardiani nemici visibili"]) end
    end
    if gf then
        add("Party %dx%d, raid %dx%d (layout Edit Mode)", gf.partyWidth or 120, gf.partyHeight or 60,
            gf.raidWidth or 90, gf.raidHeight or 45)
        if gf.powerBars then add(L["Barre risorse sui frame di gruppo"]) end
        if gf.onlyDispellable then add(L["Solo debuff dissipabili"]) end
    end
    local na, al = spec.modules.NameplateAuras, spec.modules.Alerts
    if na and na.enabled then
        add(L["Aure curate sulle nameplate: CC grande, difensivi nemici, i tuoi debuff %s"],
            na.ownDebuffs == "all" and "(tutti)" or L["curati per classe"])
    end
    if al and al.enabled and al.healerCC then add(L["Avviso quando l'healer del gruppo finisce in CC"]) end
    if sc and sc.enabled then add(sc.pixelPerfect and L["Scala UI pixel perfect"] or L["Scala UI manuale"]) end
    if spec.editMode then
        local n = type(spec.editMode) == "table" and spec.editMode.systems and #spec.editMode.systems or 0
        if n > 0 then add(L["Layout Edit Mode dedicato: %d elementi posizionati (barre, unit frame, cast bar)"], n)
        else add(L["Layout Edit Mode dedicato (posizioni di barre e frame)"]) end
    end
    if spec.hideClutter then add(L["Nasconde micro menu, barra borse e barra esperienza"]) end
    return lines
end

-- Applica un preset.
--   Presets:Apply("druid-pve-raid", { role = "healer", variant = "40", mode = "new-profile"|"merge"|"replace",
--                                    profileName = "...", only = { "GroupFrames", "frames", "EditMode" } })
--   Presets:Apply(spec)  -- specifica composta dal wizard (Presets:Build): crea sempre un nuovo profilo.
-- -> nomeProfilo, report | nil, err. Non lancia mai errori.
function Presets:Apply(keyOrSpec, opts)
    if type(keyOrSpec) == "table" then
        local spec = keyOrSpec
        local r = { title = spec.title or "Preset", modules = spec.modules or {}, frames = {}, editMode = spec.editMode }
        if spec.hideClutter then
            for _, key in ipairs(CLUTTER) do r.frames[key] = { hidden = true } end
        end
        local okc, name, report = pcall(applyResolved, self, r, { mode = "new-profile" })
        if not okc then Logger:Error("Preset: %s", tostring(name)); return nil, tostring(name) end
        if not name then Logger:Warn("Preset: %s", tostring(report)); return nil, report end
        Logger:Info(L["Preset applicato: profilo '%s' (annulla con /badb undo)"], name)
        Events:Fire("BADB_PRESET_APPLIED", name, spec)
        return name, report
    end
    local okr, r, rerr = pcall(self.Resolve, self, keyOrSpec, opts)
    if not okr then return nil, tostring(r) end
    if not r then Logger:Warn("Preset: %s", tostring(rerr)); return nil, rerr end
    local okc, name, report = pcall(applyResolved, self, r, opts)
    if not okc then Logger:Error("Preset: %s", tostring(name)); return nil, tostring(name) end
    if not name then Logger:Warn("Preset: %s", tostring(report)); return nil, report end
    local mode = type(opts) == "table" and opts.mode or "new-profile"
    Logger:Info(L["Preset '%s' (%s) applicato al profilo '%s' (annulla con /badb undo)"], r.title, r.role, name)
    Events:Fire("BADB_PRESET_APPLIED", r.key, mode, name)
    return name, report
end

function Presets:CanUndo()
    local u = DB.sv and DB.sv.global.presetUndo
    if type(u) == "string" then return DB.sv.profiles[u] ~= nil end
    if type(u) ~= "table" or type(u.profile) ~= "string" then return false end
    return DB.sv.profiles[u.profile] ~= nil or type(u.snapshot) == "table"
end

-- Ripristina lo stato precedente all'ultimo Apply: profilo attivo, opzioni (modi merge/replace) e layout Edit Mode.
function Presets:Undo()
    if not self:CanUndo() then Logger:Info(L["Nessun preset da annullare"]); return nil, L["nessun preset da annullare"] end
    if inCombat() then return nil, L["impossibile annullare in combattimento"] end
    local u = DB.sv.global.presetUndo
    DB.sv.global.presetUndo = nil
    if type(u) == "string" then
        DB:SetProfile(u)
        Logger:Info(L["Tornato al profilo '%s'"], u)
        Events:Fire("BADB_PRESET_UNDONE", nil)
        return true
    end
    local ok, err = pcall(function()
        if type(u.snapshot) == "table" then DB.sv.profiles[u.profile] = Badb.CopyTable(u.snapshot) end
        if u.layout then Layout.Uninstall(u.layout) end
        DB:SetProfile(u.profile)
    end)
    if not ok then Logger:Error(L["Annulla preset: %s"], tostring(err)); return nil, tostring(err) end
    Logger:Info(L["Tornato al profilo '%s'"], u.profile)
    Events:Fire("BADB_PRESET_UNDONE", u.key)
    return true
end

------------------------------------------------------------------------------
-- Raccomandazioni
------------------------------------------------------------------------------
-- Scelte del wizard (contenuto + ruolo) in base al personaggio: usata da "Applica consigliato".
function Presets:Recommend()
    local role = playerRole()
    if not role then
        -- Senza Badb.Player (solo ambienti ridotti) si legge il ruolo assegnato dal client.
        local assigned
        local spec = GetSpecialization and GetSpecialization()
        assigned = spec and GetSpecializationRole and GetSpecializationRole(spec)
        if not assigned and UnitGroupRolesAssigned then assigned = UnitGroupRolesAssigned("player") end
        role = (assigned == "TANK" and "tank") or (assigned == "HEALER" and "healer") or "dps"
    end
    local level = UnitLevel("player") or 1
    local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 60
    local content = level < maxLevel and "leveling" or (IsInRaid() and "raid" or "dungeon")
    return { content = content, role = role, pixelPerfect = true, hideClutter = false, friendlyPlates = false }
end

local function probe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local res = { pcall(fn, ...) }
    if not res[1] then return nil end
    return unpack(res, 2, 6)
end

-- Template consigliato per classe + contesto attuale. -> key, opts { role, variant }, motivo | nil, err
-- BG/AV/World PvP -> pvp; istanza raid -> raid (variante per dimensione); gruppo/istanza -> dungeon; altrimenti solo.
function Presets:RecommendTemplate()
    local P = Badb.Player
    local class = type(P) == "table" and type(P.GetClass) == "function" and probe(P.GetClass, P) or nil
    if type(class) ~= "string" then return nil, L["classe del personaggio non disponibile"] end
    local ctx
    local C = Badb.Contexts
    if type(C) == "table" and type(C.GetCurrent) == "function" then
        local ok, c = pcall(C.GetCurrent, C)
        if ok and type(c) == "table" then ctx = c end
    end
    local instance = ctx and ctx.instance
    if instance == nil then
        local inInst, kind = probe(IsInInstance)
        instance = inInst and kind or "none"
    end
    local scenario, variant, why
    if instance == "pvp" or instance == "arena" then
        local _, _, _, _, maxPlayers = probe(GetInstanceInfo)
        if isFiniteNumber(maxPlayers) and not Badb.Compat.IsSecret(maxPlayers) and maxPlayers >= 40 then
            scenario, why = "av", L["campo di battaglia da 40 (Alterac Valley)"]
        else
            scenario, why = "bg", L["campo di battaglia"]
        end
    elseif instance == "raid" then
        local _, _, _, _, maxPlayers = probe(GetInstanceInfo)
        if isFiniteNumber(maxPlayers) and not Badb.Compat.IsSecret(maxPlayers) then
            variant = maxPlayers <= 10 and "10" or (maxPlayers <= 20 and "20" or "40")
        end
        variant = variant or raidSizeVariant()
        scenario, why = "raid", L["istanza raid"]
    elseif instance == "party" or instance == "scenario" then
        scenario, why = "dungeon", "dungeon"
    else
        local flagged = probe(UnitIsPVP, "player")
        local resting = probe(IsResting)
        local grouped = (ctx and ctx.group and ctx.group ~= "solo") or probe(IsInGroup)
        if flagged == true and not resting then scenario, why = "world", L["flag PvP attivo nel mondo"]
        elseif grouped then scenario, why = "dungeon", L["in gruppo"]
        else scenario, why = "solo", L["da solo"] end
    end
    local mode = SCENARIO_MODE[scenario]
    local key = class:lower() .. "-" .. mode .. "-" .. scenario
    if not self.templates[key] then return nil, L["nessun template per "] .. key end
    return key, { role = playerRole(), variant = variant }, why
end

------------------------------------------------------------------------------
-- Preset utente: salva, esporta, importa (stringhe BADB tipizzate "preset")
------------------------------------------------------------------------------
local function customStore()
    local g = DB.sv.global
    if type(g.customPresets) ~= "table" then g.customPresets = {} end
    return g.customPresets
end

local function countCustom()
    local n = 0
    for _ in pairs(customStore()) do n = n + 1 end
    return n
end

-- Cattura lo stato attuale come definizione di preset (solo opzioni note dei moduli, layout Edit Mode come stringa).
local function captureCurrent(name, desc, role)
    local profile = DB.profile or {}
    local def = { title = cleanText(name, 48) or L["Preset personale"], description = cleanText(desc, 300),
        role = VALID_ROLES[role] and role or "any", modules = {}, frames = {}, version = 1, custom = true,
        author = UnitName and probe(UnitName, "player") or nil }
    local errs = {}
    for modName, opts in pairs(profile.modules or {}) do
        local m = Badb.Modules:Get(modName)
        if m and modName ~= "EditModeBridge" and modName ~= "Presets" and type(opts) == "table" then
            def.modules[modName] = checkOptions(deepCopy(opts), m.defaults or {}, modName, errs, false, 0)
        end
    end
    def.frames = checkFrames(deepCopy(profile.frames or {}), "frames", errs)
    local bridge = profile.modules and profile.modules.EditModeBridge
    if type(bridge) == "table" and type(bridge.layoutString) == "string" and #bridge.layoutString <= 20000 then
        def.editMode = bridge.layoutString
    end
    return def
end

local function storeCustom(self, def)
    local store = customStore()
    local base = "custom-" .. slug(def.title)
    local key, n = base, 2
    while self.templates[key] and not (store[key] and store[key].title == def.title) do
        key = base .. "-" .. n; n = n + 1
    end
    if not store[key] and countCustom() >= MAX_CUSTOM then return nil, L["troppi preset personali (max "] .. MAX_CUSTOM .. ")" end
    def.key, def.custom = key, true
    local ok, err = self:Register(def)
    if not ok then return nil, err end
    store[key] = deepCopy(def)
    return key
end

-- Salva lo stato attuale come preset personale (riapplicabile da questa o altre classi). -> key | nil, err
function Presets:SaveCustom(name, desc, role)
    local ok, key, err = pcall(function() return storeCustom(self, captureCurrent(name, desc, role)) end)
    if not ok then return nil, tostring(key) end
    return key, err
end

-- Stringa condivisibile dello stato attuale. -> stringa | nil, err
function Presets:ExportCustom(name, desc, role)
    local ok, str = pcall(function()
        local def = captureCurrent(name, desc, role)
        def.key = "custom-" .. slug(def.title)
        return Badb.Serializer:Export("preset", def)
    end)
    if not ok then return nil, tostring(str) end
    return str
end

-- Esporta un template registrato (bundled o personale) cosi' com'e'.
function Presets:Export(key)
    local def = self:Get(key)
    if not def then return nil, L["preset sconosciuto"] end
    local ok, str = pcall(Badb.Serializer.Export, Badb.Serializer, "preset", def)
    if not ok then return nil, tostring(str) end
    return str
end

-- Importa un preset condiviso: opzioni sconosciute scartate (report), mai codice eseguito. -> key, scartati | nil, err
function Presets:ImportCustom(str)
    if type(str) ~= "string" or str == "" then return nil, L["stringa vuota"] end
    if #str > 200000 then return nil, L["stringa troppo lunga"] end
    local okI, data, err = pcall(Badb.Serializer.Import, Badb.Serializer, str, "preset")
    if not okI then return nil, tostring(data) end
    if type(data) ~= "table" then return nil, err or L["stringa non valida"] end
    local ok, def, dropped = pcall(normalize, data, false)
    if not ok then return nil, tostring(def) end
    if not def then return nil, (dropped and dropped[1]) or L["preset non valido"] end
    if not def.title then def.title = L["Preset importato"] end
    -- Un preset importato non porta byRole/varianti di ruoli che la classe non ha: normalize li ha gia' scartati.
    local okS, key, serr = pcall(storeCustom, self, def)
    if not okS then return nil, tostring(key) end
    if not key then return nil, serr end
    if dropped and #dropped > 0 then Logger:Warn(L["Import preset: %d voci scartate (%s)"], #dropped, dropped[1]) end
    return key, dropped or {}
end

function Presets:DeleteCustom(key)
    local store = customStore()
    if type(key) ~= "string" or not store[key] then return nil, L["preset personale sconosciuto"] end
    store[key] = nil
    self:Unregister(key)
    return true
end

function Presets:LoadCustom()
    local store = customStore()
    local loaded = 0
    for key, def in pairs(store) do
        if type(def) == "table" then
            def.key, def.custom = key, true
            local ok, nd = pcall(normalize, def, false)
            if ok and nd and nd.title then
                if not self.templates[key] then self.templateOrder[#self.templateOrder + 1] = key end
                self.templates[key] = nd
                loaded = loaded + 1
            else
                store[key] = nil
            end
        else
            store[key] = nil
        end
    end
    return loaded
end

------------------------------------------------------------------------------
-- Modulo: opzioni, pagina della configurazione, comandi
------------------------------------------------------------------------------
local M = Badb.Modules:New("Presets", {
    title = L["Preset e configurazione guidata"],
    category = "Layout",
    defaults = { enabled = true },
    options = {
        { type = "execute", label = L["Apri configurazione guidata"], func = function()
            if Badb.Wizard then Badb.Wizard:Open() end
        end },
        { type = "execute", label = L["Applica layout consigliato"], func = function()
            Presets:Apply(Presets:Build(Presets:Recommend()))
        end },
        { type = "execute", label = L["Annulla ultimo preset"], func = function() Presets:Undo() end },
    },
})
Presets.module = M

function M:OnInitialize() Presets:LoadCustom() end
function M:OnEnable() end
function M:OnDisable() end

local CLASS_NAMES = { WARRIOR = L["Guerriero"], PALADIN = L["Paladino"], HUNTER = L["Cacciatore"], ROGUE = L["Ladro"],
    PRIEST = L["Sacerdote"], SHAMAN = L["Sciamano"], MAGE = L["Mago"], WARLOCK = L["Stregone"], DRUID = L["Druido"] }
Presets.CLASS_NAMES = CLASS_NAMES
local ROLE_NAMES = { tank = "Tank", healer = "Healer", dps = "DPS" }
Presets.ROLE_NAMES = ROLE_NAMES

local function say(fmt, ...) Logger:Info(fmt, ...) end
local function textBox(title, text, onAccept)
    local UI = Badb.ConfigUI
    if UI and UI.TextBox then UI.TextBox(title, text, onAccept) else say("%s", tostring(text)) end
end

local function previewText(key, opts)
    local r = Presets:Resolve(key, opts)
    local diff, err = Presets:Diff(key, opts)
    if not r or not diff then return L["Anteprima non disponibile: "] .. tostring(err) end
    local def = Presets:Get(key)
    local head = string.format(L["%s  (ruolo %s%s)\n%s\n\n%d modifiche:\n"], r.title, ROLE_NAMES[r.role] or r.role,
        r.variant and (L[", raid da "] .. r.variant) or "", def.rationale or def.description or "", #diff)
    return head .. Presets:FormatDiff(diff)
end

local function parseApplyArgs(rest)
    local key, a, b = rest:match("^(%S+)%s*(%S*)%s*(%S*)")
    local opts = {}
    for _, v in ipairs({ a, b }) do
        if VALID_ROLES[v] then opts.role = v elseif VARIANT_OK[v] then opts.variant = v
        elseif APPLY_MODES[v] then opts.mode = v end
    end
    return key, opts
end

M.commands = {
    preset = {
        help = L["preset list [pve|pvp] | apply <chiave> [ruolo] [10|20|40] | diff <chiave> | recommend | undo | save <nome> | export [chiave] | import | delete <chiave>"],
        fn = function(args)
            local sub, rest = (args or ""):match("^(%S*)%s*(.-)$")
            sub, rest = (sub or ""):lower(), rest or ""
            if sub == "" or sub == "list" then
                local class = Badb.Player and probe(Badb.Player.GetClass, Badb.Player)
                local list = Presets:List({ class = class, mode = Presets.MODES[rest] and rest or nil })
                for _, d in ipairs(list) do say("%s  |cff888888%s|r", d.key, d.title) end
                if #list == 0 then say(L["Nessun preset"]) end
            elseif sub == "apply" then
                local key, opts = parseApplyArgs(rest)
                if not key then say(L["Uso: /badb preset apply <chiave> [ruolo] [10|20|40]"]); return end
                local name, err = Presets:Apply(key, opts)
                if not name then say(L["Preset non applicato: %s"], tostring(err)) end
            elseif sub == "diff" or sub == "preview" then
                local key, opts = parseApplyArgs(rest)
                textBox(L["Anteprima preset"], previewText(key or "", opts))
            elseif sub == "recommend" then
                local key, opts, why = Presets:RecommendTemplate()
                if key then say(L["Consigliato: %s (%s, ruolo %s)"], key, why, tostring(opts.role or "?"))
                else say(L["Nessuna raccomandazione: %s"], tostring(opts)) end
            elseif sub == "undo" then
                Presets:Undo()
            elseif sub == "save" then
                local key, err = Presets:SaveCustom(rest ~= "" and rest or nil)
                say(key and L["Preset personale salvato: %s"] or L["Salvataggio fallito: %s"], tostring(key or err))
            elseif sub == "export" then
                local str, err
                if rest ~= "" and Presets:Get(rest) then str, err = Presets:Export(rest)
                else str, err = Presets:ExportCustom(rest ~= "" and rest or nil) end
                if str then textBox(L["Esporta preset"], str) else say(L["Export fallito: %s"], tostring(err)) end
            elseif sub == "import" then
                textBox(L["Incolla la stringa del preset"], "", function(s)
                    local key, err = Presets:ImportCustom(s)
                    say(key and L["Preset importato: %s"] or L["Import fallito: %s"], tostring(key or err))
                end)
            elseif sub == "delete" then
                local ok, err = Presets:DeleteCustom(rest)
                say(ok and L["Preset eliminato"] or L["Eliminazione fallita: %s"], tostring(err))
            else
                say("%s", M.commands.preset.help)
            end
        end,
    },
}

------------------------------------------------------------------------------
-- Pagina "Preset" della ConfigUI v2: classe -> PvE/PvP -> 3 template con anteprima e applica.
-- Usa solo CreateFrame e template base, cosi' funziona anche senza i builder estesi.
------------------------------------------------------------------------------
local page = { class = nil, mode = "pve", role = nil, variant = nil, rows = {} }
Presets.pageState = page

local function newButton(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", function() local ok, err = pcall(onClick); if not ok then Logger:Error("Preset: %s", tostring(err)) end end)
    return b
end

local function newText(parent, template)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    return fs
end

local function cycle(list, current)
    for i, v in ipairs(list) do if v == current then return list[i % #list + 1] end end
    return list[1]
end

local function pageClass()
    if page.class then return page.class end
    local c = Badb.Player and probe(Badb.Player.GetClass, Badb.Player)
    return type(c) == "string" and c or "WARRIOR"
end

local function classRoles(token)
    local info = classInfo(token)
    return info and info.roles or { "dps" }
end

local function renderPage()
    local class = pageClass()
    if page.header then
        page.header:SetText(string.format(L["Classe: |cff3fa7ff%s|r   ·   Modalita': |cff3fa7ff%s|r   ·   Ruolo: |cff3fa7ff%s|r"],
            CLASS_NAMES[class] or class, page.mode == "pvp" and "PvP" or "PvE",
            page.role and ROLE_NAMES[page.role] or L["automatico"]))
    end
    local list = Presets:List({ class = class, mode = page.mode, strictClass = true, custom = false })
    for i, row in ipairs(page.rows) do
        local d = list[i]
        row.key = d and d.key or nil
        row.frame:SetShown(d ~= nil)
        if d then
            local r = Presets:Resolve(d.key, { role = page.role, variant = page.variant })
            row.title:SetText(string.format("|cffffd100%s|r  |cff888888%s|r", d.title, r and ROLE_NAMES[r.role] or ""))
            row.desc:SetText(d.rationale or d.description or "")
        end
    end
    if page.undo then page.undo:SetShown(Presets:CanUndo()) end
    if page.customInfo then
        local customs = Presets:List({ custom = true })
        local names = {}
        for i, d in ipairs(customs) do if i <= 6 then names[#names + 1] = d.key end end
        page.customInfo:SetText(#customs == 0 and L["Nessun preset personale salvato."]
            or (L["Preset personali: "] .. table.concat(names, ", ") .. (#customs > 6 and " ..." or "")))
    end
end

local function buildPage(parent)
    local y = 8
    local intro = newText(parent, "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 16, -y); intro:SetWidth(540)
    intro:SetText(L["Interfacce complete in un click: layout Edit Mode (barre, unit frame, cast bar) piu' le opzioni di BadbUI, "]
        .. L["su misura per classe, ruolo e contenuto di Forever. Ogni preset mostra l'anteprima, crea un nuovo profilo "]
        .. L["con backup e si annulla con /badb undo."])
    y = y + 48
    page.header = newText(parent, "GameFontNormal")
    page.header:SetPoint("TOPLEFT", 16, -y)
    y = y + 24
    local function ctl(text, x, fn) local b = newButton(parent, text, 128, function() fn(); renderPage() end); b:SetPoint("TOPLEFT", x, -y); return b end
    ctl(L["Classe"], 16, function()
        local tokens = {}
        for _, c in ipairs(Badb.Player and Badb.Player.CLASSES or {}) do tokens[#tokens + 1] = c.token end
        page.class = cycle(tokens, pageClass()); page.role = nil
    end)
    ctl("PvE / PvP", 152, function() page.mode = page.mode == "pve" and "pvp" or "pve" end)
    ctl(L["Ruolo"], 288, function()
        local roles = { "auto" }
        for _, r in ipairs(classRoles(pageClass())) do roles[#roles + 1] = r end
        local nextRole = cycle(roles, page.role or "auto")
        page.role = nextRole ~= "auto" and nextRole or nil
    end)
    ctl("Raid 10/20/40", 424, function() page.variant = cycle({ "10", "20", "40" }, page.variant or "40") end)
    y = y + 34
    page.rows = {}
    for i = 1, 3 do
        local row = { frame = CreateFrame("Frame", nil, parent) }
        row.frame:SetPoint("TOPLEFT", 16, -y); row.frame:SetSize(540, 70)
        row.title = newText(row.frame, "GameFontNormal"); row.title:SetPoint("TOPLEFT", 0, 0)
        row.desc = newText(row.frame, "GameFontHighlightSmall"); row.desc:SetPoint("TOPLEFT", 0, -18); row.desc:SetWidth(390)
        local preview = newButton(row.frame, L["Anteprima"], 100, function()
            if row.key then textBox(L["Anteprima preset"], previewText(row.key, { role = page.role, variant = page.variant })) end
        end)
        preview:SetPoint("TOPRIGHT", 0, -14)
        local apply = newButton(row.frame, L["Applica"], 100, function()
            if not row.key then return end
            local key, opts = row.key, { role = page.role, variant = page.variant }
            local function go()
                local name, err = Presets:Apply(key, opts)
                local UI = Badb.ConfigUI
                if UI and UI.Toast then UI.Toast(name and (L["Preset applicato: "] .. name) or (L["Preset non applicato: "] .. tostring(err)), name and "info" or "error") end
                renderPage()
            end
            local UI = Badb.ConfigUI
            if UI and UI.Confirm then UI.Confirm(L["Applicare il preset? Verra' creato un nuovo profilo (annullabile)."], go) else go() end
        end)
        apply:SetPoint("TOPRIGHT", 0, -40)
        page.rows[i] = row
        y = y + 78
    end
    page.undo = newButton(parent, L["Annulla ultimo preset"], 180, function() Presets:Undo(); renderPage() end)
    page.undo:SetPoint("TOPLEFT", 16, -y)
    local rec = newButton(parent, L["Consigliato per me"], 180, function()
        local key, opts = Presets:RecommendTemplate()
        if key then
            local d = Presets:Get(key)
            page.class, page.mode, page.variant = d.class, d.mode, opts.variant
        end
    end)
    rec:SetPoint("TOPLEFT", 204, -y)
    rec:HookScript("OnClick", renderPage)
    y = y + 40
    local h = newText(parent, "GameFontNormalLarge"); h:SetPoint("TOPLEFT", 16, -y); h:SetText(L["Preset personali"])
    y = y + 28
    page.customInfo = newText(parent, "GameFontHighlightSmall"); page.customInfo:SetPoint("TOPLEFT", 16, -y); page.customInfo:SetWidth(540)
    y = y + 22
    local function cbtn(text, x, fn) local b = newButton(parent, text, 128, fn); b:SetPoint("TOPLEFT", x, -y); return b end
    cbtn(L["Salva attuale"], 16, function()
        textBox(L["Nome del preset personale"], "", function(name)
            local key, err = Presets:SaveCustom(name)
            say(key and L["Preset personale salvato: %s"] or L["Salvataggio fallito: %s"], tostring(key or err)); renderPage()
        end)
    end)
    cbtn(L["Esporta attuale"], 152, function()
        local str, err = Presets:ExportCustom(DB:GetProfileName())
        textBox(L["Esporta preset"], str or (L["Errore: "] .. tostring(err)))
    end)
    cbtn(L["Importa"], 288, function()
        textBox(L["Incolla la stringa del preset"], "", function(s)
            local key, err = Presets:ImportCustom(s)
            say(key and L["Preset importato: %s (applicalo con /badb preset apply %s)"] or L["Import fallito: %s"], tostring(key or err), tostring(key))
            renderPage()
        end)
    end)
    y = y + 34
    renderPage()
    return y + 10
end

M.page = {
    title = "Preset", order = 20, category = L["Gestione"],
    build = function(parent) return buildPage(parent) end,
    refresh = function() if page.header then renderPage() end end,
}
