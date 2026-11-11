local _, ns = ...
local Badb, L = ns.Badb, ns.Badb.L
if not Badb.Guides then return end

Badb.Guides:Register({
    id = "loot", title = L["Bottino ed equipaggiamento"], category = L["Gioco"], version = 1,
    entries = {
        {
            id = "confronto", title = L["Confrontare equipaggiamento e salvare preferiti"],
            tags = { "loot", "pawn", "bis" },
            body = {
                { type = "step", text = L["Apri /badb loot e seleziona Pesi delle statistiche. Assegna pesi adatti al tuo ruolo."] },
                { type = "step", text = L["In Confronta inserisci un ID o un link oggetto. Puoi valutare un oggetto da solo o confrontarlo con uno dello stesso tipo."] },
                { type = "step", text = L["Aggiungi gli oggetti che cerchi ai Preferiti. La scheda Bottini osservati raccoglie gli oggetti che hai visto aprendo un bottino."] },
                { type = "warn", text = L["Il punteggio riguarda solo le statistiche esposte dal client. L'archivio non indica tassi di rilascio e non contiene liste BiS."] },
            },
        },
    },
})
