local T = {}

local function eq(actual, expected)
    assert(actual == expected, ("%s ~= %s"):format(tostring(actual), tostring(expected)))
end

local function withLog(Mock, fn)
    local names = { "C_QuestLog", "UnitXP", "UnitXPMax", "UnitLevel", "GetMaxPlayerLevel", "GetServerTime" }
    local saved = {}
    for _, key in ipairs(names) do saved[key] = _G[key] end
    local after = BadbUI.Compat.After
    local rows = {
        { isHeader = true, title = "Vallée nord" },
        { questID = 12, title = "Gemme antiche", level = 13 },
        { questID = 15, title = "Consegna urgente", difficultyLevel = 14 },
        { isHeader = true, title = "Città" },
        { questID = 77, title = "Scorta", level = 17 },
        { questID = 78, title = "Missione interna", isHidden = true },
    }
    local objectives = {
        [12] = { { text = "Gemme: 2/4", numFulfilled = 2, numRequired = 4, finished = false } },
        [15] = { { text = "Trova il messaggero", numFulfilled = 0, numRequired = 0, finished = true } },
    }
    local reads = 0
    C_QuestLog = {
        GetNumQuestLogEntries = function() reads = reads + 1; return #rows end,
        GetInfo = function(index) return rows[index] end,
        ReadyForTurnIn = function(id) return id == 15 end,
        IsComplete = function() return false end,
        IsFailed = function(id) return id == 77 end,
        GetQuestObjectives = function(id) return objectives[id] or {} end,
        GetTitleForQuestID = function(id) return "Titolo " .. id end,
    }
    UnitLevel = function() return 14 end
    GetMaxPlayerLevel = function() return 60 end
    UnitXP = function() return 300 end
    UnitXPMax = function() return 1000 end
    GetServerTime = function() return 1800000000 end

    local module = BadbUI.Quests
    if BadbUI.Modules:Get("QuestTracker") then BadbUI.Modules:Disable("QuestTracker") end
    BadbUI.Modules:Disable("Quests")
    BadbUI.Modules:Enable("Quests")
    local ok, err = pcall(fn, module, rows, objectives, function() return reads end)
    for _, key in ipairs(names) do _G[key] = saved[key] end
    BadbUI.Compat.After = after
    Mock.combat = false
    assert(ok, err)
end

