# Macro catalog

Files: `Modules/Macros.lua` (engine, page, command), `Data/Macros.lua` (hand-written catalog),
`Data/MacroVariants.lua` (fixed-unit variants, loaded immediately after the hand-written catalog).
Tests: `tests/macros_test.lua`.

## Purpose
Ready-made macros for every class and each of its 3 talent trees, split into PvE and PvP, plus a set of
general macros that work for everyone. Each entry can be **turned on** (the macro appears in the game's `/macro`
panel) and **turned off** (it is deleted). Page: `/badb macro` or sidebar > Macros.
The native WoW Options > AddOns > BadbUI entry also has expandable child categories for the control panel,
macro catalog, profiles and help. Expand the `+`, select a section and use its Open button.

The catalog has **6,609 entries** covering all 9 classes and 27 talent trees, including 244 general macros.
Everything in the macro catalog is in English: names, descriptions, spell names, notes and controls.
Entries are available to choose from; they are not automatically created in the game's limited macro slots.

| Class | Entries across shared macros and all three trees |
|---|---:|
| Warrior | 480 |
| Paladin | 1,072 |
| Hunter | 428 |
| Rogue | 457 |
| Priest | 1,183 |
| Shaman | 644 |
| Mage | 444 |
| Warlock | 612 |
| Druid | 1,045 |

## Fixed-unit variants

Each targeted spell or combination listed in `Data/MacroVariants.lua` expands into individual entries.
The spell lists follow the existing catalog; they do not assert that every spell is currently available in the client.
Class-wide heals, dispels, blessings and buffs are shared so they remain available when browsing any tree.

| Name suffix | Unit | Use |
|---|---|---|
| `Foc` | `focus` | Enemy control, interrupts, damage, healing or friendly support |
| `MO` | `mouseover` | Strict mouseover cast |
| `Me` | `player` | Friendly spells on yourself; excluded for resurrection |
| `TT` / `FT` | `targettarget` / `focustarget` | Damage an ally's target or heal an enemy's target |
| `P1`–`P4` | `party1`–`party4` | Friendly party members, including teammates on an arena-enabled client |
| `P1T`–`P4T` | `party1target`–`party4target` | Attack or interrupt a party member's target |
| `R1`–`R40` | `raid1`–`raid40` | Raid healing, dispels, buffs and resurrection (PvE filter) |
| `B1`–`B5` | `boss1`–`boss5` | Boss damage, interrupts and control where permitted (PvE filter) |
| `B1T`–`B5T` | `boss1target`–`boss5target` | Heal or support whoever a boss is attacking (PvE filter) |
| `A1`–`A5` | `arena1`–`arena5` | Arena enemy compatibility templates (PvP filter) |

Fixed-unit spell macros do not switch your current target and have no fallback to another unit.
Friendly casts require `help,nodead`; resurrection requires `help,dead`; harmful casts require `harm,nodead`.
Interrupts include `/stopcasting`. General Target, Focus and Assist helpers intentionally change targeting or focus.
There are general helpers for all party and raid positions, pets, bosses and arena enemies, plus all eight raid
markers, ready check and 5/10/15/20-second pull timers.

Raid indices follow the current roster; they do not permanently identify a player, tank or healer.
Boss indices depend on encounter frames exposed by the client and may be absent. Control and interrupts do not
bypass immunity or range. **Forever currently has no arenas**: arena entries are explicitly labeled compatibility
templates and require an arena-enabled client. Teammates use `partyN`, not `arenaN`.

## Usage
- Page: pick Class, Specialization (All / Shared by the whole class / one tree) and Content (PvE, PvP).
  It opens on your character's class and tree. `Include shared class macros` is enabled by default for a tree;
  turn it off to see only that tree's entries. Filter by `Target / variant`, then search a name, spell or unit
  (press Enter to apply). `Page` exposes every match in batches of 100, avoiding the shared widget's 300-row limit.
  `Turn on` / `Turn off` per row, `Pick up` puts an active macro
  on your cursor so you can drop it on an action bar, `Code` (or clicking the row) shows the text and lets you save your own version.
  At the bottom: turn on / turn off all listed. Bulk actions apply to **all matches across all pages**, up to the
  available game slots. Use filters or individual toggles to keep the selection within your slot budget.
- Command: `/badb macro list [tree] [pve|pvp] [shared|withshared] [focus|mouseover|self|party|raid|boss|arena|assist]`,
  `on <name|id>`, `off <name|id>`, `show <name>`, `alloff`,
  `name <english> = <local>`.
- Examples: `/badb macro list holy pve raid withshared`, `/badb macro on Cleanse R12`,
  `/badb macro on Pummel A2`, `/badb macro show Holy Light B1T` (use the matching character class).

## Safety rules
- BadbUI manages **only** the macros it created. If you already have a macro with the same name and different text, turning on is refused.
- A catalog macro you edited by hand in `/macro` is not deleted when turned off: it stays yours (`Disable` returns `true, "kept"`).
- No creating or deleting in combat (the client forbids it): the action returns a readable error.
- Slots: character slots first, then general slots; if all are full, turning on fails with a message.
- Disabling the module does **not** delete macros already created (they are on your bars): turn them off from the catalog.
- Only macros of your own class and the general ones can be turned on; other classes are read-only.

## Client language
The catalog targets the English client: spell names are English and work as they are.
In the source text they are wrapped in braces (`/cast {Charge}`); the braces are removed when the macro is created.
On a non-English client the braces allow a per-spell replacement:
- `/badb macro name Charge = <local name>` saves a translation (applies to every macro using that spell).
- Or `Code` > edit > `Save` customizes a single macro.
- If the client can tell whether a spell is in the spellbook (`C_Spell.GetSpellInfo` / `GetSpellInfo` by name), `Code` and
  `/badb macro show` list the ones it cannot find: not learned yet, or needing a translation.
