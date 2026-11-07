# Solo Trip (page)

> **What:** Settings > Vacation > Solo Trip: toggle, travelers, return time and status. **Read when:** you change the Solo Trip page.

- Mockup: [solo-trip.html](solo-trip.html) · shipped · reviewed 2026-10-23 (author self-check; skill reviewers replace it)
- Source: `apple/Sources/HassUI/Features/Vacation/SoloTripScreen.swift`, `VacationComponents.swift`, `HassCore/HouseholdAway/SoloTripController.swift`, `SoloTripStatus.swift`
- Spec: `.agents/pages/vacation/spec.md`, `ios.md` · Patterns: schedule-date-fields, info-box, entity-tile
- States covered: off, traveler chosen, scheduled, running (two viewers), return error, needs attention, degraded, error, setup required, Vacation engaged, offline, reconnecting, AX5.
- Motion: toggle and traveler tile tint cross-fade; sheet and push transitions.
- Devices: iPhone, Duo folded, Duo unfolded portrait and landscape, iPad portrait and landscape.
- Open note: Locked tiles are drawn glyph-muted only (GlassTile disabled behaviour); rim dimming unchecked.
- Rollout M (2026-10-28): the toggle is an action tile with a `power` disc (off opens the editor, on asks "End Solo Trip?"; new `end-alert` state) and the travelers are single-choice selection tiles (check disc / empty ring); ids `soloTrip.toggle`, `soloTrip.traveler.<name>` kept.
