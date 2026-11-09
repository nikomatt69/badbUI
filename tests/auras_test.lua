-- Test: motore aure curate (Auras), aure sulle nameplate (NameplateAuras), avvisi (Alerts).
-- Le API aure/nameplate/gruppo del client sono simulate qui (non nel mock condiviso) e rimosse
-- alla fine di ogni test, cosi' le altre suite non le vedono.
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end
local function ok(v, msg) if not v then error(msg or "condizione falsa", 2) end end

local GLOBALS = { "C_UnitAuras", "C_Spell", "C_NamePlate", "AuraUtil", "UnitAura", "UnitCanAttack", "UnitIsUnit",
    "UnitIsFriend", "UnitExists", "UnitGroupRolesAssigned", "IsInInstance", "IsInRaid", "IsInGroup",
    "GetNumGroupMembers", "GetNumSubgroupMembers", "PlaySound", "issecure", "UnitName", "SOUNDKIT" }

local NAMES = { [118] = "Polimorfismo", [11958] = "Blocco di Ghiaccio", [116] = "Dardo di Gelo",
    [172] = "Corruzione", [853] = "Martello della Giustizia", [15487] = "Silenzio", [122] = "Nova di Gelo",
    [871] = "Muro di Scudi", [12042] = "Potere Arcano", [430] = "Bere", [3600] = "Vincolo Terrestre",
    [5782] = "Paura", [1022] = "Benedizione della Protezione" }

