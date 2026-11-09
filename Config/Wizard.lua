-- BadbUI - Configurazione guidata (onboarding)
-- Finestra a passi in stile "hub": rail di navigazione a sinistra, contenuto a destra,
-- barra di avanzamento in basso. Porta a un layout completo in pochi click:
--   Benvenuto -> Ruolo -> Contenuto -> Dettagli -> Riepilogo -> Applica
-- oppure "Applica consigliato" direttamente dal primo passo.
-- Usa il design system (Badb.Theme / Badb.UI) se presente, altrimenti un fallback locale
-- con la stessa palette, cosi' il wizard funziona anche da solo.
local _, ns = ...
local Badb = ns.Badb
local DB, Events, Presets, Logger = Badb.DB, Badb.Events, Badb.Presets, Badb.Logger

local Wizard = { step = 1, choices = {} }
Badb.Wizard = Wizard

------------------------------------------------------------------------------
-- Tema: adattatore verso Badb.Theme con fallback "Dusk"
------------------------------------------------------------------------------
local FALLBACK = {
    bg = { 0.075, 0.086, 0.133, 0.97 }, sidebar = { 0.060, 0.068, 0.106, 1 },
    panel = { 0.110, 0.129, 0.200, 1 }, panelAlt = { 0.137, 0.165, 0.247, 1 },
    header = { 0.090, 0.105, 0.165, 1 }, border = { 0.180, 0.208, 0.314, 1 },
    hover = { 0.165, 0.196, 0.290, 1 }, selected = { 0.200, 0.180, 0.150, 1 },
    accent = { 0.902, 0.729, 0.400, 1 }, accentDim = { 0.55, 0.45, 0.27, 1 },
    text = { 0.91, 0.90, 0.87, 1 }, textDim = { 0.70, 0.71, 0.76, 1 }, textMuted = { 0.54, 0.56, 0.65, 1 },
    success = { 0.40, 0.80, 0.60, 1 },
}
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function color(key)
    local T = Badb.Theme
    if T and T.Get then
        local r, g, b, a = T:Get(key)
        if r then return r, g, b, a or 1 end
    end
    local c = FALLBACK[key] or FALLBACK.text
    return c[1], c[2], c[3], c[4]
end

local function fill(region, key, alphaMul)
    local r, g, b, a = color(key)
    region:SetColorTexture(r, g, b, (a or 1) * (alphaMul or 1))
end

local function skin(frame, bgKey, borderKey)
    local T = Badb.Theme
    if T and T.Skin then
        T:Skin(frame, { bg = bgKey, border = borderKey })
        return
    end
    if not frame.SetBackdrop then Mixin(frame, BackdropTemplateMixin) end
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(color(bgKey or "panel"))
    frame:SetBackdropBorderColor(color(borderKey or "border"))
end

local function setBorder(frame, key)
    if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(color(key)) end
end

local function label(parent, text, size, key, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local T = Badb.Theme
    local font = (T and T.fonts and (size >= 16 and T.fonts.header or T.fonts.body)) or STANDARD_TEXT_FONT
    fs:SetFont(font, size, flags or "")
    fs:SetTextColor(color(key or "text"))
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end

local function button(parent, text, w, onClick, variant)
    local UI = Badb.UI
    if UI and UI.Button then return UI.Button(parent, text, w, 26, onClick, variant) end
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, 26)
    skin(b, variant == "primary" and "accent" or "panelAlt", variant == "primary" and "accent" or "border")
    b.text = label(b, text, 12, variant == "primary" and "bg" or "text")
    b.text:SetPoint("CENTER")
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) setBorder(self, "accent") end)
    b:SetScript("OnLeave", function(self) setBorder(self, variant == "primary" and "accent" or "border") end)
    function b:SetEnabled(on)
        self:EnableMouse(on); self:SetAlpha(on and 1 or 0.4)
    end
    function b:SetLabel(t) self.text:SetText(t) end
    return b
end

local function setButtonText(b, t)
    if b.SetLabel then b:SetLabel(t) elseif b.SetText then b:SetText(t) end
