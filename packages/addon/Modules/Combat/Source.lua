-- Adattatore per le statistiche native. Nessun accesso al registro di combattimento.
local _, ns = ...
local Badb = ns.Badb
local L, IsSecret = Badb.L, Badb.Compat.IsSecret

local Source = {}
ns.CombatSource = Source

local METRICS = {
    { value = "DamageDone", text = L["Danni inflitti"] },
    { value = "Dps", text = L["Danni al secondo"] },
    { value = "HealingDone", text = L["Cure effettuate"] },
    { value = "Hps", text = L["Cure al secondo"] },
    { value = "DamageTaken", text = L["Danni subiti"] },
    { value = "Interrupts", text = L["Interruzioni"] },
    { value = "Dispels", text = L["Dissoluzioni"] },
    { value = "Absorbs", text = L["Assorbimenti"] },
}
local MAX_SOURCES, MAX_SPELLS, MAX_SESSIONS = 100, 120, 30

local function call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function readableTable(value)
    return not IsSecret(value) and type(value) == "table"
end

local function number(value)
    if not IsSecret(value) and type(value) == "number" and value >= 0 and value < math.huge then return value end
end

function Source.CleanText(value)
    if not IsSecret(value) and type(value) == "string" and value ~= "" and #value <= 256 then
        return (value:gsub("[%c]", " "):gsub("|", "||"))
    end
end

function Source.IsMeterAvailable()
    local api = C_DamageMeter
    if not api or type(api.GetCombatSessionFromType) ~= "function" then return false end
    if type(api.IsDamageMeterAvailable) ~= "function" then return true end
    local ok, available = call(api.IsDamageMeterAvailable)
    return ok and not IsSecret(available) and available == true
end

