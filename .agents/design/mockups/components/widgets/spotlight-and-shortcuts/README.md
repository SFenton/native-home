# Spotlight results and App Shortcuts (component)

> **What:** the strings, symbols, phrases and thumbnails S+H gives Spotlight, Siri and the Shortcuts app. **Read when:** you change a shortcut, the Spotlight catalog, the app name or its search terms.

- Mockup: [spotlight-and-shortcuts.html](spotlight-and-shortcuts.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Apps/iOS/SHShortcuts.swift`, `OpenPageIntent.swift`, `AppPageOption.swift`, `apple/Sources/HassUI/App/Spotlight/CoreSpotlightIndexer.swift`, `HassCore/Spotlight/SpotlightCatalog.swift`, `AppBranding.swift` · Spec: `.agents/platforms/apple/app-name.md` · Patterns: none
- States covered: default ("S+H"), ha ("Home Assistant"), room, shortcuts, phrases, intent, catalog (21 pages), ax5
- Motion: none
- Devices: iPhone, iPhone Duo folded (system UI)
- Open notes:
  - System UI: layouts approximate iOS; only the titles, descriptions, symbols and phrases are S+H's.
  - list.clipboard.fill is drawn with the kit's checklist; promote to kit.
- Helper: `components/live-activity/_widgets-liveactivity.js` (Live Activity, island, small family, notification and Watch stand-ins; promote to kit).
