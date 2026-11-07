# Presence-Based Overrides sheet (modal)

> **What:** Opened from Admin: a large-detent page sheet with one tile per room (14), tinted by presence mode. **Read when:** changing the room grid, the mode tints or the sheet's detent.

- Mockup: [presence-overrides-sheet.html](presence-overrides-sheet.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Settings/Household/AdminSettingsContent.swift`, `apple/Sources/HassCore/Settings/PresenceOverrideState.swift`, `apple/Sources/HassDesign/HassModal.swift`
- Spec: `.agents/pages/settings/household.md`, `.agents/patterns/modal-sheet.md` · Patterns: modal-sheet, entity-tile, dynamic-grid
- States covered: default (large), error, offline, reconnecting, pushed (room detail), large, closed, ax5; light and dark in the gallery. loading, medium, fitted explained in notes (it is full height).
- Motion: room tile re-tint (state 0.6 s); transitions: present, push into a room, dismiss from any depth.
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (704 pt page sheet).
- Open notes: Docs say "Done"; code has the circle-X Close. Duo unfolded sheet placement vs the hinge not run on a simulator.
- Shared helper: `pages/settings/_household-forms.js` (household-forms batch; local icons and builders, "promote to kit" in the notes).
