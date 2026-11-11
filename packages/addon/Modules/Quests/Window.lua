-- Diario e monitor delle missioni in evidenza.
local _, ns = ...
local Badb = ns.Badb
local M, L, UI, Theme = Badb.Quests, Badb.L, Badb.UI, Badb.Theme
local sp, sizes = Theme.spacing, Theme.sizes
local HUD_LIMIT = 5
local TABS = {
    { id = "all", text = L["Registro"] },
    { id = "pinned", text = L["In evidenza"] },
    { id = "ready", text = L["Da consegnare"] },
    { id = "history", text = L["Cronologia"] },
}
local STATUS = {
    active = L["In corso"], ready = L["Da consegnare"],
    failed = L["Fallita"], unknown = L["Stato non disponibile"],
}

local function details(entry)
    local level = entry.level and L["Livello %d"]:format(entry.level)
    if level and entry.zone then return level .. "  ·  " .. entry.zone end
    return level or entry.zone
end

local function historyText(entry)
    local xp = entry.xp and L["+%d XP"]:format(entry.xp)
    local stamp
    if entry.time and type(date) == "function" then
        local ok, value = pcall(date, "%x %H:%M", entry.time)
        if ok and type(value) == "string" then stamp = value end
    end
    if stamp and xp then return stamp .. "  ·  " .. xp end
    return stamp or xp or L["Consegnata"]
end

local function objectiveText(entry)
    if entry.text then return entry.text end
    return L["Progresso: %d/%d"]:format(entry.have, entry.need)
end

local function rowKey(entry, filter)
    return filter == "history" and entry or entry.id
end

local function objectiveRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:EnableMouse(true)
    row.text = UI:Label(row, nil, "body", "text")
    row.text:SetWordWrap(true)
    row.text:SetMaxLines(2)
    row.text:SetJustifyV("MIDDLE")
    row.text:SetPoint("TOPLEFT", sp.sm, -sp.xs)
    row.text:SetPoint("BOTTOMRIGHT", -sp.sm, sp.xs)
    row:SetScript("OnEnter", function(frame)
        if frame.item then UI:Tooltip(frame, L["Obiettivo"], { objectiveText(frame.item) }) end
    end)
    row:SetScript("OnLeave", function() UI:HideTooltip() end)
    row:SetScript("OnHide", function(frame)
        if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(frame) then UI:HideTooltip() end
    end)
    return row
end

local function updateObjective(row, entry)
    local prefix = ""
    if entry.done == true then prefix = "✓  " end
    Theme:Paint(row.text, entry.done == true and "success" or "text")
    row.text:SetText(prefix .. objectiveText(entry))
end

local function questRow(parent, window)
    local row = CreateFrame("Button", nil, parent)
    UI.AddHover(row)
    row.selected = UI:Fill(row, "selected", "BACKGROUND")
    row.selected:SetAllPoints()
    row.title = UI:Label(row, nil, "body", "text")
    row.title:SetPoint("LEFT", sp.sm, sp.sm)
    row.title:SetPoint("RIGHT", -sp.sm, sp.sm)
    row.meta = UI:Label(row, nil, "small", "textDim")
    row.meta:SetPoint("LEFT", sp.sm, -sp.sm)
    row.meta:SetPoint("RIGHT", -sp.sm, -sp.sm)
    local divider = UI:Separator(row, false, "divider")
    divider:SetPoint("BOTTOMLEFT", sp.sm, 0)
    divider:SetPoint("BOTTOMRIGHT", -sp.sm, 0)
    row:SetScript("OnClick", function(self)
        if self.item then
            window.selected = rowKey(self.item, window.filter)
            M:RefreshWindow()
        end
    end)
    return row
end

local function updateQuest(row, entry, window)
    local inHistory = window.filter == "history"
    local title = entry.title
    if not inHistory and M:IsPinned(entry.id) then title = "★  " .. title end
    row.title:SetText(title)
    local description = details(entry)
    if inHistory then
        row.meta:SetText(historyText(entry))
    else
        local status = STATUS[entry.status]
        row.meta:SetText(description and (description .. "  ·  " .. status) or status)
    end
    Theme:Paint(row.meta, entry.status == "ready" and "success" or entry.status == "failed" and "danger" or "textDim")
    row.selected:SetShown(rowKey(entry, window.filter) == window.selected)
