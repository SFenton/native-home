# Apple Watch app stub (page)

> **What:** the one placeholder screen the Watch target draws: a house, "S+H", "Coming soon". **Read when:** you touch the watchOS target or ask what the Watch app does today (nothing).

- Mockup: [watch-app.html](watch-app.html) · status placeholder · reviewed 2026-10-23
- Source: `apple/Apps/watchOS/FentonHomeWatchApp.swift`, `apple/Sources/HassCore/Spotlight/AppBranding.swift` · Spec: `.agents/design/apple/watchos.md`, `.agents/platforms/apple/app-name.md` · Patterns: none
- States covered: default, ax5 (the other page states are listed as not applicable in the notes)
- Motion: none
- Devices: Apple Watch 46 mm (a device registered by the helper; the kit has none)
- Open notes:
  - Placeholder: planned scope (security, open contacts, lights count, favourite toggles) is not built and is not drawn.
  - AX behaviour of the unscrolled VStack unverified on a Watch.
- Helper: `components/live-activity/_widgets-liveactivity.js` (Live Activity, island, small family, notification and Watch stand-ins; promote to kit).
