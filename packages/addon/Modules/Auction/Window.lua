local _, ns = ...
local Badb = ns.Badb
local L, UI, Theme = Badb.L, Badb.UI, Badb.Theme
local M, S = Badb.Auction, Badb.AuctionStore
local space, sizes = Theme.spacing, Theme.sizes

local function variant(name, item, itemID)
    local _, level, suffix, pet = item:match("^(%d+):(%d+):(-?%d+):(%d+)$")
    local text = name or string.format(L["Oggetto #%d"], itemID)
    if level and level ~= "0" then text = string.format(L["%s · livello %s"], text, level) end
    if suffix and suffix ~= "0" then text = string.format(L["%s · variante %s"], text, suffix) end
    if pet and pet ~= "0" then text = string.format(L["%s · specie %s"], text, pet) end
    return text
end

local function money(price)
    return price and M:FormatMoney(price) or L["—"]
end

local function day(at)
    return date("%Y-%m-%d", at)
end

local function createRow(parent)
    local row = CreateFrame("Button", nil, parent)
    UI.AddHover(row)
    row.label = UI:Label(row, nil, "body", "text")
    row.label:SetPoint("TOPLEFT", space.sm, -space.xs)
    row.detail = UI:Label(row, nil, "small", "textDim")
    row.detail:SetPoint("BOTTOMLEFT", space.sm, space.xs)
    row.value = UI:Label(row, nil, "number", "accent")
    row.value:SetPoint("RIGHT", -space.sm, 0)
    row.label:SetPoint("RIGHT", row.value, "LEFT", -space.sm, 0)
    row.detail:SetPoint("RIGHT", row.value, "LEFT", -space.sm, 0)
    row:SetScript("OnClick", function(self) if self.action then self.action() end end)
    return row
end

local function updateRow(row, item)
    row.label:SetText(item.name)
    row.detail:SetText(item.detail or "")
    row.value:SetText(item.value)
    row.action = item.action
    row:EnableMouse(item.action ~= nil)
end