function Source.Metrics()
    local types = Enum and Enum.DamageMeterType
    local metrics = {}
    for _, entry in ipairs(METRICS) do
        if types and number(types[entry.value]) then metrics[#metrics + 1] = entry end
    end
    return metrics
end

function Source.Sessions()
    local sessions = {
        { value = "Current", text = L["Scontro attuale"] },
        { value = "Overall", text = L["Totale sessione"] },
    }
    local api = C_DamageMeter
    if not api or type(api.GetCombatSessionFromID) ~= "function" then return sessions end
    local ok, list = call(api.GetAvailableCombatSessions)
    if not ok or not readableTable(list) then return sessions end
    -- Il client restituisce gli scontri in ordine cronologico.
    for i = #list, math.max(1, #list - MAX_SESSIONS + 1), -1 do
        local entry = list[i]
        local id = readableTable(entry) and number(entry.sessionID)
        if id and id == math.floor(id) then
            sessions[#sessions + 1] = { value = id, text = Source.CleanText(entry.name) or L["Scontro %d"]:format(id) }
        end
    end
    return sessions
end

local function query(metric, session, source)
    if not Source.IsMeterAvailable() or type(metric) ~= "string" then return false, nil, "unavailable" end
    local meterType = Enum and Enum.DamageMeterType and number(Enum.DamageMeterType[metric])
    if not meterType then return false, nil, "unavailable" end
    local api = C_DamageMeter
    if type(session) == "string" and (session == "Current" or session == "Overall") then
        local sessionType = Enum and Enum.DamageMeterSessionType and number(Enum.DamageMeterSessionType[session])
        if not sessionType then return false, nil, "unavailable" end
        if source then
            return call(api.GetCombatSessionSourceFromType, sessionType, meterType, source.guid, source.creature)
        end
        return call(api.GetCombatSessionFromType, sessionType, meterType)
    end
    local id = number(session)
    if not id or id ~= math.floor(id) then return false, nil, "unavailable" end
    if source then
        return call(api.GetCombatSessionSourceFromID, id, meterType, source.guid, source.creature)
    end
    return call(api.GetCombatSessionFromID, id, meterType)
end

local function sourceIdentity(entry, session)
    local guid, creature = entry.sourceGUID, number(entry.sourceCreatureID)
    if IsSecret(guid) or type(guid) ~= "string" or #guid == 0 or #guid > 128 then guid = nil end
    if creature and (creature <= 0 or creature ~= math.floor(creature)) then creature = nil end
    if not guid and not creature then return end
    local api = C_DamageMeter
    local fn = type(session) == "number" and api.GetCombatSessionSourceFromID or nil
    if type(session) == "string" then fn = api.GetCombatSessionSourceFromType end
    if type(fn) == "function" then return { guid = guid, creature = creature } end
end

local function spellName(id)
    if not id or id <= 0 or id ~= math.floor(id) then return end
    local ok, name = call(C_Spell and C_Spell.GetSpellName or GetSpellInfo, id)
    if ok and not IsSecret(name) and type(name) == "string" and name ~= "" then return name end
    return L["Magia %d"]:format(id)
end

local function readMeter(metric, session, source)
    local result = { rows = {}, state = "empty" }
    local ok, data, unavailable = query(metric, session, source)
    if not ok then
        result.state = unavailable or "unreadable"
        return result
    end
    if not readableTable(data) then
        if IsSecret(data) then result.state = "restricted"
        elseif type(session) == "number" then result.state = "unreadable" end
        return result
    end
    local entries, maxEntries
    if source then entries, maxEntries = data.combatSpells, MAX_SPELLS
    else entries, maxEntries = data.combatSources, MAX_SOURCES end
    if not readableTable(entries) then
        if IsSecret(entries) then result.state = "restricted" end
        return result
    end

    local perSecond = metric == "Dps" or metric == "Hps"
    local maxPublic = 0
    result.duration = number(data.durationSeconds)
    result.total = number(data.totalAmount)
    result.limited = IsSecret(data.totalAmount)
    for i = 1, math.min(#entries, maxEntries) do
        local entry = entries[i]
        if readableTable(entry) then
            local value = entry.totalAmount
            if perSecond then value = entry.amountPerSecond end
            local name, identity, player
            if source then
                name = spellName(number(entry.spellID))
            else
                name, identity = entry.name, sourceIdentity(entry, session)
                player = not IsSecret(entry.isLocalPlayer) and entry.isLocalPlayer == true
            end
            local public = number(value)
            if public and public > maxPublic then maxPublic = public end
            if public or IsSecret(value) then
                result.rows[#result.rows + 1] = {
                    name = name, value = value, public = public, identity = identity, player = player,
                }
            end
            if IsSecret(name) or IsSecret(value) or IsSecret(entry.spellID) then result.limited = true end
        elseif IsSecret(entry) then
            result.limited = true
        end
    end
    if #result.rows > 0 then
        result.state = "ready"
        -- L'ordine proviene dal client. Le barre confrontano solo valori pubblici.
        if not result.limited and maxPublic > 0 then
            for _, row in ipairs(result.rows) do row.progress = row.public / maxPublic end
        end
    elseif result.limited then
        result.state = "restricted"
    end
    return result
end

function Source.Meter(metric, session)
    return readMeter(metric, session)
end

function Source.Breakdown(metric, session, source)
    return readMeter(metric, session, source)
end

local function addThreat(result, unit)
    local ok, _, status, percent, _, raw = call(UnitDetailedThreatSituation, unit, "target")
    if not ok then status, percent, raw = nil, nil, nil end
    if IsSecret(status) or IsSecret(percent) or IsSecret(raw) then result.limited = true end
    status, percent, raw = number(status), number(percent), number(raw)
    if not status then
        local available, fallback = call(UnitThreatSituation, unit, "target")
        if available then
            if IsSecret(fallback) then result.limited = true end
            status = number(fallback)
        end
    end
    if not status and not percent and not raw then return end
    local named, name = call(UnitName, unit)
    if not named then name = nil end
    local isLocal = unit == "player"
    if not isLocal then
        local checked, same = call(UnitIsUnit, unit, "player")
        isLocal = checked and not IsSecret(same) and same == true
    end
    result.rows[#result.rows + 1] = {
        name = name, player = isLocal, status = status, value = percent, public = percent, raw = raw,
        progress = percent and math.min(percent / 100, 1),
        order = #result.rows + 1,
    }
end

function Source.Threat()
    local result = { rows = {}, state = "empty" }
    if type(UnitDetailedThreatSituation) ~= "function" and type(UnitThreatSituation) ~= "function" then
        result.state = "unavailable"
        return result
    end
    local checked, exists = call(UnitExists, "target")
    local attackChecked, attackable = call(UnitCanAttack, "player", "target")
    if IsSecret(exists) or IsSecret(attackable) then
        result.state = "restricted"
        return result
    end
    if (checked and exists == false) or (attackChecked and attackable == false) then
        result.state = "noTarget"
        return result
    end

    local inRaid, raid = call(IsInRaid)
    local counted, count
    if inRaid and not IsSecret(raid) and raid == true then
        counted, count = call(GetNumGroupMembers)
        for i = 1, counted and math.min(number(count) or 0, 40) or 0 do addThreat(result, "raid" .. i) end
    else
        addThreat(result, "player")
        counted, count = call(GetNumSubgroupMembers)
        for i = 1, counted and math.min(number(count) or 0, 4) or 0 do addThreat(result, "party" .. i) end
    end

    table.sort(result.rows, function(a, b)
        -- Percentuali scalate a distanza diversa non sono una misura uniforme.
        if (a.raw or -1) ~= (b.raw or -1) then return (a.raw or -1) > (b.raw or -1) end
        if (a.status or -1) ~= (b.status or -1) then return (a.status or -1) > (b.status or -1) end
        return a.order < b.order
    end)
    if #result.rows > 0 then result.state = "ready"
    elseif result.limited then result.state = "restricted" end
    return result
end
