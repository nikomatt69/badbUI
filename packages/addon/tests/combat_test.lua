local T = {}
local root = arg and arg[1] or "."

local function eq(actual, expected)
    if actual ~= expected then
        error(("atteso %s, ottenuto %s"):format(tostring(expected), tostring(actual)), 2)
    end
end

local function withGlobals(values, fn)
    local saved = {}
    for key, value in pairs(values) do
        saved[#saved + 1] = { key, _G[key] }
        _G[key] = value or nil
    end
    local ok, err = pcall(fn)
    for _, entry in ipairs(saved) do _G[entry[1]] = entry[2] end
    if not ok then error(err, 0) end
end

local function source()
    local ns = { Badb = BadbUI }
    assert(loadfile(root .. "/Modules/Combat/Source.lua"))("BadbUI", ns)
    return ns.CombatSource
end

local ENUM = {
    DamageMeterType = { DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3 },
    DamageMeterSessionType = { Overall = 0, Current = 1 },
}
local function withMeter(api, fn)
    withGlobals({ C_DamageMeter = api, Enum = ENUM }, fn)
end
local function combatSession()
    return {
        combatSources = {
            { name = "Mira", sourceGUID = "Player-1", totalAmount = 240, amountPerSecond = 12, isLocalPlayer = true },
            { name = "Luca", sourceGUID = "Player-2", totalAmount = 120, amountPerSecond = 6 },
        },
        totalAmount = 360, durationSeconds = 20,
    }
end

T["combat: scontri, metriche e magie arrivano dalle API native"] = function()
    withMeter({
        GetCombatSessionFromType = function(scope, metric)
            if metric == 3 then eq(scope, 0) else eq(scope, 1) end
            return combatSession()
        end,
        GetCombatSessionFromID = function(id, metric)
            eq(id, 7)
            eq(metric, 2)
            return combatSession()
        end,
        GetAvailableCombatSessions = function()
            return { { sessionID = 7, name = "Un nemico" }, { sessionID = 8, name = "" } }
        end,
        GetCombatSessionSourceFromType = function(scope, metric, guid, creature)
            eq(scope, 1)
            eq(metric, 0)
            eq(guid, "Player-1")
            eq(creature, nil)
            return { combatSpells = { { spellID = 116, totalAmount = 80 } } }
        end,
    }, function()
        local data = source()
        eq(#data.Metrics(), 4)
        eq(data.Sessions()[3].value, 8)
        eq(data.Sessions()[4].text, "Un nemico")
        local current = data.Meter("DamageDone", "Current")
        eq(current.state, "ready")
        eq(current.rows[1].name, "Mira")
        eq(current.rows[1].player, true)
        eq(current.rows[2].progress, 0.5)
        eq(current.total, 360)
        eq(current.duration, 20)
        eq(data.Meter("Hps", "Overall").rows[1].value, 12)
        eq(data.Meter("HealingDone", 7).state, "ready")
        local detail = data.Breakdown("DamageDone", "Current", current.rows[1].identity)
        eq(detail.rows[1].name, "Magia 116")
        eq(detail.rows[1].value, 80)
    end)
end

T["combat: i dati opachi del contatore non entrano nei calcoli"] = function(Mock)
    local secret = Mock.Secret()
    local session = {
        combatSources = {
            { name = secret, sourceGUID = secret, totalAmount = secret, isLocalPlayer = secret },
            { name = "Luca", totalAmount = 10 },
            secret,
        },
        totalAmount = secret, durationSeconds = secret,
    }
    withMeter({
        GetCombatSessionFromType = function() return session end,
        GetCombatSessionSourceFromType = function() error("identificatore riservato") end,
    }, function()
        local data = source()
        local result = data.Meter("DamageDone", "Current")
        eq(result.state, "ready")
        eq(result.limited, true)
        eq(result.total, nil)
        eq(result.duration, nil)
        eq(result.rows[1].identity, nil)
        eq(result.rows[1].public, nil)
        eq(result.rows[2].progress, nil)
        session.combatSources = secret
        eq(data.Meter("DamageDone", "Current").state, "restricted")
        session = secret
        eq(data.Meter("DamageDone", "Current").state, "restricted")
    end)
end

T["combat: API assenti, rifiutate e dati invalidi hanno esiti distinti"] = function()
    withMeter(false, function() eq(source().Meter("DamageDone", "Current").state, "unavailable") end)
    withMeter({
        IsDamageMeterAvailable = function() return false end,
        GetCombatSessionFromType = function() error("API disabilitata") end,
    }, function() eq(source().Meter("DamageDone", "Current").state, "unavailable") end)
    withMeter({
        GetCombatSessionFromType = function() error("API rifiutata") end,
        GetCombatSessionFromID = function() end,
    }, function()
        local data = source()
        eq(data.Meter("DamageDone", "Current").state, "unreadable")
        eq(data.Meter("DamageDone", 123).state, "unreadable")
        eq(data.Meter("Tipo inesistente", "Current").state, "unavailable")
        eq(data.Meter("DamageDone", 0 / 0).state, "unavailable")
    end)
    withMeter({
        GetCombatSessionFromType = function()
            return { combatSources = { { totalAmount = 0 / 0 }, 17, { totalAmount = math.huge } } }
        end,
    }, function()
        local result = source().Meter("DamageDone", "Current")
        eq(result.state, "empty")
        eq(#result.rows, 0)
    end)
end

T["combat: limiti su storico e partecipanti"] = function()
    local entries, sessions = {}, {}
    for i = 1, 300 do
        entries[i] = { name = "Giocatore", totalAmount = i }
        sessions[i] = { sessionID = i, name = "Scontro" }
    end
    withMeter({
        GetCombatSessionFromType = function() return { combatSources = entries } end,
        GetCombatSessionFromID = function() end,
        GetAvailableCombatSessions = function() return sessions end,
    }, function()
        local data = source()
        eq(#data.Sessions(), 32)
        eq(data.Sessions()[3].value, 300)
        eq(#data.Meter("DamageDone", "Current").rows, 100)
    end)
end

T["combat: minaccia ordinata per valore grezzo, soglia scalata per riga"] = function()
    withGlobals({
        UnitExists = function(unit) return unit == "target" end,
        UnitCanAttack = function() return true end,
        IsInRaid = function() return false end,
        GetNumSubgroupMembers = function() return 2 end,
        UnitName = function(unit) return unit end,
        UnitDetailedThreatSituation = function(unit, target)
            eq(target, "target")
            if unit == "player" then return false, 1, 95, 65, 450 end
            if unit == "party1" then return true, 3, 100, 100, 520 end
            return false, 0, 98, 63, 420
        end,
    }, function()
        local result = source().Threat()
        eq(result.state, "ready")
        eq(#result.rows, 3)
        eq(result.rows[1].name, "party1")
        eq(result.rows[2].player, true)
        eq(result.rows[2].public, 95)
        eq(result.rows[3].public, 98)
    end)
end

T["combat: minaccia opaca, stato pubblico di riserva e nessun bersaglio"] = function(Mock)
    local secret = Mock.Secret()
    local exists, simpleStatus, calls = true, secret, 0
    withGlobals({
        UnitExists = function() return exists end,
        UnitCanAttack = function() return true end,
        IsInRaid = false,
        GetNumSubgroupMembers = false,
        UnitDetailedThreatSituation = function()
            calls = calls + 1
            return secret, secret, secret, secret, secret
        end,
        UnitThreatSituation = function() return simpleStatus end,
    }, function()
        local data = source()
        Mock.combat = true
        eq(data.Threat().state, "restricted")
        simpleStatus = 2
        local result = data.Threat()
        eq(result.state, "ready")
        eq(result.limited, true)
        eq(result.rows[1].status, 2)
        eq(result.rows[1].public, nil)
        exists = false
        eq(data.Threat().state, "noTarget")
        eq(calls, 2)
    end)
end

local function extendWindowMock(Mock)
    local methods = Mock.Methods
    function methods:GetHeight() return self.__height or 160 end
    function methods:SetSize(w, h) self.__width, self.__height = w, h end
    function methods:GetStringWidth() return #(self:GetText() or "") * 6 end
    function methods:Show()
        local changed = not self.__shown
        self.__shown = true
        local onShow = self:GetScript("OnShow")
        if changed and onShow then onShow(self) end
    end
    function methods:Hide()
        local changed = self.__shown
        self.__shown = false
        local onHide = self:GetScript("OnHide")
        if changed and onHide then onHide(self) end
    end
    function methods:SetFormattedText(fmt, value)
        if issecretvalue(value) then self.__opaque = true
        else self:SetText(fmt:format(value)) end
    end
end

T["combat: slash, widget, guida, aggiornamento accorpato e disattivazione"] = function(Mock)
    extendWindowMock(Mock)
    local pending, reads = {}, 0
    local model = combatSession()
    BadbUI.Compat.After = function(_, fn) pending[#pending + 1] = fn end
    withMeter({
        GetCombatSessionFromType = function()
            reads = reads + 1
            return model
        end,
        GetCombatSessionSourceFromType = function()
            return { combatSpells = { { spellID = 116, totalAmount = 80 } } }
        end,
    }, function()
        Mock.combat = true
        assert(BadbUI.Slash:Dispatch("combat"))
        local combat = BadbUI.Combat
        assert(BadbUI.ConfigUI:FindPage("mod:Combat"))
        assert(BadbUI.Guides:Get("suite-combat:meter"))
        for _, entry in ipairs(combat.replaces) do eq(entry.coverage, "partial") end
        local window = combat.window
        eq(window:IsShown(), true)
        eq(window.list.rows[1].name:GetText(), "Mira")
        eq(window.list.rows[1].value:GetText(), "240")
        window.list.rows[1]:GetScript("OnClick")(window.list.rows[1])
        eq(window.columnName:GetText(), "Magia")
        eq(window.list.rows[1].name:GetText(), "Magia 116")
        assert(BadbUI.Slash:Dispatch("combat"))
        eq(window.columnName:GetText(), "Partecipante")
        local secret = Mock.Secret()
        model.combatSources[1].name = secret
        model.combatSources[1].totalAmount = secret
        local before = reads
        Mock.Fire("DAMAGE_METER_CURRENT_SESSION_UPDATED")
        Mock.Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED")
        eq(#pending, 1)
        eq(reads, before)
        pending[1]()
        eq(reads, before + 1)
        eq(window.list.rows[1].value.__opaque, true)

        Mock.Fire("DAMAGE_METER_CURRENT_SESSION_UPDATED")
        BadbUI.Modules:SetEnabled("Combat", false)
        eq(window:IsShown(), false)
        eq(window.list.rows[1].item, nil)
        pending[2]()
        eq(reads, before + 1)
        eq(combat:Open(), false)
    end)
end

T["combat: apertura all'accesso e dimensioni seguono il profilo"] = function(Mock)
    extendWindowMock(Mock)
    local combat, db = BadbUI.Combat, BadbUI.DB
    withMeter(false, function()
        local current = db:GetProfileName()
        combat:Set("showAtLogin", true)
        Mock.Fire("PLAYER_ENTERING_WORLD", true, false)
        eq(combat.window:IsShown(), true)
        local firstWidth = combat.window:GetWidth()
        db:SetProfile("altro")
        combat:Set("width", firstWidth + 60)
        combat:Set("height", "danneggiato")
        combat:OnProfileChanged()
        eq(combat.window:GetWidth(), firstWidth + 60)
        eq(combat.window:GetHeight(), combat.defaults.height)
        db:SetProfile(current)
        eq(combat.window:GetWidth(), firstWidth)
        eq(combat.window.empty:IsShown(), true)
    end)
end

return T
