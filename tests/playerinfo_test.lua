-- Test del servizio Core/PlayerInfo (classe, talenti, ruolo, dual spec)
local function eq(a, b, msg)
    if a ~= b then error((msg or "valori diversi") .. ": atteso " .. tostring(b) .. ", ottenuto " .. tostring(a), 2) end
end

local GLOBALS = { "UnitClass", "UnitLevel", "GetNumTalentTabs", "GetTalentTabInfo", "GetActiveTalentGroup", "GetNumTalentGroups",
    "GetSpecialization", "GetSpecializationInfo", "GetSpecializationRole", "IsInGroup", "UnitGroupRolesAssigned", "GetClassInfo" }

-- Imposta globali per il test e li ripulisce sempre (anche in caso di errore).
local function with(globals, fn)
    local saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k]; _G[k] = nil end
    for k, v in pairs(globals) do _G[k] = v end
    local ok, err = pcall(fn)
    for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
    if not ok then error(err, 0) end
end

-- Alberi in formato Classic: name, icon, points
local function classicTabs(trees)
    return {
        GetNumTalentTabs = function() return #trees end,
        GetTalentTabInfo = function(i) local t = trees[i]; return t[1], "icon", t[2] end,
    }
end

local function merge(a, b) for k, v in pairs(b) do a[k] = v end return a end

local T = {}

T["senza alcuna API: ruolo primario della classe, confidenza bassa"] = function()
    with({}, function()
        local P = BadbUI.Player
        P:Invalidate()
        local s = P:GetSnapshot()
        eq(s.role, "dps"); eq(s.roleSource, "class"); eq(s.roleConfidence, "low")
        eq(s.talentGroup, 1); eq(s.numTalentGroups, 1)
    end)
end

T["albero dominante riconosciuto per nome (Paladino Protezione = tank)"] = function()
    with(merge({ UnitClass = function() return "Paladin", "PALADIN" end },
        classicTabs({ { "Holy", 3 }, { "Protection", 31 }, { "Retribution", 0 } })), function()
        local P = BadbUI.Player
        P:Invalidate()
        local role, source, conf = P:GetRole()
        eq(role, "tank"); eq(source, "tree-name"); eq(conf, "high")
        eq(P:GetSnapshot().tree, "Protection")
        eq(P:GetSnapshot().treeSource, "talent-tabs")
    end)
end

T["nomi in italiano"] = function()
    with(merge({ UnitClass = function() return "Sacerdote", "PRIEST" end },
        classicTabs({ { "Disciplina", 0 }, { "Sacro", 0 }, { "Ombra", 31 } })), function()
        BadbUI.Player:Invalidate()
        eq(BadbUI.Player:GetRole(), "dps")
    end)
end

T["formato Cata+ (id, nome, descrizione, icona, punti)"] = function()
    with({
        UnitClass = function() return "Shaman", "SHAMAN" end,
        GetNumTalentTabs = function() return 3 end,
        GetTalentTabInfo = function(i)
            local d = { { 261, "Elemental", "d", "i", 5 }, { 263, "Enhancement", "d", "i", 2 }, { 262, "Restoration", "d", "i", 31 } }
            local t = d[i]; return t[1], t[2], t[3], t[4], t[5]
        end,
    }, function()
        BadbUI.Player:Invalidate()
        eq(BadbUI.Player:GetRole(), "healer")
    end)
end

T["albero rinominato: fallback sull'indice, confidenza media"] = function()
    with(merge({ UnitClass = function() return "Paladin", "PALADIN" end },
        classicTabs({ { "Xyz", 0 }, { "Abc", 0 }, { "Qrs", 31 } })), function()
        local P = BadbUI.Player
        P:Invalidate()
        local role, source, conf = P:GetRole()
        eq(role, "dps"); eq(source, "tree-index"); eq(conf, "medium")
    end)
end

