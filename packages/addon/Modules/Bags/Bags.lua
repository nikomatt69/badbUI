-- BadbUI - Ricerca in borse, banca personale e inventario dei personaggi.
local _, ns = ...
local Badb, Inventory = ns.Badb, ns.BagsInventory
local L, UI, Theme = Badb.L, Badb.UI, Badb.Theme
local Compat, Logger = Badb.Compat, Badb.Logger

local SOURCES = { bags = L["Borse"], bank = L["Banca"] }
local TABS = {
    { id = "bags", text = SOURCES.bags },
    { id = "bank", text = SOURCES.bank },
    { id = "all", text = L["Tutte le fonti"] },
}
local UNAVAILABLE = L["Il client non espone l'inventario a BadbUI."]
local SHOW = L["Apri inventario"]
local GUIDE_ID = "badb-bags:inventory"
local DELAY = 0.12

local M = Badb.Modules:New("Bags", {
    title = L["Inventario"],
    category = L["Gioco"],
    description = L["Cerca oggetti nelle borse e nella banca di tutti i personaggi visitati."],
    defaults = { enabled = true },
    page = {
        title = L["Inventario"], category = L["Gioco"], order = 10,
        keywords = { SOURCES.bags, SOURCES.bank, "inventory", "Baganator", "Syndicator" },
    },
    replaces = {
        { addon = "Baganator", coverage = "partial",
          note = L["Ricerca unificata e banca personale. Spostamento, ordinamento e categorie personalizzate restano fuori da questa vista."] },
        { addon = "Syndicator", coverage = "partial",
          note = L["Archivio di borse e banca personale per personaggio. Esclude posta, equipaggiamento, aste e banca di gilda."] },
    },
})
Badb.Bags = M

function M:OnInitialize()
    local store = Badb.DB:GetStore("bags")
    self.characters = store and Inventory.OpenStore(store) or {}
end

function M:ResolveCharacter(selection)
    if selection == "all" or self.characters[selection] then return selection end
    return self.currentKey
end

local function validScope(scope)
    return SOURCES[scope] ~= nil or scope == "all"
end

function M:Find(query, scope, character)
    if not self.running then return {} end
    scope = validScope(scope) and scope or "all"
    local rows = Inventory.Rows(self.characters, self.live, scope, self:ResolveCharacter(character),
        self.currentKey, self.currentName, self.currentRealm)
    return Inventory.Filter(rows, query)
end

function M:Capture(source)
    local snapshot, missingNames = Inventory.Scan(source)
    self.live[source], self.missingNames[source] = snapshot, missingNames
    if not snapshot then return end
    local key, name, realm = Inventory.Character()
    if key then self.currentKey, self.currentName, self.currentRealm = key, name, realm end
    Inventory.Save(self.characters, self.currentKey, self.currentName, self.currentRealm, source, snapshot)
end

function M:Queue(source)
    self.pending[source] = true
    if self.scanQueued then return end
    self.scanQueued = true
    local generation = self.generation
    Compat.After(DELAY, function()
        if not self.running or self.generation ~= generation then return end
        self.scanQueued = false
        local pending = self.pending
        self.pending = {}
        if pending.bags then self:Capture("bags") end
        if pending.bank and self.bankOpen then self:Capture("bank") end
        self:RefreshView()
    end)
end

