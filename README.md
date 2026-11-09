# BadbUI

Addon originale per **World of Warcraft: Forever** (client 1.60.x, `## Interface: 16001`) per gestire tutta l'interfaccia da un unico punto: profili, layout Edit Mode, frame Blizzard, import/export.

## Installazione
Copia la cartella `BadbUI` in `World of Warcraft\_classic_\Interface\AddOns\` (o la cartella del client Forever), riavvia il gioco. Verifica l'interface number con `/dump select(4, GetBuildInfo())` e aggiorna la TOC se cambia dopo una patch.

## Architettura

| Livello | File | Ruolo |
|---|---|---|
| Namespace | `Core/Init.lua` | Tabella `BadbUI` pubblica, utility (merge default, path `a.b.c`) |
| Compatibilità | `Core/Compat.lua` | Unico punto che tocca API variabili: Settings API, Edit Mode, secret values |
| Log | `Core/Logger.lua` | Livelli DEBUG→ERROR, buffer consultabile con `/badb log` |
| Eventi | `Core/Events.lua` | Bus unico per eventi di gioco e messaggi `BADB_*`, listener isolati con `pcall`, coda per azioni fuori combattimento |
| Serializzazione | `Core/Serializer.lua` | Stringhe `BADB1:<base64>:<checksum>` tipizzate (profile/layout/module), parser senza `loadstring` |
| Database | `Core/Database.lua` | Profili per personaggio, profilo per spec, migrazioni di schema versionate, import/export |
| Moduli | `Core/Modules.lua` | Ciclo di vita `OnInitialize/OnEnable/OnDisable/OnProfileChanged`, dipendenze, attivazione a runtime |
| Frame | `Core/FrameManager.lua` | Registro frame: posizione, scala, alpha, visibilità, snapshot e ripristino originale, modalità sblocco con griglia |
| Config | `Config/*` | Pannello in Opzioni > AddOns generato dai descrittori dei moduli, slash `/badb` `/bui` |

### Regole specifiche di Forever
- I frame gestiti dall'**Edit Mode** non vengono mai spostati con `SetPoint`: il modulo `EditModeBridge` salva il layout Edit Mode dentro il profilo BadbUI e lo riattiva al cambio profilo. Una sola stringa di export contiene layout Blizzard + opzioni BadbUI.
- **Secret values**: usare `Compat.IsSecret` / `Compat.SafeValue` prima di confrontare valori come `UnitHealth` in combattimento.
- Nessuna lettura del combat log e nessuno snippet secure: su Forever non sono disponibili agli addon.
- Ogni modifica a frame protetti passa da `Events:RunOutOfCombat`.

### Aggiungere un modulo
```lua
local M = BadbUI.Modules:New("MioModulo", {
    title = "Mio modulo", category = "Interfaccia",
    defaults = { enabled = true, alpha = 1 },
    options = { { type = "range", path = "alpha", label = "Trasparenza", min = 0, max = 1, step = 0.05 } },
})
function M:OnEnable() ... end
function M:OnDisable() ... end -- deve ripristinare lo stato Blizzard
```
Il modulo appare automaticamente nella config, nei profili e nell'export.

## Comandi
`/badb` config · `/badb unlock` · `/badb profile <nome>` · `/badb export` · `/badb enable|disable <modulo>` · `/badb debug` · `/badb log`

## Barre azioni e cooldown

**ActionBars** (`Modules/ActionBars.lua`)
- Icone piatte con zoom, bordo 1px e sfondo slot presi dal tema (`BadbUI.Theme`, con palette di riserva se il design system manca).
- Keybind abbreviati (`SHIFT-BUTTON4` diventa `SM4`, `CTRL-NUMPAD5` diventa `CN5`), dimensione regolabile, keybind e nomi macro nascondibili, font delle cariche.
- Icona rossa fuori portata, blu senza risorsa, grigia se non utilizzabile.
- Dissolvenza al mouseover per ognuna delle 10 barre, con opzioni "visibile in combattimento", "visibile con bersaglio" e durata della transizione. Le barre restano visibili mentre trascini un'abilita'.
- Posizione, dimensione, righe e spaziatura restano all'Edit Mode (salvate nel profilo da EditModeBridge): il modulo non chiama mai `SetPoint`/`SetScale` sulle barre e tocca solo texture, testi e alpha, quindi funziona anche in combattimento senza taint.

**Cooldowns** (`Modules/Cooldowns.lua`)
- Usa il countdown nativo del client (CVar `countdownForCooldowns`, ripristinata al valore dell'utente quando il modulo si spegne) e lo stilizza: font del tema, dimensione proporzionale al pulsante.
- Niente numeri sotto la soglia del GCD, colore per tempo rimanente (in scadenza, sotto il minuto, minuti), swipe, bordo e lampo configurabili.
- Pulse al centro dello schermo quando un'abilita' lunga torna pronta; spostabile con `/badb unlock`.
- Opzione per estendere lo stile a tutti i cooldown (buff, oggetti); i frame "forbidden" (nameplate) non vengono mai toccati.
- Secret values: quando la durata e' opaca il client disegna comunque il countdown; colore, soglia e pulse si disattivano per quel cooldown senza errori.

## Test
`lua5.1 tests/run.lua .` carica la TOC con API WoW simulate (`tests/wow_mock.lua`) ed esegue `tests/*_test.lua`, con l'addon ricaricato da zero per ogni test. La CI (`.github/workflows/lua-tests.yml`) esegue controllo sintassi e test su ogni PR. I casi limite coperti includono secret values, combattimento, barre mancanti, pulsanti creati dopo il login, cambio profilo, temi malformati e ripristino completo alla disattivazione.

## Stato
v0.1.0, scaffold: core completo, moduli EditModeBridge, Hider, Scaling. Non ancora testato in gioco.
