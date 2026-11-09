-- BadbUI - Event bus
-- Unifica eventi di gioco (RegisterEvent) e messaggi interni (Fire) in un'unica API.
-- Gli errori nei listener sono isolati: un modulo rotto non blocca gli altri.
local _, ns = ...
local Badb = ns.Badb
local Logger = Badb.Logger

local Events = { listeners = {} }
Badb.Events = Events

local frame = CreateFrame("Frame")
Events.frame = frame

local function dispatch(event, ...)
    local list = Events.listeners[event]
    if not list then return end
    for owner, fn in pairs(list) do
        local ok, err = pcall(fn, event, ...)
        if not ok then
            Logger:Error("Listener %s su %s: %s", tostring(owner.name or owner), event, err)
        end
    end
end

frame:SetScript("OnEvent", function(_, event, ...) dispatch(event, ...) end)

-- owner: qualunque tabella (tipicamente un modulo); permette UnregisterAll pulito.
function Events:On(owner, event, fn)
    local list = self.listeners[event]
    if not list then
        list = {}
        self.listeners[event] = list
        -- I messaggi interni usano il prefisso "BADB_" e non vanno registrati sul frame.
        if not event:find("^BADB_") then pcall(frame.RegisterEvent, frame, event) end
    end
    list[owner] = fn
end

function Events:Off(owner, event)
    local list = self.listeners[event]
    if not list then return end
    list[owner] = nil
    if next(list) == nil then
        self.listeners[event] = nil
        if not event:find("^BADB_") then frame:UnregisterEvent(event) end
    end
end

function Events:OffAll(owner)
    for event in pairs(self.listeners) do self:Off(owner, event) end
end

function Events:Fire(message, ...)
    dispatch(message, ...)
end

-- Coda per azioni protette: in combattimento non si possono muovere frame protetti.
local queue = {}
function Events:RunOutOfCombat(key, fn)
    if not InCombatLockdown() then return fn() end
    queue[key] = fn
end

Events:On(Events, "PLAYER_REGEN_ENABLED", function()
    for key, fn in pairs(queue) do
        queue[key] = nil
        local ok, err = pcall(fn)
        if not ok then Logger:Error("Azione differita %s: %s", key, err) end
    end
end)