T["ricerca per titolo zona e ID con obiettivi e stato del client"] = function(Mock)
    withLog(Mock, function(m)
        eq(#m:List(), 3)
        eq(#m:List("vallee GEMME"), 1)
        eq(#m:List("77 citta"), 1)
        eq(#m:List("[gemme]"), 0)
        local quest = m:List("vallee GEMME")[1]
        eq(quest.id, 12)
        eq(quest.level, 13)
        eq(quest.objectives[1].have, 2)
        eq(quest.objectives[1].need, 4)
        eq(quest.objectives[1].done, false)
        eq(m:List(nil, "ready")[1].id, 15)
        eq(m:List("15")[1].level, 14)
        eq(m:List("77")[1].status, "failed")
    end)
end

T["distingue registro parziale, ultimo registro e API indisponibili"] = function(Mock)
    withLog(Mock, function(m, rows, objectives)
        rows[3].title = Mock.Secret()
        objectives[12][1].numFulfilled = Mock.Secret()
        objectives[12][2] = { text = Mock.Secret() }
        C_QuestLog.ReadyForTurnIn = function() return Mock.Secret() end
        C_QuestLog.IsComplete = function() error("not readable") end
        Mock.combat = true
        Mock.Fire("QUEST_LOG_UPDATE")
        eq(m.log.partial, true)
        eq(#m:List(), 2)
        local entry = m:List("12")[1]
        eq(entry.status, "unknown")
        eq(entry.objectives[1].have, nil)
        eq(entry.objectivesKnown, false)
        C_QuestLog.GetNumQuestLogEntries = function() return Mock.Secret() end
        Mock.Fire("QUEST_LOG_UPDATE")
        eq(m.logStatus, "unreadable")
        eq(#m:List(), 2)
        eq(m:SetPinned(12, true), false)
        C_QuestLog = nil
        Mock.Fire("QUEST_LOG_UPDATE")
        eq(m.logStatus, "unsupported")
        eq(#m:List(), 2)
    end)
end

T["cronologia consegne e preferiti restano nel personaggio tra profili e ricariche"] = function(Mock)
    withLog(Mock, function(m)
        eq(m:SetPinned(12, true), true)
        eq(m:SetPinned(15, true), true)
        eq(#m:List(nil, "pinned"), 2)
        Mock.Fire("QUEST_TURNED_IN", 15, 242)
        eq(m:IsPinned(15), false)
        Mock.Fire("QUEST_TURNED_IN", 80, Mock.Secret())
        local history = m:List(nil, "history")
        eq(history[1].title, "Titolo 80")
        eq(history[1].xp, nil)
        eq(history[2].title, "Consegna urgente")
        eq(history[2].xp, 242)
        eq(history[2].time, 1800000000)
        local store = BadbUI.DB:GetStore("quests")
        BadbUI.DB:SetProfile("Missioni Due")
        eq(m:IsPinned(12), true)
        eq(BadbUI.DB:GetStore("quests"), store)
        m:OnInitialize()
        eq(m:IsPinned(12), true)
        eq(#m:List(nil, "history"), 2)
        Mock.Fire("QUEST_REMOVED", 12)
        eq(#m:List(nil, "pinned"), 0)
    end)
end

T["rimuove i preferiti obsoleti solo su conferma del client"] = function(Mock)
    withLog(Mock, function(m, rows)
        eq(m:SetPinned(12, true), true)
        table.remove(rows, 2)
        C_QuestLog.IsOnQuest = function() return Mock.Secret() end
        Mock.Fire("QUEST_LOG_UPDATE")
        eq(m:IsPinned(12), true)
        C_QuestLog.IsOnQuest = function() return false end
        Mock.Fire("QUEST_LOG_UPDATE")
        eq(m:IsPinned(12), false)
    end)
end

T["applica i limiti a preferiti e consegne e ripulisce dati corrotti"] = function(Mock)
    withLog(Mock, function(m, rows)
        for i = 1, 26 do rows[#rows + 1] = { questID = 100 + i, title = "Missione" } end
        Mock.Fire("QUEST_LOG_UPDATE")
        for i = 1, 25 do eq(m:SetPinned(100 + i, true), true) end
        eq(m:SetPinned(126, true), false)
        for i = 1, 60 do Mock.Fire("QUEST_TURNED_IN", 80, i) end
        local history = m:List(nil, "history")
        eq(#history, 50)
        eq(history[1].xp, 60)
        eq(history[50].xp, 11)
        local saved = BadbUI.DB:GetStore("quests").characters[BadbUI.DB.char]
        saved.pins = { {}, 12, math.huge, 15 }
        saved.history = { { id = 12, title = "|Tmalformed|t", xp = 0/0, time = -1 }, { id = -15, title = "Ignora" } }
        m:OnInitialize()
        eq(m:IsPinned(12), true)
        eq(m:IsPinned(15), true)
        eq(#m:List(nil, "history"), 1)
        eq(m:List(nil, "history")[1].title, "Tmalformed t")
        eq(m:List(nil, "history")[1].xp, nil)
        eq(m:List(nil, "history")[1].time, nil)
    end)
end

T["aggrega gli eventi ed aggiorna gli XP senza rileggere il registro"] = function(Mock)
    withLog(Mock, function(m, _, _, reads)
        local callbacks = {}
        BadbUI.Compat.After = function(_, fn) callbacks[#callbacks + 1] = fn end
        local count = reads()
        Mock.Fire("QUEST_LOG_UPDATE")
        Mock.Fire("QUEST_ACCEPTED")
        Mock.Fire("PLAYER_XP_UPDATE", "player")
        eq(#callbacks, 1)
        callbacks[1]()
        eq(reads(), count + 1)
        eq(m.progress.current, 300)
        UnitXP = function() return 750 end
        Mock.Fire("PLAYER_XP_UPDATE", "party1")
        eq(#callbacks, 1)
        Mock.Fire("PLAYER_XP_UPDATE", "player")
        eq(#callbacks, 2)
        callbacks[2]()
        eq(m.progress.current, 750)
        eq(reads(), count + 1)
        UnitLevel = function() return 60 end
        Mock.Fire("PLAYER_LEVEL_UP", 60)
        callbacks[3]()
        eq(m.progress.capped, true)
        eq(m.progress.current, nil)

        Mock.Fire("QUEST_LOG_UPDATE")
        local before = reads()
        BadbUI.Modules:Disable("Quests")
        callbacks[4]()
        eq(reads(), before)
        eq(m:Open(), false)
    end)
end

T["mostra diario monitor e progresso nella UI con cambio profilo"] = function(Mock)
    withLog(Mock, function(m)
        Mock.Methods.GetStringWidth = function(frame) return #(frame:GetText() or "") * 6 end
        Mock.Methods.GetHeight = function() return 200 end
        assert(BadbUI.ConfigUI:FindPage("mod:Quests"))
        assert(BadbUI.Guides:Get("badb-quests:journal"))
        assert(BadbUI.Slash:Dispatch("quests gemme"))
        local w = m.window
        eq(w:IsShown(), true)
        eq(w.xp:GetText(), "Level 14 · 300/1000 XP")
        eq(w.entry.id, 12)
        eq(w.detail.list.data[1].text, "Gemme: 2/4")
        w.detail.pin:GetScript("OnClick")(w.detail.pin)
        eq(m:IsPinned(12), true)
        eq(m.hud, nil)
        m:Set("hud", true)
        eq(m.hud:IsShown(), true)
        eq(m.hud.rows[1].meta:GetText(), "Gemme: 2/4")
        assert(BadbUI.FrameManager.registry.BadbUIQuestTracker)
        w.query = ""
        w.tabs:Select("ready", true)
        eq(w.entry.id, 15)
        BadbUI.DB:SetProfile("Missioni HUD spento")
        eq(m.hud:IsShown(), false)
        m.hud:Show()
        eq(m.hud:IsShown(), false)
        eq(m:IsPinned(12), true)
        BadbUI.Modules:Disable("Quests")
        eq(w:IsShown(), false)
    end)
end

T["dichiara come parziale solo la copertura dei due addon principali"] = function()
    local seen = {}
    for _, entry in ipairs(BadbUI.Suite:ListCoverage()) do
        if entry.module == "Quests" then
            eq(entry.coverage, "partial")
            eq(entry.removable, false)
            assert(entry.addon == "Questie" or entry.addon == "Polestar")
            seen[entry.addon] = true
        end
    end
    assert(seen.Questie and seen.Polestar)
end

return T
