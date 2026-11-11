local T = {}
T["monitor obiettivi: carico sicuro, copertura Questie parziale"] = function()
    local M = BadbUI.QuestTracker
    assert(M and M.enabled ~= nil)
    local suite = BadbUI.Suite:ListCoverage()
    local questie, helper = false, false
    for _, r in ipairs(suite) do
        if r.addon == "Questie" then questie = r.coverage == "partial" end
        if r.addon == "QuestHelper" then helper = r.coverage == "partial" end
    end
    assert(questie and helper, "Questie/QuestHelper partial coverage must be declared")
    if M.ListWatched then assert(type(M:ListWatched()) == "table") end
end
return T
