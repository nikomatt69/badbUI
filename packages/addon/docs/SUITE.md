# BadbUI Suite 1.0 — contratto delle aree (leggere PRIMA di scrivere codice)

Obiettivo: **un solo addon**. BadbUI implementa da se' tutto cio' che oggi fanno gli altri addon installati
dall'utente, con un'unica interfaccia coerente, cosi' quegli addon possono essere spenti e rimossi.
Nessuna dipendenza da addon terzi, nessuna "integrazione": il modulo BadbUI fa il lavoro.

Restano validi `docs/CONTRACT.md` (regole di qualita' 1-10), `docs/UI.md` (design system) e
`docs/FOREVER_FACTS.md` (fatti del client). Questo file aggiunge le regole della Suite.

## Aree, file posseduti e addon da coprire

| Area | Cartelle possedute | Addon dell'utente da coprire |
|---|---|---|
| `bags` | `Modules/Bags/`, `Data/Bags/` | Baganator, Syndicator |
| `auction` | `Modules/Auction/`, `Data/Auction/` | Auctionator |
| `combat` | `Modules/Combat/`, `Data/Combat/` | Details (+ plugin), ThreatClassic2 |
| `encounters` | `Modules/Encounters/`, `Data/Encounters/` | BigWigs (+ Core/Options/Plugins), Capping, NovaInstanceTracker |
| `world` | `Modules/World/`, `Data/World/` | Leatrix_Maps, TomTom, GatherMate2, RareScanner, Atlas |
| `quests` | `Modules/Quests/`, `Data/Quests/` | Questie, QuestieDB, QuestieTrace, Polestar (+ sotto-addon) |
| `loot` | `Modules/Loot/`, `Data/Loot/` | AtlasLootClassic (+ sotto-addon), AtlasBIStooltips, Pawn |
| `qol` | `Modules/QoL/`, `Data/QoL/` | Leatrix_Plus, BlizzMove, BugSack, !BugGrabber, FrameSort, MiniAuras, MiniCC, UIScalaMinima, Mac-ever |

Ogni area possiede inoltre: `Locales/Suite/<Area>.lua` (traduzioni enUS delle proprie chiavi),
`tests/<area>*_test.lua`, `docs/<area>.md`, e **le sole righe dentro il proprio blocco** `# >>> area` ... `# <<< area`
di `BadbUI.toc` (prima riga del blocco: il file di traduzioni; poi dati e moduli nell'ordine di caricamento).

**Vietato** modificare qualunque altro file (Core, UI, Config, Locales/enUS.lua, itIT.lua, moduli esistenti,
runner e mock dei test, README). Se serve una modifica fuori dai propri file: descriverla nel report finale
("Richieste all'integratore") e, nel frattempo, degradare con una guardia.

## Codice originale (obbligatorio: il prodotto deve essere distribuibile)

Gli addon dell'utente sono in `/Volumes/SSD/World of Warcraft/_forever_/Interface/AddOns/` e si possono **leggere**
per due scopi soltanto: capire quali funzioni l'utente usa davvero (anche da
`.../WTF/Account/*/SavedVariables/<Addon>.lua`) e **quali API del client esistono su Forever** (gli addon con
`## Interface: 16001` girano su questo client: le API che chiamano esistono).
**Non copiare codice, tabelle dati, texture o testi** da quegli addon: hanno licenze proprie (GPL, All Rights
Reserved...). Tutto il codice e' scritto da zero; i dati arrivano dalle API del client a runtime, da cio' che il
giocatore incontra (apprendimento) o sono fatti verificabili citati in `FOREVER_FACTS.md`. Niente database di terzi.
Dove un addon vive di un database che non possiamo includere, il modulo usa le API del client e l'apprendimento,
dichiara `coverage = "partial"` e spiega in `note` cosa manca. **Mai fingere una copertura che non c'e'.**

## Sondare, non presumere

Nessuna API e' garantita: ogni chiamata al client passa da un controllo di esistenza e da `pcall` dove puo'
fallire; i valori del client passano da `Badb.Compat.IsSecret` prima di confronti e aritmetica. Se l'API manca, la
funzione si spegne da sola e la pagina lo dice con una riga chiara ("non disponibile su questo client").
Su Forever il combat log non e' leggibile dagli addon e salute/minaccia sono valori segreti (FOREVER_FACTS):
progettare di conseguenza (API native del client, non parsing del combat log).

## Descrittore del modulo

```lua
local M = Badb.Modules:New("Bags", {
    title = L["Borse"], category = L["Gioco"],            -- nuova categoria della sidebar per le aree di gioco
    description = L["..."],
    defaults = { enabled = true, ... },                    -- solo valori semplici, nel profilo
    replaces = {                                           -- letto da Badb.Suite (pagina "Addon sostituiti")
        { addon = "Baganator", title = "Baganator", coverage = "full" },
        { addon = "Syndicator", title = "Syndicator", coverage = "partial", note = L["..."] },
    },
    options = { ... }, page = { title = L["Borse"], order = 10, category = L["Gioco"], keywords = { ... } },
    commands = { bags = { help = L["..."], fn = function(args) end } },
})
Badb.Bags = M
```

* `addon` = nome esatto della cartella. Dichiarare ogni cartella coperta (anche i sotto-addon).
* `coverage = "full"` solo se, con il modulo acceso, l'utente non perde nulla di cio' che usa.
* Un'area puo' registrare piu' moduli (uno per funzione) cosi' l'utente li accende e spegne separatamente.
* Categorie pagina: `L["Gioco"]` per le funzioni di gioco, `L["Interfaccia"]`, `L["Strumenti"]`, `L["Gestione"]`.

## Dati

* Impostazioni: nel profilo (`M:Get/Set`).
* Dati voluminosi o per personaggio (inventari, prezzi, nodi, storico istanze, errori):
  `Badb.DB:GetStore("<area>")` -> tabella in `BadbUIDB.data.<area>`, fuori da backup/export/profili.
  Disponibile da `OnInitialize`. Campo `version`, limiti espliciti (righe, giorni), pulizia dei dati vecchi,
  tolleranza a dati corrotti (tipi sbagliati => ignorati e ripuliti).
* Mai nuove SavedVariables, mai globali nuovi.

## Interfaccia (coerenza: un solo linguaggio visivo)

* Solo `Badb.UI` e `Badb.Theme` (docs/UI.md): `UI:Window`, `UI:ScrollList`, `UI:Tabs`, `UI:Button`...,
  colori e misure dai token. Nessun template Blizzard, nessun colore o misura scritto a mano.
* Finestre di gioco (borse, contatore, mappa...) con nome `BadbUI<Nome>`; posizione ricordata dal design system.
* Frame liberi sullo schermo (barre timer, freccia, contatore): registrarli in `Badb.FrameManager:Register`
  cosi' si spostano con `/badb unlock` come tutti gli altri.
* Testo: chiavi `L[...]` in italiano nel codice, traduzione inglese in `Locales/Suite/<Area>.lua`
  (`ns.Badb.Localization:RegisterLocale("enUS", { ... })`). Ogni chiave nuova ha la sua traduzione.
  Etichette brevi, dicono cosa fa il controllo; errori che dicono cosa e' successo e cosa fare.
* Ogni stato vuoto ha un testo utile; ogni funzione non disponibile lo dice.
* Combat-safe: nessuna modifica a frame protetti in combattimento (`Events:RunOutOfCombat`).
* Prestazioni: niente lavoro per frame se non serve (OnUpdate con throttle), liste virtualizzate, nessuna
  allocazione nei percorsi caldi, eventi a raffica raggruppati (bucket con `C_Timer.After`).

## Guide per l'utente

Ogni area registra un pacchetto di guide in gioco con `Badb.Guides:Register(pack)` (vedi `docs/guides.md` e
`Data/Guides.lua` per il formato): come si usa la funzione, comandi, limiti. E `docs/<area>.md` per il sito.

## Test

`tests/<area>*_test.lua` (formato di CONTRACT.md regola 7). Le API del client mancanti nel mock si definiscono nel
proprio file di test (`Mock.Methods.X = ...`, globali impostati nel test). Coprire: percorso felice, API assenti,
valori segreti, input/dati salvati corrotti, combattimento, disattivazione con ripristino, cambio profilo.

Prima di consegnare, dalla cartella `packages/addon`, tutto verde:
```
luajit tests/run.lua . <area>      # durante lo sviluppo: solo le proprie suite (veloce)
luajit tests/run.lua .             # tutta la suite (lenta: alcuni minuti)
luajit tests/run_stub.lua && luajit tests/ui/run.lua .
```

## Consegna

Commit nel proprio worktree con messaggio chiaro in italiano, poi `git push -u origin HEAD`.
Report finale (max 30 righe): moduli e file creati, copertura dichiarata per ogni addon (full/partial e perche'),
API del client usate e cosa resta da verificare in gioco, risultati dei test, "Richieste all'integratore".
