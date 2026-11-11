local _, ns = ...
local Badb, S = ns.Badb, ns.EncounterSource
local L, IsSecret = Badb.L, Badb.Compat.IsSecret
local Journal = {}
ns.EncounterJournal = Journal

local STORE_VERSION, MAX_VISITS, MAX_AGE = 1, 120, 90 * 86400
local RESUME_WINDOW = 12 * 3600
local KINDS = { party = L["Spedizione"], raid = L["Incursione"], pvp = L["Campo di battaglia"] }

local function now()
    local ok, value = S.Call(GetServerTime)
    if ok and S.Number(value) then return value end
    ok, value = S.Call(time or (os and os.time))
    return ok and S.Number(value) or nil
end

local function clean(entry, stamp)
    if IsSecret(entry) or type(entry) ~= "table" then return end
    local name, char, kind = S.Text(entry.name), S.Text(entry.character), S.Text(entry.kind)
    local entered, map = S.Number(entry.entered), S.Number(entry.map)
    if not name or not char or not KINDS[kind] or not entered or not map then return end
    if stamp and (entered < stamp - MAX_AGE or entered > stamp + 86400) then return end
    local attempts, kills = S.Number(entry.attempts, 500) or 0, S.Number(entry.kills, 500) or 0
    return {
        name = name, character = char, kind = kind, map = map,
        difficulty = S.Number(entry.difficulty) or 0, entered = entered,
        attempts = attempts, kills = math.min(kills, attempts), lastBoss = S.Text(entry.lastBoss),
        active = not IsSecret(entry.active) and entry.active == true,
    }
end

function Journal:Initialize()
    local store = Badb.DB:GetStore("encounters")
    if not store then return end
    local visits, old = {}, store.visits
    if store.version == STORE_VERSION and type(old) == "table" then
        local stamp, active = now(), {}
        for i = math.max(1, #old - MAX_VISITS + 1), #old do
            local visit = clean(old[i], stamp)
            if visit then visits[#visits + 1] = visit end
        end
        for i = #visits, 1, -1 do
            local visit = visits[i]
            if visit.active and active[visit.character] then visit.active = false end
            if visit.active then active[visit.character] = true end
        end
    end
    store.version, store.visits = STORE_VERSION, visits
    self.visits = visits
end

function Journal:Observe()
    local visits, char = self.visits, S.Text(Badb.DB.char)
    if not visits or not char then return end
    local ok, name, kind, difficulty, _, _, _, _, map = S.Call(GetInstanceInfo)
    if not ok or IsSecret(kind) or type(kind) ~= "string" then return end
    local current
    for i = #visits, 1, -1 do
        local visit = visits[i]
        if visit.active and visit.character == char then current = visit; break end
    end
    if not KINDS[kind] then
        if current then current.active = false end
        return
    end
    local stamp = now()
    name, map, difficulty = S.Text(name), S.Number(map), S.Number(difficulty) or 0
    if not name or not map or not stamp then return end
    if current and current.map == map and current.kind == kind and current.difficulty == difficulty
        and stamp - current.entered < RESUME_WINDOW then
        return current
    end
    if current then current.active = false end
    for i = #visits, 1, -1 do
        if visits[i].entered < stamp - MAX_AGE then table.remove(visits, i) end
    end
    if #visits >= MAX_VISITS then table.remove(visits, 1) end
    local visit = {
        name = name, character = char, kind = kind, map = map, difficulty = difficulty,
        entered = stamp, attempts = 0, kills = 0, active = true,
    }
    visits[#visits + 1] = visit
    return visit
end

function Journal:EncounterEnd(boss, success)
    if IsSecret(success) or (success ~= 0 and success ~= 1) then return end
    local visit = self:Observe()
    if not visit or visit.kind == "pvp" or visit.attempts >= 500 then return end
    visit.attempts = visit.attempts + 1
    if success == 1 then visit.kills = visit.kills + 1 end
    visit.lastBoss = S.Text(boss)
end

function Journal:Rows()
    local rows = {}
    local visits = self.visits or {}
    local stamp = now()
    for i = #visits, 1, -1 do
        local visit = visits[i]
        if not stamp or visit.entered >= stamp - MAX_AGE then
            local detail = KINDS[visit.kind] .. " · " .. (S.Plain(visit.character) or "")
            if visit.lastBoss then detail = detail .. " · " .. (S.Plain(visit.lastBoss) or "") end
            local ok, visited = S.Call(date, "%d/%m %H:%M", visit.entered)
            local dateText = ok and S.Plain(visited) or "—"
            if visit.attempts > 0 then
                dateText = dateText .. " · " .. L["%d/%d vittorie"]:format(visit.kills, visit.attempts)
            end
            rows[#rows + 1] = { name = visit.name, detail = detail, value = dateText }
        end
    end
    return rows
end
