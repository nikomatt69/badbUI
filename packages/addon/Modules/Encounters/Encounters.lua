local _, ns = ...
local Badb, S, Journal = ns.Badb, ns.EncounterSource, ns.EncounterJournal
local L, UI, Theme = Badb.L, Badb.UI, Badb.Theme
local Logger, IsSecret = Badb.Logger, Badb.Compat.IsSecret
local FM, Events = Badb.FrameManager, Badb.Events
local P, Size = Theme.spacing, Theme.sizes
local FRAME, GUIDE = "Encounters", "suite-encounters:overview"
local TABS = {
    { id = "boss", text = L["Boss"] },
    { id = "pvp", text = L["Campi di battaglia"] },
    { id = "visits", text = L["Visite"] },
    { id = "lockouts", text = L["Salvataggi"] },
}
local EMPTY = {
    boss = L["Nessun timer nativo attivo per questo incontro."],
    pvp = L["Nessuna coda o partita in corso."],
    visits = L["Le visite iniziano a comparire al tuo ingresso in un'istanza."],
    lockouts = L["Nessun salvataggio attivo per questo personaggio."],
}
local UNAVAILABLE = {
    boss = L["La cronologia degli incontri non è disponibile su questo client."],
    pvp = L["Lo stato delle code PvP non è disponibile su questo client."],
    lockouts = L["I salvataggi delle istanze non sono disponibili su questo client."],
}

local M = Badb.Modules:New("Encounters", {
    title = L["Incontri e istanze"], category = L["Gioco"],
    description = L["Timer dei boss, code PvP, visite registrate e salvataggi del personaggio."],
    defaults = { enabled = true, trackVisits = true, autoOpenBoss = false },
    page = {
        title = L["Incontri e istanze"], category = L["Gioco"], order = 40,
        keywords = { "boss", "bigwigs", "capping", "nova", L["Campi di battaglia"], L["Salvataggi"] },
    },
    replaces = {
        { addon = "BigWigs", title = "BigWigs", coverage = "partial",
          note = L["Timer nativi degli incontri. Avvisi personalizzati, moduli specifici e suoni di BigWigs restano scoperti."] },
        { addon = "BigWigs_Core", title = "BigWigs Core", coverage = "partial",
          note = L["Mostra i timer forniti dal client per l'incontro."] },
        { addon = "BigWigs_Options", title = "BigWigs Options", coverage = "partial",
          note = L["Impostazioni del pannello BadbUI e apertura all'inizio del boss."] },
        { addon = "BigWigs_Plugins", title = "BigWigs Plugins", coverage = "partial",
          note = L["Mostra i timer forniti dal client per l'incontro."] },
        { addon = "Capping", title = "Capping", coverage = "partial",
          note = L["Code, inviti e durata delle partite. Timer degli obiettivi e previsioni del punteggio restano scoperti."] },
        { addon = "Capping_Options", title = "Capping Options", coverage = "partial",
          note = L["Configurazione del pannello condivisa con il resto di BadbUI."] },
        { addon = "NovaInstanceTracker", title = "Nova Instance Tracker", coverage = "partial",
          note = L["Registro delle visite e salvataggi attivi. Limiti orari e condivisione di gruppo restano scoperti."] },
    },
})
Badb.Encounters = M

local function createRow(list)
    local row = CreateFrame("Frame", nil, list)
    row.name = UI:Label(row, nil, "body", "text")
    row.name:SetPoint("TOPLEFT", P.sm, -P.xs)
    row.value = UI:Label(row, nil, "number", "text")
    row.value:SetPoint("RIGHT", -P.sm, 0)
    row.value:SetWidth(P.xl * 6)
    row.value:SetJustifyH("RIGHT")
    row.name:SetPoint("TOPRIGHT", -(P.xl * 6 + P.sm * 2), -P.xs)
    row.detail = UI:Label(row, nil, "small", "textDim")
    row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, 0)
    row.detail:SetPoint("TOPRIGHT", row.name, "BOTTOMRIGHT", 0, 0)
    row.progress = UI:ProgressBar(row, P.xl, Theme:Pixel(row) * 2, "accentDim")
    row.progress:SetPoint("BOTTOMLEFT", P.sm, Theme:Pixel(row))
    row.progress:SetPoint("BOTTOMRIGHT", -P.sm, Theme:Pixel(row))
    return row
end

local function updateRow(row, item)
    local name = item.name
    if not IsSecret(name) or not pcall(row.name.SetText, row.name, name) then
        row.name:SetText(S.Plain(name) or L["Sconosciuto"])
    end
    row.detail:SetText(item.detail or "")
    row.value:SetText(item.value or "")
    Theme:Paint(row.value, item.color or "text")
    row.progress:SetShown(item.progress ~= nil)
    if item.progress then row.progress:SetProgress(item.progress) end
