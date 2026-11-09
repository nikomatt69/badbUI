# Integrazioni addon (modulo `Integrations`)

Hub per gestire gli addon terzi (ElvUI, Details!, Plater, Bartender4, BigWigs, DBM, Clique, WeakAuras, EllesmereUI) da BadbUI:
rileva l'addon, **cattura** il suo profilo/stato dentro il profilo BadbUI e lo **riapplica**. Poiche' i dati
stanno nel profilo, finiscono nell'export BadbUI (`DB:ExportProfile`) e viaggiano con esso.

## Cosa viene catturato (importante)
Gli adapter AceDB (Plater, Bartender4, BigWigs, ElvUI) e quelli di Details!/DBM salvano il **nome del profilo
attivo**, non il suo contenuto. Chi importa una stringa BadbUI ottiene il riferimento al profilo: se quel profilo
non esiste sul suo account, `Apply` non cambia nulla e segnala il warning `profilo mancante: 'X'` (non e' un
errore, `Status(id).lastWarning` lo conserva). Unica eccezione best-effort: **ElvUI**, se il modulo `Distributor`
espone `ExportProfile`/`ImportProfile`, cattura anche la stringa di export (max 40 KB) e la usa per ricreare un
profilo mancante.

## API (`Badb.Integrations`)
Nessun metodo lancia errori verso il chiamante: in errore ritornano `false, messaggio`.

