-- BadbUI - UI: controlli (bottoni, toggle, checkbox, slider, campo di testo).
-- Le righe di impostazione (Toggle, Slider, Dropdown) seguono uno schema unico:
-- etichetta a sinistra, controllo a destra, altezza Theme.sizes.row, descrizione
-- opzionale (opts.desc) mostrata come tooltip. get/set sono funzioni: il controllo
-- non sa dove vive il valore (profilo, modulo, globale).
local _, ns = ...
local Badb = ns.Badb
local Theme, UI = Badb.Theme, Badb.UI

local WHITE = Theme.textures.white

---------------------------------------------------------------------------
-- Bottoni
---------------------------------------------------------------------------

-- variant -> { fondo, testo, bordo, hover }
local VARIANTS = {
    primary   = { bg = "accent",  text = "onAccent", border = false,   hover = "text",   hoverMul = 0.12 },
    secondary = { bg = "control", text = "text",     border = "border", hover = "hover" },
    ghost     = { bg = false,     text = "textDim",  border = false,   hover = "hover", hoverText = "text" },
    danger    = { bg = "danger",  bgMul = 0.16, text = "danger", border = "danger", borderMul = 0.5, hover = "danger", hoverMul = 0.12 },
}
UI.BUTTON_VARIANTS = VARIANTS

local function styleButton(b)
    local v = VARIANTS[b.variant] or VARIANTS.secondary
    if v.bg then b.bg:Show(); Theme:Paint(b.bg, v.bg, v.bgMul) else b.bg:Hide() end
    if v.border then
        Theme:Skin(b, { bg = false, border = v.border })
        if v.borderMul then Theme:SetBorder(b, v.border, v.borderMul) end
    elseif b.badbSkin then
        Theme:Skin(b, { bg = false, border = false })
    end
    Theme:Paint(b.hl, v.hover, v.hoverMul or 1)
    Theme:Paint(b.text, v.text)
end

