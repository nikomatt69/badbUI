-- BadbUI - Confronto equipaggiamento, preferiti e bottini visti dal client.
local _, ns = ...
local Badb, L = ns.Badb, ns.Badb.L
local UI, Theme, Model = Badb.UI, Badb.Theme, Badb.LootModel

local M = Badb.Modules:New("Loot", {
    title = L["Bottino ed equipaggiamento"],
    category = L["Gioco"],
    description = L["Confronta due oggetti, salva gli obiettivi e consulta i bottini osservati."],
    defaults = { enabled = true, record = true, tooltip = false, weights = {} },
    replaces = {
        { addon = "Pawn", coverage = "partial",
          note = L["Pesi personalizzati e confronto esplicito. Restano fuori effetti, incavi, DPS delle armi e suggerimenti automatici."] },
        { addon = "AtlasLootClassic", coverage = "partial",
          note = L["Archivio dei bottini osservati e preferiti. Nessun catalogo precompilato di fonti o ricompense."] },
        { addon = "AtlasBIStooltips", coverage = "partial",
          note = L["Preferiti personali nei tooltip. Le liste BiS per classe e fase non sono incluse."] },
    },
    page = { title = L["Bottino ed equipaggiamento"], order = 65, category = L["Gioco"],
        keywords = { "loot", "pawn", "bis", L["Bottini osservati"], L["Pesi delle statistiche"] } },
})
Badb.Loot = M

local function clock()
    local ok, value = Model.Call(time)
    return ok and Model.Number(value, 0, 999999999999) or 0
end

local function weight(path)
    return M:Get("weights." .. path)
end

local function requestItem(id)
    local load = C_Item and C_Item.RequestLoadItemDataByID
    Model.Call(load, id)
end

function M:OnInitialize()
    self.store = Model.Open(Badb.DB:GetStore("loot"), clock())
end

function M:ObserveLoot()
    if not self.store or not self:Get("record") or not (GetNumLootItems and GetLootSlotLink) then return 0 end
    local ok, count = Model.Call(GetNumLootItems)
    if not ok or not Model.Number(count, 0, 1000) then return 0 end
    local zoneOK, zone = Model.Call(GetRealZoneText or GetZoneText)
    local area = zoneOK and Model.Text(zone, 120) or nil
    if not area then return 0 end
    local seen, at = 0, clock()
    for slot = 1, math.min(count, 80) do
        local linkOK, link = Model.Call(GetLootSlotLink, slot)
        if linkOK and Model.Observe(self.store, link, area, at) then seen = seen + 1 end
    end
    return seen
end

function M:ToggleFavorite(item)
    return Model.Favorite(self.store, item)
end

function M:IsFavorite(id)
    if not self.store then return false end
    for _, value in ipairs(self.store.favorites) do if value == id then return true end end
    return false
end

function M:Compare(candidate, baseline, loadMissing)
    if Badb.Compat.IsSecret(baseline) then return nil, "unavailable" end
    local left, reason, id = Model.Score(candidate, weight)
    if not left then
        if loadMissing and id then requestItem(id) end
        return nil, reason
    end
    local _, baseItem = Model.Item(baseline)
    if not baseItem and (baseline == nil or (type(baseline) == "string" and not baseline:find("%S"))) then return left end
    local right, baseReason, baseID = Model.Score(baseline, weight)
    if not right then
        if loadMissing and baseID then requestItem(baseID) end
        return nil, baseReason
    end
    if left.equip ~= right.equip then return nil, "slot" end
    return left, right, left.score - right.score
end

local function tooltipLine(tt)
    if not M.running or not M:Get("tooltip") or (InCombatLockdown and InCombatLockdown()) then return end
    local ok, _, link = Model.Call(tt.GetItem, tt)
    local id = ok and Model.Item(link)
    if not id then return end
    local scored = Model.Score(link, weight)
    if scored then tt:AddLine(string.format(L["BadbUI · Punteggio %.2f"], scored.score), Theme:Get("accent")) end
    if M:IsFavorite(id) then tt:AddLine(L["BadbUI · Oggetto nei preferiti"], Theme:Get("accent")) end
end

