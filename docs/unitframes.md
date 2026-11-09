# Unit frame (UnitFrames)

File: `Modules/UnitFrames/Style.lua` (adattatore del tema), `Modules/UnitFrames/Elements.lua` (elementi), `Modules/UnitFrames/UnitFrames.lua` (modulo, eventi, config). Test: `tests/unitframes_test.lua`.

## Cosa fa
Sostituisce i frame Blizzard di giocatore, bersaglio, bersaglio del bersaglio, focus e gruppo con frame propri, piu' puliti e configurabili, nello stile del design system (`Badb.Theme`). Ogni unita' si attiva separatamente; disattivandola torna il frame Blizzard.

| Unita' | Chiave | Default |
|---|---|---|
| Giocatore | `player` | 220x44, castbar, valore risorsa, icone combattimento e capogruppo |
| Bersaglio | `target` | 220x44, livello, castbar, 12 aure, icona combattimento, colore per reazione |
| Bersaglio del bersaglio | `targettarget` | 120x22, solo vita in percentuale |
| Focus | `focus` | 180x34, castbar, 6 aure (solo i miei debuff), icona combattimento |
| Gruppo | `party` | 160x36 x4, verticale, sfumato fuori portata, evidenzia il bersaglio |

Il modulo e' **spento di default** (come gli altri moduli che sostituiscono frame Blizzard): lo attivano l'utente, il wizard o un preset (`modules.UnitFrames.enabled = true`, opzioni in `units.<chiave>.<campo>`).

## Regole Forever rispettate
- **Combattimento**: i bottoni secure si creano, ridimensionano e ancorano solo fuori combattimento (`Events:RunOutOfCombat("uf:apply")`). Cambi di opzione, profilo o attivazione durante il combattimento vengono applicati all'uscita. Vita, risorsa, testi, castbar, aure e icone sono figli non protetti e si aggiornano sempre.
- **Visibilita'**: `RegisterUnitWatch` per le unita', `RegisterStateDriver("visibility")` per il contenitore del gruppo (`[group:raid] hide; [group:party] show; hide`, oppure `[group] show; hide` con "mostra anche in incursione"). Nessuno snippet secure.
- **Secret values**: i valori opachi (vita, risorsa, nome, livello, icone, tempi dei cast, campi delle aure) vanno direttamente a `SetValue`/`SetText`/`SetTexture` dentro `pcall`. Le decisioni (colori, stato morto/offline, portata, combattimento) usano `Compat.SafeValue` con un fallback neutro, oppure le API del client che accettano secret: `UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)`, `Region:SetAlphaFromBoolean`, `UnitCastingDuration` + `StatusBar:SetTimerDuration`, `C_UnitAuras.GetAuraDuration` + `Cooldown:SetCooldownFromDurationObject`. Se mancano, il frame mostra meno informazioni ma non da' errori.
- **Frame Blizzard**: nascosti riparentandoli a un frame nascosto, mai `SetPoint` (sono frame Edit Mode). Ripristinati al parent originale quando l'unita' o il modulo si spengono. Se il modulo **GroupFrames** e' attivo, `CompactPartyFrame` resta suo.
- **Posizioni**: tramite FrameManager con le chiavi `UF_player`, `UF_target`, `UF_targettarget`, `UF_focus`, `UF_party`: `/badb unlock` mostra le maniglie, tasto destro ripristina il default. Finiscono nel profilo e nell'export.
- **Config robusta**: campi numerici fuori limite, stringhe, NaN, booleani sbagliati o un'unita' non-tabella (import corrotto) vengono riparati al volo verso i default.

## Tema
`Style` legge `Badb.Theme:Get(chiave)` (bg, border, shadow, accent, text, textDim, danger...), `Theme.textures.statusbar` e `Theme.fonts.normal`; se il tema manca, una chiave non esiste o `Get` lancia, usa una palette di riserva con la stessa direzione visiva. Al messaggio `BADB_THEME_CHANGED` i frame vengono ri-skinnati.

## API
- `BadbUI.UnitFrames.frames[token]` (`player`, `target`, `targettarget`, `focus`, `party1`..`party4`) e `BadbUI.UnitFrames.partyHeader`.
- `UnitFrames:Apply()`, `:SetPreview(bool)`, `:TogglePreview()`, `:ResetUnit(chiave)` -> ok, err, `:GetUnitConfig(chiave)`.
- Comandi: `/badb uf preview`, `/badb uf unlock`, `/badb uf reset <player|target|targettarget|focus|party>`.

## Limiti noti
- Non ancora verificato in gioco su Forever: i nomi delle API secret-aware sono quelli di Midnight e sono tutti sondati prima dell'uso.
- Niente frame arena, DR o trinket: Forever non ha arene e senza combat log i DR non si possono calcolare.
- Le aure non hanno ancora una priorita' "CC prima, poi difensivi": oggi l'ordine e' debuff poi buff, con filtro "solo i miei debuff".
