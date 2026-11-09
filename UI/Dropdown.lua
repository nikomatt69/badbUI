-- BadbUI - UI: dropdown nello stile del tema (menu proprio, niente UIDropDownMenu,
-- cosi' non contamina il menu di Blizzard e non causa taint).
-- UI:Dropdown(parent, label, items, get, set, opts)
--   items: { { value = v, text = "Testo", desc = "tooltip", disabled = bool }, ... }
--          oppure function() -> items (rivalutata a ogni apertura)
--   label: nil per un dropdown senza riga (solo il bottone)
--   opts:  { width, buttonWidth, desc, maxRows = 10, onChange(value) }
local _, ns = ...
local Badb = ns.Badb
local Theme, UI = Badb.Theme, Badb.UI

local ROW_H = 22

-- Un solo menu condiviso: aprirne uno chiude l'altro.
local menu
local function getMenu()
    if menu then return menu end
    menu = CreateFrame("Frame", "BadbUIDropdownMenu", UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:Hide()
    Theme:Skin(menu, { bg = "panelAlt", border = "border", shadow = true })
    menu.list = UI:ScrollList(menu, ROW_H, function(list)
        local row = CreateFrame("Button", nil, list)
        row.sel = UI:Fill(row, "accentSoft", "BACKGROUND")
        row.sel:SetAllPoints()
        row.mark = UI:Fill(row, "accent", "ARTWORK")
        row.mark:SetSize(2, ROW_H - 8); row.mark:SetPoint("LEFT", 2, 0)
        UI.AddHover(row)
        row.text = UI:Label(row, nil, "body", "text")
        row.text:SetPoint("LEFT", 10, 0); row.text:SetPoint("RIGHT", -6, 0)
        row:SetScript("OnClick", function(self)
            if self.item.disabled then return end
            local owner = menu.owner
            menu:Hide()
            if owner then owner:Choose(self.item.value) end
        end)
        row:SetScript("OnEnter", function(self) if self.item.desc then UI:Tooltip(self, self.item.text, { self.item.desc }) end end)
        row:SetScript("OnLeave", function() UI:HideTooltip() end)
        return row
    end, function(row, item)
        local selected = menu.owner and menu.owner.value == item.value
        row.sel:SetShown(selected)
        row.mark:SetShown(selected)
        row.text:SetText(item.text or tostring(item.value))
        Theme:Paint(row.text, item.disabled and "textMuted" or (selected and "accent" or "text"))
    end)
    menu.list:SetPoint("TOPLEFT", 2, -2)
    menu.list:SetPoint("BOTTOMRIGHT", -2, 2)
    -- chiusura con click fuori (niente cattura tastiera: SetPropagateKeyboardInput
    -- e' limitata in combattimento)
    menu:SetScript("OnUpdate", function(self)
        if IsMouseButtonDown("LeftButton") and not self:IsMouseOver() and not (self.owner and self.owner.button:IsMouseOver()) then
            self:Hide()
        end
    end)
    menu:SetScript("OnHide", function(self)
        if self.owner then self.owner:SetOpen(false) end
        self.owner = nil
    end)
    return menu
end

local function resolve(items)
    if type(items) == "function" then items = items() end
    local out = {}
    for i, it in ipairs(items or {}) do
        if type(it) ~= "table" then it = { value = it, text = tostring(it) } end
        out[i] = it
    end
    return out
end

-- Chevron disegnato con due linee ruotate (nessun asset).
local function chevron(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(10, 6)
    c.l = UI:Fill(c, "textDim", "OVERLAY"); c.l:SetSize(6, 1.5); c.l:SetPoint("CENTER", -2, 0); c.l:SetRotation(-math.pi / 4)
    c.r = UI:Fill(c, "textDim", "OVERLAY"); c.r:SetSize(6, 1.5); c.r:SetPoint("CENTER", 2, 0); c.r:SetRotation(math.pi / 4)
    function c:SetColor(k) Theme:Paint(self.l, k); Theme:Paint(self.r, k) end
    function c:SetOpen(open)
        self.l:SetRotation(open and math.pi / 4 or -math.pi / 4)
        self.r:SetRotation(open and -math.pi / 4 or math.pi / 4)
    end
    return c
end

function UI:Dropdown(parent, label, items, get, set, opts)
    opts = opts or {}
    local row
    if label then
        row = UI.SettingRow(parent, label, opts)
    else
        row = CreateFrame("Frame", nil, parent)
        row:SetSize(opts.buttonWidth or opts.width or 180, Theme.sizes.button)
    end
    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(opts.buttonWidth or (label and 170 or row:GetWidth()), Theme.sizes.button)
    btn:SetPoint("RIGHT")
    Theme:Skin(btn, { bg = "control", border = "border" })
    UI.AddHover(btn)
    btn.text = UI:Label(btn, "", "body", "text")
    btn.text:SetPoint("LEFT", 8, 0); btn.text:SetPoint("RIGHT", -22, 0)
    btn.chev = chevron(btn)
    btn.chev:SetPoint("RIGHT", -8, 0)
    row.button = btn
    row.items = items

    function row:GetItems() return resolve(self.items) end
    function row:SetItems(newItems) self.items = newItems; self:Refresh() end

    function row:Refresh()
        self.value = get()
        local text
        for _, it in ipairs(self:GetItems()) do
            if it.value == self.value then text = it.text; break end
        end
        btn.text:SetText(text or (self.value ~= nil and tostring(self.value)) or (opts.placeholder or "—"))
        Theme:Paint(btn.text, text and "text" or "textMuted")
    end

    function row:Choose(value)
        set(value)
        self:Refresh()
        if opts.onChange then opts.onChange(value) end
    end

    function row:SetOpen(open)
        self.open = open
        btn.chev:SetOpen(open)
        btn.chev:SetColor(open and "accent" or "textDim")
        Theme:SetBorder(btn, open and "focus" or "border")
    end

    function row:Toggle()
        local m = getMenu()
        if m:IsShown() and m.owner == self then m:Hide(); return end
        if m:IsShown() then m:Hide() end
        local list = self:GetItems()
        local rows = math.min(#list, opts.maxRows or 10)
        m.owner = self
        m:ClearAllPoints()
        m:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
        m:SetSize(math.max(btn:GetWidth(), opts.menuWidth or 0), math.max(1, rows) * ROW_H + 4)
        m:Show()
        m.list:SetData(list)
        for i, it in ipairs(list) do
            if it.value == self.value and i > rows then m.list:ScrollToIndex(i - rows + 1) end
        end
        self:SetOpen(true)
    end

    btn:SetScript("OnClick", function() if row.badbEnabled then row:Toggle() end end)
    UI.MakeEnable(row, function(_, on) btn:EnableMouse(on) end)
    row:Refresh()
    return row
end

-- Chiude il menu aperto (es. alla chiusura di una finestra).
function UI:CloseDropdowns() if menu then menu:Hide() end end
