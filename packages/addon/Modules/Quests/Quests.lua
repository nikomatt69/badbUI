-- BadbUI - Diario di missioni, preferiti e cronologia locale delle consegne.
local _, ns = ...
local Badb, Journal = ns.Badb, ns.QuestJournal
local L, Compat = Badb.L, Badb.Compat

local LIMIT_PINS = 25
local LIMIT_HISTORY = 50
local LIMIT_CHARACTERS = 24
local MAX_TIME = 4102444800
local SCHEMA = 1
local GUIDE = "badb-quests:journal"
local statuses = { all = true, pinned = true, ready = true, history = true }

local M = Badb.Modules:New("Quests", {
    title = L["Diario missioni"],
    category = L["Gioco"],
    description = L["Cerca nel registro, metti in evidenza le missioni e rivedi le consegne recenti."],
    defaults = { enabled = true, hud = false },
    page = { title = L["Diario missioni"], category = L["Gioco"], order = 60,
        keywords = { L["Missioni"], L["Obiettivi"], "leveling", "Questie", "Polestar" } },
    replaces = {
        { addon = "Questie", coverage = "partial",
          note = L["Registro ricercabile, obiettivi e monitor. Restano esclusi il catalogo delle missioni e i segnalini aggiuntivi."] },
        { addon = "Polestar", coverage = "partial",
          note = L["Monitor delle missioni, esperienza e cronologia consegne. Restano escluse le rotte guidate e la navigazione."] },
    },
})
Badb.Quests = M

local function now()
    return Journal.Integer(Journal.Call(GetServerTime), 1, MAX_TIME)
        or Journal.Integer(Journal.Call(time), 1, MAX_TIME) or 0
end

local function cleanCharacter(value)
    local clean = { pins = {}, history = {}, touched = 0 }
    if type(value) ~= "table" then return clean end
    clean.touched = Journal.Integer(value.touched, 0, MAX_TIME) or 0
    if type(value.pins) == "table" then
        for i = 1, LIMIT_PINS do
            local id = Journal.ID(value.pins[i])
            if id then clean.pins[id] = true end
        end
    end
    if type(value.history) == "table" then
        for i = 1, LIMIT_HISTORY do
            local entry = value.history[i]
            if type(entry) == "table" then
                local id = Journal.ID(entry.id)
                local title = Journal.Text(entry.title, 240)
                if id and title then
                    clean.history[#clean.history + 1] = {
                        id = id, title = title, xp = Journal.Integer(entry.xp, 0, 2147483647),
                        time = Journal.Integer(entry.time, 1, MAX_TIME),
                    }
                end
            end
        end
    end
    return clean
end

local function sortedPins(pins)
    local ids = {}
    for id in pairs(pins) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

