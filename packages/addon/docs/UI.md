# Design system BadbUI

`UI/*.lua`: un unico stile per pannello di configurazione, wizard, frame e allerte.
Look "notte strumentale", ispirato a Polestar (fondi blu notte, hairline da 1px, scala di testo bianca, un solo accento caldo). Codice, palette e valori sono originali BadbUI: nessun asset o file di Polestar.

Anteprima dal vivo in gioco: **`/badb gallery`**. Cambio tema veloce: **`/badb theme dusk jade`**.

Caricamento: i file `UI/` sono nella TOC subito dopo `Core/` e prima di `Modules/`, quindi ogni modulo e ogni pagina di config possono usarli senza guardie. `UI/Gallery.lua` viene caricato per ultimo perché registra i comandi nel router slash.

## Principi

1. **Token, non valori.** Nessun modulo scrive colori o dimensioni a mano: legge `Theme.colors`, `Theme.sizes`, `Theme.styles`.
2. **Tutto segue il tema.** `Theme:Paint` ricolora le region quando l'utente cambia schema o accento; `Theme.colors.*` sono aggiornate *in place* (chi tiene un riferimento vede i nuovi valori).
3. **1px vero.** Le hairline di `Theme:Skin` misurano un pixel fisico a qualsiasi scala UI e risoluzione (`Theme:Pixel`), ricalcolate su `UI_SCALE_CHANGED` e `DISPLAY_SIZE_CHANGED`.
4. **Leggibilità garantita.** I test verificano il contrasto WCAG di ogni schema: testo primario ≥ 7:1, secondario ≥ 4.5:1, accenti ≥ 4.5:1.
5. **Nessun taint.** Niente template Blizzard (`UIDropDownMenu`, `UIPanelButtonTemplate`...), niente frame secure: i widget sono frame semplici, utilizzabili anche in combattimento.
6. **Input non fidati.** SavedVariables corrotte (tipi sbagliati, NaN, colori fuori range, posizioni senza punto) vengono ignorate e ripulite, mai propagate.

## `Badb.Theme` (anche `BadbUI.Theme`)

### Colori: `Theme.colors.<chiave> = { r, g, b, a }` (anche `.r .g .b .a`)

| Gruppo | Chiavi |
|---|---|
| Fondi | `bg` finestra, `panel` (= `surface`) pannelli, `panelAlt` controlli e card, `sidebar`, `header` cielo dell'header, `footer` |
| Velature di ink | `border`, `divider`, `hover`, `selected`, `track`, `control` |
| Testo | `text` (100%), `textDim` (secondario), `textMuted` (terziario) |
| Accento | `accent`, `accentDim` (35%), `accentSoft` (14%), `onAccent` (testo su accento), `focus` |
| Stato | `success`, `warning`, `danger`, `info` |
| Gioco | `cc` controllo di folla, `combat`, `alert` |
| Altro | `shadow` |

### Font, texture, misure

```lua
Theme.fonts       -- path: normal, body, bold, header, title, mono, number
Theme.fontObjects -- nomi FontObject globali: title (18), heading (14), body (12), small (10), mono, number
Theme.textures    -- white, statusbar, glow
Theme.spacing     -- xs 4, sm 8, md 12, lg 16, xl 24
Theme.sizes       -- row 32, button 26, header 48, sidebar 180, footer 30, tab 28, border 1
Theme.styles      -- priorityAura, alert, combatIndicator, statusbar (vedi sotto)
```

`Theme.styles` sono token per elementi di gioco, così aure, allerte e indicatori dei vari moduli hanno la stessa misura e lo stesso linguaggio:

| Stile | Campi |
|---|---|
| `priorityAura` | `size` 36, `borderSize` 2, `borderColor` "cc", `glow`, `countFont`, `countSize` |
| `alert` | `font` "title", `size` 24, `color` "alert", `bg`, `bgAlpha`, `duration` 2.5, `fadeOut`, `offsetY` |
| `combatIndicator` | `size` 14, `color` "combat", `pulse` |
| `statusbar` | `texture`, `border`, `bg`, `height` |

### Funzioni

