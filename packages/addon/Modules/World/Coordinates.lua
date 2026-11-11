-- Coordinate esposte dal client. Le posizioni interne sono rapporti da 0 a 1.
local _, ns = ...
local Badb, Compat = ns.Badb, ns.Badb.Compat
local C = {}
ns.WorldCoordinates = C

local MAX_ID = 2147483647
local mapNames = {}

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, first, second = pcall(fn, ...)
    if ok then return Compat.SafeValue(first), Compat.SafeValue(second) end
end

local function number(value, minimum, maximum)
    value = Compat.SafeValue(value)
    if type(value) == "number" and value >= minimum and value <= maximum then return value end
end

function C.ID(value)
    local id = number(value, 1, MAX_ID)
    if id and id == math.floor(id) then return id end
end

function C.Text(value, limit)
    value = Compat.SafeValue(value)
    if type(value) ~= "string" or #value > limit then return nil end
    local clean = value:gsub("[%c|]", " "):match("^%s*(.-)%s*$")
    if clean ~= "" then return clean end
end

function C.Point(map, x, y)
    map, x, y = C.ID(map), number(x, 0, 1), number(y, 0, 1)
    if map and x and y then return { map = map, x = x, y = y } end
end

function C.Percent(value)
    value = Compat.SafeValue(value)
    if type(value) == "string" then
        local text = value:match("^%s*(%d+[.,]?%d*)%s*$")
        if not text then return nil end
        value = tonumber((text:gsub(",", ".")))
    end
    local percent = number(value, 0, 100)
    if percent then return percent / 100 end
end

local function xy(position)
    position = Compat.SafeValue(position)
    if type(position) ~= "table" then return nil end
    local getter = Compat.SafeValue(position.GetXY)
    if type(getter) == "function" then return call(getter, position) end
    return Compat.SafeValue(position.x), Compat.SafeValue(position.y)
end

function C.PlayerMap()
    return C.ID(call(C_Map and C_Map.GetBestMapForUnit, "player"))
end

function C.Player(map)
    map = C.ID(map) or C.PlayerMap()
    if not map then return nil end
    local x, y = xy(call(C_Map and C_Map.GetPlayerMapPosition, map, "player"))
    if x == 0 and y == 0 then return nil end
    return C.Point(map, x, y)
end

function C.MapName(map)
    if not mapNames[map] then
        local info = call(C_Map and C_Map.GetMapInfo, map)
        if type(info) == "table" then mapNames[map] = C.Text(info.name, 120) end
    end
    return mapNames[map] or Badb.L["Mappa %d"]:format(map)
end

function C.ViewedMap()
    local frame = WorldMapFrame
    if not frame or call(frame.IsShown, frame) ~= true then return nil end
    return C.ID(call(frame.GetMapID, frame))
end

function C.Same(a, b)
    if not a or not b then return a == b end
    return a.map == b.map and math.abs(a.x - b.x) < 0.00001 and math.abs(a.y - b.y) < 0.00001
end

function C.Distance(player, target)
    if not (player and target and player.map == target.map) then return nil end
    local width, height = call(C_Map and C_Map.GetMapWorldSize, player.map)
    width, height = number(width, 1, 1000000), number(height, 1, 1000000)
    if not (width and height) then return nil end
    local dx, dy = (target.x - player.x) * width, (target.y - player.y) * height
    return math.floor(math.sqrt(dx * dx + dy * dy) + 0.5)
end

function C.ReadNative()
    if not (C_Map and type(C_Map.GetUserWaypoint) == "function") then return nil, false end
    local ok, raw = pcall(C_Map.GetUserWaypoint)
    if not ok or Compat.IsSecret(raw) then return nil, false end
    if raw == nil then return nil, true end
    if type(raw) ~= "table" then return nil, false end
    local x, y = xy(raw.position)
    local point = C.Point(raw.uiMapID, x, y)
    return point, point ~= nil
end

function C.CanWrite(map)
    local api = C_Map
    if not (api and type(api.GetUserWaypoint) == "function" and type(api.SetUserWaypoint) == "function"
        and type(api.ClearUserWaypoint) == "function" and type(UiMapPoint) == "table"
        and type(UiMapPoint.CreateFromCoordinates) == "function") then return false end
    return type(api.CanSetUserWaypointOnMap) ~= "function" or call(api.CanSetUserWaypointOnMap, map) == true
end

function C.WriteNative(point)
    if not point then
        return C_Map and type(C_Map.ClearUserWaypoint) == "function" and pcall(C_Map.ClearUserWaypoint)
    end
    if not C.CanWrite(point.map) then return false end
    local raw = call(UiMapPoint.CreateFromCoordinates, point.map, point.x, point.y)
    return raw ~= nil and pcall(C_Map.SetUserWaypoint, raw)
end
