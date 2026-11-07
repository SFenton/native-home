# Home Live Activity widget configuration (component)

> **What:** the extension's one widget: which view each presentation uses, the system chrome it sets, taps and buttons. **Read when:** you touch the widget extension, the Live Activity chrome, deep links, or ask whether any Home Screen widget or Control exists (none).

- Mockup: [home-live-activity-widget.html](home-live-activity-widget.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Apps/Widgets/HomeLiveActivity.swift`, `FentonHomeWidgets.swift`, `apple/Apps/Shared/LiveActivityIntents.swift`, `FentonActivityModel/ActivityDeepLink.swift` · Spec: `.agents/platforms/apple/live-activities-per-job.md`, `live-activities.md` · Patterns: none
- States covered: default (every presentation of a fan), vacuum, problem, chrome (tints, keyline), links, bundle, ax5
- Motion: timers count (system)
- Devices: iPhone; Watch and CarPlay via the small family
- Open notes:
  - No Home Screen widgets, Lock Screen widgets or Controls exist (live-activities.md section 9).
  - Keyline drawn as a 1.5 pt ring; the system draws its own.
  - Engine and relay lane is not built: only fixtures and relay test content drive it.
- Helper: `components/live-activity/_widgets-liveactivity.js` (Live Activity, island, small family, notification and Watch stand-ins; promote to kit).
