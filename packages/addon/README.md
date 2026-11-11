# BadbUI

One modular interface suite for **World of Warcraft: Forever** (client 1.60.x, `## Interface: 16001`). English-only UI on every client.

BadbUI replaces the pile of single-purpose add-ons with one coherent panel: profiles, Edit Mode layouts, unit frames, action bars, bags, auction, combat meters, encounters, world waypoints, quests, loot scoring, macros, guides, backups and diagnostics — all styled by one design system (Polestar-inspired midnight theme, warm amber accent, 1px hairlines).

## Install

1. Quit WoW.
2. Extract the ZIP so the folder is `Interface/AddOns/BadbUI/` with `BadbUI/BadbUI.toc` inside.
3. Start WoW, enable **BadbUI**, then type `/badb`.

Your settings live in `WTF/` (SavedVariables) and survive updates. Never delete `WTF` when updating — just replace the `BadbUI` folder.

## Optional add-ons (separate downloads)

- **BadbUI_Guild** — guild calendar, roster and armory bridge. Requires BadbUI. Not needed for the interface suite.
- **Companion (desktop)** — syncs guild data and installs BadbUI updates you confirm in-game with `/badb update`.

## Highlights

- `/badb` — one panel for every module; search any setting.
- `/badb setup` — guided setup with per-class/role presets (54 templates).
- `/badb unlock` — move frames; Edit Mode layouts are captured into profiles.
- `/badb update` — check and confirm updates (installed by the companion while WoW is closed).
- In-game manual and guides work fully offline, in English.

## Support

BadbUI is free (WoW add-ons must be). Voluntary tips: see `SUPPORT.md` in the project repository.

## Notes

- Forever restricts combat add-on APIs (secret values, no combat-log parsing). BadbUI uses native client APIs and degrades gracefully where an API is unavailable.
- Coverage honesty: the in-game **Suite** page (`/badb`, Management → Addons replaced) lists exactly which installed add-ons each module fully or partly replaces.
