local _, ns = ...
local L = ns.Badb.L
local Badb, C = ns.Badb, ns.Badb.ChatbotContext
local M = Badb.Modules:New("Chatbot", { title = "Chatbot", category = L["Contenuti"], defaults = { enabled = true } })
Badb.Chatbot = M
local function store()
    if type(BadbUI_ChatbotExport) ~= "table" or BadbUI_ChatbotExport.version ~= 1 then BadbUI_ChatbotExport = { version = 1 } end
    local s = BadbUI_ChatbotExport
    s.requests = type(s.requests) == "table" and s.requests or {}
    s.characters = type(s.characters) == "table" and s.characters or {}
    return s
end
function M:State()
    local s, key = store(), C.Identity()
    if type(s.characters[key]) ~= "table" then s.characters[key] = {} end
    local state = s.characters[key]
    state.history = type(state.history) == "table" and state.history or {}
    state.selected = type(state.selected) == "table" and state.selected or {}
    state.generation = type(state.generation) == "number" and math.max(1, math.floor(state.generation)) or 1
    if state.includeBags == nil then state.includeBags = true end
    return state
end
function M:Queue(kind, payload)
    if not self.enabled then return false, "Enable the Chatbot module." end
    if InCombatLockdown and InCombatLockdown() then return false, "Send outside combat." end
    if kind == "configure" and (type(payload.json) ~= "string" or #payload.json > 100000) then return false, "Configuration JSON must be under 100 KB." end
    if kind ~= "ask" and kind ~= "catalog" and kind ~= "configure" and (type(payload.provider) ~= "string" or payload.provider == "") then return false, "Enter a provider ID." end
    local s, state = store(), self:State()
    if #s.requests >= 20 then return false, "Queue full: wait for the AI runtime, then reload the UI." end
    s.sequence = (tonumber(s.sequence) or 0) + 1
    local at = C.Call(GetServerTime) or C.Call(time) or 0
    local request = { id = C.Identity() .. ":" .. tostring(at) .. ":" .. s.sequence, character = C.Identity(), at = at,
        kind = kind, payload = payload or {}, generation = state.generation }
    s.requests[#s.requests + 1] = request
    return true, request
end
function M:Ask(text)
    text = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
    if text == "" or #text > 4000 then return false, "Enter a question (up to 4000 bytes)." end
    local state = self:State()
    if type(state.provider) ~= "string" or state.provider == "" or type(state.model) ~= "string" or state.model == "" then return false, "Choose a provider and model first." end
    local context = C.Capture(state.selected, state.includeBags)
    local ok, request = self:Queue("ask", { text = text, context = context, provider = state.provider, model = state.model, variant = state.variant })
    if not ok then return false, request end
    state.history[#state.history + 1] = { id = request.id, question = text, status = "pending", at = request.at }
    while #state.history > 40 do table.remove(state.history, 1) end
    state.selected = {}
    return true
end
function M:Import()
    local s, data = store(), BadbUI_ChatbotSync
    self.bundle = type(data) == "table" and data or nil
    if not self.bundle then return end
    local receipts, pendingIDs, recovering = {}, {}, {}
    for _, request in ipairs(s.requests) do pendingIDs[request.id] = true end
    for _, r in ipairs(data.receipts or {}) do
        receipts[r.id] = r
        local state = s.characters[r.character]
        -- Keep replies readable even on Forever builds that fail to restore
        -- SavedVariables. The response bundle contains the original question.
        if r.kind == "ask" and type(r.question) == "string" then
            if type(state) ~= "table" then
                state = { history = {}, selected = {}, includeBags = true, generation = r.generation }
                s.characters[r.character] = state
                recovering[r.character] = true
            end
            if type(state.generation) ~= "number" or state.generation < r.generation then
                state.generation, state.history = r.generation, {}
                recovering[r.character] = true
            end
            if type(state.history) ~= "table" then state.history = {} end
            if state.generation == r.generation then
                local found = false
                for _, h in ipairs(state.history) do if h.id == r.id then found = true end end
                if not found and (recovering[r.character] or pendingIDs[r.id]) then state.history[#state.history + 1] = { id = r.id, question = r.question } end
                while #state.history > 40 do table.remove(state.history, 1) end
            end
        end
        if state and state.generation == r.generation then
            for _, h in ipairs(state.history) do
                if h.id == r.id then h.answer, h.status, h.sources = r.text, r.status, r.sources end
            end
        end
    end
    local pending = {}
    for _, request in ipairs(s.requests) do
        if not receipts[request.id] then pending[#pending + 1] = request end
        -- Acknowledged credentials are removed from memory and the next WoW save.
    end
    s.requests = pending
end
function M:NewConversation()
    local state = self:State()
    for _, r in ipairs(store().requests) do if r.character == C.Identity() then return false, "Wait for queued requests first." end end
    state.generation = state.generation + 1
    state.history, state.selected = {}, {}
    return true
end
function M:OnInitialize() store(); self:Import() end
function M:OnEnable() end
function M:OnDisable() if self.frame then self.frame:Hide() end end
M.commands = { chat = { help = "Open the AI chatbot with character context", fn = function(args)
    if args and args:match("%S") then
        local ok, err = M:Ask(args)
        Badb.Logger:Info("%s", ok and "Question queued: /reload to send, wait for Reply ready, then /reload again." or err)
    end
    Badb.ConfigUI:OpenPage("Chatbot")
end } }
