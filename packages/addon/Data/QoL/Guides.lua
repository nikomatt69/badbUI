local _, ns = ...
local Badb = ns.Badb
local L = Badb.L
if not Badb.Guides then return end

Badb.Guides:Register({
    id = "qol",
    title = L["Comodità di gioco"],
    category = "BadbUI",
    version = 1,
    author = "BadbUI",
    entries = {
        {
            id = "automation",
            title = L["Bottino, mercanti e missioni con BadbUI"],
            tags = { L["Bottino"], L["Mercante"], L["Missioni"] },
            confidence = "B",
            body = {
                { type = "step", text = L["Apri /badb qol e attiva le automazioni che vuoi usare nel profilo corrente."] },
                { type = "step", text = L["Per riparare in automatico, imposta il limite di oro e apri un mercante che offre riparazioni. Tieni premuto Maiusc per saltare una visita."] },
                { type = "step", text = L["Con il mercante aperto, usa Vendi cianfrusaglie e conferma. Il client decide quali oggetti rientrano nella vendita."] },
                { type = "step", text = L["Per le missioni, apri il dettaglio del PNG. Usa Maiusc per leggere o scegliere manualmente. Se sono richiesti denaro, valuta o una scelta di ricompensa, completa la missione a mano."] },
                { type = "tip", text = L["Quando spegni il bottino automatico di BadbUI, torna il valore che avevi impostato nel client."] },
                { type = "warn", text = L["Da verificare in gioco: la disponibilità delle azioni dipende dalle API del client Forever."] },
            },
        },
    },
})
