-- BadbUI - UI: finestre, tab e navigazione laterale.
-- La finestra e' la "shell" di tutte le schermate BadbUI:
--   ┌ sidebar ┬ header (cielo notturno, titolo, sottotitolo, chiudi) ┐
--   │  nav    ├ tab (opzionali)                                       │
--   │         │ body                                                  │
--   └─────────┴ footer (opzionale)                                    ┘
local _, ns = ...
local Badb = ns.Badb
local Theme, UI = Badb.Theme, Badb.UI

---------------------------------------------------------------------------
-- Finestra
---------------------------------------------------------------------------

local function windowStore()
    if type(BadbUIDB) ~= "table" then return nil end
    BadbUIDB.global = BadbUIDB.global or {}
    BadbUIDB.global.windows = BadbUIDB.global.windows or {}
    return BadbUIDB.global.windows
end

local function savePosition(f)
    local db = windowStore()
    if not db or not f.badbName then return end
    local point, _, relPoint, x, y = f:GetPoint(1)
    db[f.badbName] = { point = point, relPoint = relPoint, x = x, y = y, w = f:GetWidth(), h = f:GetHeight() }
end

local function restorePosition(f)
    local db = windowStore()
    local pos = db and f.badbName and db[f.badbName]
    f:ClearAllPoints()
    if pos and pos.point then
        f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
        if f.badbResizable and pos.w and pos.h then f:SetSize(pos.w, pos.h) end
    else
        f:SetPoint("CENTER")
    end
end

-- Maniglia di ridimensionamento disegnata: tre diagonali nell'angolo.
local function resizeGrip(f)
    local g = CreateFrame("Button", nil, f)
    g:SetSize(14, 14)
    g:SetPoint("BOTTOMRIGHT", -2, 2)
    g.lines = {}
    for i = 1, 3 do
        local l = UI:Fill(g, "textMuted", "OVERLAY")
        l:SetSize(4 * i, 1)
        l:SetPoint("BOTTOMRIGHT", -1, 1 + (i - 1) * 3)
        l:SetRotation(math.pi / 4)
        g.lines[i] = l
    end
    g:SetScript("OnEnter", function(self) for _, l in ipairs(self.lines) do Theme:Paint(l, "accent") end end)
    g:SetScript("OnLeave", function(self) for _, l in ipairs(self.lines) do Theme:Paint(l, "textMuted") end end)
    g:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    g:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); savePosition(f) end)
    return g
end