local function buildWindow()
    local win = UI:Window("BadbUIAuction", sizes.sidebar * 4, sizes.row * 16, M.title,
        { subtitle = L["Ricerca e prezzi osservati"], footer = true })
    local body = win.body
    local mode, selected, detailKey, detailBack = "search", nil, nil, "history"
    local refresh, search

    local tabs = UI:Tabs(body, { { id = "search", text = L["Ricerca"] }, { id = "history", text = L["Storico"] } },
        function(id)
            mode, detailKey = id, nil
            if refresh then refresh() end
        end)
    tabs:SetPoint("TOPLEFT", space.lg, -space.sm)
    tabs:SetPoint("TOPRIGHT", -space.lg, -space.sm)
    tabs:SetHeight(sizes.tab)

    local input = UI:EditBox(body, nil, nil, {
        placeholder = L["Nome dell'oggetto"],
        maxLetters = S.MAX_SEARCH,
        onEnter = function() search() end,
        onChange = function() if refresh then refresh() end end,
    })
    input:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -space.md)

    local searchButton = UI:Button(body, L["Cerca"], sizes.row * 3, nil, function() search() end, "primary")
    searchButton:SetPoint("TOPRIGHT", tabs, "BOTTOMRIGHT", 0, -space.md)
    input:SetPoint("RIGHT", searchButton, "LEFT", -space.sm, 0)

    local saved = UI:Dropdown(body, nil, function()
        local items = {}
        for _, term in ipairs(S:ListSearches()) do items[#items + 1] = { value = term, text = term } end
        return items
    end, function() return selected end, function(value)
        selected = value
        input:SetText(value)
        refresh()
    end, { placeholder = L["Ricerche salvate"] })
    saved:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -space.sm)

    local save = UI:Button(body, L["Salva ricerca"], sizes.row * 4, nil, function()
        local ok, reason = S:SaveSearch(input:GetText())
        if ok then
            selected = S.NormalizeSearch(input:GetText())
            win.feedback = L["Ricerca salvata."]
        elseif reason == "duplicate" then
            win.feedback = L["Questa ricerca è già salvata."]
        elseif reason == "full" then
            win.feedback = L["Hai raggiunto il limite di ricerche salvate."]
        end
        refresh()
    end)
    save:SetPoint("TOPRIGHT", searchButton, "BOTTOMRIGHT", 0, -space.sm)

    local remove = UI:Button(body, L["Rimuovi"], sizes.row * 3, nil, function()
        if not selected then return end
        if S:DeleteSearch(selected) then
            selected = nil
            win.feedback = L["Ricerca rimossa."]
            refresh()
        end
    end, "ghost")
    remove:SetPoint("RIGHT", save, "LEFT", -space.xs, 0)
    saved:SetPoint("RIGHT", remove, "LEFT", -space.sm, 0)
    saved.button:SetPoint("LEFT")

    local status = UI:Label(body, "", "body", "textDim")
    status:SetWordWrap(true)
    status:SetPoint("TOPLEFT", saved, "BOTTOMLEFT", 0, -space.md)
    status:SetPoint("TOPRIGHT", save, "BOTTOMRIGHT", 0, -space.md)
    status:SetHeight(sizes.row)

    local headings = UI:Label(body, "", "small", "textMuted")
    headings:SetPoint("TOPLEFT", status, "BOTTOMLEFT", space.sm, -space.xs)
    local priceHeading = UI:Label(body, L["Prezzo da"], "small", "textMuted")
    priceHeading:SetPoint("TOPRIGHT", status, "BOTTOMRIGHT", -space.xl, -space.xs)

    local list = UI:ScrollList(body, sizes.row, createRow, updateRow)
    list:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -sizes.button)
    list:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -space.lg, space.lg)

    local note = UI:Label(win.footer, L["Conferma acquisti e vendite nella finestra Blizzard."], "small", "textDim")
    note:SetPoint("LEFT", space.lg, 0)
    local back = UI:Button(win.footer, L["Indietro"], sizes.row * 3, nil, function()
        tabs:Select(detailBack)
    end, "ghost")
    back:SetPoint("RIGHT", -space.sm, 0)

    local function openHistory(key)
        detailBack, mode, detailKey = mode, "detail", key
        refresh()
    end

    search = function()
        if mode ~= "search" then return end
        local ok, err = M:Search(input:GetText())
        win.feedback = ok and nil or err
        refresh()
    end

    refresh = function()
        local isSearch = mode == "search"
        local isHistory = mode == "history"
        local canSearch, reason = M:CanSearch()
        searchButton:SetShown(isSearch)
        searchButton:SetEnabled(canSearch and S.NormalizeSearch(input:GetText()) ~= nil)
        input:SetShown(isSearch or isHistory)
        saved:SetShown(isSearch)
        save:SetShown(isSearch)
        save:SetEnabled(S.NormalizeSearch(input:GetText()) ~= nil)
        remove:SetShown(isSearch)
        remove:SetEnabled(selected ~= nil)
        saved:Refresh()
        back:SetShown(mode == "detail")

        local rows, message = {}, nil
        if isSearch then
            headings:SetText(L["Oggetto"])
            priceHeading:SetText(L["Prezzo da"])
            local scope, market = M.resultScope, M.resultMarket
            for _, row in ipairs(M.results or {}) do
                local key = scope and market and (scope .. "|" .. market .. "|" .. row.item)
                rows[#rows + 1] = {
                    name = variant(row.name, row.item, row.itemID),
                    detail = row.quantity and string.format(L["Disponibili: %d"], row.quantity),
                    value = money(row.price),
                    action = key and row.price and M.resultSaved and function() openHistory(key) end or nil,
                }
            end
            if win.feedback then
                message = win.feedback
            elseif M.status then
                message = M.status
            elseif M.term then
                if #rows == 0 then
                    message = string.format(L["Nessun risultato per «%s»."], M.term)
                elseif M.partial then
                    message = string.format(L["Risultati iniziali per «%s» · %d"], M.term, #rows)
                else
                    message = string.format(L["Risultati per «%s» · %d"], M.term, #rows)
                end
            else
                message = reason or L["Cerca un oggetto per confrontare i prezzi del mercato attivo."]
            end
        elseif isHistory then
            headings:SetText(L["Oggetto e mercato"])
            priceHeading:SetText(L["Ultima osservazione"])
            for _, row in ipairs(S:ListHistory(M.scope, input:GetText())) do
                local entry, key = row.entry, row.key
                rows[#rows + 1] = {
                    name = variant(entry.name, entry.item, entry.itemID),
                    detail = entry.market .. " · " .. day(entry.samples[1].at),
                    value = money(entry.samples[1].price),
                    action = function() openHistory(key) end,
                }
            end
            message = #rows == 0 and L["Nessuna osservazione locale corrispondente."]
                or L["Seleziona un oggetto per vedere le osservazioni degli ultimi 21 giorni."]
        else
            headings:SetText(L["Data"])
            priceHeading:SetText(L["Prezzo osservato"])
            local entry, samples = S:GetHistory(detailKey)
            if entry then
                message = variant(entry.name, entry.item, entry.itemID) .. " · " .. entry.market
                for _, sample in ipairs(samples) do
                    rows[#rows + 1] = { name = day(sample.at), value = money(sample.price) }
                end
            end
            if #rows == 0 then message = L["Non ci sono osservazioni recenti per questo oggetto."] end
        end
        status:SetText(message or "")
        list:SetData(rows)
    end

    win.Refresh = refresh
    win.OnOpen = refresh
    Badb.Events:On(win, "BADB_AUCTION_CHANGED", function()
        if win:IsShown() then
            win.feedback = nil
            refresh()
        end
    end)
    return win
end

function M:Open()
    if not self.active then return false, L["Modulo Casa d'aste disattivato."] end
    self.window = self.window or buildWindow()
    self.window:Show()
    return true
end

M.page = {
    title = M.title, order = 20, category = M.category,
    keywords = { "Auctionator", L["mercato"], L["storico"], L["prezzi"] },
}
M.options = {
    { type = "execute", label = L["Apri Casa d'aste BadbUI"], func = function()
        local ok, err = M:Open()
        if not ok then Badb.Logger:Warn("%s", err) end
    end },
    { type = "toggle", path = "tooltipPrice", label = L["Ultimo prezzo delle merci nel tooltip"],
      desc = L["Mostra l'ultima osservazione locale per le merci senza varianti."] },
    { type = "execute", label = L["Apri la guida alla casa d'aste"], func = function()
        if Badb.Guides then Badb.Guides:Open("auction:market") end
    end },
}
M.commands = {
    auction = { help = L["auction - apri ricerca e storico della casa d'aste"], fn = function()
        local ok, err = M:Open()
        if not ok then Badb.Logger:Warn("%s", err) end
    end },
}