function M:OnInitialize()
    local store = Badb.DB:GetStore("quests")
    local key = Badb.DB.char
    local saved = store and store.version == SCHEMA and type(store.characters) == "table" and store.characters or {}
    self.saved = nil
    self.state = cleanCharacter(saved[key])
    if not store or type(key) ~= "string" or #key > 240 then return end
    if type(store.version) == "number" and store.version > SCHEMA then return end
    local ranked = {}
    for owner, value in pairs(saved) do
        if owner ~= key and type(owner) == "string" and #owner <= 240 and type(value) == "table" then
            local touched = Journal.Integer(value.touched, 0, MAX_TIME) or 0
            ranked[#ranked + 1] = { owner = owner, touched = touched }
        end
    end
    table.sort(ranked, function(a, b)
        if a.touched ~= b.touched then return a.touched > b.touched end
        return a.owner < b.owner
    end)
    self.saved = {}
    store.version, store.characters = SCHEMA, { [key] = self.saved }
    for index = 1, math.min(#ranked, LIMIT_CHARACTERS - 1) do
        local owner = ranked[index].owner
        local clean = cleanCharacter(saved[owner])
        store.characters[owner] = { pins = sortedPins(clean.pins), history = clean.history, touched = clean.touched }
    end
    self:Save()
end

function M:Save()
    if not self.saved then return end
    self.saved.pins = sortedPins(self.state.pins)
    self.saved.history = self.state.history
    self.saved.touched = now()
end

function M:List(query, filter)
    if not self.running then return {} end
    filter = Compat.SafeValue(filter)
    filter = statuses[filter] and filter or "all"
    local entries = filter == "history" and self.state.history or self.log and self.log.entries or {}
    local terms, result = Journal.Terms(query), {}
    for _, entry in ipairs(entries) do
        if (filter == "all" or filter == "history" or (filter == "ready" and entry.status == "ready")
            or (filter == "pinned" and self.state.pins[entry.id])) and Journal.Matches(entry, terms) then
            result[#result + 1] = entry
        end
    end
    return result
end

function M:IsPinned(id)
    id = Journal.ID(id)
    return self.state ~= nil and self.state.pins[id] == true
end

function M:SetPinned(id, pinned)
    id, pinned = Journal.ID(id), Compat.SafeValue(pinned)
    if not self.running or not id or type(pinned) ~= "boolean" then return false end
    local value = pinned
    if value == self:IsPinned(id) then return true end
    if value then
        if self.logStatus ~= "live" or not self.log or not self.log.byID[id] then return false end
        local count = 0
        for _ in pairs(self.state.pins) do count = count + 1 end
        if count >= LIMIT_PINS then return false, L["Hai raggiunto il limite di 25 missioni in evidenza."] end
        self.state.pins[id] = true
    else
        self.state.pins[id] = nil
    end
    self:Save()
    self:UpdateViews()
    return true
end

function M:RecordTurnIn(id, xp)
    id = Journal.ID(id)
    if not id then return end
    local entry = self.log and self.log.byID[id]
    local title = entry and entry.title or Journal.Text(Journal.Call(C_QuestLog and C_QuestLog.GetTitleForQuestID, id), 240)
    title = title or L["Missione %d"]:format(id)
    local stamp = now()
    local history = self.state.history
    table.insert(history, 1, { id = id, title = title, xp = Journal.Integer(xp, 0, 2147483647),
        time = stamp > 0 and stamp or nil })
    history[LIMIT_HISTORY + 1] = nil
    self.state.pins[id] = nil
    self:Save()
    self:Queue(true)
end

function M:UpdateViews()
    if self.RefreshWindow then self:RefreshWindow() end
    if self.RefreshHUD then self:RefreshHUD() end
end

function M:Refresh(readLog)
    if readLog then
        local snapshot, status = Journal.Read()
        self.logStatus = status
        if snapshot then
            self.log = snapshot
            local api = C_QuestLog
            local changed = false
            if #snapshot.entries > 0 and type(api.IsOnQuest) == "function" then
                for id in pairs(self.state.pins) do
                    if not snapshot.byID[id] and Journal.Call(api.IsOnQuest, id) == false then
                        self.state.pins[id] = nil
                        changed = true
                    end
                end
            end
            if changed then self:Save() end
        end
    end
    self.progress = Journal.Progress()
    self:UpdateViews()
end

function M:Queue(readLog)
    self.readLog = self.readLog or readLog
    if self.queued then return end
    self.queued = true
    local generation = self.generation
    Compat.After(0.15, function()
        if not self.running or self.generation ~= generation then return end
        self.queued = false
        local wanted = self.readLog
        self.readLog = false
        self:Refresh(wanted)
    end)
end

function M:OnEnable()
    self.running, self.readLog, self.queued = true, false, false
    self.generation = (self.generation or 0) + 1
    local function changed() self:Queue(true) end
    self:On("PLAYER_ENTERING_WORLD", changed)
    self:On("QUEST_LOG_UPDATE", changed)
    self:On("UNIT_QUEST_LOG_CHANGED", function(_, unit)
        if Compat.SafeValue(unit) == "player" then changed() end
    end)
    self:On("QUEST_ACCEPTED", changed)
    self:On("PLAYER_REGEN_ENABLED", changed)
    self:On("QUEST_REMOVED", function(_, id)
        id = Journal.ID(id)
        if id and self.state.pins[id] then
            self.state.pins[id] = nil
            self:Save()
        end
        changed()
    end)
    self:On("QUEST_TURNED_IN", function(_, id, xp) self:RecordTurnIn(id, xp) end)
    self:On("PLAYER_XP_UPDATE", function(_, unit)
        if Compat.SafeValue(unit) == "player" then self:Queue(false) end
    end)
    self:On("PLAYER_LEVEL_UP", function() self:Queue(true) end)
    self:On("BADB_OPTION_CHANGED", function(_, module, path)
        if module == self.name and path == "hud" then self:UpdateViews() end
    end)
    changed()
end

function M:OnDisable()
    self.running, self.hudWanted = false, false
    self.log, self.progress = nil, nil
    if self.window then self.window:Hide() end
    if self.hud then self.hud:Hide() end
end

function M:OnProfileChanged()
    self:UpdateViews()
end

local function open(query)
    if M.running then
        M:Open(query)
    else
        Badb.Logger:Warn(L["Attiva Diario missioni in BadbUI per aprirlo."])
    end
end

M.commands = {
    quests = { help = L["quests [testo] - cerca nel diario missioni"], fn = function(args) open(args) end },
}

M.options = {
    { type = "label", text = function() return Journal.Available() and M.description or L["Registro missioni non disponibile su questo client."] end },
    { type = "execute", label = L["Apri diario missioni"], disabled = function() return not M.running end, func = function() open() end },
    { type = "toggle", path = "hud", label = L["Mostra il monitor delle missioni in evidenza"] },
    { type = "execute", label = L["Guida al diario missioni"], func = function()
        if Badb.Guides then Badb.Guides:Open(GUIDE) end
    end },
}

if Badb.Guides then
    Badb.Guides:Register({
        id = "badb-quests", title = L["Diario missioni"], category = L["Gioco"], version = 1,
        entries = { {
            id = "journal", title = L["Guida al diario missioni"], tags = { L["Missioni"], L["Obiettivi"], "leveling" },
            body = {
                { type = "step", text = L["Apri Gioco > Diario missioni in BadbUI oppure digita /badb quests."] },
                { type = "step", text = L["Cerca per titolo, zona o ID. Usa Da consegnare per vedere le missioni pronte."] },
                { type = "step", text = L["Metti in evidenza le missioni che vuoi seguire. Nelle opzioni puoi mostrarle in un monitor sullo schermo."] },
                { type = "tip", text = L["Premi M per vedere le aree degli obiettivi nella mappa di WoW, se abilitate nelle opzioni del client."] },
                { type = "p", text = L["Cronologia raccoglie le consegne registrate mentre il modulo è attivo. In basso trovi l'esperienza del livello attuale."] },
            },
        } },
    })
end
