-- AegisUI - Widget dichiarativi per la ConfigUI.
-- Ogni modulo descrive le opzioni come dati: { type, path | get/set, label, ... }
-- Tipi supportati: toggle, range, execute, header. Nuovi tipi = nuova funzione in Builders.
local _, ns = ...
local Aegis = ns.Aegis

local W = { Builders = {} }
Aegis.Widgets = W

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