- Item names (potions, stones) have no braces: fix them by hand in the text if needed.

## API (`Badb.Macros`)
No function throws; on failure they return `false|nil, message`.
| Call | Notes |
|---|---|
| `Register(def)` | `def = { class = token or "ALL", spec = tree key or nil, mode = "pve"|"pvp"|"any", name (max 16), title, body (max 255 without braces), note? }` -> `true, id` |
| `RegisterPack(class, pack)` | `pack = { [tree or "all"] = { any = {...}, pve = {...}, pvp = {...} } }`, entry `{ name, title, text, note? }` -> number registered, list of errors |
| `List(filter?)` | `filter = { class, spec ("all" = shared only), mode, search, target, includeShared? }`; with `mode`, `any` entries stay included. Spec matching is exact unless `includeShared = true`; `target` takes the values in `TARGET_CHOICES` |
| `Get(id)`, `Find(nameOrId, class?)` | id = `<lowercase class>:<name-with-dashes>`, e.g. `mage:pom-pyro` |
| `Render(id)` | final text (customized version + translations) |
| `Enable(id)`, `Disable(id)`, `Toggle(id)`, `SetActive(id, bool)`, `IsActive(id)` | |
| `EnableAll(filter)`, `DisableAll(filter?)`, `ActiveCount()`, `Slots()`, `Pickup(id)` | |
| `SetSpellName(en, local)`, `GetSpellName(en)`, `SetBody(id, text|nil)`, `IsCustomized(id)`, `MissingSpells(id)` | |

`List` and bulk APIs are not paginated. Only UI `rows()` is paginated via `view.page` and `PAGE_SIZE = 100`.
`pageInfo()` returns current page, page count and match count; `pageChoices()` supplies the page selector.
Target classification is derived from catalog text at registration; custom text does not change catalog filters.
The bounded registration capacity is 12,000 entries, leaving room for extensions.

Internal event: `BADB_MACROS_CHANGED`.

## Saved data
`Badb.DB.sv.global.macros = { version = 1, chars = { [character] = { [id] = { name, body, perChar } } }, spellNames = { [english] = local }, bodies = { [id] = text } }`.
It lives in `global`, not in the profile: macros belong to the game, not to the BadbUI profile.

## Sources and confidence (research of 2026-11-10)
| Fact | Conf. | Source |
|---|---|---|
| Modern-client macros: 255 characters, 16-character name, bracket conditionals, `/castsequence`, `@mouseover`, `@focus`, `/focus`; no editing in combat | B | [mmonster](https://mmonster.co/wow-forever/guides/macros), [foreverdb](https://foreverdb.net/macros) |
| Slot count on Forever not confirmed (Classic Era: 120 general + 18 per character) | C | [mmonster](https://mmonster.co/wow-forever/guides/macros) |
| Names of new or renamed spells (Bane of Agony/Doom, Victory Rush, Fire Nova, Totemic Recall, Call of the Elements, Penance, Prayer of Mending, Ice Lance, Frostfire Bolt, Mutilate, Wild Growth, Berserk, Shifting Power, Lava Burst, Riptide, Holy Strike, Seal of Fury, Light's Vigil, Incinerate, Sniper Shot, Strider Kick...) and removed ones (Curse of Shadows, Fire Nova Totem, Tiger's Fury, Wyvern Sting, Lightwell, Dark Pact...) | B | [maxroll](https://maxroll.gg/wow-forever/news/wow-forever-class-deep-dives-whats-changing-for-all-nine-classes) |
| Example macros per class | B | [classicwowforever](https://classicwowforever.com/macros/warrior/), [mmonster](https://mmonster.co/wow-forever/guides/macros) |
| Reference implementation for unit suffixes, focus, party, raid, boss and arena unit handling; this does not establish Forever support | B | [Blizzard FrameXML source mirror, SecureTemplates.lua](https://github.com/tekkub/wow-ui-source/blob/live/FrameXML/SecureTemplates.lua) |

Every source states its macros were **not tested in the launch client**; neither were these.

## Known limits
- No in-game verification: `CreateMacro` / `DeleteMacro` / `GetMacroIndexByName` / `GetNumMacros` / `PickupMacro` are probed; if they are missing the catalog stays read-only.
- Entries with the "to be verified" note use new Forever talents whose name is known but not the exact behaviour (target, form, active or passive).
- Classic spells the sources do not mention (e.g. Mortal Strike, Combustion, Ice Barrier, Bestial Wrath, Adrenaline Rush, Preparation) are assumed to still exist.
- Macros with `(Rank 1)` use the Classic rank syntax.
- Talents can change stance or form requirements (e.g. Vanguard: Charge in Defensive Stance): the text is editable from `Code`.
- A talent or multi-spell combination may require multiple presses or fail if a prerequisite is missing. Fixed-unit
  variants carry a verification note; arena, boss and raid variants also explain their unit-specific limitations.
- The sidebar group name and the rest of BadbUI are still in Italian; only the macro catalog is English.

## Adding macros
Add a row in the right block of `Data/Macros.lua`, or add a spell to the appropriate `harm` / `help` list in
`Data/MacroVariants.lua`. A generated label must fit within 12 characters (suffixes use up to 4 more, including
the separator). The name must be unique within the class and differ from the general ones; spell names go in braces.
Run `luajit tests/run.lua .`, `luajit tests/run_stub.lua` and `luajit tests/ui/run.lua .` from `packages/addon`.
Macro tests check full registration, all 27 trees, name/body limits, uniqueness, complete raid/party/arena/boss
coverage, unit guards, resurrection conditions, filters, pagination, activation, slot exhaustion and user-macro safety.
