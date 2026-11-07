# car (page)

> **What:** Settings > Household > car: Doors (action tile, lock disc) and four read-only state tiles under a "Charge Status" header. **Read when:** changing the car tiles or the read-only tile (GlassStateTile).

- Mockup: [household-mach-e.html](household-mach-e.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Settings/Household/HouseholdSettingsPage.swift`, `apple/Sources/HassCore/Config/HouseholdSettingsConfig.swift`
- Spec: `.agents/pages/settings/household.md`, `.agents/pages/security/ios.md` · Patterns: entity-tile, dynamic-grid
- States covered: default, error (all Unavailable), offline, reconnecting, long-text (long sensor value, xxxLarge), ax5. loading, refreshing, empty in notes.
- Motion: live value colour cross-fade (state 0.6 s); push from Settings.
- Devices: all six windows; one centred 840 pt column.
- Open notes: GlassStateTile is feature-local until HassDesign has a shared read-only tile. Charge Status value set is not documented; "Plugged In" is a stand-in.
- Shared helper: `pages/settings/_household-forms.js` (household-forms batch; local icons and builders, "promote to kit" in the notes).
- Rollout S (2026-10-28, owner pick 25 B): Doors is `MachEDoorsTile`, an action tile with the lock disc (`LockActions`, tracked; blue Settings tint) and the extra states doors-unlocking, doors-unlocked, doors-jammed. Identifier `household.tile.<lock entity>`; the disc is hidden from VoiceOver because it repeats the body.
