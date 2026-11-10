-- Snapshot of the active character only. Optional APIs and secret values are guarded.
local _, ns = ...
local Badb = ns.Badb
local C = {}
Badb.ChatbotContext = C
function C.Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local function pack(...) return { n = select("#", ...), ... } end
    local r = pack(pcall(fn, ...))
    if not r[1] then return nil end
    for i = 2, r.n do if Badb.Compat.IsSecret(r[i]) then r[i] = nil end end
    return unpack(r, 2, r.n)
end
local call = C.Call
local function str(v) return type(v) == "string" and v:sub(1, 2000) or nil end
local function num(v) return type(v) == "number" and v or nil end
local function id(v) local n = num(v); return n and n > 0 and n or nil end
function C.Identity()
    return str(call(UnitGUID, "player")) or ((str(call(UnitName, "player")) or "?") .. "@" .. (str(call(GetRealmName)) or "?"))
end
function C.Quests()
    local quests, complete = {}, true
    local modern = C_QuestLog and type(C_QuestLog.GetInfo) == "function"
    local count = num(call(modern and C_QuestLog.GetNumQuestLogEntries or GetNumQuestLogEntries))
    if not count then return quests, false end
    for i = 1, math.min(count, 200) do
        local q
        if modern then
            local info = call(C_QuestLog.GetInfo, i)
            if type(info) == "table" and not Badb.Compat.IsSecret(info.isHeader) and not info.isHeader then
                q = { id = id(Badb.Compat.SafeValue(info.questID)), title = str(Badb.Compat.SafeValue(info.title)), level = num(Badb.Compat.SafeValue(info.level)) }
            elseif type(info) ~= "table" then complete = false end
        else
            local title, level, _, header, _, done, _, id = call(GetQuestLogTitle, i)
            if title and not header then q = { id = num(id) and id > 0 and id or nil, title = str(title), level = num(level), complete = done == 1 } end
        end
        if q and q.title then
            q.index, q.objectives = i, {}
            if modern and q.id then
                local done = call(C_QuestLog.IsComplete, q.id)
                if type(done) == "boolean" then q.complete = done else complete = false end
                local objectives = call(C_QuestLog.GetQuestObjectives, q.id)
                if type(objectives) == "table" then
                    for _, o in ipairs(objectives) do
                        if type(o) == "table" then
                            q.objectives[#q.objectives + 1] = { text = str(Badb.Compat.SafeValue(o.text)), done = Badb.Compat.SafeValue(o.finished) == true,
                                have = num(Badb.Compat.SafeValue(o.numFulfilled)), need = num(Badb.Compat.SafeValue(o.numRequired)) }
                        end
                    end
                else complete = false end
            else
                local n = num(call(GetNumQuestLeaderBoards, i))
                if not n then complete = false end
                for j = 1, math.min(n or 0, 30) do
                    local text, _, done = call(GetQuestLogLeaderBoard, j, i)
                    q.objectives[#q.objectives + 1] = { text = str(text), done = done == true }
                end
            end
            q.key = q.id and tostring(q.id) or (tostring(i) .. ":" .. q.title)
            quests[#quests + 1] = q
        end
    end
    return quests, complete
end
function C.Capture(selected, includeBags)
    local player = Badb.Player:GetSnapshot()
    local version, build, _, interface = call(GetBuildInfo)
    local quests, questsComplete = C.Quests()
    for _, q in ipairs(quests) do q.selected = selected and selected[q.key] == true or false end
    local bags, bagsComplete = {}, includeBags ~= false
    if includeBags ~= false then
        local api = C_Container
        local slotsFn = api and api.GetContainerNumSlots or GetContainerNumSlots
        local infoFn = api and api.GetContainerItemInfo or GetContainerItemInfo
        if type(slotsFn) ~= "function" or type(infoFn) ~= "function" then bagsComplete = false end
        for bag = 0, 4 do
            local slots = num(call(slotsFn, bag))
            if not slots then bagsComplete = false end
            for slot = 1, math.min(slots or 0, 100) do
                local info, count, _, _, _, _, link = call(infoFn, bag, slot)
                local itemID
                if api and type(info) == "table" then
                    itemID = id(Badb.Compat.SafeValue(info.itemID))
                    count = num(Badb.Compat.SafeValue(info.stackCount))
                    link = str(Badb.Compat.SafeValue(info.hyperlink))
                else
                    itemID = id(call(GetContainerItemID, bag, slot))
                end
                itemID = itemID or (type(link) == "string" and id(tonumber(link:match("item:(%d+)"))))
                if itemID then
                    local name = str(call(C_Item and C_Item.GetItemInfo or GetItemInfo, itemID))
                    bags[#bags + 1] = { bag = bag, slot = slot, id = itemID, count = num(count) or 1, name = name }
                    if not name then bagsComplete = false end
                elseif info then bagsComplete = false end
            end
        end
    end
    local map = num(call(C_Map and C_Map.GetBestMapForUnit, "player"))
    local position = map and call(C_Map and C_Map.GetPlayerMapPosition, map, "player")
    local x, y
    if position then x, y = call(position.GetXY, position) end
    return { character = C.Identity(), capturedAt = num(call(GetServerTime)) or num(call(time)) or 0,
        client = { version = str(version), build = str(build), interface = num(interface), flavor = "WoW Forever" },
        player = { name = str(call(UnitName, "player")), realm = str(call(GetRealmName)), class = player.class,
            level = num(call(UnitLevel, "player")), race = str(call(UnitRace, "player")), faction = str(call(UnitFactionGroup, "player")),
            role = player.role, roleConfidence = player.roleConfidence, tree = player.treeKey,
            zone = str(call(GetZoneText)), subZone = str(call(GetSubZoneText)), map = map, x = num(x), y = num(y) },
        quests = quests, questsComplete = questsComplete, bags = bags, bagsComplete = bagsComplete, bagsIncluded = includeBags ~= false }
end