| Firma | Note |
|---|---|
| `Theme:Get(key) -> r, g, b, a` | accetta `"accent"` o `"colors.accent"`; chiave ignota → `text` |
| `Theme:GetColor(key) -> table` | la tabella viva |
| `Theme:Hex(key) -> "|cffrrggbb"` · `Theme:Wrap(text, key)` | testo colorato inline |
| `Theme:Paint(region, key [, alphaMul])` | Texture, FontString, EditBox, StatusBar; segue il tema. `Paint(region, nil)` smette |
| `Theme:OnChange(owner, fn [, skipNow])` · `Theme:OffChange(owner)` | fn(Theme) ora e a ogni cambio; anche messaggio `BADB_THEME_CHANGED` sul bus |
| `Theme:Skin(frame, opts)` | fondo + hairline 1px. `opts = { bg = "panel" \| false, border = "border" \| false, alpha, inset, shadow }`; riapplicabile senza duplicare texture |
| `Theme:SetBorder(frame, key [, mul])` | cambia la hairline di uno skin (focus, errore) |
| `Theme:Gradient(texture, topKey, bottomKey [, topMul, bottomMul])` | gradiente verticale che segue il tema |
| `Theme:SetScheme("night" \| "dusk" \| "graphite") -> bool` | |
| `Theme:SetAccent("gold" \| "badb" \| "jade" \| "violet" \| "ember" \| "frost")` o `Theme:SetAccent(r, g, b)` | |
| `Theme:SetOpacity(0.3..1)` · `Theme:Reset()` · `Theme:ListSchemes()` | |
| `Theme:Pixel([frame]) -> number` | un pixel fisico in unità UI |
| `Theme:CreateButton(parent, text, w, h, onClick, variant)` | alias di `UI:Button` |

Le preferenze stanno in `BadbUIDB.global.theme` (valgono per tutti i profili) e vengono lette a `PLAYER_LOGIN`; prima del login il tema ha già i valori di default, quindi è usabile da subito.

## `Badb.UI`

Convenzioni comuni:
- Le factory si chiamano con i due punti (`UI:Button(...)`); per robustezza accettano anche `UI.Button(...)`.
- Ogni controllo ha `:Refresh()` (rilegge `get()`) e `:SetEnabled(bool)` (alpha 0.4 e input bloccato: `set` non viene mai chiamato da un controllo disabilitato).
- I controlli non sanno dove vive il valore: ricevono `get`/`set`. Le righe di impostazione hanno etichetta a sinistra, controllo a destra, `opts.desc` come tooltip, larghezza `opts.width` (default 320; con `UI:Stack` si allargano al contenitore).

### Primitive e contenitori

| Firma | Ritorna / note |
|---|---|
| `UI:Label(parent, text, fontKey, colorKey)` | FontString; `fontKey` = title, heading, body, small, mono, number |
| `UI:Fill(parent, colorKey, layer, sublevel, alphaMul)` | Texture piena che segue il tema |
| `UI:Panel(parent, colorKey, opts)` | frame con fondo e hairline |
| `UI:Card(parent, title, opts)` | pannello rialzato, `.title`, `.subtitle` (`opts.subtitle`), `.content` |
| `UI:Separator(parent, vertical, colorKey)` | linea di 1px |
| `UI:SectionHeader(parent, text)` | titolo di sezione + filo a tutta larghezza |
| `UI:Chip(parent, text, kind)` | `kind` = neutral, accent, success, warning, danger, info; `:SetChip(text, kind)` |
| `UI:ProgressBar(parent, w, h, colorKey)` | `:SetProgress(0..1)` (valori fuori range bloccati), `:SetColorKey(k)` |
| `UI:Tooltip(owner, title, lines)` · `UI:HideTooltip()` | righe: stringa, `{ left=, right= }`, `{ testo, colorKey }` |
| `UI.AttachTooltip(frame, title, lines)` | tooltip statico su un frame |
| `UI.AddHover(frame [, key])` | velatura al passaggio del mouse |

### Controlli

| Firma | Note |
|---|---|
| `UI:Button(parent, text, w, h, onClick, variant)` | `variant` = primary, secondary (default), ghost, danger. `:SetVariant`, `:SetLabel`, `:SetTooltip(title, lines)` |
| `UI:ConfirmButton(parent, text, confirmText, w, h, onConfirm)` | agisce solo al secondo click entro 3 s |
| `UI:IconButton(parent, texture, size, tooltip, onClick)` | `:SetActive(bool)` colora d'accento, `:SetIcon(tex)` |
| `UI:CloseButton(parent, onClick)` | X disegnata, rossa al passaggio |
| `UI:Toggle(parent, label, get, set, opts)` | interruttore a pillola; `opts.onChange(v)` |
| `UI:Checkbox(parent, label, get, set, opts)` | |
| `UI:Slider(parent, label, min, max, step, get, set, opts)` | `opts.format` (stringa o funzione), `opts.percent`, `opts.live = false` scrive solo al rilascio; rotella del mouse; valore non numerico → `min` |
| `UI:Dropdown(parent, label, items, get, set, opts)` | `items` = `{ { value, text, desc, disabled } }`, stringhe, o funzione rivalutata a ogni apertura. `label = nil` per il solo bottone. `opts.maxRows` (10), `opts.placeholder`, `opts.onChange`, `opts.menuWidth`. Un solo menu aperto alla volta, chiuso al click esterno o alla chiusura della finestra; `:SetItems(items)` |
| `UI:EditBox(parent, w, h, opts)` | `opts.multiline`, `placeholder`, `onEnter(text)`, `onChange(text)`, `numeric`, `maxLetters`, `mono`, `get`. Metodi `:GetText` `:SetText` `:SetFocus` `:HighlightText` `:SetError(bool)`. In multiline Invio va a capo, Ctrl+Invio conferma |
| `UI:InputRow(parent, label, get, set, opts)` | etichetta + EditBox, salva con Invio |