end

function M:BuildWindow()
    local window = UI:Window("BadbUIEncounters", Size.sidebar * 2 + P.xl * 3,
        Size.header + Size.row * 9, self.title, {
            footer = true, strata = "MEDIUM", remember = false,
            onClose = function(closed)
                self.automaticallyOpened, self.refreshTicket = nil, nil
                closed:SetScript("OnUpdate", nil)
                self.frameDescriptor.movable = false
                if FM.movers[FRAME] then FM.movers[FRAME]:Hide() end
                closed.list:SetData({})
                for _, row in ipairs(closed.list.rows) do
                    row.item = nil
                    row.name:SetText("")
                end
            end,
        })
    self.window, self.view = window, "boss"
    window.badbPlaced = true
    window:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -P.xl, -Size.header * 3)
    window.tabs = UI:Tabs(window.body, TABS, function(id, user)
        if not user then return end
        self.view = id
        if id ~= "boss" then self.automaticallyOpened = nil end
        window.list:ScrollToIndex(1)
        self:RequestLockouts()
        self:Refresh()
    end)
    window.tabs:SetPoint("TOPLEFT", P.md, 0)
    window.tabs:SetPoint("TOPRIGHT", -P.md, 0)
    window.list = UI:ScrollList(window.body, Size.row + P.xs, createRow, updateRow)
    window.list:SetPoint("TOPLEFT", window.tabs, "BOTTOMLEFT", 0, -P.xs)
    window.list:SetPoint("BOTTOMRIGHT", -P.md, P.sm)
    window.empty = UI:Label(window.body, nil, "body", "textDim")
    window.empty:SetWordWrap(true)
    window.empty:SetPoint("TOPLEFT", window.tabs, "BOTTOMLEFT", P.sm, -P.lg)
    window.empty:SetPoint("TOPRIGHT", window.tabs, "BOTTOMRIGHT", -P.sm, -P.lg)
    window.footerText = UI:Label(window.footer, nil, "small", "textDim")
    window.footerText:SetPoint("LEFT", P.md, 0)
    window.footerText:SetPoint("RIGHT", -P.md, 0)
    self.frameDescriptor = { frame = window, title = self.title, category = L["Gioco"], movable = false, hideable = false }
    FM:Register(FRAME, self.frameDescriptor)
    window.header:HookScript("OnDragStop", function()
        local point, relative, relPoint, x, y = window:GetPoint(1)
        if not point or (relative and relative ~= UIParent) or not x or not y then return end
        local frames = Badb.DB.profile.frames
        local config = frames[FRAME] or {}
        frames[FRAME] = config
        config.point, config.relPoint, config.x, config.y = point, relPoint, x, y
        Events:Fire("BADB_FRAME_CHANGED", FRAME, "position", config)
    end)
    window.OnOpen = function()
        self.frameDescriptor.movable = true
        self:RequestLockouts()
        self:Refresh()
    end
    return window
end

function M:RequestLockouts()
    if self.view ~= "lockouts" or not self.window:IsShown() or InCombatLockdown() then return end
    local ok, now = S.Call(GetTime)
    now = ok and S.Number(now)
    if self.lastRaidInfo and now and now - self.lastRaidInfo < 10 then return end
    self.lastRaidInfo = now or nil
    S.Call(RequestRaidInfo)
end

local function tick(window, elapsed)
    window.tickElapsed = (window.tickElapsed or 0) + elapsed
    if window.tickElapsed < (M.view == "boss" and 0.25 or 1) then return end
    window.tickElapsed = 0
    M:Refresh()
end

