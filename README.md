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
| Design system | `UI/*` | `Badb.Theme` (token di colore, font, spaziature, schemi notte/crepuscolo/grafite, accento) e `Badb.UI` (finestre, bottoni, toggle, slider, dropdown, tab, liste virtualizzate). Doc: [docs/UI.md](docs/UI.md), anteprima dal vivo: `/badb gallery` |
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

## Aure curate e avvisi

| Modulo | File | Cosa fa |
|---|---|---|
| Aure curate | `Modules/Auras.lua`, `Data/Auras.lua` | Database di CC, immunita', difensivi, offensivi, root, rallentamenti e debuff per classe; riconosce anche i rank nuovi per nome localizzato; elenco personale (`/badb aura`). |
| Aure sulle nameplate | `Modules/NameplateAuras.lua` | CC grande a destra, difensivi/offensivi nemici a sinistra, i tuoi debuff sopra; nasconde le aure Blizzard. |
| Avvisi | `Modules/Alerts.lua` | "Healer in CC" (e focus) con suono, di default solo nei BG (`/badb alert`). |

Tutto passa dalle API aure (niente combat log) e tollera i secret values: dettagli in [docs/auras.md](docs/auras.md). Gli unit frame mostrano la stessa "aura grande" al centro di bersaglio, focus e gruppo.

## Suite di gestione (v0.2)

BadbUI non e' solo un insieme di moduli grafici: e' la **console unica** per gestire l'interfaccia di WoW: Forever. Ogni area ha API pubblica, test e documento dedicato.

| Area | File | Cosa fa | Doc |
|---|---|---|---|
| Giocatore | `Core/PlayerInfo.lua` | Classe, talenti (3 alberi, dual spec lv 40) e **ruolo** con fonte e confidenza; override dell'utente (`/badb role`) | [FOREVER_FACTS](docs/FOREVER_FACTS.md) |
| Preset | `Modules/Presets.lua`, `Data/Presets.lua` | 6 template per classe (PvE: dungeon, raid 10/20/40, solo; PvP: campo di battaglia, Alterac Valley, world PvP), per ruolo, con anteprima e annulla | [presets](docs/presets.md) |
| Contesti | `Modules/Contexts.lua` | Cambio profilo automatico per istanza, Alterac vs altri BG, ruolo, spec, classe, flag PvP | [contexts](docs/contexts.md) |
| Layout | `Modules/LayoutStudio.lua` | Undo/redo, nudge da tastiera, allineamento, distribuzione, gruppi | [layoutstudio](docs/layoutstudio.md) |
| Integrazioni | `Modules/Integrations.lua` | Cattura e riapplica i profili di ElvUI, Details, Plater, Bartender4, BigWigs, DBM, Clique (best-effort) | [integrations](docs/integrations.md) |
| Guide | `Modules/Guides.lua` | Libreria in-game con ricerca, segnalibri, progresso, suggerimento per zona | [guides](docs/guides.md) |
| Operativita' | `Modules/Backups.lua`, `Modules/Diagnostics.lua` | Backup con rotazione e ripristino atomico; controlli, conflitti, report senza dati personali | [ops](docs/ops.md) |
| Interfaccia | `Config/ConfigUI.lua`, `Config/Slash.lua` | Finestra con sidebar, pagine fornite dai moduli, ricerca, comandi slash estensibili | [configui](docs/configui.md) |
| Primo avvio | `Config/Wizard.lua` | Setup guidato: ruolo, PvE/PvP, regole automatiche, backup, annulla | [wizard](docs/wizard.md) |

