-- Contatore e minaccia in una finestra BadbUI indipendente dai pannelli Blizzard.
local _, ns = ...
local Badb, Source = ns.Badb, ns.CombatSource
local L, UI, Theme = Badb.L, Badb.UI, Badb.Theme
local FM, Events, Logger = Badb.FrameManager, Badb.Events, Badb.Logger
local IsSecret = Badb.Compat.IsSecret
local P, S = Theme.spacing, Theme.sizes

local FRAME_KEY, GUIDE_ID = "Combat", "suite-combat:meter"
local MIN_W, MIN_H = S.sidebar * 2 + 4 * P.lg, S.header + S.row * 6
local MAX_W, MAX_H = MIN_W + S.sidebar * 2, MIN_H + S.row * 16
local DEFAULT_H = MIN_H + S.row * 3
local REFRESH_DELAY = 0.25
local DASH = "—"

local M = Badb.Modules:New("Combat", {
    title = L["Statistiche di combattimento"],
    category = L["Gioco"],
    description = L["Danni, cure e minaccia del bersaglio dalle API native del client."],
    defaults = { enabled = true, showAtLogin = false, width = MIN_W, height = DEFAULT_H },
    page = {
        title = L["Statistiche di combattimento"], order = 30, category = L["Gioco"],
        keywords = { "dps", "hps", "details", "threat", L["Minaccia"], L["Danni inflitti"], L["Cure effettuate"] },
    },
    replaces = {
        { addon = "Details", title = "Details!", coverage = "partial",
          note = L["Resoconto e magie dalle API native; confronto, esportazione e archivio dei plugin non inclusi."] },
        { addon = "Details_TinyThreat", title = "Details! Tiny Threat", coverage = "partial",
          note = L["Mostra la minaccia del bersaglio quando il client la rende leggibile."] },
        { addon = "ThreatClassic2", title = "ThreatClassic2", coverage = "partial",
          note = L["Mostra la minaccia del bersaglio quando il client la rende leggibile."] },
    },
})
Badb.Combat = M

local METER_EVENTS = {
    "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_RESET",
}
local THREAT_EVENTS = {
    "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
}
local METER_MESSAGES = {
    unavailable = L["Il contatore nativo non è disponibile su questo client."],
    unreadable = L["Questo scontro non è più accessibile oppure il client non ne espone i dati."],
    restricted = L["Il client riserva i dati di questo scontro."],
    empty = L["Nessuna statistica per questa selezione. Prova dopo uno scontro."],
}
local SPELL_MESSAGES = {
    unavailable = L["Il dettaglio delle magie non è disponibile su questo client."],
    unreadable = L["Il client non rende disponibile il dettaglio di questo partecipante."],
    restricted = L["Il client riserva il dettaglio delle magie di questo partecipante."],
    empty = L["Nessuna magia per questo partecipante e questa statistica."],
}
local THREAT_MESSAGES = {
    unavailable = L["Le API native di minaccia non sono disponibili."],
    noTarget = L["Seleziona un bersaglio ostile per vedere la minaccia."],
    empty = L["Il client non ha ancora dati di minaccia per questo bersaglio."],
    restricted = L["Il client riserva la minaccia di questo bersaglio."],
}
local THREAT_STATUS = {
    [0] = { L["Minaccia bassa"], "textMuted" },
    [1] = { L["Vicino all'aggro"], "warning" },
    [2] = { L["Aggro conteso"], "warning" },
    [3] = { L["Aggro stabile"], "success" },
}

local function cleanName(name, player)
    return Source.CleanText(name) or (player and L["Tu"] or L["Sconosciuto"])
end

local function setName(label, name, player)
    -- FontString:SetText accetta valori opachi. Non leggere il testo del widget.
    if IsSecret(name) and pcall(label.SetText, label, name) then return end
    label:SetText(cleanName(name, player))
end

local function publicNumber(value, perSecond)
    if value < 1000 then return (perSecond and "%.1f" or "%.0f"):format(value) end
    if value < 1000000 then return ("%.1fK"):format(value / 1000) end
    if value < 1000000000 then return ("%.1fM"):format(value / 1000000) end
    if value < 1000000000000 then return ("%.1fB"):format(value / 1000000000) end
    return ("%.3g"):format(value)
end

local function setValue(label, row, view, perSecond)
    if view == "threat" then
        label:SetText(row.public and ("%.0f%%"):format(row.public) or DASH)
    elseif IsSecret(row.value) then
        -- Formattazione del client: il numero resta opaco anche al font.
        local fmt = perSecond and "%.1f" or "%.0f"
        if not pcall(label.SetFormattedText, label, fmt, row.value) then label:SetText(DASH) end
    else
        label:SetText(row.public and publicNumber(row.public, perSecond) or DASH)
    end
