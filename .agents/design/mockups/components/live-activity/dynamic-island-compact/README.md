# Dynamic Island compact and minimal (component)

> **What:** the island while another app is in front: ring and rigid-width time, or glyph and one word, plus the minimal bubble. **Read when:** you change the compact leading or trailing side, the width template, or the iOS 27 limited-width rule.

- Mockup: [dynamic-island-compact.html](dynamic-island-compact.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/FentonActivityViews/HomeActivityIslandViews.swift`, `HomeActivityIslandPreview.swift`, `ActivityRing.swift`, `SeverityCircle.swift`, `apple/Apps/Widgets/HomeLiveActivity.swift` · Spec: `.agents/platforms/apple/live-activities-per-job.md` (8, 8a), `live-activities.md` · Patterns: none
- States covered: default (device), widths, problems, minimal, two activities, limited (iOS 27), ax5 (capped)
- Motion: timers count (system)
- Devices: iPhone with a Dynamic Island only; Duo has no island
- Open notes:
  - The capsule widths are estimates from a monospaced digit width; the real island size and status bar spacing are the system's.
  - Doc vs code: spec 8 says a 26 pt ring; code and 8a say 24 pt.
- Helper: `components/live-activity/_widgets-liveactivity.js` (Live Activity, island, small family, notification and Watch stand-ins; promote to kit).