| Metodo | Ritorno |
|---|---|
| `List()` | `{ {id, title, loaded, supported, hasProfile, reason, state, capturedAt, canReset, note, confidence}, ... }` (ordine di registrazione). `note` = avvertenza per l'utente (stringa, puo' essere vuota); `confidence` = `"A"`/`"B"`/`"C"` (affidabilita' dell'informazione su Forever: A confermato, B una fonte, C non verificato; i built-in sono solo B/C) |
| `Status(id)` | tabella estesa: `+ addon, unsupportedReason, corrupt, lastError, lastWarning, lastApplied`; `state` = `missing` / `installed` / `captured` / `unsupported` |
| `Capture(id)` | `ok, err` — salva `data[id]`; rifiuta payload > 64 KB (export serializzato), ciclici, troppo profondi |
| `Apply(id, opts?)` | `ok, err[, nota]` — backup `Backups:Create(..., "pre-import")` se `Badb.Backups` esiste (un backup fallito avvisa ma non blocca), fuori combattimento, poi `Events:Fire("BADB_INTEGRATION_APPLIED", id)`. In combattimento: `true, nil, "differito a fine combattimento"` (esegue a `PLAYER_REGEN_ENABLED`). Profilo mancante: `true, nil, "profilo mancante: ..."` e **nessun** evento |
| `ApplyAll(opts?)` | `ok, ultimoErrore, applicate, fallite` — un adapter che fallisce non blocca gli altri; `opts.noBackup` |
| `Reset(id)` | `ok, err` — ripristina i default dell'addon terzo (solo se l'adapter ha `reset`); backup prima; differito in combattimento |
| `Forget(id)` | elimina i dati catturati (non tocca l'addon terzo) |
| `RegisterAdapter(def)` | `ok, err` — vedi sotto; stessa `id` = sostituzione |

Estensione rispetto al contratto: `Status`, `ApplyAll`, `Reset`, `Forget`, e il terzo ritorno (nota/avviso) di `Apply`.

## Adapter di terze parti
```lua
Badb.Integrations:RegisterAdapter({
    id = "miaddon",              -- solo [A-Za-z0-9_-], max 64
    title = "Mio Addon", addon = "MioAddon",
    detect  = function() return C_AddOns.IsAddOnLoaded("MioAddon") end,
    capture = function() return { profile = MioAddonDB.profile } end,   -- tabella (o nil, "errore")
    apply   = function(payload) ... return true end,   -- true | false, "errore" | "skipped", "motivo"
    reset   = function() ... return true end,           -- opzionale
    note = "avvertenza", confidence = "C",  -- opzionali (default "" e "C"); noteFn = fn -> stringa per note dinamiche
    -- oppure, per sola visibilita': supported = false, unsupportedReason = "..."
})
```
Per addon AceDB: `Badb.IntegrationAdapterHelpers.aceDBAdapter(id, title, addon, dbGetter)` ritorna una def pronta.
`apply` riceve una **copia** del payload. Un adapter integrato puo' essere sostituito registrando la stessa `id`
(prima o dopo `OnInitialize`: la registrazione esterna ha sempre la precedenza).

## Dati salvati
Profilo BadbUI, modulo `Integrations`:
```lua
data = { [id] = { version = 1, capturedAt = time(), payload = { ... } } }
```
Opzione `autoApplyOnProfileChange` (default `false`): al cambio profilo BadbUI riapplica tutte le integrazioni
catturate (in `Events:RunOutOfCombat`, senza backup per non riempire la lista), con protezione anti-ricorsione
(i `BADB_PROFILE_CHANGED` generati durante un'applicazione vengono ignorati). Dati corrotti o di versione piu'
recente vengono trattati come "nessun dato" (`Status.corrupt`); una nuova `Capture` li ripara.

## ConfigUI e comandi
Pagina "Integrazioni" (categoria Strumenti): una riga per integrazione con icona di stato (non installato /
installato / catturato), pulsanti Cattura / Applica / Reset (Reset chiede conferma se `ConfigUI.Confirm` esiste),
riga con la motivazione per gli adapter `supported = false`. Le righe sono costruite alla apertura della pagina:
adapter registrati dopo compaiono alla riapertura.
`/badb integration list | capture <id> | apply <id> | reset <id> | forget <id>`.

## Stato delle API terze (best-effort, NON verificato in gioco)
Ogni accesso e' sondato e in `pcall`; se un metodo manca l'adapter degrada con un errore chiaro.

| Adapter | Rilevamento | API usate |
|---|---|---|
| ElvUI | addon `ElvUI`, globale `ElvUI` | `ElvUI[1].data` (AceDB) `GetCurrentProfile/SetProfile/ResetProfile`; opz. `E:GetModule("Distributor")` `ExportProfile(nome,"profile","text")` / `ImportProfile(str)` |
| Details! | `Details` | `GetCurrentProfileName` (o `GetCurrentProfile`), `GetProfileList`, `ApplyProfile`, `ResetProfile` |
| Plater | `Plater` | `Plater.db` (AceDB) |
| Bartender4 | `Bartender4` | `Bartender4.db` (AceDB) |
| BigWigs | `BigWigs` | `BigWigs.db` (AceDB) |
| DBM | `DBM-Core`, globale `DBM` | `DBM_UsedProfile`, `DBM_AllSavedOptions[nome]`, `DBM:ApplyProfile(nome)`; nessuna scrittura diretta sulle SavedVariables; senza `reset` |
| Clique | `Clique` | `Clique.db` (AceDB, solo nome profilo). Il click casting **integrato di Blizzard** (`C_ClickBindings`) non e' catturabile: viene solo sondato per mostrarlo nella nota, mai letto/scritto |
| EllesmereUI | `EllesmereUI` | nessuna: solo rilevamento, `supported = false` (API di profilo non nota) |
| WeakAuras | `WeakAuras` | nessuna: `supported = false` (nessuna API pubblica per catturare/applicare le aura; usare l'export nativo) |

Su Forever la disponibilita' degli addon terzi e' incerta (docs/FOREVER_FACTS.md: Plater nessun dato, WeakAuras
build non ufficiali, ElvUI secondo una sola fonte): l'assenza di un addon e' uno stato normale, mai un errore.

`detect` usa `C_AddOns.IsAddOnLoaded` (o `IsAddOnLoaded`) e il globale; se l'API non esiste basta il globale.
Un `SetProfile` AceDB su un profilo inesistente lo creerebbe vuoto: per questo l'esistenza e' verificata prima
(`db.sv.profiles` o `GetProfiles()`); se non verificabile si procede con `SetProfile`.

## Note e confidenza (docs/FOREVER_FACTS.md)
| id | confidence | note |
|---|---|---|
| elvui | B | build Forever segnalata da una fonte |
| details | B | meter real-time limitato nelle istanze (combat log non leggibile) |
| plater | C | non verificato |
| bartender4 | C | non verificato su Forever (API AceDB standard) |
| bigwigs, dbm | B | timer dalla timeline nativa, si cattura solo il profilo |
| clique | C | non verificato; solo il profilo Clique (+ avviso `C_ClickBindings` se presente) |
| weakauras | C | stato incerto su Forever (restrizioni stile Midnight, build non ufficiali) |
| ellesmereui | C | solo rilevamento: API di profilo non nota |

Gli addon UI in conflitto (ClassicUI Forever, Forever Unit Frames, ...) **non** sono integrazioni: li gestisce Diagnostics.

## Limiti noti
- Payload max 64 KB per integrazione (export serializzato), 20000 nodi, profondita' 12; valori secret, funzioni e
  NaN/inf vengono scartati.
- Cattura il riferimento al profilo, non i suoi dati (tranne ElvUI best-effort): vedi sopra.
- `Reset` e' distruttivo per l'addon terzo (ripristina i default del profilo attivo); il backup BadbUI non contiene
  i dati dell'addon terzo.
