# Preset di interfaccia

Scopo: interfacce complete applicabili in un click, sul modello degli UI pack curati (Skill Capped), ma con
anteprima, backup, nuovo profilo e annulla. Un preset contiene **layout Edit Mode** (posizioni e impostazioni di
barre, unit frame, cast bar, tracker) + **opzioni dei moduli** BadbUI + **frame nascosti** (micro menu, borse...).

File: `Modules/Presets.lua` (motore, pagina, comandi), `Data/Presets.lua` (54 template), `tests/presets_test.lua`.

## Catalogo
9 classi × 6 template = 54, chiavi `<classe>-<mode>-<scenario>`:

| mode | scenario | contenuto Forever |
|---|---|---|
| pve | `dungeon` | gruppo da 5 |
| pve | `raid` | varianti `10` / `20` / `40` (Barrow Deeps, Hyjal Summit, Onyxia) |
| pve | `solo` | leveling e mondo aperto |
| pvp | `bg` | Warsong 10v10, Arathi e Darkspear 15v15 |
| pvp | `av` | Alterac Valley 40v40 |
| pvp | `world` | world PvP e duelli |

Nessuna arena (Forever non ne ha). Generazione data-driven: base dello scenario → ritocchi della classe →
`byRole` (solo ruoli ammessi da `Badb.Player.CLASSES`) → variante raid (con `byRole` interno per gli healer).
Ogni template ha `rationale` e `facts` (righe di `docs/FOREVER_FACTS.md`).

Layout per archetipo (healer, tank, mischia, distanza): giocatore e bersaglio ai lati del centro, cast bar sopra
le barre, barre compatte per distanza e healer, party/raid orizzontali al centro per gli healer e a sinistra per gli
altri; in PvP focus e gruppo simmetrici alla stessa distanza dal centro; raid 40/AV compatti in alto a sinistra.

## API (`Badb.Presets`)
```lua
P:Register(def) -> key | nil, err          -- valida; stessa key = sostituisce
P:Validate(def) -> ok, errori
P:List({ class=, mode=, scenario=, role=, tag=, search=, custom=, strictClass= }) -> { def... }
P:Get(key) -> def | nil
P:Resolve(key, { role=, variant= }) -> { modules, frames, editMode, role, roleSource, variant, title }
P:Diff(key, opts) -> { {module, path, from, to}... }   -- module "frames" / "EditMode" per frame e layout
P:FormatDiff(diff) -> testo
P:Apply(key, { role=, variant=, mode="new-profile"|"merge"|"replace", profileName=, only={...} }) -> profilo, report | nil, err
P:Apply(spec)                               -- specifica del wizard (Build): nuovo profilo
P:Undo() -> true | nil, err ;  P:CanUndo()
P:RecommendTemplate() -> key, { role, variant }, motivo
P:SaveCustom(nome, desc, ruolo) -> key ;  P:ExportCustom(nome, desc, ruolo) -> stringa
P:Export(key) -> stringa ;  P:ImportCustom(stringa) -> key, scartati ;  P:DeleteCustom(key)
P.Layout.Build(spec) / Install / Uninstall / Merge / Validate
```
Restano invariati `RegisterContent`, `RegisterRole`, `Build`, `Describe`, `Recommend` usati dal wizard; i contenuti
del wizard ricevono ora un layout Edit Mode per ruolo.
`only` accetta nomi di modulo piu' `"frames"` e `"EditMode"`. Il ruolo, se non passato, viene da `Badb.Player`.

### Apply, passo per passo
1. rifiuta in combattimento o con l'Edit Mode aperto (nessuna modifica);
2. backup `pre-preset` con `Badb.Backups` (se presente);
3. `new-profile` copia il profilo attivo in uno nuovo; `merge` fonde nel profilo attivo; `replace` riporta ai default
   i moduli toccati prima di applicare (in entrambi i casi si salva una copia per l'annulla);
4. costruisce il layout Edit Mode, lo installa tra i layout dell'account (sostituisce quello con lo stesso nome) e lo
   salva nell'EditModeBridge del profilo come stringa portabile;
5. attiva il profilo; un errore in qualunque passo annulla tutto (profilo creato, copia, layout).

## Layout Edit Mode dichiarativo
```lua
{ base = "modern", systems = {
  { system = "ActionBar", index = "MainBar", anchor = { "BOTTOM", "BOTTOM", 0, 24 },
    settings = { IconSize = 90, NumRows = 1, Orientation = "Horizontal", HideBarArt = true } },
  { system = "UnitFrame", index = "Party", anchor = { "TOP", "CENTER", 0, -120 },
    settings = { UseRaidStylePartyFrames = true } } } }
```
I nomi si risolvono negli `Enum` del client a runtime; si parte da una copia del preset Blizzard e si modificano
solo sistemi e impostazioni esistenti. Cio' che il client non conosce viene saltato e riportato in `report.layout.skipped`.
Gli slider usano il convertitore dell'Edit Mode del client quando esiste, altrimenti `(valore - min) / passo`.

## Dati salvati
`sv.global.presetUndo` (ultimo apply: profilo, copia, layout), `sv.global.customPresets` (max 50). Stringhe di
scambio: `Badb.Serializer` tipo `"preset"`; all'import le opzioni sconosciute vengono scartate e riportate.

## Limiti noti (da verificare in gioco)
- Posizioni pensate per UI a 768 unita' di altezza: da rifinire in gioco (conf. C).
- Conversione degli slider senza convertitore del client e nomi Enum dei sistemi su Forever: conf. C.
- Sciamano e Druido DPS usano l'archetipo mischia (Potenziamento/Ferino); per Elementale/Equilibrio usare
  "merge" con `only` o spostare le barre in Edit Mode.
- L'account ha un limite di layout Edit Mode (5 di default): oltre il limite il preset applica le opzioni e
  avvisa che il layout non e' stato installato.

## Comandi
`/badb preset list [pve|pvp]` · `apply <chiave> [ruolo] [10|20|40] [merge|replace]` · `diff <chiave>` ·
`recommend` · `undo` · `save <nome>` · `export [chiave]` · `import` · `delete <chiave>`
