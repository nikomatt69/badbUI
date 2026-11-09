# Guides: libreria di guide in-game

Guide testuali (classi, dungeon, raid, PvP, uso di BadbUI) con link ai video **da copiare**: un addon non puo' riprodurre video ne' aprire il browser.

File: `Modules/Guides.lua` (logica + viewer + modulo), `Data/Guides.lua` (contenuto bundled), `tests/guides_test.lua`.

## API (`Badb.Guides`, esiste gia' al caricamento del file)
`Badb.Guides` e' una tabella API **separata** dal descrittore del modulo (`ModuleProto:Get(path)` e' gia' usato per le opzioni, mentre il contratto vuole `Guides:Get(entryId)`). Il modulo si chiama `"Guides"`; `Badb.Guides.module` ne e' il descrittore.

| Funzione | Ritorno |
|---|---|
| `:Register(pack)` | `packId, {entries, skipped, errors}` oppure `nil, err` (mai errori Lua; warning nel Logger). Funziona anche prima dell'init del DB |
| `:Unregister(packId)` | `true` / `false, err` |
| `:Search(query, filter?)` | array di riepiloghi `{id, entryId, packId, title, category, tags, zone, level, steps, confidence, score}`, max 50 |
| `:ListEntries(filter?)` | come Search senza query e senza tetto di 50 (max 2000), in ordine di registrazione |
| `:Get(entryId)` | copia completa (con `body`, `links`) o `nil, err` |
| `:ListPacks()`, `:ListCategories()` | `{id,title,category,version,author,count}` / `{name,count}` |
| `:Open(entryId?)` | `true` o `nil, err`; apre il viewer (senza id riprende l'ultima guida). Rifiutato se il modulo e' disattivo |
| `:OpenLibrary(query?)`, `:Close()` | apre il viewer con la ricerca precompilata / lo chiude |
| `:Bookmark(entryId, bool?)`, `:IsBookmarked`, `:GetBookmarks()` | `bool` nil = inverte |
| `:GetProgress(entryId)` | `fatti, totale` (step spuntati / step della guida) |
| `:SetProgress(entryId, n)` | segna i primi `n` step (clamp 0..totale) |
| `:SetStep(entryId, i, bool?)`, `:GetStepsDone(entryId)` | singolo step |
| `:GetLastOpened()`, `:GetRecent(n?)` | ultime guide aperte |
| `:Cleanup()` | rimuove dal salvataggio riferimenti a guide inesistenti; ritorna il numero di voci rimosse (eseguita a ogni `OnEnable`) |
| `:CheckZone()`, `:FindByZone(zona)`, `:ResetSuggestions()` | suggerimento contestuale |
| Pure: `G.Sanitize(s)`, `G.IsValidUrl(u)`, `G.Fold(s)`, `G.ParseQuery(q)`, `G.SearchList(entries, q, filter, limit)` | nessuno stato |

Evento: `BADB_GUIDE_OPENED(entryId)`. Comando: `/badb guide [open [id]] | search <testo> | bookmarks`. Pagina ConfigUI "Guide" (categoria "Contenuti"): ricerca rapida, ultime guide, segnalibri, "Apri libreria", opzione `autoSuggest`.

## Formato di un pack
```lua
Badb.Guides:Register({
  id = "mio-pack", title = "Il mio pack", category = "Raid", version = 1, author = "Nome",
  entries = {
    { id = "intro", title = "Titolo", tags = { "raid", "tank" }, zone = "Nome zona" --[[ o lista ]], level = 60 --[[ o {min,max} ]],
      confidence = "A", -- A (default) | B | C, come docs/FOREVER_FACTS.md
      body = {
        { type = "h", text = "Titolo di sezione" },
        { type = "p", text = "Paragrafo" },
        { type = "list", items = { "uno", "due" } },
        { type = "step", text = "Passo spuntabile" },   -- alimenta il progresso
        { type = "tip", text = "Consiglio" },
        { type = "warn", text = "Attenzione" },
      },
      links = { { label = "Video", url = "https://..." } },
    },
  },
})
```
`entryId` globale = `"<packId>:<entryId>"`. Id: `[%w_-.]` fino a 64 caratteri (il packId non puo' contenere `:`).

### Validazione
- Pack invalido (non tabella, id/titolo/category/version/author non validi, `entries` mancante, >500 entry, >2 MB di testo, nessuna entry valida) => `nil, err` e `Logger:Warn`.
- Entry invalida => **saltata** con warning (le altre restano): id non valido o duplicato, titolo mancante/>200, >200 blocchi, tipo di blocco sconosciuto, testo >4000 byte (anche per le voci di lista), `tags/zone/level/confidence` non validi, **link non http/https**. Max 20 tag, 10 zone, 100 voci per lista, 20 link.
- Sanificazione di **ogni** stringa: restano solo i colori `|cAARRGGBB...|r` (un colore non chiuso viene chiuso) e `|T...|t` con path `Interface\Icons\...`, marcatori raid o file ID numerici; `|H...|h` (hyperlink), `|A`, `|K`, texture non whitelisted, codici sconosciuti e caratteri di controllo sono rimossi; una `|` isolata diventa `||`.
- Link: solo `http://` / `https://`, niente spazi, `|`, `@` nell'host. L'URL e' mostrato in un EditBox di sola lettura (selezione + Ctrl+C), **mai aperto**.

## Ricerca
Case/accent-insensitive (`G.Fold`, lettere latine comuni e apostrofi/trattini tipografici), multi-termine in AND (max 8 termini, query max 200 caratteri). Punteggio per termine: titolo 100 (130 a inizio parola) > tag 70 esatto / 50 parziale > zona 30 > categoria/pack 20 > corpo 10; +50 se la frase intera e' nel titolo. A parita': titolo alfabetico. Filtri: `category`, `tag`, `zone` (sottostringa), `level` (entry con livello scalare = "da n in su", con `{min,max}` = intervallo; senza livello = sempre), `pack`, `bookmarked`.

## Dati salvati
`BadbUIDB.global.guides` (per account, non legato al profilo): `{ bookmarks = {[id]=true}, progress = {[id]={done={[i]=true}}}, lastOpened = id, recent = {id,...} }`. Dati corrotti tollerati (la struttura viene ricostruita, valori non validi ignorati). `Cleanup()` gira a ogni abilitazione del modulo (PLAYER_LOGIN, quando tutti gli addon hanno gia' registrato i pack): un segnalibro verso un pack non piu' registrato (addon disattivato) viene quindi perso.

## Suggerimento per zona (`autoSuggest`, default true)
A `PLAYER_ENTERING_WORLD` / `ZONE_CHANGED_NEW_AREA` (e a `PLAYER_REGEN_ENABLED` se rimandato) confronta `GetRealZoneText`, `GetZoneText`, `GetInstanceInfo` (sondate con `pcall`, valori secret/non stringa ignorati) con il campo `zone` delle entry (uguaglianza normalizzata). Un solo avviso per zona per sessione, mai in combattimento, mai apre finestre: `Badb.ConfigUI:Toast` se esiste, altrimenti `Logger:Info`.

## Viewer
Finestra `BadbUIGuideViewer`, costruita al primo `Open`, trascinabile, chiusa da ESC (`UISpecialFrames`). Sinistra: ricerca, filtro segnalibri, lista a categorie comprimibili (max 400 righe). Destra: intestazione (titolo, meta, confidenza, stella segnalibro, progresso) e corpo scorrevole reso con pool di FontString/CheckButton/EditBox riusati (corpi da 200 blocchi senza garbage). Le altezze usano `GetStringHeight` con una stima di riserva.

## Confidenza dei contenuti
Ogni entry ha `confidence` A/B/C (vedi `docs/FOREVER_FACTS.md`; vale la piu' bassa tra le affermazioni contenute). Nel viewer le entry B/C mostrano "da verificare in gioco" e il test della suite richiede un blocco `warn` "Da verificare in gioco" in ogni entry bundled non A.

## Aggiungere contenuti
Nuove entry in `Data/Guides.lua` oppure `Badb.Guides:Register(pack)` da un altro file/addon (anche prima dell'init). Niente dati di gioco inventati: se non e' verificabile, non scriverlo, o marcalo B/C.

## Limiti noti
- Il viewer non e' stato provato nel client (solo mock): template `UIPanelScrollFrameTemplate`/`UICheckButtonTemplate`/`UIPanelCloseButton`, atlas `auctionhouse-icon-favorite` (con fallback testuale) e font `GameFontNormalHuge` sono quelli del client Mainline.
- Il comando `/badb role` e i template di classe citati nelle guide dipendono dagli altri moduli: la guida rimanda a `/badb help`.
- Il limite di 4000 e' in byte, non in caratteri UTF-8.
