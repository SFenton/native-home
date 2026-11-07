# Admin Controls (page)

> **What:** Settings > Household > Admin Controls (nav title "Admin"): six sections of toggle, command and opener tiles on the wallpaper. **Read when:** changing or reviewing the Admin page, its relay warning or the two sheets it opens.

- Mockup: [household-admin.html](household-admin.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Settings/Household/AdminSettingsContent.swift`, `HouseholdSettingsPage.swift`, `apple/Sources/HassCore/Config/HouseholdSettingsConfig.swift`, `apple/Sources/HassCore/Settings/HouseholdSettingsController.swift`
- Spec: `.agents/pages/settings/household.md` · Patterns: settings-section, entity-tile, dynamic-grid, modal-sheet
- States covered: default, relay-warning, all-on, all-off, error (unavailable), offline, reconnecting (arc), long-text (xxxLarge), ax5. loading, refreshing, empty are explained in notes (no UI).
- Motion: toggle colour cross-fade (state 0.6 s), optimistic 2 s revert; transitions: push from Settings, the two sheets.
- Devices: iPhone, Duo folded, Duo unfolded (both), iPad portrait and landscape; one centred 840 pt column, never split.
- Open notes: Docs say the pages push inside the Account sheet and the sheets have "Done"; code pushes on the Settings tab path and uses the circle-X Close. A tile can straddle the hinge on the unfolded Duo (the 840 pt column is centred on the window, not the hinge): check on a device.
- Shared helper: `pages/settings/_household-forms.js` (household-forms batch; local icons and builders, "promote to kit" in the notes).
- Rollout S (2026-10-28): the switches are action tiles (`HouseholdActionTile`): Front Door Auto-Lock with a `lock.fill` / `lock.open` disc, Relay Control Mode, Outdoor Faucets and Holiday Lights with a `power` disc, no leading glyph; power recovery is a momentary tile with a `bolt.fill` disc (`CommandActions.powerRecovery`, keeps the red "Didn't Respond"); the openers are unchanged. The tile is the one VoiceOver element; the disc is hidden. Identifiers `household.tile.<entity>` and `admin.powerRecovery` are kept.
