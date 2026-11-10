-- BadbUI - Galleria del design system + impostazioni del tema.
-- /badb gallery  apre una finestra con tutti i widget dal vivo (utile per sviluppo e QA).
-- /badb theme [night|dusk|graphite] [accento]  cambia tema da riga di comando.
-- Serve anche da esempio d'uso completo dell'API Badb.UI.
local _, ns = ...
local L = ns.Badb.L
local Badb = ns.Badb
local Theme, UI = Badb.Theme, Badb.UI

local Gallery = {}
UI.Gallery = Gallery

local demo = { toggle = true, check = false, slider = 0.6, steps = 3, choice = "b", text = "" }

local function buildControls(page)
    local st = UI:Stack(page, { gap = 10 })
    st:Add(UI:SectionHeader(page, L["Bottoni"]))
    local row = CreateFrame("Frame", nil, page); row:SetHeight(Theme.sizes.button)
    local x = 0
    for _, v in ipairs({ "primary", "secondary", "ghost", "danger" }) do
        local b = UI:Button(row, v:gsub("^%l", string.upper), 104, nil, function() Badb.Logger:Info(L["Bottone %s"], v) end, v)
        b:SetPoint("LEFT", x, 0); x = x + 112
    end
    local confirm = UI:ConfirmButton(row, "Reset", L["Conferma?"], 104, nil, function() Badb.Logger:Info(L["Confermato"]) end)
    confirm:SetPoint("LEFT", x, 0)
    st:Add(row)

    st:Add(UI:SectionHeader(page, L["Impostazioni"]))
    st:Add(UI:Toggle(page, L["Interruttore"], function() return demo.toggle end, function(v) demo.toggle = v end, { desc = L["Un toggle a pillola."] }))
    st:Add(UI:Checkbox(page, L["Casella di controllo"], function() return demo.check end, function(v) demo.check = v end))
    st:Add(UI:Slider(page, L["Trasparenza"], 0, 1, 0.05, function() return demo.slider end, function(v) demo.slider = v end, { percent = true }))
    st:Add(UI:Slider(page, L["Passi interi"], 1, 10, 1, function() return demo.steps end, function(v) demo.steps = v end))
    st:Add(UI:Dropdown(page, L["Scelta"], {
        { value = "a", text = L["Opzione A"] }, { value = "b", text = L["Opzione B"] },
        { value = "c", text = L["Opzione C"], desc = L["Con descrizione"] }, { value = "d", text = L["Disabilitata"], disabled = true },
    }, function() return demo.choice end, function(v) demo.choice = v end))
    st:Add(UI:InputRow(page, L["Nome profilo"], function() return demo.text end, function(v) demo.text = v end, { placeholder = L["Scrivi e premi Invio"] }))

    st:Add(UI:SectionHeader(page, L["Stato"]))
    local chips = CreateFrame("Frame", nil, page); chips:SetHeight(20)
    x = 0
    for _, k in ipairs({ "neutral", "accent", "success", "warning", "danger", "info" }) do
        local c = UI:Chip(chips, k, k); c:SetPoint("LEFT", x, 0); x = x + c:GetWidth() + 6
    end
    st:Add(chips)
    local bar = UI:ProgressBar(page, 300, 4); bar:SetProgress(0.42)
    st:Add(bar, 4)
    return st
end

