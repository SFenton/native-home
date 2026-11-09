# Tile rollout: Settings and more (proposal)

> **What:** owner-review proposal that rolls the action and navigation tile convention out to audit items 18 to 33 (Admin, Auto-Reset, High AQI, Guest Controls, car Doors, Chores quick links, Vacation Mode, Solo Trip, sprinkler controller card, Vacuums page and sheet). **Read when:** you build any of those tiles, or the owner has picked on sub-choices 25 and 26.

- Mockup: [tile-rollout-settings-more.html](tile-rollout-settings-more.html) · status `proposed` (awaiting the owner) · reviewed 2026-10-27
- Rules applied: owner answers A to D in [action-navigation-tiles.md](../../../action-navigation-tiles.md) (chevron on every navigation tile, confirmed discs keep their confirmation, lights and switches use the `power` disc, selection tiles use the selected face with a check or numbered disc)
- States (each draws Today above Proposed on iPhone, Duo and iPad): Admin (18 to 21), Auto-Reset sheet (22), High AQI plus both alerts (23), Guests (24), car (25), Chores and zero counts (26), Vacation Mode plus its sheet and alert (27), Solo Trip plus editor and end alert (28, 29), Sprinklers idle and watering (30), Vacuums docked, cleaning, paused (31), Vacuum Rooms (32), Selected Rooms and Full Clean (33), unavailable, AX5
- **Sub-choices for the owner:** 25 (car Doors read-only or acts; recommended: acts) and 26 (Chores open count in the subtitle or a badge beside the chevron; recommended: subtitle)
- Source: `apple/Sources/HassUI/Features/{Settings/Household,Chores,Vacation,Sprinklers,Vacuums}`, `apple/Sources/HassCore/TileActions` (PowerToggleActions, LockActions, VacuumActions)
- Related: [action-navigation-tiles](../action-navigation-tiles/action-navigation-tiles.html), [selection-tiles](../selection-tiles/selection-tiles.html), [action-tiles pattern](../../../../patterns/action-tiles.md)
- Helper: `_rollout.js` (local; loads the kit GlassTile, `Mock.sel` and the first proposal's `Mock.at.grid`, copies none). Frozen after the pick; the decision goes in `.agents/design/action-navigation-tiles.md`.