function M:OnEnable()
    self.running = true
    self:On("LOOT_OPENED", function()
        if self:ObserveLoot() > 0 then self:RefreshWindow() end
    end)
    self:On("ITEM_DATA_LOAD_RESULT", function()
        if not self.window or not self.window:IsShown() or self.refreshQueued then return end
        self.refreshQueued = true
        Badb.Compat.After(0.15, function()
            self.refreshQueued = false
            if self.running then self:RefreshWindow() end
        end)
    end)
    local post = TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
    local itemType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    if not self.tooltipHook and itemType and type(post) == "function" then
        self.tooltipHook = Model.Call(post, itemType, function(tt)
            if tt and type(tt.AddLine) == "function" then pcall(tooltipLine, tt) end
        end)
    end
end

function M:OnProfileChanged()
    if self.window and self.window:IsShown() then self:RefreshWindow() end
end

function M:OnDisable()
    self.running = false
    if self.window then self.window:Hide() end
end

local messages = {
    invalid = L["Inserisci un ID o un link oggetto valido."],
    unavailable = L["Le statistiche degli oggetti non sono disponibili su questo client."],
    loading = L["Dati oggetto in caricamento. Verifica l'ID e riprova."],
    equipment = L["Seleziona un oggetto equipaggiabile."],
    weights = L["Imposta almeno un peso nella pagina Bottino ed equipaggiamento."],
    slot = L["Scegli due oggetti dello stesso tipo di equipaggiamento."],
}

local function attachLabel(parent, font, color, top, offset)
    local label = UI:Label(parent, nil, font, color)
    label:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -offset)
    label:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(true)
    return label
end

function M:ShowComparison(loadMissing)
    local panel = self.window.compare
    local left, right, delta = self:Compare(panel.candidate:GetText(), panel.baseline:GetText(), loadMissing)
    if not left then
        panel.result:SetText(messages[right] or messages.unavailable)
    elseif not right then
        panel.result:SetText(string.format(L["%s · %.2f punti"], left.name, left.score))
    else
        panel.result:SetText(string.format(L["%s · %.2f punti\n%s · %.2f punti\nDifferenza: %+.2f"],
            left.name, left.score, right.name, right.score, delta))
    end
end

local function listRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row.name = UI:Label(row, nil, "body", "text")
    row.name:SetPoint("LEFT", Theme.spacing.sm, 0)
    row.name:SetPoint("RIGHT", -Theme.spacing.sm, 0)
    row.name:SetJustifyH("LEFT")
    UI.AddHover(row)
    row:SetScript("OnClick", function()
        local w = M.window
        if w and row.entry then
            w.compare.candidate:SetText(tostring(row.entry.id))
            w.tabs:Select("compare")
            M:ShowComparison(true)
        end
    end)
    return row
end

local function updateRow(row, entry)
    row.entry = entry
    row.name:SetText(entry.area and (entry.name .. " · " .. entry.area) or entry.name)
end

