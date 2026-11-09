-- Test del modulo Contexts (regole di cambio profilo per contesto)
-- Il mock non conosce le API di gruppo/istanza/spec: le simuliamo qui, dentro il test,
-- e le ripuliamo a fine caso. C_Timer.After e' sostituito da una coda controllabile.
local ROOT = (arg and arg[1]) or "."

local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 3) end
end

local API = { "IsInInstance", "IsInGroup", "IsInRaid", "GetNumGroupMembers", "UnitGroupRolesAssigned",
    "GetSpecialization", "GetActiveTalentGroup", "GetSpecializationRole", "GetSpecializationInfo",
    "UnitClass", "UnitLevel", "UnitIsPVP", "IsResting", "C_PvP", "LE_PARTY_CATEGORY_INSTANCE",
    "GetNumRaidMembers", "GetNumPartyMembers", "GetNumTalentTabs", "GetTalentTabInfo", "GetNumTalentGroups",
    "GetClassInfo", "GetInstanceInfo" }

-- Prepara ambiente: modulo caricato e riavviato con timer finti, mondo simulato.
local function setup(Mock)
    local env = { Mock = Mock, timers = {}, saved = {} }
    local Badb = BadbUI
    local M = Badb.Modules:Get("Contexts")
    if not M then -- TOC senza il modulo (worktree isolato): lo carichiamo noi
        local chunk = assert(loadfile(ROOT .. "/Modules/Contexts.lua"))
        chunk("BadbUI", { Badb = Badb })
        M = Badb.Modules:Get("Contexts")
    end
    env.M, env.DB, env.Events = M, Badb.DB, Badb.Events
    for _, name in ipairs(API) do env.saved[name] = _G[name] end

    -- Stato del mondo simulato. Ogni scrittura invalida la cache di Badb.Player (come farebbero
    -- gli eventi del client) cosi' il contesto riflette subito le API finte.
    local state = { inInstance = false, instance = "none", group = false, raid = false, role = "NONE",
        spec = 1, class = "WARRIOR", resting = false, pvp = false, trees = nil }
    local W = setmetatable({}, {
        __index = state,
        __newindex = function(_, k, v)
            state[k] = v
            if Badb.Player then Badb.Player:Invalidate() end
        end,
    })
    env.W = W
    env.player0, env.presets0 = Badb.Player, Badb.Presets
    IsInInstance = function() return W.inInstance, W.instance end
    IsInGroup = function() return W.group or W.raid end
    IsInRaid = function() return W.raid end
    UnitGroupRolesAssigned = function() return W.role end
    GetActiveTalentGroup = function() return W.spec end
    UnitClass = function() return "Localizzato", W.class, 1 end
    UnitIsPVP = function() return W.pvp end
    IsResting = function() return W.resting end
    GetNumTalentTabs = function() return W.trees and #W.trees or 0 end
    GetTalentTabInfo = function(i) local t = W.trees[i]; return t[1], "icon", t[2] end

    env.origAfter = C_Timer.After
    C_Timer.After = function(delay, fn) env.timers[#env.timers + 1] = { at = Mock.time + delay, fn = fn } end
    function env.advance(dt)
        Mock.time = Mock.time + dt
        local ran = true
        while ran do
            ran = false
            table.sort(env.timers, function(a, b) return a.at < b.at end)
            for i, t in ipairs(env.timers) do
                if t.at <= Mock.time then
                    table.remove(env.timers, i)
                    t.fn()
                    ran = true
                    break
                end
            end
        end
    end
    function env.settle() env.advance(M.DEBOUNCE + 0.01) end
    function env.setOpt(key, value)
        for _, p in pairs(env.DB.sv.profiles) do p.modules.Contexts[key] = value end
    end
    function env.cleanup()
        C_Timer.After = env.origAfter
        for _, name in ipairs(API) do _G[name] = env.saved[name] end
        Badb.Player, Badb.Presets = env.player0, env.presets0
        if Badb.Player then Badb.Player.cache = nil end
        Mock.combat = false
    end

    -- Riavvio pulito del modulo (con i timer finti) e profili di prova.
    Badb.Modules:Disable("Contexts")
    env.DB.sv.global.contextRules = nil
    env.DB:CopyProfile("Default", "Raid")
    env.DB:CopyProfile("Default", "PvP")
    env.DB:CopyProfile("Default", "Solo")
    for _, p in pairs(env.DB.sv.profiles) do p.modules.Contexts.switchCooldown = 0; p.modules.Contexts.enabled = true end
    Badb.Modules:Enable("Contexts")
    if Badb.Player then Badb.Player:Invalidate() end
    env.settle()
    M.stats.evals, M.stats.switches = 0, 0
    return env
end

local function case(fn)
    return function(Mock)
        local env = setup(Mock)
        local ok, err = pcall(fn, Mock, env)
        env.cleanup()
        if not ok then error(err, 0) end
    end
end

local T = {}

---------------------------------------------------------------------------
-- Rilevamento del contesto
---------------------------------------------------------------------------
T["contesto: ogni tipo di istanza (mai arena)"] = case(function(_, env)
    for _, t in ipairs({ "none", "party", "raid", "pvp", "scenario" }) do
        env.W.instance, env.W.inInstance = t, t ~= "none"
        eq(env.M:GetCurrent().instance, t, "istanza " .. t)
    end
    -- Su Forever non ci sono arene: un eventuale "arena" del client non genera mai il contesto "arena"
    env.W.instance, env.W.inInstance = "arena", true
    eq(env.M:GetCurrent().instance, "pvp", "arena non viene mai generata")
    env.W.instance, env.W.inInstance = "none", false
    C_PvP = { IsBattleground = function() return true end }
    eq(env.M:GetCurrent().instance, "pvp", "campo di battaglia via C_PvP")
    env.W.instance = "mistero"
    C_PvP = nil
    eq(env.M:GetCurrent().instance, "none", "tipo sconosciuto => none")
    -- "arena" resta valido come valore di regola (compatibilita' futura) ma non corrisponde mai
    local id = env.M:AddRule({ profile = "PvP", when = { instance = "arena" } })
    assert(id, "regola arena accettata")
    for _, t in ipairs({ "none", "party", "raid", "pvp", "scenario" }) do
        env.W.instance, env.W.inInstance = t, t ~= "none"
        eq(env.M:Evaluate(), nil, "la regola arena non scatta in " .. t)
    end
    for _, t in ipairs(env.M.GENERATED_INSTANCES) do assert(t ~= "arena") end
end)

T["contesto: gruppo, ruolo, spec, classe, riposo, flag PvP via Badb.Player"] = case(function(_, env)
    local c = env.M:GetCurrent()
    eq(c.group, "solo"); eq(c.spec, 1); eq(c.class, "WARRIOR"); eq(c.resting, false); eq(c.pvpFlag, false)
    eq(c.role, "dps", "senza dati: ruolo primario della classe"); eq(c.roleConfidence, "low", "confidenza esposta")
    env.W.group = true
    eq(env.M:GetCurrent().group, "party")
    env.W.raid = true
    eq(env.M:GetCurrent().group, "raid")
    env.W.role = "TANK"
    c = env.M:GetCurrent(); eq(c.role, "tank"); eq(c.roleConfidence, "high")
    env.W.role = "HEALER"; eq(env.M:GetCurrent().role, "healer")
    env.W.role = "DAMAGER"; eq(env.M:GetCurrent().role, "dps")
    env.W.spec, env.W.class, env.W.resting, env.W.pvp = 2, "DRUID", true, true
    c = env.M:GetCurrent()
    eq(c.spec, 2, "spec = gruppo talenti"); eq(c.class, "DRUID"); eq(c.resting, true); eq(c.pvpFlag, true)
end)

T["contesto: ruolo dall'albero dominante e confidenza"] = case(function(_, env)
    env.W.trees = { { "Arms", 3 }, { "Fury", 0 }, { "Protection", 31 } }
    local c = env.M:GetCurrent()
    eq(c.role, "tank"); eq(c.roleConfidence, "high")
    env.W.trees = { { "Arms", 3 }, { "Fury", 31 }, { "Protection", 0 } }
    eq(env.M:GetCurrent().role, "dps")
    -- albero con nome sconosciuto: si ricade sull'indice => confidenza media
    env.W.trees = { { "???", 0 }, { "???", 0 }, { "???", 31 } }
    c = env.M:GetCurrent()
    eq(c.role, "tank"); eq(c.roleConfidence, "medium", "confidenza non alta esposta nel contesto")
    -- override utente di Badb.Player
    BadbUI.Player:SetRoleOverride("healer")
    c = env.M:GetCurrent()
    eq(c.role, "healer"); eq(c.roleConfidence, "high")
    BadbUI.Player:SetRoleOverride(nil)
end)

T["contesto: Badb.Player assente o che fallisce => default"] = case(function(_, env)
    BadbUI.Player = nil
    local c = env.M:GetCurrent()
    eq(c.role, "none"); eq(c.spec, 0); eq(c.class, ""); eq(c.roleConfidence, "low")
    BadbUI.Player = { GetSnapshot = function() error("boom") end }
    c = env.M:GetCurrent()
    eq(c.role, "none"); eq(c.spec, 0)
    BadbUI.Player = { GetSnapshot = function()
        return { role = {}, roleConfidence = 5, talentGroup = "x", class = 7 }
    end }
    c = env.M:GetCurrent()
    eq(c.role, "none"); eq(c.spec, 0); eq(c.class, ""); eq(c.roleConfidence, "low")
    BadbUI.Player = { GetSnapshot = function() return "stringa" end }
    eq(env.M:GetCurrent().role, "none")
    env.M:AddRule({ profile = "Raid" })
    env.settle()
end)

T["contesto: API vecchie di gruppo"] = case(function(_, env)
    IsInGroup, IsInRaid = nil, nil
    GetNumGroupMembers = function() return 5 end
    eq(env.M:GetCurrent().group, "party")
    GetNumGroupMembers = nil
    GetNumRaidMembers = function() return 10 end
    eq(env.M:GetCurrent().group, "raid")
end)

T["API mancanti: valori di default, mai errore"] = case(function(Mock, env)
    for _, name in ipairs(API) do _G[name] = nil end
    BadbUI.Player:Invalidate()
    local c = env.M:GetCurrent()
    eq(c.instance, "none"); eq(c.group, "solo"); eq(c.spec, 1); eq(c.class, "")
    eq(c.role, "dps"); eq(c.roleConfidence, "low"); eq(c.resting, false); eq(c.pvpFlag, false)
    assert(env.M:Evaluate() == nil)
    -- API che lanciano errori
    for _, name in ipairs({ "IsInInstance", "IsInGroup", "IsInRaid", "UnitGroupRolesAssigned", "GetActiveTalentGroup",
        "UnitClass", "IsResting", "UnitIsPVP", "GetNumTalentTabs" }) do
        _G[name] = function() error("boom") end
    end
    BadbUI.Player:Invalidate()
    c = env.M:GetCurrent()
    eq(c.instance, "none"); eq(c.group, "solo"); eq(c.class, ""); eq(c.pvpFlag, false)
    -- API che ritornano tipi sbagliati o secret value
    IsInInstance = function() return Mock, 42 end
    IsInGroup = function() return "si" end
    UnitGroupRolesAssigned = function() return 7 end
    UnitIsPVP = function() return 1 end
    UnitClass = function() return 1, {} end
    IsResting = function() return 1 end
    BadbUI.Player:Invalidate()
    c = env.M:GetCurrent()
    eq(c.instance, "none"); eq(c.group, "solo"); eq(c.resting, false); eq(c.pvpFlag, false)
    local secret = env.Mock.Secret()
    IsInInstance = function() return secret, secret end
    UnitClass = function() return secret, secret end
    BadbUI.Player:Invalidate()
    eq(env.M:GetCurrent().instance, "none", "secret value ignorato")
    eq(env.M:GetCurrent().class, "")
    -- Il motore continua a funzionare
    env.M:AddRule({ profile = "Raid", when = {} })
    env.settle()
end)

---------------------------------------------------------------------------
-- Regole: priorita', AND, regole rotte
---------------------------------------------------------------------------
T["priorita' e ordine a parita'"] = case(function(_, env)
    local M = env.M
    local a = M:AddRule({ name = "A", profile = "Raid", when = { group = "raid" } })
    local b = M:AddRule({ name = "B", profile = "PvP", when = { instance = "raid" } })
    local ctx = { instance = "raid", group = "raid", role = "dps", spec = 1, class = "MAGE", resting = false, pvpFlag = false }
    local p, id = M:Evaluate(ctx)
    eq(p, "Raid", "parita': vince la prima"); eq(id, a)
    assert(M:MoveRule(b, -1))
    eq(M:Evaluate(ctx), "PvP", "dopo MoveRule vince l'altra")
    assert(M:UpdateRule(a, { priority = 5 }))
    eq(M:Evaluate(ctx), "Raid", "priorita' piu' alta vince")
    assert(M:SetEnabled(a, false))
    eq(M:Evaluate(ctx), "PvP", "regola disabilitata ignorata")
    assert(M:SetEnabled(b, false))
    eq(M:Evaluate(ctx), nil, "nessuna regola attiva")
    local list = M:ListRules()
    eq(list[1].id, b); eq(list[2].id, a)
    eq(list[2].priority, 5)
end)

T["condizioni in AND"] = case(function(_, env)
    local M = env.M
    M:AddRule({ profile = "Raid", when = { instance = "raid", role = "tank", spec = 2, class = "WARRIOR", resting = false,
        pvpFlag = true } })
    local ctx = { instance = "raid", group = "raid", role = "tank", spec = 2, class = "WARRIOR", resting = false, pvpFlag = true }
    eq(M:Evaluate(ctx), "Raid", "tutte vere")
    for key, bad in pairs({ instance = "party", role = "dps", spec = 1, class = "MAGE", resting = true, pvpFlag = false }) do
        local c = {}
        for k, v in pairs(ctx) do c[k] = v end
        c[key] = bad
        eq(M:Evaluate(c), nil, "una condizione falsa: " .. key)
    end
    -- resting = nil nel contesto si comporta come false
    ctx.resting = nil
    eq(M:Evaluate(ctx), "Raid")
    ctx.pvpFlag = nil
    eq(M:Evaluate(ctx), nil, "pvpFlag nil si comporta come false")
    ctx.pvpFlag = true
    -- when vuoto: sempre vera
    M:AddRule({ profile = "Solo", priority = -5, when = {} })
    eq(M:Evaluate({ instance = "pvp", group = "solo", role = "none", spec = 0, class = "", resting = true }), "Solo")
end)

T["valutazione sul contesto reale (API simulate)"] = case(function(_, env)
    local M = env.M
    M:AddRule({ profile = "Raid", when = { instance = "raid", role = "healer" } })
    M:AddRule({ profile = "PvP", when = { instance = "pvp" } })
    eq(M:Evaluate(), nil)
    env.W.instance, env.W.inInstance, env.W.role, env.W.raid = "raid", true, "HEALER", true
    eq(M:Evaluate(), "Raid")
    env.W.instance, env.W.role = "pvp", "NONE"
    eq(M:Evaluate(), "PvP")
end)

T["regola con profilo inesistente: rotta e mai applicata"] = case(function(_, env)
    local M = env.M
    local broken = M:AddRule({ name = "Rotta", profile = "Fantasma", priority = 100, when = {} })
    local ok = M:AddRule({ name = "Buona", profile = "Raid", priority = 1, when = {} })
    local list = M:ListRules()
    eq(list[1].broken, true); eq(list[1].brokenReason, "profilo inesistente"); eq(list[2].broken, false)
    eq(M:Evaluate(), "Raid", "la rotta non vince nonostante la priorita'")
    env.settle()
    eq(env.DB:GetProfileName(), "Raid")
    assert(env.DB.sv.profiles.Fantasma == nil, "il profilo fantasma non viene creato")
    -- La regola guarisce quando il profilo compare
    env.DB.sv.profiles.Fantasma = {}
    eq(M:GetRule(broken).broken, false)
    eq(M:Evaluate(), "Fantasma")
    env.DB.sv.profiles.Fantasma = nil
    assert(ok)
end)

T["API regole: input errato non lancia errori"] = case(function(_, env)
    local M = env.M
    local function bad(r, label)
        local id, err = M:AddRule(r)
        eq(id, nil, label); assert(type(err) == "string", label .. ": messaggio")
    end
    bad(nil, "nil"); bad("x", "stringa"); bad(5, "numero"); bad({}, "senza profilo")
    bad({ profile = 3 }, "profilo numerico"); bad({ profile = "" }, "profilo vuoto")
    bad({ profile = "Raid", when = "x" }, "when stringa")
    bad({ profile = "Raid", when = { instance = "luna" } }, "istanza sconosciuta")
    bad({ profile = "Raid", when = { role = 3 } }, "ruolo numerico")
    bad({ profile = "Raid", when = { spec = 0 } }, "spec zero")
    bad({ profile = "Raid", when = { spec = 1.5 } }, "spec frazionaria")
    bad({ profile = "Raid", when = { spec = 0 / 0 } }, "spec NaN")
    bad({ profile = "Raid", when = { class = "due parole" } }, "classe malformata")
    bad({ profile = "Raid", when = { resting = "si" } }, "resting stringa")
    bad({ profile = "Raid", when = { colore = "rosso" } }, "chiave sconosciuta")
    bad({ profile = "Raid", priority = "alta" }, "priorita' stringa")
    bad({ profile = "Raid", priority = 0 / 0 }, "priorita' NaN")
    bad({ profile = "Raid", enabled = "yes" }, "enabled stringa")
    bad({ profile = "Raid", name = {} }, "nome tabella")
    bad({ profile = "Raid", id = {} }, "id tabella")
    local cyc = {}; cyc.self = cyc
    bad({ profile = "Raid", when = cyc }, "when ciclico")
    eq(#M:ListRules(), 0, "nessuna regola creata")

    local id = M:AddRule({ profile = "Raid", id = "mia", when = { instance = "RAID", class = "mage" } })
    eq(id, "mia")
    eq(M:GetRule("mia").when.instance, "raid", "normalizzato in minuscolo")
    eq(M:GetRule("mia").when.class, "MAGE")
    bad({ profile = "Raid", id = "mia" }, "id duplicato")
    -- le altre operazioni ritornano false, err
    local ok, err = M:RemoveRule("nope"); eq(ok, false); assert(err)
    ok = M:RemoveRule(nil); eq(ok, false)
    ok = M:MoveRule("nope", 1); eq(ok, false)
    ok = M:MoveRule("mia", "su"); eq(ok, false)
    ok = M:UpdateRule("mia", "x"); eq(ok, false)
    ok = M:UpdateRule("mia", { priority = {} }); eq(ok, false)
    ok = M:UpdateRule("mia", { when = { spec = 99 } }); eq(ok, false)
    ok = M:SetEnabled("mia", "si"); eq(ok, false)
    eq(M:GetRule("mia").when.instance, "raid", "regola intatta dopo gli errori")
    -- spostamento oltre i limiti: clamp
    M:AddRule({ profile = "Solo", id = "due" })
    assert(M:MoveRule("due", -50)); eq(M:ListRules()[1].id, "due")
    assert(M:MoveRule("due", 50)); eq(M:ListRules()[2].id, "due")
    assert(M:RemoveRule("due")); eq(#M:ListRules(), 1)
    -- limite del numero di regole
    for _ = 1, M.MAX_RULES do M:AddRule({ profile = "Raid" }) end
    eq(#M:ListRules(), M.MAX_RULES)
    local lim, e = M:AddRule({ profile = "Raid" }); eq(lim, nil); assert(e)
end)

---------------------------------------------------------------------------
-- Motore: debounce, isteresi, combattimento, loop, override manuale
---------------------------------------------------------------------------
T["motore: applica la regola e spara gli eventi"] = case(function(Mock, env)
    local M, Events = env.M, env.Events
    local log = {}
    local owner = { name = "spy" }
    Events:On(owner, "BADB_CONTEXT_CHANGED", function(_, ctx) log[#log + 1] = { "ctx", ctx } end)
    Events:On(owner, "BADB_RULE_MATCHED", function(_, id, profile) log[#log + 1] = { "rule", id, profile } end)
    local id = M:AddRule({ profile = "Raid", when = { instance = "raid" } })
    env.W.instance, env.W.inInstance, env.W.raid = "raid", true, true
    Mock.Fire("PLAYER_ENTERING_WORLD")
    env.settle()
    eq(env.DB:GetProfileName(), "Raid")
    local ctxEvents, ruleEvents = 0, 0
    for _, e in ipairs(log) do
        if e[1] == "ctx" then ctxEvents = ctxEvents + 1; eq(e[2].instance, "raid", "ctx passato all'evento") end
        if e[1] == "rule" then ruleEvents = ruleEvents + 1; eq(e[2], id); eq(e[3], "Raid") end
    end
    eq(ruleEvents, 1, "RULE_MATCHED una volta")
    assert(ctxEvents >= 1, "CONTEXT_CHANGED sparato")
    -- stesso contesto: nessun nuovo evento
    local before = #log
    Mock.Fire("ZONE_CHANGED_NEW_AREA")
    env.settle()
    eq(#log, before, "nessun evento se il contesto non cambia")
    -- la copia passata agli ascoltatori non altera lo stato del modulo
    log[1][2].instance = "manomesso"
    eq(M:GetCurrent().instance, "raid")
    Events:OffAll(owner)
end)

T["motore: ogni evento di gioco richiede una valutazione"] = case(function(Mock, env)
    env.M:AddRule({ profile = "Raid", when = {} })
    env.settle()
    for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE",
        "PLAYER_UPDATE_RESTING", "PLAYER_FLAGS_CHANGED", "UNIT_FACTION", "BADB_PLAYER_CHANGED",
        "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED" }) do
        local before = env.M.stats.evals
        Mock.Fire(ev, "player")
        env.settle()
        eq(env.M.stats.evals, before + 1, "valutazione su " .. ev)
    end
    -- spec di un altro unita': ignorata
    local before = env.M.stats.evals
    Mock.Fire("PLAYER_SPECIALIZATION_CHANGED", "target")
    Mock.Fire("UNIT_FACTION", "target")
    env.settle()
    eq(env.M.stats.evals, before, "unita' diversa da player ignorata")
end)

T["motore: debounce e coalescenza delle raffiche"] = case(function(Mock, env)
    env.M:AddRule({ profile = "Raid", when = { group = "raid" } })
    env.settle()
    env.M.stats.evals = 0
    env.W.raid = true
    for _ = 1, 10 do
        Mock.Fire("GROUP_ROSTER_UPDATE")
        Mock.Fire("PLAYER_ROLES_ASSIGNED")
        env.advance(0.01)
    end
    eq(env.M.stats.evals, 0, "nessuna valutazione dentro la finestra")
    eq(env.DB:GetProfileName(), "Default")
    env.settle()
    eq(env.M.stats.evals, 1, "una sola valutazione per tutta la raffica")
    eq(env.DB:GetProfileName(), "Raid")
    eq(#env.timers, 0, "nessun timer residuo")
    -- una seconda raffica produce una seconda valutazione
    Mock.Fire("GROUP_ROSTER_UPDATE"); Mock.Fire("GROUP_ROSTER_UPDATE")
    env.settle()
    eq(env.M.stats.evals, 2)
end)

T["motore: isteresi anti-flapping"] = case(function(Mock, env)
    local M = env.M
    env.setOpt("switchCooldown", 3)
    M:AddRule({ profile = "Solo", when = { group = "solo" } })
    M:AddRule({ profile = "Raid", when = { group = "raid" } })
    env.settle()
    eq(env.DB:GetProfileName(), "Solo"); eq(M.stats.switches, 1)
    env.W.raid = true
    Mock.Fire("GROUP_ROSTER_UPDATE")
    env.settle()
    eq(env.DB:GetProfileName(), "Solo", "cambio bloccato dall'isteresi")
    eq(M.stats.switches, 1)
    assert(#env.timers > 0, "ritentera' a isteresi scaduta")
    env.advance(3)
    eq(env.DB:GetProfileName(), "Raid", "applicato dopo la pausa")
    eq(M.stats.switches, 2)

    -- Flapping: il contesto torna com'era prima della scadenza => nessun cambio inutile
    env.W.raid = false
    Mock.Fire("GROUP_ROSTER_UPDATE")
    env.settle()
    eq(env.DB:GetProfileName(), "Raid")
    env.W.raid = true
    Mock.Fire("GROUP_ROSTER_UPDATE")
    env.advance(5)
    eq(env.DB:GetProfileName(), "Raid", "stato finale coerente col contesto finale")
    eq(M.stats.switches, 2, "nessun cambio spurio")
    eq(#env.timers, 0)
end)

T["motore: combattimento differisce, poi esegue a PLAYER_REGEN_ENABLED"] = case(function(Mock, env)
    local M = env.M
    Mock.combat = true
    M:AddRule({ profile = "Raid", when = { group = "raid" } })
    env.W.raid = true
    Mock.Fire("GROUP_ROSTER_UPDATE")
    env.settle()
    env.advance(10)
    eq(env.DB:GetProfileName(), "Default", "nessun cambio in combattimento")
    eq(M.stats.evals, 0, "nessuna valutazione in combattimento")
    -- altre raffiche durante il combattimento non producono errori ne' esecuzioni
    Mock.Fire("GROUP_ROSTER_UPDATE"); env.settle()
    eq(M.stats.evals, 0)
    Mock.combat = false
    Mock.Fire("PLAYER_REGEN_ENABLED")
    eq(env.DB:GetProfileName(), "Raid", "eseguito a fine combattimento")
    eq(M.stats.evals, 1, "una sola valutazione differita")
end)

T["motore: nessun loop dopo un cambio del motore"] = case(function(Mock, env)
    local M = env.M
    -- Due regole che si "rincorrerebbero" se il cambio profilo rilanciasse la valutazione.
    M:AddRule({ profile = "Raid", when = { group = "raid" } })
    M:AddRule({ profile = "Solo", when = { group = "solo" } })
    env.W.raid = true
    Mock.Fire("GROUP_ROSTER_UPDATE")
    env.settle()
    eq(env.DB:GetProfileName(), "Raid")
    local evals, switches = M.stats.evals, M.stats.switches
    env.advance(30)
    eq(M.stats.evals, evals, "nessuna valutazione extra dopo il cambio")
    eq(M.stats.switches, switches)
    eq(#env.timers, 0, "nessun timer residuo")
    eq(M._manual, false, "il cambio del motore non e' un override manuale")
    eq(M._foreign, nil)

    -- Ascoltatore che reagisce a CONTEXT_CHANGED cambiando profilo: niente ricorsione
    local owner = { name = "reattivo" }
    local calls = 0
    env.Events:On(owner, "BADB_CONTEXT_CHANGED", function() calls = calls + 1; env.DB:SetProfile("Solo") end)
    env.W.raid = false
    Mock.Fire("GROUP_ROSTER_UPDATE")
    env.advance(60)
    assert(calls <= 2, "ascoltatore chiamato un numero limitato di volte: " .. calls)
    assert(M.stats.evals < evals + 6, "valutazioni limitate: " .. M.stats.evals)
    env.advance(5); env.advance(5) -- orologio finto a salti: lascia scadere i timer creati durante il salto
    eq(#env.timers, 0)
    env.Events:OffAll(owner)
end)

T["override manuale sospende fino al prossimo cambio di contesto"] = case(function(Mock, env)
    local M = env.M
    M:AddRule({ profile = "Raid", when = { group = "raid" } })
    M:AddRule({ profile = "Solo", when = { group = "solo" } })
    env.settle()
    eq(env.DB:GetProfileName(), "Solo")
    env.W.raid = true
    Mock.Fire("GROUP_ROSTER_UPDATE"); env.settle()
    eq(env.DB:GetProfileName(), "Raid")
    -- l'utente sceglie un altro profilo a mano
    env.DB:SetProfile("PvP")
    env.settle()
    eq(env.DB:GetProfileName(), "PvP", "il motore non lo annulla")
    eq(M._manual, true)
    -- eventi che non cambiano il contesto non riportano indietro
    Mock.Fire("ZONE_CHANGED_NEW_AREA"); Mock.Fire("PLAYER_ENTERING_WORLD"); env.settle()
    env.advance(20)
    eq(env.DB:GetProfileName(), "PvP", "contesto invariato: resta la scelta manuale")
    -- un cambio di contesto reale riattiva il motore
    env.W.raid = false
    Mock.Fire("GROUP_ROSTER_UPDATE"); env.settle()
    eq(env.DB:GetProfileName(), "Solo", "nuovo contesto: il motore riprende")
    eq(M._manual, false)
end)

T["override manuale: modificare le regole riattiva il motore"] = case(function(Mock, env)
    local M = env.M
    M:AddRule({ profile = "Raid", when = {} })
    env.settle()
    env.DB:SetProfile("PvP"); env.settle()
    eq(env.DB:GetProfileName(), "PvP")
    M:AddRule({ profile = "Solo", priority = 5, when = {} })
    env.settle()
    eq(env.DB:GetProfileName(), "Solo")
end)

T["override manuale: con respectManual spento il motore riafferma"] = case(function(Mock, env)
    local M = env.M
    env.setOpt("respectManual", false)
    M:AddRule({ profile = "Raid", when = {} })
    env.settle()
    eq(env.DB:GetProfileName(), "Raid")
    env.DB:SetProfile("PvP"); env.settle()
    eq(env.DB:GetProfileName(), "Raid", "riaffermato")
    -- ... ma l'isteresi continua a valere e non c'e' loop
    env.setOpt("switchCooldown", 5)
    env.DB:SetProfile("PvP"); env.settle()
    eq(env.DB:GetProfileName(), "PvP", "isteresi: ancora non riaffermato")
    env.advance(6)
    eq(env.DB:GetProfileName(), "Raid")
    env.advance(60)
    eq(#env.timers, 0)
end)

T["auto-switch spento: valuta ma non cambia; riacceso applica"] = case(function(Mock, env)
    local M = env.M
    M:AddRule({ profile = "Raid", when = {} })
    env.settle()
    env.DB:SetProfile("Default")
    M:AddRule({ profile = "Raid", when = {} }) -- forza il ricalcolo
    env.settle()
    env.DB:SetProfile("Default")
    env.setOpt("autoSwitch", false)
    env.settle()
    Mock.Fire("PLAYER_ENTERING_WORLD"); env.settle()
    eq(env.DB:GetProfileName(), "Default", "auto-switch spento")
    eq(M:Evaluate(), "Raid", "Evaluate resta disponibile")
    env.setOpt("autoSwitch", true)
    M:Set("autoSwitch", true) -- evento di opzione => rivalutazione
    env.settle()
    eq(env.DB:GetProfileName(), "Raid")
end)

T["Apply: applica subito ignorando isteresi e override"] = case(function(Mock, env)
    local M = env.M
    env.setOpt("switchCooldown", 30)
    M:AddRule({ profile = "Raid", when = {} })
    env.settle()
    eq(env.DB:GetProfileName(), "Raid")
    env.DB:SetProfile("PvP"); env.settle()
    eq(env.DB:GetProfileName(), "PvP")
    assert(M:Apply())
    eq(env.DB:GetProfileName(), "Raid")
    Mock.combat = true
    env.DB.profileName = "PvP" -- stato come se fosse cambiato
    env.DB.profile = env.DB.sv.profiles.PvP
    assert(M:Apply())
    eq(env.DB:GetProfileName(), "PvP", "in combattimento differito")
    Mock.combat = false
    Mock.Fire("PLAYER_REGEN_ENABLED")
    eq(env.DB:GetProfileName(), "Raid")
end)

T["fallbackProfile: nessuna regola => profilo base; default lascia l'attuale"] = case(function(Mock, env)
    local M = env.M
    local id = M:AddRule({ profile = "Raid", when = { group = "raid" } })
    env.W.raid = true
    Mock.Fire("GROUP_ROSTER_UPDATE"); env.settle()
    eq(env.DB:GetProfileName(), "Raid")
    env.W.raid = false
    Mock.Fire("GROUP_ROSTER_UPDATE"); env.settle()
    eq(env.DB:GetProfileName(), "Raid", "default: lascia l'attuale")
    env.setOpt("fallbackProfile", "Solo")
    env.W.raid = true
    Mock.Fire("GROUP_ROSTER_UPDATE"); env.settle()
    env.W.raid = false
    Mock.Fire("GROUP_ROSTER_UPDATE"); env.settle()
    eq(env.DB:GetProfileName(), "Solo", "ritorno al profilo base")
    -- fallback inesistente: ignorato
    env.setOpt("fallbackProfile", "Fantasma")
    env.W.raid = true
    Mock.Fire("GROUP_ROSTER_UPDATE"); env.settle()
    env.W.raid = false
    Mock.Fire("GROUP_ROSTER_UPDATE"); env.settle()
    eq(env.DB:GetProfileName(), "Raid")
    assert(env.DB.sv.profiles.Fantasma == nil)
    assert(id)
end)

T["interazione col profilo-per-spec del core"] = case(function(Mock, env)
    local M, DB = env.M, env.DB
    DB:SetSpecProfile(2, "Solo")
    -- 1) regola con spec abilitata: ha la precedenza, senza combattersi col core
    M:AddRule({ name = "Spec2", profile = "PvP", when = { spec = 2 } })
    env.settle()
    env.W.spec = 2
    Mock.Fire("ACTIVE_TALENT_GROUP_CHANGED")
    env.settle()
    eq(DB:GetProfileName(), "PvP", "vince la regola con spec")
    eq(M._manual, false, "lo switch del core non e' scambiato per override manuale")
    local sw = M.stats.switches
    env.advance(30)
    Mock.Fire("PLAYER_ENTERING_WORLD"); env.settle()
    eq(DB:GetProfileName(), "PvP"); eq(M.stats.switches, sw, "nessun rimbalzo")
    eq(#env.timers, 0)

    -- 2) regola con spec disabilitata: decide il core
    M:SetEnabled(M:ListRules()[1].id, false)
    env.settle()
    env.W.spec = 1
    Mock.Fire("ACTIVE_TALENT_GROUP_CHANGED"); env.settle()
    env.W.spec = 2
    Mock.Fire("ACTIVE_TALENT_GROUP_CHANGED"); env.settle()
    eq(DB:GetProfileName(), "Solo", "senza regole applicabili vale il profilo-per-spec")
    -- 3) niente regola: il fallback non combatte col profilo-per-spec
    env.setOpt("fallbackProfile", "Raid")
    env.W.spec = 1
    Mock.Fire("ACTIVE_TALENT_GROUP_CHANGED"); env.settle()
    env.W.spec = 2
    Mock.Fire("ACTIVE_TALENT_GROUP_CHANGED"); env.settle()
    eq(DB:GetProfileName(), "Solo", "fallback non applicato sopra il profilo-per-spec")
end)

T["interazione col core: spec in combattimento, ordine di esecuzione indifferente"] = case(function(Mock, env)
    local M, DB = env.M, env.DB
    DB:SetSpecProfile(2, "Solo")
    M:AddRule({ profile = "PvP", when = { spec = 2 } })
    env.settle()
    Mock.combat = true
    env.W.spec = 2
    Mock.Fire("ACTIVE_TALENT_GROUP_CHANGED")
    env.settle()
    eq(DB:GetProfileName(), "Default", "tutto differito in combattimento")
    Mock.combat = false
    Mock.Fire("PLAYER_REGEN_ENABLED")
    env.advance(10)
    eq(DB:GetProfileName(), "PvP", "stato finale: regola con spec")
    eq(#env.timers, 0)
end)

---------------------------------------------------------------------------
-- Persistenza e dati corrotti
---------------------------------------------------------------------------
T["persistenza: regole in sv.global.contextRules con version"] = case(function(_, env)
    local M, DB = env.M, env.DB
    local id = M:AddRule({ name = "Raid tank", profile = "Raid", priority = 7, when = { instance = "raid", role = "tank" } })
    local store = DB.sv.global.contextRules
    eq(type(store.version), "number"); eq(store.version, 1)
    eq(#store.rules, 1)
    eq(store.rules[1].id, id); eq(store.rules[1].profile, "Raid"); eq(store.rules[1].priority, 7)
    eq(store.rules[1].when.role, "tank")
    eq(store.rules[1].enabled, true)
    -- Non e' nel profilo
    assert(DB.profile.modules.Contexts.rules == nil, "le regole non stanno nel profilo")
    -- Sopravvive a cambio profilo e a disattivazione/riattivazione del modulo
    DB:SetProfile("PvP")
    eq(#M:ListRules(), 1)
    BadbUI.Modules:SetEnabled("Contexts", false)
    BadbUI.Modules:SetEnabled("Contexts", true)
    eq(#M:ListRules(), 1)
    -- "Ricarica" simulata: copia profonda della tabella salvata
    local function deep(t) local o = {} for k, v in pairs(t) do o[k] = type(v) == "table" and deep(v) or v end return o end
    DB.sv.global.contextRules = deep(DB.sv.global.contextRules)
    local list = M:ListRules()
    eq(#list, 1); eq(list[1].name, "Raid tank"); eq(list[1].when.instance, "raid")
    -- id nuovi non collidono dopo il ricaricamento
    local id2 = M:AddRule({ profile = "Raid" })
    assert(id2 ~= id)
end)

T["dati corrotti in contextRules: ripuliti senza errori"] = case(function(Mock, env)
    local M, DB = env.M, env.DB
    local function exercise(label)
        local ok, err = pcall(function()
            M:ListRules(); M:Evaluate(); M:GetCurrent(); M:GetRule("r1")
            M.commands.context.fn("list"); M.commands.context.fn("status"); M.commands.context.fn("eval")
            M:AddRule({ profile = "Raid" }); M:MoveRule("r1", 1); M:RemoveRule("zzz")
            Mock.Fire("PLAYER_ENTERING_WORLD"); env.settle()
        end)
        if not ok then error(label .. ": " .. tostring(err)) end
        local store = DB.sv.global.contextRules
        eq(type(store), "table", label .. ": store e' una tabella")
        eq(type(store.version), "number", label .. ": version")
        eq(type(store.rules), "table", label .. ": rules")
        for i, r in ipairs(store.rules) do
            eq(type(r.id), "string", label .. ": id " .. i)
            eq(type(r.profile), "string"); eq(type(r.priority), "number"); eq(type(r.enabled), "boolean")
            eq(type(r.when), "table"); eq(type(r.name), "string")
        end
    end

    for i, junk in ipairs({ "stringa", 42, true, 0 / 0, function() end }) do
        DB.sv.global.contextRules = junk
        exercise("contextRules = " .. type(junk) .. i)
        eq(#M:ListRules() >= 0, true)
    end
    DB.sv.global = "rotto"
    exercise("global stringa")
    eq(type(DB.sv.global), "table")
    DB.sv.global.contextRules = nil

    local cyc = {}; cyc.self = cyc
    local hugeName = string.rep("x", 100000)
    local many = {}
    for i = 1, 500 do many[i] = { id = "m" .. i, profile = "Raid", when = {} } end
    local cases = {
        { rules = "stringa" },
        { rules = 5 },
        { rules = { 1, 2, "a", true, false } },
        { rules = { {}, {}, {} } },
        { version = "uno", seq = "x", rules = {} },
        { version = -3, seq = -1 },
        { version = math.huge, seq = math.huge, rules = {} },
        { rules = { { id = {}, name = 5, profile = {}, priority = "alta", enabled = "yes", when = "x" } } },
        { rules = { { id = "a", profile = "Raid" }, { id = "a", profile = "PvP" }, { id = "a", profile = "Solo" } } },
        { rules = { { id = "a", profile = "Raid", when = { instance = 5, role = {}, resting = "si", spec = -3,
            class = "war rior", foo = 1, [1] = "x" } } } },
        { rules = { { id = "a", profile = "Raid", when = cyc, name = hugeName } } },
        { rules = { { id = hugeName, profile = hugeName, priority = 0 / 0 } } },
        { rules = { { id = "a", profile = "Raid", priority = math.huge, enabled = 1 } } },
        { rules = many },
        { rules = { [1] = { profile = "Raid" }, [3] = { profile = "PvP" }, x = { profile = "Solo" }, [1.5] = {} } },
        { rules = setmetatable({}, { __index = function() error("trappola") end }) },
    }
    for i, c in ipairs(cases) do
        DB.sv.global.contextRules = c
        exercise("caso " .. i)
    end

    -- Dettagli di ripulitura
    DB.sv.global.contextRules = { rules = { { id = "a", profile = "Raid", when = "x" } } }
    local r = M:ListRules()[1]
    eq(r.broken, true, "when corrotto => rotta (non una regola 'sempre vera')")
    eq(M:Evaluate(), nil)

    DB.sv.global.contextRules = { rules = { { id = "a", profile = "Raid", when = { class = "no no" } },
        { id = "b", profile = "PvP", when = {}, priority = -1, enabled = "yes" } } }
    eq(M:ListRules()[1].broken, true)
    eq(M:ListRules()[2].enabled, false, "enabled non booleano => disattivata")
    eq(M:Evaluate(), nil)

    DB.sv.global.contextRules = { rules = { { id = "a", profile = "Raid" }, { id = "a", profile = "PvP" } } }
    local l = M:ListRules()
    assert(l[1].id ~= l[2].id, "id duplicati risolti")

    DB.sv.global.contextRules = { rules = many }
    eq(#M:ListRules(), M.MAX_RULES, "numero di regole limitato")

    DB.sv.global.contextRules = { rules = { { id = "a", profile = hugeName, priority = math.huge } } }
    r = M:ListRules()[1]
    eq(r.profile, "", "profilo enorme scartato"); eq(r.priority, 1000, "priorita' limitata")
    eq(r.broken, true)
end)

---------------------------------------------------------------------------
-- Disattivazione
---------------------------------------------------------------------------
T["disattivazione: ferma timer, listener e code"] = case(function(Mock, env)
    local M = env.M
    M:AddRule({ profile = "Raid", when = { group = "raid" } })
    env.settle()
    env.DB:SetProfile("Default"); env.settle()
    env.W.raid = true
    Mock.Fire("GROUP_ROSTER_UPDATE") -- timer in volo
    assert(#env.timers > 0)
    BadbUI.Modules:SetEnabled("Contexts", false)
    env.advance(10)
    eq(env.DB:GetProfileName(), "Default", "il timer in volo non fa nulla")
    for ev, list in pairs(env.Events.listeners) do
        assert(list[M] == nil, "listener residuo su " .. ev)
    end
    local evals = M.stats.evals
    Mock.Fire("GROUP_ROSTER_UPDATE"); Mock.Fire("PLAYER_ENTERING_WORLD"); env.advance(10)
    eq(M.stats.evals, evals, "nessuna valutazione da spento")
    eq(#env.timers, 0, "nessun timer pianificato da spento")
    -- API ancora usabili (sola gestione dati) senza effetti collaterali
    local id = M:AddRule({ profile = "Raid" })
    assert(id)
    eq(#env.timers, 0)
    eq(M:Evaluate(), "Raid")
    eq(M:Apply(), false)

    -- azione differita da combattimento prima della disattivazione
    BadbUI.Modules:SetEnabled("Contexts", true)
    env.settle()
    env.DB:SetProfile("Default"); env.settle()
    Mock.combat = true
    M:Touch(); env.settle()
    BadbUI.Modules:SetEnabled("Contexts", false)
    Mock.combat = false
    Mock.Fire("PLAYER_REGEN_ENABLED")
    eq(env.DB:GetProfileName(), "Default", "azione differita annullata dalla disattivazione")

    -- riattivazione: riparte pulito
    BadbUI.Modules:SetEnabled("Contexts", true)
    env.settle()
    eq(env.DB:GetProfileName(), "Raid")
end)

T["cambio a un profilo con il modulo spento non lascia stato sporco"] = case(function(Mock, env)
    local M = env.M
    env.DB.sv.profiles.Solo.modules.Contexts.enabled = false
    M:AddRule({ profile = "Solo", when = {} })
    env.settle()
    eq(env.DB:GetProfileName(), "Solo")
    eq(M.enabled, false, "modulo spento dal profilo di destinazione")
    eq(M._applying, false, "flag di origine ripulito")
    env.advance(30)
    eq(#env.timers, 0)
end)

---------------------------------------------------------------------------
-- Comandi e pagina
---------------------------------------------------------------------------
T["comandi: status, list, eval"] = case(function(Mock, env)
    local M = env.M
    local cmd = M.commands.context
    assert(type(cmd.help) == "string" and type(cmd.fn) == "function")
    local function out()
        local s = table.concat(Mock.chat, "\n")
        for i = #Mock.chat, 1, -1 do Mock.chat[i] = nil end
        return s
    end
    M:AddRule({ name = "Raid tank", profile = "Raid", when = { instance = "raid", role = "tank" } })
    M:AddRule({ name = "Rotta", profile = "Fantasma", when = {} })
    env.settle()
    out()
    cmd.fn("")
    local s = out()
    assert(s:find("Contesto:", 1, true), s); assert(s:find("Regola vincente: nessuna", 1, true), s)
    cmd.fn("list")
    s = out()
    assert(s:find("Raid tank", 1, true), s); assert(s:find("ROTTA", 1, true), s)
    env.W.instance, env.W.inInstance, env.W.group, env.W.role = "raid", true, true, "TANK"
    cmd.fn("eval")
    s = out()
    assert(s:find("Raid tank -> Raid", 1, true), s)
    eq(env.DB:GetProfileName(), "Default", "eval a secco non cambia profilo")
    cmd.fn("eval apply")
    eq(env.DB:GetProfileName(), "Raid", "eval apply applica")
    cmd.fn("sconosciuto"); cmd.fn(nil); cmd.fn(42)
    assert(out():find("context", 1, true))
end)

T["pagina: costruzione, creazione/ordine/eliminazione regole"] = case(function(Mock, env)
    local M = env.M
    local page = M.page
    eq(page.title, "Contesti"); eq(page.category, "Gestione"); eq(type(page.order), "number")
    local parent = CreateFrame("Frame")
    local height = page.build(parent, { UI = nil, W = BadbUI.Widgets })
    assert(type(height) == "number" and height > 100, "altezza ritornata")
    local ps = M._page
    local function click(b) b.__scripts.OnClick(b) end

    -- il form: istanza -> "none"(1) ... 3 click => "raid"; profilo: primo click => successivo a quello attivo
    for _ = 1, 3 do click(ps.cycles[1]) end
    eq(ps.form.instance, "raid")
    click(ps.cycles[7]) -- profilo (dopo 6 cicli: istanza, gruppo, ruolo, spec, classe, riposo)
    eq(ps.form.profile, "PvP")
    click(ps.createBtn)
    local rules = M:ListRules()
    eq(#rules, 1); eq(rules[1].when.instance, "raid"); eq(rules[1].profile, "PvP")
    assert(ps.rows[1].frame.__shown, "riga mostrata")
    assert(ps.rows[1].label:GetText():find("PvP", 1, true), "etichetta riga")
    assert(not ps.rows[2].frame.__shown, "righe in eccesso nascoste")

    -- seconda regola poi su/giu/elimina
    click(ps.createBtn)
    eq(#M:ListRules(), 2)
    local second = M:ListRules()[2].id
    click(ps.rows[2].up)
    eq(M:ListRules()[1].id, second)
    click(ps.rows[1].down)
    eq(M:ListRules()[2].id, second)
    click(ps.rows[1].check) -- GetChecked del mock ritorna nil => disabilita
    eq(M:ListRules()[1].enabled, false)
    click(ps.rows[1].del)
    eq(#M:ListRules(), 1)

    -- regola rotta: messaggio nella riga
    M:AddRule({ profile = "Fantasma" })
    page.refresh()
    assert(ps.rows[2].label:GetText():find("ROTTA", 1, true), "riga rotta segnalata")
    -- errore dal form: messaggio, nessun lancio
    env.DB.sv.profiles = env.DB.sv.profiles
    ps.form.profile = ""
    click(ps.createBtn)
    page.refresh()
    assert(ps.ctxLine:GetText():find("Contesto:", 1, true))
    assert(ps.winLine:GetText():find("Regola vincente:", 1, true))
end)

T["pagina: refresh prima della build non fa nulla"] = case(function(_, env)
    env.M._page = nil
    env.M.page.refresh()
    env.M:RefreshPage()
end)

---------------------------------------------------------------------------
-- Badb.Player, flag PvP, regole base per classe
---------------------------------------------------------------------------
T["BADB_PLAYER_CHANGED: il cambio di ruolo/talenti rivaluta le regole"] = case(function(_, env)
    local M = env.M
    M:AddRule({ profile = "Raid", when = { role = "healer" } })
    M:AddRule({ profile = "Solo", when = { role = "dps", spec = 2 } })
    env.settle()
    eq(env.DB:GetProfileName(), "Default")
    local sw = M.stats.switches
    BadbUI.Player:SetRoleOverride("healer") -- Invalidate => BADB_PLAYER_CHANGED
    env.settle()
    eq(env.DB:GetProfileName(), "Raid", "ruolo dal servizio Player")
    BadbUI.Player:SetRoleOverride("dps") -- override: confidenza alta (un dps solo ipotizzato non farebbe scattare la regola)
    env.W.spec = 2 -- secondo gruppo talenti (dual spec)
    env.settle()
    eq(env.DB:GetProfileName(), "Solo", "spec = gruppo talenti")
    eq(M.stats.switches, sw + 2)
    eq(M:GetCurrent().spec, 2)
end)

T["ruolo ipotizzato (confidenza bassa) non fa scattare regole per ruolo; l'override si"] = case(function(_, env)
    local M = env.M
    M:AddRule({ profile = "Raid", when = { role = "dps" } })
    env.settle()
    local c = M:GetCurrent()
    eq(c.role, "dps"); eq(c.roleConfidence, "low", "nessun dato sui talenti")
    eq(env.DB:GetProfileName(), "Default", "ruolo solo ipotizzato: nessun cambio")
    eq(M:Evaluate(), nil)
    BadbUI.Player:SetRoleOverride("dps")
    env.settle()
    eq(env.DB:GetProfileName(), "Raid", "ruolo scelto dall'utente: la regola scatta")
end)

T["flag PvP: world PvP cambia profilo"] = case(function(Mock, env)
    local M = env.M
    M:AddRule({ profile = "PvP", when = { pvpFlag = true } })
    M:AddRule({ profile = "Solo", when = { pvpFlag = false } })
    env.settle()
    eq(env.DB:GetProfileName(), "Solo")
    env.W.pvp = true
    Mock.Fire("UNIT_FACTION", "player")
    env.settle()
    eq(env.DB:GetProfileName(), "PvP")
    env.W.pvp = false
    Mock.Fire("PLAYER_FLAGS_CHANGED")
    env.settle()
    eq(env.DB:GetProfileName(), "Solo")
end)

T["AddRulesForClass: regole base idempotenti"] = case(function(_, env)
    local M = env.M
    local res = M:AddRulesForClass("warrior", { pvp = "PvP", raid = "Raid", party = "Default" })
    eq(#res.ids, 3, "pvp, raid, party"); eq(#res.skipped, 2, "av e solo non indicati => saltati")
    local rules = M:ListRules()
    eq(#rules, 3)
    for _, r in ipairs(rules) do eq(r.when.class, "WARRIOR"); eq(r.broken, false) end
    local bg = M:GetRule("cls-warrior-pvp")
    eq(bg.when.instance, "pvp"); eq(bg.profile, "PvP")
    -- riesecuzione: aggiorna, non duplica
    res = M:AddRulesForClass("WARRIOR", { pvp = "Solo", raid = "Raid", party = "Default", solo = "Default" })
    eq(#res.ids, 4); eq(#M:ListRules(), 4)
    eq(M:GetRule("cls-warrior-pvp").profile, "Solo")
    -- selezione sul contesto: solo la classe giusta
    local ctx = { instance = "pvp", group = "party", role = "dps", spec = 1, class = "WARRIOR", resting = false, pvpFlag = false }
    eq(M:Evaluate(ctx), "Solo")
    ctx.class = "MAGE"
    eq(M:Evaluate(ctx), nil)
    ctx.class, ctx.instance = "WARRIOR", "raid"
    eq(M:Evaluate(ctx), "Raid")
    ctx.instance = "party"
    eq(M:Evaluate(ctx), "Default")
    -- applicazione reale
    env.W.instance, env.W.inInstance = "raid", true
    env.settle()
    eq(env.DB:GetProfileName(), "Raid")
end)

T["AddRulesForClass: input errato e Presets solo con guardia"] = case(function(_, env)
    local M = env.M
    local function bad(...) local r, e = M:AddRulesForClass(...); eq(r, nil); assert(type(e) == "string") end
    bad(nil, {}); bad(5, {}); bad("", {}); bad("due parole", {}); bad("WARRIOR"); bad("WARRIOR", "x")
    bad("NONESISTE", { pvp = "PvP" })
    local res = M:AddRulesForClass("MAGE", { pvp = 5, raid = {}, party = "" })
    eq(#res.ids, 0); eq(#res.skipped, 5)
    eq(#M:ListRules(), 0)
    -- Presets assente o che lancia errori: nessun problema
    BadbUI.Presets = nil
    assert(#M:AddRulesForClass("MAGE", { pvp = "PvP" }).ids == 1)
    BadbUI.Presets = { Get = function() error("boom") end }
    assert(#M:AddRulesForClass("PRIEST", { pvp = "PvP" }).ids == 1)
    -- con Presets: il titolo del template etichetta la regola
    BadbUI.Presets = { Get = function(_, key) return key == "druid-pvp-bg" and { title = "BG Druido" } or nil end }
    M:AddRulesForClass("DRUID", { pvp = "PvP", raid = "Raid" })
    eq(M:GetRule("cls-druid-pvp").name, "BG Druido")
    eq(M:GetRule("cls-druid-raid").name, "Raid DRUID")
end)

T["Alterac Valley: pvpKind per ID e per nome; la regola av ha la precedenza su pvp"] = case(function(_, env)
    local M = env.M
    M:AddRulesForClass("WARRIOR", { pvp = "PvP", av = "Solo", raid = "Raid", party = "Default" })
    env.W.instance, env.W.inInstance = "pvp", true
    local function info(name, id) GetInstanceInfo = function() return name, "pvp", 0, "", 0, 0, false, id end end
    info("Warsong Gulch", 489)
    eq(M:GetCurrent().pvpKind, "bg"); eq(M:Evaluate(), "PvP")
    info("Alterac Valley", 30)
    eq(M:GetCurrent().pvpKind, "av", "per ID istanza"); eq(M:Evaluate(), "Solo", "precedenza di av")
    info("Valle d'Alterac", 0)
    eq(M:GetCurrent().pvpKind, "av", "per nome (itIT)")
    info(nil, nil)
    eq(M:GetCurrent().pvpKind, "bg", "informazioni mancanti: campo generico")
    GetInstanceInfo = function() error("boom") end
    eq(M:GetCurrent().pvpKind, "bg", "API che lancia errori")
    GetInstanceInfo = nil
    eq(M:GetCurrent().pvpKind, "bg", "API assente")
    env.W.instance, env.W.inInstance = "raid", true
    eq(M:GetCurrent().pvpKind, "", "fuori dal PvP nessun tipo")
    -- Senza profilo av: Alterac ricade sulla regola pvp
    M:AddRulesForClass("WARRIOR", { pvp = "PvP", raid = "Raid", party = "Default" })
    env.W.instance = "pvp"
    info("Alterac Valley", 30)
    eq(M:Evaluate(), "Solo", "la regola av esistente resta finche' non viene rimossa")
    M:RemoveRule("cls-warrior-av")
    eq(M:Evaluate(), "PvP", "senza regola av vale pvp")
    -- Condizione non valida
    local id, err = M:AddRule({ profile = "PvP", when = { instance = "pvp", pvpKind = "arena" } })
    eq(id, nil); assert(type(err) == "string")
end)

T["pagina: ciclo istanza senza arena, classi di Forever, flag PvP"] = case(function(_, env)
    local M = env.M
    M.page.build(CreateFrame("Frame"), {})
    local ps = M._page
    local function click(b) b.__scripts.OnClick(b) end
    local seen = {}
    for _ = 1, 8 do click(ps.cycles[1]); seen[#seen + 1] = ps.form.instance end
    for _, v in ipairs(seen) do assert(v ~= "arena", "il form non offre arena") end
    for _ = 1, 12 do click(ps.cycles[5]); assert(ps.form.class == nil or #ps.form.class > 0) end
    ps.form.class = nil
    click(ps.cycles[9]); eq(ps.form.pvpFlag, true)
    click(ps.createBtn)
    eq(M:ListRules()[1].when.pvpFlag, true)
end)

return T
