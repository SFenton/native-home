# Notification, Spotlight and Live Activity deep links (flow)

> **What:** Five ways into a page from outside the app and where each lands. **Read when:** you touch PushCoordinator, SpotlightCatalog, SHShortcuts or ActivityDeepLink.

- Mockup: [notification-deep-link.html](notification-deep-link.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/App/Push/PushCoordinator.swift`, `apple/Sources/HassCore/Push/PushLink.swift`, `apple/Sources/HassCore/Push/PushDestination.swift`, `apple/Apps/iOS/SHShortcuts.swift`, `apple/Sources/FentonActivityModel/ActivityDeepLink.swift`
- Spec: `.agents/platforms/apple/push.md`, `.agents/platforms/apple/live-activities-per-job.md`, `.agents/platforms/apple/app-name.md` · Patterns: motion
- States covered: push to section, push to page with an anchor sheet, Spotlight, App Shortcut, Live Activity, unknown page, link-mapping, ax5
- Motion: lands as a cut or push; the anchor sheet opens after the push
- Devices: iPhone, folded Duo, iPad portrait, unfolded Duo landscape
- Open notes: push.md says anchors are not scrolled to; the code opens a room card sheet from an anchor. System UI (banner, Spotlight, shortcut tile, lock-screen card) is a stand-in.