function M:Refresh()
    local window = self.window
    if not window or not window:IsShown() then return end
    local view, rows, status = self.view
    if view == "boss" then rows, status = S.Timeline()
    elseif view == "pvp" then rows, status = S.Battlegrounds()
    elseif view == "lockouts" then rows, status = S.Lockouts()
    else rows = Journal:Rows() end

    window.list:SetData(rows)
    local empty = EMPTY[view]
    if status == "unavailable" then empty = UNAVAILABLE[view]
    elseif status == "restricted" then empty = L["Il client riserva questi dati."]
    elseif status == "disabled" then empty = L["Attiva la cronologia degli incontri nelle opzioni di WoW."] end
    window.empty:SetText(empty or "")
    window.empty:SetShown(#rows == 0)
    local footer = ""
    if status == "restricted" and #rows > 0 then footer = L["Alcuni dati sono riservati dal client."]
    elseif view == "visits" and self:Get("trackVisits") ~= true then footer = L["Registrazione delle visite in pausa."]
    elseif view == "visits" then footer = L["Visite degli ultimi 90 giorni su questo account."]
    elseif view == "lockouts" then footer = L["Tempo rimanente al ripristino del salvataggio."] end
    window.footerText:SetText(footer)
    if view ~= "visits" and #rows > 0 then window:SetScript("OnUpdate", tick)
    else window:SetScript("OnUpdate", nil) end
end

function M:QueueRefresh(view)
    if (view and self.view ~= view) or self.refreshTicket or not self.window or not self.window:IsShown() then return end
    local ticket = {}
    self.refreshTicket = ticket
    Badb.Compat.After(0.12, function()
        if self.refreshTicket ~= ticket then return end
        self.refreshTicket = nil
        if self:IsEnabled() then self:Refresh() end
    end)
end

function M:Open(view, automatic)
    if not self:IsEnabled() then return false, L["Attiva Incontri e istanze in /badb."] end
    local window = self.window or self:BuildWindow()
    if not automatic then self.automaticallyOpened = nil
    elseif not window:IsShown() then self.automaticallyOpened = true end
    for _, tab in ipairs(TABS) do
        if view == tab.id then window.tabs:Select(view, true); break end
    end
    window:Show()
    return true
end

function M:OnInitialize()
    Journal:Initialize()
end

local function canListen(event)
    local validate = C_EventUtils and C_EventUtils.IsEventValid
    if type(validate) ~= "function" then return true end
    local ok, result = S.Call(validate, event)
    return ok and not IsSecret(result) and result == true
end

function M:OnEnable()
    local groups = {
        boss = {
            "ENCOUNTER_TIMELINE_EVENT_ADDED", "ENCOUNTER_TIMELINE_EVENT_REMOVED",
            "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED", "ENCOUNTER_TIMELINE_STATE_UPDATED",
            "ENCOUNTER_TIMELINE_VIEW_ACTIVATED", "ENCOUNTER_TIMELINE_VIEW_DEACTIVATED",
        },
        pvp = { "UPDATE_BATTLEFIELD_STATUS" },
        lockouts = { "UPDATE_INSTANCE_INFO" },
    }
    for view, events in pairs(groups) do
        for _, event in ipairs(events) do
            if canListen(event) then self:On(event, function() self:QueueRefresh(view) end) end
        end
    end
    self:On("PLAYER_ENTERING_WORLD", function()
        if self:Get("trackVisits") == true then Journal:Observe() end
        self:QueueRefresh()
    end)
    self:On("ZONE_CHANGED_NEW_AREA", function()
        if self:Get("trackVisits") == true then Journal:Observe() end
        self:QueueRefresh()
    end)
    self:On("ENCOUNTER_START", function()
        if self:Get("autoOpenBoss") == true and (not self.window or not self.window:IsShown()) then
            local _, state = S.Timeline()
            if state ~= "unavailable" and state ~= "disabled" then self:Open("boss", true) end
        end
        self:QueueRefresh("boss")
    end)
    self:On("ENCOUNTER_END", function(_, _, boss, _, _, success)
        if self:Get("trackVisits") == true then Journal:EncounterEnd(boss, success) end
        if self.automaticallyOpened then self.window:Hide() end
        self:QueueRefresh()
    end)
    self:On("PLAYER_REGEN_ENABLED", function()
        if self.window and self.window:IsShown() then self:RequestLockouts() end
        self:QueueRefresh()
    end)
    if self:Get("trackVisits") == true then Journal:Observe() end
end

function M:OnDisable()
    self.refreshTicket = nil
    if self.window then self.window:Hide() end
end

function M:OnProfileChanged()
    self:QueueRefresh()
end

M.options = {
    { type = "execute", label = L["Apri Incontri e istanze"], func = function()
        local ok, err = M:Open()
        if not ok then Logger:Warn(err) end
    end },
    { type = "toggle", path = "autoOpenBoss", label = L["Apri il pannello all'inizio di un incontro"] },
    { type = "toggle", path = "trackVisits", label = L["Registra le visite nelle istanze"] },
    { type = "execute", label = L["Leggi la guida a incontri e istanze"], func = function()
        if Badb.Guides then Badb.Guides:Open(GUIDE) end
    end },
}
M.commands = {
    encounters = {
        help = L["encounters [boss|pvp|visits|lockouts] - apre incontri e istanze"],
        fn = function(args)
            local view = strtrim(args or ""):lower()
            local ok, err = M:Open(view ~= "" and view or nil)
            if not ok then Logger:Warn(err) end
        end,
    },
}