-- UI:Window(name, w, h, title, opts)
-- name: nome globale (serve per ESC e per ricordare la posizione), puo' essere nil.
-- opts: {
--   subtitle   = "testo sotto il titolo",
--   sidebar    = true | larghezza,   crea .sidebar a sinistra
--   footer     = true,               crea .footer in basso
--   resizable  = true, minW, minH, maxW, maxH
--   strata     = "HIGH" (default),
--   noClose    = true,               nessun bottone di chiusura
--   remember   = false,              non ricordare posizione/dimensione
--   onClose    = function(window)
-- }
function UI:Window(name, w, h, title, opts)
    opts = opts or {}
    local S = Theme.sizes
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(w or 720, h or 520)
    f:SetFrameStrata(opts.strata or "HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()
    f.badbName = opts.remember ~= false and name or nil
    Theme:Skin(f, { bg = "bg", border = "border", shadow = true })

    -- Sidebar
    local left = 0
    if opts.sidebar then
        local sw = type(opts.sidebar) == "number" and opts.sidebar or S.sidebar
        f.sidebar = CreateFrame("Frame", nil, f)
        f.sidebar:SetPoint("TOPLEFT", 1, -1); f.sidebar:SetPoint("BOTTOMLEFT", 1, 1)
        f.sidebar:SetWidth(sw)
        f.sidebar.bg = UI:Fill(f.sidebar, "sidebar", "BACKGROUND", 1)
        f.sidebar.bg:SetAllPoints()
        local edge = UI:Separator(f.sidebar, true, "divider")
        edge:SetPoint("TOPRIGHT"); edge:SetPoint("BOTTOMRIGHT")
        left = sw + 1
    end

    -- Header: banda "cielo notturno" in gradiente con filo d'accento sotto
    f.header = CreateFrame("Frame", nil, f)
    f.header:SetPoint("TOPLEFT", left + 1, -1); f.header:SetPoint("TOPRIGHT", -1, -1)
    f.header:SetHeight(opts.subtitle and S.header + 8 or S.header)
    f.header.sky = f.header:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.header.sky:SetAllPoints()
    f.header.sky.badbVertex = true
    Theme:Gradient(f.header.sky, "header", "bg", 1, 0)
    f.header.line = UI:Separator(f.header, false, "divider")
    f.header.line:SetPoint("BOTTOMLEFT"); f.header.line:SetPoint("BOTTOMRIGHT")
    f.header.glint = UI:Fill(f.header, "accent", "ARTWORK")
    f.header.glint:SetSize(44, 2)
    f.header.glint:SetPoint("BOTTOMLEFT", Theme.spacing.lg, 0)
    f.header.accentLine = UI:Fill(f.header, "accentDim", "ARTWORK")
    f.header.accentLine:SetHeight(1)
    f.header.accentLine:SetPoint("BOTTOMLEFT", 0, 1); f.header.accentLine:SetPoint("BOTTOMRIGHT", 0, 1)
    f.header.brand = UI:Fill(f.header, "accent", "ARTWORK")
    f.header.brand:SetSize(3, 18)
    f.header.brand:SetPoint("LEFT", 0, 0)
    f.header:EnableMouse(true)
    f.header:RegisterForDrag("LeftButton")
    f.header:SetScript("OnDragStart", function() f:StartMoving() end)
    f.header:SetScript("OnDragStop", function() f:StopMovingOrSizing(); savePosition(f) end)

    f.title = UI:Label(f.header, title, "title", "accent")
    if opts.subtitle then
        f.title:SetPoint("TOPLEFT", Theme.spacing.lg, -12)
        f.subtitle = UI:Label(f.header, opts.subtitle, "small", "textMuted")
        f.subtitle:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
    else
        f.title:SetPoint("LEFT", Theme.spacing.lg, 0)
    end

    if not opts.noClose then
        f.close = UI:CloseButton(f.header, function() f:Hide() end)
        f.close:SetPoint("TOPRIGHT", -10, -10)
    end

    -- Footer
    local bottom = 1
    if opts.footer then
        f.footer = CreateFrame("Frame", nil, f)
        f.footer:SetPoint("BOTTOMLEFT", left + 1, 1); f.footer:SetPoint("BOTTOMRIGHT", -1, 1)
        f.footer:SetHeight(S.footer)
        f.footer.bg = UI:Fill(f.footer, "footer", "BACKGROUND", 1)
        f.footer.bg:SetAllPoints()
        local line = UI:Separator(f.footer, false, "divider")
        line:SetPoint("TOPLEFT"); line:SetPoint("TOPRIGHT")
        bottom = S.footer + 1
    end

    -- Body
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, 0)
    f.body:SetPoint("BOTTOMRIGHT", -1, bottom)

    if opts.resizable then
        f.badbResizable = true
        f:SetResizable(true)
        local minW, minH = opts.minW or 480, opts.minH or 320
        if f.SetResizeBounds then
            f:SetResizeBounds(minW, minH, opts.maxW or 1600, opts.maxH or 1200)
        elseif f.SetMinResize then
            f:SetMinResize(minW, minH)
        end
        f.grip = resizeGrip(f)
    end

    -- ESC chiude (richiede un nome globale)
    if name and UISpecialFrames then tinsert(UISpecialFrames, name) end

    f:SetScript("OnShow", function(self)
        if not self.badbPlaced then restorePosition(self); self.badbPlaced = true end
        if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPEN) end
        if self.OnOpen then self:OnOpen() end
    end)
    f:SetScript("OnHide", function(self)
        UI:CloseDropdowns()
        if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_CLOSE) end
        if opts.onClose then opts.onClose(self) end
    end)

    function f:SetTitle(t, sub)
        self.title:SetText(t)
        if sub and self.subtitle then self.subtitle:SetText(sub) end
    end
    function f:Toggle() self:SetShown(not self:IsShown()) end
    function f:ResetPosition()
        local db = windowStore()
        if db and self.badbName then db[self.badbName] = nil end
        restorePosition(self)
    end
    return f
end

