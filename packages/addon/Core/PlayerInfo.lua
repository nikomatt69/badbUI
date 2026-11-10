-- BadbUI - PlayerInfo
-- Servizio unico per classe, livello, gruppo talenti (dual spec), albero dominante e RUOLO del giocatore.
-- Perche' esiste: su WoW Forever le "specializzazioni" sono i 3 alberi di talenti classici (27 in totale) con
-- dual spec dal livello 40, NON le spec Mainline. Le API (GetTalentTabInfo vs C_ClassTalents/C_Traits) sono
-- documentate in modo contrastante e cambiano tra build: nessun modulo deve sondarle da solo.
-- Tutte le letture sono in pcall; se nulla e' leggibile si degrada al ruolo predefinito della classe,
-- dichiarando la FONTE e la CONFIDENZA, cosi' la UI puo' chiedere conferma all'utente.
--
-- Fonti del ruolo, in ordine di priorita':
--   override  scelta esplicita dell'utente (per gruppo talenti o "*"), salvata in sv.global.roleOverrides
--   group     ruolo assegnato dal gruppo (UnitGroupRolesAssigned) se diverso da NONE
--   tree-name albero dominante riconosciuto dal nome (en/it)
--   tree-index albero dominante riconosciuto dalla posizione (ordine classico dei 3 alberi)
--   spec      API Mainline GetSpecialization*, se presente
--   class     ruolo primario della classe (confidenza bassa)
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local Events, Logger, Compat = Badb.Events, Badb.Logger, Badb.Compat

local Player = { cache = nil, providers = {} }
Badb.Player = Player

-- Dati classi: UNICA fonte di verita' per presets, wizard, contesti.
-- `trees` segue l'ordine classico dei tre alberi; `names` sono indizi minuscoli (en/it) usati per il riconoscimento
-- per nome (le build possono rinominare gli alberi: il fallback e' l'indice). I nomi non sono verificati in gioco.
local CLASSES = {
    { token = "WARRIOR", primary = "dps",    roles = { "dps", "tank" },
      trees = { { key = "arms", role = "dps", names = { "arms", "armi" } },
                { key = "fury", role = "dps", names = { "fury", "furia" } },
                { key = "protection", role = "tank", names = { "protection", "protezione" } } } },
    { token = "PALADIN", primary = "healer", roles = { "dps", "tank", "healer" },
      trees = { { key = "holy", role = "healer", names = { "holy", "sacro" } },
                { key = "protection", role = "tank", names = { "protection", "protezione" } },
                { key = "retribution", role = "dps", names = { "retribution", "castigo" } } } },
    { token = "HUNTER", primary = "dps", roles = { "dps" }, ranged = true,
      trees = { { key = "beastmastery", role = "dps", names = { "beast", "bestie" } },
                { key = "marksmanship", role = "dps", names = { "marksman", "precisione", "mira" } },
                { key = "survival", role = "dps", names = { "survival", "sopravvivenza" } } } },
    { token = "ROGUE", primary = "dps", roles = { "dps" },
      trees = { { key = "assassination", role = "dps", names = { "assassination", "assassinio" } },
                { key = "combat", role = "dps", names = { "combat", "combattimento" } },
                { key = "subtlety", role = "dps", names = { "subtlety", "furtivit" } } } },
    { token = "PRIEST", primary = "healer", roles = { "healer", "dps" }, ranged = true,
      trees = { { key = "discipline", role = "healer", names = { "discipline", "disciplina" } },
                { key = "holy", role = "healer", names = { "holy", "sacro" } },
                { key = "shadow", role = "dps", names = { "shadow", "ombra" } } } },
    { token = "SHAMAN", primary = "dps", roles = { "dps", "healer" },
      trees = { { key = "elemental", role = "dps", names = { "elemental", "elementale" } },
                { key = "enhancement", role = "dps", names = { "enhancement", "potenziamento" } },
                { key = "restoration", role = "healer", names = { "restoration", "rigenerazione" } } } },
    { token = "MAGE", primary = "dps", roles = { "dps" }, ranged = true,
      trees = { { key = "arcane", role = "dps", names = { "arcane", "arcano" } },
                { key = "fire", role = "dps", names = { "fire", "fuoco" } },
                { key = "frost", role = "dps", names = { "frost", "gelo" } } } },
    { token = "WARLOCK", primary = "dps", roles = { "dps" }, ranged = true,
      trees = { { key = "affliction", role = "dps", names = { "affliction", "afflizione" } },
                { key = "demonology", role = "dps", names = { "demonology", "demonologia" } },
                { key = "destruction", role = "dps", names = { "destruction", "distruzione" } } } },
    -- Il Feral e' ambiguo (tank o dps in mischia): si presume dps, `alt = "tank"`: l'utente puo' correggere con un override.
    { token = "DRUID", primary = "dps", roles = { "dps", "tank", "healer" },
      trees = { { key = "balance", role = "dps", names = { "balance", "equilibrio" } },
                { key = "feral", role = "dps", alt = "tank", names = { "feral", "ferino" } },
                { key = "restoration", role = "healer", names = { "restoration", "rigenerazione" } } } },
}
Player.CLASSES = CLASSES
Player.ROLES = { "tank", "healer", "dps" }

