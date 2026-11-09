# Stile ElvUI (`ElvLook`, tema `elvui`)

Confronto con i default di [tukui-org/ElvUI](https://github.com/tukui-org/ElvUI) (`ElvUI/Game/Shared/Defaults/Profile.lua`
e `Layout/Layout.lua`, letti il 2026-11-09). Nessun codice o asset di ElvUI e' copiato: sono solo valori numerici.

| Elemento | ElvUI | BadbUI |
|---|---|---|
| Colore fondo / fondo trasparente | `backdropcolor` 0.10, `backdropfadecolor` 0.06 @ 0.8 | `panel` 0.10, `bg` 0.06; sfondo chat alpha 0.8 |
| Bordo | nero, 1 px | nero pieno, 1 px (`Theme:Skin`, pixel perfect) |
| Colore valore / accento | (0.09, 0.52, 0.82) | identico (`Theme.ACCENTS.elvui`) |
| Font | PT Sans Narrow 12 (datatext: ombra) | Arial Narrow del client (PT Sans Narrow non e' incluso), ombra |
| Pannelli datatext | 2 pannelli 412x22 sotto la chat, 3 caselle ciascuno | identici, agli angoli in basso; larghezza/altezza regolabili |
| Contenuto di default | sx: versione, durabilita', posta; dx: sistema, ora, oro | sx: zona, durabilita', borse; dx: fps+ms, ora, oro |
| Pannelli chat | 412x180 | sfondo che segue il frame chat (la posizione resta all'Edit Mode) |
| Unit frame | player/target 270x54, ToT 130x36, focus 190x36, party 184x54 | identici |
| Posizioni | player (-342,139), target (342,139), ToT (342,101), focus (342,60) dal centro-basso; party (4,269) | party identico; player/target/ToT/focus a **±395** invece di ±342: le barre Blizzard sono larghe ~500 px (ElvUI usa pulsanti da 32 px) e a ±342 il frame del giocatore le sovrapporrebbe. Si regola con `/badb unlock` |
| Minimappa | quadrata, 175 px, bordo | quadrata con bordo; la dimensione resta all'Edit Mode |
| Barre azioni | fondo con bordo, senza arte Blizzard | fondo piatto + decorazioni Blizzard nascoste |

## Differenze volute (limiti di Forever)
* **Colore della vita**: ElvUI di default colora la barra per valore (`colorhealthbyvalue`). Su Forever la vita e' un *secret value*
  in combattimento e non si puo' confrontare: BadbUI usa il colore di classe/reazione, con fallback neutro.
* **Chat e minimappa**: sono frame gestiti dall'Edit Mode; BadbUI non li sposta (`SetPoint`) per non causare taint.
  Si ridisegnano attorno e si posizionano con l'Edit Mode.
* **Niente combat log**: nessun datatext che lo richieda (DPS, ecc.).

## Manipolare tutto (`/badb unlock`)
Ogni elemento (unit frame, pannelli datatext, pulse cooldown...) mostra una maniglia azzurra con il suo nome:

| Azione | Effetto |
|---|---|
| Trascina | sposta, con griglia (`gridSize`, default 8) |
| Frecce (mouse sopra la maniglia) | 1 px; con Maiusc 10 px |
| Maiusc + rotella | scala 0.5 - 2 (passi da 0.05) |
| Tasto destro | ripristina posizione e scala |

Le frecce funzionano solo con il mouse sopra la maniglia; gli altri tasti restano al gioco. In combattimento lo sblocco
si chiude. Dimensioni, caselle dei datatext, trasparenze: `/badb` > Stile ElvUI e Unit frame. `/badb elv` riapplica tutto.

## Non verificato
Mai provato nel client Forever: i test usano frame simulati. Da controllare in gioco: nomi dei pezzi Blizzard nascosti
(minimappa, barra principale, pulsanti chat), sovrapposizioni con le barre azioni del tuo layout, leggibilita' del font.
