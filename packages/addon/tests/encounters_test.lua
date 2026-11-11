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

local function sources()
    local ns = { Badb = BadbUI }
    for _, file in ipairs({ "Source", "Journal" }) do
        assert(loadfile(root .. "/Modules/Encounters/" .. file .. ".lua"))("BadbUI", ns)
    end
    return ns.EncounterSource, ns.EncounterJournal
end

local ENUM = {
    EncounterTimelineEventState = { Active = 0, Paused = 1, Finished = 2, Canceled = 3 },
    EncounterTimelineEventSource = { Encounter = 0, Script = 1, EditMode = 2 },
}

T["encounters: timer ordinati, pausa, eventi terminali ed esterni"] = function()
    withGlobals({
        Enum = ENUM,
        C_EncounterTimeline = {
            GetEventList = function() return { 1, 2, 3, 4 } end,
            GetEventInfo = function(id) return { spellName = "Mossa " .. id, duration = 10, source = id == 4 and 1 or 0 } end,
            GetEventTimeRemaining = function(id) return id == 1 and 8 or 4 end,
            GetEventState = function(id) return id == 3 and 2 or (id == 1 and 1 or 0) end,
        },
    }, function()
        local source = sources()
        local rows = source.Timeline()
        eq(#rows, 2)
        eq(rows[1].name, "Mossa 2")
        eq(rows[1].value, "0:04")
        eq(rows[1].color, "warning")
        eq(rows[1].progress, 0.4)
        eq(rows[2].detail, "In pausa")
        eq(rows[2].color, nil)
    end)
end

T["encounters: API mancanti, opzione spenta e dati opachi"] = function(Mock)
    local secret = Mock.Secret()
    local enabled = false
    withGlobals({ C_EncounterTimeline = false }, function()
        local source = sources()
        local _, state = source.Timeline()
        eq(state, "unavailable")
    end)
    withGlobals({
        Enum = ENUM,
        C_EncounterTimeline = {
            IsFeatureEnabled = function() return enabled end,
            GetSortedEventList = function(max, _, excludeTerminal, excludeHidden)
                eq(max, 24)
                eq(excludeTerminal, true)
                eq(excludeHidden, true)
                return { 9, secret }
            end,
            GetEventInfo = function() return { spellName = secret, duration = 10, source = 0, isApproximate = secret } end,
            GetEventTimeRemaining = function() return secret end,
        },
    }, function()
        local source = sources()
        local _, state = source.Timeline()
        eq(state, "disabled")
        enabled, Mock.combat = true, true
        local rows, current = source.Timeline()
        eq(current, "restricted")
        eq(#rows, 1)
        eq(rows[1].name, secret)
        eq(rows[1].value, "—")
        eq(rows[1].progress, nil)
    end)
end

T["encounters: code, inviti e partite leggono le unità native"] = function()
    withGlobals({
        GetMaxBattlefieldID = function() return 4 end,
        GetBattlefieldStatus = function(index)
            local states = { "queued", "confirm", "active", "none" }
            return states[index], "Campo " .. index
        end,
        GetBattlefieldTimeWaited = function() return 43000 end,
        GetBattlefieldEstimatedWaitTime = function() return 88000 end,
        GetBattlefieldPortExpiration = function() return 15 end,
        GetBattlefieldInstanceRunTime = function() return 90500 end,
    }, function()
        local source = sources()
        local rows = source.Battlegrounds()
        eq(#rows, 3)
        eq(rows[1].value, "0:43")
        eq(rows[1].detail, "Attesa media 1:28")
        eq(rows[2].value, "0:15")
        eq(rows[3].value, "1:31")
    end)
end

T["encounters: salvataggi attivi, scadenza e progressi leggibili"] = function(Mock)
    local secret = Mock.Secret()
    withGlobals({
        GetNumSavedInstances = function() return 3 end,
        GetSavedInstanceInfo = function(index)
            if index == 1 then return "Raid A", 10, 86400, 3, true, true, 0, true, 10, "Normale", 7, 2 end
            if index == 2 then return "Raid B", 11, 1200, 3, false end
            return "Raid C", 12, secret, 3, true, false, 0, true, 10, secret, secret, secret
        end,
    }, function()
        local source = sources()
        local rows = source.Lockouts()
        eq(#rows, 2)
        eq(rows[1].value, "1 g 0 h")
        eq(rows[1].detail, "Normale · 2/7 · Esteso")
        eq(rows[2].value, "—")
    end)
end

T["encounters: registro locale deduplica, conserva l'esito e ignora valori opachi"] = function(Mock)
    local stamp, map, kind = 1700000000, 36, "party"
    withGlobals({
        GetServerTime = function() return stamp end,
        GetInstanceInfo = function() return "Officina", kind, 1, nil, nil, nil, nil, map end,
    }, function()
        local _, journal = sources()
        journal:Initialize()
        local first = journal:Observe()
        eq(journal:Observe(), first)
        journal:EncounterEnd("Boss A", 0)
        journal:EncounterEnd("Boss B", 1)
        journal:EncounterEnd(Mock.Secret(), Mock.Secret())
        eq(first.kills, 1)
        eq(first.attempts, 2)
        eq(first.lastBoss, "Boss B")
        journal:Initialize()
        eq(journal:Observe().entered, stamp)
        kind = "none"
        journal:Observe()
        kind, stamp = "party", stamp + 60
        eq(journal:Observe().entered, stamp)
        eq(#journal:Rows(), 2)
        eq(journal:Rows()[2].value:match("1/2 vittorie"), "1/2 vittorie")
        eq(BadbUIDB.data.encounters.version, 1)
    end)
end

T["encounters: registro ripara dati corrotti e rispetta limite e retention"] = function()
    local stamp, map = 1700000000, 1
    withGlobals({
        GetServerTime = function() return stamp end,
        GetInstanceInfo = function() return "Officina", "party", 1, nil, nil, nil, nil, map end,
    }, function()
        local _, journal = sources()
        local store = BadbUI.DB:GetStore("encounters")
        store.version, store.visits = 1, { { name = "invalido", kind = {} }, true }
        journal:Initialize()
        eq(#journal:Rows(), 0)
        for index = 1, 130 do
            map = index
            journal:Observe()
        end
        eq(#journal:Rows(), 120)
        eq(store.visits[1].map, 11)
        stamp = stamp + 91 * 86400
        eq(#journal:Rows(), 0)
        journal:Observe()
        eq(#store.visits, 1)
    end)
end

local function extendWindowMock(Mock)
    local methods = Mock.Methods
    function methods:GetHeight() return 180 end
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
end

T["encounters: guida e slash, richiesta salvataggi solo fuori combattimento"] = function(Mock)
    extendWindowMock(Mock)
    local requests = 0
    local module = BadbUI.Encounters
    assert(BadbUI.ConfigUI:FindPage("mod:Encounters"))
    assert(BadbUI.Guides:Get("suite-encounters:overview"))
    for _, replacement in ipairs(module.replaces) do eq(replacement.coverage, "partial") end
    withGlobals({
        GetNumSavedInstances = function() return 0 end,
        GetSavedInstanceInfo = function() end,
        RequestRaidInfo = function() requests = requests + 1 end,
    }, function()
        Mock.combat = true
        assert(BadbUI.Slash:Dispatch("encounters lockouts"))
        eq(module.window:IsShown(), true)
        eq(module.view, "lockouts")
        eq(requests, 0)
        Mock.combat = false
        Mock.Fire("PLAYER_REGEN_ENABLED")
        eq(requests, 1)
        Mock.Fire("PLAYER_REGEN_ENABLED")
        eq(requests, 1)
        BadbUI.Modules:SetEnabled("Encounters", false)
        eq(module.window:IsShown(), false)
        eq(module.window:GetScript("OnUpdate"), nil)
    end)
end

T["encounters: apertura automatica solo per timeline disponibile, chiusura a fine scontro"] = function(Mock)
    extendWindowMock(Mock)
    local module = BadbUI.Encounters
    module:Set("autoOpenBoss", true)
    withGlobals({ C_EncounterTimeline = false }, function()
        Mock.Fire("ENCOUNTER_START", 10, "Boss", 1, 5)
        eq(module.window, nil)
    end)
    withGlobals({
        C_EncounterTimeline = {
            GetEventList = function() return { 1 } end,
            GetEventInfo = function() return { spellName = "Mossa", duration = 10 } end,
            GetEventTimeRemaining = function() return 4 end,
        },
    }, function()
        Mock.Fire("ENCOUNTER_START", 10, "Boss", 1, 5)
        eq(module.window:IsShown(), true)
        eq(module.window.list.rows[1].name:GetText(), "Mossa")
        Mock.Fire("ENCOUNTER_END", 10, "Boss", 1, 5, 1)
        eq(module.window:IsShown(), false)
    end)
end

return T
