# Dynamic Island expanded (component)

> **What:** the expanded island: glyph and mark beside the camera, title over value with up to two buttons, a bar. **Read when:** you change the expanded regions, the button set, or how a long title or time fits a camera width.

- Mockup: [dynamic-island-expanded.html](dynamic-island-expanded.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/FentonActivityViews/HomeActivityIslandViews.swift`, `HomeActivityIslandPreview.swift`, `ActivityButtons.swift`, `ActivityValueLine.swift`, `apple/Apps/Widgets/HomeLiveActivity.swift` · Spec: `.agents/platforms/apple/live-activities-per-job.md` (8a E2c), `live-activities.md` · Patterns: none
- States covered: default (device), widths (393/126, 402/104, 440/126), jobs, buttons, pending, problem, ax5 (capped)
- Motion: expand morph (system, illustrative), timers count (system)
- Devices: iPhone with a Dynamic Island only
- Open notes:
  - Doc vs code: spec 8 lists a 34 pt ring and a trailing value; E2c and the code put a 24 pt glyph and the corner mark there.
  - The morph curve and duration are illustrative; the system draws it.
- Helper: `components/live-activity/_widgets-liveactivity.js` (Live Activity, island, small family, notification and Watch stand-ins; promote to kit).
