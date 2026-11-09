# Special Device Modes (page)

> **What:** Settings > Household > Special Device Modes: the High AQI Mode toggle. **Read when:** changing the page or the High AQI Mode copy.

- Mockup: [household-special-device-modes.html](household-special-device-modes.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Settings/Household/HouseholdSettingsPage.swift`, `apple/Sources/HassCore/Config/HouseholdSettingsConfig.swift`
- Spec: `.agents/pages/settings/household.md` · Patterns: settings-section, entity-tile, dynamic-grid
- States covered: default (off), aqi-on, error, offline, reconnecting, long-text (xxxLarge), ax5. loading, refreshing, empty in notes.
- Motion: toggle colour cross-fade (state 0.6 s), optimistic 2 s revert; push from Settings.
- Devices: all six windows; one centred 840 pt column.
- Open notes: Same docs-versus-code gap as Admin (Account sheet vs Settings tab path).
- Shared helper: `pages/settings/_household-forms.js` (household-forms batch; local icons and builders, "promote to kit" in the notes).
- Rollout S (2026-10-28): High AQI Mode is an action tile with a `power` disc; its question ("Turn On/Off High AQI Mode? This changes every air purifier in the house.") is the disc's confirmation: a body tap and a disc tap ask the same, and nothing is sent before Turn On / Turn Off. Identifiers `household.tile.<entity>.confirm` / `.cancel`.
