# Live Activity small family, Smart Stack and CarPlay (component)

> **What:** the iOS 18 supplemental small view for the Apple Watch Smart Stack and CarPlay: glyph or ring, title, one figure; no controls. **Read when:** you change the small view or need to know what the Watch and CarPlay show for a job or problem.

- Mockup: [live-activity-small.html](live-activity-small.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/FentonActivityViews/HomeActivitySmallView.swift`, `ActivityRing.swift`, `apple/Apps/Widgets/HomeLiveActivity.swift` · Spec: `.agents/platforms/apple/live-activities-per-job.md` (8), `live-activities.md` · Patterns: none
- States covered: default (Watch Smart Stack), carplay, catalog, problems, ax5
- Motion: timers count (system)
- Devices: phone-hosted; Watch (46 mm stand-in) and CarPlay (stand-in) surfaces, neither run on hardware
- Open notes:
  - Tile, header and stack indicator are stand-ins; only the small view inside is the code.
  - At AX sizes the one-line limits truncate: unverified on a Watch or in CarPlay.
- Helper: `components/live-activity/_widgets-liveactivity.js` (Live Activity, island, small family, notification and Watch stand-ins; promote to kit).
