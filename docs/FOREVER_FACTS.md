# WoW: Forever — fatti verificati e ipotesi (ricerca del 2026-11-09)

Regola: **ogni scelta di design che dipende dal client cita una riga di questa pagina**. Le fonti sono in gran parte siti di guide/fan e forum:
nessuna e' documentazione Blizzard ufficiale delle API addon. Per questo ogni voce ha una confidenza e il codice deve **sondare, non presumere**.
Legenda: **A** = confermata da piu' fonti indipendenti / fonte ufficiale · **B** = una fonte o fonti discordanti · **C** = ipotesi nostra, da verificare in gioco.

## Client e TOC
| Fatto | Conf. | Fonte |
|---|---|---|
| Lancio 4 novembre 2026; client 1.60.x, interface **16001** (target 1.60.1) | A | [CurseForge ClassicUI Forever](https://www.curseforge.com/wow/addons/classicui-forever), [Warcraft Tavern](https://www.warcrafttavern.com/forever/news/classicui-forever-addon-makes-wow-forever-truly-feel-like-classic/) |
| Client moderno (architettura Mainline): gli addon Classic Era non si caricano senza build Forever; esiste il suffisso TOC `_Camelot.toc` | B | [Classic UI Forever](https://www.curseforge.com/wow/addons/classic-ui-forever) |
| Edit Mode integrato (barre, unit frame, minimappa...); layout "Classic (Preset)" sposta i frame ma mantiene l'arte moderna | A | [Classic UI Forever Reframed](https://www.curseforge.com/wow/addons/classic-ui-forever-reframed), [classicwowforever.com](https://classicwowforever.com/guides/make-wow-forever-look-like-classic/) |
| Al primo login Blizzard propone il preset **Classic / Enhanced** (anche da Opzioni > Sistema > Preset); click casting e dispel sui raid frame **integrati** | B | [guida impostazioni](https://guildjen.com/the-best-wow-forever-settings-no-addons/) |
| Integrati: damage meter e cooldown manager | B | [mmonster built-in](https://mmonster.co/wow-forever/guides/addons/built-in-features) (titolo pagina) |

## Classi, talenti, ruoli
| Fatto | Conf. | Fonte |
|---|---|---|
| **9 classi** (Guerriero, Paladino, Cacciatore, Ladro, Sacerdote, Sciamano, Mago, Stregone, Druido), nessuna nuova al lancio | A | [OpenCritic](https://opencritic.com/news/39075/world-of-warcraft-forever-officially-confirms-best-races-and-classes-on-launch), [GameSpot](https://www.gamespot.com/articles/wow-forever-may-have-just-sneakily-revealed-new-class-and-race-combos/) |
| 3 alberi di talenti per classe (27), **dual spec al livello 40**, tutte le classi rielaborate | A | [Warcraft Tavern classi](https://www.warcrafttavern.com/forever/guides/classes/), [Icy Veins](https://www.icy-veins.com/wow-forever/choosing-your-main) |
| Ruoli: Guerriero Prot=tank; Paladino Holy=healer/Prot=tank/Ret=dps; Sacerdote Disc+Holy=healer/Shadow=dps; Sciamano Resto=healer; Druido Feral=tank o dps, Resto=healer; Cacciatore/Ladro/Mago/Stregone solo dps | A (Feral, Enhancement: B) | [Warcraft Tavern](https://www.warcrafttavern.com/forever/guides/classes/), [senseos](https://senseos.gg/guides/wow-forever/classes-explained/) |
| `GetTalentTabInfo` segnato disponibile su Forever (con `talentGroup` per dual spec); **un report** dice che in una build (70532) e' sparita a favore di `C_ClassTalents`/`C_Traits` | **B discordante** | [warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/API_GetTalentTabInfo), [Runback PR #153](https://github.com/Nercari/runback/pull/153) |
→ **Conseguenza**: `Core/PlayerInfo.lua` sonda entrambe le forme di `GetTalentTabInfo`, `GetSpecialization*` e accetta provider esterni (`RegisterTreeProvider`) per `C_Traits`; senza dati cade sul ruolo primario con confidenza bassa e l'utente puo' impostare un override (`Player:SetRoleOverride`). Un wizard/UI **deve** chiedere conferma del ruolo quando `roleConfidence ~= "high"`.

## PvP (determina i template!)
| Fatto | Conf. | Fonte |
|---|---|---|
| **Nessuna arena e nessun PvP classificato al lancio** (ne' rated BG) | A | [Icy Veins PvP](https://www.icy-veins.com/wow-forever/pvp-overview), [khorium](https://khorium.pro/guide-view.html?slug=wow-forever-arena-pvp) |
| 4 campi di battaglia: **Warsong Gulch 10v10** (lv 10-60), **Arathi Basin 15v15** (20-60), **Alterac Valley 40v40** (51-60), **Darkspear Islands 15v15** (30-60, nuovo) | A | [Blizzpro](https://blizzpro.com/2026/10/08/world-of-warcraft-forever-reveals-overhauled-pvp-and-two-new-battlegrounds/), [Icy Veins](https://www.icy-veins.com/wow-forever/pvp-overview) |
| 4 ruleset di reame: Normal, PvP, Roleplay, Roleplay-PvP; il World PvP e' obbligatorio solo nelle zone contese | B | [guided.news](https://guided.news/en/news/wow-forever-pvp-transfers-arenas-matchmaking-honor/) |
→ **Conseguenza**: i template PvP sono **Campo di battaglia 10-15**, **Alterac Valley 40v40**, **World PvP / duelli**. "Arena" NON esiste: nessun template o regola deve dipenderne (il contesto `arena` resta solo per compatibilita' futura).

## PvE (determina i template!)
| Fatto | Conf. | Fonte |
|---|---|---|
| Dungeon a 5: 9 nuovi (lv 13-60) piu' tutti i dungeon vanilla originali con loot rivisto | B | [outputlag](https://outputlag.com/guides/wow-forever-dungeons-and-raids-list/) |
| Primi raid lv 60 (sblocco **9 dicembre 2026**): **Barrow Deeps (10)**, **Hyjal Summit (20)**, **Onyxia's Lair (40, attunement Drakefire Amulet)**. Molten Core/BWL/Naxx NON nel primo tier | A (ufficiale) | [Blizzard News](https://news.blizzard.com/en-us/article/24303009/world-of-warcraft-forever-raid-overviewlocations-raid-sizes-and-attunement) |
→ **Conseguenza**: i template PvE sono **Dungeon (5)**, **Raid** con varianti di dimensione **10 / 20 / 40**, **Solo / Leveling**. Il layout dei group frames del Raid dipende dalla dimensione.

## Restrizioni addon (stile Midnight)
| Fatto | Conf. | Fonte |
|---|---|---|
| Forever eredita le restrizioni di Midnight (dichiarazione di un rappresentante Blizzard su Discord, 15/9, riportata di seconda mano) | B | [masterofwarcraft](https://www.masterofwarcraft.net/2026/09/wow-forever-combat-addon-restrictions.html) |
| Combat log non leggibile dagli addon; snippet secure non funzionano; salute unita' e minaccia sono **secret values**; chat secret nelle istanze | A/B | [wowforevertierlist](https://wowforevertierlist.com/addons/restrictions), [forum Blizzard](https://eu.forums.blizzard.com/en/wow/t/threat-is-a-secrethidden-value-in-addon-api-why/633885) |
| Gli addon **possono** ristilizzare raid frame, nameplate, barre azioni, pannelli, font e arte | B | idem |
| `NAME_PLATE_UNIT_ADDED` puo' scattare prima che l'unita' sia popolata | B | [wowforeverguides](https://wowforeverguides.com/addons/patterns) |
| Details: build Forever ma meter real-time limitato nelle istanze; DBM/BigWigs: timer dalla timeline nativa degli incontri; **WeakAuras: stato incerto** (build non ufficiali in giro); ElvUI: build Forever secondo una fonte; Plater: nessun dato | B | [teamoverpowered](https://teamoverpowered.com/forever/guides/addons/), [wowsod](https://wowsod.pro/articles/wow-forever-addons-weakauras) |
| Addon UI diffusi che possono confliggere: **ClassicUI Forever**, **Classic UI Forever Reframed**, **Forevermore Classic UI**, **Forever Unit Frames**, **EllesmereUI**, ElvUI, Clique | B | [CurseForge](https://www.curseforge.com/wow/addons/forever-unit-frames), [mmonster UI](https://mmonster.co/wow-forever/guides/addons/ui) |

## Non verificato (da provare in gioco prima di fidarsi)
- Nomi esatti degli alberi in itIT (le liste `names` in PlayerInfo sono indizi; il fallback e' l'indice).
- Esistenza reale di `C_Traits`/`C_ClassTalents` su Forever e loro forma; `GetNumTalentGroups`.
- Come il client espone il ruleset del reame (Normal/PvP/RP): finche' non e' noto, il contesto "world pvp" si deduce da zona/flag PvP del giocatore (`UnitIsPVP("player")`), sondato in modo difensivo.
- Se `_Camelot.toc` sia necessario/utile per BadbUI.
- Le adapter delle integrazioni (nessuna API terza e' stata provata).