local byToken = {}
for i, c in ipairs(CLASSES) do c.order = i; byToken[c.token] = c end

function Player:GetClassInfo(token) return byToken[token] end

-- Classi presenti nel client (sonda GetClassInfo); se la sonda non da' risultati si restituiscono tutte (degrado sicuro).
function Player:ListClasses(onlyPresent)
    if not onlyPresent or not GetClassInfo then return CLASSES end
    local present, n = {}, 0
    for i = 1, 40 do
        local ok, _, token = pcall(GetClassInfo, i)
        if not ok or not token then break end
        present[token] = true; n = n + 1
    end
    if n == 0 then return CLASSES end
    local list = {}
    for _, c in ipairs(CLASSES) do if present[c.token] then list[#list + 1] = c end end
    return list
end

local ROLE_FROM_GROUP = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }

local function charKey() return Badb.DB and Badb.DB.char end

local function num(v)
    if v == nil or Compat.IsSecret(v) or type(v) ~= "number" then return nil end
    return v
end

-- ---------------------------------------------------------------- talenti
function Player:GetNumTalentGroups()
    for _, fn in ipairs({ "GetNumTalentGroups", "GetNumSpecGroups" }) do
        local f = _G[fn]
        if f then
            local ok, n = pcall(f)
            n = ok and num(n)
            if n and n >= 1 then return math.floor(n) end
        end
    end
    return 1
end

function Player:GetTalentGroup()
    for _, fn in ipairs({ "GetActiveTalentGroup", "GetActiveSpecGroup" }) do
        local f = _G[fn]
        if f then
            local ok, g = pcall(f)
            g = ok and num(g)
            if g and g >= 1 then return math.floor(g) end
        end
    end
    return 1
end