end

local function toggle(parent, text, get, set)
    local UI = Badb.UI
    if UI and UI.Toggle then return UI.Toggle(parent, text, get, set) end
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    local t = cb.text or cb.Text
    if t then t:SetText(text); t:SetTextColor(color("text")) end
    cb.Refresh = function(self) self:SetChecked(get() and true or false) end
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    cb:Refresh()
    return cb
end

------------------------------------------------------------------------------
-- Card selezionabile (ruolo / contenuto)
------------------------------------------------------------------------------
local function selectCard(parent, w, h, spec, isSelected, onSelect)
    local c = CreateFrame("Button", nil, parent, "BackdropTemplate")
    c:SetSize(w, h)
    skin(c, "panel", "border")
    local icon = c:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36); icon:SetPoint("TOPLEFT", 12, -12)
    icon:SetTexture(spec.icon); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local title = label(c, spec.title, 15, "text")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    local desc = label(c, spec.description, 11, "textDim")
    desc:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("RIGHT", -12, 0)
    desc:SetWordWrap(true)
    local band = c:CreateTexture(nil, "OVERLAY") -- banda accento a sinistra quando selezionata
    band:SetPoint("TOPLEFT", 1, -1); band:SetPoint("BOTTOMLEFT", 1, 1); band:SetWidth(3)
    fill(band, "accent")
    function c:Refresh()
        local sel = isSelected()
        band:SetShown(sel)
        setBorder(self, sel and "accent" or "border")
        if self.SetBackdropColor then self:SetBackdropColor(color(sel and "selected" or "panel")) end
    end
    c:SetScript("OnClick", function() onSelect(); Wizard:Refresh() end)
    c:SetScript("OnEnter", function(self) if not isSelected() then setBorder(self, "accentDim") end end)
    c:SetScript("OnLeave", function(self) self:Refresh() end)
    c:Refresh()
    return c
end

------------------------------------------------------------------------------
-- Finestra
------------------------------------------------------------------------------
local STEPS = {
    { key = "welcome", title = "Benvenuto" },
    { key = "role", title = "Ruolo" },
    { key = "content", title = "Contenuto" },
    { key = "details", title = "Dettagli" },
    { key = "summary", title = "Riepilogo" },
}

local W_WIDTH, W_HEIGHT, RAIL = 760, 500, 180
local frame, pages, railItems, refreshers = nil, {}, {}, {}