-- UI:Button(parent, text, w, h, onClick, variant)
-- variant: "primary" | "secondary" (default) | "ghost" | "danger"
function UI:Button(parent, text, w, h, onClick, variant)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 120, h or Theme.sizes.button)
    b.variant = variant or "secondary"
    b.bg = UI:Fill(b, "control", "BACKGROUND")
    b.bg:SetAllPoints()
    b.hl = UI:Fill(b, "hover", "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.text = UI:Label(b, text, "body", "text")
    b.text:SetJustifyH("CENTER")
    b.text:SetPoint("LEFT", 8, 0); b.text:SetPoint("RIGHT", -8, 0)
    b:SetFontString(b.text)
    styleButton(b)

    -- pressione: il testo scende di un pixel, come un tasto
    b:SetScript("OnMouseDown", function(self) if self.badbEnabled then self.text:SetPoint("LEFT", 8, -1); self.text:SetPoint("RIGHT", -8, -1) end end)
    b:SetScript("OnMouseUp", function(self) self.text:SetPoint("LEFT", 8, 0); self.text:SetPoint("RIGHT", -8, 0) end)
    b:SetScript("OnEnter", function(self)
        local v = VARIANTS[self.variant]
        if v and v.hoverText then Theme:Paint(self.text, v.hoverText) end
        if self.tooltip then UI:Tooltip(self, self.tooltip, self.tooltipLines) end
    end)
    b:SetScript("OnLeave", function(self)
        local v = VARIANTS[self.variant] or VARIANTS.secondary
        Theme:Paint(self.text, v.text)
        UI:HideTooltip()
    end)
    b:SetScript("OnClick", function(self, button)
        if self.badbEnabled and self.onClick then self.onClick(self, button) end
    end)
    b.onClick = onClick

    function b:SetVariant(v) self.variant = v; styleButton(self) end
    function b:SetLabel(t) self.text:SetText(t) end
    function b:SetTooltip(title, lines) self.tooltip, self.tooltipLines = title, lines end
    UI.MakeEnable(b, function(self, on) if on then self:Enable() else self:Disable() end end)
    return b
end

-- Bottone che agisce solo al secondo click entro 3 secondi (azioni distruttive).
function UI:ConfirmButton(parent, text, confirmText, w, h, onConfirm)
    local b = self:Button(parent, text, w, h, nil, "danger")
    local armed
    b.onClick = function(self)
        if armed then
            armed = nil; self:SetLabel(text); onConfirm(self)
        else
            armed = true; self:SetLabel(confirmText or "Sicuro?")
            C_Timer.After(3, function() if armed then armed = nil; self:SetLabel(text) end end)
        end
    end
    return b
end

-- Bottone icona: glifo attenuato che si illumina al passaggio.
function UI:IconButton(parent, texture, size, tooltip, onClick)
    local b = CreateFrame("Button", nil, parent)
    size = size or 20
    b:SetSize(size, size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("CENTER")
    b.icon:SetSize(size - 4, size - 4)
    b.icon.badbVertex = true
    if texture then b.icon:SetTexture(texture) end
    Theme:Paint(b.icon, "textDim")
    b.hl = UI:Fill(b, "hover", "HIGHLIGHT")
    b.hl:SetAllPoints()
    b:SetScript("OnEnter", function(self)
        if not self.active then Theme:Paint(self.icon, "text") end
        if tooltip then UI:Tooltip(self, tooltip) end
    end)
    b:SetScript("OnLeave", function(self)
        if not self.active then Theme:Paint(self.icon, "textDim") end
        UI:HideTooltip()
    end)
    b:SetScript("OnMouseDown", function(self) self.icon:SetPoint("CENTER", 0, -1) end)
    b:SetScript("OnMouseUp", function(self) self.icon:SetPoint("CENTER", 0, 0) end)
    b:SetScript("OnClick", function(self, btn) if self.badbEnabled and onClick then onClick(self, btn) end end)
    function b:SetActive(on) self.active = on; Theme:Paint(self.icon, on and "accent" or "textDim") end
    function b:SetIcon(tex) self.icon:SetTexture(tex) end
    UI.MakeEnable(b)
    return b
end

-- Bottone di chiusura disegnato (una X con due linee), nessun asset richiesto.
function UI:CloseButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    b.hl = UI:Fill(b, "hover", "HIGHLIGHT"); b.hl:SetAllPoints()
    b.lines = {}
    for i, rot in ipairs({ math.pi / 4, -math.pi / 4 }) do
        local l = UI:Fill(b, "textDim", "ARTWORK")
        l:SetSize(12, 1.5)
        l:SetPoint("CENTER")
        l:SetRotation(rot)
        b.lines[i] = l
    end
    b:SetScript("OnEnter", function(self) for _, l in ipairs(self.lines) do Theme:Paint(l, "danger") end end)
    b:SetScript("OnLeave", function(self) for _, l in ipairs(self.lines) do Theme:Paint(l, "textDim") end end)
    b:SetScript("OnClick", onClick)
    UI.MakeEnable(b)
    return b
end

---------------------------------------------------------------------------
-- Righe di impostazione
---------------------------------------------------------------------------

-- Riga base: frame a tutta larghezza con etichetta (e descrizione come tooltip).
local function settingRow(parent, label, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(opts.height or Theme.sizes.row)
    row:SetWidth(opts.width or 320)
    row.label = UI:Label(row, label, "body", "text")
    row.label:SetPoint("LEFT", 0, 0)
    row.desc = opts.desc
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self) if self.desc then UI:Tooltip(self, label, { self.desc }) end end)
    row:SetScript("OnLeave", function() UI:HideTooltip() end)
    return row
end
UI.SettingRow = settingRow

-- Interruttore a pillola. UI:Toggle(parent, label, get, set, opts)
-- opts: { width, desc, onChange }
function UI:Toggle(parent, label, get, set, opts)
    local row = settingRow(parent, label, opts)
    local sw = CreateFrame("Button", nil, row)
    sw:SetSize(34, 18)
    sw:SetPoint("RIGHT", 0, 0)
    sw.track = UI:Fill(sw, "track", "BACKGROUND")
    sw.track:SetAllPoints()
    sw.knob = UI:Fill(sw, "text", "ARTWORK")
    sw.knob:SetSize(14, 14)
    Theme:Skin(sw, { bg = false, border = "border" })
    UI.AddHover(sw)
    row.switch = sw

    function row:Refresh()
        local on = get() and true or false
        self.value = on
        sw.knob:ClearAllPoints()
        if on then
            sw.knob:SetPoint("RIGHT", -2, 0)
            Theme:Paint(sw.track, "accent"); Theme:Paint(sw.knob, "onAccent")
        else
            sw.knob:SetPoint("LEFT", 2, 0)
            Theme:Paint(sw.track, "track"); Theme:Paint(sw.knob, "textDim")
        end
    end
    sw:SetScript("OnClick", function()
        if not row.badbEnabled then return end
        local v = not row.value
        set(v)
        row:Refresh()
        if opts and opts.onChange then opts.onChange(v) end
    end)
    UI.MakeEnable(row, function(_, on) sw:EnableMouse(on) end)
    row:Refresh()
    return row
end

-- Checkbox quadrata con spunta disegnata. UI:Checkbox(parent, label, get, set, opts)
function UI:Checkbox(parent, label, get, set, opts)
    opts = opts or {}
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(opts.height or 24)
    local box = CreateFrame("Frame", nil, row)
    box:SetSize(16, 16)
    box:SetPoint("LEFT")
    Theme:Skin(box, { bg = "control", border = "border" })
    box.fill = UI:Fill(box, "accent", "ARTWORK")
    box.fill:SetPoint("TOPLEFT", 3, -3); box.fill:SetPoint("BOTTOMRIGHT", -3, 3)
    row.box = box
    row.label = UI:Label(row, label, "body", "text")
    row.label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    row:SetWidth(opts.width or (24 + row.label:GetStringWidth() + 8))
    UI.AddHover(row)
    UI.AttachTooltip(row, opts.desc and label, opts.desc)

    function row:Refresh()
        self.value = get() and true or false
        self.box.fill:SetShown(self.value)
        Theme:SetBorder(self.box, self.value and "accent" or "border")
    end
    row:SetScript("OnClick", function(self)
        if not self.badbEnabled then return end
        set(not self.value); self:Refresh()
        if opts.onChange then opts.onChange(self.value) end
    end)
    UI.MakeEnable(row)
    row:Refresh()
    return row
end

-- Slider: traccia hairline, riempimento accento, pollice, valore a destra.
-- UI:Slider(parent, label, min, max, step, get, set, opts)
-- opts: { width, desc, format = "%.2f" | function(v) -> string, percent = true, live = true }
function UI:Slider(parent, label, min, max, step, get, set, opts)
    opts = opts or {}
    local row = settingRow(parent, label, { width = opts.width, desc = opts.desc, height = 40 })
    row.label:ClearAllPoints()
    row.label:SetPoint("TOPLEFT", 0, -2)
    row.valueText = UI:Label(row, "", "number", "accent")
    row.valueText:SetPoint("TOPRIGHT", 0, -2)
    row.valueText:SetJustifyH("RIGHT")

    local s = CreateFrame("Slider", nil, row)
    s:SetOrientation("HORIZONTAL")
    s:SetHeight(14)
    s:SetPoint("BOTTOMLEFT", 0, 4); s:SetPoint("BOTTOMRIGHT", 0, 4)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step or 0.01)
    s:SetObeyStepOnDrag(true)
    s:EnableMouseWheel(true)
    s.track = UI:Fill(s, "track", "BACKGROUND")
    s.track:SetPoint("LEFT"); s.track:SetPoint("RIGHT"); s.track:SetHeight(2)
    s.fill = UI:Fill(s, "accent", "BORDER")
    s.fill:SetPoint("LEFT"); s.fill:SetHeight(2)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(WHITE); thumb.badbVertex = true
    thumb:SetSize(10, 10)
    Theme:Paint(thumb, "text")
    s:SetThumbTexture(thumb)
    row.slider = s

    local function fmt(v)
        if type(opts.format) == "function" then return opts.format(v) end
        if opts.percent then return string.format("%d%%", math.floor(v * 100 + 0.5)) end
        if opts.format then return string.format(opts.format, v) end
        if (step or 0.01) >= 1 then return string.format("%d", v) end
        return string.format("%.2f", v)
    end
    local function paintFill(v)
        local w = s:GetWidth()
        local frac = (max > min) and (v - min) / (max - min) or 0
        s.fill:SetWidth(math.max(1, w * frac))
        row.valueText:SetText(fmt(v))
    end

    s:SetScript("OnValueChanged", function(_, v, userInput)
        paintFill(v)
        if userInput and row.badbEnabled and opts.live ~= false then set(v) end
    end)
    s:SetScript("OnMouseUp", function(self) if row.badbEnabled and opts.live == false then set(self:GetValue()) end end)
    s:SetScript("OnMouseWheel", function(self, delta)
        if not row.badbEnabled then return end
        local v = math.max(min, math.min(max, self:GetValue() + delta * (step or 0.01)))
        self:SetValue(v); set(v)
    end)
    s:SetScript("OnSizeChanged", function(self) paintFill(self:GetValue()) end)
    s:SetScript("OnEnter", function() Theme:Paint(thumb, "accent") end)
    s:SetScript("OnLeave", function() Theme:Paint(thumb, "text") end)

    function row:Refresh()
        local v = get()
        if type(v) ~= "number" then v = min end
        s:SetValue(v)
        paintFill(v)
    end
    UI.MakeEnable(row, function(_, on) s:EnableMouse(on); s:EnableMouseWheel(on) end)
    row:Refresh()
    return row
