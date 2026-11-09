# Aure curate (Auras, NameplateAuras, Alerts)

File: `Data/Auras.lua` (database), `Modules/Auras.lua` (motore e widget), `Modules/NameplateAuras.lua` (nameplate), `Modules/Alerts.lua` (avvisi), elemento "aura grande" in `Modules/UnitFrames/Elements.lua`. Test: `tests/auras_test.lua`, casi "aura grande" in `tests/unitframes_test.lua`.

Copre la priorita' 2 e parte della 3 di [docs/research/skillcapped.md](research/skillcapped.md): aure importanti su nameplate e frame, avviso "healer in CC". Selezione degli incantesimi, codice e testi sono nostri.

## Cosa vede il giocatore
| Dove | Cosa | Default |
|---|---|---|
| Nameplate nemica, a destra | Il controllo piu' importante: stun/fear/poly/sleep > silence/disarm > root. Icona grande (30 px) con countdown. | modulo spento, acceso dai preset |
| Nameplate nemica, a sinistra | Immunita' > difensivi > offensivi > "sta bevendo" del nemico (max 3). | |
| Nameplate nemica, sopra | I **tuoi** debuff: curati per la tua classe (DoT, rallentamenti, maledizioni) o tutti. Ordine stabile di applicazione. | curati |
| Nameplate alleata | Solo il CC (o CC e difensivi, o niente). In istanza Blizzard rende le nameplate alleate "forbidden": non si toccano. | solo CC |
| Unit frame bersaglio, focus, gruppo | "Aura grande" al centro: immunita' > CC > silence > difensivi > offensivi. | attiva sulle tre unita' |
| Centro schermo | "Healer in CC": icona, nome, tipo di controllo; suono; fino a 3 righe e "+N". | spento; acceso dal preset PvP, solo nei BG |

Le aure Blizzard sulle nameplate vengono nascoste (alpha 0) mentre il modulo e' attivo e tornano quando lo si spegne o si toglie l'opzione.

## Database
- 9 categorie con priorita' e colore: `immunity` 100, `cc` 90, `silence` 80, `defensive` 70, `offensive` 60, `root` 50, `utility` 40, `snare` 30, `drink` 20. La priorita' si cambia per profilo (`Auras.priorities`).
- Famiglie di incantesimi con tutti i rank Classic Era, piu' debuff curati per ognuna delle 9 classi di Forever.
- **Rank nuovi di Forever**: gli ID potrebbero cambiare (FOREVER_FACTS, conf. C). Per questo il motore risolve il nome localizzato del primo ID di ogni famiglia (`C_Spell.GetSpellName`/`GetSpellInfo`) e riconosce l'aura anche per nome. Disattivabile.
- Elenco personale per profilo: `/badb aura add <id|nome> <categoria|hide>`, `remove`, `list`, `check`, `reset`, oppure dalla pagina Moduli > Aure curate. `hide` nasconde un'aura ovunque (anche dai "miei debuff").

## Regole Forever
- **Niente combat log**: tutto viene da `C_UnitAuras.GetAuraDataByIndex` (con ripiego su `UnitAura`). Nessun tracking di cooldown nemici o DR.
- **Secret values**: spellId, nome, durata, stack e "chi l'ha messa" possono essere opachi in combattimento.
  - Si classifica solo con valori leggibili; un valore secret non viene mai confrontato ne' usato come chiave.
  - Con ID e nome secret: se il client dichiara in `AuraUtil.AuraFilters` filtri come `CrowdControl`/`BigDefensive`/`ExternalDefensive`, si rilegge con quei filtri (dedup per `auraInstanceID`). Un filtro **non dichiarato non viene mai provato**: un filtro sconosciuto potrebbe essere ignorato e restituire tutte le aure.
  - I tuoi debuff secret restano visibili se `isFromPlayerOrPlayerPet` (o `sourceUnit`) e' leggibile: meglio un debuff in piu' che perdere i propri DoT.
  - Countdown con durate secret: `C_UnitAuras.GetAuraDuration` + `Cooldown:SetCooldownFromDurationObject`, poi `SetCooldownFromExpirationTime`; se mancano entrambi lo swipe si nasconde. Stack secret tramite `GetAuraApplicationDisplayCount` se esiste.
  - Nomi secret negli avvisi: vanno al FontString cosi' come sono, mai concatenati; l'elenco manuale degli healer si confronta solo con nomi leggibili.
- Ostilita' secret (`UnitCanAttack`): la nameplate viene trattata da nemica (solo piu' informazioni).
- `UNIT_AURA` in BG arriva a raffica: i ridisegni delle nameplate sono coalescati, uno per unita' per frame.
- Nameplate riciclate, rimosse, barra personale, nameplate forbidden, unita' senza nameplate e API che lanciano errori sono gestite (vedi test).

## Avvisi "healer in CC"
- Healer = ruolo di gruppo `HEALER` oppure nomi aggiunti con `/badb alert healer add <nome>` (su Forever i ruoli di gruppo possono mancare). Il giocatore e' escluso.
- Opzionale: focus amico (`focusCC`), senza doppioni se e' gia' sorvegliato.
- Contesto: solo BG (default), qualunque istanza, sempre se in gruppo, sempre.
- Suono `RAID_WARNING` al nuovo CC, limitato a uno ogni 1,5 s. `/badb alert test` mostra un avviso di prova per posizionarlo; `/badb alert status` dice quante unita' sono sorvegliate.

## API (`BadbUI.Auras`)
```lua
Auras:Classify(auraData)            -> categoria|nil, via ("id"|"name"|"custom"|"secret"|"hidden")
Auras:Collect(unit, { helpful, harmful, categories = set, own = "off"|"curated"|"all", class, max })
                                    -> { {aura, category, priority, own, filter, index, via}, ... } ordinate
Auras:GetHighest(unit, {"cc", ...}) -> voce|nil
Auras:IsCrowdControlled(unit, includeSilence) -> voce|nil
Auras:CreateIcon(parent, size) / :SetIcon(icon, voce, unit, { size, numbers, border }) / :ClearIcon(icon)
Auras:SetCustom(idOrName, categoria|"hide"|nil) -> ok, err;  :ListCustom();  :ResetCustom();  :Status()
```
Evento `BADB_AURAS_CHANGED` quando l'indice o l'elenco personale cambiano.

## Preset
Dungeon, Raid e Leveling accendono le aure sulle nameplate (debuff curati, meno icone in raid). PvP le accende con CC piu' grande, rallentamenti e utilita' visibili, e accende l'avviso "healer in CC" nei BG. Il ruolo Healer riduce i propri debuff sopra le nameplate.

## Da verificare in gioco
- ID degli incantesimi di Forever (il riconoscimento per nome copre i rank nuovi con lo stesso nome).
- Quali campi delle aure sono secret su Forever e se `AuraUtil.AuraFilters` espone filtri CC/difensivi: `/badb aura status` lo mostra.
- Nomi dei frame aure Blizzard sulle nameplate (`BuffFrame`/`AurasFrame`/`DebuffFrame`, sondati).
