# Room presence override detail (modal)

> **What:** Pushed inside the presence sheet: a room's four modes as a single-choice list (title = room name). **Read when:** changing the mode copy, selection look or the one-or-two-column rule.

- Mockup: [presence-override-detail.html](presence-override-detail.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Settings/Household/AdminSettingsContent.swift`, `apple/Sources/HassDesign/SettingsSection.swift`, `apple/Sources/HassCore/Settings/PresenceOverrideState.swift`
- Spec: `.agents/pages/settings/household.md`, `.agents/patterns/settings-section.md` · Patterns: settings-section, modal-sheet, dynamic-grid
- States covered: default (Enabled), disabled, paused, quieted, error (Unavailable), offline, wide (iPad, two columns), ax5, long-text; light and dark in the gallery. loading, medium, large, fitted in notes.
- Motion: option select (border and glyph state 0.6 s, checkmark quick 0.2 s), disabled dim (quick); transitions: push from the grid, Back and Close.
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad (two columns).
- Open notes: The web's 2x2 grid is one column on phones (departure recorded in household.md).
- Shared helper: `pages/settings/_household-forms.js` (household-forms batch; local icons and builders, "promote to kit" in the notes).