Contratto condiviso tra i moduli (API, eventi, regole di qualita'): [docs/CONTRACT.md](docs/CONTRACT.md). Ricerca su Forever con fonti e livello di affidabilita': [docs/FOREVER_FACTS.md](docs/FOREVER_FACTS.md). Confronto con Skill Capped UI: [docs/research/skillcapped.md](docs/research/skillcapped.md).

**Principi**: nessuna API presunta (si sonda tutto, in `pcall`); ogni operazione distruttiva fa prima un backup; ogni modulo ripristina lo stato Blizzard alla disattivazione; nessun `loadstring` su input utente; ruolo incerto = si chiede conferma, non si indovina.

## Test
`lua5.1 tests/run.lua` dalla root del repo (eseguito anche dalla CI su ogni PR). Il design system ha una suite propria con un mock che registra punti, dimensioni e colori dei widget: `lua5.1 tests/ui/run.lua`. `tests/lua/wowstub.lua` simula l'API WoW necessaria: CVar, combattimento, nameplate, layout Edit Mode, secret values.

## Comandi
`/badb` config · `/badb help` elenco completo (i comandi dei moduli compaiono da soli: `preset`, `context`, `layout`, `backup`, `doctor`, `integration`, `guide`) · `/badb role <tank|healer|dps|auto>` · `/badb setup` configurazione guidata · `/badb undo` annulla ultimo preset · `/badb unlock` · `/badb profile <nome>` · `/badb export` · `/badb enable|disable <modulo>` · `/badb debug` · `/badb log` · `/badb gallery` galleria del design system · `/badb theme <schema> <accento>`

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

## Unit frame

**UnitFrames** (`Modules/UnitFrames/`, documentazione in `docs/unitframes.md`)
- Frame propri per giocatore, bersaglio, bersaglio del bersaglio, focus e gruppo (party 1-4), stile piatto del tema: fondo notturno, hairline da 1px, ombra morbida, accento oro, palette di riserva se il design system manca.
- Bottoni `SecureUnitButtonTemplate`: click = bersaglio, destro = menu, registrati in `ClickCastFrames`. Visibilita' affidata al client (`RegisterUnitWatch`, state driver per il gruppo), nessuno snippet secure.
- Vita (valore e/o percentuale), risorsa, nome, livello, colore di classe o reazione, castbar con icona (grigia se non interrompibile), aure su bersaglio/focus/gruppo con debuff prima dei buff, icona di classe, icone combattimento (anche su bersaglio/focus), capogruppo e marker, gruppo sfumato fuori portata, bordo d'accento sul membro che e' il tuo bersaglio.
- Secret values: i valori opachi vanno direttamente ai widget, testi e colori usano le API del client (`UnitHealthPercent`, `SetAlphaFromBoolean`, durate dei cast) quando ci sono, altrimenti un fallback neutro. Nessun confronto o calcolo su valori secret.
- Combattimento: creazione, dimensioni e ancoraggi solo fuori combattimento (rimandati automaticamente), aggiornamenti di vita/aure/cast sempre attivi. Frame Blizzard nascosti riparentandoli e ripristinati alla disattivazione.
- Spento di default. Anteprima con dati finti (`/badb uf preview`), posizioni con `/badb unlock`, `/badb uf reset <unita'>`. Un solo pannello di opzioni con selettore dell'unita'.

## Test
Tre runner, tutti eseguiti dalla CI su ogni PR (insieme al controllo di sintassi `luac5.1 -p`):
- `lua5.1 tests/run.lua .`: carica la TOC con API WoW simulate (`tests/wow_mock.lua`), ricarica l'addon da zero per ogni test ed esegue `tests/*_test.lua` (auto-discovery).
- `lua5.1 tests/run_stub.lua`: suite stub (CVar, nameplate, group frame, preset).
- `lua5.1 tests/ui/run.lua .`: design system.

Casi limite coperti: secret values, combattimento, API mancanti o che lanciano errori, dati salvati corrotti, import malevoli, cambio profilo, dual spec, disattivazione con ripristino completo.

## Stato
v0.2: core, moduli grafici e suite di gestione completi. **Tutto verificato solo con API WoW simulate: nessuna prova nel client Forever.** Le assunzioni sul client (API dei talenti, ID di Alterac, adapter degli addon terzi) sono elencate in [FOREVER_FACTS](docs/FOREVER_FACTS.md) con il loro livello di confidenza; il primo passo in gioco e' `/badb doctor run`.
