local _, ns = ...
local Badb = ns.Badb
local L, UI, Theme, Logger = Badb.L, Badb.UI, Badb.Theme, Badb.Logger
local M = Badb.QoL
local page

local function section(stack, parent, text)
    stack:Add(UI:SectionHeader(parent, text), Theme.sizes.button)
end

local function toggle(stack, parent, controls, path, label, description, available)
    local control = UI:Toggle(parent, label, function() return M:Get(path) == true end,
        function(value) M:Set(path, value) end, { desc = description })
    controls[#controls + 1] = { control = control, available = available }
    stack:Add(control, Theme.sizes.row)
end

local function build(parent)
    local stack = UI:Stack(parent)
    local controls = {}

    section(stack, parent, L["Bottino"])
    toggle(stack, parent, controls, "autoLoot", L["Attiva il bottino automatico"],
        L["Usa l'opzione del client per il profilo attivo. Quando la disattivi, BadbUI ripristina il valore precedente."],
        M.HasLootAPI)

    section(stack, parent, L["Mercante"])
    toggle(stack, parent, controls, "autoRepair", L["Ripara al mercante"],
        L["Usa l'oro del personaggio fino al limite indicato. Tieni premuto Maiusc quando apri il mercante per riparare a mano."],
        M.HasRepairAPI)
    local cap = UI:Slider(parent, L["Limite di spesa per visita"], 1, 100, 1, function()
        return M:GetRepairCap()
    end, function(value)
        M:Set("repairCap", value)
    end, { format = L["%d oro"], live = false })
    controls[#controls + 1] = { control = cap, available = function()
        return M:HasRepairAPI() and M:Get("autoRepair") == true
    end }
    stack:Add(cap, Theme.sizes.row)

    local junk = UI:Button(parent, L["Vendi cianfrusaglie"], nil, nil, function() M:ConfirmJunkSale() end)
    stack:Add(junk, Theme.sizes.button)
    local junkStatus = UI:Label(parent, "", "small", "textDim")
    junkStatus:SetWordWrap(true)
    stack:Add(junkStatus, Theme.sizes.button)

    section(stack, parent, L["Missioni"])
    toggle(stack, parent, controls, "autoAccept", L["Accetta dal dialogo del PNG"],
        L["Apri il dettaglio della missione. Tieni premuto Maiusc per scegliere a mano."],
        M.HasAcceptAPI)
    toggle(stack, parent, controls, "autoComplete", L["Consegna senza scelta di ricompensa"],
        L["Apri il dialogo di consegna. Spese in denaro o valuta e scelte di ricompensa richiedono l'intervento del giocatore."],
        M.HasCompleteAPI)

    local status = UI:Label(parent, "", "small", "textDim")
    status:SetWordWrap(true)
    stack:Add(status, Theme.sizes.header)

    local guide = UI:Button(parent, L["Apri la guida alle automazioni"], nil, nil, function()
        if Badb.Guides then
            local ok, err = Badb.Guides:Open("qol:automation")
            if not ok then Logger:Warn("%s", err) end
        end
    end, "ghost")
    stack:Add(guide, Theme.sizes.button)

    page = { controls = controls, junk = junk, junkStatus = junkStatus, status = status }
    M:RefreshPage()
    return stack:Height()
end

function M:RefreshPage()
    if not page then return end
    for _, item in ipairs(page.controls) do
        item.control:SetEnabled(self.active and item.available(self))
        item.control:Refresh()
    end

    local count = self:GetJunkCount()
    local locked = InCombatLockdown()
    page.junk:SetEnabled(count ~= nil and count > 0 and not locked and not self.junkPending)
    if not self:HasJunkAPI() then
        page.junkStatus:SetText(L["Vendita di cianfrusaglie non disponibile su questo client."])
    elseif not self.merchantOpen then
        page.junkStatus:SetText(L["Apri un mercante per vedere le cianfrusaglie disponibili."])
    elseif count == nil then
        page.junkStatus:SetText(L["La vendita di cianfrusaglie non è disponibile presso questo mercante."])
    elseif count == 0 then
        page.junkStatus:SetText(L["Il client non ha rilevato cianfrusaglie vendibili."])
    else
        page.junkStatus:SetText(string.format(L["Cianfrusaglie rilevate dal client: %d."], count))
    end

    local missing = {}
    if not self:HasLootAPI() then missing[#missing + 1] = L["bottino automatico"] end
    if not self:HasRepairAPI() then missing[#missing + 1] = L["riparazioni"] end
    if not self:HasAcceptAPI() then missing[#missing + 1] = L["accettazione missioni"] end
    if not self:HasCompleteAPI() then missing[#missing + 1] = L["consegna missioni"] end
    if not self.active then
        page.status:SetText(L["Attiva il modulo dalla panoramica di BadbUI per usare queste funzioni."])
    elseif locked then
        page.status:SetText(L["Le azioni automatiche restano sospese durante il combattimento."])
    elseif #missing > 0 then
        page.status:SetText(string.format(L["Non disponibile su questo client: %s."], table.concat(missing, ", ")))
    else
        page.status:SetText(L["Tieni premuto Maiusc per sospendere riparazioni e missioni automatiche."])
    end
end

M.page = {
    title = M.title,
    order = 80,
    category = M.category,
    keywords = { L["bottino automatico"], L["riparazioni"], L["accettazione missioni"], L["consegna missioni"], "Leatrix" },
    build = build,
    refresh = function() M:RefreshPage() end,
}

M.commands = {
    qol = { help = L["qol - apre le impostazioni di comodità di gioco"], fn = function()
        if Badb.ConfigUI then Badb.ConfigUI:OpenPage(M.name) end
    end },
}
