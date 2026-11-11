-- Lettura difensiva del registro e dei progressi esposti da WoW: Forever.
local _, ns = ...
local Badb = ns.Badb
local Compat = Badb.Compat

local Journal = {}
ns.QuestJournal = Journal

local MAX_ID = 2147483647
local MAX_ENTRIES = 200
local MAX_OBJECTIVES = 32

function Journal.Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return Compat.SafeValue(value) end
end

function Journal.Integer(value, min, max)
    value = Compat.SafeValue(value)
    if type(value) == "number" and value >= min and value <= max and value == math.floor(value) then
        return value
    end
end

function Journal.ID(value)
    return Journal.Integer(value, 1, MAX_ID)
end

function Journal.Text(value, max)
    value = Compat.SafeValue(value)
    if type(value) ~= "string" or #value > max then return nil end
    local clean = value:gsub("[%c|]", " "):match("^%s*(.-)%s*$")
    if clean ~= "" then return clean end
end

local call, integer, text = Journal.Call, Journal.Integer, Journal.Text

function Journal.Available()
    local api = C_QuestLog
    return type(api) == "table" and type(api.GetNumQuestLogEntries) == "function" and type(api.GetInfo) == "function"
end

local function readObjectives(api, id)
    local raw = call(api.GetQuestObjectives, id)
    if type(raw) ~= "table" then return {}, false end
    local objectives, complete = {}, #raw <= MAX_OBJECTIVES
    for i = 1, math.min(#raw, MAX_OBJECTIVES) do
        local value = Compat.SafeValue(raw[i])
        if type(value) == "table" then
            local label = text(value.text, 500)
            local have = integer(value.numFulfilled, 0, MAX_ID)
            local need = integer(value.numRequired, 1, MAX_ID)
            local done = Compat.SafeValue(value.finished)
            if type(done) ~= "boolean" then
                if have and need then done = have >= need else done = nil end
            end
            if label or (have and need) then
                objectives[#objectives + 1] = { text = label, have = have, need = need, done = done }
            else
                complete = false
            end
        else
            complete = false
        end
    end
    return objectives, complete
end

local function readStatus(api, id)
    if call(api.IsFailed, id) == true then return "failed" end
    local ready = call(api.ReadyForTurnIn, id)
    local complete = call(api.IsComplete, id)
    if ready == true or complete == true then return "ready" end
    if ready == false or complete == false then return "active" end
    return "unknown"
end

local function fold(value)
    if Badb.Guides and Badb.Guides.Fold then return Badb.Guides.Fold(value) end
    return value:lower()
end

function Journal.Read()
    if not Journal.Available() then return nil, "unsupported" end
    local api = C_QuestLog
    local count = integer(call(api.GetNumQuestLogEntries), 0, MAX_ID)
    if not count then return nil, "unreadable" end
    local entries, byID, zone = {}, {}, nil
    local partial = count > MAX_ENTRIES
    for index = 1, math.min(count, MAX_ENTRIES) do
        local info = call(api.GetInfo, index)
        if type(info) ~= "table" or Compat.IsSecret(info.isHeader) or Compat.IsSecret(info.isHidden) then
            partial = true
        elseif info.isHeader == true then
            zone = text(info.title, 180)
        elseif info.isHidden ~= true then
            local id, title = Journal.ID(info.questID), text(info.title, 240)
            if not (id and title) then
                partial = true
            elseif not byID[id] then
                local objectives, objectivesKnown = readObjectives(api, id)
                local entry = {
                    id = id, title = title, zone = zone, status = readStatus(api, id),
                    level = integer(info.level, 1, 255) or integer(info.difficultyLevel, 1, 255),
                    objectives = objectives, objectivesKnown = objectivesKnown,
                    search = fold(title .. " " .. (zone or "") .. " " .. id),
                }
                byID[id] = entry
                entries[#entries + 1] = entry
            end
        end
    end
    return { entries = entries, byID = byID, partial = partial }, "live"
end

function Journal.Progress()
    local level = integer(call(UnitLevel, "player"), 1, 255)
    if not level then return nil end
    local cap = integer(call(GetMaxPlayerLevel), 1, 255)
    if cap and level >= cap then return { level = level, capped = true } end
    local maximum = integer(call(UnitXPMax, "player"), 1, MAX_ID)
    local current = maximum and integer(call(UnitXP, "player"), 0, maximum)
    return { level = level, current = current, maximum = maximum }
end

function Journal.Terms(query)
    query = Compat.SafeValue(query)
    local terms = {}
    if type(query) == "string" then
        for term in fold(query:sub(1, 120)):gmatch("%S+") do
            terms[#terms + 1] = term
            if #terms == 8 then break end
        end
    end
    return terms
end

function Journal.Matches(entry, terms)
    local search = entry.search or fold(entry.title .. " " .. entry.id)
    for _, term in ipairs(terms) do
        if not search:find(term, 1, true) then return false end
    end
    return true
end
