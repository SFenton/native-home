# Placeholder screen (page)

> **What:** The "Not Available Yet" page (with Try Again) a pushed Home route shows when there is no connection. **Read when:** you touch HomeRouteDestination, PlaceholderScreen or the debug galleries.

- Mockup: [placeholder-screen.html](placeholder-screen.html) · shipped (a placeholder: no signed-in path reaches it) · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Placeholders/PlaceholderScreen.swift`, `apple/Sources/HassUI/Features/Home/HomeRoute.swift`, `apple/Sources/HassUI/App/MainTabView.swift`
- Spec: `.agents/design/direction-g.md`, `.agents/design/apple/iphone.md`, `.agents/design/apple/duo.md` · Patterns: page-backdrop, header-edge-fade
- States covered: default (Sprinklers), vacuums, media, custom-lights, grocery-list, long-text, offline, reconnecting (arc), ax5; loading, refreshing, empty and error are explained in notes
- Motion: none of its own; one push transition
- Devices: iPhone, folded Duo, unfolded Duo (portrait, landscape), iPad (portrait, landscape)
- Open notes: No document describes this view; the catalog lists rooms among its users but only vacuums, media, custom lights, sprinklers and the grocery list reach it. The copy is untrue for pages that exist (review: fix).