### Layout

| Firma | Note |
|---|---|
| `UI:Window(name, w, h, title, opts)` | `.header .title .subtitle .body .footer .sidebar .close`. `opts`: `subtitle`, `sidebar` (true o larghezza), `footer`, `resizable` (+ `minW minH maxW maxH`), `strata`, `noClose`, `remember = false`, `onClose`. Trascinabile dall'header, ESC chiude (serve `name`), posizione e dimensione ricordate in `BadbUIDB.global.windows[name]`. `:Toggle()`, `:SetTitle(t, sub)`, `:ResetPosition()`, hook opzionale `window.OnOpen` |
| `UI:Tabs(parent, tabs, onSelect)` | `tabs = { { id, text, badge } }`; `:Select(id)`, `:GetSelected()`, `:SetTabs(tabs)`; `onSelect(id, byUser)` |
| `UI:NavList(parent, items, onSelect)` | menu laterale; item `{ id, text, icon, badge, header = true }`; `:Select(id)`, `:SetBadge(id, text)`, `:SetItems(items)` |
| `UI:ScrollFrame(parent)` | `scroll, content`; scrollbar sottile, rotella, `scroll:ScrollToTop()` |
| `UI:ScrollList(parent, rowHeight, createRow, updateRow)` | lista virtualizzata: crea solo le righe visibili. `:SetData(list)`, `:ScrollToIndex(i)`, `:Refresh()` |
| `UI:Stack(parent, { gap, padding })` | impilatore: `:Add(widget [, h, indent])`, `:Space(px)`, `:Height()`, `:Refresh()` (errori isolati) |

## Esempio: una pagina di opzioni

```lua
local Theme, UI = BadbUI.Theme, BadbUI.UI
local w = UI:Window("MioAddonFinestra", 640, 480, "Mio modulo", { subtitle = "Impostazioni", footer = true })
local scroll, content = UI:ScrollFrame(w.body)
scroll:SetPoint("TOPLEFT", 0, -4); scroll:SetPoint("BOTTOMRIGHT", -14, 4)

local st = UI:Stack(content)
st:Add(UI:SectionHeader(content, "Generale"))
st:Add(UI:Toggle(content, "Attivo", function() return M:Get("enabled") end, function(v) M:Set("enabled", v) end))
st:Add(UI:Slider(content, "Scala", 0.5, 2, 0.05, function() return M:Get("scale") end, function(v) M:Set("scale", v) end, { percent = true }))
st:Add(UI:Dropdown(content, "Ancoraggio", { { value = "TOP", text = "Alto" }, { value = "BOTTOM", text = "Basso" } },
    function() return M:Get("anchor") end, function(v) M:Set("anchor", v) end))
local save = UI:Button(w.footer, "Salva", 100, 22, function() w:Hide() end, "primary")
save:SetPoint("RIGHT", -8, 0)
w:Show()
```

Per un frame di gioco che deve solo prendere lo stile:

```lua
Theme:Skin(myFrame, { bg = "bg", border = "border" })
Theme:Paint(myFrame.name, "text")
local st = Theme.styles.priorityAura
aura:SetSize(st.size, st.size); Theme:SetBorder(aura, st.borderColor)
BadbUI.Events:On(M, "BADB_THEME_CHANGED", function() M:RefreshColors() end) -- solo per colori letti a mano
```

## Test

`lua5.1 tests/ui/run.lua` (anche in CI). Il mock `tests/ui/wow_mock.lua` registra stato reale dei widget (punti, dimensioni, colori, script, timer) e carica dalla TOC `Core/`, `Locales/`, `UI/` e il router slash. Coprono: contratto dei token, persistenza e SavedVariables corrotte, contrasto WCAG, pixel perfect con cambio di scala/risoluzione, ogni controllo abilitato e disabilitato, valori limite (slider con valore non numerico, dropdown vuoto o con valore fuori lista, liste da 1000 righe), posizione delle finestre, galleria completa.
