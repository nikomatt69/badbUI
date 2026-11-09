-- BadbUI - Logger con livelli e buffer circolare consultabile con /badb log
local _, ns = ...
local Badb = ns.Badb

local Logger = { level = 2, buffer = {}, max = 200 }
Badb.Logger = Logger

local LEVELS = { "DEBUG", "INFO", "WARN", "ERROR" }
local COLORS = { "ff888888", "ff3fa7ff", "ffffcc00", "ffff4040" }

local function push(lvl, fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end
    local line = string.format("[%s] %s: %s", date("%H:%M:%S"), LEVELS[lvl], msg)
    local buf = Logger.buffer
    buf[#buf + 1] = line
    if #buf > Logger.max then table.remove(buf, 1) end
    if lvl >= Logger.level then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|c%sBadbUI|r %s", COLORS[lvl], msg))
    end
end

function Logger:Debug(...) push(1, ...) end
function Logger:Info(...)  push(2, ...) end
function Logger:Warn(...)  push(3, ...) end
function Logger:Error(...) push(4, ...) end

function Badb:Print(...) Logger:Info(...) end