end

local function renderDetail(window, entry)
    local detail = window.detail
    local inHistory = window.filter == "history"
    detail.title:SetText(entry and entry.title or "")
    detail.meta:SetText(entry and (inHistory and historyText(entry) or details(entry) or STATUS[entry.status]) or "")
    detail.list:SetData(entry and entry.objectives or {})
    detail.pin:SetShown(entry ~= nil and not inHistory)
    detail.pin:SetEnabled(entry ~= nil and (M.logStatus == "live" or M:IsPinned(entry.id)))
    if not entry then
        detail.notice:SetText("")
    elseif inHistory then
        detail.notice:SetText(L["Missione %d"]:format(entry.id))
    else
        detail.pin:SetLabel(M:IsPinned(entry.id) and L["Rimuovi da In evidenza"] or L["Metti in evidenza"])
        local notice
        if not entry.objectivesKnown then notice = L["Alcuni obiettivi non sono leggibili."]
        elseif #entry.objectives == 0 then notice = STATUS[entry.status] end
        detail.notice:SetText(notice or "")
    end
    window.entry = entry
end

local function emptyText(window)
    if window.filter == "history" and #M.state.history == 0 then
        return L["Le missioni consegnate compariranno qui."]
    end
    if window.filter ~= "history" and M.logStatus ~= "live" then
        return L["Il registro missioni non è leggibile in questo momento."]
    end
    if window.query:match("%S") then return L["Nessuna missione corrisponde alla ricerca."] end
    if window.filter == "ready" then return L["Nessuna missione pronta da consegnare."] end
    if window.filter == "pinned" then return L["Metti in evidenza una missione dal Registro."] end
    return L["Il registro missioni è vuoto."]
end

local function renderProgress(window)
    local progress = M.progress
    if not progress then
        window.xp:SetText(L["Esperienza non disponibile"])
    elseif progress.capped then
        window.xp:SetText(L["Livello %d · livello massimo"]:format(progress.level))
    elseif progress.current then
        window.xp:SetText(L["Livello %d · %d/%d XP"]:format(progress.level, progress.current, progress.maximum))
        window.progress:SetProgress(progress.current / progress.maximum)
    else
        window.xp:SetText(L["Livello %d"]:format(progress.level))
    end
    window.progress:SetShown(progress ~= nil and progress.current ~= nil)
end

