# Languages and offline help

BadbUI's built-in interface, guides, option descriptions and diagnostic messages support English and Italian. The macro catalog and macro bodies stay in English. User-created profile names, Lua code and server-authored guild content keep their original language.

## Choose a language

Open **Appearance > Language** (Italian: **Aspetto > Lingua**) or use:

- `/badb language enUS`: English, including on an Italian client.
- `/badb language itIT`: Italian.
- `/badb language auto`: Italian on an Italian client; English on every other client.
- `/badb language`: show the saved preference and active language.

Use `/reload` after changing the preference. Descriptors and built-in content are translated when their files load, so the active language stays consistent until reload. The preference is stored in `BadbUIDB.global.language`, independently of profiles. No game locale, spell name or stored identifier is changed.

English and Italian are the available translations; other game locales use the English interface. Localized game clients have not all been verified. English macro spell names may need individual overrides on non-English game clients.

## Help

Open **Help / Aiuto** in the sidebar, the Home quick action, or `/badb help`. Chat command help remains available as well.

The offline manual includes:

- First setup and language selection.
- Profiles, presets, backups and import/export.
- Frame movement, Edit Mode and appearance.
- Class/spec macro browsing, activation, placement, removal and limitations.
- Context rules, integrations and scripts.
- Guild snapshots and the companion synchronization cycle.
- Chatbot setup, providers, quest context and the local runtime cycle.
- Guides, troubleshooting, recovery and client compatibility.
- An explanation of every installed module and a live slash-command reference.

Choose a topic, show all topics, or search across the manual. `/badb help macros` opens a topic directly. Stable topic IDs are `start`, `language`, `profiles`, `layout`, `macros`, `contexts`, `scripts`, `guild`, `chatbot`, `guides`, `troubleshooting`, `limits`, `modules`, `commands`, and `all`.

Settings and guide buttons lead to the corresponding page. Help remains usable when the Guides or Diagnostics modules are disabled. Help content is local; guild synchronization and external links have their own connectivity requirements.

## Translation maintenance

`Core/Localization.lua` loads directly after `Core/Init.lua`, followed by both locale dictionaries, before other core files and modules. `Badb.L[key]` looks up the active dictionary and falls back to the original key. Missing entries are not cached, so later registrations work.

Existing Italian source phrases are stable keys in `Locales/enUS.lua`. New English manual text has Italian overrides in `Locales/itIT.lua`. Add UI strings through `Badb.L` and register translations with `Badb.Localization:RegisterLocale`. Preserve formatting placeholders, newlines and WoW color escapes. Keep internal IDs, slash aliases, spell aliases and API status codes independent of language.

`Data/Help.lua` holds the manual and module explanations; `Config/Help.lua` implements topic selection, full-text search, navigation and the command reference. Add module descriptions to `HelpData.modules` when introducing modules. The help tests check coverage and navigation targets.

Validation includes language resolution and reload behavior, English/Italian addon loading, unchanged macro bodies and IDs, formatting preservation, help filtering, scroll resizing, offline availability and dynamic command discovery. These are simulated Lua-client tests; final visual and gameplay checks require the Forever client.

From `packages/addon`, run `luajit tests/run.lua . localization` and `luajit tests/run.lua . help` for the new suites. The optional second argument selects suite filenames; omit it to discover all suites. Use `luajit tests/run_stub.lua` and `luajit tests/ui/run.lua .` for the smaller engine and design-system suites.
