local T = {}
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function with(values, fn)
    local old = {}
    for k, v in pairs(values) do old[k] = _G[k]; _G[k] = v end
    local ok, err = pcall(fn)
    for k in pairs(values) do _G[k] = old[k] end
    if not ok then error(err) end
end
local function api()
    return {
        UnitGUID = function() return "Player-Test-1" end,
        GetServerTime = function() return 1794260000 end,
        UnitLevel = function() return 23 end,
        GetZoneText = function() return "Westfall" end,
        C_QuestLog = {
            GetNumQuestLogEntries = function() return 3 end,
            GetInfo = function(i)
                if i == 1 then return { title = "Westfall", isHeader = true } end
                return { questID = i == 2 and 12 or 13, title = i == 2 and "The People's Militia" or "A different quest", level = 14 }
            end,
            GetQuestObjectives = function() return { { text = "Defias: 2/10", numFulfilled = 2, numRequired = 10, finished = false } } end,
            IsComplete = function() return false end,
        },
        C_Container = {
            GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
            GetContainerItemInfo = function() return { itemID = 123, stackCount = 4 } end,
        },
        GetItemInfo = function() return "Quest supplies" end,
    }
end
T["selected quest and bags are frozen at send, not replaced by the next character"] = function()
    with(api(), function()
        local M = BadbUI.Chatbot
        local s = M:State(); s.selected["12"] = true; s.provider = "test"; s.model = "test-model"
        assert(M:Ask("What do I do next?"))
        local r = BadbUI_ChatbotExport.requests[1]
        eq(r.payload.context.player.level, 23); eq(r.payload.context.player.zone, "Westfall")
        eq(r.payload.context.quests[1].id, 12); eq(r.payload.context.quests[1].selected, true)
        eq(r.payload.context.quests[2].selected, false); eq(r.payload.context.quests[1].objectives[1].have, 2)
        eq(r.payload.context.bags[1].count, 4); eq(r.payload.context.bagsComplete, true)
        s.selected["12"] = false
        eq(r.payload.context.quests[1].selected, true)
        UnitGUID = function() return "Player-Test-2" end
        eq(#M:State().history, 0)
        eq(r.character, "Player-Test-1")
    end)
end
T["missing or failing APIs are unknown and bags can be excluded"] = function()
    with({ C_QuestLog = { GetNumQuestLogEntries = function() error("unavailable") end }, C_Container = { GetContainerNumSlots = function() error("unavailable") end } }, function()
        local c = BadbUI.ChatbotContext.Capture({}, true)
        eq(c.questsComplete, false); eq(c.bagsComplete, false)
        c = BadbUI.ChatbotContext.Capture({}, false)
        eq(c.bagsIncluded, false); eq(#c.bags, 0)
    end)
end
T["legacy quest and bag APIs preserve IDs and objective progress"] = function()
    local values = api()
    values.C_QuestLog, values.C_Container = {}, false
    values.GetNumQuestLogEntries = function() return 2 end
    values.GetQuestLogTitle = function(i)
        if i == 1 then return "Westfall", 0, nil, true end
        return "The People's Militia", 14, nil, false, false, 0, nil, 12
    end
    values.GetNumQuestLeaderBoards = function() return 1 end
    values.GetQuestLogLeaderBoard = function() return "Defias: 2/10", "monster", false end
    values.GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end
    values.GetContainerItemInfo = function() return "icon", 4, false, nil, nil, nil, "item:123" end
    values.GetContainerItemID = function() return 123 end
    with(values, function()
        local c = BadbUI.ChatbotContext.Capture({ ["12"] = true }, true)
        eq(c.quests[1].id, 12); eq(c.quests[1].selected, true)
        eq(c.quests[1].objectives[1].text, "Defias: 2/10")
        eq(c.bags[1].id, 123); eq(c.bags[1].count, 4)
    end)
end
T["secret and uncached IDs remain unknown rather than invalidating the export"] = function(Mock)
    local values = api()
    values.UnitLevel = function() return Mock.Secret() end
    values.C_QuestLog.GetInfo = function(i) return { questID = 0, title = "Uncached quest", isHeader = i == 1 } end
    values.C_Container.GetContainerItemInfo = function() return { itemID = Mock.Secret(), stackCount = Mock.Secret() } end
    with(values, function()
        local c = BadbUI.ChatbotContext.Capture({}, true)
        eq(c.player.level, nil); eq(c.quests[1].id, nil)
        eq(c.questsComplete, false); eq(c.bagsComplete, false)
    end)
end
T["receipts are character scoped, remove secrets from pending queue and survive reload"] = function()
    with(api(), function()
        local M = BadbUI.Chatbot
        M:State().provider, M:State().model = "test", "test-model"
        assert(M:Ask("Help"))
        assert(M:Queue("api-key", { provider = "test", key = "not-a-real-key" }))
        local s = M:State()
        local ask, auth = BadbUI_ChatbotExport.requests[1], BadbUI_ChatbotExport.requests[2]
        BadbUI_ChatbotSync = { receipts = {
            { id = ask.id, character = "Player-Test-1", generation = s.generation, text = "Reply", status = "ok", sources = { "https://www.wowhead.com/classic/quest=12" } },
            { id = auth.id, character = "Player-Test-1", generation = s.generation, text = "Connected", status = "ok" },
        } }
        M:Import(); M:Import()
        eq(#BadbUI_ChatbotExport.requests, 0); eq(s.history[1].answer, "Reply"); eq(#s.history, 1)
        assert(M:NewConversation()); eq(#s.history, 0)
        M:Import(); eq(#s.history, 0)
    end)
end
T["combat and disabled module do not enqueue or reload"] = function(Mock)
    Mock.combat = true
    eq(BadbUI.Chatbot:Ask("Help"), false)
    eq(#BadbUI_ChatbotExport.requests, 0)
    Mock.combat = false
    BadbUI.Modules:Disable("Chatbot")
    eq(BadbUI.Chatbot:Ask("Help"), false)
end
T["Forever missing SavedVariables can recover questions and replies from the bundle"] = function()
    with(api(), function()
        BadbUI_ChatbotExport = nil
        BadbUI_ChatbotSync = { receipts = { { id = "restored", kind = "ask", character = "Player-Test-1", generation = 3,
            question = "Where is my quest?", text = "In Westfall", status = "ok", sources = {} } } }
        local M = BadbUI.Chatbot
        M:Import()
        local state = M:State()
        eq(state.generation, 3); eq(state.history[1].question, "Where is my quest?"); eq(state.history[1].answer, "In Westfall")
        M:Import(); eq(#state.history, 1)
        assert(M:NewConversation())
        M:Import(); eq(#state.history, 0)
    end)
end
T["importing archived replies never pushes a pending question out of visible history"] = function()
    with(api(), function()
        local M = BadbUI.Chatbot
        local state = M:State()
        local receipts = {}
        for i = 1, 45 do
            receipts[i] = { id = "old-" .. i, kind = "ask", character = "Player-Test-1", generation = state.generation,
                question = "Old question " .. i, text = "Old answer " .. i, status = "ok", sources = {} }
            if i >= 7 then state.history[#state.history + 1] = { id = "old-" .. i, question = "Old question " .. i, status = "ok" } end
        end
        state.history[#state.history + 1] = { id = "pending", question = "My current question", status = "pending" }
        BadbUI_ChatbotExport.requests = { { id = "pending", character = "Player-Test-1" } }
        BadbUI_ChatbotSync = { receipts = receipts }
        M:Import(); M:Import()
        eq(#state.history, 40)
        eq(state.history[40].id, "pending"); eq(state.history[40].status, "pending")
        eq(state.history[1].answer, "Old answer 7")
    end)
end
T["chat section is discoverable and builds top bar composer and quest picker"] = function(Mock)
    local values, reloads = api(), 0
    values.ReloadUI = function() reloads = reloads + 1 end
    with(values, function()
        local state = BadbUI.Chatbot:State()
        state.provider, state.model, state.draft = "test", "test-model", "Where should I go?"
        local objects, old = {}, CreateFrame
        CreateFrame = function(...)
            local o = old(...); objects[#objects + 1] = o; return o
        end
        local ok, err = pcall(function()
            local page = BadbUI.ConfigUI:FindPage("mod:Chatbot")
            eq(page.title, "Chatbot")
            assert(page.build(Mock.NewObject("Frame")) >= 500)
            local questButton, send, settings
            for _, o in ipairs(objects) do
                if o.text and o.text.__text == "+ Add quests" then questButton = o end
                if o.text and o.text.__text == "Send & reload" then send = o end
                if o.text and o.text.__text == "Settings" then settings = o end
            end
            assert(questButton and send and settings)
            questButton.onClick(questButton)
            local attach
            for _, o in ipairs(objects) do if o.text and tostring(o.text.__text):find("The People's Militia", 1, true) then attach = o end end
            assert(attach); attach.onClick(attach)
            eq(BadbUI.Chatbot:State().selected["12"], true)
            local chip
            for _, o in ipairs(objects) do if o.questKey == "12" then chip = o end end
            assert(chip); chip.onClick(chip)
            eq(BadbUI.Chatbot:State().selected["12"], nil)
            -- Reopen the picker after removing the chip and attach it again.
            questButton.onClick(questButton)
            for _, o in ipairs(objects) do if o.text and tostring(o.text.__text):find("The People's Militia", 1, true) and not o.questKey then attach = o end end
            attach.onClick(attach)
            send.onClick(send)
            eq(reloads, 1)
            local request = BadbUI_ChatbotExport.requests[1]
            eq(request.payload.text, "Where should I go?")
            eq(request.payload.context.quests[1].selected, true)
            settings.onClick(settings)
            assert(BadbUI.Chatbot.settingsFrame:IsShown())
        end)
        CreateFrame = old
        if not ok then error(err) end
    end)
end
return T
