local _, ns = ...
local Badb = ns.Badb
local L = Badb.L
if not Badb.Guides then return end

Badb.Guides:Register({
    id = "auction", title = L["Casa d'aste"], category = "BadbUI", version = 1, author = "BadbUI",
    entries = {
        {
            id = "market", title = L["Ricercare prezzi e consultare lo storico delle aste"],
            tags = { L["mercato"], L["storico"], L["prezzi"] }, confidence = "B",
            body = {
                { type = "step", text = L["Parla con un banditore, poi digita /badb auction. Inserisci il nome dell'oggetto e premi Cerca."] },
                { type = "step", text = L["Usa Salva ricerca per ritrovare il termine nel menu. Selezionare una voce compila il campo e puoi avviare la ricerca con Cerca."] },
                { type = "step", text = L["Apri Storico e seleziona un oggetto per vedere i prezzi osservati negli ultimi 21 giorni in quel mercato."] },
                { type = "tip", text = L["Per valutare un'inserzione, confronta lo storico con i prezzi correnti e conferma la vendita dalla finestra Blizzard."] },
                { type = "warn", text = L["Da verificare in gioco: la disponibilità delle ricerche dipende dalle API di Forever e dal mercato aperto."] },
            },
        },
    },
})