---------------------------------------------------------------------------
-- Tab orizzontali (sottolineatura d'accento sul tab attivo)
---------------------------------------------------------------------------

-- UI:Tabs(parent, tabs, onSelect) ; tabs = { { id = "a", text = "Generale", badge = "3" }, ... }
-- Ritorna un frame alto Theme.sizes.tab con :Select(id), :GetSelected(), :SetTabs(tabs)
function UI:Tabs(parent, tabs, onSelect)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(Theme.sizes.tab)
    bar.buttons = {}
    local line = UI:Separator(bar, false, "divider")
    line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT")

    local function paint(b, active)
        Theme:Paint(b.text, active and "text" or "textDim")
        b.under:SetShown(active)
    end

    function bar:SetTabs(list)
        for _, b in ipairs(self.buttons) do b:Hide() end
        local x = 0
        for i, t in ipairs(list) do
            local b = self.buttons[i]
            if not b then
                b = CreateFrame("Button", nil, self)
                b.text = UI:Label(b, nil, "body", "textDim")
                b.text:SetPoint("CENTER", 0, 1)
                b.under = UI:Fill(b, "accent", "ARTWORK")
                b.under:SetHeight(2)
                b.under:SetPoint("BOTTOMLEFT", 6, 0); b.under:SetPoint("BOTTOMRIGHT", -6, 0)
                UI.AddHover(b)
                b:SetScript("OnClick", function(btn) self:Select(btn.id, true) end)
                b:SetScript("OnEnter", function(btn) if btn.id ~= self.selected then Theme:Paint(btn.text, "text") end end)
                b:SetScript("OnLeave", function(btn) paint(btn, btn.id == self.selected) end)
                self.buttons[i] = b
            end
            b.id = t.id
            b.text:SetText(t.badge and (t.text .. "  " .. Theme:Wrap(t.badge, "accent")) or t.text)
            b:SetSize(b.text:GetStringWidth() + 24, Theme.sizes.tab)
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", x, 0)
            x = x + b:GetWidth()
            b:Show()
            paint(b, t.id == self.selected)
        end
        self.tabs = list
    end

    function bar:Select(id, user)
        self.selected = id
        for _, b in ipairs(self.buttons) do if b:IsShown() then paint(b, b.id == id) end end
        if onSelect then onSelect(id, user) end
    end
    function bar:GetSelected() return self.selected end

    bar:SetTabs(tabs or {})
    if tabs and tabs[1] then bar:Select(tabs[1].id) end
    UI.MakeEnable(bar)
    return bar
end

---------------------------------------------------------------------------
-- Navigazione laterale (sidebar)
---------------------------------------------------------------------------

-- UI:NavList(parent, items, onSelect)
-- items: { { id = "profiles", text = "Profili", icon = "Interface\\Icons\\...", header = false }, ... }
--        un item con header = true e' un'etichetta di sezione non cliccabile.
-- Ritorna un frame con :Select(id), :SetItems(items), :SetBadge(id, text)
function UI:NavList(parent, items, onSelect)
    local nav = CreateFrame("Frame", nil, parent)
    nav.buttons, nav.byId = {}, {}
    local ROW = 28

    local function paint(b, active)
        b.sel:SetShown(active)
        b.mark:SetShown(active)
        Theme:Paint(b.text, active and "text" or "textDim")
        if b.icon then Theme:Paint(b.icon, active and "accent" or "textDim") end
    end

    function nav:SetItems(list)
        for _, b in ipairs(self.buttons) do b:Hide() end
        wipe(self.byId)
        local y = 0
        for i, it in ipairs(list) do
            local b = self.buttons[i]
            if not b then
                b = CreateFrame("Button", nil, self)
                b.sel = UI:Fill(b, "selected", "BACKGROUND")
                b.sel:SetAllPoints()
                b.mark = UI:Fill(b, "accent", "ARTWORK")
                b.mark:SetWidth(2); b.mark:SetPoint("TOPLEFT"); b.mark:SetPoint("BOTTOMLEFT")
                b.hl = UI.AddHover(b)
                b.icon = b:CreateTexture(nil, "ARTWORK")
                b.icon:SetSize(14, 14); b.icon:SetPoint("LEFT", 12, 0); b.icon.badbVertex = true
                b.text = UI:Label(b, nil, "body", "textDim")
                b.badge = UI:Label(b, nil, "small", "accent")
                b.badge:SetPoint("RIGHT", -10, 0)
                b:SetScript("OnClick", function(btn) self:Select(btn.id, true) end)
                b:SetScript("OnEnter", function(btn) if btn.id ~= self.selected then Theme:Paint(btn.text, "text") end end)
                b:SetScript("OnLeave", function(btn) paint(btn, btn.id == self.selected) end)
                self.buttons[i] = b
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 0, -y); b:SetPoint("RIGHT")
            b.id = it.id
            b.text:ClearAllPoints()
            if it.header then
                b:SetHeight(ROW - 4)
                b:EnableMouse(false)
                b.icon:Hide(); b.sel:Hide(); b.mark:Hide(); b.hl:Hide(); b.badge:SetText("")
                b.text:SetFontObject(Theme.fontObjects.small)
                b.text:SetText(string.upper(it.text or ""))
                b.text:SetPoint("BOTTOMLEFT", 12, 4)
                Theme:Paint(b.text, "textMuted")
                y = y + ROW - 4 + (i > 1 and 6 or 0)
                if i > 1 then b:SetPoint("TOPLEFT", 0, -(y - ROW + 4)) end
            else
                b:SetHeight(ROW)
                b:EnableMouse(true)
                b.hl:Show()
                b.text:SetFontObject(Theme.fontObjects.body)
                b.text:SetText(it.text)
                if it.icon then
                    b.icon:SetTexture(it.icon); b.icon:Show()
                    b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
                else
                    b.icon:Hide()
                    b.text:SetPoint("LEFT", 14, 0)
                end
                b.badge:SetText(it.badge or "")
                self.byId[it.id] = b
                paint(b, it.id == self.selected)
                y = y + ROW
            end
            b:Show()
        end
        self:SetHeight(math.max(1, y))
        self.items = list
    end

    function nav:Select(id, user)
        if not self.byId[id] then return end
        self.selected = id
        for _, b in pairs(self.byId) do paint(b, b.id == id) end
        if onSelect then onSelect(id, user) end
    end
    function nav:GetSelected() return self.selected end
    function nav:SetBadge(id, text) local b = self.byId[id]; if b then b.badge:SetText(text or "") end end

    nav:SetItems(items or {})
    UI.MakeEnable(nav)
    return nav