end

local function size(value, min, max, default)
    if type(value) ~= "number" or value ~= value or value < min or value > max then return default end
    return value
end

function M:ApplySize()
    if not self.window then return end
    self.window:SetSize(size(self:Get("width"), MIN_W, MAX_W, MIN_W),
        size(self:Get("height"), MIN_H, MAX_H, DEFAULT_H))
end

function M:SetTab(tab)
    if tab ~= "meter" and tab ~= "threat" then return end
    self.view, self.selected = tab, nil
    local window = self.window
    if not window then return end
    window.list:ScrollToIndex(1)
    self:RefreshWindow()
end

function M:SelectSource(row)
    if not row or not row.identity then return end
    self.selected = { identity = row.identity, title = cleanName(row.name, row.player) }
    self.window.list:ScrollToIndex(1)
    self:RefreshWindow()
end

local function createRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row.shade = UI:Fill(row, "accentSoft", "BACKGROUND")
    row.shade:SetAllPoints()
    row.mark = UI:Fill(row, "accent", "ARTWORK")
    row.mark:SetWidth(Theme:Pixel(row))
    row.mark:SetPoint("TOPLEFT", 0, -P.xs)
    row.mark:SetPoint("BOTTOMLEFT", 0, P.xs)
    UI.AddHover(row)

    row.rank = UI:Label(row, nil, "small", "textMuted")
    row.rank:SetPoint("LEFT", P.sm, 0)
    row.rank:SetWidth(S.button)
    row.value = UI:Label(row, nil, "number", "text")
    row.value:SetJustifyH("RIGHT")
    row.value:SetPoint("RIGHT", -(P.sm + P.md), 0)
    row.value:SetWidth(P.xl * 4)
    row.details = UI:Label(row, "›", "heading", "accent")
    row.details:SetPoint("RIGHT", -P.xs, 0)
    row.status = UI:Label(row, nil, "small", "textDim")
    row.status:SetJustifyH("RIGHT")
    row.status:SetPoint("RIGHT", row.value, "LEFT", -P.sm, 0)
    row.status:SetWidth(P.xl * 4)
    row.name = UI:Label(row, nil, "body", "text")
    row.name:SetPoint("LEFT", row.rank, "RIGHT", P.xs, 0)
    row.name:SetMaxLines(1)

    row.bar = UI:ProgressBar(row, P.xl, Theme:Pixel(row) * 2, "accentDim")
    row.bar:SetPoint("BOTTOMLEFT", P.sm, P.xs)
    row.bar:SetPoint("BOTTOMRIGHT", -P.sm, P.xs)
    row:SetScript("OnClick", function(self) M:SelectSource(self.item) end)
    return row
end

local function updateRow(row, item, index)
    local isThreat = M.view == "threat"
    local status = isThreat and THREAT_STATUS[item.status]
    local perSecond = M.metric == "Dps" or M.metric == "Hps"
    row.rank:SetText(index)
    row.shade:SetShown(item.player == true)
    row.mark:SetShown(item.player == true)
    row.status:SetText(status and status[1] or "")
    Theme:Paint(row.status, status and status[2] or "textDim")
    row.name:SetPoint("RIGHT", status and row.status or row.value, "LEFT", -P.sm, 0)
    setName(row.name, item.name, item.player)
    setValue(row.value, item, M.view, perSecond)
    row.bar:SetShown(item.progress ~= nil)
    if item.progress then
        row.bar:SetProgress(item.progress)
        row.bar:SetColorKey(isThreat and "warning" or "accentDim")
    end
    row.details:SetShown(item.identity ~= nil)
    row:EnableMouse(item.identity ~= nil)
end

