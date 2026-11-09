-- BadbUI - Pannello di configurazione (Settings > AddOns > BadbUI)
-- Sezioni: Profili (cambio/copia/reset/import/export), Moduli (attiva + opzioni generate).
local _, ns = ...
local Badb = ns.Badb
local DB, Modules, Compat, W, Events = Badb.DB, Badb.Modules, Badb.Compat, Badb.Widgets, Badb.Events

local UI = {}
Badb.ConfigUI = UI

local panel = CreateFrame("Frame")
panel:Hide()
UI.panel = panel

local scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 8, -8)
scroll:SetPoint("BOTTOMRIGHT", -28, 8)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(600, 1)
scroll:SetScrollChild(content)

-- Finestra di testo riutilizzata per import/export
local box
local function textBox(title, text, onAccept)
    if not box then
        box = Compat.CreateFrame("Frame", "BadbUITextBox", UIParent, "BasicFrameTemplateWithInset")
        box:SetSize(520, 300); box:SetPoint("CENTER"); box:SetFrameStrata("DIALOG")
        box:SetMovable(true); box:EnableMouse(true); box:RegisterForDrag("LeftButton")
        box:SetScript("OnDragStart", box.StartMoving); box:SetScript("OnDragStop", box.StopMovingOrSizing)
        box.title = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        box.title:SetPoint("TOP", 0, -5)
        local sf = CreateFrame("ScrollFrame", nil, box, "InputScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 14, -32); sf:SetPoint("BOTTOMRIGHT", -14, 40)
        sf.EditBox:SetWidth(470); sf.EditBox:SetFontObject(ChatFontNormal)
        if sf.CharCount then sf.CharCount:Hide() end
        box.edit = sf.EditBox
        box.ok = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
        box.ok:SetSize(120, 22); box.ok:SetPoint("BOTTOM", 0, 12)
        tinsert(UISpecialFrames, "BadbUITextBox")
    end
    box.title:SetText(title)
    box.edit:SetText(text or "")
    box.edit:HighlightText(); box.edit:SetFocus()
    box.ok:SetText(onAccept and "Importa" or "Chiudi")
    box.ok:SetScript("OnClick", function()
        if onAccept then onAccept(box.edit:GetText()) end
        box:Hide()
    end)
    box:Show()
end
UI.TextBox = textBox

local function header(text, y)
    local fs = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", 16, -y); fs:SetText(text)
    return y + 30
end

local function button(text, x, y, fn)
    local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    b:SetSize(130, 22); b:SetPoint("TOPLEFT", x, -y); b:SetText(text)
    b:SetScript("OnClick", fn)
    return b
end

local built, refreshers = false, {}

local function build()
    local y = 8
    local title = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    title:SetPoint("TOPLEFT", 16, -y); title:SetText("BadbUI  |cff888888v" .. Badb.version .. "|r")
    y = y + 40

    -- Profili
    y = header("Profili", y)
    local current = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    current:SetPoint("TOPLEFT", 16, -y)
    refreshers[#refreshers + 1] = function() current:SetText("Profilo attivo: |cff3fa7ff" .. DB:GetProfileName() .. "|r") end
    y = y + 24

    local dd = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
    dd:SetPoint("TOPLEFT", 16, -y); dd:SetWidth(200)
    dd:SetupMenu(function(_, root)
        for _, name in ipairs(DB:ListProfiles()) do
            root:CreateRadio(name, function() return name == DB:GetProfileName() end, function() DB:SetProfile(name) end)
        end
    end)
    y = y + 34

    button("Nuovo / Copia", 16, y, function()
        textBox("Nome del nuovo profilo (copia dell'attivo)", "", function(name)
            name = strtrim(name or "")
            if name ~= "" and DB:CopyProfile(DB:GetProfileName(), name) then DB:SetProfile(name) end
        end)
    end)
    button("Esporta", 152, y, function() textBox("Esporta profilo", DB:ExportProfile()) end)
    button("Importa", 288, y, function()
        textBox("Incolla la stringa BadbUI", "", function(str)
            local name = "Importato " .. date("%Y-%m-%d %H:%M")
            local ok, err = DB:ImportProfile(str, name)
            if ok then DB:SetProfile(name) else Badb.Logger:Error("Import fallito: %s", err) end
        end)
    end)
    button("Reset", 424, y, function() DB:ResetProfile() end)
    y = y + 40

    -- Moduli
    y = header("Moduli", y)
    for _, name in ipairs(Modules.order) do
        local m = Modules:Get(name)
        local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 16, -y)
        local label = cb.text or cb.Text
        if label then label:SetText("|cffffd100" .. m.title .. "|r  |cff888888" .. (m.category or "") .. "|r") end
        cb:SetScript("OnClick", function(self) Modules:SetEnabled(name, self:GetChecked()) end)
        refreshers[#refreshers + 1] = function() cb:SetChecked(m.enabled and true or false) end
        y = y + 28

        local sub = CreateFrame("Frame", nil, content)
        sub:SetPoint("TOPLEFT", 24, -y); sub:SetSize(560, 1)
        local h, widgets = W:Build(sub, m, 0)
        for _, w in ipairs(widgets) do
            if w.Refresh then refreshers[#refreshers + 1] = function() w:Refresh() end end
        end
        y = y + h + 8
    end
    content:SetHeight(y + 20)
end

function UI:Refresh()
    for _, fn in ipairs(refreshers) do pcall(fn) end
end

panel:SetScript("OnShow", function()
    if not built then build(); built = true end
    UI:Refresh()
end)

function UI:Open() Compat.OpenOptionsPanel(panel) end

Compat.RegisterOptionsPanel(panel, "BadbUI")

Events:On(UI, "BADB_PROFILE_CHANGED", function() if built then UI:Refresh() end end)
Events:On(UI, "BADB_MODULE_ENABLED", function() if built then UI:Refresh() end end)
Events:On(UI, "BADB_MODULE_DISABLED", function() if built then UI:Refresh() end end)
