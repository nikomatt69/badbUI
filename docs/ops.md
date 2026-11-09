# Ops: Backups e Diagnostics

Due moduli "enterprise" indipendenti (nessuna dipendenza hard tra loro; usano `Badb.X and ...` verso gli altri).

## Backups (`Badb.Backups`, modulo "Backups", pagina "Gestione")

Snapshot completo di `BadbUIDB`: `profiles`, `profileKeys`, `specProfiles`, `global` (esclusi i backup stessi, quindi niente crescita a spirale;
includono `global.roleOverrides` di `Badb.Player`). Salvati in `Badb.DB.sv.global.backups`: lista in ordine cronologico di
`{ id, label, kind, time, size, data }`. L'id (`bk<time>-<n>`) e' univoco e non cambia. Il tempo viene da `time()` con fallback
(`GetServerTime`, `os.time`, `GetTime`).

| API | Note |
|---|---|
| `Create(label, kind?)` -> id \| nil, err | kind: `manual` (default), `auto`, `pre-import`, `pre-preset`, `pre-restore`, `pre-repair`, ... |
| `List()` | `{ {id,label,kind,time,size}, ... }`, piu' recente prima |
| `GetInfo(id)` | metadati + nomi dei profili + `valid` |
| `Restore(id)` -> ok, err | in combattimento ritorna `true, "differito"` ed esegue a fine combattimento (annullato da OnDisable) |
| `Delete(id)`, `Prune()` | `Prune` applica la retention e ritorna quanti backup ha eliminato |
| `Export(id)` -> stringa, `Import(str, label)` -> id | `Badb.Serializer` con kind `"backup"`; l'import aggiunge un backup (kind `imported`), **non lo applica** |
| `Validate(snapshot)`, `EstimateSize(tbl)` | utilita' pubbliche |

Nessuna funzione lancia errori. Eventi: `BADB_BACKUP_CREATED(id)`, `BADB_BACKUP_RESTORED(id)`.

**Retention** (opzioni del modulo): `maxBackups` (20), `maxSizeKB` (1024, dimensione totale stimata), `autoOnLogin` (true), `autoHours` (24).
Per fare spazio si ruotano prima i backup non protetti (tutto tranne `manual`/`imported`), dal piu' vecchio. I protetti si eliminano
solo se il *numero* massimo non e' rispettabile in altro modo (si perde il piu' vecchio). Il limite di *dimensione* non elimina mai
backup protetti: `Create` rifiuta con "spazio insufficiente..." (o "backup troppo grande" se un solo snapshot supera il limite).
La dimensione e' una stima della serializzazione (stessa forma del Serializer, senza costruire la stringa).

