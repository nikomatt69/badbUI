# Setup guidato (Config/Wizard.lua)

Finestra a passi in stile hub (`BadbUIWizard`): rail a sinistra, contenuto, barra di avanzamento. Estende il wizard di PR #2
(look, "Applica consigliato", `/badb setup`) con stato persistente, passi opzionali, piano di esecuzione con backup e annulla.

## API (`Badb.Wizard`)
| Metodo | Effetto |
|---|---|
| `Start(force?)` | apre il wizard; senza `force` solo se non completato (o personaggio nuovo: modalita' breve). Ritorna `true` o `false, motivo` |
| `IsCompleted()` / `Reset()` | stato per account / riparte da zero (rimuove anche il vecchio `global.wizardDone`) |
| `GetState()` | copia: `{completed, skipped, version, completedAt, mode, active, step, stepIndex, stepCount, answers}` |
| `Next()` / `Back()` | navigazione; `Next` valida il passo (blocca con messaggio) e sull'ultimo passo esegue `Finish` |
| `Finish()` | valida tutto, esegue il piano, segna completato, `Events:Fire("BADB_WIZARD_DONE")`. `true, resoconto` / `false, errore` |
| `Skip()` | "Non mostrare piu'": `completed=true, skipped=true` |
| `Close()` | "Piu' tardi": chiude senza segnare nulla |
| `Undo()` / `CanUndo()` | "Annulla tutto" sull'ultima esecuzione |
| `BuildPlan()` / `Execute(plan)` | piano (lista di azioni) ed esecuzione con fallimenti parziali |
| `Open(mode?)`, `Toggle()`, `ApplyRecommended()` | API esistenti (usate da Slash/Presets) |

`Wizard.STEPS`: tabella data-driven `{key, title, modes, applicable(c), validate(c) -> ok, err, plan(c, names), apply(c)}`;
la UI di ogni passo e' in `Builders[key]` (ogni build e' in pcall: un passo rotto mostra un box d'errore e non blocca).

## Passi
`welcome` (client, Edit Mode, avviso preset Classic/Enhanced, avvisi di `Badb.Diagnostics`) - `role` - `template` - `content` -
`details` - `rules` - `integrations` - `summary`; in modalita' breve (personaggio nuovo) `charprofile` - `summary`.
Un passo viene **saltato** se non applicabile: `template` senza `Badb.Player`/`Presets:List/Get` con template per la classe,
`content` quando si usa un template, `rules` senza `Badb.Contexts`, `integrations` senza `Badb.Integrations` o senza addon caricati.

- **Ruolo**: classe e ruolo solo da `Badb.Player`. Se `roleConfidence ~= "high"` o `roleAmbiguous` compare il riquadro "Conferma il tuo ruolo",
  le card sono limitate a `Player.CLASSES[classe].roles` e al Finish il ruolo viene salvato con `Player:SetRoleOverride(ruolo)`.
  "Applica consigliato" non scavalca la conferma.
- **Template** (classe del giocatore): PvE / PvP / Entrambi (`Presets:List({class=, mode=})`, max 3 per modalita'; niente arena).
  Preselezione da `Presets:RecommendTemplate()`. Per un template con `variants` (raid) si sceglie la dimensione 10/20/40 (`variant`).
  "Scelta generica" ripiega sul percorso composto (ruolo + contenuto, `Presets:Build/Apply(spec)`).
- **Entrambi**: applica PvP, poi PvE (resta attivo il PvE), poi `Contexts:AddRulesForClass(class, {pvp=, raid=, party=, solo=})`
  con i nomi dei profili creati; senza quel metodo ripiega su una regola `AddRule` instance=pvp.
- **Regole**: copia del profilo scelto associata a raid / campi di battaglia (`Contexts:AddRule`, idempotente per nome).
- **Integrazioni**: `Integrations:Capture(id)` per gli addon caricati e supportati.

## Esecuzione
Ordine: backup (`Backups:Create("Prima del wizard","pre-preset")`, se c'e' un'azione distruttiva; se fallisce e' un avviso),
ruolo, template/preset, dettagli, regole, integrazioni. Ogni azione e' in pcall: un fallimento non ferma le altre; il resoconto
(`{done, errors, warnings, undo, backup}`) e' mostrato nel riepilogo finale con "Annulla tutto". L'annullamento ripercorre le azioni
al contrario (`Presets:Undo`, `RemoveRule`, profili creati) e infine ripristina il profilo di partenza.
In combattimento `Finish` non tocca nulla, mostra il motivo e riprova a fine combattimento.

## Stato (`Badb.DB.sv.global.wizard`, per account)
`{completed, skipped, version=1, step (id), answers = {...}, completedAt, chars = {[personaggio]=true}, lastProfile}`.
Letto sempre da `state()`, che normalizza in place (tipi, lunghezze, tabelle cicliche): uno stato corrotto non genera errori.
`answers` ha una whitelist di chiavi (ruolo, contenuto, toggle, template, variante, regole, integrazioni, profilo personaggio).
Un account che ha completato (senza "non mostrare piu'") ma con un personaggio non in `chars` vede il **wizard breve**:
"Usa un profilo esistente o creane uno nuovo".

## Avvio automatico
Modulo `Wizard` (`BadbUI.Modules`): a `PLAYER_ENTERING_WORLD` con `isLogin/isReload`, una sola volta per sessione, dopo 3 s
(`Compat.After`), mai in combattimento (`Events:RunOutOfCombat`). ESC e la X chiedono conferma: non mostrare piu' / piu' tardi / continua.
Disattivare il modulo chiude la finestra e ferma l'avvio automatico. Pagina "Setup guidato" nella ConfigUI; comando `wizardreset [status]`
(`/badb wizard` e `/badb setup` sono comandi base di Slash.lua).

## Limiti noti
- Il toggle per singoli frame nascosti (FrameManager) non e' esposto: il passo "Dettagli" mantiene il solo "nascondi micro menu, borse, barra esperienza".
- La classe di un template e' valida solo se `Badb.Player` la conosce; senza dati si usa il percorso generico.
- Con un template i toggle di "Dettagli" attivi si aggiungono, quelli spenti non sovrascrivono il template.
- L'annullamento di `AddRulesForClass` rimuove anche regole che la chiamata ha solo aggiornato.
