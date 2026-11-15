# Acceptance record

Automated checks establish compilation, API compatibility, ownership safety and
offline rendering. Live acceptance remains separate for every skin.

| Area | Required acceptance |
| --- | --- |
| Appearance | Frames, backgrounds, fonts, gauges, buttons, tabs, lists and all control states |
| Missing windows | New client and addon windows retain working controls and selected styling |
| Switching | Login and in-world selection, repeated changes, failed-load recovery, persistence and zoning |
| Layout | Move, resize, lock, fade, minimize, close, reopen and restore |
| Inventory | Bags, stacks, equipment, cursor, bank, merchants, loot and confirmations |
| Spells | Book, gems, memorization, casting, cooldowns and buff menus |
| Social | Chat links, filters/history, group, raid, guild and invitations |
| Tasks | Journal, tracker, rewards, shared roster, expeditions and adventures |
| Navigation | Map, Find, options, quantity entry, focus and physical controllers |

Features need an implemented host model and action. A skin cannot implement
missing gameplay support by drawing controls. Absent source art must remain
visible in diagnostics.

Captures and player-derived data stay outside tracked files.
See [validation](validation.md) for executed checks and measured coverage.
