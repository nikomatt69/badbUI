-- BadbUI - Widget dichiarativi per la ConfigUI.
-- Ogni modulo descrive le opzioni come dati: { type, path | get/set, label, ... }
-- Tipi supportati: toggle, range, select, execute, header. Nuovi tipi = nuova funzione in Builders.
local _, ns = ...
local Badb = ns.Badb

local W = { Builders = {} }
Badb.Widgets = W

local function getter(module, opt)
    if opt.get then return opt.get end
    return function() return module:Get(opt.path) end
end

local function setter(module, opt)
    if opt.set then return opt.set end
    return function(v) module:Set(opt.path, v) end
end

W.Builders.header = function(parent, _, opt)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetText(opt.label)
    fs:SetHeight(24)
    return fs, 28
end

W.Builders.toggle = function(parent, module, opt)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    local get, set = getter(module, opt), setter(module, opt)
    cb.text = cb.text or cb.Text
    if cb.text then cb.text:SetText(opt.label) end
    cb.Refresh = function(self) self:SetChecked(get() and true or false) end
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    cb:Refresh()
    return cb, 28
end

W.Builders.range = function(parent, module, opt)
    local s = CreateFrame("Slider", nil, parent, "MinimalSliderTemplate")
    local get, set = getter(module, opt), setter(module, opt)
    s:SetSize(220, 16)
    s:SetMinMaxValues(opt.min, opt.max)
    s:SetValueStep(opt.step or 0.01)
    s:SetObeyStepOnDrag(true)
    local label = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 2)
    s.Refresh = function(self)
        local v = get() or opt.min
        self:SetValue(v)
        label:SetFormattedText("%s: %.2f", opt.label, v)
    end
    s:SetScript("OnValueChanged", function(self, v, userInput)
        label:SetFormattedText("%s: %.2f", opt.label, v)
        if userInput then set(v) end
    end)
    s:Refresh()
    return s, 40
end

W.Builders.execute = function(parent, _, opt)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(200, 22)
    b:SetText(opt.label)
    b:SetScript("OnClick", function() opt.func() end)
    return b, 30
end

-- select: { type = "select", path, label, values = { { value, text }, ... } }
W.Builders.select = function(parent, module, opt)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(320, 44)
    local get, set = getter(module, opt), setter(module, opt)
    local label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", 4, 0)
    label:SetText(opt.label)
    local dd = CreateFrame("DropdownButton", nil, holder, "WowStyle1DropdownTemplate")
    dd:SetPoint("TOPLEFT", 0, -14)
    dd:SetWidth(220)
    dd:SetupMenu(function(_, root)
        local values = type(opt.values) == "function" and opt.values() or opt.values
        for _, v in ipairs(values) do
            root:CreateRadio(v.text, function() return get() == v.value end, function() set(v.value) end)
        end
    end)
    holder.Refresh = function() if dd.GenerateMenu then dd:GenerateMenu() end end
    return holder, 48
end

-- Costruisce in colonna tutte le opzioni di un modulo; restituisce l'altezza totale.
function W:Build(parent, module, startY)
    local y = startY or 0
    local widgets = {}
    for _, opt in ipairs(module.options) do
        local build = self.Builders[opt.type]
        if build then
            local w, h = build(parent, module, opt)
            w:SetPoint("TOPLEFT", parent, "TOPLEFT", opt.type == "range" and 20 or 16, -y - (opt.type == "range" and 14 or 0))
            widgets[#widgets + 1] = w
            y = y + h
        end
    end
    return y, widgets
end