T["pareggio o nessun punto: non si indovina, ruolo di classe"] = function()
    with(merge({ UnitClass = function() return "Paladin", "PALADIN" end },
        classicTabs({ { "Holy", 10 }, { "Protection", 10 }, { "Retribution", 0 } })), function()
        BadbUI.Player:Invalidate()
        local role, source = BadbUI.Player:GetRole()
        eq(role, "healer", "primario Paladino"); eq(source, "class")
    end)
    with(merge({ UnitClass = function() return "Warrior", "WARRIOR" end },
        classicTabs({ { "Arms", 0 }, { "Fury", 0 }, { "Protection", 0 } })), function()
        BadbUI.Player:Invalidate()
        eq(BadbUI.Player:GetDominantTree(), nil)
        eq(BadbUI.Player:GetRole(), "dps")
    end)
end

T["druido feral e' ambiguo (dps con alternativa tank)"] = function()
    with(merge({ UnitClass = function() return "Druid", "DRUID" end },
        classicTabs({ { "Balance", 0 }, { "Feral Combat", 31 }, { "Restoration", 0 } })), function()
        BadbUI.Player:Invalidate()
        local s = BadbUI.Player:GetSnapshot()
        eq(s.role, "dps"); eq(s.altRole, "tank"); eq(s.roleAmbiguous, true); eq(s.roleConfidence, "medium")
    end)
end

T["ruolo del gruppo batte l'albero; l'override batte il gruppo"] = function()
    with(merge({
        UnitClass = function() return "Druid", "DRUID" end,
        IsInGroup = function() return true end,
        UnitGroupRolesAssigned = function() return "TANK" end,
    }, classicTabs({ { "Balance", 0 }, { "Feral Combat", 31 }, { "Restoration", 0 } })), function()
        local P = BadbUI.Player
        P:Invalidate()
        local role, source = P:GetRole()
        eq(role, "tank"); eq(source, "group")
        eq(P:SetRoleOverride("healer"), true)
        role, source = P:GetRole()
        eq(role, "healer"); eq(source, "override")
        eq(P:SetRoleOverride(nil), true)
        eq(select(2, P:GetRole()), "group")
    end)
end

T["override: valore non valido rifiutato; per gruppo talenti"] = function()
    with({ UnitClass = function() return "Priest", "PRIEST" end, GetActiveTalentGroup = function() return 2 end,
        GetNumTalentGroups = function() return 2 end }, function()
        local P = BadbUI.Player
        local ok = P:SetRoleOverride("mago")
        eq(ok, false)
        eq(P:SetRoleOverride("dps", 1), true)
        P:Invalidate()
        eq(P:GetRole(), "healer", "il gruppo attivo e' 2: nessun override")
        eq(P:SetRoleOverride("dps", 2), true)
        eq(P:GetRole(), "dps")
    end)
end

T["dual spec: cambio gruppo talenti ricalcola e notifica"] = function(Mock)
    local active = 1
    local trees = {
        [1] = { { "Arms", 31 }, { "Fury", 0 }, { "Protection", 0 } },
        [2] = { { "Arms", 0 }, { "Fury", 0 }, { "Protection", 31 } },
    }
    with({
        UnitClass = function() return "Warrior", "WARRIOR" end,
        GetActiveTalentGroup = function() return active end,
        GetNumTalentGroups = function() return 2 end,
        GetNumTalentTabs = function() return 3 end,
        GetTalentTabInfo = function(i, _, _, group) local t = trees[group or active][i]; return t[1], "i", t[2] end,
    }, function()
        local P = BadbUI.Player
        P:Invalidate()
        eq(P:GetRole(), "dps")
        eq(P:GetSnapshot().numTalentGroups, 2)
        local notified
        BadbUI.Events:On({ name = "t" }, "BADB_PLAYER_CHANGED", function(_, snap) notified = snap end)
        active = 2
        Mock.Fire("ACTIVE_TALENT_GROUP_CHANGED")
        eq(P:GetRole(), "tank")
        assert(notified and notified.role == "tank", "evento BADB_PLAYER_CHANGED mancante")
    end)
end