local function onRefresh(fn) refreshers[#refreshers + 1] = fn end

local function buildShell()
    local f = CreateFrame("Frame", "BadbUIWizard", UIParent, "BackdropTemplate")
    f:SetSize(W_WIDTH, W_HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    skin(f, "bg", "border")
    tinsert(UISpecialFrames, "BadbUIWizard")

    -- Banda di intestazione con "stelle" (puntini accento) e titolo
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 1, -1); header:SetPoint("TOPRIGHT", -1, -1); header:SetHeight(48)
    local hbg = header:CreateTexture(nil, "BACKGROUND"); hbg:SetAllPoints(); fill(hbg, "header")
    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1); fill(line, "accent", 0.6)
    local seed = { 0.12, 0.31, 0.47, 0.58, 0.66, 0.79, 0.88, 0.95 }
    for i, x in ipairs(seed) do
        local s = header:CreateTexture(nil, "ARTWORK")
        local sz = (i % 3 == 0) and 2 or 1
        s:SetSize(sz, sz)
        s:SetPoint("TOPLEFT", math.floor(W_WIDTH * x), -6 - ((i * 7) % 30))
        fill(s, "accent", 0.35 + (i % 4) * 0.15)
    end
    local title = label(header, "BADB|cffe6ba66UI|r", 18, "text")
    title:SetPoint("LEFT", 18, 0)
    local subtitle = label(header, "Configurazione guidata", 12, "textMuted")
    subtitle:SetPoint("LEFT", title, "RIGHT", 12, -1)
    local close = CreateFrame("Button", nil, header, "UIPanelCloseButtonNoScripts")
    close:SetPoint("RIGHT", -6, 0)
    close:SetScript("OnClick", function() Wizard:Close() end)

    -- Rail di navigazione
    local rail = CreateFrame("Frame", nil, f)
    rail:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    rail:SetPoint("BOTTOMLEFT", 1, 1)
    rail:SetWidth(RAIL)
    local rbg = rail:CreateTexture(nil, "BACKGROUND"); rbg:SetAllPoints(); fill(rbg, "sidebar")
    for i, s in ipairs(STEPS) do
        local item = CreateFrame("Button", nil, rail)
        item:SetSize(RAIL, 36)
        item:SetPoint("TOPLEFT", 0, -12 - (i - 1) * 38)
        local hl = item:CreateTexture(nil, "BACKGROUND"); hl:SetAllPoints(); fill(hl, "hover")
        local mark = item:CreateTexture(nil, "ARTWORK")
        mark:SetPoint("TOPLEFT"); mark:SetPoint("BOTTOMLEFT"); mark:SetWidth(3); fill(mark, "accent")
        local num = label(item, tostring(i), 12, "textMuted")
        num:SetPoint("LEFT", 18, 0)
        local txt = label(item, s.title, 13, "textDim")
        txt:SetPoint("LEFT", 40, 0)
        item:SetScript("OnClick", function() if i <= Wizard.maxStep then Wizard:Go(i) end end)
        item.Refresh = function()
            local current, done = Wizard.step == i, i < Wizard.step
            hl:SetShown(current); mark:SetShown(current)
            txt:SetTextColor(color(current and "text" or (i <= Wizard.maxStep and "textDim" or "textMuted")))
            num:SetText(done and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t" or tostring(i))
            num:SetTextColor(color(current and "accent" or "textMuted"))
        end
        railItems[i] = item
    end
    local version = label(rail, "v" .. (Badb.version or "dev"), 10, "textMuted")
    version:SetPoint("BOTTOMLEFT", 18, 12)

    -- Corpo e piede
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", rail, "TOPRIGHT", 24, -20)
    body:SetPoint("BOTTOMRIGHT", -24, 64)
    f.body = body

    local footer = CreateFrame("Frame", nil, f)
    footer:SetPoint("BOTTOMLEFT", rail, "BOTTOMRIGHT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(52)
    local fline = footer:CreateTexture(nil, "ARTWORK")
    fline:SetPoint("TOPLEFT"); fline:SetPoint("TOPRIGHT"); fline:SetHeight(1); fill(fline, "border")
    local track = footer:CreateTexture(nil, "ARTWORK")
    track:SetPoint("LEFT", 24, 0); track:SetSize(180, 4); fill(track, "panelAlt")
    local prog = footer:CreateTexture(nil, "OVERLAY")
    prog:SetPoint("LEFT", track); prog:SetHeight(4); fill(prog, "accent")
    local progText = label(footer, "", 11, "textMuted")
    progText:SetPoint("LEFT", track, "RIGHT", 10, 0)
    onRefresh(function()
        prog:SetWidth(math.max(1, 180 * Wizard.step / #STEPS))
        progText:SetFormattedText("Passo %d di %d", Wizard.step, #STEPS)
    end)

    f.next = button(footer, "Avanti", 120, function() Wizard:Next() end, "primary")
    f.next:SetPoint("RIGHT", -24, 0)
    f.back = button(footer, "Indietro", 100, function() Wizard:Go(Wizard.step - 1) end, "secondary")
    f.back:SetPoint("RIGHT", f.next, "LEFT", -8, 0)
    f.skip = button(footer, "Salta", 80, function()
        DB.sv.global.wizardDone = true
        Wizard:Close()
    end, "ghost")
    f.skip:SetPoint("RIGHT", f.back, "LEFT", -8, 0)

    -- Applica i cambi di tema del design system
    Events:On(Wizard, "BADB_THEME_CHANGED", function()
        if frame then frame:Hide(); frame = nil; pages = {}; railItems = {}; refreshers = {} end
        if Wizard.wasOpen then Wizard:Open() end
    end)
    return f
end

------------------------------------------------------------------------------
-- Pagine
------------------------------------------------------------------------------
local function pageHeading(page, title, text)
    local h = label(page, title, 20, "text")
    h:SetPoint("TOPLEFT", 0, 0)
    local p = label(page, text, 12, "textDim")
    p:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -8)
    p:SetPoint("RIGHT", 0, 0)
    p:SetWordWrap(true)
    return p
end

local Builders = {}

Builders.welcome = function(page)
    local intro = pageHeading(page, "Il tuo layout in un minuto",
        "BadbUI configura nameplate, frame di raid e party, scala dell'interfaccia ed elementi superflui in base al tuo ruolo e al contenuto che giochi. Viene creato un nuovo profilo: quello attuale resta intatto e puoi tornare indietro in qualsiasi momento.")

    local quick = CreateFrame("Frame", nil, page, "BackdropTemplate")
    quick:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -24)
    quick:SetPoint("RIGHT", 0, 0)
    quick:SetHeight(120)
    skin(quick, "panel", "accentDim")
    local qt = label(quick, "Consigliato per questo personaggio", 14, "accent")
    qt:SetPoint("TOPLEFT", 16, -14)
    local qd = label(quick, "", 12, "textDim")
    qd:SetPoint("TOPLEFT", qt, "BOTTOMLEFT", 0, -8)
    qd:SetPoint("RIGHT", -16, 0)
    local apply = button(quick, "Applica consigliato", 170, function()
        local name = Presets:Apply(Presets:Build(Presets:Recommend()))
        if name then DB.sv.global.wizardDone = true; Wizard:Close() end
    end, "primary")
    apply:SetPoint("BOTTOMLEFT", 16, 14)
    onRefresh(function()
        local r = Presets:Recommend()
        local c, role = Presets.content[r.content], Presets.roles[r.role]
        qd:SetFormattedText("%s  ·  %s\nRilevato da specializzazione, livello e gruppo.",
            role and role.title or "?", c and c.title or "?")
    end)

    local custom = label(page, "Oppure premi |cffe6ba66Avanti|r per scegliere tu ogni dettaglio.", 12, "textMuted")
    custom:SetPoint("TOPLEFT", quick, "BOTTOMLEFT", 0, -18)

    local undo = button(page, "Annulla ultimo preset", 170, function() Presets:Undo(); Wizard:Refresh() end, "ghost")
    undo:SetPoint("BOTTOMLEFT", 0, 0)
    onRefresh(function() undo:SetShown(Presets:CanUndo()) end)
end

local function cardGrid(page, anchor, ids, registry, field)
    local bodyW = W_WIDTH - RAIL - 48
    local cols = #ids == 3 and 3 or 2
    local gap = 12
    local w = math.floor((bodyW - gap * (cols - 1)) / cols)
    local h = cols == 3 and 150 or 112
    for i, id in ipairs(ids) do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        local card = selectCard(page, w, h, registry[id],
            function() return Wizard.choices[field] == id end,
            function() Wizard.choices[field] = id end)
        card:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", col * (w + gap), -20 - row * (h + gap))
        onRefresh(function() card:Refresh() end)
    end
end

Builders.role = function(page)
    local p = pageHeading(page, "Che ruolo giochi?",
        "Il ruolo decide dimensioni dei frame di gruppo, informazioni mostrate e quanto risaltano le nameplate.")
    cardGrid(page, p, Presets.roleOrder, Presets.roles, "role")
end

Builders.content = function(page)
    local p = pageHeading(page, "Cosa giochi di piu'?",
        "Puoi rifare la configurazione per ogni attivita' e associare un profilo a ciascuna specializzazione.")
    cardGrid(page, p, Presets.contentOrder, Presets.content, "content")
end

Builders.details = function(page)
    local p = pageHeading(page, "Ultimi ritocchi", "Opzioni generali, modificabili in seguito dal pannello BadbUI.")
    local items = {
        { "pixelPerfect", "Scala interfaccia pixel perfect (bordi nitidi a ogni risoluzione)" },
        { "hideClutter", "Nascondi micro menu, barra borse e barra esperienza" },
        { "friendlyPlates", "Mostra le nameplate degli alleati" },
    }
    local prev = p
    for _, it in ipairs(items) do
        local key = it[1]
        local t = toggle(page, it[2], function() return Wizard.choices[key] end,
            function(v) Wizard.choices[key] = v end)
        t:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", prev == p and 0 or 0, prev == p and -20 or -10)
        onRefresh(function() if t.Refresh then t:Refresh() end end)
        prev = t
    end
end

Builders.summary = function(page)
    local p = pageHeading(page, "Riepilogo", "Ecco cosa verra' applicato. Premi |cffe6ba66Applica|r per creare il profilo.")
    local box = CreateFrame("Frame", nil, page, "BackdropTemplate")
    box:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 0, -18)
    box:SetPoint("RIGHT", 0, 0)
    box:SetHeight(220)
    skin(box, "panel", "border")
    local profile = label(box, "", 13, "accent")
    profile:SetPoint("TOPLEFT", 16, -14)
    local lines = label(box, "", 12, "text")
    lines:SetPoint("TOPLEFT", profile, "BOTTOMLEFT", 0, -10)
    lines:SetPoint("RIGHT", -16, 0)
    lines:SetSpacing(6)
    local note = label(page, "Il profilo attuale non viene modificato. /badb undo per tornare indietro.", 11, "textMuted")
    note:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -10)
    onRefresh(function()
        local spec = Presets:Build(Wizard.choices)
        profile:SetText("Nuovo profilo: Badb - " .. spec.title)
        local out = {}
        for _, l in ipairs(Presets:Describe(spec)) do out[#out + 1] = "|cffe6ba66•|r  " .. l end
        lines:SetText(table.concat(out, "\n"))
    end)
end

------------------------------------------------------------------------------
-- Navigazione
------------------------------------------------------------------------------
local function pageFor(i)
    if pages[i] then return pages[i] end
    local page = CreateFrame("Frame", nil, frame.body)
    page:SetAllPoints()
    Builders[STEPS[i].key](page)
    pages[i] = page
    return page
end

function Wizard:Refresh()
    if not frame then return end
    for _, item in ipairs(railItems) do item:Refresh() end
    for _, fn in ipairs(refreshers) do pcall(fn) end
    frame.back:SetEnabled(self.step > 1)
    setButtonText(frame.next, self.step == #STEPS and "Applica" or "Avanti")
end

function Wizard:Go(i)
    if i < 1 or i > #STEPS then return end
    self.step = i
    self.maxStep = math.max(self.maxStep or 1, i)
    for idx, page in pairs(pages) do page:SetShown(idx == i) end
    pageFor(i):Show()
    self:Refresh()
end

function Wizard:Next()
    if self.step < #STEPS then return self:Go(self.step + 1) end
    local name = Presets:Apply(Presets:Build(self.choices))
    if name then
        DB.sv.global.wizardDone = true
        self:Close()
    end
end

function Wizard:Open()
    if InCombatLockdown() then
        Logger:Info("La configurazione guidata si aprira' a fine combattimento")
        Events:RunOutOfCombat("wizardOpen", function() Wizard:Open() end)
        return
    end
    if not frame then frame = buildShell() end
    local rec = Presets:Recommend()
    for k, v in pairs(rec) do if self.choices[k] == nil then self.choices[k] = v end end
    self.maxStep = self.maxStep or 1
    self.wasOpen = true
    frame:Show()
    self:Go(self.step or 1)
end

function Wizard:Close()
    self.wasOpen = false
    if frame then frame:Hide() end
end

function Wizard:Toggle()
    if frame and frame:IsShown() then self:Close() else self:Open() end
end

-- Primo avvio: proponi il wizard una volta per account, dopo che l'interfaccia si e' assestata.
Events:On(Wizard, "PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
    Events:Off(Wizard, "PLAYER_ENTERING_WORLD")
    if DB.sv and not DB.sv.global.wizardDone and (isLogin or isReload) then
        C_Timer.After(3, function() Wizard:Open() end)
    end
end)
