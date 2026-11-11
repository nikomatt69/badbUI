local _, ns = ...
local Badb = ns.Badb
local L = Badb.L
if not Badb.Guides then return end

Badb.Guides:Register({
    id = "suite-encounters", title = L["Incontri e istanze"], category = L["Gioco"], version = 1,
    entries = {
        {
            id = "overview", title = L["Seguire incontri, code e salvataggi"], tags = { "boss", "pvp", "lockout" },
            confidence = "B",
            body = {
                { type = "step", text = L["Apri Incontri e istanze in /badb oppure digita /badb encounters."] },
                { type = "step", text = L["Nella scheda Boss leggi i timer esposti dal client. Puoi far aprire il pannello automaticamente all'inizio di un incontro."] },
                { type = "step", text = L["In Campi di battaglia trovi code e inviti. Apri Visite per il registro locale e Salvataggi per le scadenze del personaggio attivo."] },
                { type = "warn", text = L["Da verificare in gioco: i timer disponibili dipendono dall'incontro e dalle API del client."] },
            },
        },
    },
})
