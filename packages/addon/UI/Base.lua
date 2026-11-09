-- BadbUI - UI: factory dei widget del design system (parte 1: primitive e contenitori).
-- Tutto si dipinge da Badb.Theme e segue i cambi di tema da solo.
-- Convenzioni comuni a ogni controllo:
--   control:Refresh()          rilegge il valore da get() e si ridisegna
--   control:SetEnabled(bool)   abilita/disabilita (alpha + input)
--   control.label              FontString dell'etichetta (se presente)
-- API completa: docs/UI.md
local _, ns = ...
local Badb = ns.Badb
local Theme = Badb.Theme

local UI = {}
Badb.UI = UI

local WHITE = Theme.textures.white

---------------------------------------------------------------------------
-- Helper interni (esposti per i widget negli altri file UI/*.lua)
---------------------------------------------------------------------------

-- Texture piena dipinta con un token.
function UI:Fill(parent, key, layer, sub, mul)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    t:SetTexture(WHITE)
    t.badbVertex = true
    Theme:Paint(t, key, mul)
    return t
end

-- FontString con font e colore del tema. fontKey: title|heading|body|small|mono|number
function UI:Label(parent, text, fontKey, colorKey, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFontObject(Theme.fontObjects[fontKey or "body"] or Theme.fontObjects.body)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    Theme:Paint(fs, colorKey or "text")
    if text then fs:SetText(text) end
    return fs
end

-- Rende un controllo disabilitabile in modo uniforme.
function UI.MakeEnable(control, onChange)
    control.badbEnabled = true
    function control:SetEnabled(on)
        on = on and true or false
        self.badbEnabled = on
        self:SetAlpha(on and 1 or 0.4)
        if self.EnableMouse then self:EnableMouse(on) end
        if onChange then onChange(self, on) end
    end
    function control:IsEnabledBadb() return self.badbEnabled end
    if not control.Refresh then function control:Refresh() end end
end

-- Hover leggero (velatura ink) su qualunque frame cliccabile.
function UI.AddHover(frame, key, mul)
    local h = UI:Fill(frame, key or "hover", "HIGHLIGHT", 0, mul)
    h:SetAllPoints()
    return h
end

---------------------------------------------------------------------------
-- Tooltip (GameTooltip, scritto nei colori del tema)
---------------------------------------------------------------------------

-- lines: stringhe, { left, right } oppure { text, colorKey }
function UI:Tooltip(owner, title, lines, anchor)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    if title then GameTooltip:AddLine(title, Theme:Get("text")) end
    for _, l in ipairs(lines or {}) do
        if type(l) == "string" then
            local r, g, b = Theme:Get("textDim")
            GameTooltip:AddLine(l, r, g, b, true)
        elseif l.left then
            local r1, g1, b1 = Theme:Get("textDim")
            local r2, g2, b2 = Theme:Get("text")
            GameTooltip:AddDoubleLine(l.left, l.right, r1, g1, b1, r2, g2, b2)
        else
            local r, g, b = Theme:Get(l[2] or "textDim")
            GameTooltip:AddLine(l[1], r, g, b, true)
        end
    end
    GameTooltip:Show()
end

function UI:HideTooltip() if GameTooltip then GameTooltip:Hide() end end

-- Collega un tooltip statico a un frame (tip = stringa o { title, lines }).
function UI.AttachTooltip(frame, title, lines)
    if not title then return end
    frame:HookScript("OnEnter", function(self) UI:Tooltip(self, title, type(lines) == "string" and { lines } or lines) end)
    frame:HookScript("OnLeave", function() UI:HideTooltip() end)
end

---------------------------------------------------------------------------
-- Contenitori
---------------------------------------------------------------------------

-- Pannello piatto con hairline. colorKey: panel (default), panelAlt, bg, sidebar...
function UI:Panel(parent, colorKey, opts)
    local f = CreateFrame("Frame", nil, parent)
    opts = opts or {}
    Theme:Skin(f, { bg = colorKey or "panel", border = opts.border, alpha = opts.alpha })
    return f
end

-- Card: pannello rialzato con titolo e area contenuto (.content).
function UI:Card(parent, title, opts)
    opts = opts or {}
    local sp = Theme.spacing
    local f = self:Panel(parent, opts.color or "panelAlt")
    local top = sp.md
    if title then
        f.title = self:Label(f, title, "heading", "text")
        f.title:SetPoint("TOPLEFT", sp.md, -sp.md)
        if opts.subtitle then
            f.subtitle = self:Label(f, opts.subtitle, "small", "textMuted")
            f.subtitle:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
            top = top + 34
        else
            top = top + 22
        end
        -- filo d'accento sotto il titolo
        f.accent = self:Fill(f, "accent", "ARTWORK")
        f.accent:SetSize(18, 2)
        f.accent:SetPoint("TOPLEFT", sp.md, -(top - 4))
        top = top + sp.sm
    end
    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT", sp.md, -top)
    f.content:SetPoint("BOTTOMRIGHT", -sp.md, sp.md)
    return f
end

-- Linea di 1px (orizzontale di default).
function UI:Separator(parent, vertical, key)
    local t = self:Fill(parent, key or "divider", "ARTWORK")
    if vertical then t:SetWidth(1) else t:SetHeight(1) end
    return t
end

-- Chip/pillola: kind = neutral|accent|success|warning|danger|info
function UI:Chip(parent, text, kind)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(18)
    f.bg = self:Fill(f, "selected", "BACKGROUND")
    f.bg:SetAllPoints()
    f.text = self:Label(f, nil, "small", "text")
    f.text:SetPoint("CENTER", 0, 0)
    function f:SetChip(t, k)
        k = k or "neutral"
        self.text:SetText(t or "")
        self:SetWidth(math.max(24, self.text:GetStringWidth() + 14))
        if k == "neutral" then
            Theme:Paint(self.bg, "selected"); Theme:Paint(self.text, "textDim")
        else
            Theme:Paint(self.bg, k, 0.18); Theme:Paint(self.text, k)
        end
    end
    f:SetChip(text, kind)
    return f
end

-- Barra di avanzamento piatta: traccia hairline + riempimento colorato.
function UI:ProgressBar(parent, w, h, colorKey)
    local f = CreateFrame("StatusBar", nil, parent)
    f:SetSize(w or 200, h or 4)
    f:SetStatusBarTexture(WHITE)
    f:SetMinMaxValues(0, 1)
    f:SetValue(0)
    Theme:Paint(f, colorKey or "accent")
    f.track = self:Fill(f, "track", "BACKGROUND")
    f.track:SetAllPoints()
    function f:SetProgress(frac) self:SetValue(math.max(0, math.min(1, frac or 0))) end
    function f:SetColorKey(k) Theme:Paint(self, k) end
    UI.MakeEnable(f)
    return f
end

---------------------------------------------------------------------------
-- Scroll
---------------------------------------------------------------------------

-- Scrollbar sottile: traccia hairline e pollice nel colore testo attenuato.
local function thinScrollBar(scroll)
    local bar = CreateFrame("Slider", nil, scroll)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(6)
    bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 10, 0)
    bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 10, 0)
    local track = UI:Fill(bar, "track", "BACKGROUND", 0, 0.5)
    track:SetPoint("TOP"); track:SetPoint("BOTTOM"); track:SetWidth(2)
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(WHITE); thumb.badbVertex = true
    thumb:SetSize(4, 40)
    Theme:Paint(thumb, "textMuted", 0.8)
    bar:SetThumbTexture(thumb)
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    bar:SetScript("OnValueChanged", function(_, v) scroll:SetVerticalScroll(v) end)
    bar:SetScript("OnEnter", function() Theme:Paint(thumb, "accent") end)
    bar:SetScript("OnLeave", function() Theme:Paint(thumb, "textMuted", 0.8) end)
    return bar
end

-- ScrollFrame con contenuto a larghezza piena e rotella. Ritorna scroll, content.
function UI:ScrollFrame(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    local bar = thinScrollBar(scroll)
    scroll.bar, scroll.content = bar, content

    local function update()
        local max = math.max(0, content:GetHeight() - scroll:GetHeight())
        bar:SetMinMaxValues(0, max)
        bar:SetShown(max > 0)
        if bar:GetValue() > max then bar:SetValue(max) end
    end
    scroll.UpdateScroll = update
    scroll:SetScript("OnSizeChanged", function(self, w)
        content:SetWidth(w)
        update()
    end)
    content:SetScript("OnSizeChanged", update)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        bar:SetValue(bar:GetValue() - delta * 40)
    end)
    function scroll:ScrollToTop() bar:SetValue(0) end
    return scroll, content
end

-- Lista virtualizzata: crea solo le righe visibili e le ricicla.
-- createRow(parent, index) -> frame ; updateRow(row, item, index)
function UI:ScrollList(parent, rowHeight, createRow, updateRow)
    local list = CreateFrame("Frame", nil, parent)
    list.rowHeight, list.rows, list.data, list.offset = rowHeight or Theme.sizes.row, {}, {}, 0
    list:SetClipsChildren(true)

    local bar = CreateFrame("Slider", nil, list)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(6)
    bar:SetPoint("TOPRIGHT", 0, 0); bar:SetPoint("BOTTOMRIGHT", 0, 0)
    local track = UI:Fill(bar, "track", "BACKGROUND", 0, 0.5)
    track:SetPoint("TOP"); track:SetPoint("BOTTOM"); track:SetWidth(2)
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(WHITE); thumb.badbVertex = true; thumb:SetSize(4, 30)
    Theme:Paint(thumb, "textMuted", 0.8)
    bar:SetThumbTexture(thumb)
    bar:SetValueStep(1); bar:SetObeyStepOnDrag(true)
    list.bar = bar

    local function visibleCount() return math.ceil(math.max(1, list:GetHeight()) / list.rowHeight) end

    function list:Render()
        local n = visibleCount()
        for i = 1, n do
            local row = self.rows[i]
            if not row then
                row = createRow(self, i)
                row:SetHeight(self.rowHeight)
                self.rows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(i - 1) * self.rowHeight)
            row:SetPoint("RIGHT", bar, "LEFT", -4, 0)
            local idx = self.offset + i
            local item = self.data[idx]
            if item ~= nil then
                row.index, row.item = idx, item
                updateRow(row, item, idx)
                row:Show()
            else
                row:Hide()
            end
        end
        for i = n + 1, #self.rows do self.rows[i]:Hide() end
    end

    function list:SetData(data)
        self.data = data or {}
        local max = math.max(0, #self.data - visibleCount() + 1)
        bar:SetMinMaxValues(0, max)
        bar:SetShown(max > 0)
        if self.offset > max then self.offset = max; bar:SetValue(max) end
        self:Render()
    end
    function list:Refresh() self:Render() end
    function list:ScrollToIndex(i)
        bar:SetValue(math.max(0, (i or 1) - 1))
    end

    bar:SetScript("OnValueChanged", function(_, v)
        list.offset = math.floor(v + 0.5)
        list:Render()
    end)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) bar:SetValue(bar:GetValue() - delta * 2) end)
    list:SetScript("OnSizeChanged", function(self) self:SetData(self.data) end)
    UI.MakeEnable(list)
    return list
end