end

---------------------------------------------------------------------------
-- Stack: impila widget in colonna (layout veloce per pagine di opzioni)
---------------------------------------------------------------------------

-- local st = UI:Stack(content, { gap = 8, padding = 16 })
-- st:Add(widget [, height [, indent]]) ; st:Space(px) ; st:Height() ; st:Reset()
function UI:Stack(parent, opts)
    opts = opts or {}
    local st = { parent = parent, gap = opts.gap or Theme.spacing.sm, pad = opts.padding or Theme.spacing.lg, y = opts.padding or Theme.spacing.lg, items = {} }
    function st:Add(w, h, indent)
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.pad + (indent or 0), -self.y)
        w:SetPoint("RIGHT", self.parent, "RIGHT", -self.pad, 0)
        self.y = self.y + (h or w:GetHeight()) + self.gap
        self.items[#self.items + 1] = w
        if self.parent.SetHeight then self.parent:SetHeight(self.y + self.pad) end
        return w
    end
    function st:Space(px) self.y = self.y + (px or self.gap) end
    function st:Height() return self.y + self.pad end
    function st:Refresh() for _, w in ipairs(self.items) do if w.Refresh then pcall(w.Refresh, w) end end end
    function st:Reset() self.y = self.pad; wipe(self.items) end
    return st
end

-- Intestazione di sezione per pagine: titolo + filo hairline a tutta larghezza.
function UI:SectionHeader(parent, text)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(26)
    f.text = UI:Label(f, text, "heading", "text")
    f.text:SetPoint("LEFT")
    f.line = UI:Separator(f, false, "divider")
    f.line:SetPoint("LEFT", f.text, "RIGHT", 10, 0)
    f.line:SetPoint("RIGHT")
    return f
end

---------------------------------------------------------------------------
-- Tolleranza di chiamata: le factory accettano sia UI:X(...) sia UI.X(...).
-- Un consumatore che usa il punto per errore non deve rompersi in gioco.
---------------------------------------------------------------------------

local FACTORIES = {
    "Fill", "Label", "Tooltip", "HideTooltip", "Panel", "Card", "Separator", "Chip", "ProgressBar",
    "ScrollFrame", "ScrollList", "Button", "ConfirmButton", "IconButton", "CloseButton", "Toggle", "Checkbox",
    "Slider", "EditBox", "InputRow", "Dropdown", "CloseDropdowns", "Window", "Tabs", "NavList", "Stack", "SectionHeader",
}
for _, name in ipairs(FACTORIES) do
    local fn = UI[name]
    if type(fn) == "function" then
        UI[name] = function(first, ...)
            if first == UI then return fn(UI, ...) end
            return fn(UI, first, ...)
        end
    end
end
