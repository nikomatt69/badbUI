local _, ns = ...
local Badb = ns.Badb
local L, IsSecret = Badb.L, Badb.Compat.IsSecret
local S = {}
ns.EncounterSource = S

function S.Call(fn, ...)
    if type(fn) == "function" then return pcall(fn, ...) end
    return false
end

function S.Number(value, max)
    if not IsSecret(value) and type(value) == "number" and value >= 0 and value <= (max or 9007199254740991) then
        return value
    end
end

function S.Text(value)
    if not IsSecret(value) and type(value) == "string" and value ~= "" and #value <= 200 then
        return (value:gsub("[%c]", " "))
    end
end

function S.Plain(value)
    local text = S.Text(value)
    return text and (text:gsub("|", "||"))
end

function S.Seconds(value)
    if not value then return "—" end
    local seconds = math.ceil(value)
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function isTable(value) return not IsSecret(value) and type(value) == "table" end

local MAX_TIMERS = 24

function S.Timeline()
    local api = C_EncounterTimeline
    if not api or type(api.GetEventInfo) ~= "function" or type(api.GetEventTimeRemaining) ~= "function" then
        return {}, "unavailable"
    end
    local checked, available = S.Call(api.IsFeatureAvailable)
    if checked and not IsSecret(available) and available == false then return {}, "unavailable" end
    checked, available = S.Call(api.IsFeatureEnabled)
    if checked and not IsSecret(available) and available == false then return {}, "disabled" end

    local sorted, ids = S.Call(api.GetSortedEventList, MAX_TIMERS, nil, true, true)
    sorted = sorted and isTable(ids)
    if not sorted then
        local ok
        ok, ids = S.Call(api.GetEventList)
        if not ok or not isTable(ids) then return {}, "unavailable" end
    end

    local events, limited = {}, false
    local states = Enum and Enum.EncounterTimelineEventState
    local sources = Enum and Enum.EncounterTimelineEventSource
    for i = 1, math.min(#ids, sorted and MAX_TIMERS or 96) do
        local id = ids[i]
        if S.Number(id) or S.Text(id) then
            local stateOK, state = S.Call(api.GetEventState, id)
            state = stateOK and S.Number(state)
            local terminal = states and state and (state == states.Finished or state == states.Canceled)
            if not terminal then
                local ok, info = S.Call(api.GetEventInfo, id)
                if ok and isTable(info) then
                    local origin = S.Number(info.source)
                    local isExternal = sources and origin and (origin == sources.Script or origin == sources.EditMode)
                    if not isExternal then
                        local gotTime, remaining = S.Call(api.GetEventTimeRemaining, id)
                        local gotBlocked, blocked = S.Call(api.IsEventBlocked, id)
                        local value = gotTime and S.Number(remaining, 86400) or nil
                        if gotTime and IsSecret(remaining) then limited = true end
                        local duration = S.Number(info.duration, 86400)
                        local paused = states and state and state == states.Paused
                        local detail
                        if paused then detail = L["In pausa"]
                        elseif gotBlocked and not IsSecret(blocked) and blocked == true then detail = L["Condizione non soddisfatta"]
                        elseif not IsSecret(info.isApproximate) and info.isApproximate == true then detail = L["Tempo indicativo"] end
                        events[#events + 1] = {
                            name = info.spellName, detail = detail,
                            value = S.Seconds(value),
                            progress = value and duration and duration > 0 and math.min(1, value / duration) or nil,
                            color = not paused and value and value <= 5 and "warning" or nil,
                            remaining = value, order = i,
                        }
                    end
                elseif ok and IsSecret(info) then
                    limited = true
                end
            end
        elseif IsSecret(id) then
            limited = true
        end
    end
    if not sorted then
        table.sort(events, function(a, b)
            if a.remaining == b.remaining then return a.order < b.order end
            return (a.remaining or math.huge) < (b.remaining or math.huge)
        end)
        for i = #events, MAX_TIMERS + 1, -1 do events[i] = nil end
    end
    return events, limited and "restricted" or nil
end

local function millis(fn, index)
    local ok, value = S.Call(fn, index)
    local valid = ok and S.Number(value, 2147483647)
    return valid and valid / 1000
end

function S.Battlegrounds()
    if type(GetBattlefieldStatus) ~= "function" then return {}, "unavailable" end
    local ok, maxQueues = S.Call(GetMaxBattlefieldID)
    maxQueues = math.min((ok and S.Number(maxQueues)) or S.Number(MAX_BATTLEFIELD_QUEUES) or 3, 8)
    local rows, limited = {}, false
    for index = 1, maxQueues do
        local checked, status, map = S.Call(GetBattlefieldStatus, index)
        if checked and not IsSecret(status) then
            local detail, value, color
            if status == "queued" then
                local waited = millis(GetBattlefieldTimeWaited, index)
                local estimate = millis(GetBattlefieldEstimatedWaitTime, index)
                detail = estimate and estimate > 0 and L["Attesa media %s"]:format(S.Seconds(estimate)) or L["In coda"]
                value = S.Seconds(waited)
            elseif status == "confirm" then
                local expires, seconds = S.Call(GetBattlefieldPortExpiration, index)
                detail, color = L["Invito disponibile"], "warning"
                value = S.Seconds(expires and S.Number(seconds, 86400) or nil)
            elseif status == "active" then
                detail, color = L["Partita in corso"], "success"
                value = S.Seconds(millis(GetBattlefieldInstanceRunTime))
            end
            if detail then
                rows[#rows + 1] = { name = map, detail = detail, value = value, color = color }
            end
        elseif checked and IsSecret(status) then
            limited = true
        end
    end
    return rows, limited and "restricted" or nil
end

function S.Lockouts()
    if type(GetNumSavedInstances) ~= "function" or type(GetSavedInstanceInfo) ~= "function" then
        return {}, "unavailable"
    end
    local ok, count = S.Call(GetNumSavedInstances)
    local rows = {}
    for index = 1, ok and math.min(S.Number(count) or 0, 80) or 0 do
        local read, name, _, reset, _, locked, extended, _, _, _, difficulty, total, done = S.Call(GetSavedInstanceInfo, index)
        if read and not IsSecret(locked) and locked == true then
            reset, total, done = S.Number(reset, 2678400), S.Number(total, 100), S.Number(done, 100)
            local detail = S.Plain(difficulty) or L["Salvataggio attivo"]
            if total and total > 0 and done then detail = ("%s · %d/%d"):format(detail, done, total) end
            if not IsSecret(extended) and extended == true then detail = detail .. " · " .. L["Esteso"] end
            local value = S.Seconds(reset)
            if reset and reset >= 86400 then
                value = L["%d g %d h"]:format(math.floor(reset / 86400), math.floor(reset % 86400 / 3600))
            end
            rows[#rows + 1] = { name = name, detail = detail, value = value, reset = reset }
        end
    end
    table.sort(rows, function(a, b) return (a.reset or math.huge) < (b.reset or math.huge) end)
    return rows
end
