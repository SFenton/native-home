# Guest Controls (page)

> **What:** Settings > Household > Guest Controls: one section with a toggle per guest room (Guest Room, Studio, Media Room). **Read when:** changing the guest toggles or checking how they relate to Home's Guests Staying Over and the Admin relay warning.

- Mockup: [household-guests.html](household-guests.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Settings/Household/HouseholdSettingsPage.swift`, `apple/Sources/HassCore/Config/HouseholdSettingsConfig.swift`, `apple/Sources/HassCore/Config/HomeConfig.swift`
- Spec: `.agents/pages/settings/household.md` · Patterns: settings-section, entity-tile, dynamic-grid
- States covered: default, all-off, all-on, error, offline, reconnecting, long-text (xxxLarge), ax5. loading, refreshing, empty in notes.
- Motion: toggle colour cross-fade (state 0.6 s), optimistic 2 s revert; push from Settings.
- Devices: all six windows; one centred 840 pt column.
- Open notes: Same docs-versus-code gap as Admin (Account sheet vs Settings tab path). Up to six columns in code, the web caps at three.
- Shared helper: `pages/settings/_household-forms.js` (household-forms batch; local icons and builders, "promote to kit" in the notes).
- Rollout S (2026-10-28): the three guest toggles are action tiles drawn like the Home page's (occupancy family, `power` disc, "Guests staying" / "No guests"); explicit `turn_on` / `turn_off`; identifiers `guest.tile.<entity>`.
