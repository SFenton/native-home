# Household toggle tile, grid and read-only tile (component)

> **What:** The tinted-glass tile every household page uses, its grid and the read-only variant. **Read when:** reusing the household tile or changing a household grid's minimum width.

- Mockup: [household-toggle-tile.html](household-toggle-tile.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Settings/Household/HouseholdSettingsPage.swift`, `apple/Sources/HassDesign/GlassTile.swift`, `apple/Sources/HassDesign/DynamicGridLayout.swift`
- Spec: `.agents/patterns/entity-tile.md`, `.agents/patterns/dynamic-grid.md` · Patterns: entity-tile, dynamic-grid
- States covered: toggle (off, on, unavailable, no subtitle), kinds (command, navigate, room), read-only, grid at 360 / 600 / 840 pt, ax5; page and sheet surfaces.
- Motion: tile colour (state 0.6 s), optimistic revert (2 s), read-only colour.
- Devices: size class via the Device control (iPhone, Duo folded, iPad).
- Open notes: GlassStateTile is feature-local; promote HF.tile and HF.stateTile to the kit.
- Shared helper: `pages/settings/_household-forms.js` (household-forms batch; local icons and builders, "promote to kit" in the notes).
- Rollout S (2026-10-28): the toggle is now the action tile `HouseholdActionTile` (text and a power disc, no leading glyph; a lock disc for Front Door Auto-Lock; guest face in the occupancy family with "Guests staying" / "No guests"); `HouseholdToggleTile` is deleted. `HF.tile` draws it; `HF.doorsTile` draws car Doors. Command and navigate kinds: power recovery gets the momentary `bolt.fill` disc, openers are unchanged.
