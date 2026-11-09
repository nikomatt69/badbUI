# ConfigUI v2, widget e comandi slash (shell)

File: `Config/ConfigUI.lua`, `Config/Widgets.lua`, `Config/Slash.lua`. Test: `tests/configui_test.lua`, `tests/slash_test.lua`.

## Finestra
- `BadbUIConfigFrame`: trascinabile, ridimensionabile (820x460 .. 1300x950), ESC la chiude (`UISpecialFrames`), costruita alla prima `UI:Open()`.
- Stato in `Badb.DB.sv.global.ui`: `scale`, `point/relPoint/x/y`, `width/height`, `page` (ultima pagina), `expanded` (sezioni aperte in Moduli). Scala regolabile da Informazioni.
- Il pannello in Opzioni > AddOns resta registrato (`Compat.RegisterOptionsPanel`) ma e' leggero: un pulsante "Apri BadbUI".
- Sidebar a sinistra con i gruppi `Gestione`, `Interfaccia`, `Strumenti`, `Contenuti` (categorie sconosciute dopo quelle note), pagine ordinate per `order`, poi titolo. Ricerca in alto.

## Pagine
Sempre presenti: **Panoramica** (versione, profilo, moduli attivi, scorciatoie ai moduli con pagina, avvisi con azione, elenco moduli con attiva/apri, ultime azioni), **Profili** (lista con Attiva/Copia/Rinomina/Esporta/Elimina con conferma, Nuovo/Importa/Reset con conferma, profilo per specializzazione), **Moduli** (sezione collassabile per modulo con toggle e opzioni generate da `options`), **Frame** (per categoria: visibile/alpha/scala dove ammesso, Ripristina, Sblocca/Blocca), **Informazioni** (versione, scala finestra, comandi).

Pagine dei moduli: `Badb.Modules.list[nome].page` e' riletto ogni volta (a ogni `Open`/`RebuildSidebar`, nessuna cache). Un modulo con `page` appare in sidebar; il campo `page` puo' avere `title`, `order`, `category`, `build(parent, ctx)`, `refresh(ctx)`, `keywords` (stringa o lista, per la ricerca).
- `build` ritorna l'altezza usata (limitata a 40..20000). Se `page` non ha `build` la pagina mostra le `options` del modulo.
- **Modulo disattivato**: la pagina resta in sidebar in grigio; aprendola compare un avviso con il pulsante "Attiva modulo" e `build` NON viene eseguito. Alla (ri)attivazione la pagina viene costruita.
- `ctx` = `{ UI, W, theme, key, module, AddRefresh(fn), Resize(h) }`. `AddRefresh` registra una funzione chiamata a ogni refresh della pagina; `Resize(h)` cambia l'altezza dopo la build (per sezioni collassabili).
- **Errori isolati**: `build` in errore => box rosso con il messaggio nella pagina + `Logger:Error`, la shell continua. `refresh` in errore => testo rosso in alto a destra + `Logger:Error` (non ripetuto per lo stesso messaggio).
- `refresh` viene chiamato all'apertura della pagina, a ogni `UI:Refresh()`, a cambio profilo / modulo attivato o disattivato / opzione cambiata (questi ultimi coalescati su un frame).