**Backup automatico**: in `OnEnable` (cioe' al login) se non esiste un `auto` piu' recente di `autoHours`. Gli altri moduli chiamano
`Create(label, "pre-...")` prima delle operazioni distruttive (le API restano utilizzabili anche a modulo disattivato).

**Restore transazionale**: valida lo snapshot (schema, tipi, profondita', nessuna metatable/funzione, schema non piu' recente del DB) e ne
costruisce una copia; se qualcosa non va il DB non e' stato toccato e non viene creato nessun backup. Poi crea il backup `pre-restore`,
scambia le quattro sezioni *in place* (i riferimenti a `sv.global` ecc. restano validi), mantiene l'elenco dei backup, chiama
`DB:SetProfile` sul profilo del personaggio (`profileKeys[char]`, fallback "Default"), ripristina la config dei frame
(vedi "Richieste al core") e chiama `Badb.Player:Invalidate()` se esiste.

**Comandi**: `/badb backup create [etichetta] | list | restore <id|n> | delete <id|n>` (`n` = posizione in `list`, 1 = piu' recente).

**Pagina**: lista (data, etichetta, kind, dimensione) con Ripristina (con `UI:Confirm` se esiste), Esporta (`UI:TextBox`), Elimina; Crea backup, Importa.

**Privacy**: un export contiene `profileKeys`/`specProfiles`, cioe' i nomi "Personaggio - Reame": condividilo con cautela.

## Diagnostics (`Badb.Diagnostics`, modulo "Diagnostics", pagina "Strumenti")

`RunChecks()` -> `{ {id, level = ok|warn|error, title, detail, fix = fn|nil}, ... }`. La lista dei controlli e' `Diagnostics.checks`
(`{ id, fn }`; `fn` ritorna un risultato o una lista): ogni controllo e' in `pcall`, se lancia diventa `error` "Check fallito: <id>".

| Check | Cosa verifica |
|---|---|
| `db` | schema, profili/`modules`/`frames` di tipo errato, `profileKeys`/`specProfiles` che puntano a profili inesistenti, elenco backup corrotto. Ogni problema ha un `fix` che prima crea un backup `pre-repair` (senza Backups: copia locale in memoria) e se il backup fallisce si ferma |
| `client`, `api` | `Compat.interface` vs riga Interface del TOC (se leggibile), `Compat.isForever`, Edit Mode / Settings API |
| `modules` | modulo attivo nel profilo ma non in esecuzione; errori `ERROR` nel `Logger.buffer` attribuiti per prefisso `Nome:` (o `Listener Nome su`) |
| `conflicts` | addon di interfaccia noti (lista dati-driven `KNOWN_ADDONS` in testa al file) via `C_AddOns.IsAddOnLoaded`, con i moduli BadbUI coinvolti |
| `playerinfo` | `Badb.Player:GetSnapshot()`: talenti illeggibili (`trees == nil`), confidenza ruolo bassa -> suggerisce `/badb role` |
| `restrictions` | informativo: secret values e combat log non leggibile (FOREVER_FACTS), con sonde di `issecretvalue`/`CombatLogGetCurrentEventInfo` |
| `cvar` | `countdownForCooldowns` coerente col modulo Cooldowns (fix: imposta "1") |
| `size` | avviso oltre ~2 MB stimati |
| `frames` | frame del FrameManager che non si risolvono |
| `luaerrors` | errori Lua catturati |

**Aggiungere un addon in conflitto**: una riga in `KNOWN_ADDONS`: `{ title, addons = { varianti del nome cartella }, modules = { moduli BadbUI }, note }`.
I nomi cartella degli addon Forever non sono verificati (confidenza B): per questo ci sono piu' varianti.

**Cattura errori**: in `OnEnable` concatena `seterrorhandler` (registra e inoltra SEMPRE al precedente, in `pcall`); filtra per messaggio o
`debugstack` che contiene "BadbUI"; deduplica per messaggio (contatore); buffer circolare da 50. `OnDisable` ripristina l'handler
precedente solo se e' ancora il nostro (altrimenti resta in catena ma inerte). `GetErrors()` (piu' recente prima), `ClearErrors()`.

**Report()**: versione addon/client/interface, locale, stato moduli, profilo attivo, snapshot PlayerInfo (classe, ruolo, fonte,
confidenza, gruppo talenti), risultati dei check, ultimi 20 log, ultimi errori Lua, addon di interfaccia caricati. Privacy: il personaggio e'
un hash corto (`#a1b2c3`), nome e reame vengono sostituiti ovunque nel testo (`<pg>`, `<reame>`), nessun contenuto dei profili.

**Statistiche** (`GetStats()`): memoria dell'*intero addon* solo se `GetAddOnMemoryUsage` esiste (`UpdateAddOnMemoryUsage` al massimo ogni
30 s); per modulo: stato, errori recenti e byte stimati dei dati salvati (la memoria per modulo non e' misurabile dal client).

**Comandi**: `/badb doctor run | report | errors`; `/badb role <tank|healer|dps|auto>` imposta l'override del ruolo con
`Badb.Player:SetRoleOverride`, validato contro `Player.CLASSES[classe].roles`.

## Limiti noti
- Il ripristino di uno snapshot con schema piu' vecchio imposta `sv.schema` al valore dello snapshot: le migrazioni girano al prossimo login.
- `UI:TextBox` e' chiamato come metodo (`UI:TextBox(title, text, onAccept?)`, come da contratto); l'attuale `Config/ConfigUI.lua` lo espone ancora
  come funzione semplice finche' shell non lo aggiorna.