function M:OnEnable()
    self.running, self.bankOpen, self.scanQueued = true, false, false
    self.generation = (self.generation or 0) + 1
    self.pending, self.live, self.missingNames = {}, {}, {}
    self.currentKey, self.currentName, self.currentRealm = Inventory.Character()

    local function bagsChanged() self:Queue("bags") end
    local function bankChanged() if self.bankOpen then self:Queue("bank") end end
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE", "BAG_UPDATE_DELAYED", "BAG_CONTAINER_UPDATE", "KEYRING_UPDATE", "PLAYER_REGEN_ENABLED" }) do
        self:On(event, bagsChanged)
    end
    for _, event in ipairs({ "PLAYERBANKSLOTS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED", "BANK_TABS_CHANGED" }) do
        self:On(event, bankChanged)
    end
    self:On("BANKFRAME_OPENED", function()
        self.bankOpen = true
        bankChanged()
    end)
    self:On("BANKFRAME_CLOSED", function()
        self.bankOpen = false
        self.pending.bank, self.live.bank, self.missingNames.bank = nil, nil, nil
        self:RefreshView()
    end)
    local function itemDataLoaded(_, id, success)
        id, success = Compat.SafeValue(id), Compat.SafeValue(success)
        if type(id) ~= "number" or success ~= true then return end
        for source, missing in pairs(self.missingNames) do
            if missing[id] then self:Queue(source) end
        end
    end
    self:On("ITEM_DATA_LOAD_RESULT", itemDataLoaded)
    self:On("GET_ITEM_INFO_RECEIVED", itemDataLoaded)

    if BankFrame and type(BankFrame.IsShown) == "function" then
        local ok, shown = pcall(BankFrame.IsShown, BankFrame)
        self.bankOpen = ok and Compat.SafeValue(shown) == true
        if self.bankOpen then self.pending.bank = true end
    end
    self:Queue("bags")
end

function M:OnDisable()
    self.running, self.bankOpen = false, false
    self.pending, self.live, self.missingNames = {}, {}, {}
    if self.window then
        self.window:Hide()
        self.window.rows, self.window.snapshots = nil, nil
        self.window.list:SetData({})
    end
end

function M:OnProfileChanged()
    if self.window then
        self.window.character = "current"
        self:RefreshView(true)
    end
end

local function closeTooltip(row)
    if GameTooltip and type(GameTooltip.IsOwned) == "function" and GameTooltip:IsOwned(row) then
        UI:HideTooltip()
    end
end

local function showTooltip(row)
    local entry = row.item
    if not (entry and GameTooltip) then return end
    local item = entry.item
    if type(GameTooltip.SetOwner) == "function" and type(GameTooltip.SetHyperlink) == "function" then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, item.link or ("item:" .. item.id))
        if ok then
            GameTooltip:Show()
            return
        end
    end
    UI:Tooltip(row, entry.label, { entry.owner, SOURCES[entry.source] })
end

local function linkItem(row)
    local entry = row.item
    local link = entry and entry.item.link
    if link and type(IsModifiedClick) == "function" and type(ChatEdit_InsertLink) == "function" then
        local ok, modified = pcall(IsModifiedClick, "CHATLINK")
        if ok and Compat.SafeValue(modified) == true then pcall(ChatEdit_InsertLink, link) end
    end
end