function M:BuildWindow()
    local window = UI:Window("BadbUICombat", MIN_W, DEFAULT_H, self.title, {
        subtitle = L["Dati nativi di Forever"], footer = true, strata = "MEDIUM", remember = false,
        resizable = true, minW = MIN_W, minH = MIN_H, maxW = MAX_W, maxH = MAX_H,
        onClose = function(closed)
            self.refreshTicket = nil
            self.selected = nil
            closed.list:SetData({})
            for _, row in ipairs(closed.list.rows) do
                row.item = nil
                row.name:SetText("")
                row.value:SetText("")
            end
            if self.frameDescriptor then self.frameDescriptor.movable = false end
            if FM.movers[FRAME_KEY] then FM.movers[FRAME_KEY]:Hide() end
        end,
    })
    self.window = window
    -- La posizione appartiene al profilo tramite FrameManager.
    window:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -P.xl, S.header + P.xl)
    window.badbPlaced = true

    self.view, self.metric, self.session = "meter", "DamageDone", "Current"
    local body = window.body
    window.tabs = UI:Tabs(body, {
        { id = "meter", text = L["Resoconto"] },
        { id = "threat", text = L["Minaccia"] },
    }, function(id, user)
        if user then self:SetTab(id) end
    end)
    window.tabs:SetPoint("TOPLEFT", P.md, 0)
    window.tabs:SetPoint("TOPRIGHT", -P.md, 0)

    local controls = CreateFrame("Frame", nil, body)
    controls:SetPoint("TOPLEFT", window.tabs, "BOTTOMLEFT", 0, -P.sm)
    controls:SetPoint("TOPRIGHT", window.tabs, "BOTTOMRIGHT", 0, -P.sm)
    controls:SetHeight(S.button)
    window.controls = controls
    window.metric = UI:Dropdown(controls, nil, Source.Metrics, function() return self.metric end, function(metric)
        self.metric = metric
        window.list:ScrollToIndex(1)
        self:RefreshWindow()
    end, { width = S.sidebar })
    window.metric:SetPoint("LEFT")
    window.session = UI:Dropdown(controls, nil, Source.Sessions, function() return self.session end, function(session)
        self.session = session
        window.list:ScrollToIndex(1)
        self:RefreshWindow()
    end, { width = S.sidebar })
    window.session:SetPoint("RIGHT")

    window.detail = CreateFrame("Frame", nil, body)
    window.detail:SetAllPoints(controls)
    local back = UI:Button(window.detail, L["Indietro"], P.xl * 4, S.button, function()
        self:SetTab("meter")
    end, "secondary")
    back:SetPoint("LEFT")
    window.detailTitle = UI:Label(window.detail, nil, "heading", "text")
    window.detailTitle:SetPoint("LEFT", back, "RIGHT", P.sm, 0)
    window.detailTitle:SetPoint("RIGHT")

    window.columns = CreateFrame("Frame", nil, body)
    window.columns:SetHeight(S.button)
    window.columnName = UI:Label(window.columns, nil, "small", "textDim")
    window.columnName:SetPoint("LEFT", P.sm + S.button + P.xs, 0)
    window.columnValue = UI:Label(window.columns, nil, "small", "textDim")
    window.columnValue:SetJustifyH("RIGHT")
    window.columnValue:SetPoint("RIGHT", -(P.sm + P.lg + P.md), 0)

    window.list = UI:ScrollList(body, S.row, createRow, updateRow)
    window.list:SetPoint("TOPLEFT", window.columns, "BOTTOMLEFT", 0, 0)
    window.list:SetPoint("BOTTOMRIGHT", -P.md, P.sm)

    window.empty = UI:Label(body, nil, "body", "textDim")
    window.empty:SetJustifyH("CENTER")
    window.empty:SetWordWrap(true)
    window.empty:SetPoint("TOPLEFT", window.columns, "BOTTOMLEFT", P.md, -P.lg)
    window.empty:SetPoint("TOPRIGHT", window.columns, "BOTTOMRIGHT", -P.md, -P.lg)
    window.footerText = UI:Label(window.footer, nil, "small", "textDim")
    window.footerText:SetPoint("LEFT", P.md, 0)
    window.footerText:SetPoint("RIGHT", -P.xl, 0)

    self.frameDescriptor = { frame = window, title = self.title, category = L["Gioco"], hideable = false, movable = false }
    FM:Register(FRAME_KEY, self.frameDescriptor)
    window.header:HookScript("OnDragStop", function()
        local point, relative, relPoint, x, y = window:GetPoint(1)
        if not point or (relative and relative ~= UIParent) or not x or not y then return end
        local frames = Badb.DB.profile.frames
        local config = frames[FRAME_KEY] or {}
        frames[FRAME_KEY] = config
        config.point, config.relPoint, config.x, config.y = point, relPoint, x, y
        Events:Fire("BADB_FRAME_CHANGED", FRAME_KEY, "position", config)
    end)
    window.grip:HookScript("OnMouseUp", function()
        self:Set("width", window:GetWidth())
        self:Set("height", window:GetHeight())
    end)
    window.OnOpen = function()
        self.frameDescriptor.movable = true
        window.metric:Refresh()
        window.session:Refresh()
        self:RefreshWindow()
    end
    self:ApplySize()
    return window
end

