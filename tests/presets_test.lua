-- Test dei preset di interfaccia: template per classe, layout Edit Mode dichiarativo, Apply/Undo, preset utente.
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end
local function truthy(v, msg) if not v then error(msg or "atteso vero", 2) end end

local T = {}

------------------------------------------------------------------------------
-- Edit Mode simulato (forma dei layout Mainline). Pulito alla fine di ogni test che lo usa.
------------------------------------------------------------------------------
local EM_GLOBALS = { "Enum", "Constants", "C_EditMode", "EditModePresetLayoutManager", "EditModeManagerFrame",
    "EditModeSettingDisplayInfoManager" }

local function settingsFor(ids)
    local out = {}
    for _, id in pairs(ids) do out[#out + 1] = { setting = id, value = 0 } end
    table.sort(out, function(a, b) return a.setting < b.setting end)
    return out
end

local function copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = copy(v) end
    return c
end

local function installEditMode(opts)
    opts = opts or {}
    local E = {
        EditModeSystem = { ActionBar = 0, CastBar = 1, UnitFrame = 3, ObjectiveTracker = 12 },
        EditModeActionBarSystemIndices = { MainBar = 1, Bar2 = 2, Bar3 = 3, RightBar1 = 4, RightBar2 = 5 },
        EditModeUnitFrameSystemIndices = { Player = 1, Target = 2, Focus = 3, Party = 4, Raid = 5 },
        EditModeActionBarSetting = { Orientation = 0, NumRows = 1, NumIcons = 2, IconSize = 3, IconPadding = 4,
            VisibleSetting = 5, HideBarArt = 6, HideBarScrolling = 8 },
        EditModeUnitFrameSetting = { BuffsOnTop = 2, UseLargerFrame = 3, UseRaidStylePartyFrames = 4,
            UseHorizontalGroups = 6, FrameWidth = 10, FrameHeight = 11 },
        EditModeCastBarSetting = { BarSize = 0, LockToPlayerFrame = 1, ShowCastTime = 2 },
        EditModeObjectiveTrackerSetting = { Height = 0 },
        ActionBarOrientation = { Horizontal = 0, Vertical = 1 },
        EditModeLayoutType = { Preset = 0, Account = 1, Character = 2 },
        EditModePresetLayouts = { Modern = 0, Classic = 1 },
        EditModePresetLayoutsMeta = { NumValues = 2 },
    }
    if opts.noFocus then E.EditModeUnitFrameSystemIndices.Focus = nil end
    if opts.noObjective then E.EditModeSystem.ObjectiveTracker = nil end
    Enum = E
    Constants = { EditModeConsts = { EditModeMaxLayoutsPerType = opts.max or 5 } }
    local systems = {}
    for _, i in pairs(E.EditModeActionBarSystemIndices) do
        systems[#systems + 1] = { system = 0, systemIndex = i, settings = settingsFor(E.EditModeActionBarSetting),
            anchorInfo = { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = 0, offsetY = 0 },
            isInDefaultPosition = true }
    end
    for _, i in pairs({ 1, 2, 3, 4, 5 }) do
        systems[#systems + 1] = { system = 3, systemIndex = i, settings = settingsFor(E.EditModeUnitFrameSetting),
            anchorInfo = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", offsetX = 0, offsetY = 0 },
            isInDefaultPosition = true }
    end
    systems[#systems + 1] = { system = 1, settings = settingsFor(E.EditModeCastBarSetting), anchorInfo = {}, isInDefaultPosition = true }
    systems[#systems + 1] = { system = 12, settings = settingsFor(E.EditModeObjectiveTrackerSetting), anchorInfo = {}, isInDefaultPosition = true }
    local modern = { layoutName = "Modern", layoutType = 0, systems = systems }
    local classic = { layoutName = "Classic", layoutType = 0, systems = copy(systems) }
    EditModePresetLayoutManager = { GetCopyOfPresetLayouts = function() return { copy(modern), copy(classic) } end }
    local state = { layouts = { activeLayout = 1, layouts = {} }, saves = 0, active = 1 }
    for i = 1, (opts.existing or 0) do
        state.layouts.layouts[i] = { layoutName = "Mio " .. i, layoutType = 1, systems = copy(systems) }
    end
    C_EditMode = {
        GetLayouts = function() local l = copy(state.layouts); l.activeLayout = state.active; return l end,
        SaveLayouts = function(l) state.layouts = copy(l); state.saves = state.saves + 1 end,
        SetActiveLayout = function(i) state.active = i end,
        ConvertLayoutInfoToString = function(info) return "EMSTR:" .. tostring(info.layoutName) end,
        ConvertStringToLayoutInfo = function(s)
            if type(s) == "string" and s:find("^EMSTR:") then return { layoutName = s:sub(7), systems = copy(systems) } end
        end,
    }
    EditModeManagerFrame = { IsEditModeActive = function() return opts.open == true end }
    BadbUI.Compat.hasEditMode = true
    return state
end

local function clearEditMode()
    for _, k in ipairs(EM_GLOBALS) do _G[k] = nil end
end

local function withEditMode(opts, fn)
    if type(opts) == "function" then fn, opts = opts, nil end
    return function(Mock)
        local state = installEditMode(opts)
        local ok, err = pcall(fn, Mock, state)
        clearEditMode()
        if not ok then error(err, 0) end
    end
end

local function findSys(info, system, index)
    for _, s in ipairs(info.systems) do
        if s.system == system and (index == nil or s.systemIndex == index) then return s end
    end
end
local function settingValue(sys, id)
    for _, e in ipairs(sys.settings) do if e.setting == id then return e.value end end
end
local function layoutByName(state, name)
    for i, l in ipairs(state.layouts.layouts) do if l.layoutName == name then return l, i end end
end

local function setPlayer(class, role)
    local P = BadbUI.Player
    P.GetClass = function() return class end
    P.GetRole = function() return role, "test", "high" end
end

------------------------------------------------------------------------------
-- Catalogo dei template
------------------------------------------------------------------------------
T["catalogo: 54 template, 3 PvE + 3 PvP per classe, niente arena"] = function()
    local P = BadbUI.Presets
    eq(#P.Data.failed, 0, "registrazioni fallite: " .. table.concat(P.Data.failed, " | "))
    local seen, total = {}, 0
    for _, c in ipairs(BadbUI.Player.CLASSES) do
        local pve = P:List({ class = c.token, mode = "pve", strictClass = true })
        local pvp = P:List({ class = c.token, mode = "pvp", strictClass = true })
        eq(#pve, 3, c.token .. " pve"); eq(#pvp, 3, c.token .. " pvp")
        local scen = {}
        for _, d in ipairs(pve) do scen[d.scenario] = true end
        for _, d in ipairs(pvp) do scen[d.scenario] = true end
        for _, s in ipairs({ "dungeon", "raid", "solo", "bg", "av", "world" }) do truthy(scen[s], c.token .. " manca " .. s) end
        for _, list in ipairs({ pve, pvp }) do
            for _, d in ipairs(list) do
                truthy(not seen[d.key], "chiave duplicata " .. d.key); seen[d.key] = true; total = total + 1
                eq(d.key, c.token:lower() .. "-" .. d.mode .. "-" .. d.scenario, "formato chiave")
                truthy(not d.key:find("arena") and d.scenario ~= "arena", "nessuna arena")
                truthy(d.rationale and #d.rationale > 40, d.key .. ": rationale")
                truthy(#d.facts >= 2, d.key .. ": fatti citati")
                truthy(d.editMode and #d.editMode.systems >= 10, d.key .. ": layout Edit Mode")
                local okv, errs = P:Validate(d)
                truthy(okv, d.key .. " non valido: " .. tostring(errs and errs[1]))
            end
        end
    end
    eq(total, 54)
end

T["catalogo: byRole solo per i ruoli della classe, varianti solo raid"] = function()
    local P = BadbUI.Presets
    for _, c in ipairs(BadbUI.Player.CLASSES) do
        local allowed = {}
        for _, r in ipairs(c.roles) do allowed[r] = true end
        for _, d in ipairs(P:List({ class = c.token, strictClass = true })) do
            for role in pairs(d.byRole or {}) do truthy(allowed[role], d.key .. ": ruolo " .. role .. " non ammesso") end
            for _, r in ipairs(c.roles) do truthy(d.byRole[r], d.key .. ": manca byRole " .. r) end
            eq(d.role, c.primary, d.key .. ": ruolo di default")
            if d.scenario == "raid" then
                truthy(d.variants and d.variants["10"] and d.variants["20"] and d.variants["40"], d.key .. ": varianti")
            else
                eq(d.variants, nil, d.key .. ": varianti fuori dal raid")
            end
        end
    end
end

T["catalogo: valori entro i limiti delle opzioni dei moduli"] = function()
    local P = BadbUI.Presets
    local ranges = {}
    for _, name in ipairs(BadbUI.Modules.order) do
        local m = BadbUI.Modules:Get(name)
        for _, o in ipairs(m.options or {}) do
            if type(o) == "table" and o.type == "range" and o.path then ranges[name .. "." .. o.path] = o end
        end
    end
    local checked = 0
    local function check(mods, where)
        for name, opts in pairs(mods or {}) do
            for k, v in pairs(opts) do
                local o = ranges[name .. "." .. k]
                if o and type(v) == "number" then
                    truthy(v >= o.min and v <= o.max, where .. ": " .. name .. "." .. k .. "=" .. v .. " fuori da " .. o.min .. "-" .. o.max)
                    checked = checked + 1
                end
            end
        end
    end
    for _, key in ipairs(P.templateOrder) do
        for _, role in ipairs({ "tank", "healer", "dps" }) do
            for _, v in ipairs({ "10", "20", "40" }) do
                local r = P:Resolve(key, { role = role, variant = v })
                check(r.modules, key .. "/" .. role .. "/" .. v)
            end
        end
    end
    truthy(checked > 500, "controlli effettuati: " .. checked)
end

T["catalogo: PvP diverso dal PvE, raid 10/20/40 con group frames diversi"] = function()
    local P = BadbUI.Presets
    for _, c in ipairs(BadbUI.Player.CLASSES) do
        local k = c.token:lower()
        local pve = P:Resolve(k .. "-pve-dungeon", { role = c.primary })
        local pvp = P:Resolve(k .. "-pvp-bg", { role = c.primary })
        eq(pvp.modules.Nameplates.maxDistance, 60, k .. ": PvP nameplate fino a 60 yard")
        local differ = 0
        for mod, opts in pairs(pvp.modules) do
            for o, v in pairs(opts) do if type(v) ~= "table" and (pve.modules[mod] or {})[o] ~= v then differ = differ + 1 end end
        end
        truthy(differ >= 3, k .. ": PvP diverso dal PvE (" .. differ .. ")")
        eq(pvp.modules.Nameplates.classColorEnemies, true)
        local sizes = {}
        for _, v in ipairs({ "10", "20", "40" }) do
            local r = P:Resolve(k .. "-pve-raid", { role = c.primary, variant = v })
            eq(r.variant, v)
            sizes[v] = r.modules.GroupFrames.raidWidth * 1000 + r.modules.GroupFrames.raidHeight
        end
        truthy(sizes["10"] > sizes["20"] and sizes["20"] > sizes["40"], k .. ": raid 10 > 20 > 40")
        local av = P:Resolve(k .. "-pvp-av", { role = c.primary })
        truthy(av.modules.GroupFrames.raidWidth < pvp.modules.GroupFrames.raidWidth, k .. ": AV piu' compatto dei BG")
    end
end

T["resolve: healer ha group frames piu' grandi, tank nameplate piu' grandi, ruolo non ammesso ignorato"] = function()
    local P = BadbUI.Presets
    setPlayer("PALADIN", "dps")
    local heal = P:Resolve("paladin-pve-raid", { role = "healer", variant = "40" })
    local dps = P:Resolve("paladin-pve-raid", { role = "dps", variant = "40" })
    truthy(heal.modules.GroupFrames.raidWidth > dps.modules.GroupFrames.raidWidth, "healer piu' largo")
    eq(heal.modules.GroupFrames.incomingHeals, true)
    local tank = P:Resolve("paladin-pve-dungeon", { role = "tank" })
    truthy(tank.modules.Nameplates.globalScale > 1, "tank: nameplate piu' grandi")
    -- Mago tank non esiste: si usa il ruolo rilevato (dps) o quello del template.
    setPlayer("MAGE", "tank")
    local mage = P:Resolve("mage-pve-dungeon", { role = "tank" })
    eq(mage.role, "dps", "ruolo non ammesso scartato")
    -- Ruolo rilevato da Badb.Player quando non scelto
    setPlayer("DRUID", "healer")
    eq(P:Resolve("druid-pve-dungeon").role, "healer")
    eq(P:Resolve("druid-pve-dungeon").roleSource, "rilevato")
    -- Layout: l'archetipo segue il ruolo (healer: party orizzontale al centro)
    local hl = P:Resolve("druid-pve-dungeon", { role = "healer" }).editMode
    local found
    for _, s in ipairs(hl.systems) do if s.index == "Party" then found = s end end
    eq(found.anchor[2], "CENTER"); eq(found.settings.UseHorizontalGroups, true)
end

T["list: filtri per classe, modalita', scenario, ruolo, ricerca"] = function()
    local P = BadbUI.Presets
    eq(#P:List({ mode = "pvp", scenario = "av" }), 9)
    eq(#P:List({ role = "tank", scenario = "dungeon" }), 3, "guerriero, paladino, druido")
    eq(#P:List({ class = "ROGUE", search = "alterac" }), 1)
    eq(#P:List({ tag = "raid" }), 9)
    eq(#P:List("spazzatura"), 54, "filtro non tabella = nessun filtro")
    eq(P:Get(42), nil); eq(P:Get("nessuno"), nil)
end

------------------------------------------------------------------------------
-- Validazione
------------------------------------------------------------------------------
T["register: rifiuta input errati senza lanciare errori"] = function()
    local P = BadbUI.Presets
    local base = function() return { key = "zz-test", title = "Test", modules = { Nameplates = { globalScale = 1.1 } } } end
    truthy(P:Register(base()), "valido")
    local cases = {
        { nil, "nil" }, { 42, "numero" }, { {}, "senza key" },
        { { key = "con spazi", title = "x" }, "key" },
        { { key = "zz-a", title = "x", modules = { Inesistente = {} } }, "modulo" },
        { { key = "zz-b", title = "x", modules = { Nameplates = { nonEsiste = 1 } } }, "opzione" },
        { { key = "zz-c", title = "x", modules = { Nameplates = { globalScale = "grande" } } }, "tipo" },
        { { key = "zz-d", title = "x", modules = { Nameplates = { globalScale = 0 / 0 } } }, "nan" },
        { { key = "zz-e", title = "x", mode = "pvp", scenario = "arena" }, "arena" },
        { { key = "zz-f", title = "x", mode = "pve", scenario = "bg" }, "scenario incoerente" },
        { { key = "zz-g", title = "x", class = "MAGE", byRole = { tank = {} } }, "mago tank" },
        { { key = "zz-h", title = "x", class = "WARRIOR", scenario = "dungeon", mode = "pve", variants = { ["10"] = {} } }, "varianti fuori raid" },
        { { key = "zz-i", title = "x", mode = "pve", scenario = "raid", variants = { ["25"] = {} } }, "variante 25" },
        { { key = "zz-j", title = "x", class = "DEATHKNIGHT" }, "classe" },
        { { key = "zz-k", title = "x", modules = { EditModeBridge = { layoutName = "a" } } }, "bridge diretto" },
        { { key = "zz-l", title = "x", editMode = { systems = { { system = "Unit Frame" } } } }, "layout" },
        { { key = "zz-m", title = "x", editMode = { systems = { { system = "UnitFrame", anchor = { "MEZZO", "CENTER", 0, 0 } } } } }, "punto" },
        { { key = "zz-n", title = "x", frames = { MicroMenu = { hidden = "si" } } }, "frame" },
    }
    for _, c in ipairs(cases) do
        local ok, key, err = pcall(P.Register, P, c[1])
        truthy(ok, c[2] .. ": ha lanciato un errore")
        eq(key, nil, c[2] .. " accettato")
        truthy(type(err) == "string", c[2] .. ": messaggio")
    end
    local cyc = base(); cyc.modules.self = cyc
    local ok, key = pcall(P.Register, P, cyc)
    truthy(ok); eq(key, nil, "ciclo rifiutato")
    local deep = base(); local t = deep
    for _ = 1, 30 do t.x = {}; t = t.x end
    ok, key = pcall(P.Register, P, deep)
    truthy(ok); eq(key, nil, "troppo profondo")
end

------------------------------------------------------------------------------
-- Diff e Apply
------------------------------------------------------------------------------
T["diff: anteprima senza modifiche al profilo"] = function()
    local P, DB = BadbUI.Presets, BadbUI.DB
    setPlayer("MAGE", "dps")
    local before = DB:Get("Nameplates", "maxDistance")
    local diff = P:Diff("mage-pvp-bg")
    truthy(#diff > 5, "modifiche elencate")
    local found
    for _, d in ipairs(diff) do if d.module == "Nameplates" and d.path == "maxDistance" then found = d end end
    eq(found.from, 41); eq(found.to, 60)
    eq(DB:Get("Nameplates", "maxDistance"), before, "profilo intatto")
    local only = P:Diff("mage-pvp-bg", { only = { "Nameplates" } })
    for _, d in ipairs(only) do eq(d.module, "Nameplates") end
    local bad, err = P:Diff("sconosciuto")
    eq(bad, nil); truthy(err)
    truthy(P:FormatDiff(diff):find("Nameplates.maxDistance: 41 %-> 60"), "testo leggibile")
end

T["apply: nuovo profilo, backup, evento e undo"] = function(Mock)
    local P, DB = BadbUI.Presets, BadbUI.DB
    setPlayer("PRIEST", "healer")
    local before = DB:GetProfileName()
    local backups = {}
    BadbUI.Backups = { Create = function(_, label, kind) backups[#backups + 1] = kind; return "b1" end }
    local fired
    BadbUI.Events:On({}, "BADB_PRESET_APPLIED", function(_, key, mode, name) fired = { key, mode, name } end)
    local name, report = P:Apply("priest-pve-raid", { variant = "40" })
    truthy(name, "applicato: " .. tostring(report))
    eq(DB:GetProfileName(), name)
    truthy(name:find("Sacerdote"), "nome dal titolo")
    eq(backups[1], "pre-preset")
    eq(report.backup, "b1")
    eq(fired[1], "priest-pve-raid"); eq(fired[2], "new-profile"); eq(fired[3], name)
    eq(DB:Get("GroupFrames", "raidWidth"), 88, "healer raid 40")
    eq(DB:Get("GroupFrames", "enabled"), true)
    eq(DB.profile.frames.MicroMenu.hidden, true)
    eq(DB:Get("Hider", "enabled"), true)
    truthy(BadbUI.Modules:Get("GroupFrames").enabled, "modulo attivato")
    eq(DB.sv.profiles[before].modules.GroupFrames.raidWidth, 90, "profilo originale intatto")
    truthy(P:CanUndo())
    truthy(P:Undo())
    eq(DB:GetProfileName(), before)
    truthy(not P:CanUndo())
    eq(select(1, P:Undo()), nil, "secondo undo: niente da fare")
end

T["apply merge: tiene le scelte dell'utente; replace: riparte dai default; undo ripristina tutto"] = function()
    local P, DB = BadbUI.Presets, BadbUI.DB
    setPlayer("WARRIOR", "tank")
    local profile = DB:GetProfileName()
    DB:Set("Nameplates", "nameSize", 14)        -- non toccata dal preset
    DB:Set("Nameplates", "texture", "smooth")   -- idem
    local name = P:Apply("warrior-pve-dungeon", { mode = "merge" })
    eq(name, profile, "stesso profilo")
    eq(DB:Get("Nameplates", "nameSize"), 14, "merge mantiene")
    eq(DB:Get("Nameplates", "globalScale"), 1.15, "tank")
    P:Undo()
    eq(DB:Get("Nameplates", "globalScale"), 1.0, "undo merge")
    eq(DB:Get("Nameplates", "nameSize"), 14)
    P:Apply("warrior-pve-dungeon", { mode = "replace" })
    eq(DB:Get("Nameplates", "nameSize"), 10, "replace: default")
    eq(DB:Get("Nameplates", "texture"), "flat")
    truthy(P:Undo())
    eq(DB:Get("Nameplates", "nameSize"), 14, "undo replace")
    eq(DB:Get("Nameplates", "texture"), "smooth")
end

T["apply only: solo i moduli scelti"] = function()
    local P, DB = BadbUI.Presets, BadbUI.DB
    setPlayer("ROGUE", "dps")
    P:Apply("rogue-pvp-world", { mode = "merge", only = { "Cooldowns" } })
    eq(DB:Get("Cooldowns", "expiringThreshold"), 3, "Cooldowns applicato")
    eq(DB:Get("Nameplates", "maxDistance"), 41, "Nameplates escluso")
    eq(DB.profile.frames.MicroMenu, nil, "frame esclusi")
end

T["apply: rifiutato in combattimento, con modalita' errata o preset ignoto, senza modifiche"] = function(Mock)
    local P, DB = BadbUI.Presets, BadbUI.DB
    local before, count = DB:GetProfileName(), #DB:ListProfiles()
    Mock.combat = true
    local name, err = P:Apply("mage-pve-solo")
    eq(name, nil); truthy(err:find("combattimento"))
    Mock.combat = false
    eq(select(1, P:Apply("mage-pve-solo", { mode = "boh" })), nil)
    eq(select(1, P:Apply("inesistente")), nil)
    eq(select(1, P:Apply(nil)), nil)
    eq(select(1, P:Apply(12)), nil)
    eq(DB:GetProfileName(), before); eq(#DB:ListProfiles(), count, "nessun profilo creato")
end

T["apply: errore a meta' -> rollback completo"] = withEditMode(function(Mock, state)
    local P, DB = BadbUI.Presets, BadbUI.DB
    setPlayer("MAGE", "dps")
    local before, count = DB:GetProfileName(), #DB:ListProfiles()
    local orig = DB.SetProfile
    DB.SetProfile = function(self, name, silent)
        if name ~= before then error("disco pieno") end
        return orig(self, name, silent)
    end
    local name, err = P:Apply("mage-pve-dungeon")
    DB.SetProfile = orig
    eq(name, nil); truthy(tostring(err):find("disco pieno"))
    eq(DB:GetProfileName(), before)
    eq(#DB:ListProfiles(), count, "profilo creato rimosso")
    eq(#state.layouts.layouts, 0, "layout Edit Mode rimosso")
    eq(DB.sv.global.presetUndo, nil)
end)

------------------------------------------------------------------------------
-- Edit Mode
------------------------------------------------------------------------------
T["edit mode: layout costruito, installato, attivato e annullabile"] = withEditMode(function(Mock, state)
    local P, DB = BadbUI.Presets, BadbUI.DB
    setPlayer("HUNTER", "dps")
    local name, report = P:Apply("hunter-pve-dungeon")
    truthy(name, tostring(report))
    local l, idx = layoutByName(state, name)
    truthy(l, "layout salvato con il nome del profilo")
    eq(l.layoutType, 1, "account")
    eq(state.active, idx + 2, "attivato dall'EditModeBridge (2 preset Blizzard in testa)")
    eq(DB:Get("EditModeBridge", "layoutName"), name)
    eq(DB:Get("EditModeBridge", "layoutString"), "EMSTR:" .. name)
    local main = findSys(l, 0, 1)
    eq(main.anchorInfo.point, "BOTTOM"); eq(main.anchorInfo.offsetY, 24); eq(main.isInDefaultPosition, false)
    eq(settingValue(main, 3), 4, "IconSize 90% -> grezzo 4")
    eq(settingValue(main, 6), 1, "HideBarArt")
    eq(settingValue(findSys(l, 0, 4), 0), 1, "barra destra verticale")
    local player = findSys(l, 3, 1)
    eq(player.anchorInfo.point, "CENTER"); eq(player.anchorInfo.offsetX, -300, "distanza: frame larghi")
    eq(settingValue(findSys(l, 3, 4), 4), 1, "party in stile raid")
    eq(settingValue(findSys(l, 1), 2), 1, "tempo di cast")
    eq(report.layout.applied, 11); eq(#report.layout.skipped, 0)
    truthy(P:Undo())
    eq(layoutByName(state, name), nil, "layout rimosso")
    eq(state.active, 1, "layout attivo precedente")
end)

T["edit mode: convertitore slider del client se presente"] = withEditMode(function(Mock, state)
    EditModeSettingDisplayInfoManager = { systemSettingDisplayInfo = { [0] = {
        { setting = 3, ConvertValue = function(_, v) return (v - 50) / 5 end } } } }
    setPlayer("MAGE", "dps")
    local name = BadbUI.Presets:Apply("mage-pve-solo")
    eq(settingValue(findSys(layoutByName(state, name), 0, 1), 3), 8, "valore dal convertitore del client")
end)

T["edit mode: sistemi assenti saltati e riportati, mai inventati"] = withEditMode({ noFocus = true, noObjective = true }, function(Mock, state)
    setPlayer("WARLOCK", "dps")
    local name, report = BadbUI.Presets:Apply("warlock-pve-solo")
    truthy(name)
    local text = table.concat(report.layout.skipped, ";")
    truthy(text:find("UnitFrame Focus assente"), text)
    truthy(text:find("ObjectiveTracker assente"), text)
    eq(#layoutByName(state, name).systems, 12, "nessun sistema aggiunto")
end)

T["edit mode: limite layout raggiunto -> opzioni applicate, layout segnalato"] = withEditMode({ existing = 5 }, function(Mock, state)
    local P, DB = BadbUI.Presets, BadbUI.DB
    setPlayer("ROGUE", "dps")
    local name, report = P:Apply("rogue-pve-dungeon")
    truthy(name, "applicato comunque")
    truthy(report.warnings[1]:find("limite di 5"), report.warnings[1])
    eq(#state.layouts.layouts, 5)
    eq(DB:Get("EditModeBridge", "layoutString"), nil)
    eq(DB:Get("Nameplates", "enabled"), true)
end)

T["edit mode: aperto -> preset rifiutato"] = withEditMode({ open = true }, function()
    local name, err = BadbUI.Presets:Apply("mage-pve-solo")
    eq(name, nil); truthy(err:find("Edit Mode"))
end)

T["edit mode: merge riapplicato sostituisce il layout con lo stesso nome"] = withEditMode(function(Mock, state)
    local P = BadbUI.Presets
    setPlayer("DRUID", "healer")
    P:Apply("druid-pvp-bg", { mode = "merge" })
    P:Apply("druid-pvp-bg", { mode = "merge", role = "tank" })
    local n = 0
    for _, l in ipairs(state.layouts.layouts) do if l.layoutName:find("Druido") then n = n + 1 end end
    eq(n, 1, "un solo layout")
    P:Undo()
    local l = layoutByName(state, "Badb - Druido · Campo di battaglia")
    truthy(l, "torna il layout del primo apply")
    eq(findSys(l, 3, 1).anchorInfo.offsetX, -290, "layout healer ripristinato")
end)

T["edit mode non disponibile: opzioni applicate con avviso"] = function()
    local name, report = BadbUI.Presets:Apply("mage-pve-solo")
    truthy(name)
    truthy(report.warnings[1]:find("Edit Mode non disponibile"), report.warnings[1])
end

T["wizard: contenuto + ruolo con layout Edit Mode dichiarativo"] = withEditMode(function(Mock, state)
    local P, DB = BadbUI.Presets, BadbUI.DB
    local spec = P:Build({ content = "dungeon", role = "healer" })
    truthy(type(spec.editMode) == "table" and spec.editMode.systems, "layout healer")
    truthy(table.concat(P:Describe(spec), "\n"):find("elementi posizionati"))
    local name = P:Apply(spec)
    truthy(layoutByName(state, name), "layout installato dal percorso wizard")
    eq(DB:Get("EditModeBridge", "layoutName"), name)
end)

------------------------------------------------------------------------------
-- Raccomandazione
------------------------------------------------------------------------------
T["recommend: contesto -> scenario, classe da Badb.Player"] = function()
    local P = BadbUI.Presets
    setPlayer("SHAMAN", "healer")
    local ctx = { instance = "pvp", group = "raid" }
    BadbUI.Contexts = { GetCurrent = function() return ctx end }
    local maxPlayers = 10
    GetInstanceInfo = function() return "x", "pvp", 0, "", maxPlayers end
    eq(P:RecommendTemplate(), "shaman-pvp-bg")
    maxPlayers = 40
    eq(P:RecommendTemplate(), "shaman-pvp-av")
    ctx.instance, maxPlayers = "raid", 20
    local key, opts = P:RecommendTemplate()
    eq(key, "shaman-pve-raid"); eq(opts.variant, "20"); eq(opts.role, "healer")
    ctx.instance = "party"
    eq(P:RecommendTemplate(), "shaman-pve-dungeon")
    ctx.instance, ctx.group = "none", "solo"
    eq(P:RecommendTemplate(), "shaman-pve-solo")
    UnitIsPVP = function() return true end
    eq(P:RecommendTemplate(), "shaman-pvp-world")
    UnitIsPVP, GetInstanceInfo = nil, nil
    setPlayer(nil, "dps")
    eq(P:RecommendTemplate(), nil, "classe ignota")
    BadbUI.Contexts = { GetCurrent = function() error("rotto") end }
    setPlayer("MAGE", "dps")
    eq(P:RecommendTemplate(), "mage-pve-solo", "Contexts rotto: degrado")
end

------------------------------------------------------------------------------
-- Preset utente
------------------------------------------------------------------------------
T["custom: esporta -> importa -> applica, persiste e si elimina"] = function()
    local P, DB = BadbUI.Presets, BadbUI.DB
    DB:Set("Nameplates", "globalScale", 1.4)
    DB:Set("Cooldowns", "pulseSize", 96)
    local str = P:ExportCustom("Il mio PvP", "prova", "dps")
    truthy(type(str) == "string" and str:find("^BADB1:"), "stringa")
    DB:Set("Nameplates", "globalScale", 1.0)
    local key, dropped = P:ImportCustom(str)
    eq(key, "custom-il-mio-pvp"); eq(#dropped, 0)
    truthy(DB.sv.global.customPresets[key], "salvato in global")
    eq(#P:List({ custom = true }), 1)
    truthy(P:Apply(key))
    eq(DB:Get("Nameplates", "globalScale"), 1.4)
    eq(DB:Get("Cooldowns", "pulseSize"), 96)
    -- Dopo un /reload il preset viene ricaricato da global
    P:Unregister(key)
    eq(P:LoadCustom(), 1)
    truthy(P:Get(key))
    -- Un secondo import con lo stesso titolo non duplica la chiave a caso
    local key2 = P:ImportCustom(str)
    eq(key2, key)
    truthy(P:DeleteCustom(key)); eq(P:Get(key), nil); eq(DB.sv.global.customPresets[key], nil)
    eq(select(1, P:DeleteCustom(key)), nil)
end

T["custom: import di stringhe malevole o rotte"] = function()
    local P, S = BadbUI.Presets, BadbUI.Serializer
    for _, bad in ipairs({ nil, "", 42, "ciao", "BADB1:abc:00000000", string.rep("A", 300000) }) do
        local ok, key, err = pcall(P.ImportCustom, P, bad)
        truthy(ok, "nessun errore Lua"); eq(key, nil); truthy(err)
    end
    eq(select(1, P:ImportCustom(S:Export("profile", { modules = {} }))), nil, "tipo sbagliato")
    local str = S:Export("preset", { key = "x", title = "Strano|cffff0000", role = "dps",
        modules = { Nameplates = { globalScale = 1.2, nonEsiste = true }, Fantasma = { a = 1 } },
        byRole = { tank = { modules = { Nameplates = { globalScale = 1.3 } } } },
        frames = { MicroMenu = { hidden = true, colore = "rosso" } } })
    local key, dropped = P:ImportCustom(str)
    truthy(key, "importato ripulito")
    truthy(#dropped >= 3, "voci scartate riportate")
    local d = P:Get(key)
    eq(d.modules.Nameplates.globalScale, 1.2)
    eq(d.modules.Nameplates.nonEsiste, nil); eq(d.modules.Fantasma, nil); eq(d.frames.MicroMenu.colore, nil)
    truthy(not d.title:find("|"), "codici colore neutralizzati")
    truthy(d.custom)
end

T["custom: limite di preset personali"] = function()
    local P = BadbUI.Presets
    for i = 1, 50 do truthy(P:SaveCustom("P" .. i)) end
    local key, err = P:SaveCustom("Uno di troppo")
    eq(key, nil); truthy(err:find("max 50"))
end

T["export di un template e reimport come preset personale"] = function()
    local P = BadbUI.Presets
    local str = P:Export("paladin-pve-raid")
    local key = P:ImportCustom(str)
    eq(key, "custom-paladino-raid")
    local d = P:Get(key)
    eq(d.class, "PALADIN"); truthy(d.variants["40"]); truthy(d.byRole.healer)
end

------------------------------------------------------------------------------
-- Comandi e pagina
------------------------------------------------------------------------------
T["comando /badb preset"] = function(Mock)
    local P, DB = BadbUI.Presets, BadbUI.DB
    setPlayer("WARRIOR", "dps")
    eq(BadbUI.Slash:Dispatch("preset list pvp"), true)
    local joined = table.concat(Mock.chat, "\n")
    truthy(joined:find("warrior%-pvp%-bg") and not joined:find("warrior%-pve%-raid"), "elenco filtrato")
    BadbUI.Slash:Dispatch("preset apply warrior-pve-raid tank 10")
    truthy(DB:GetProfileName():find("Guerriero"), DB:GetProfileName())
    eq(DB:Get("GroupFrames", "raidWidth"), 112, "variante 10")
    eq(DB:Get("Nameplates", "globalScale"), 1.15, "ruolo tank")
    BadbUI.Slash:Dispatch("preset undo")
    eq(DB:GetProfileName(), "Default")
    for _, sub in ipairs({ "diff warrior-pvp-av", "recommend", "save Mio", "export", "export warrior-pvp-av", "import", "delete nessuno", "boh", "apply" }) do
        BadbUI.Slash:Dispatch("preset " .. sub)
    end
    truthy(P:Get("custom-mio"), "save da comando")
end

T["pagina Preset: si costruisce e cambia classe/modalita'"] = function()
    local P = BadbUI.Presets
    setPlayer("MAGE", "dps")
    local parent = CreateFrame("Frame")
    local h = P.module.page.build(parent)
    truthy(type(h) == "number" and h > 300, "altezza")
    local st = P.pageState
    eq(st.rows[1].key, "mage-pve-dungeon")
    st.mode = "pvp"; P.module.page.refresh()
    eq(st.rows[3].key, "mage-pvp-world")
    st.class = "DRUID"; st.role = "tank"; P.module.page.refresh()
    eq(st.rows[1].key, "druid-pvp-bg")
    truthy(st.rows[1].title:GetText():find("Tank"))
end

return T
