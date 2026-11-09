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

## Nameplate, raid frame e configurazione guidata

| Modulo | File | Cosa fa |
|---|---|---|
| CVar | `Core/CVars.lua` | Salva il valore originale di ogni CVar modificato (persistente tra `/reload`), sa quale modulo lo possiede, rimanda le modifiche fuori dal combattimento, ripristina tutto quando il modulo si spegne. Al login riporta indietro i CVar di moduli spenti nel profilo attuale. |
| Nameplate | `Modules/Nameplates.lua` | Visibilita' (nemici, alleati, pet/totem, barra personale), distanza, impilamento, scala, trasparenza; stile (texture, dimensione nome, bordo sul bersaglio). Salta le nameplate forbidden e tratta `UnitIsUnit` come possibile secret value. |
| Raid e party | `Modules/GroupFrames.lua` | Opzioni Blizzard via CVar (colore classe, risorse, pet, aggro, testo vita, solo dissipabili...), larghezza/altezza scritte nel **layout Edit Mode** attivo (mai `SetSize`), stile con `hooksecurefunc` sui setup Blizzard. Se il layout attivo e' un preset Blizzard avvisa senza scrivere. |
| Preset | `Modules/Presets.lua` | Preset componibili: contenuto (Leveling, Dungeon, Raid, PvP) + ruolo (Tank, Healer, DPS) + scelte. Applicare un preset crea un **nuovo profilo** partendo da una copia dell'attuale; `/badb undo` torna indietro. `Presets:Recommend()` sceglie in base a spec, livello e gruppo. |
| Wizard | `Config/Wizard.lua` | Finestra di onboarding in 5 passi (rail a sinistra, card selezionabili, riepilogo, barra di avanzamento). Si apre al primo login; "Applica consigliato" in un click. Usa `Badb.Theme`/`Badb.UI` se presenti, con fallback sulla stessa palette. |

Nameplate e Raid e party sono spenti di default: si attivano dal wizard, da un preset o dal pannello.

Aggiungere un preset:
```lua
Badb.Presets:RegisterContent("arena", { title = "Arena", description = "...", icon = "Interface\\Icons\\...",
    modules = { Nameplates = { enabled = true, globalScale = 1.2 } } })
```
I test verificano che ogni chiave di un preset esista nei default del modulo.

## Test
`lua5.1 tests/run.lua` dalla root del repo (eseguito anche dalla CI su ogni PR). `tests/lua/wowstub.lua` simula l'API WoW necessaria: CVar, combattimento, nameplate, layout Edit Mode, secret values.

## Comandi
`/badb` config · `/badb setup` configurazione guidata · `/badb undo` annulla ultimo preset · `/badb unlock` · `/badb profile <nome>` · `/badb export` · `/badb enable|disable <modulo>` · `/badb debug` · `/badb log`

## Stato
v0.1.0, scaffold: core completo, moduli EditModeBridge, Hider, Scaling. Non ancora testato in gioco.