T["profilo per spec: usa il gruppo talenti di PlayerInfo"] = function(Mock)
    local active = 1
    with({ GetActiveTalentGroup = function() return active end }, function()
        local DB = BadbUI.DB
        DB:SetProfile("Dps", true); DB:SetProfile("Tank", true); DB:SetProfile("Dps", true)
        DB:SetSpecProfile(1, "Dps"); DB:SetSpecProfile(2, "Tank")
        BadbUI.Player:Invalidate()
        active = 2
        Mock.Fire("ACTIVE_TALENT_GROUP_CHANGED")
        eq(DB:GetProfileName(), "Tank")
        active = 1
        Mock.Fire("ACTIVE_TALENT_GROUP_CHANGED")
        eq(DB:GetProfileName(), "Dps")
    end)
end

T["valori secret nelle API talenti: ignorati senza errori"] = function(Mock)
    with({
        UnitClass = function() return "Mage", "MAGE" end,
        GetNumTalentTabs = function() return Mock.Secret() end,
        GetTalentTabInfo = function() return Mock.Secret() end,
    }, function()
        BadbUI.Player:Invalidate()
        local s = BadbUI.Player:GetSnapshot()
        eq(s.role, "dps"); eq(s.roleSource, "class"); eq(s.trees, nil)
    end)
    with({
        UnitClass = function() return "Mage", "MAGE" end,
        GetNumTalentTabs = function() return 3 end,
        GetTalentTabInfo = function(i) return Mock.Secret(), "i", Mock.Secret() end,
    }, function()
        BadbUI.Player:Invalidate()
        eq(BadbUI.Player:GetRole(), "dps")
    end)
end

T["API che lanciano errori: nessun errore, degrado"] = function()
    with({
        UnitClass = function() error("boom") end,
        GetNumTalentTabs = function() error("boom") end,
        GetActiveTalentGroup = function() error("boom") end,
        IsInGroup = function() error("boom") end,
        UnitGroupRolesAssigned = function() error("boom") end,
    }, function()
        BadbUI.Player:Invalidate()
        local s = BadbUI.Player:GetSnapshot()
        eq(s.role, "dps"); eq(s.talentGroup, 1)
    end)
end

T["fallback Mainline: GetSpecialization con ruolo"] = function()
    with({
        UnitClass = function() return "Priest", "PRIEST" end,
        GetSpecialization = function() return 3 end,
        GetSpecializationInfo = function() return 258, "Shadow", "desc", "icon", "DAMAGER", "INTELLECT" end,
    }, function()
        BadbUI.Player:Invalidate()
        local s = BadbUI.Player:GetSnapshot()
        eq(s.role, "dps"); eq(s.roleSource, "specialization"); eq(s.treeSource, "specialization")
    end)
end

T["provider di alberi registrato da terzi"] = function()
    with({ UnitClass = function() return "Warrior", "WARRIOR" end }, function()
        local P = BadbUI.Player
        P:RegisterTreeProvider(function() return { { index = 3, name = "Protection", points = 20 } } end)
        P:RegisterTreeProvider("non-una-funzione")
        P:Invalidate()
        eq(P:GetRole(), "tank"); eq(P:GetSnapshot().treeSource, "provider")
        P.providers = {}
    end)
end

T["classi: 9 classi, ruoli coerenti, sonda classi presenti"] = function()
    local P = BadbUI.Player
    eq(#P.CLASSES, 9)
    local seen = {}
    for _, c in ipairs(P.CLASSES) do
        assert(not seen[c.token], "classe duplicata " .. c.token); seen[c.token] = true
        eq(#c.trees, 3, c.token .. " alberi")
        local has = {}
        for _, r in ipairs(c.roles) do has[r] = true end
        assert(has[c.primary], c.token .. ": ruolo primario non tra i ruoli")
        for _, t in ipairs(c.trees) do assert(has[t.role], c.token .. ": albero con ruolo non ammesso") end
    end
    eq(#P:ListClasses(true), 9, "senza GetClassInfo: tutte")
    with({ GetClassInfo = function(i)
        local d = { { "Warrior", "WARRIOR" }, { "Mage", "MAGE" } }
        if d[i] then return d[i][1], d[i][2], i end
    end }, function()
        local list = P:ListClasses(true)
        eq(#list, 2); eq(list[1].token, "WARRIOR"); eq(list[2].token, "MAGE")
    end)
    with({ GetClassInfo = function() return nil end }, function()
        eq(#P:ListClasses(true), 9, "sonda vuota: degrado a tutte")
    end)
end

return T
