# Skill Capped UI: cosa fa e come BadbUI lo supera

Ricerca del 2026-11-09. Descriviamo solo le **funzionalità** osservabili da pagine pubbliche: niente codice, asset, testi o marchi di Skill Capped finiscono in BadbUI.

Fonti: [pagina CurseForge](https://www.curseforge.com/wow/addons/skill-capped-ui) (v2.3.3i, 26/09/2026, ~1,6 M download, licenza All Rights Reserved), [guida Midnight](https://www.skill-capped.com/wowarticles/general/pvp-addons-ui-guide/), [guida TBC Classic](https://www.skill-capped.com/wowarticles/tbc/general/pvp-addons-ui-guide/), [guida MoP Classic](https://www.skill-capped.com/wowarticles/mop/general/pvp-addons-ui-guide/). Vincoli Forever: [FOREVER_FACTS.md](../FOREVER_FACTS.md).

## 1. Cos'è davvero

Skill Capped UI **non è una UI**: è un **installer di profili**. Non disegna frame propri; scrive profili già pronti dentro 10-11 addon di terzi, imposta qualche CVar e applica un layout Edit Mode. Il valore sta nella curatela (scelte PvP fatte da giocatori esperti) e nel "un click invece di ore".

| Aspetto | Comportamento |
|---|---|
| Installazione | Finestra in gioco: scegli quali profili installare, poi "installa". Ogni addon selezionato riceve il proprio profilo. Ogni addon è deselezionabile. |
| Accesso | Base gratis; profili premium sbloccati con un codice legato al BattleTag e all'abbonamento. Supporto via video e Discord. |
| Versioni | Retail (Midnight 12.x), MoP Classic, TBC Classic, Classic, Titan Reforged. Pacchetto diverso per versione. |
| Per classe/spec | Dichiara impostazioni "rifinite per ogni classe e spec" (filtri aure, WeakAuras per spec nel premium). |
| Aggiornamenti | Tramite l'app CurseForge; nessun meccanismo in gioco di diff o migrazione. |

### Addon configurati (Retail/Midnight)
| Area | Addon | Funzione curata |
|---|---|---|
| Nameplate | BetterBlizzPlates | DoT/slow sopra la nameplate nemica, CC a destra, bordo bianco sul bersaglio, icona bersaglio sulle amiche, combo point sotto il bersaglio, numeri 1-3 per le macro arena |
| Unit frame | BetterBlizzFrames | Meno ingombro, icona classe al posto del ritratto, indicatore di combattimento (quando il Rogue può Sap, quando l'healer può bere), Loss of Control |
| Arena frame | sArena Reloaded | DR a sinistra della vita, margine cast bar, icone dispel/racial riposizionate |
| CC e cooldown | MiniCC (sostituisce BigDebuffs+OmniBar+WeakAuras) | Aure chiare, tracking cooldown nemici, avviso cooldown offensivi nemici, avviso "healer in CC" |
| Raid frame | FrameSort | Te stesso in fondo, così party1/party2 combaciano con le macro |
| Colori | FrameColor, HealthBarColor | Colori dei frame e della vita |
| BG | BattleGroundEnemies, Win Conditions, Capping | Frame nemici nel BG, condizioni di vittoria, timer obiettivi |
| Meter | Details! | Danni/cure |
| Premium | ArcUI, Talent Loadout Ex | Addon esclusivo; cambio rapido build PvP |

Classic/TBC/MoP usano invece Gladdy o sArena (DR, trinket, cast bar nemiche, totem), BigDebuffs, BuffOverlay (difensivi sui raid frame), OmniCD (cooldown alleati), OmniBar (cooldown nemici divisi in barre: interrupt, CC, difensivi), WeakAuras (buff mancanti, procs, healer che beve), Bartender4 (almeno 5 barre, micromenu nascosto).

### CVar e layout
Spell queue = latenza + 100, pet nei raid frame, errori script nascosti, testo di combattimento sul ritratto spento, texture proiettate ridotte, grafica meno caotica, distanza camera massima e camera fissa, bersaglio del bersaglio, bersaglio "sticky", testo missioni istantaneo, autoloot. Opzionali: icona élite sul player, font, suono all'ingresso in coda. Layout Edit Mode: elementi chiave al centro; raid frame e focus alla stessa distanza dal centro degli arena frame.

## 2. Limiti di Skill Capped (dove vinciamo)

1. **Dipendenza da 10+ addon terzi.** Ogni aggiornamento di un addon può rompere il profilo; l'utente installa e mantiene tutto.
2. **Installazione a senso unico.** Sovrascrive i profili degli addon; nessun diff, nessuna anteprima, nessun annulla, nessun backup.
3. **Nessuna gestione dopo l'installazione.** Niente cambio automatico per contesto (BG vs dungeon vs raid), niente profili per spec gestiti centralmente.
4. **Impostazioni frammentate.** Per cambiare qualcosa apri `/bbp`, `/bbf`, `/sarena`... ognuno col suo stile.
5. **Niente condivisione unificata.** Non esiste una stringa unica "tutta la mia UI".
6. **Sapere chiuso.** Il perché delle scelte è nei video premium, non nell'addon.
7. **Pensato per l'arena.** Su Forever le arene non esistono.

## 3. Vincoli Forever che cambiano la mappa

- **Niente arene né PvP classificato al lancio** (FOREVER_FACTS, conf. A). Tutto il blocco "arena frame / numeri arena 1-3 / DR arena" non ha bersaglio: il PvP di Forever è **BG 10v10 e 15v15, Alterac 40v40, World PvP/duelli**.
- **Niente combat log per gli addon**: impossibile il tracking dei cooldown nemici stile OmniBar/MiniCC basato sugli eventi di cast. Le DR non si calcolano dal log.
- **Secret values** su vita, minaccia e durate in combattimento: niente colori o soglie calcolate su questi valori; lasciare disegnare il client (countdown nativo, barre native).
- **Snippet secure non funzionano**: niente frame unità secure custom stile Gladdy; si ristilizzano i frame Blizzard.
- **Edit Mode integrato** + **cooldown manager e damage meter integrati** (conf. B): quello che Skill Capped ottiene con addon esterni, su Forever va costruito sopra le funzioni native.

## 4. Mappa funzionalità → BadbUI

Legenda stato: ✅ già su `main` · 🟡 parziale · ⬜ da fare · ⛔ impossibile su Forever (alternativa indicata).

| Funzione Skill Capped | BadbUI oggi | Come la facciamo meglio |
|---|---|---|
| Installer "un click" | ✅ Wizard (`/badb setup`) + Presets | Anteprima diff prima di applicare, preset = nuovo profilo (annullabile con `/badb undo`), backup automatico `pre-preset`. Mostrare "cosa cambia" per modulo. |
| Profili per classe/spec | ✅ profilo per spec (DB) + PlayerInfo | Ruolo rilevato con confidenza; il wizard chiede conferma se `roleConfidence ~= "high"`. Preset per i 9 ruoli/alberi Forever, non per spec retail. |
| Cambio per contenuto | ✅ Contexts | Regole automatiche: BG → profilo PvP, dungeon/raid 10/20/40 → profilo PvE, solo → leveling. Skill Capped non lo ha. |
| Layout Edit Mode | ✅ EditModeBridge + LayoutStudio | Layout Blizzard dentro il profilo, undo/redo, allineamento e distribuzione. Preset "centrati" equivalenti (player/target vicini al centro, party allineati al focus). |
| Profili addon terzi | 🟡 Integrations (riferimento al profilo, ElvUI con export) | Hub opzionale, non obbligatorio: BadbUI funziona da solo. Integrare i più diffusi su Forever (Details!, Plater, Bartender4, BigWigs/DBM) quando le API sono verificate. |
| Nameplate: aure importanti sopra, CC a destra, bordo bersaglio | ✅ NameplateAuras + Nameplates (vedi docs/auras.md) | Aggiungere aure **dalle API aure** (non dal combat log): whitelist per classe dei debuff propri, CC più grande e separato. Indicatore "bersaglio del mio party" sulle nameplate amiche. Combo point sotto il bersaglio nemico. |
| Numeri arena 1-3 | ⛔ niente arene | Marcatori sulle nameplate per i **bersagli dei raid marker** e per "nemico che bersaglia me" in BG (se `UnitIsUnit(unit.."target","player")` non è secret). |
| Unit frame puliti, icona classe, colori | ⬜ thread unit frames in corso | Ristile dei frame Blizzard: icona classe al posto del ritratto, colore classe, testo vita nativo, Loss of Control nativo abilitato e stilizzato. |
| Indicatore "in combattimento" (Sap / healer che beve) | ⬜ | `UnitAffectingCombat` su bersaglio/focus come icona sul frame; "healer che beve" dalle aure (buff Drink) se leggibili. |
| Arena frame (DR, trinket, cast bar) | ⛔ niente arene | Per i BG: frame focus/bersaglio potenziati e cast bar nemica grande; DR **non calcolabili** senza combat log, mostrare solo il CC attivo dalle aure. |
| Cooldown nemici (OmniBar/MiniCC) | ⛔ niente combat log | Non promettere tracking nemico. Al suo posto: cooldown **propri** curati (Cooldowns ✅ + cooldown manager nativo), avvisi CC sul party dalle aure. |
| Cooldown alleati (OmniCD) | ⛔ / 🟡 | Solo ciò che il client espone; difensivi attivi sui raid frame dalle aure (stile BuffOverlay) in GroupFrames. |
| CC e aure grandi su frame (BigDebuffs) | ✅ aura grande sugli unit frame (bersaglio, focus, gruppo); 🟡 raid frame | Nei group frame e unit frame: priorità aure (CC > difensivi > altro), icona grande sopra il ritratto/al centro del raid frame. |
| Avviso "healer in CC" | ✅ Alerts | Dalle aure dell'healer del gruppo (ruolo dal ruolo di gruppo); avviso centrale con suono, spento di default fuori dai BG. |
| FrameSort (me in fondo) | 🟡 GroupFrames | Ordinamento solo se consentito senza codice secure: altrimenti usare le opzioni native di ordinamento dell'Edit Mode e documentarlo. |
| Barre (Bartender4, 5 barre, micromenu nascosto) | ✅ ActionBars | Barre native via Edit Mode, stile, keybind abbreviati, dissolvenza; preset "PvP" con micromenu e borse nascosti (Hider ✅). |
| CVar curati | ✅ Core/CVars | Pagina "Gioco" con spell queue automatica (latenza + 100, ricalcolata), sticky target, camera, texture proiettate. Ogni CVar con valore originale ripristinabile: Skill Capped non li ripristina. |
| Damage meter | integrato su Forever | Nessun modulo: puntare al meter nativo o all'adapter Details!. |
| BG: nemici, timer obiettivi | ⬜ | Fase successiva: timer obiettivi solo se il client li espone (widget mappa); i frame nemici BG richiedono dati non disponibili senza secure, quindi da sondare in gioco. |
| Talenti rapidi | ⬜ | Dual spec al lv 40: pulsante di cambio talenti nel pannello e cambio profilo associato (Contexts lo fa già). |
| Guida/sapere | ✅ Guides | Il perché di ogni preset spiegato in gioco, gratis, con link ai video da copiare. |
| Supporto | ✅ Diagnostics | Report copiabile senza dati personali, controllo conflitti con altre UI. |
| Condivisione | ✅ Serializer | Una sola stringa `BADB1:` con layout Edit Mode + opzioni + riferimenti agli addon terzi. |

## 5. Priorità consigliate

1. **Preset PvP Forever** (BG 10-15, Alterac 40, World PvP) come preset ufficiali nel wizard, con layout centrato e CVar curati.
2. **Aure curate su nameplate e frame** (whitelist per classe, CC grande, difensivi sui raid frame): è la parte più visibile di Skill Capped ed è fattibile senza combat log.
3. **Avvisi** (healer in CC, buff mancanti, pet non evocato) come piccolo modulo "Alerts" basato su aure e stato unità.
4. **Diff/anteprima prima di ogni preset** e backup automatico: è la differenza "enterprise" più chiara.
5. Integrazioni terze solo dopo verifica in gioco delle API.

## 6. Cosa non fare
- Non promettere tracking dei cooldown nemici, DR o frame arena: su Forever non sono possibili o non servono.
- Non dipendere da addon terzi per le funzioni base.
- Non usare nomi, icone, testi o filtri di Skill Capped o degli addon citati.