function M:RefreshWindow(reset)
    local window = self.window
    if not (window and window:IsShown()) then return end
    local rows = self:List(window.query, window.filter)
    local selected
    for _, entry in ipairs(rows) do
        if rowKey(entry, window.filter) == window.selected then selected = entry; break end
    end
    selected = selected or rows[1]
    window.selected = selected and rowKey(selected, window.filter) or nil
    if reset then window.list:ScrollToIndex(1) end
    window.list:SetData(rows)
    window.empty:SetText(#rows == 0 and emptyText(window) or "")
    local notice = ""
    if window.filter ~= "history" and #rows > 0 then
        if self.logStatus ~= "live" then notice = L["Ultimo registro leggibile"]
        elseif self.log.partial then notice = L["Registro parziale"] end
    end
    window.status:SetText(notice)
    renderDetail(window, selected)
    renderProgress(window)
end

function M:BuildWindow()
    if self.window then return self.window end
    local window = UI:Window("BadbUIQuestJournal", sizes.sidebar * 4, sizes.row * 15, L["Diario missioni"], {
        footer = true, resizable = true, minW = sizes.sidebar * 3 + sp.xl, minH = sizes.row * 11,
        onClose = function(frame) frame.search.edit:ClearFocus() end,
    })
    window.query, window.filter = "", "all"
    window.tabs = UI:Tabs(window.body, TABS, function(filter)
        window.filter, window.selected = filter, nil
        self:RefreshWindow(true)
    end)
    window.tabs:SetPoint("TOPLEFT", sp.lg, -sp.md)
    window.tabs:SetPoint("TOPRIGHT", -sp.lg, -sp.md)

    window.search = UI:EditBox(window.body, sizes.sidebar, sizes.button, {
        placeholder = L["Cerca titolo, zona o ID"], maxLetters = 120,
        onChange = function(query)
            window.query = query
            self:RefreshWindow(true)
        end,
    })
    window.search:SetPoint("TOPLEFT", window.tabs, "BOTTOMLEFT", 0, -sp.md)
    window.search:SetPoint("TOPRIGHT", window.tabs, "BOTTOM", -sp.sm, -sp.md)

    window.status = UI:Label(window.body, nil, "small", "warning")
    window.status:SetPoint("LEFT", window.search, "RIGHT", sp.md, 0)
    window.status:SetPoint("RIGHT", window.tabs, "BOTTOMRIGHT", 0, -(sp.md + sizes.button / 2))

    window.list = UI:ScrollList(window.body, sizes.row + sp.xs, function(parent)
        return questRow(parent, window)
    end, function(row, entry) updateQuest(row, entry, window) end)
    window.list:SetPoint("TOPLEFT", window.search, "BOTTOMLEFT", 0, -sp.md)
    window.list:SetPoint("TOPRIGHT", window.search, "BOTTOMRIGHT", 0, -sp.md)
    window.list:SetPoint("BOTTOMLEFT", window.body, "BOTTOMLEFT", sp.lg, sp.md)
    window.empty = UI:Label(window.list, nil, "body", "textDim")
    window.empty:SetWordWrap(true)
    window.empty:SetPoint("TOPLEFT", sp.sm, -sp.md)
    window.empty:SetPoint("TOPRIGHT", -sp.sm, -sp.md)

    local detail = UI:Panel(window.body, "panel", { border = "border" })
    window.detail = detail
    detail:SetPoint("TOPLEFT", window.list, "TOPRIGHT", sp.md, 0)
    detail:SetPoint("BOTTOMRIGHT", window.body, "BOTTOMRIGHT", -sp.lg, sp.md)
    detail.title = UI:Label(detail, nil, "heading", "text")
    detail.title:SetWordWrap(true)
    detail.title:SetMaxLines(2)
    detail.title:SetJustifyV("TOP")
    detail.title:SetHeight(sizes.row + sp.xs)
    detail.title:SetPoint("TOPLEFT", sp.md, -sp.md)
    detail.title:SetPoint("TOPRIGHT", -sp.md, -sp.md)
    detail.meta = UI:Label(detail, nil, "small", "textDim")
    detail.meta:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -sp.xs)
    detail.meta:SetPoint("TOPRIGHT", detail.title, "BOTTOMRIGHT", 0, -sp.xs)

    detail.pin = UI:Button(detail, L["Metti in evidenza"], sizes.sidebar, sizes.button, function()
        local entry = window.entry
        if not entry then return end
        local ok, err = self:SetPinned(entry.id, not self:IsPinned(entry.id))
        if not ok and err then Badb.Logger:Warn("%s", err) end
    end)
    detail.pin:SetPoint("BOTTOMLEFT", sp.md, sp.md)
    detail.list = UI:ScrollList(detail, sizes.row + sp.sm, objectiveRow, updateObjective)
    detail.list:SetPoint("TOPLEFT", detail.meta, "BOTTOMLEFT", 0, -sp.sm)
    detail.list:SetPoint("TOPRIGHT", detail.meta, "BOTTOMRIGHT", 0, -sp.sm)
    detail.notice = UI:Label(detail, nil, "small", "textDim")
    detail.notice:SetWordWrap(true)
    detail.notice:SetPoint("BOTTOMLEFT", detail.pin, "TOPLEFT", 0, sp.xs)
    detail.notice:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -sp.md, sp.md + sizes.button + sp.xs)
    detail.list:SetPoint("BOTTOMLEFT", detail.notice, "TOPLEFT", 0, sp.xs)

    window.xp = UI:Label(window.footer, nil, "small", "textDim")
    window.xp:SetPoint("LEFT", sp.lg, 0)
    window.progress = UI:ProgressBar(window.footer, sizes.sidebar, sp.sm, "accent")
    window.progress:SetPoint("RIGHT", -sp.lg, 0)
    window.progress:Hide()

    self.window = window
    return window