-- Provider aggiuntivi (es. per C_ClassTalents/C_Traits, non coperti qui perche' non verificati):
-- fn(group) -> { {name=, points=, icon=}, ... } | nil
function Player:RegisterTreeProvider(fn)
    if type(fn) == "function" then table.insert(self.providers, fn) end
end

-- Classic (name, icon, points, ...) oppure Cata+ (id, name, desc, icon, points, ...): riconosciuti dal tipo del primo ritorno.
local function readTalentTabs(group)
    if not (GetNumTalentTabs and GetTalentTabInfo) then return nil end
    local okN, n = pcall(GetNumTalentTabs, false, false)
    n = okN and num(n)
    if not n or n < 1 then return nil end
    local trees = {}
    for i = 1, math.min(n, 5) do
        local r = { pcall(GetTalentTabInfo, i, false, false, group) }
        if not r[1] then return nil end
        local name, icon, points
        if type(r[2]) == "number" and type(r[3]) == "string" then
            name, icon, points = r[3], r[5], r[6]
        else
            name, icon, points = r[2], r[3], r[4]
        end
        if type(name) ~= "string" or Compat.IsSecret(name) then return nil end
        trees[i] = { index = i, name = name, icon = icon, points = num(points) or 0 }
    end
    return trees
end

local function readMainlineSpec()
    if not GetSpecialization or not GetSpecializationInfo then return nil end
    local ok, spec = pcall(GetSpecialization)
    spec = ok and num(spec)
    if not spec then return nil end
    local r = { pcall(GetSpecializationInfo, spec) }
    if not r[1] then return nil end
    local role = r[6]
    if type(role) ~= "string" and GetSpecializationRole then
        local okR, rr = pcall(GetSpecializationRole, spec)
        role = okR and rr or nil
    end
    local mapped = ROLE_FROM_GROUP[role]
    return { { index = spec, name = type(r[3]) == "string" and r[3] or tostring(spec), points = 1, role = mapped } }
end

function Player:GetTrees(group)
    group = group or self:GetTalentGroup()
    local trees = readTalentTabs(group)
    local source = trees and "talent-tabs"
    if not trees then
        for _, fn in ipairs(self.providers) do
            local ok, t = pcall(fn, group)
            if ok and type(t) == "table" and #t > 0 then trees, source = t, "provider"; break end
        end
    end
    if not trees then
        trees = readMainlineSpec()
        source = trees and "specialization"
    end
    return trees, source
end

-- Albero con piu' punti; nil se nessun punto o pareggio al primo posto (ambiguo: meglio non indovinare).
function Player:GetDominantTree(group, trees)
    trees = trees or self:GetTrees(group)
    if not trees then return nil end
    local best, tie = nil, false
    for _, t in ipairs(trees) do
        if (t.points or 0) > 0 then
            if not best or t.points > best.points then best, tie = t, false
            elseif t.points == best.points then tie = true end
        end
    end
    if not best or tie then return nil end
    return best
end

local function matchTree(classInfo, tree)
    if not classInfo or not tree then return nil end
    if tree.role then return { role = tree.role, how = "specialization" } end
    local lname = (tree.name or ""):lower()
    for i, def in ipairs(classInfo.trees) do
        for _, hint in ipairs(def.names) do
            if lname:find(hint, 1, true) then return { role = def.role, alt = def.alt, key = def.key, how = "tree-name", index = i } end
        end
    end
    local def = classInfo.trees[tree.index or 0]
    if def then return { role = def.role, alt = def.alt, key = def.key, how = "tree-index", index = tree.index } end
end

-- ---------------------------------------------------------------- ruolo
function Player:SetRoleOverride(role, group)
    if role ~= nil and not (role == "tank" or role == "healer" or role == "dps") then return false, L["ruolo non valido"] end
    local sv, key = Badb.DB and Badb.DB.sv, charKey()
    if not sv or not key then return false, L["database non pronto"] end
    sv.global.roleOverrides = type(sv.global.roleOverrides) == "table" and sv.global.roleOverrides or {}
    local perChar = type(sv.global.roleOverrides[key]) == "table" and sv.global.roleOverrides[key] or {}
    sv.global.roleOverrides[key] = perChar
    perChar[group or "*"] = role
    self:Invalidate()
    return true
end

local function getOverride(group)
    local sv, key = Badb.DB and Badb.DB.sv, charKey()
    local o = sv and key and type(sv.global.roleOverrides) == "table" and sv.global.roleOverrides[key]
    if type(o) ~= "table" then return nil end
    local r = o[group] or o["*"]
    if r == "tank" or r == "healer" or r == "dps" then return r end
end

local function groupRole()
    if not (UnitGroupRolesAssigned and IsInGroup and IsInGroup()) then return nil end
    local ok, r = pcall(UnitGroupRolesAssigned, "player")
    return ok and ROLE_FROM_GROUP[r] or nil
end

local function compute()
    local okC, _, classToken = pcall(UnitClass, "player")
    local token = okC and classToken or nil
    if type(token) ~= "string" or Compat.IsSecret(token) then token = nil end
    local info = token and byToken[token]
    local group = Player:GetTalentGroup()
    local trees, treeSource = Player:GetTrees(group)
    local dominant = Player:GetDominantTree(group, trees)
    local match = matchTree(info, dominant)

    local role, source, confidence, alt
    local ov = getOverride(group)
    local gr = groupRole()
    if ov then role, source, confidence = ov, "override", "high"
    elseif gr then role, source, confidence = gr, "group", "high"
    elseif match then
        role, alt = match.role, match.alt
        source = match.how
        confidence = (match.how == "tree-index" and "medium") or (alt and "medium") or "high"
    elseif info then role, source, confidence = info.primary, "class", "low"
    else role, source, confidence = "dps", "class", "low" end

    local okL, level = pcall(function() return UnitLevel and UnitLevel("player") end)
    return {
        class = token, classInfo = info, level = okL and num(level) or nil,
        talentGroup = group, numTalentGroups = Player:GetNumTalentGroups(),
        trees = trees, treeSource = treeSource,
        tree = dominant and dominant.name or nil, treeKey = match and match.key or nil,
        role = role, roleSource = source, roleConfidence = confidence, altRole = alt,
        roleAmbiguous = (info and #info.roles > 1 and confidence ~= "high") or alt ~= nil,
    }
end

local function signature(s)
    return table.concat({ tostring(s.class), tostring(s.talentGroup), tostring(s.role), tostring(s.roleSource),
        tostring(s.tree), tostring(s.level) }, "|")
end

-- Snapshot memorizzato: si ricalcola solo dopo Invalidate() (eventi di talenti/gruppo/livello).
function Player:GetSnapshot()
    if not self.cache then
        local ok, snap = pcall(compute)
        if not ok then
            Logger:Error("PlayerInfo: %s", tostring(snap))
            snap = { role = "dps", roleSource = "class", roleConfidence = "low", talentGroup = 1, numTalentGroups = 1 }
        end
        self.cache = snap
    end
    return self.cache
end

function Player:GetRole() local s = self:GetSnapshot(); return s.role, s.roleSource, s.roleConfidence end
function Player:GetClass() return self:GetSnapshot().class end

function Player:Invalidate()
    local old = self.cache and signature(self.cache)
    self.cache = nil
    local snap = self:GetSnapshot()
    if old and old ~= signature(snap) then Events:Fire("BADB_PLAYER_CHANGED", snap) end
end

for _, ev in ipairs({ "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_TALENT_UPDATE",
    "CHARACTER_POINTS_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED" }) do
    Events:On(Player, ev, function() Player:Invalidate() end)
end
