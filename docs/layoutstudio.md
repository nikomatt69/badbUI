# LayoutStudio

Editor di layout sopra il FrameManager: undo/redo, nudge da tastiera, allineamento/distribuzione,
gruppi bloccabili, snap intelligente. Modulo `LayoutStudio` (`Badb.LayoutStudio`), pagina "Layout" nella ConfigUI.

## API (tutte ritornano `ok, err`, non lanciano errori)
- `Undo()`, `Redo()`, `CanUndo()`, `CanRedo()`, `ClearHistory()`
- `GetHistory(limit?)` -> lista (dal piu' recente) di `{text, label, keys, time, undone}`, `canUndo`, `canRedo`.
  Testo leggibile, es. `Giocatore: x 128 -> 136`; passi multi-frame: `Allinea a sinistra (5 frame)`.
- `Begin(label)` / `End()`: transazione esplicita (un solo passo di undo, annidabile).
- `Nudge(key, dx, dy)` (key nil = primo selezionato), `NudgeSelection(dx, dy)`
- `Align(keys, mode)` con mode `left|right|top|bottom|hcenter|vcenter`; `Distribute(keys, axis)` con `h|v` (servono 3 frame).
  Ritornano `true, nil, info` con `info = {unknown, editMode, noGeometry}` (frame saltati).
- `Select(key, add?)` (`add` = shift-click, alterna), `SelectAll(category?)`, `SelectGroup(name)`, `GetSelection()`
- `Group(name, keys)`, `Ungroup(name)`, `SetGroupLock(name, bool)`, `GetGroups()`
- `SetGridSize(n)` (1-128, in `DB.sv.global.gridSize`), `ToggleSnap()`
- `Calc.*`: funzioni pure (`Align`, `Distribute`, `SnapDelta`, `Step`, `Unique`, `Diff`) su rect `{key,x,y,w,h}`,
  centro relativo al centro di UIParent (come il FrameManager, point CENTER). Posizioni arrotondate al pixel intero.

Evento emesso: `BADB_LAYOUT_HISTORY(canUndo, canRedo)`.
Comando: `/badb layout undo | redo | grid <n> | nudge <chiave> <dx> <dy> | snap`.

## Storia
Ascolta `BADB_FRAME_CHANGED` e registra prima/dopo di `DB.profile.frames[key]` (max 100 passi, opzione `maxHistory`).
Sono agganciati anche i due casi in cui il FrameManager cambia stato senza evento: fine drag di un mover e `FM:Restore`.
Coalescenza: nella stessa transazione, e fra eventi automatici sullo stesso frame entro `coalesceWindow` (0.4 s), un solo passo.
Undo/Redo riapplicano lo stato con `FM:SetOption` / `FM:Restore` con un flag di replay: non creano storia (gli altri moduli
vedono comunque `BADB_FRAME_CHANGED`). Una nuova azione svuota il redo. La storia si svuota a cambio profilo,
disattivazione, preset applicato/annullato e backup ripristinato.

## Tastiera e mover
Un overlay locale cattura la tastiera solo se `FM.unlocked` e c'e' una selezione (si spegne in combattimento).
Frecce = 1 px, SHIFT = griglia, CTRL = 10 px; Ctrl+Z / Ctrl+Y = undo/redo. Ogni altro tasto propaga al gioco.
Clic su un mover seleziona, shift-clic aggiunge (hook difensivo su `FM.movers`).
Snap intelligente (opzione `snap`, soglia `snapThreshold` px): a fine drag il frame si aggancia a bordi/centri degli altri
frame visibili. Lo snap alla griglia del core resta sempre attivo.

## Edit Mode, combattimento, gruppi
- Frame Edit Mode: mai mossi, ritorno `false, "gestito dall'Edit Mode"`; se il layout attivo e' un preset Blizzard
  (non modificabile ne' esportabile) il messaggio aggiunge di duplicarlo in Edit Mode e usare EditModeBridge.
  In `Align`/`Distribute` questi frame vengono saltati.
- Combattimento: Nudge/Align/Distribute/Undo/Redo su frame protetti ritornano `false, "in combattimento"` (nulla cambia);
  i frame non protetti funzionano.
- Gruppi (salvati nel profilo, `groups`): un gruppo bloccato rifiuta (`false, "gruppo bloccato: nome"`) tutte le operazioni
  di questo modulo che toccano i suoi frame, undo/redo compresi. **Limite**: non impedisce al FrameManager, al drag di un mover
  o ad altri moduli di scrivere sul frame.

## Limiti noti
- Lo stato "prima" viene da una copia locale: scritture esterne senza evento (non via FM) possono renderla imprecisa.
- Geometria in unita' del frame (`GetCenter`, `GetWidth`), come il drag del FrameManager: con scale lontane da 1 gli allineamenti sono approssimati.
- Un frame senza geometria valida (non ancora layoutato) viene saltato; senza posizione salvata il nudge ritorna `false`.