end

function M:Open(query, filter)
    if not self.running then return false end
    query, filter = Badb.Compat.SafeValue(query), Badb.Compat.SafeValue(filter)
    local window = self:BuildWindow()
    if type(query) == "string" then
        window.query = query:sub(1, 120)
        window.search:SetText(window.query)
    end
    if filter == "pinned" then window.tabs:Select("pinned")
    elseif type(query) == "string" and query:match("%S") then window.tabs:Select("all") end
    window:Show()
    self:RefreshWindow(true)
    self:Queue(true)
    return true
end

function M:BuildHUD()
    if self.hud then return self.hud end
    local hud = CreateFrame("Frame", "BadbUIQuestTracker", UIParent)
    hud:Hide()
    hud:SetSize(sizes.sidebar + sizes.row * 4, sizes.header)
    hud:SetPoint("RIGHT", UIParent, "RIGHT", -sp.lg, 0)
    hud:SetClampedToScreen(true)
    Theme:Skin(hud, { bg = "panel", border = "border" })
    local open = UI:Button(hud, L["Missioni in evidenza"], sizes.sidebar, sizes.button,
        function() self:Open("", "pinned") end, "ghost")
    open:SetPoint("TOPLEFT", sp.xs, -sp.xs)
    hud.rows = {}
    for i = 1, HUD_LIMIT do
        local row = CreateFrame("Frame", nil, hud)
        row:SetHeight(sizes.row + sp.xs)
        row:SetPoint("TOPLEFT", sp.md, -(sizes.button + sp.sm + (i - 1) * (sizes.row + sp.xs)))
        row:SetPoint("TOPRIGHT", -sp.md, -(sizes.button + sp.sm + (i - 1) * (sizes.row + sp.xs)))
        row.title = UI:Label(row, nil, "body", "text")
        row.title:SetPoint("TOPLEFT", 0, -sp.xs)
        row.title:SetPoint("TOPRIGHT", 0, -sp.xs)
        row.meta = UI:Label(row, nil, "small", "textDim")
        row.meta:SetPoint("BOTTOMLEFT", 0, sp.xs)
        row.meta:SetPoint("BOTTOMRIGHT", 0, sp.xs)
        hud.rows[i] = row
    end
    self.hud = hud
    hooksecurefunc(hud, "Show", function(frame)
        if not self.hudWanted then frame:Hide() end
    end)
    Badb.FrameManager:Register("BadbUIQuestTracker", {
        frame = "BadbUIQuestTracker", title = L["Missioni in evidenza"], category = L["Gioco"],
        movable = true, scalable = true, hideable = true,
    })
    return hud
end

function M:RefreshHUD()
    self.hudWanted = false
    local frameSettings = Badb.DB.profile.frames.BadbUIQuestTracker
    if self:Get("hud") ~= true or (frameSettings and frameSettings.hidden) or self.logStatus ~= "live" then
        if self.hud then self.hud:Hide() end
        return
    end
    local entries = self:List(nil, "pinned")
    if #entries == 0 then
        if self.hud then self.hud:Hide() end
        return
    end
    local hud = self:BuildHUD()
    for index, row in ipairs(hud.rows) do
        local entry = entries[index]
        row:SetShown(entry ~= nil)
        if entry then
            row.title:SetText(entry.title)
            local message = STATUS[entry.status]
            if entry.status == "active" then
                for _, objective in ipairs(entry.objectives) do
                    if objective.done ~= true then message = objectiveText(objective); break end
                end
            end
            row.meta:SetText(message)
            Theme:Paint(row.meta, entry.status == "ready" and "success" or entry.status == "failed" and "danger" or "textDim")
        end
    end
    hud:SetHeight(sizes.button + sp.md + math.min(#entries, HUD_LIMIT) * (sizes.row + sp.xs))
    self.hudWanted = true
    hud:Show()
end
