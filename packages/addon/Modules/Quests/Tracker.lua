-- BadbUI - Monitor obiettivi: missioni seguite, progresso e waypoint.
-- Nessun database di missioni: i dati arrivano solo dalle API del client
-- sondate a runtime. Senza coordinate esposte dal client non esiste un
-- waypoint obiettivo: il pulsante lo dice e non inventa posizioni.
local _, ns = ...
local Badb = ns.Badb
local L, Compat = Badb.L, Badb.Compat

local MAX_ID = 2147483647
local MAX_ENTRIES = 200
local MAX_OBJECTIVES = 32
local MAX_WATCHED = 25
local MAX_CHARACTERS = 24
local SCHEMA = 1
local GUIDE = "badb-questtracker:tracker"

local M = Badb.Modules:New("QuestTracker", {
    title = L["Monitor obiettivi"],
    category = L["Gioco"],
    description = L["Segui le missioni, leggi il progresso degli obiettivi e invia un waypoint quando il client lo espone."],
    defaults = { enabled = true, autoWatch = true },
    page = { title = L["Monitor obiettivi"], category = L["Gioco"], order = 61,
        keywords = { L["Missioni"], L["Obiettivi"], "Questie", "QuestHelper", "tracker" } },
    replaces = {
        { addon = "Questie", coverage = "partial",
          note = L["Monitor obiettivi, progresso e missioni seguite. Restano esclusi database delle missioni e segnalini degli obiettivi sulla mappa."] },
        { addon = "QuestHelper", coverage = "partial",
          note = L["Monitor obiettivi e progresso. Restano esclusi database, rotte e segnalini degli obiettivi sulla mappa."] },
    },
})
Badb.QuestTracker = M

-- Chiamata difensiva: esistenza, pcall e valori segreti scartati.
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return Compat.SafeValue(value) end
end

local function callMulti(fn, ...)
    if type(fn) ~= "function" then return nil end
    local packed = { pcall(fn, ...) }
    if not packed[1] then return nil end
    for i = 2, #packed do packed[i] = Compat.SafeValue(packed[i]) end
    return unpack(packed, 2)
end

local function integer(value, min, max)
    value = Compat.SafeValue(value)
    if type(value) == "number" and value >= min and value <= max and value == math.floor(value) then
        return value
    end
end

local function questID(value) return integer(value, 1, MAX_ID) end

local function text(value, max)
    value = Compat.SafeValue(value)
    if type(value) ~= "string" or #value > max then return nil end
    local clean = value:gsub("[%c|]", " "):match("^%s*(.-)%s*$")
    if clean ~= "" then return clean end
end

local function ratio(value)
    value = Compat.SafeValue(value)
    if type(value) == "number" and value >= 0 and value <= 1 then return value end
end

-- Percentuale 0-100 dagli obiettivi, o nil se non calcolabile.
function M.ComputeProgress(objectives, status)
    if status == "ready" then return 100 end
    if type(objectives) ~= "table" or #objectives == 0 then return nil end
    local have, need, done, counted = 0, 0, 0, 0
    for _, objective in ipairs(objectives) do
        if type(objective) == "table" then
            counted = counted + 1
            if objective.done == true then done = done + 1 end
            local h, n = objective.have, objective.need
            if type(h) == "number" and type(n) == "number" and n > 0 then
                have, need = have + math.min(h, n), need + n
            end
        end
    end
    if need > 0 then return math.floor(have * 100 / need + 0.5) end
    if counted > 0 then return math.floor(done * 100 / counted + 0.5) end
    return nil
end