local function buildTheme(page)
    local st = UI:Stack(page, { gap = 10 })
    st:Add(UI:SectionHeader(page, L["Tema"]))
    st:Add(UI:Dropdown(page, L["Schema colori"], function() return Theme:ListSchemes() end,
        function() return Theme.state.scheme end, function(v) Theme:SetScheme(v) end))
    local accents = {}
    for _, k in ipairs(Theme.ACCENT_ORDER) do accents[#accents + 1] = { value = k, text = k:gsub("^%l", string.upper) } end
    st:Add(UI:Dropdown(page, L["Accento"], accents, function() return Theme.state.customAccent and "custom" or Theme.state.accent end,
        function(v) Theme:SetAccent(v) end))
    st:Add(UI:Slider(page, L["Opacita' sfondo"], 0.3, 1, 0.05, function() return Theme.state.opacity end,
        function(v) Theme:SetOpacity(v) end, { percent = true, live = false }))
    local reset = UI:Button(page, L["Ripristina tema"], 160, nil, function() Theme:Reset(); st:Refresh() end, "secondary")
    st:Add(reset)

    st:Add(UI:SectionHeader(page, "Palette"))
    local grid = CreateFrame("Frame", nil, page); grid:SetHeight(120)
    local keys = { "bg", "panel", "panelAlt", "sidebar", "header", "accent", "text", "textDim", "textMuted", "success", "warning", "danger" }
    for i, k in ipairs(keys) do
        local sw = UI:Panel(grid, k)
        sw:SetSize(96, 26)
        sw:SetPoint("TOPLEFT", ((i - 1) % 4) * 104, -math.floor((i - 1) / 4) * 34)
        local l = UI:Label(sw, k, "small", (k:find("^text") or k == "accent" or k == "success" or k == "warning" or k == "danger") and "onAccent" or "text")
        l:SetPoint("CENTER")
    end
    st:Add(grid)
    return st
end

local function buildList(page)
    local data = {}
    for i = 1, 200 do data[i] = { name = L["Elemento "] .. i, value = (i * 37) % 100 } end
    local list = UI:ScrollList(page, 28, function(parent)
        local r = CreateFrame("Button", nil, parent)
        UI.AddHover(r)
        r.name = UI:Label(r, nil, "body", "text"); r.name:SetPoint("LEFT", 8, 0)
        r.chip = UI:Chip(r, "", "neutral"); r.chip:SetPoint("RIGHT", -8, 0)
        r.line = UI:Separator(r, false, "divider"); r.line:SetPoint("BOTTOMLEFT"); r.line:SetPoint("BOTTOMRIGHT")
        return r
    end, function(r, item)
        r.name:SetText(item.name)
        r.chip:SetChip(item.value .. "%", item.value > 66 and "success" or item.value > 33 and "warning" or "danger")
    end)
    list:SetPoint("TOPLEFT", 16, -16); list:SetPoint("BOTTOMRIGHT", -16, 16)
    list:SetData(data)
    return list
end

function Gallery:Build()
    if self.window then return self.window end
    local w = UI:Window("BadbUIGallery", 760, 560, "BadbUI", { subtitle = "Design system  ·  " .. (Badb.version or ""), sidebar = true, footer = true, resizable = true })
    local pages, stacks = {}, {}
    local function page(id)
        local scroll, content = UI:ScrollFrame(w.body)
        scroll:SetPoint("TOPLEFT", 0, -Theme.sizes.tab - 4); scroll:SetPoint("BOTTOMRIGHT", -14, 4)
        scroll:Hide()
        pages[id] = scroll
        return content, scroll
    end
    stacks.controls = buildControls((page("controls")))
    stacks.theme = buildTheme((page("theme")))
    local listHolder = CreateFrame("Frame", nil, w.body)
    listHolder:SetPoint("TOPLEFT", 0, -Theme.sizes.tab - 4); listHolder:SetPoint("BOTTOMRIGHT")
    listHolder:Hide()
    pages.list = listHolder
    buildList(listHolder)

    local function show(id)
        for k, p in pairs(pages) do p:SetShown(k == id) end
        if stacks[id] then stacks[id]:Refresh() end
    end

    w.tabs = UI:Tabs(w.body, { { id = "controls", text = L["Controlli"] }, { id = "theme", text = L["Tema"] }, { id = "list", text = L["Lista"], badge = "200" } },
        function(id) show(id); if w.nav then w.nav:Select(id) end end)
    w.tabs:SetPoint("TOPLEFT", 8, 0); w.tabs:SetPoint("TOPRIGHT", -8, 0)

    local brand = UI:Label(w.sidebar, "Badb" .. Theme:Wrap("UI", "accent"), "title", "text")
    brand:SetPoint("TOPLEFT", 16, -18)
    Theme:OnChange(brand, function() brand:SetText("Badb" .. Theme:Wrap("UI", "accent")) end, true)
    w.nav = UI:NavList(w.sidebar, {
        { id = "h1", text = "Design system", header = true },
        { id = "controls", text = L["Controlli"] },
        { id = "theme", text = L["Tema"] },
        { id = "list", text = L["Lista"], badge = "200" },
    }, function(id, user) if user then w.tabs:Select(id) end end)
    w.nav:SetPoint("TOPLEFT", 0, -56); w.nav:SetPoint("RIGHT", w.sidebar, "RIGHT", -1, 0)

    local hint = UI:Label(w.footer, L["/badb gallery  ·  /badb theme <schema> <accento>"], "small", "textMuted")
    hint:SetPoint("LEFT", 12, 0)
    local close = UI:Button(w.footer, L["Chiudi"], 90, 22, function() w:Hide() end, "ghost")
    close:SetPoint("RIGHT", -8, 0)

    w.tabs:Select("controls")
    self.window = w
    return w
end

function Gallery:Toggle() self:Build():Toggle() end

-- Comandi slash tramite il router (Config/Slash.lua, caricato prima di questo file).
local function themeCommand(args)
    local scheme, accent = strsplit(" ", strtrim(args or ""))
    if scheme and scheme ~= "" and not Theme:SetScheme(scheme) then
        if not Theme:SetAccent(scheme) then
            Badb.Logger:Warn(L["Schema sconosciuto '%s'. Schemi: night, dusk, graphite. Accenti: %s"], scheme, table.concat(Theme.ACCENT_ORDER, ", "))
            return
        end
    end
    if accent and accent ~= "" and not Theme:SetAccent(accent) then
        Badb.Logger:Warn(L["Accento sconosciuto '%s'. Accenti: %s"], accent, table.concat(Theme.ACCENT_ORDER, ", "))
        return
    end
    Badb.Logger:Info(L["Tema: %s, accento %s"], Theme.state.scheme, Theme.state.customAccent and L["personalizzato"] or Theme.state.accent)
end
Gallery.ThemeCommand = themeCommand

if Badb.Slash and Badb.Slash.Register then
    Badb.Slash:Register("gallery", function() Gallery:Toggle() end, L["galleria del design system"])
    Badb.Slash:Register("theme", themeCommand, L["theme [night|dusk|graphite] [accento] - cambia tema"])
end
