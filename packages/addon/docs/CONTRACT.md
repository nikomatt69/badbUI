# BadbUI v0.2 — contratto condiviso (leggere PRIMA di scrivere codice)

Obiettivo prodotto: BadbUI diventa una **suite enterprise per gestire l'interfaccia di WoW: Forever**,
sul modello degli UI pack "curati" in stile Skill Capped, ma con un motore migliore:
preset per ruolo/spec, wizard di primo avvio, regole automatiche per contesto, layout studio con undo/redo,
hub di integrazione con gli altri addon, libreria di guide in-game, backup/diagnostica.

Il codice esistente (Core/*, ActionBars, Cooldowns, Hider, Scaling, EditModeBridge) e' stabile: **non va riscritto**.
Estendere solo tramite le API pubbliche sotto. Lingua: commenti e testo UI in italiano, identificatori in inglese.


## AGGIORNAMENTO (merge PR #2 su main) — leggere
`main` contiene ora implementazioni **reali e testate** da estendere, NON da riscrivere/sostituire (nessun `Modules:New` duplicato: asserisce!):
- `Modules/Presets.lua` (modulo "Presets"): preset componibili contenuto+ruolo, Apply = nuovo profilo copia dell'attuale, `/badb undo`, `Recommend()`. L'agente **presets** deve AGGIUNGERE l'API del contratto (Diff, only/modi merge|replace, custom export/import, page, validazione) sopra quella esistente, preservando comportamento e test di `tests/lua/test_presets.lua`.
- `Config/Wizard.lua`: wizard a 5 passi in stile hub (`/badb setup`). L'agente **wizard** deve estenderlo (passi opzionali Contexts/Integrations, API Start/Reset/IsCompleted, esecuzione con backup/annulla), preservando look, "Applica consigliato" e il comportamento esistente.
- `Config/Widgets.lua` ha gia' il builder `select`, `Config/Slash.lua` ha `setup` e `undo`: l'agente **shell** li mantiene (compatibili) mentre costruisce la v2.
- `Core/CVars.lua`, `Modules/Nameplates.lua`, `Modules/GroupFrames.lua` sono nuovi moduli di main: usare `Badb.CVars:Set(modulo, cvar, valore)` per ogni CVar (salva/ripristina l'originale).
- Due runner di test: `lua5.1 tests/run.lua .` (wow_mock, auto-discovery `tests/*_test.lua`) e `lua5.1 tests/run_stub.lua` (suite `tests/lua/`). **Entrambi devono restare verdi.**
- Prima di consegnare: `git fetch origin && git merge origin/main` nel tuo worktree e risolvi i conflitti sui TUOI file.

## REQUISITO CONTENUTO (RIVISTO dopo la ricerca: leggere docs/FOREVER_FACTS.md) — template per classe, su misura
**Fatti che cambiano il design**: Forever ha 9 classi con 3 alberi di talenti ciascuna (27), dual spec al lv 40; **NON ha arene ne' PvP classificato**;
PvP = 4 campi di battaglia (WSG 10v10, AB 15v15, Alterac 40v40, Darkspear Islands 15v15) + world PvP; PvE = dungeon a 5 e raid a 10 / 20 / 40 giocatori.

- `Badb.Player` (nuovo, **Core/PlayerInfo.lua, gia' su main, NON modificare**) e' l'unica fonte per classe/ruolo/talenti:
  `Player.CLASSES` (9 classi: token, `roles`, `primary`, `trees`), `Player:ListClasses(onlyPresent)`, `Player:GetSnapshot()` ->
  `{class, level, talentGroup, numTalentGroups, tree, role, roleSource, roleConfidence, altRole, roleAmbiguous}`, `Player:GetRole()`, `Player:SetRoleOverride(role, group?)`,
  evento `BADB_PLAYER_CHANGED(snapshot)`. **Vietato** usare direttamente `GetSpecialization*`, `GetTalentTabInfo`, `UnitGroupRolesAssigned` per decidere il ruolo (spec Mainline != Forever): passare da `Badb.Player`.
  Se `roleConfidence ~= "high"` le UI devono mostrare/chiedere conferma del ruolo.
- Il `def` di un preset ha i campi nuovi `class` (token: WARRIOR, PALADIN, HUNTER, ROGUE, PRIEST, SHAMAN, MAGE, WARLOCK, DRUID; `nil` = qualsiasi), `mode` (`"pve"|"pvp"`),
  `scenario` (vedi sotto), `role` (ruolo di default del template), `byRole = { [ruolo] = { modules=..., frames=... } }` (override applicati sopra il template in base al ruolo rilevato o scelto: solo i ruoli che la classe puo' avere secondo `Player.CLASSES[c].roles`),
  `variants = { ["10"]=..., ["20"]=..., ["40"]=... }` (solo scenario raid: override per dimensione), `facts` (lista di riferimenti a righe di FOREVER_FACTS usate). `Presets:Apply(key, {role=, variant=})`; default da `Player:GetRole()`. `Presets:List` filtra per `class`, `mode`, `scenario`, `role`.
- **6 template bundled per ogni classe** (54 totali), chiavi `"<classe-minuscola>-<mode>-<scenario>"`:
  PvE: `dungeon` (gruppo da 5), `raid` (varianti 10/20/40), `solo` (leveling/mondo aperto).
  PvP: `bg` (WSG/AB/Darkspear, 10-15 giocatori), `av` (Alterac Valley 40v40), `world` (world PvP e duelli).
  **Niente "arena".**
- Differenze **motivate e specifiche** (nel campo `rationale` di ogni template, in italiano, 1-2 frasi, con riferimento ai fatti): ruolo e distanza di combattimento della classe (mischia/ranged da `Player.CLASSES`), healer = group frames piu' grandi/leggibili
  e meno elementi inutili, tank = nameplate nemici e barre/cooldown difensivi in evidenza, ranged = barre piu' compatte, raid 40 = group frames compatti vs raid 10 piu' ampi, PvP = nameplate nemici ben visibili e distanza maggiore / alleati ridotti,
  solo/leveling = HUD pulito, tracker missioni visibile. Solo chiavi esistenti dei moduli (ActionBars, Cooldowns, Hider, Scaling, Nameplates, GroupFrames, EditModeBridge): generazione data-driven da profili base (mode x scenario) + override per classe/ruolo/variante, non 54 tabelle copiate.
  Ogni template deve restare ispezionabile con `Diff` e passare la validazione di Register.
- Test: per ogni classe di `Player.CLASSES` esattamente 3 pve + 3 pvp con scenari corretti, nessuna arena, chiavi uniche, tutti validi e applicabili, i PvP differiscono dai PvE, `byRole` solo per ruoli ammessi dalla classe,
  le varianti raid 10/20/40 producono group frames diversi, filtri, `Recommend()` per classe+contesto (BG/AV/world => pvp, istanza raid => raid, altrimenti dungeon/solo) usando `Badb.Player`.
- Contexts: contesti `instance = none|party|raid|pvp|scenario` (+ `arena` solo per compatibilita' futura, mai generato), `role` da `Badb.Player`, `pvpFlag` (UnitIsPVP, sondato). "Collega a regola automatica": BG/AV (`instance=pvp`) -> template PvP della classe; raid -> PvE raid; party -> dungeon.
- Wizard: usa `Badb.Player` per classe/ruolo, chiede conferma del ruolo se la confidenza non e' alta, propone PvE/PvP/entrambi e i 3 template della classe.
- Diagnostics: lista conflitti estesa con **ClassicUI, ClassicUI Forever, Classic UI Forever Reframed, Forevermore Classic UI, Forever Unit Frames, EllesmereUI, ElvUI, Bartender4, Dominos, Clique** (dati-driven) e avvisi su restrizioni note (secret values / combat log). Check "PlayerInfo": ruolo con confidenza bassa, talenti non leggibili.
- Integrations: WeakAuras `supported=false` con motivazione; Details marcato "meter limitato nelle istanze"; DBM/BigWigs "timer nativi"; Plater "non verificato"; tutti "best-effort, non verificato in gioco".
- Guides: le guide devono rispecchiare i fatti reali (preset Classic/Enhanced di Blizzard al primo login, Edit Mode Classic (Preset), click casting integrato, damage meter e cooldown manager integrati, 4 BG, raid 10/20/40) senza inventare numeri; marcare cio' che e' B/C.

## Regole di ownership (anti-conflitto)
Ogni agente lavora in un proprio worktree e modifica **solo i file che possiede** (vedi tabella).
**Vietato** modificare: `BadbUI.toc`, `tests/run.lua`, `tests/wow_mock.lua`, `Core/*`, `README.md`, file di altri agenti.
Se serve un'estensione al mock o al core: crearla nel proprio file di test (`Mock.Methods.X = ...`, funzioni locali)
oppure descriverla nel report finale (sezione "Richieste al core"). Il TOC contiene gia' le righe per tutti i file.

| Agente | File posseduti |
|---|---|
| presets | `Modules/Presets.lua`, `Data/Presets.lua`, `tests/presets_test.lua`, `docs/presets.md` |
| contexts | `Modules/Contexts.lua`, `tests/contexts_test.lua`, `docs/contexts.md` |
| layout | `Modules/LayoutStudio.lua`, `tests/layoutstudio_test.lua`, `docs/layoutstudio.md` |
| integrations | `Modules/IntegrationAdapters.lua`, `Modules/Integrations.lua`, `tests/integrations_test.lua`, `docs/integrations.md` |
| guides | `Modules/Guides.lua`, `Data/Guides.lua`, `tests/guides_test.lua`, `docs/guides.md` |
| ops | `Modules/Backups.lua`, `Modules/Diagnostics.lua`, `tests/backups_test.lua`, `tests/diagnostics_test.lua`, `docs/ops.md` |
| shell | `Config/ConfigUI.lua`, `Config/Widgets.lua`, `Config/Slash.lua`, `tests/configui_test.lua`, `tests/slash_test.lua`, `docs/configui.md` |
| wizard | `Config/Wizard.lua`, `tests/wizard_test.lua`, `docs/wizard.md` |

## Estensioni al descrittore di modulo (`Badb.Modules:New(name, info)`)
`info` puo' contenere, oltre ai campi esistenti, due campi **letti a runtime da shell** (nessun problema di ordine di caricamento):

```lua
page = {                       -- pagina nella ConfigUI v2 (sidebar)
    title = "Preset",          -- etichetta sidebar
    order = 20,                -- ordinamento (numero piu' basso = piu' in alto)
    category = "Gestione",     -- gruppo sidebar: "Gestione" | "Interfaccia" | "Strumenti" | "Contenuti"
    build = function(parent, ctx) ... return height end,  -- costruisce i widget dentro `parent` (larghezza ~560); ritorna l'altezza usata
    refresh = function() end,  -- opzionale, chiamata a ogni cambio profilo/opzione e quando la pagina si apre
},
commands = {                   -- sottocomandi di /badb, letti da Config/Slash.lua a ogni invocazione
    preset = { help = "preset <chiave> | list | undo", fn = function(args) ... end },
},
```
`ctx` passato a `build` = `{ UI = Badb.ConfigUI, W = Badb.Widgets, theme = Badb.Theme or nil }`. Una pagina deve funzionare anche se `Badb.Widgets`
ha solo i builder base (toggle, range, execute, header): se servono widget nuovi, crearli localmente nel proprio file.

`shell` implementa anche (contratto che altri possono usare, sempre con guardia `if Badb.ConfigUI and Badb.ConfigUI.X then`):
`UI:Open(pageKey?)`, `UI:TextBox(title, text, onAccept?)`, `UI:Confirm(text, onYes)`, `UI:Toast(text, level?)`, `UI:Refresh()`,
`UI:OpenPage(moduleName)`.
Nuovi builder opzionali in `Badb.Widgets.Builders`: `dropdown`, `text`, `color`, `label`, `separator`, `list` (documentati in docs/configui.md).

## API pubbliche dei moduli (chiunque puo' chiamarle con guardia di esistenza)
Tutte ritornano `ok, err` (o un valore, `nil, err` in errore) e **non lanciano mai errori** verso il chiamante.

```lua
-- Backups (ops)
Badb.Backups:Create(label, kind?)  -> id            -- snapshot completo di BadbUIDB (kind: "manual"|"auto"|"pre-import"|"pre-preset")
Badb.Backups:List()                -> { {id, label, kind, time, size}, ... }  (piu' recente prima)
Badb.Backups:Restore(id)           -> ok, err        -- crea prima un backup "pre-restore"; ricarica profilo e moduli
Badb.Backups:Delete(id), Badb.Backups:Export(id) -> stringa, Badb.Backups:Import(str, label) -> id

-- Presets (presets)
Badb.Presets:Register(def)         -- def = { key, title, description, role = "tank|healer|dps|pvp|leveling|any", tags = {...}, version = 1,
                                   --         author, modules = { [moduleName] = {opzioni...} }, frames = { [frameKey] = {...} },
                                   --         layoutString = nil | stringa Edit Mode }
Badb.Presets:List(filter?)         -> array di def (filter = { role=, tag=, search= })
Badb.Presets:Get(key)              -> def | nil
Badb.Presets:Diff(key)             -> { {module=, path=, from=, to=}, ... }   -- anteprima senza applicare
Badb.Presets:Apply(key, opts?)     -> ok, err        -- opts = { mode = "new-profile"|"merge"|"replace", profileName=, only = {moduleName,...} }
Badb.Presets:Undo()                -> ok, err        -- ripristina lo stato precedente all'ultimo Apply
Badb.Presets:ExportCustom(name, desc, role) -> stringa;  Badb.Presets:ImportCustom(str) -> key   -- preset utente condivisibili

-- Contexts (contexts)
Badb.Contexts:GetCurrent()         -> { instance = "none|party|raid|pvp|arena|scenario", role = "tank|healer|dps|none", spec = n, group = "solo|party|raid", resting = bool }
Badb.Contexts:ListRules() / :AddRule(rule) -> id / :RemoveRule(id) / :MoveRule(id, delta) / :Evaluate() -> profileName|nil
-- rule = { id, name, when = { instance=, role=, group=, spec=, class= (tutti opzionali, AND) }, profile = "nome", priority = n, enabled = bool }

-- LayoutStudio (layout)
Badb.LayoutStudio:Undo() / :Redo() / :CanUndo() / :CanRedo() / :Nudge(frameKey, dx, dy) / :Align(keys, mode) / :Distribute(keys, axis)
Badb.LayoutStudio:SetGroupLock(groupName, bool) / :Select(frameKey) / :GetHistory()

-- Integrations (integrations)
Badb.Integrations:List()           -> { {id, title, loaded = bool, supported = bool, hasProfile = bool}, ... }
Badb.Integrations:Capture(id)      -> ok, err        -- salva nel profilo BadbUI lo stato/profilo scelto dell'addon terzo
Badb.Integrations:Apply(id)        -> ok, err        -- riapplica quanto catturato (profilo ElvUI, Details, Plater, Bartender4, WeakAuras...)
Badb.Integrations:RegisterAdapter(def)  -- def = { id, title, addon = "NomeAddon", detect = fn, capture = fn -> table, apply = fn(table), reset = fn? }

-- Guides (guides)
Badb.Guides:Register(pack)         -- pack = { id, title, category, version, entries = { {id, title, tags, zone, body = {blocchi}, links = {...}} } }
Badb.Guides:Search(query, filter?) -> array di entry;  :Open(entryId);  :Bookmark(entryId, bool);  :GetProgress(entryId);  :SetProgress(entryId, n)

-- Diagnostics (ops)
Badb.Diagnostics:RunChecks()       -> { {id, level = "ok|warn|error", title, detail, fix = fn|nil}, ... }
Badb.Diagnostics:Report()          -> stringa copiabile (versione addon/client, moduli, errori recenti, conflitti)

-- Wizard (wizard)
Badb.Wizard:Start(force?) / :IsCompleted() / :Reset()
```

## Eventi interni (Events:Fire) aggiunti
`BADB_PRESET_APPLIED(key, mode)`, `BADB_PRESET_UNDONE(key)`, `BADB_CONTEXT_CHANGED(ctx)`, `BADB_RULE_MATCHED(ruleId, profile)`,
`BADB_LAYOUT_HISTORY(canUndo, canRedo)`, `BADB_BACKUP_CREATED(id)`, `BADB_BACKUP_RESTORED(id)`, `BADB_INTEGRATION_APPLIED(id)`,
`BADB_GUIDE_OPENED(entryId)`, `BADB_WIZARD_DONE()`.

## Regole di qualita' (valgono per tutti)
1. **Combat-safe**: ogni modifica a frame protetti passa da `Events:RunOutOfCombat(key, fn)`. Mai `SetPoint` su frame Edit Mode (usare EditModeBridge).
2. **Secret values**: confronti/aritmetica su valori del client solo dopo `Badb.Compat.IsSecret` / `SafeValue`.
3. **Nessun `loadstring` / `RunScript` su input utente.** Import solo via `Badb.Serializer` (kind tipizzato).
4. **Reversibilita'**: ogni modulo ripristina lo stato in `OnDisable`; ogni operazione distruttiva (apply preset, restore, import) crea prima un backup (`Badb.Backups` se esiste, altrimenti snapshot locale).
5. **Persistenza**: dati utente nel profilo (`self:Get/Set`, finisce nell'export) o in `Badb.DB.sv.global` (non legati al profilo). Mai nuove SavedVariables.
   Nuovi default modulo = solo valori semplici; versionare i dati con campo `version`.
6. **Robustezza**: input malformato (nil, tipi sbagliati, tabelle cicliche/profonde, stringhe enormi) non deve mai produrre un errore Lua non gestito. Limiti espliciti su dimensioni (liste, storia, buffer).
7. **Test obbligatori** in `tests/<nome>_test.lua` (formato: `local T = {} ; T["nome"] = function(Mock) ... end ; return T`), Lua 5.1, zero dipendenze.
   Coprire: percorso felice, input errato, combattimento attivo (`Mock.combat = true`), cambio profilo, disattivazione/ripristino, import/export round-trip dove applicabile.
   Eseguire sempre `lua5.1 tests/run.lua .` e `for f in $(git ls-files '*.lua'); do luac5.1 -p $f; done` prima di consegnare: **tutta** la suite deve essere verde.
8. Nessuna dipendenza hard da altri moduli nuovi: usare `Badb.X and Badb.X:Metodo()`; un modulo mancante degrada la funzione, non rompe l'addon.
9. Nessun `print` diretto: usare `Badb.Logger`. Nessun globale nuovo oltre a quelli dichiarati (SavedVariables incluse).
10. Documentare in `docs/<nome>.md` (breve: scopo, API, dati salvati, limiti noti, come aggiungere contenuti).

## Consegna
Commit nel proprio worktree (messaggio chiaro in italiano). Report finale (max 25 righe): file creati, API effettive (se diverse dal contratto, **dirlo**),
risultati di `lua5.1 tests/run.lua .`, "Richieste al core", limiti noti.
