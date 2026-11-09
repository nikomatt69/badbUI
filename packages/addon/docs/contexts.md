# Contexts — cambio profilo automatico per contesto

Modulo `Contexts` (`Modules/Contexts.lua`, API pubblica `Badb.Contexts`). Un piccolo motore di regole sceglie il profilo
BadbUI in base al contesto di gioco: istanza, gruppo, ruolo, gruppo talenti, classe, riposo, flag PvP.

## Contesto (`Contexts:GetCurrent()`)
```lua
{ instance = "none|party|raid|pvp|scenario", group = "solo|party|raid", role = "tank|healer|dps|none",
  roleConfidence = "high|medium|low", spec = n, class = "WARRIOR", resting = bool, pvpFlag = bool }
```
* **Classe, ruolo, spec** arrivano **solo** da `Badb.Player:GetSnapshot()` (Core/PlayerInfo.lua): `class` = token,
  `role` = ruolo risolto (override utente > ruolo di gruppo > albero dominante > classe), `spec` = `talentGroup`
  (su Forever le "spec" sono i 3 alberi classici con dual spec al lv 40, quindi `spec` e' 1 o 2). Se `Badb.Player` manca:
  `role = "none"`, `spec = 0`, `class = ""`.
* `roleConfidence ~= "high"` significa che il ruolo e' una stima (es. nessun dato sui talenti => ruolo primario della classe):
  la UI mostra `ruolo=dps(low)`; le regole su `role` scattano comunque sul valore dello snapshot. Per renderlo certo
  l'utente imposta `Badb.Player:SetRoleOverride(...)`.
* **Istanza**: `IsInInstance()` (+ `C_PvP.IsBattleground()` come ripiego). `pvp` = campo di battaglia (WSG, AB, Alterac,
  Darkspear). **Su Forever non esistono arene**: `arena` non viene mai generato (un eventuale tipo `arena` del client e'
  letto come `pvp`); resta valido come valore di regola solo per compatibilita' futura e non corrisponde mai.
* **Gruppo**: `IsInRaid` / `IsInGroup` (anche `LE_PARTY_CATEGORY_INSTANCE`), ripiego su `GetNumGroupMembers` e API vecchie.
* **Flag PvP** (`pvpFlag`): `UnitIsPVP("player")`, per il world PvP. Il ruleset del reame non e' leggibile in modo verificato
  (docs/FOREVER_FACTS.md): il flag e' la deduzione difensiva.
* Ogni API assente, che lancia errori, che ritorna tipi sbagliati o secret value => valore di default, mai errore.

## Regole
Salvate in `Badb.DB.sv.global.contextRules` = `{ version = 1, seq = n, rules = { ... } }` (per account, non per profilo; massimo 40).
```lua
rule = { id, name, profile = "nome", priority = n, enabled = bool,
         when = { instance=, group=, role=, spec=, class=, resting=, pvpFlag= } }   -- condizioni presenti = AND; when vuoto = sempre
```
Vince la regola **abilitata e non rotta** con priorita' piu' alta; a parita' la prima della lista. Una regola e' **rotta**
(`broken = true` + `brokenReason`) se il profilo non esiste o i dati erano corrotti (condizione non valida): non viene mai
applicata e non crea profili. Guarisce da sola quando il profilo compare.

| API | |
|---|---|
| `ListRules()` | copie con `broken`/`brokenReason`, in ordine di lista |
| `GetRule(id)`, `AddRule(rule) -> id \| nil, err` | `id` opzionale (stringa unica); valori non validi => `nil, err` |
| `UpdateRule(id, patch) -> ok, err`, `SetEnabled(id, bool)` | patch parziale validata |
| `RemoveRule(id)`, `MoveRule(id, delta)` | `ok, err`; `delta` limitato ai bordi della lista |
| `Evaluate([ctx]) -> profilo, ruleId \| nil` | **a secco**: non cambia nulla; `ctx` opzionale per simulare |
| `Apply() -> ok, err` | valuta e applica subito (ignora debounce, isteresi, override manuale, opzione auto-switch; in combattimento viene differita) |
| `AddRulesForClass(token, {pvp=, raid=, party=, solo=})` | crea/aggiorna (mai duplica) le regole base della classe |

`AddRulesForClass`: nomi profilo **passati dal chiamante** (per esempio quelli creati da `Presets:Apply` in modalita'
`new-profile`); i tipi senza nome sono saltati. Regole create (id `cls-<classe>-<tipo>`, condizione `class` = token):
BG (`instance=pvp`, prio 20) -> profilo PvP, raid (prio 20), dungeon (`party`, prio 10), solo (`instance=none + group=solo`, prio 0).
Se esiste `Badb.Presets` (con guardia di esistenza e `pcall`) il titolo del template `<classe>-pvp-bg` / `-pve-raid` /
`-pve-dungeon` / `-pve-solo` etichetta la regola; altrimenti nome descrittivo. Alterac e BG hanno entrambi `instance=pvp`: il
client non li distingue in modo verificato, quindi c'e' una sola regola PvP.

## Motore
* Eventi: `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`, `GROUP_ROSTER_UPDATE`, `PLAYER_UPDATE_RESTING`,
  `PLAYER_FLAGS_CHANGED`, `UNIT_FACTION` (solo player) e **`BADB_PLAYER_CHANGED`** (ruolo/classe/talenti, da `Badb.Player`).
  Nessun listener nostro sul ruolo assegnato: lo segnala gia' `Badb.Player`.
* **Debounce** 0,5 s (`C_Timer.After`, a fronte iniziale): una raffica di eventi produce una sola valutazione.
* **Mai in combattimento**: la valutazione passa da `Events:RunOutOfCombat("contextEval", ...)` e riparte a `PLAYER_REGEN_ENABLED`.
* **Isteresi**: opzione `switchCooldown` (default 3 s, 0-30). Un cambio troppo vicino al precedente non viene scartato ma
  riprogrammato alla scadenza, rivalutando il contesto fresco: se nel frattempo il contesto e' tornato com'era, nessun cambio.
* **`fallbackProfile`** (default `""` = lascia l'attuale): profilo usato quando nessuna regola corrisponde (deve esistere).
* **Nessun loop**: i cambi profilo del motore sono marcati (`_applying`) e il listener di `BADB_PROFILE_CHANGED` li ignora.
  Cambi causati da altri (utente, preset, ascoltatori di `BADB_CONTEXT_CHANGED`) non rilanciano mai un cambio immediato.
* **Override manuale** (`respectManual`, default true): un cambio profilo non fatto dal motore sospende l'auto-switch finche'
  il contesto non cambia davvero (o le regole/opzioni vengono modificate). Eventi che non cambiano il contesto
  (caricamenti tra zone uguali) non riportano indietro la scelta. Con `respectManual = false` il motore riafferma il profilo della
  regola a ogni valutazione (sempre con isteresi).
* Eventi emessi: `BADB_CONTEXT_CHANGED(ctx)` (copia del contesto) quando il contesto cambia;
  `BADB_RULE_MATCHED(ruleId, profile)` quando una **regola** applica un profilo (non per il solo fallback).
* `OnDisable`: invalida timer e azioni differite (contatore di generazione) e rimuove tutti i listener.

### Interazione col profilo-per-spec del core (`DB:SetSpecProfile`)
Il core ascolta **sia** `ACTIVE_TALENT_GROUP_CHANGED` **sia** `PLAYER_SPECIALIZATION_CHANGED` e legge il gruppo talenti da
`Badb.Player:GetTalentGroup()`. Per non combattersi:
1. **Le regole hanno la precedenza**: se una regola abilitata corrisponde (in particolare una con `spec`), il suo profilo
   vince sul profilo-per-spec, anche se il core ha appena cambiato profilo (il motore lo riafferma dopo la sua valutazione).
2. Se **nessuna** regola corrisponde e il core ha un profilo per il gruppo talenti attuale, il motore **non fa nulla**
   (neanche `fallbackProfile`): decide il core.
3. Lo switch del core non e' scambiato per un override manuale: il motore ascolta gli stessi eventi di spec solo per
   riconoscerlo (cambio di profilo uguale al profilo-per-spec dopo un evento di spec).
4. Se il cambio avviene in combattimento, core e motore sono differiti e l'ordine a fine combattimento e' indifferente: lo stato
   finale e' sempre quello della regola. Per far vincere il profilo-per-spec in un contesto basta non avere regole che lo coprano.

## Opzioni (per profilo) e comandi
`autoSwitch` (toggle), `respectManual` (toggle), `switchCooldown` (range), `fallbackProfile` (ciclo nella pagina).
Le opzioni stanno nel profilo (come ogni modulo): se un profilo ha `Contexts` spento o `autoSwitch` spento, il motore
si ferma dopo esservi entrato; per questo i profili copiati ereditano le opzioni.

`/badb context status | list | eval [apply]` — `status`: stato, contesto e regola vincente; `list`: regole (con `ROTTA`);
`eval`: valutazione a secco; `eval apply`: applica subito.

## Pagina ConfigUI ("Contesti", categoria Gestione)
Riga con contesto corrente e regola vincente; form con bottoni ciclici (istanza — senza arena —, gruppo, ruolo, spec, classe
dalle 9 di Forever, riposo, flag PvP, profilo, priorita'); profilo base per il fallback; elenco regole (abilita, Su/Giu, elimina,
regole rotte in rosso). Usa solo `CreateFrame`: nessun widget esterno.

## Limiti noti
* Ruolo/talenti dipendono da `Badb.Player` (a sua volta con confidenza variabile: vedi FOREVER_FACTS.md).
* `UNIT_FACTION` / `PLAYER_FLAGS_CHANGED` per il flag PvP non sono verificati in gioco; la pagina e il debounce limitano il costo.
* BG e Alterac non si distinguono (stesso `instance=pvp`).
* Massimo 40 regole; nomi 48 caratteri, profili 64.