function M:RefreshWindow()
    local window = self.window
    if not window or not window:IsShown() then return end

    local isThreat, selected = self.view == "threat", self.selected
    window.controls:SetShown(not isThreat and not selected)
    window.detail:SetShown(selected ~= nil)
    if selected then window.detailTitle:SetText(selected.title) end
    local anchor = isThreat and window.tabs or window.controls
    window.columns:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -P.xs)
    window.columns:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -P.xs)

    local result, messages
    if isThreat then
        result, messages = Source.Threat(), THREAT_MESSAGES
    elseif selected then
        result, messages = Source.Breakdown(self.metric, self.session, selected.identity), SPELL_MESSAGES
    else
        result, messages = Source.Meter(self.metric, self.session), METER_MESSAGES
    end
    local perSecond = self.metric == "Dps" or self.metric == "Hps"
    window.columnName:SetText(selected and L["Magia"] or L["Partecipante"])
    window.columnValue:SetText(isThreat and L["Soglia aggro"] or (perSecond and L["Al secondo"] or L["Totale"]))
    if not isThreat and not selected then
        local available = result.state ~= "unavailable"
        window.metric:SetEnabled(available)
        window.session:SetEnabled(available)
    end
    window.columns:SetShown(result.state == "ready")
    window.list:SetData(result.rows)
    window.empty:SetText(messages[result.state] or "")
    window.empty:SetShown(result.state ~= "ready")
    local footer = ""
    if result.limited and result.state == "ready" then
        footer = L["Alcuni dati sono riservati dal client."]
    elseif isThreat and result.state == "ready" then
        footer = L["100% indica la soglia di aggro alla distanza del partecipante."]
    elseif result.total and result.state == "ready" then
        footer = L["Totale %s"]:format(publicNumber(result.total, false))
        if result.duration then
            local seconds = math.floor(result.duration)
            footer = footer .. ("  •  %d:%02d"):format(math.floor(seconds / 60), seconds % 60)
        end
    end
    window.footerText:SetText(footer)
end

function M:QueueRefresh()
    if self.refreshTicket or not self.window or not self.window:IsShown() then return end
    local ticket = {}
    self.refreshTicket = ticket
    Badb.Compat.After(REFRESH_DELAY, function()
        if self.refreshTicket ~= ticket then return end
        self.refreshTicket = nil
        if self:IsEnabled() then self:RefreshWindow() end
    end)
end

function M:Open(tab)
    if not self:IsEnabled() then return false, L["Attiva Statistiche di combattimento in /badb."] end
    local window = self.window or self:BuildWindow()
    if tab == "meter" or tab == "threat" then window.tabs:Select(tab, true) end
    window:Show()
    return true
end

local function isEventAvailable(event)
    local validate = C_EventUtils and C_EventUtils.IsEventValid
    if type(validate) ~= "function" then return true end
    local ok, valid = pcall(validate, event)
    return ok and not IsSecret(valid) and valid == true
end

function M:OnEnable()
    for _, event in ipairs(METER_EVENTS) do
        if isEventAvailable(event) then
            self:On(event, function(name)
                if self.view ~= "meter" then return end
                if name == "DAMAGE_METER_RESET" and self.window then
                    self.session, self.selected = "Current", nil
                    self.window.session:Refresh()
                end
                self:QueueRefresh()
            end)
        end
    end
    for _, event in ipairs(THREAT_EVENTS) do
        self:On(event, function() if self.view == "threat" then self:QueueRefresh() end end)
    end
    self:On("PLAYER_REGEN_ENABLED", function() self:QueueRefresh() end)
    self:On("PLAYER_REGEN_DISABLED", function() self:QueueRefresh() end)
    self:On("PLAYER_ENTERING_WORLD", function(_, initialLogin, reloading)
        if (initialLogin or reloading) and self:Get("showAtLogin") == true then self:Open() end
        self:QueueRefresh()
    end)
end

function M:OnDisable()
    self.refreshTicket = nil
    if self.window then self.window:Hide() end
end

function M:OnProfileChanged()
    self:ApplySize()
    self:QueueRefresh()
end

M.options = {
    { type = "execute", label = L["Apri statistiche di combattimento"], func = function()
        local ok, err = M:Open()
        if not ok then Logger:Warn(err) end
    end },
    { type = "toggle", path = "showAtLogin", label = L["Apri il pannello all'accesso"] },
    { type = "execute", label = L["Leggi la guida al contatore"], func = function()
        if Badb.Guides then Badb.Guides:Open(GUIDE_ID) end
    end },
}

M.commands = {
    combat = {
        help = L["combat [threat] - apre le statistiche o la minaccia del bersaglio"],
        fn = function(args)
            local tab = strtrim(args or ""):lower() == "threat" and "threat" or "meter"
            local ok, err = M:Open(tab)
            if not ok then Logger:Warn(err) end
        end,
    },
}