local function setup(Mock)
    local saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
    local W = { auras = {}, plates = {}, friends = {}, names = {}, roles = {}, exists = {}, sounds = 0,
        calls = {}, instance = { true, "pvp" }, raid = false, members = 0, me = {}, nextId = 0 }
    W.saved = saved
    C_UnitAuras = {
        GetAuraDataByIndex = function(unit, i, filter)
            W.calls[#W.calls + 1] = filter
            local base, extra = filter:match("^(%u+)|?(.*)$")
            local list = (W.auras[unit] or {})[base] or {}
            if extra ~= "" then
                local sub = {}
                for _, a in ipairs(list) do if a.tags and a.tags[extra] then sub[#sub + 1] = a end end
                list = sub
            end
            return list[i]
        end,
    }
    C_Spell = { GetSpellName = function(id) return NAMES[id] end }
    issecure = function() return true end
    C_NamePlate = {
        GetNamePlateForUnit = function(unit) return W.plates[unit] end,
        GetNamePlates = function()
            local l = {}
            for _, p in pairs(W.plates) do l[#l + 1] = p end
            return l
        end,
    }
    UnitCanAttack = function(_, unit)
        if W.secretHostility then return Mock.Secret() end
        return not W.friends[unit]
    end
    UnitIsUnit = function(a, b)
        if a == b then return true end
        return (W.me[a] and b == "player") or false
    end
    UnitIsFriend = function(_, unit) return W.friends[unit] or false end
    UnitExists = function(unit) return W.exists[unit] or false end
    UnitGroupRolesAssigned = function(unit)
        if W.secretRoles then return Mock.Secret() end
        return W.roles[unit] or "NONE"
    end
    UnitName = function(unit)
        if W.secretNames then return Mock.Secret() end
        return W.names[unit] or "Tester"
    end
    IsInInstance = function() return W.instance[1], W.instance[2] end
    IsInRaid = function() return W.raid end
    IsInGroup = function() return W.members > 0 end
    GetNumGroupMembers = function() return W.members end
    GetNumSubgroupMembers = function() return W.members end
    PlaySound = function() W.sounds = W.sounds + 1 end
    SOUNDKIT = { RAID_WARNING = 8959 }
    BadbUI.Player.GetClass = function() return W.class or "MAGE" end
    BadbUI.Auras:BuildIndex()
    BadbUI.Auras.clientFilterList = nil
    return W
end

local function teardown(W)
    for _, k in ipairs(GLOBALS) do _G[k] = W.saved[k] end
end

-- Aura finta in stile C_UnitAuras.
local function aura(W, Mock, id, o)
    o = o or {}
    W.nextId = W.nextId + 1
    return {
        spellId = id, name = o.name or NAMES[id] or ("Spell" .. tostring(id)), icon = o.icon or ("icon" .. tostring(id)),
        duration = o.duration or 8, expirationTime = o.expirationTime or (Mock.time + (o.duration or 8)),
        applications = o.applications or 0, isFromPlayerOrPlayerPet = o.own or false,
        sourceUnit = o.source, auraInstanceID = o.instance or W.nextId, tags = o.tags,
    }
end

local function setAuras(W, unit, helpful, harmful) W.auras[unit] = { HELPFUL = helpful or {}, HARMFUL = harmful or {} } end

local function addPlate(W, Mock, unit, o)
    o = o or {}
    local uf = Mock.NewObject("Frame")
    uf.healthBar = Mock.NewObject("StatusBar")
    uf.BuffFrame = Mock.NewObject("Frame")
    uf.unit = unit
    if o.forbidden then uf.__forbidden = true end
    W.plates[unit] = { namePlateUnitToken = unit, UnitFrame = uf }
    if o.friend then W.friends[unit] = true end
    return uf
end

local function fireAura(Mock, unit) Mock.Fire("UNIT_AURA", unit, { isFullUpdate = true }) end

local T = {}
local function test(name, fn)
    T[name] = function(Mock)
        local W = setup(Mock)
        local okRun, err = pcall(fn, Mock, W)
        teardown(W)
        if not okRun then error(err, 0) end
    end
end

local function NP() return BadbUI.Modules:Get("NameplateAuras") end
local function AL() return BadbUI.Modules:Get("Alerts") end
local function stateOf(uf) return NP()._plates[uf] end

------------------------------------------------------------------------------
-- Database
------------------------------------------------------------------------------
test("database: categorie complete, ID unici, classi Forever", function()
    local D, A = BadbUI.AuraData, BadbUI.Auras
    local seen = {}
    for _, c in ipairs(D.CATEGORIES) do
        ok(type(D.SPELLS[c.key]) == "table" and #D.SPELLS[c.key] > 0, "categoria senza aure: " .. c.key)
        ok(type(c.priority) == "number" and c.color and c.title, "categoria incompleta: " .. c.key)
        for _, fam in ipairs(D.SPELLS[c.key]) do
            ok(#fam > 0, "famiglia vuota in " .. c.key)
            for _, id in ipairs(fam) do
                ok(type(id) == "number" and id > 0, "ID non valido")
                ok(not seen[id], "ID duplicato " .. id .. " in " .. c.key .. " e " .. tostring(seen[id]))
                seen[id] = c.key
            end
        end
    end
    for k in pairs(D.SPELLS) do ok(A.categories[k], "SPELLS ha una categoria non dichiarata: " .. k) end
    local classes = 0
    for _, info in ipairs(BadbUI.Player.CLASSES) do
        classes = classes + 1
        ok(D.CLASS_DEBUFFS[info.token] and #D.CLASS_DEBUFFS[info.token] > 0, "debuff curati mancanti per " .. info.token)
    end
    for token in pairs(D.CLASS_DEBUFFS) do ok(BadbUI.Player:GetClassInfo(token), "classe sconosciuta " .. token) end
    eq(classes, 9, "classi Forever")
end)

------------------------------------------------------------------------------
-- Classificazione
------------------------------------------------------------------------------
test("classifica per ID e per nome localizzato (rank nuovi)", function(Mock, W)
    local A = BadbUI.Auras
    eq(A:Classify({ spellId = 12826 }), "cc", "rank alto di Polymorph")
    eq((A:Classify({ spellId = 11958 })), "immunity")
    local cat, via = A:Classify({ spellId = 999001, name = "Polimorfismo" })
    eq(cat, "cc", "ID sconosciuto ma nome noto"); eq(via, "name")
    eq(A:Classify({ spellId = 999002, name = "Qualcosa" }), nil)
    eq(A:Classify(nil), nil)
    eq(A:Classify({}), nil)
    A:Set("matchByName", false)
    eq(A:Classify({ spellId = 999001, name = "Polimorfismo" }), nil, "riconoscimento per nome spento")
    eq(A:Classify({ spellId = 118 }), "cc", "gli ID restano")
end)

test("valori secret: nessun errore, categoria 'secret'", function(Mock)
    local A = BadbUI.Auras
    local cat, via = A:Classify({ spellId = Mock.Secret(), name = Mock.Secret() })
    eq(cat, nil); eq(via, "secret")
    eq(A:Classify({ spellId = Mock.Secret(), name = "Polimorfismo" }), "cc", "il nome leggibile basta")
    eq(A:IsOwn({ isFromPlayerOrPlayerPet = Mock.Secret(), sourceUnit = "player" }), true, "ripiego su sourceUnit")
    eq(A:IsOwn({ isFromPlayerOrPlayerPet = Mock.Secret(), sourceUnit = Mock.Secret() }), nil)
    eq(A:IsOwn({ isFromPlayerOrPlayerPet = false }), false)
end)

test("elenco personale: aggiungi, nascondi, rimuovi, errori", function(Mock, W)
    local A = BadbUI.Auras
    local changed = 0
    BadbUI.Events:On("t", "BADB_AURAS_CHANGED", function() changed = changed + 1 end)
    ok(A:SetCustom(118, "hide"))
    eq(A:Classify({ spellId = 118 }), nil, "nascosta")
    ok(A:SetCustom("  Mio Buff ", "offensive"))
    eq(A:Classify({ spellId = 5, name = "mio buff" }), "offensive", "nome case-insensitive e trim")
    ok(A:SetCustom("12294", "defensive"))
    eq(A:Classify({ spellId = 12294 }), "defensive", "ID come testo")
    ok(changed >= 3, "evento di aggiornamento")
    local okBad, err = A:SetCustom(118, "boh")
    eq(okBad, false); ok(err:find("categoria"))
    eq((A:SetCustom("   ", "cc")), false)
    eq((A:SetCustom({}, "cc")), false)
    eq(#A:ListCustom(), 3)
    eq(BadbUI.DB:Get("Auras", "custom")["118"], "hide", "salvato nel profilo")
    ok(A:SetCustom(118, nil))
    eq(A:Classify({ spellId = 118 }), "cc", "rimossa: torna al default")
    A:ResetCustom()
    eq(#A:ListCustom(), 0)
    BadbUI.Events:Off("t", "BADB_AURAS_CHANGED")
end)

test("aura nascosta non diventa nemmeno 'mio debuff'", function(Mock, W)
    local A = BadbUI.Auras
    A:SetCustom(116, "hide")
    setAuras(W, "nameplate1", {}, { aura(W, Mock, 116, { own = true }) })
    eq(#A:Collect("nameplate1", { own = "all" }), 0)
end)

------------------------------------------------------------------------------
-- Raccolta
------------------------------------------------------------------------------
test("Collect: priorita', filtri, massimo", function(Mock, W)
    local A = BadbUI.Auras
    setAuras(W, "u", { aura(W, Mock, 871), aura(W, Mock, 11958), aura(W, Mock, 12345) },
        { aura(W, Mock, 3600), aura(W, Mock, 118), aura(W, Mock, 15487) })
    local list = A:Collect("u")
    eq(#list, 5, "l'aura non curata e' esclusa")
    eq(list[1].category, "immunity"); eq(list[2].category, "cc"); eq(list[3].category, "silence")
    eq(list[4].category, "defensive"); eq(list[5].category, "snare")
    eq(#A:Collect("u", { max = 2 }), 2)
    eq(#A:Collect("u", { categories = { cc = true } }), 1)
    eq(#A:Collect("u", { helpful = false }), 3)
    eq(A:GetHighest("u", { "silence", "snare" }).category, "silence", "GetHighest con lista")
    eq(A:IsCrowdControlled("u").category, "cc")
    A:Set("priorities", { snare = 999 })
    eq(A:Collect("u")[1].category, "snare", "priorita' personalizzata")
end)

test("Collect: debuff propri curati, tutti o nessuno", function(Mock, W)
    local A = BadbUI.Auras
    setAuras(W, "u", {}, { aura(W, Mock, 172, { own = true }), aura(W, Mock, 7777, { own = true }),
        aura(W, Mock, 172, { own = false }) })
    eq(#A:Collect("u", { own = "off" }), 0)
    local cur = A:Collect("u", { own = "curated", class = "WARLOCK" })
    eq(#cur, 1, "solo Corruzione propria"); eq(cur[1].category, "own"); eq(cur[1].own, true)
    eq(#A:Collect("u", { own = "curated", class = "MAGE" }), 0, "non curata per il mago")
    eq(#A:Collect("u", { own = "all" }), 2, "tutti i miei, mai quelli degli altri")
    eq(#A:Collect("u", { own = "curated", class = "WARLOCK", max = 0 }), 0)
end)

test("Collect: con dati secret i miei debuff restano visibili", function(Mock, W)
    local A = BadbUI.Auras
    setAuras(W, "u", {}, { aura(W, Mock, 172, { own = true }) })
    W.auras.u.HARMFUL[1].spellId, W.auras.u.HARMFUL[1].name = Mock.Secret(), Mock.Secret()
    local list = A:Collect("u", { own = "curated", class = "MAGE" })
    eq(#list, 1); eq(list[1].category, "own"); eq(list[1].via, "secret")
end)

test("ripiego filtri del client solo se il client li dichiara", function(Mock, W)
    local A = BadbUI.Auras
    local a = aura(W, Mock, 118, { tags = { CROWD_CONTROL = true } })
    a.spellId, a.name = Mock.Secret(), Mock.Secret()
    setAuras(W, "u", {}, { a })
    eq(#A:Collect("u"), 0, "nessun filtro dichiarato: niente")
    for _, f in ipairs(W.calls) do ok(not f:find("|", 1, true), "mai filtri inventati: " .. f) end
    AuraUtil = { AuraFilters = { CrowdControl = "CROWD_CONTROL" } }
    A:ProbeClientFilters()
    local list = A:Collect("u")
    eq(#list, 1); eq(list[1].category, "cc"); eq(list[1].via, "client")
    A:Set("clientFilters", false)
    eq(#A:Collect("u"), 0, "opzione spenta")
end)

test("ripiego client: un mio debuff secret diventa CC, senza doppioni", function(Mock, W)
    local A = BadbUI.Auras
    AuraUtil = { AuraFilters = { CrowdControl = "CROWD_CONTROL" } }
    A:ProbeClientFilters()
    local a = aura(W, Mock, 118, { own = true, tags = { CROWD_CONTROL = true } })
    a.spellId, a.name = Mock.Secret(), Mock.Secret()
    local b = aura(W, Mock, 116, { tags = {} })
    b.spellId, b.name = Mock.Secret(), Mock.Secret()
    setAuras(W, "u", {}, { a, b })
    local list = A:Collect("u", { own = "curated" })
    eq(#list, 1, "una sola voce per il CC proprio"); eq(list[1].category, "cc")
end)

test("ripiego su UnitAura e assenza totale di API", function(Mock, W)
    local A = BadbUI.Auras
    C_UnitAuras = nil
    UnitAura = function(unit, i, filter)
        if unit == "u" and filter == "HARMFUL" and i == 1 then
            return "Polimorfismo", "icon", 0, nil, 10, Mock.time + 10, "player", false, false, 118
        end
    end
    local list = A:Collect("u")
    eq(#list, 1); eq(list[1].category, "cc"); eq(list[1].own, true)
    UnitAura = nil
    eq(A:HasAuraAPI(), false)
    eq(#A:Collect("u"), 0, "nessuna API: lista vuota, nessun errore")
    eq(#A:Collect(nil), 0)
end)

test("API che lancia errori: nessuna propagazione", function(Mock, W)
    C_UnitAuras.GetAuraDataByIndex = function() error("boom") end
    eq(#BadbUI.Auras:Collect("u"), 0)
end)

------------------------------------------------------------------------------
-- Widget icona
------------------------------------------------------------------------------
test("icona: countdown, stack e durate secret", function(Mock, W)
    local A = BadbUI.Auras
    local f = A:CreateIcon(UIParent, 20)
    eq(f:IsShown(), false)
    local e = { category = "cc", aura = aura(W, Mock, 118, { duration = 10, expirationTime = 110, applications = 3 }) }
    A:SetIcon(f, e, "u")
    eq(f.icon:GetTexture(), "icon118"); eq(f.cd.__start, 100); eq(f.cd.__duration, 10)
    eq(f.count:GetText(), "3"); eq(f:IsShown(), true); eq(f.cd.__hideNumbers, false)
    -- senza durata: nessuno swipe
    e.aura.duration, e.aura.applications = 0, 1
    A:SetIcon(f, e, "u", { numbers = false })
    eq(f.cd:IsShown(), false); eq(f.count:GetText(), ""); eq(f.cd.__hideNumbers, true)
    -- durate secret: il client disegna tramite l'oggetto durata
    local used
    C_UnitAuras.GetAuraDuration = function(unit, id) return { unit = unit, id = id } end
    f.cd.SetCooldownFromDurationObject = function(_, obj) used = obj end
    e.aura.duration, e.aura.expirationTime, e.aura.applications = Mock.Secret(), Mock.Secret(), Mock.Secret()
    A:SetIcon(f, e, "u")
    ok(used and used.unit == "u", "oggetto durata passato al cooldown"); eq(f.cd:IsShown(), true)
    eq(f.count:GetText(), "", "stack secret senza API dedicata")
    C_UnitAuras.GetAuraApplicationDisplayCount = function() return "S" end
    A:SetIcon(f, e, "u")
    eq(f.count:GetText(), "S")
    -- nessuna API per le durate secret: swipe nascosto, nessun errore
    C_UnitAuras.GetAuraDuration = nil
    f.cd.SetCooldownFromDurationObject = false
    f.cd.SetCooldownFromExpirationTime = false
    A:SetIcon(f, e, "u")
    eq(f.cd:IsShown(), false)
    A:ClearIcon(f)
    eq(f:IsShown(), false); eq(f.entry, nil)
end)

------------------------------------------------------------------------------
-- Comandi
------------------------------------------------------------------------------
test("comando /badb aura", function(Mock, W)
    local A, S = BadbUI.Auras, BadbUI.Slash
    ok(S:Dispatch("aura add 12345 cc"))
    eq(A:Classify({ spellId = 12345 }), "cc")
    ok(S:Dispatch("aura add Scudo di Prova defensive"))
    eq(A:Classify({ name = "scudo di prova" }), "defensive", "nome con spazi")
    ok(S:Dispatch("aura add Paura nascondi"))
    eq(A:Classify({ name = "Paura" }), nil)
    ok(S:Dispatch("aura remove 12345"))
    eq(A:Classify({ spellId = 12345 }), nil)
    local before = #Mock.chat
    ok(S:Dispatch("aura add soloparola"))
    ok(#Mock.chat > before, "uso spiegato")
    ok(S:Dispatch("aura check 118"))
    ok(Mock.chat[#Mock.chat]:find("Polimorfismo"), "check mostra il nome")
    ok(S:Dispatch("aura status"))
    ok(Mock.chat[#Mock.chat - 1]:find("C_UnitAuras"), "status mostra l'API usata")
    local st = A:Status()
    ok(st.ids > 100 and st.names > 5, "indice popolato"); eq(#st.clientFilters, 0)
    ok(S:Dispatch("aura list")); ok(S:Dispatch("aura categories")); ok(S:Dispatch("aura reset")); ok(S:Dispatch("aura"))
    eq(#A:ListCustom(), 0)
end)

------------------------------------------------------------------------------
-- Nameplate
------------------------------------------------------------------------------
local function enemyScenario(W, Mock)
    local uf = addPlate(W, Mock, "nameplate1")
    setAuras(W, "nameplate1",
        { aura(W, Mock, 11958), aura(W, Mock, 12042), aura(W, Mock, 430) },
        { aura(W, Mock, 116, { own = true }), aura(W, Mock, 118), aura(W, Mock, 122), aura(W, Mock, 7777, { own = true }) })
    return uf
end

test("nameplate: disattivato di default", function(Mock, W)
    eq(not NP().enabled, true)
    local uf = enemyScenario(W, Mock)
    Mock.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    eq(stateOf(uf), nil, "nessuna decorazione")
    eq(uf.BuffFrame:GetAlpha(), 1)
end)

test("nameplate nemica: CC a destra, difensivi a sinistra, miei debuff sopra", function(Mock, W)
    local uf = enemyScenario(W, Mock)
    BadbUI.Modules:SetEnabled("NameplateAuras", true)
    local st = stateOf(uf)
    ok(st, "decorata all'attivazione")
    eq(st.cc.icon:GetTexture(), "icon118", "Polymorph nello slot CC"); eq(st.cc:IsShown(), true)
    eq(st.buffs[1].icon:GetTexture(), "icon11958", "immunita' per prima")
    eq(st.buffs[2].icon:GetTexture(), "icon12042"); eq(st.buffs[3].icon:GetTexture(), "icon430")
    eq(#st.last.row, 1, "solo il mio Dardo di Gelo (curato per il mago)")
    eq(st.row[1].icon:GetTexture(), "icon116")
    eq(uf.BuffFrame:GetAlpha(), 0, "aure Blizzard nascoste")
end)

test("nameplate: modalita' debuff propri e limiti", function(Mock, W)
    local uf = enemyScenario(W, Mock)
    local M = NP()
    BadbUI.Modules:SetEnabled("NameplateAuras", true)
    M:Set("ownDebuffs", "all")
    eq(#stateOf(uf).last.row, 2, "tutti i miei")
    M:Set("ownDebuffs", "off")
    eq(#stateOf(uf).last.row, 0)
    eq(stateOf(uf).row[1]:IsShown(), false, "icone nascoste")
    M:Set("maxBuffs", 1)
    eq(#stateOf(uf).last.buffs, 1); eq(stateOf(uf).buffs[2]:IsShown(), false)
    M:Set("maxBuffs", 0)
    eq(#stateOf(uf).last.buffs, 0)
    M:Set("categories.cc", false)
    eq(stateOf(uf).last.cc.category, "root", "senza CC resta il root")
    M:Set("categories.root", false)
    eq(stateOf(uf).last.cc, nil); eq(stateOf(uf).cc:IsShown(), false)
    M:Set("ownDebuffs", "curated")
    eq(#stateOf(uf).last.row, 1, "il mio Dardo di Gelo (snare) resta tra i miei debuff")
end)

test("nameplate: rallentamenti degli altri solo se richiesti", function(Mock, W)
    local uf = addPlate(W, Mock, "nameplate1")
    setAuras(W, "nameplate1", {}, { aura(W, Mock, 3600) })
    local M = NP()
    BadbUI.Modules:SetEnabled("NameplateAuras", true)
    eq(#stateOf(uf).last.row, 0)
    M:Set("categories.snare", true)
    eq(#stateOf(uf).last.row, 1)
end)

test("nameplate alleata: solo CC, tutto o niente", function(Mock, W)
    local uf = addPlate(W, Mock, "nameplate2", { friend = true })
    setAuras(W, "nameplate2", { aura(W, Mock, 871) }, { aura(W, Mock, 853), aura(W, Mock, 116, { own = true }) })
    local M = NP()
    BadbUI.Modules:SetEnabled("NameplateAuras", true)
    local st = stateOf(uf)
    eq(st.last.cc.category, "cc"); eq(#st.last.buffs, 0); eq(#st.last.row, 0, "mai i miei debuff sugli alleati")
    M:Set("friendly", "all")
    eq(#stateOf(uf).last.buffs, 1)
    M:Set("friendly", "off")
    eq(stateOf(uf).last.cc, nil); eq(stateOf(uf).cc:IsShown(), false)
end)

test("nameplate: forbidden, barra personale, unita' senza nameplate", function(Mock, W)
    local f = addPlate(W, Mock, "nameplate3", { forbidden = true })
    setAuras(W, "nameplate3", {}, { aura(W, Mock, 118) })
    local me = addPlate(W, Mock, "nameplate4")
    W.me.nameplate4 = true
    setAuras(W, "nameplate4", {}, { aura(W, Mock, 118) })
    BadbUI.Modules:SetEnabled("NameplateAuras", true)
    eq(stateOf(f), nil, "forbidden mai toccata")
    eq(stateOf(me).last, nil, "barra personale senza aure")
    NP():UpdateUnit("nameplate99")
    NP():UpdateUnit(nil)
    fireAura(Mock, "party1") -- non nameplate: ignorata
end)

test("nameplate: ostilita' secret trattata da nemico, nessun errore", function(Mock, W)
    local uf = enemyScenario(W, Mock)
    W.secretHostility = true
    for _, a in ipairs(W.auras.nameplate1.HARMFUL) do a.duration, a.expirationTime = Mock.Secret(), Mock.Secret() end
    BadbUI.Modules:SetEnabled("NameplateAuras", true)
    eq(stateOf(uf).last.cc.category, "cc")
end)

test("nameplate: UNIT_AURA aggiorna, coalescato per frame", function(Mock, W)
    local uf = enemyScenario(W, Mock)
    local M = NP()
    BadbUI.Modules:SetEnabled("NameplateAuras", true)
    local queued = {}
    local After = BadbUI.Compat.After
    BadbUI.Compat.After = function(_, fn) queued[#queued + 1] = fn end
    local calls, orig = 0, M.UpdateUnit
    M.UpdateUnit = function(self, unit) calls = calls + 1; return orig(self, unit) end
    table.remove(W.auras.nameplate1.HARMFUL, 2) -- Polymorph finito
    for _ = 1, 5 do fireAura(Mock, "nameplate1") end
    eq(#queued, 1, "un solo flush in coda"); eq(calls, 0)
    queued[1]()
    eq(calls, 1, "un solo ridisegno")
    M.UpdateUnit = orig
    BadbUI.Compat.After = After
    eq(stateOf(uf).last.cc.category, "root", "il root prende lo slot")
    W.auras.nameplate1.HARMFUL = {}
    fireAura(Mock, "nameplate1")
    eq(stateOf(uf).cc:IsShown(), false)
end)

test("nameplate: rimozione e riciclo della nameplate", function(Mock, W)
    local uf = enemyScenario(W, Mock)
    BadbUI.Modules:SetEnabled("NameplateAuras", true)
    Mock.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    local st = stateOf(uf)
    eq(st.cc:IsShown(), false); eq(st.buffs[1]:IsShown(), false); eq(st.unit, nil)
    eq(uf.BuffFrame:GetAlpha(), 1, "aure Blizzard ripristinate")
    -- lo stesso frame torna per un'altra unita'
    W.plates.nameplate1 = nil
    W.plates.nameplate7 = { namePlateUnitToken = "nameplate7", UnitFrame = uf }
    setAuras(W, "nameplate7", {}, { aura(W, Mock, 15487) })
    Mock.Fire("NAME_PLATE_UNIT_ADDED", "nameplate7")
    eq(stateOf(uf).unit, "nameplate7"); eq(stateOf(uf).last.cc.category, "silence")
    eq(#stateOf(uf).last.buffs, 0, "niente residui dell'unita' precedente")
    eq(stateOf(uf).buffs[1]:IsShown(), false)
    eq(NP()._unitToUF.nameplate1, nil)
end)

test("nameplate: elenco personale e opzioni ridisegnano subito", function(Mock, W)
    local uf = enemyScenario(W, Mock)
    BadbUI.Modules:SetEnabled("NameplateAuras", true)
    BadbUI.Auras:SetCustom(118, "hide")
    eq(stateOf(uf).last.cc.category, "root", "Polymorph nascosto dall'utente")
    NP():Set("hideBlizzard", false)
    eq(uf.BuffFrame:GetAlpha(), 1, "aure Blizzard tornano visibili")
    NP():Set("hideBlizzard", true)
    eq(uf.BuffFrame:GetAlpha(), 0)
end)

test("nameplate: disattivazione ripristina e smette di disegnare", function(Mock, W)
    local uf = enemyScenario(W, Mock)
    BadbUI.Modules:SetEnabled("NameplateAuras", true)
    BadbUI.Modules:SetEnabled("NameplateAuras", false)
    eq(uf.BuffFrame:GetAlpha(), 1); eq(stateOf(uf).cc:IsShown(), false)
    local uf2 = addPlate(W, Mock, "nameplate8")
    setAuras(W, "nameplate8", {}, { aura(W, Mock, 118) })
    Mock.Fire("NAME_PLATE_UNIT_ADDED", "nameplate8")
    fireAura(Mock, "nameplate1")
    eq(stateOf(uf2), nil, "nessuna decorazione dopo il disable")
    eq(stateOf(uf).cc:IsShown(), false)
end)

test("nameplate: richiede il modulo Auras", function(Mock, W)
    BadbUI.Modules:SetEnabled("Auras", false)
    BadbUI.Modules:SetEnabled("NameplateAuras", true)
    eq(not NP().enabled, true, "dipendenza spenta")
    BadbUI.Modules:SetEnabled("Auras", true)
end)

------------------------------------------------------------------------------
-- Avvisi
------------------------------------------------------------------------------
local function party(W, n)
    W.members = n
    for i = 1, n do W.exists["party" .. i] = true; W.names["party" .. i] = "Amico" .. i end
end

test("avvisi: healer in CC nel BG, suono una volta, sparisce a fine CC", function(Mock, W)
    party(W, 2)
    W.roles.party2 = "HEALER"
    setAuras(W, "party2", {}, { aura(W, Mock, 5782) })
    BadbUI.Modules:SetEnabled("Alerts", true)
    local M = AL()
    eq(M.banner:IsShown(), true, "banner visibile")
    eq(M.banner.rows[1].name:GetText(), "Amico2"); eq(M.banner.title:GetText(), "Healer in CC")
    eq(W.sounds, 1)
    fireAura(Mock, "party2")
    eq(W.sounds, 1, "stesso CC: nessun nuovo suono")
    W.auras.party2.HARMFUL = {}
    fireAura(Mock, "party2")
    eq(M.banner:IsShown(), false)
    Mock.time = Mock.time + 10
    W.auras.party2.HARMFUL = { aura(W, Mock, 853) }
    fireAura(Mock, "party2")
    eq(W.sounds, 2, "nuovo CC: nuovo suono"); eq(M.banner:IsShown(), true)
    W.auras.party2.HARMFUL = {}
    fireAura(Mock, "party2")
    W.auras.party2.HARMFUL = { aura(W, Mock, 853) }
    fireAura(Mock, "party2")
    eq(W.sounds, 2, "suono limitato nel tempo")
end)

test("avvisi: contesto, silence opzionale, non healer", function(Mock, W)
    party(W, 2)
    W.roles.party1 = "HEALER"
    W.instance = { false, "none" }
    setAuras(W, "party1", {}, { aura(W, Mock, 15487) })
    setAuras(W, "party2", {}, { aura(W, Mock, 118) })
    BadbUI.Modules:SetEnabled("Alerts", true)
    local M = AL()
    eq(M.banner and M.banner:IsShown() or false, false, "fuori dal BG: niente")
    M:Set("when", "always")
    eq(M.banner:IsShown(), true, "silence conta")
    eq(#M:GetRows(), 1, "party2 non e' healer")
    M:Set("includeSilence", false)
    eq(M.banner:IsShown(), false)
    M:Set("when", "group")
    W.auras.party1.HARMFUL = { aura(W, Mock, 118) }
    fireAura(Mock, "party1")
    eq(M.banner:IsShown(), true)
    M:Set("sound", false)
    W.sounds = 0
    M:PlayAlertSound()
    eq(W.sounds, 0, "suono spento")
end)

test("avvisi: healer manuali, nomi e ruoli secret", function(Mock, W)
    party(W, 1)
    setAuras(W, "party1", {}, { aura(W, Mock, 118) })
    BadbUI.Modules:SetEnabled("Alerts", true)
    local M = AL()
    eq(#M:GetRows(), 0, "nessun ruolo, nessun nome")
    ok(BadbUI.Slash:Dispatch("alert healer add  amico1 "))
    eq(#M:GetRows(), 1, "nome manuale (case-insensitive)")
    W.secretNames, W.secretRoles = true, true
    M:ScanAll()
    eq(#M:GetRows(), 0, "nome secret: il confronto manuale non si fa")
    W.secretNames, W.secretRoles = false, false
    M:ScanAll()
    eq(#M:GetRows(), 1)
    ok(BadbUI.Slash:Dispatch("alert healer remove Amico1"))
    eq(#M:GetRows(), 0)
    eq((M:SetManualHealer("  ", true)), false)
    ok(BadbUI.Slash:Dispatch("alert healers")); ok(BadbUI.Slash:Dispatch("alert status")); ok(BadbUI.Slash:Dispatch("alert"))
    ok(BadbUI.Slash:Dispatch("alert healer"))
end)

test("avvisi: nome secret mostrato senza errori", function(Mock, W)
    party(W, 1)
    W.roles.party1 = "HEALER"
    W.secretNames = true
    setAuras(W, "party1", {}, { aura(W, Mock, 118) })
    BadbUI.Modules:SetEnabled("Alerts", true)
    ok(type(AL().banner.rows[1].name:GetText()) == "table", "il secret va al widget cosi' com'e'")
end)

test("avvisi: raid, me escluso, focus amico senza doppioni", function(Mock, W)
    W.raid, W.members = true, 3
    for i = 1, 3 do W.exists["raid" .. i] = true; W.roles["raid" .. i] = "HEALER" end
    W.me.raid1 = true
    BadbUI.Modules:SetEnabled("Alerts", true)
    local M = AL()
    eq(M.watch.raid1, nil, "il giocatore non si sorveglia")
    eq(M.watch.raid2, "healer"); eq(M.watch.party1, nil)
    W.exists.focus, W.friends.focus = true, true
    M:Set("focusCC", true)
    eq(M.watch.focus, "focus")
    W.friends.focus = false
    M:ScanAll()
    eq(M.watch.focus, nil, "focus nemico ignorato")
    W.friends.focus = true
    local isUnit = UnitIsUnit
    UnitIsUnit = function(a, b) return (a == "raid2" and b == "focus") or isUnit(a, b) end
    M:ScanAll()
    eq(M.watch.focus, nil, "focus gia' sorvegliato come healer")
end)

test("avvisi: cambio gruppo toglie l'avviso, prova e disattivazione", function(Mock, W)
    party(W, 1)
    W.roles.party1 = "HEALER"
    setAuras(W, "party1", {}, { aura(W, Mock, 118) })
    BadbUI.Modules:SetEnabled("Alerts", true)
    local M = AL()
    eq(M.banner:IsShown(), true)
    W.members = 0
    Mock.Fire("GROUP_ROSTER_UPDATE")
    eq(M.banner:IsShown(), false, "uscito dal gruppo")
    local queued = {}
    local After = BadbUI.Compat.After
    BadbUI.Compat.After = function(_, fn) queued[#queued + 1] = fn end
    ok(M:Test())
    eq(M.banner:IsShown(), true); eq(M.banner.rows[1].name:GetText(), "Healer di prova")
    ok(M:Test()) -- seconda prova: il primo timer non deve chiudere la seconda
    queued[1]()
    eq(M.banner:IsShown(), true, "timer vecchio ignorato")
    queued[2]()
    eq(M.banner:IsShown(), false)
    BadbUI.Compat.After = After
    W.members = 1
    Mock.Fire("GROUP_ROSTER_UPDATE")
    eq(M.banner:IsShown(), true)
    BadbUI.Modules:SetEnabled("Alerts", false)
    eq(M.banner:IsShown(), false)
    fireAura(Mock, "party1")
    eq(M.banner:IsShown(), false, "nessun avviso dopo il disable")
end)

test("avvisi: piu' di tre unita' in CC", function(Mock, W)
    party(W, 4)
    for i = 1, 4 do
        W.roles["party" .. i] = "HEALER"
        setAuras(W, "party" .. i, {}, { aura(W, Mock, 118) })
    end
    BadbUI.Modules:SetEnabled("Alerts", true)
    local M = AL()
    eq(#M:GetRows(), 4)
    eq(M.banner.more:GetText(), "+1"); eq(M.banner.more:IsShown(), true)
end)

------------------------------------------------------------------------------
-- Preset
------------------------------------------------------------------------------
test("preset PvP: aure sulle nameplate e avviso healer attivi, categorie unite ai default", function(Mock, W)
    local P = BadbUI.Presets
    local spec = P:Build({ content = "pvp", role = "healer" })
    local lines = table.concat(P:Describe(spec), "\n")
    ok(lines:find("Aure curate"), "riepilogo aure"); ok(lines:find("healer"), "riepilogo avviso")
    ok(P:Apply(spec))
    eq(NP().enabled, true); eq(AL().enabled, true)
    eq(NP():Get("categories.snare"), true, "dal preset")
    eq(NP():Get("categories.cc"), true, "default conservato")
    eq(NP():Get("maxOwn"), 3, "override del ruolo healer")
    P:Undo()
    eq(not NP().enabled, true, "annulla: torna spento")
end)

return T
