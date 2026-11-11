# Incontri e istanze

Apri **Gioco → Incontri e istanze** da `/badb`, oppure digita `/badb encounters`. La finestra segue il tema BadbUI e ricorda la posizione nel profilo. Trascina l’intestazione o usa `/badb unlock` per spostarla.

| Scheda | Comando | Dati |
|---|---|---|
| Boss | `/badb encounters boss` | Conto alla rovescia e stato degli eventi nativi dell'incontro |
| Campi di battaglia | `/badb encounters pvp` | Attesa trascorsa, attesa media, scadenza degli inviti e durata della partita |
| Visite | `/badb encounters visits` | Ultimi ingressi osservati su questo account, con personaggio ed esito dei boss |
| Salvataggi | `/badb encounters lockouts` | Reset e progressi dei salvataggi attivi del personaggio corrente |

Nelle opzioni puoi aprire il pannello all'inizio dei boss e sospendere la registrazione delle visite. La guida in gioco si apre con `/badb guide open suite-encounters:overview`.

I timer arrivano da `C_EncounterTimeline`. Se il client rende opaco il nome dell'abilità, la finestra lo passa solo alla funzione di visualizzazione consentita. Ordinamento e barre usano durate pubbliche. Le code leggono `GetBattlefieldStatus` e i relativi timer nativi. I salvataggi vengono richiesti all'apertura della scheda, fuori dal combattimento. [Definizioni Blizzard del timeline](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/EncounterTimelineDocumentation.lua).

Il registro conserva fino a 120 visite degli ultimi 90 giorni in `BadbUIDB.data.encounters`, per account. Una visita prosegue al ricaricamento della UI se il client espone la stessa mappa e difficoltà entro 12 ore. Cambi di mappa e rientri osservati avviano nuove visite. La durata dei reset arriva dal client e resta separata dal registro.

La copertura di BigWigs e dei suoi componenti, Capping e Nova Instance Tracker è parziale. Restano fuori gli avvisi personalizzati dei singoli boss, i timer degli obiettivi PvP, le previsioni di vittoria, il calcolo dei limiti d'ingresso e la condivisione dei registri. Le API e gli stati sono testati con il mock Lua. Sul client Forever restano da verificare gli eventi delle singole istanze e la resa dei timer nativi durante il combattimento.
