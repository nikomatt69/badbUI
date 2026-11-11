local _, ns = ...
local Badb = ns.Badb
local L = Badb.L
if not Badb.Guides then return end

Badb.Guides:Register({
    id = "suite-combat", title = L["Statistiche di combattimento"], category = L["Gioco"], version = 1,
    entries = {
        {
            id = "meter", title = L["Leggere danni, cure e minaccia"], tags = { "dps", "hps", "details", "threat" },
            confidence = "B",
            body = {
                { type = "step", text = L["Apri il pannello con /badb combat oppure da /badb, nella sezione Gioco."] },
                { type = "step", text = L["In Resoconto scegli la statistica e lo scontro. Clicca un partecipante per vedere le magie, quando il dettaglio è disponibile."] },
                { type = "step", text = L["In Minaccia seleziona un nemico. La percentuale indica quanto ciascun partecipante è vicino a prendere l'aggro."] },
                { type = "tip", text = L["Trascina l'intestazione per spostare il pannello. Puoi anche usare /badb unlock."] },
                { type = "warn", text = L["Da verificare in gioco: la disponibilità delle statistiche dipende dalla versione del client e dalle restrizioni dell'incontro."] },
            },
        },
    },
})