end

---------------------------------------------------------------------------
-- Campo di testo
---------------------------------------------------------------------------

-- UI:EditBox(parent, w, h, opts)
-- opts: { multiline, placeholder, onEnter(text), onChange(text), numeric, maxLetters, mono }
-- Multiline: ritorna un contenitore scrollabile con .edit (EditBox interno).
function UI:EditBox(parent, w, h, opts)
    opts = opts or {}
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(w or 200, h or Theme.sizes.button)
    Theme:Skin(holder, { bg = "control", border = "border" })
    local edit
    if opts.multiline then
        local scroll, content = UI:ScrollFrame(holder)
        scroll:SetPoint("TOPLEFT", 6, -6); scroll:SetPoint("BOTTOMRIGHT", -14, 6)
        edit = CreateFrame("EditBox", nil, content)
        edit:SetMultiLine(true)
        edit:SetPoint("TOPLEFT"); edit:SetPoint("TOPRIGHT")
        edit:SetHeight(h or 100)
        edit:SetScript("OnCursorChanged", function(self, _, y, _, ch)
            content:SetHeight(math.max(scroll:GetHeight(), self:GetHeight()))
            local top, bottom = scroll:GetVerticalScroll(), scroll:GetVerticalScroll() + scroll:GetHeight()
            y = -y
            if y < top then scroll.bar:SetValue(y) elseif y + ch > bottom then scroll.bar:SetValue(y + ch - scroll:GetHeight()) end
        end)
        holder:EnableMouse(true)
        holder:SetScript("OnMouseDown", function() edit:SetFocus() end)
        holder.scroll = scroll
    else
        edit = CreateFrame("EditBox", nil, holder)
        edit:SetPoint("TOPLEFT", 8, 0); edit:SetPoint("BOTTOMRIGHT", -8, 0)
    end
    edit:SetAutoFocus(false)
    edit:SetFontObject(Theme.fontObjects[opts.mono and "mono" or "body"])
    Theme:Paint(edit, "text")
    if opts.numeric then edit:SetNumeric(true) end
    if opts.maxLetters then edit:SetMaxLetters(opts.maxLetters) end
    holder.edit = edit

    if opts.placeholder then
        holder.placeholder = UI:Label(holder, opts.placeholder, "body", "textMuted")
        holder.placeholder:SetPoint("TOPLEFT", 8, opts.multiline and -7 or 0)
        if not opts.multiline then holder.placeholder:SetPoint("BOTTOMLEFT", 8, 0) end
    end
    local function updatePlaceholder()
        if holder.placeholder then holder.placeholder:SetShown(edit:GetText() == "" and not edit:HasFocus()) end
    end

    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(self)
        if opts.multiline and not IsControlKeyDown() then self:Insert("\n"); return end
        if opts.onEnter then opts.onEnter(self:GetText()) end
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusGained", function() Theme:SetBorder(holder, "focus"); updatePlaceholder() end)
    edit:SetScript("OnEditFocusLost", function() Theme:SetBorder(holder, "border"); updatePlaceholder() end)
    edit:SetScript("OnTextChanged", function(self, user)
        updatePlaceholder()
        if user and opts.onChange then opts.onChange(self:GetText()) end
    end)

    function holder:GetText() return edit:GetText() end
    function holder:SetText(t) edit:SetText(t or ""); updatePlaceholder() end
    function holder:SetFocus() edit:SetFocus() end
    function holder:HighlightText() edit:HighlightText() end
    function holder:SetError(on) Theme:SetBorder(holder, on and "danger" or "border") end
    function holder:Refresh() if opts.get then self:SetText(opts.get()) end end
    UI.MakeEnable(holder, function(_, on) edit:EnableMouse(on); edit:EnableKeyboard(on); if not on then edit:ClearFocus() end end)
    holder:Refresh()
    updatePlaceholder()
    return holder
end

-- Riga etichetta + EditBox a destra. opts come EditBox, più get/set e width.
function UI:InputRow(parent, label, get, set, opts)
    opts = opts or {}
    local row = settingRow(parent, label, opts)
    local box = self:EditBox(row, opts.inputWidth or 160, Theme.sizes.button, {
        placeholder = opts.placeholder, numeric = opts.numeric, get = get,
        onEnter = function(t) set(t) end,
    })
    box:SetPoint("RIGHT")
    row.input = box
    function row:Refresh() box:Refresh() end
    UI.MakeEnable(row, function(_, on) box:SetEnabled(on) end)
    return row
end