local function readObjectivesModern(api, id)
    local raw = call(api.GetQuestObjectives, id)
    if type(raw) == "table" then
        local objectives, known = {}, #raw <= MAX_OBJECTIVES
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
                else known = false end
            else known = false end
        end
        return objectives, known
    end
    -- Fallback puntuale: GetQuestObjectiveInfo (C_QuestLog o globale).
    local fn = (type(api.GetQuestObjectiveInfo) == "function" and api.GetQuestObjectiveInfo)
        or (type(GetQuestObjectiveInfo) == "function" and GetQuestObjectiveInfo)
    if not fn then return {}, false end
    local objectives, known = {}, true
    for index = 1, MAX_OBJECTIVES do
        local label, _, have, need, done = callMulti(fn, id, index)
        if label == nil and have == nil and need == nil then break end
        label = text(label, 500)
        have, need = integer(have, 0, MAX_ID), integer(need, 1, MAX_ID)
        if type(done) ~= "boolean" then
            if have and need then done = have >= need else done = nil end
        end
        if label or (have and need) then
            objectives[#objectives + 1] = { text = label, have = have, need = need, done = done }
        else known = false end
    end
    return objectives, known
end

local function readStatus(api, id)
    if call(api.IsFailed, id) == true then return "failed" end
    local ready = call(api.ReadyForTurnIn, id)
    local complete = call(api.IsComplete, id)
    if ready == true or complete == true then return "ready" end
    if ready == false or complete == false then return "active" end
    return "unknown"
end

function M:ReadLog()
    local api = C_QuestLog
    if type(api) == "table" and type(api.GetNumQuestLogEntries) == "function" and type(api.GetInfo) == "function" then
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
                local id, title = questID(info.questID), text(info.title, 240)
                if not (id and title) then partial = true
                elseif not byID[id] then
                    local objectives, known = readObjectivesModern(api, id)
                    local status = readStatus(api, id)
                    local entry = { id = id, title = title, zone = zone, status = status,
                        level = integer(info.level, 1, 255) or integer(info.difficultyLevel, 1, 255),
                        objectives = objectives, objectivesKnown = known }
                    entry.progress = M.ComputeProgress(objectives, status)
                    byID[id] = entry
                    entries[#entries + 1] = entry
                end
            end
        end
        return { entries = entries, byID = byID, partial = partial }, "live"
    end
    -- Fallback classico: conteggio globale e GetQuestLogTitle per indice.
    if type(GetNumQuestLogEntries) == "function" and type(GetQuestLogTitle) == "function" then
        local count = integer(call(GetNumQuestLogEntries), 0, MAX_ID)
        if not count then return nil, "unreadable" end
        local entries, byID, zone = {}, {}, nil
        local partial = count > MAX_ENTRIES
        for index = 1, math.min(count, MAX_ENTRIES) do
            local title, level, _, isHeader, _, isComplete, _, id =
                callMulti(GetQuestLogTitle, index)
            if title == nil then partial = true
            elseif isHeader == true or isHeader == 1 then
                zone = text(title, 180)
            else
                title, id = text(title, 240), questID(id)
                if not title then partial = true
                elseif not id then
                    -- Senza ID non possiamo seguire ne' calcolare: voce sola lettura.
                    local entry = { id = nil, index = index, title = title, zone = zone,
                        status = (isComplete == true or isComplete == 1) and "ready" or "unknown",
                        level = integer(level, 1, 255), objectives = {}, objectivesKnown = false }
                    entry.progress = M.ComputeProgress(entry.objectives, entry.status)
                    entries[#entries + 1] = entry
                elseif not byID[id] then
                    local objectives, known = readObjectivesModern({}, id)
                    local status = (isComplete == true or isComplete == 1) and "ready" or "active"
                    local entry = { id = id, index = index, title = title, zone = zone, status = status,
                        level = integer(level, 1, 255), objectives = objectives, objectivesKnown = known }
                    entry.progress = M.ComputeProgress(objectives, status)
                    byID[id] = entry
                    entries[#entries + 1] = entry
                end
            end
        end
        return { entries = entries, byID = byID, partial = partial }, "live"
    end
    return nil, "unsupported"
end

function M:Available()
    local api = C_QuestLog
    if type(api) == "table" and type(api.GetNumQuestLogEntries) == "function"
        and (type(api.GetInfo) == "function" or type(api.GetQuestObjectiveInfo) == "function") then
        return true
    end
    return type(GetNumQuestLogEntries) == "function" and type(GetQuestLogTitle) == "function"
end

-- Coordinate obiettivo esposte dal client, se esistono. Mai inventate.
function M:GetQuestWaypoint(id)
    id = questID(id)
    if not id then return nil end
    local api = C_QuestLog
    if type(api) == "table" then
        local map, x, y = callMulti(api.GetNextWaypoint, id)
        map, x, y = questID(map), ratio(x), ratio(y)
        if map and x and y then return { map = map, x = x, y = y } end
        local mapOnly = questID(call(api.GetQuestUiMapID, id))
        if mapOnly then return { map = mapOnly } end
    end
    return nil
end

-- Invia il waypoint al modulo World di BadbUI, solo se presente.
function M:SendWaypoint(id)
    if not self.running then return false, L["Attiva Monitor obiettivi in BadbUI per usarlo."] end
    id = questID(id)
    local entry = id and self.log and self.log.byID[id]
    if not entry then return false, L["Missione non leggibile nel registro."] end
    local point = self:GetQuestWaypoint(id)
    if not (point and point.x and point.y) then
        return false, L["Il client non espone le coordinate di questo obiettivo: waypoint non disponibile."]
    end
    local world = Badb.World or Badb.WorldWaypoints
    if not (type(world) == "table" and type(world.Add) == "function") then
        return false, L["Modulo waypoint di BadbUI non disponibile."]
    end
    local wid, err = world:Add(point.map, point.x, point.y, entry.title)
    if not wid then return false, err or L["Modulo waypoint di BadbUI non disponibile."] end
    if type(world.PlaceNative) == "function" then
        local ok, werr = world:PlaceNative(wid)
        if ok then return true end
        if type(world.Track) == "function" then world:Track(wid) end
        return true, werr
    end
    if type(world.Track) == "function" then world:Track(wid) end
    return true
end

local function cleanWatched(value)
    local watched, seen = {}, {}
    if type(value) == "table" then
        for i = 1, MAX_WATCHED do
            local id = questID(value[i])
            if id and not seen[id] then
                seen[id] = true
                watched[#watched + 1] = id
            end
        end
    end
    return watched
end

function M:OnInitialize()
    local store = Badb.DB:GetStore("questtracker")
    local key = Badb.DB.char
    self.watched, self.saved = {}, nil
    if not store or type(key) ~= "string" or #key > 240 then return end
    if type(store.version) == "number" and store.version > SCHEMA then return end
    local saved = store.version == SCHEMA and type(store.characters) == "table" and store.characters or {}
    self.watched = cleanWatched(saved[key] and saved[key].watched)
    -- Conserva al massimo gli ultimi personaggi toccati, come il Diario.
    local ranked = {}
    for owner, value in pairs(saved) do
        if owner ~= key and type(owner) == "string" and #owner <= 240 and type(value) == "table" then
            ranked[#ranked + 1] = { owner = owner, touched = integer(value.touched, 0, 4102444800) or 0 }
        end
    end
    table.sort(ranked, function(a, b)
        if a.touched ~= b.touched then return a.touched > b.touched end
        return a.owner < b.owner
    end)
    store.version, store.characters = SCHEMA, {}
    for index = 1, math.min(#ranked, MAX_CHARACTERS - 1) do
        local owner = ranked[index].owner
        store.characters[owner] = { watched = cleanWatched(saved[owner].watched),
            touched = ranked[index].touched }
    end
    self.saved = { watched = {}, touched = 0 }
    store.characters[key] = self.saved
    self:Save()
end

function M:Save()
    if not self.saved then return end
    self.saved.watched = {}
    for i, id in ipairs(self.watched or {}) do self.saved.watched[i] = id end
    local stamp = integer(call(GetServerTime), 1, 4102444800) or integer(call(time), 1, 4102444800)
    if stamp then self.saved.touched = stamp end
end

function M:IsWatched(id)
    id = questID(id)
    if not id then return false end
    for _, watched in ipairs(self.watched or {}) do
        if watched == id then return true end
    end
    return false
end

function M:SetWatched(id, watched)
    id = questID(id)
    watched = Compat.SafeValue(watched)
    if not self.running or not id or type(watched) ~= "boolean" then return false end
    if watched == self:IsWatched(id) then return true end
    if watched then
        if self.logStatus ~= "live" or not self.log or not self.log.byID[id] then return false end
        if #self.watched >= MAX_WATCHED then
            return false, L["Hai raggiunto il limite di 25 missioni seguite."]
        end
        self.watched[#self.watched + 1] = id
        self:TryClientWatch(id, true)
    else
        for i, current in ipairs(self.watched) do
            if current == id then table.remove(self.watched, i) break end
        end
        self:TryClientWatch(id, false)
    end
    self:Save()
    self:UpdateViews()
    return true
end

-- Watch nativo del client, solo se le API esistono: best effort, mai errore.
function M:TryClientWatch(id, watched)
    local api = C_QuestLog
    local entry = self.log and self.log.byID[id]
    local index = entry and entry.index
    if type(api) == "table" and type(api.AddQuestWatch) == "function"
        and type(api.RemoveQuestWatch) == "function" then
        pcall(watched and api.AddQuestWatch or api.RemoveQuestWatch, id)
        return true
    end
    if not index then
        local byID = type(GetQuestLogIndexByID) == "function" and call(GetQuestLogIndexByID, id)
        index = integer(byID, 1, MAX_ENTRIES)
    end
    if index and type(AddQuestWatch) == "function" and type(RemoveQuestWatch) == "function" then
        pcall(watched and AddQuestWatch or RemoveQuestWatch, index)
        return true
    end
    return false
end

function M:GetWatched()
    local out = {}
    for i, id in ipairs(self.watched or {}) do out[i] = id end
    return out
end

-- Missioni seguite con dati freschi; senza ID o fuori registro: escluse.
function M:GetTracked()
    if not self.running or not self.log then return {} end
    local out = {}
    for _, id in ipairs(self.watched or {}) do
        local entry = self.log.byID[id]
        if entry then
            local copy = { id = entry.id, title = entry.title, zone = entry.zone,
                level = entry.level, status = entry.status, progress = entry.progress,
                objectives = entry.objectives, objectivesKnown = entry.objectivesKnown,
                watched = true, waypoint = self:GetQuestWaypoint(id) }
            out[#out + 1] = copy
        end
    end
    return out
end

-- Tutte le voci leggibili, con flag watched e progresso.
function M:List()
    if not self.running or not self.log then return {} end
    local out = {}
    for _, entry in ipairs(self.log.entries) do
        local copy = { id = entry.id, title = entry.title, zone = entry.zone,
            level = entry.level, status = entry.status, progress = entry.progress,
            objectives = entry.objectives, objectivesKnown = entry.objectivesKnown,
            watched = entry.id ~= nil and self:IsWatched(entry.id) or false }
        out[#out + 1] = copy
    end
    return out
end

function M:Refresh(readLog)
    if readLog then
        local snapshot, status = self:ReadLog()
        self.logStatus = status
        if snapshot then
            self.log = snapshot
            -- Le seguite sparite dal registro restano finche' il client
            -- non conferma l'uscita (stessa regola del Diario).
            local api = C_QuestLog
            if #snapshot.entries > 0 and type(api) == "table" and type(api.IsOnQuest) == "function" then
                local kept, changed = {}, false
                for _, id in ipairs(self.watched) do
                    if snapshot.byID[id] or call(api.IsOnQuest, id) ~= false then
                        kept[#kept + 1] = id
                    else changed = true end
                end
                if changed then self.watched = kept self:Save() end
            end
        end
    end
    if readLog and self.pendingAutoWatch then
        local qid = self.pendingAutoWatch
        self.pendingAutoWatch = nil
        if self.log and self.log.byID[qid] then self:SetWatched(qid, true) end
    end
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

function M:UpdateViews()
    if self.RefreshWindow then self:RefreshWindow() end
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
    self:On("QUEST_ACCEPTED", function(_, a, b)
        -- Payload client: (indiceRegistro, questID); alcuni client solo (questID).
        local qid = questID(b) or questID(a)
        if qid and self:Get("autoWatch") == true then
            -- Il registro potrebbe non essere ancora aggiornato: accoda
            -- la lettura e poi applica la watch sulla voce fresca.
            self.pendingAutoWatch = qid
        end
        changed()
    end)
    self:On("QUEST_REMOVED", function(_, id)
        id = questID(id)
        if id and self:IsWatched(id) then
            self:SetWatchedSilent(id)
        end
        changed()
    end)
    self:On("QUEST_TURNED_IN", function(_, id)
        id = questID(id)
        if id and self:IsWatched(id) then self:SetWatchedSilent(id) end
        changed()
    end)
    self:On("PLAYER_REGEN_ENABLED", changed)
    changed()
end

-- Rimozione interna senza richiedere il registro live (missione gia' uscita).
function M:SetWatchedSilent(id)
    for i, current in ipairs(self.watched or {}) do
        if current == id then
            table.remove(self.watched, i)
            self:Save()
            return
        end
    end
end

function M:OnDisable()
    self.running = false
    self.log, self.pendingAutoWatch = nil, nil
    if self.window then self.window:Hide() end
end

function M:OnProfileChanged()
    self:UpdateViews()
end

-- Finestra del monitor: missioni seguite, progresso e azioni per missione.
local STATUS = {
    active = L["In corso"], ready = L["Da consegnare"],
    failed = L["Fallita"], unknown = L["Stato non disponibile"],
}

local function objectiveLine(objective)
    if objective.text then return objective.text end
    if objective.have and objective.need then
        return L["Progresso: %d/%d"]:format(objective.have, objective.need)
    end
    return L["Obiettivo"]
end

local function trackedRow(parent)
    local row = CreateFrame("Button", nil, parent)
    Badb.UI.AddHover(row)
    row.selected = Badb.UI:Fill(row, "selected", "BACKGROUND")
    row.selected:SetAllPoints()
    local sp = Badb.Theme.spacing
    row.title = Badb.UI:Label(row, nil, "body", "text")
    row.title:SetPoint("LEFT", sp.sm, sp.sm)
    row.title:SetPoint("RIGHT", -sp.sm, sp.sm)
    row.meta = Badb.UI:Label(row, nil, "small", "textDim")
    row.meta:SetPoint("LEFT", sp.sm, -sp.sm)
    row.meta:SetPoint("RIGHT", -sp.sm, -sp.sm)
    row:SetScript("OnClick", function(self)
        if self.item then
            M.window.selected = self.item.id
            M:RefreshWindow()
        end
    end)
    return row
end

local function updateTracked(row, entry)
    row.title:SetText(entry.title)
    local status = STATUS[entry.status] or STATUS.unknown
    local progress = entry.progress and L["Progresso %d%%"]:format(entry.progress) or L["Progresso non disponibile"]
    row.meta:SetText(progress .. "  ·  " .. status)
    Badb.Theme:Paint(row.meta, entry.status == "ready" and "success"
        or entry.status == "failed" and "danger" or "textDim")
    row.selected:SetShown(M.window and M.window.selected == entry.id)
end

function M:BuildWindow()
    if self.window then return self.window end
    local UI, Theme = Badb.UI, Badb.Theme
    local sp, sizes = Theme.spacing, Theme.sizes
    local window = UI:Window("BadbUIQuestTrackerWindow", sizes.sidebar * 4, sizes.row * 14, L["Monitor obiettivi"], {
        footer = true, resizable = true, minW = sizes.sidebar * 3 + sp.xl, minH = sizes.row * 10,
    })
    window.list = UI:ScrollList(window.body, sizes.row + sp.xs, trackedRow, updateTracked)
    window.list:SetPoint("TOPLEFT", sp.lg, -sp.md)
    window.list:SetPoint("TOPRIGHT", window.body, "TOPRIGHT", -sp.lg, -sp.md)
    window.list:SetPoint("BOTTOMLEFT", sp.lg, sizes.row * 4)
    window.empty = UI:Label(window.list, nil, "body", "textDim")
    window.empty:SetWordWrap(true)
    window.empty:SetPoint("TOPLEFT", sp.sm, -sp.md)
    window.empty:SetPoint("TOPRIGHT", -sp.sm, -sp.md)

    window.detail = UI:Label(window.body, nil, "small", "textDim")
    window.detail:SetWordWrap(true)
    window.detail:SetPoint("TOPLEFT", window.list, "BOTTOMLEFT", 0, -sp.sm)
    window.detail:SetPoint("BOTTOMRIGHT", window.body, "BOTTOMRIGHT", -sp.lg, sizes.button + sp.lg)

    local waypoint = UI:Button(window.body, L["Waypoint obiettivo"], sizes.sidebar, sizes.button, function()
        if not window.entry then return end
        local ok, err = self:SendWaypoint(window.entry.id)
        if not ok and err then Badb.Logger:Warn("%s", err) end
        if ok and err then Badb.Logger:Warn("%s", err) end
    end)
    waypoint:SetPoint("BOTTOMLEFT", sp.lg, sp.md)
    window.waypoint = waypoint
    local watch = UI:Button(window.body, L["Non seguire più"], sizes.sidebar, sizes.button, function()
        if not window.entry then return end
        local ok, err = self:SetWatched(window.entry.id, not self:IsWatched(window.entry.id))
        if not ok and err then Badb.Logger:Warn("%s", err) end
    end)
    watch:SetPoint("LEFT", waypoint, "RIGHT", sp.sm, 0)
    window.watch = watch
    window.status = UI:Label(window.footer, nil, "small", "warning")
    window.status:SetPoint("LEFT", sp.lg, 0)
    window.status:SetPoint("RIGHT", -sp.lg, 0)
    self.window = window
    return window
end

function M:RefreshWindow()
    local window = self.window
    if not (window and window:IsShown()) then return end
    local rows = self:GetTracked()
    if #rows == 0 then rows = self:List() end
    local selected
    for _, entry in ipairs(rows) do
        if entry.id == window.selected then selected = entry break end
    end
    selected = selected or rows[1]
    window.selected = selected and selected.id or nil
    window.entry = selected
    window.list:SetData(rows)
    if self.logStatus ~= "live" then
        window.empty:SetText(L["Il registro missioni non è leggibile in questo momento."])
    elseif #rows == 0 then
        window.empty:SetText(L["Nessuna missione seguita. Accetta una missione o disattiva il seguito automatico e scegli dal Diario missioni."])
    else
        window.empty:SetText("")
    end
    window.status:SetText(self.logStatus ~= "live" and L["Registro missioni non disponibile su questo client."] or "")
    if selected then
        local lines = {}
        for _, objective in ipairs(selected.objectives or {}) do
            lines[#lines + 1] = (objective.done == true and "✓  " or "") .. objectiveLine(objective)
        end
        if #lines == 0 then lines[1] = STATUS[selected.status] or "" end
        if not selected.objectivesKnown then
            lines[#lines + 1] = L["Alcuni obiettivi non sono leggibili."]
        end
        window.detail:SetText(table.concat(lines, "\n"))
        local point = selected.id and self:GetQuestWaypoint(selected.id)
        window.waypoint:SetEnabled(point ~= nil and point.x ~= nil and point.y ~= nil)
        window.waypoint:SetLabel(point and point.x and L["Waypoint obiettivo"] or L["Waypoint non disponibile"])
        window.watch:SetLabel(self:IsWatched(selected.id) and L["Non seguire più"] or L["Segui missione"])
        window.watch:SetEnabled(selected.id ~= nil)
    else
        window.detail:SetText("")
        window.waypoint:SetEnabled(false)
        window.watch:SetEnabled(false)
    end
end

function M:Open()
    if not self.running then return false end
    local window = self:BuildWindow()
    window:Show()
    self:RefreshWindow()
    self:Queue(true)
    return true
end

local function openTracker()
    if M.running then
        M:Open()
    else
        Badb.Logger:Warn(L["Attiva Monitor obiettivi in BadbUI per aprirlo."])
    end
end

M.commands = {
    quests = { help = L["quests - apri il monitor obiettivi delle missioni"], fn = function() openTracker() end },
    questtracker = { help = L["questtracker - apri il monitor obiettivi delle missioni"], fn = function() openTracker() end },
}

M.options = {
    { type = "label", text = function()
        return M:Available() and M.description or L["Registro missioni non disponibile su questo client."]
    end },
    { type = "execute", label = L["Apri monitor obiettivi"], disabled = function() return not M.running end,
      func = function() openTracker() end },
    { type = "toggle", path = "autoWatch", label = L["Segui automaticamente le nuove missioni accettate"] },
    { type = "execute", label = L["Guida al monitor obiettivi"], func = function()
        if Badb.Guides then Badb.Guides:Open(GUIDE) end
    end },
}

if Badb.Guides then
    Badb.Guides:Register({
        id = "badb-questtracker", title = L["Monitor obiettivi"], category = L["Gioco"], version = 1,
        entries = { {
            id = "tracker", title = L["Guida al monitor obiettivi"], tags = { L["Missioni"], L["Obiettivi"], "Questie", "QuestHelper" },
            body = {
                { type = "step", text = L["Apri Gioco > Monitor obiettivi in BadbUI oppure digita /badb questtracker."] },
                { type = "step", text = L["Le missioni accettate vengono seguite automaticamente se l'opzione è attiva. Dal monitor puoi smettere di seguire una missione."] },
                { type = "step", text = L["La percentuale usa gli obiettivi numerici esposti dal client. Se il client non li espone, il monitor mostra solo lo stato."] },
                { type = "tip", text = L["Waypoint obiettivo funziona solo quando il client espone le coordinate dell'obiettivo e il modulo waypoint di BadbUI è attivo. Non esistono segnalini degli obiettivi senza un database."] },
            },
        } },
    })
end
