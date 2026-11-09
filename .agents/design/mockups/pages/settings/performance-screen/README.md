# Performance (diagnostics) (page)

> **What:** Settings, Performance: scrolling, page loading, navigation, live updates, actions and images, the recording switch, export and reset. **Read when:** you change `HassUI/Diagnostics` or add a measurement row.

- Mockup: [performance-screen.html](performance-screen.html) · shipped · reviewed 2026-10-23 (apple-hig and swiftui-pro skill review)
- Source: `apple/Sources/HassUI/Diagnostics/PerformanceScreen.swift`, `PerformanceReport.swift`, `PerformanceRow.swift`
- Spec: `.agents/patterns/telemetry.md`, `.agents/testing/apple/performance.md`  · Patterns: telemetry
- States covered: default (seeded), empty, recording-off, refreshing, no-export, offline, reconnecting, long-text, ax5 (loading and error do not exist).
- Motion: None of its own. Transitions: push from Settings; the share sheet (system).
- Devices: iPhone, Duo folded, unfolded portrait and landscape, iPad portrait and landscape.
- Helpers: `pages/settings/_settings-account.js`, `pages/settings/_settings-page.js` (shared builders and local symbols; promote-to-kit list in the mockup's Notes).
- Open notes: Reviews flag: headers and footers use Ink.secondary on the wallpaper (3.8:1 risk), rows are the opaque system cell not the module, destructive rows act with no confirmation. Refresh toolbar button position unverified.