local function createRow(parent)
    local sp, sizes = Theme.spacing, Theme.sizes
    local row = CreateFrame("Button", nil, parent)
    UI.AddHover(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(sizes.button, sizes.button)
    row.icon:SetPoint("LEFT", sp.sm, 0)
    row.name = UI:Label(row, nil, "body", "text")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", sp.sm, sp.sm)
    row.name:SetPoint("RIGHT", row, "RIGHT", -(sizes.button * 3), sp.sm)
    row.owner = UI:Label(row, nil, "small", "textDim")
    row.owner:SetPoint("LEFT", row.icon, "RIGHT", sp.sm, -sp.sm)
    row.owner:SetPoint("RIGHT", row, "RIGHT", -(sizes.button * 3), -sp.sm)
    row.amount = UI:Label(row, nil, "number", "text")
    row.amount:SetPoint("RIGHT", -sp.md, 0)
    local separator = UI:Separator(row, false, "divider")
    separator:SetPoint("BOTTOMLEFT", sp.sm, 0)
    separator:SetPoint("BOTTOMRIGHT", -sp.sm, 0)
    row:SetScript("OnEnter", showTooltip)
    row:SetScript("OnLeave", closeTooltip)
    row:SetScript("OnHide", closeTooltip)
    row:SetScript("OnClick", linkItem)
    return row
end

local function updateRow(row, entry)
    row.icon:SetTexture(entry.item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.name:SetText(entry.label)
    local state = entry.live and L["In tempo reale"] or L["Ultimo salvataggio"]
    row.owner:SetText(("%s  ·  %s  ·  %s"):format(entry.owner, SOURCES[entry.source], state))
    row.amount:SetText(tostring(entry.item.count))
    if row:IsMouseOver() then showTooltip(row) end
end

function M:CharacterOptions()
    local characters = {}
    for key, character in pairs(self.characters) do
        if key ~= self.currentKey then
            characters[#characters + 1] = { value = key, text = character.name .. " - " .. character.realm }
        end
    end
    table.sort(characters, function(a, b) return a.text < b.text end)
    table.insert(characters, 1, { value = "all", text = L["Tutti i personaggi"] })
    table.insert(characters, 1, { value = "current", text = L["Personaggio attuale"] })
    return characters
end

local function emptyText(window, filtered)
    if #window.rows > 0 and #filtered == 0 then return L["Nessun risultato. Prova il nome o l'ID dell'oggetto."] end
    if #window.snapshots > 0 then return L["Questa vista dell'inventario è vuota."] end
    if not Inventory.Available() then return UNAVAILABLE end
    if window.character ~= "current" then return L["Nessun inventario salvato per questa selezione."] end
    if window.scope == "bank" then return L["Visita un banchiere per salvare la banca di questo personaggio."] end
    return L["I dati delle borse non sono ancora disponibili."]
end

function M:ApplySearch(reset)
    local window = self.window
    if not (window and window.rows) then return end
    local filtered = Inventory.Filter(window.rows, window.query)
    if reset then window.list:ScrollToIndex(1) end
    window.list:SetData(filtered)
    window.empty:SetText(#filtered == 0 and emptyText(window, filtered) or "")
    local result = L["Righe: %d"]:format(#filtered)
    local one = #window.snapshots == 1 and window.snapshots[1]
    if one then
        result = L["%s  ·  %d/%d slot occupati"]:format(result, one.snapshot.occupied, one.snapshot.capacity)
        if not one.live and one.snapshot.time and type(date) == "function" then
            local ok, stamp = pcall(date, "%x %H:%M", one.snapshot.time)
            if ok and type(stamp) == "string" then result = result .. "  ·  " .. stamp end
        end
    end
    window.summary:SetText(result)
end

function M:RefreshView(reset)
    local window = self.window
    if not (window and window:IsShown()) then return end
    if window.character ~= "all" and window.character ~= "current" and not self.characters[window.character] then
        window.character = "current"
    end
    window.selector:Refresh()
    window.rows, window.snapshots = Inventory.Rows(self.characters, self.live, window.scope,
        self:ResolveCharacter(window.character), self.currentKey, self.currentName, self.currentRealm)
    self:ApplySearch(reset)
end

local function openNativeBags()
    if InCombatLockdown() then
        Logger:Warn(L["Apri le borse di WoW fuori dal combattimento."])
        return
    end
    if type(OpenAllBags) ~= "function" or not pcall(OpenAllBags) then
        Logger:Warn(L["Usa il tasto delle borse di WoW per gestire gli oggetti."])
        return
    end
    M.window:Hide()
end

function M:BuildWindow()
    if self.window then return self.window end
    local sp, sizes = Theme.spacing, Theme.sizes
    local window = UI:Window("BadbUIInventory", sizes.sidebar * 3 + sp.xl * 2, sizes.row * 14,
        L["Inventario"], { footer = true, resizable = true, minW = sizes.sidebar * 3, minH = sizes.row * 11,
        onClose = function(frame) frame.search.edit:ClearFocus() end })
    window.scope, window.character, window.query = "bags", "current", ""

    window.tabs = UI:Tabs(window.body, TABS, function(scope)
        window.scope = scope
        self:RefreshView(true)
    end)
    window.tabs:SetPoint("TOPLEFT", sp.lg, -sp.md)
    window.tabs:SetPoint("TOPRIGHT", -sp.lg, -sp.md)

    window.selector = UI:Dropdown(window.body, nil, function() return self:CharacterOptions() end,
        function() return window.character end,
        function(selection) window.character = selection; self:RefreshView(true) end,
        { width = sizes.sidebar })
    window.selector:SetPoint("TOPRIGHT", window.tabs, "BOTTOMRIGHT", 0, -sp.md)

    window.search = UI:EditBox(window.body, sizes.sidebar, sizes.button, {
        maxLetters = 120,
        placeholder = L["Cerca per nome o ID"],
        onChange = function(query)
            window.query = query
            if window.searchQueued then return end
            window.searchQueued = true
            Compat.After(DELAY, function()
                window.searchQueued = false
                if self.running and window:IsShown() then self:ApplySearch(true) end
            end)
        end,
    })
    window.search:SetPoint("TOPLEFT", window.tabs, "BOTTOMLEFT", 0, -sp.md)
    window.search:SetPoint("RIGHT", window.selector, "LEFT", -sp.sm, 0)

    window.list = UI:ScrollList(window.body, sizes.row + sp.xs, createRow, updateRow)
    window.list:SetPoint("TOPLEFT", window.search, "BOTTOMLEFT", 0, -sp.md)
    window.list:SetPoint("BOTTOMRIGHT", window.body, "BOTTOMRIGHT", -sp.lg, sp.sm)
    window.empty = UI:Label(window.list, nil, "body", "textDim")
    window.empty:SetWordWrap(true)
    window.empty:SetPoint("TOPLEFT", sp.sm, -sp.md)
    window.empty:SetPoint("TOPRIGHT", -sp.sm, -sp.md)

    local native = UI:Button(window.footer, L["Borse di WoW"], sizes.button * 5, sizes.button - sp.xs, openNativeBags, "ghost")
    window.native = native
    native:SetPoint("RIGHT", -sp.lg, 0)
    native:SetTooltip(L["Borse di WoW"], { L["Apri le borse del client per usare o spostare gli oggetti."] })
    window.summary = UI:Label(window.footer, nil, "small", "textDim")
    window.summary:SetPoint("LEFT", sp.lg, 0)
    window.summary:SetPoint("RIGHT", native, "LEFT", -sp.sm, 0)

    self.window = window
    return window
end

function M:Open(scope, query)
    if not self.running then return false, L["Attiva Inventario in BadbUI per aprirlo."] end
    local window = self:BuildWindow()
    if validScope(scope) then window.tabs:Select(scope) end
    if type(query) == "string" then
        window.query = query:sub(1, 120)
        window.search:SetText(window.query)
    end
    window:Show()
    self:RefreshView(true)
    self.pending.bank = self.bankOpen or nil
    self:Queue("bags")
    return true
end

local function open(scope, query)
    local ok, err = M:Open(scope, query)
    if not ok then Logger:Warn("%s", err) end
end

M.options = {
    { type = "label", text = function() return Inventory.Available() and M.description or UNAVAILABLE end },
    { type = "execute", label = SHOW, disabled = function() return not M.running end, func = function() open() end },
    { type = "execute", label = L["Guida all'inventario"], func = function()
        if Badb.Guides then Badb.Guides:Open(GUIDE_ID) end
    end },
}
M.commands = {
    bags = {
        help = L["bags [testo] - cerca nelle borse. Usa bags bank per la banca."],
        fn = function(args)
            args = type(args) == "string" and strtrim(args) or ""
            if args:lower() == "bank" then open("bank", "")
            elseif args ~= "" then open("bags", args)
            else open() end
        end,
    },
}

if Badb.Guides then
    Badb.Guides:Register({
        id = "badb-bags", title = L["Inventario"], category = L["Gioco"], version = 1,
        entries = { {
            id = "inventory", title = L["Guida all'inventario"], tags = { SOURCES.bags, SOURCES.bank },
            body = {
                { type = "step", text = L["Apri Gioco > Inventario in BadbUI oppure digita /badb bags."] },
                { type = "step", text = L["Scegli Borse o Banca, poi cerca un nome o un ID. Seleziona Tutti i personaggi per estendere la ricerca."] },
                { type = "step", text = L["Accedi a un personaggio per registrare le sue borse e visita un banchiere per registrare la sua banca."] },
                { type = "tip", text = L["Le righe salvate sono copie dell'ultima visita. Usa le borse di WoW per spostare o usare gli oggetti."] },
            },
        } },
    })
end