function M:RefreshWindow()
    local w = self.window
    if not w or not w:IsShown() then return end
    local isCompare = w.mode == "compare"
    w.compare:SetShown(isCompare)
    w.list:SetShown(not isCompare)
    if isCompare then
        if w.compare.candidate:GetText():find("%S") then self:ShowComparison(false) else w.compare.result:SetText("") end
        return
    end
    local rows = {}
    local favorites = w.mode == "favorites"
    local source = self.store and self.store[w.mode] or {}
    for _, entry in ipairs(source) do
        local id, area
        if favorites then id = entry else id, area = entry.id, entry.area end
        local _, _, name = Model.GetInfo(id)
        rows[#rows + 1] = { id = id, name = name or string.format(L["Oggetto #%d"], id), area = area }
    end
    w.list:SetData(rows)
    w.empty:SetText(favorites and L["Nessun preferito. Apri Confronta e salva un oggetto."] or
        L["Nessun bottino osservato. L'archivio si popola quando apri un bottino in gioco."])
    w.empty:SetShown(#rows == 0)
end

function M:BuildWindow()
    if self.window then return self.window end
    local sp, sz = Theme.spacing, Theme.sizes
    local w = UI:Window("BadbUILoot", sz.sidebar * 3 + sp.xl * 2, sz.row * 13,
        L["Bottino ed equipaggiamento"], { footer = true, onClose = function(win)
            win.compare.candidate.edit:ClearFocus()
            win.compare.baseline.edit:ClearFocus()
        end })
    w.mode = "compare"
    w.tabs = UI:Tabs(w.body, {
        { id = "compare", text = L["Confronta"] },
        { id = "favorites", text = L["Preferiti bottino"] },
        { id = "observed", text = L["Bottini osservati"] },
    }, function(mode)
        w.mode = mode
        self:RefreshWindow()
    end)
    w.tabs:SetPoint("TOPLEFT", sp.lg, -sp.md)
    w.tabs:SetPoint("TOPRIGHT", -sp.lg, -sp.md)
    local compare = CreateFrame("Frame", nil, w.body)
    w.compare = compare
    compare:SetPoint("TOPLEFT", w.tabs, "BOTTOMLEFT", 0, -sp.md)
    compare:SetPoint("BOTTOMRIGHT", -sp.lg, sp.sm)
    local description = UI:Label(compare, L["Incolla un link o digita l'ID dell'oggetto."], "body", "textDim")
    description:SetPoint("TOPLEFT")
    local inputWidth = sz.sidebar + sp.xl * 2
    compare.candidate = UI:EditBox(compare, inputWidth, sz.button,
        { placeholder = L["Oggetto da valutare"], maxLetters = 512, onEnter = function() self:ShowComparison(true) end })
    compare.candidate:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -sp.md)
    compare.baseline = UI:EditBox(compare, inputWidth, sz.button,
        { placeholder = L["Oggetto di riferimento (facoltativo)"], maxLetters = 512, onEnter = function() self:ShowComparison(true) end })
    compare.baseline:SetPoint("LEFT", compare.candidate, "RIGHT", sp.md, 0)
    local run = UI:Button(compare, L["Calcola punteggio"], sz.sidebar, sz.button,
        function() self:ShowComparison(true) end, "primary")
    run:SetPoint("TOPLEFT", compare.candidate, "BOTTOMLEFT", 0, -sp.md)
    local favorite = UI:Button(compare, L["Aggiungi o rimuovi preferito"], sz.sidebar + sp.xl * 2, sz.button, function()
        local changed, reason = self:ToggleFavorite(compare.candidate:GetText())
        local text = changed == true and L["Oggetto aggiunto ai preferiti."] or
            (changed == false and L["Oggetto rimosso dai preferiti."] or
            (reason == "limit" and L["Lista preferiti piena. Rimuovi un oggetto per continuare."] or messages.invalid))
        compare.result:SetText(text)
    end)
    favorite:SetPoint("LEFT", run, "RIGHT", sp.md, 0)
    compare.result = attachLabel(compare, "body", "text", run, sp.lg)
    w.list = UI:ScrollList(w.body, sz.row, listRow, updateRow)
    w.list:SetPoint("TOPLEFT", w.tabs, "BOTTOMLEFT", 0, -sp.md)
    w.list:SetPoint("BOTTOMRIGHT", -sp.lg, sp.sm)
    w.empty = UI:Label(w.list, nil, "body", "textDim")
    w.empty:SetPoint("TOPLEFT", sp.sm, -sp.sm)
    w.empty:SetPoint("TOPRIGHT", -sp.sm, -sp.sm)
    w.empty:SetWordWrap(true)
    local options = UI:Button(w.footer, L["Pesi delle statistiche"], sz.sidebar, sz.button - sp.xs,
        function() Badb.ConfigUI:OpenPage("Loot") end, "ghost")
    options:SetPoint("RIGHT", -sp.lg, 0)
    self.window = w
    w.list:Hide()
    return w
end

function M:Open(item)
    if not self.running then return false end
    local w = self:BuildWindow()
    w:Show()
    if Model.Item(item) then
        w.compare.candidate:SetText(item)
        w.tabs:Select("compare")
        self:ShowComparison(true)
    else
        self:RefreshWindow()
    end
    return true
end

M.options = {
    { type = "execute", label = L["Apri bottino ed equipaggiamento"], func = function() M:Open() end },
    { type = "toggle", path = "record", label = L["Archivia i bottini osservati"] },
    { type = "toggle", path = "tooltip", label = L["Punteggio e preferiti nei tooltip"] },
    { type = "header", label = L["Pesi delle statistiche"] },
    { type = "label", text = L["Assegna un peso alle statistiche rilevanti. Il valore zero esclude la statistica dal calcolo."] },
}
for _, def in ipairs(Model.stats) do
    M.options[#M.options + 1] = { type = "range", path = "weights." .. def.path, label = def.label, min = 0, max = 100, step = 0.1 }
end
M.commands = {
    loot = { help = L["loot [ID] - apre il confronto e l'archivio dei bottini"], fn = function(args)
        if not M:Open(args) then Badb.Logger:Info("%s", L["Attiva Bottino ed equipaggiamento per aprire il confronto."]) end
    end },
}
