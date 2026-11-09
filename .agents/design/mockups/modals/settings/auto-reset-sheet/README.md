# Presence Auto-Reset sheet (modal)

> **What:** Opened from Admin: a fitted page sheet with one auto-reset toggle per room (14). **Read when:** changing the auto-reset toggles or the sheet's title and height.

- Mockup: [auto-reset-sheet.html](auto-reset-sheet.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Settings/Household/AdminSettingsContent.swift`, `apple/Sources/HassUI/Features/Settings/Household/HouseholdSettingsPage.swift`, `apple/Sources/HassDesign/SheetFit.swift`
- Spec: `.agents/pages/settings/household.md`, `.agents/patterns/modal-sheet.md` · Patterns: modal-sheet, entity-tile, dynamic-grid
- States covered: default (fitted), error, offline, one-missing, medium, large, fitted, closed, ax5; light and dark in the gallery. loading in notes.
- Motion: toggle colour cross-fade (state 0.6 s); transitions: present (fitted) and dismiss.
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad (704 pt page sheet).
- Open notes: household.md does not mention this sheet's detent or its short title "Presence Auto-Reset".
- Shared helper: `pages/settings/_household-forms.js` (household-forms batch; local icons and builders, "promote to kit" in the notes).
- Rollout S (2026-10-28): the 14 room toggles are action tiles with a `power` disc (`HouseholdActionTile`), no leading glyph; the sheet is unchanged.