## API (`Badb.ConfigUI`)
| Chiamata | Note |
|---|---|
| `UI:Open(pageKey?)` | chiave pagina (`profiles`, `mod:Nome`), nome modulo o titolo; senza argomento riapre l'ultima. Ritorna true/false, non lancia. |
| `UI:Close()`, `UI:Toggle()` | |
| `UI:OpenPage(moduleName)` | pagina del modulo; se non ne ha apre Moduli con la sua sezione espansa. false se il modulo non esiste. |
| `UI:RegisterPage(key, page)` | pagina non legata a un modulo (`page.build` obbligatorio). Chiavi core e prefisso `mod:` riservati. `UI:UnregisterPage(key)`. |
| `UI:Refresh()` | aggiorna sidebar e pagina corrente (no-op se la finestra non e' costruita). |
| `UI.TextBox(title, text, onAccept?)` | firma storica; funziona con `.` e `:`. Con `onAccept` il pulsante e' "Importa", altrimenti "Chiudi". Testo limitato a 500000 caratteri. |
| `UI:Confirm(text, onYes, onNo?)` | modale con coda (FIFO, max 10), ESC = No, callback isolate da pcall. |
| `UI:Toast(text, level?)` | `info|ok|warn|error`; max 3 visibili, il resto in coda, scadenza 4 s, stessi testi non si duplicano. |
| `UI:Search(query)` | logica pura: `{ {kind, key, title, detail, module}, ... }` (max 30). |
| `UI:CollectPages()`, `UI:GetSidebarModel()`, `UI:ResolveKey(x)` | logica pura (indice/ordinamento/risoluzione). |
| `UI:SetScale(s)`, `UI:ResetWindow()` | scala 0.6..1.5 a passi di 0.05. |

Ricerca: sottostringa case-insensitive (mai pattern Lua) su titoli pagina, `page.keywords`, titoli modulo e `label` dei descrittori `options`. I titoli aprono la pagina; le opzioni aprono Moduli con la sezione del modulo espansa.

## Widget (`Badb.Widgets`)
Descrittore: `{ type, path | get+set, label, hidden?, disabled?, tooltip?, ... }`; `hidden`/`disabled` = bool o funzione, `tooltip` = stringa o funzione. `W:Build(parent, module, startY, options?)` ritorna `altezza, widgets, gruppo`; `gruppo:Refresh()` rilegge i valori, rivaluta hidden/disabled e ricompone il layout. Se `module` e' nil servono `get`/`set` (o `options` esplicite). Descrittori errati, tipi sconosciuti o builder che lanciano producono una riga rossa e un `Logger:Error`, mai un errore.

| type | Campi |
|---|---|
| `header`, `toggle`, `range` (`min,max,step`), `execute` (`func`, `width`) | invariati |
| `select` / `dropdown` | `values` = array di scalari, `{value=,label=}` (anche `text=`), mappa valore->etichetta, o funzione; senza `DropdownButton` ricade su un pulsante che cicla i valori |
| `text` | `numeric`, `validate(text) -> ok[, valoreConvertito | messaggio]`, `width`, `maxLetters`; conferma con Invio/perdita focus, ESC annulla |
| `color` | get ritorna `{r,g,b,a}`/`{r=,...}`/hex; con `set(r,g,b,a)` o `path` (salva `{r,g,b,a}`); `hasAlpha` |
| `label` | `text` (stringa o funzione), `small`, `width` |
| `separator` | |
| `list` | `items` = funzione/tabella di righe `{ text, detail, onClick, actions = { {label, func(item), confirm, disabled, width} } }`, `height`, `empty`, `label`; max 300 righe, max 5 azioni per riga |

Nuovo tipo: aggiungere `W.Builders.mio = function(parent, module, opt) ... return frame, altezza[, xoff, yoff] end`. Utilita' pubbliche: `W.CreateFrame` (prova i template in ordine e ricade su un frame base), `W.CreateScrollFrame`, `W.MakeButton`, `W.Backdrop`, `W.Call`, `W.Eval`, `W.Safe`.

## Comandi slash (`Badb.Slash`)
`/badb` e `/bui`. Base (comportamento invariato): `config [pagina|modulo]`, `unlock`, `profile [nome]`, `export`, `enable`, `disable`, `setup`/`wizard`, `undo`, `debug`, `log`, `help`. In piu' i sottocomandi di `Badb.Modules.list[*].commands = { nome = { help, fn(args) } }`, riletti a ogni invocazione (anche per `help`).
- Priorita': base > `Slash:Register` > moduli in ordine di caricamento. Nomi duplicati: vince il primo, `Logger:Warn` una sola volta; i comandi base non si possono sostituire.
- Comando di un modulo disattivato: viene eseguito comunque, l'help lo segnala "(modulo disattivato)".
- Sconosciuto: "Intendevi 'X'?" (distanza di Levenshtein <= 2 per nomi di 4+ lettere, <= 1 per i piu' corti, o prefisso); senza suggerimento mostra l'help.
- `fn` che lancia: `Logger:Error`, la chat non si rompe.
- `Slash:Register(name, fn, help)` -> ok, err; `Slash:Unregister(name)`; `Slash:Dispatch(msg)` -> `true | false, "unknown", suggerimento | false, "error", messaggio`; `Slash:List()`; `Slash:Resolve()`.
- `setup`/`undo` usano `Badb.Wizard:Toggle()` / `Badb.Presets:Undo()` con guardia di esistenza.

## Limiti noti
- Nessuna verifica in gioco: i template Blizzard (`BasicFrameTemplateWithInset`, `ScrollFrameTemplate`, `WowStyle1DropdownTemplate`, `SearchBoxTemplate`, `InputScrollFrameTemplate`) sono sondati con pcall e hanno un fallback a frame base, ma l'aspetto del fallback e' minimale.
- Le pagine dei moduli sono pensate per ~540 px di larghezza; ridimensionare la finestra non le allarga.
- L'ordine di costruzione e' lazy: una pagina gia' costruita non viene ricostruita se un modulo cambia `page.build` a runtime (si ricostruisce solo al cambio di stato attivo/disattivo del modulo).
