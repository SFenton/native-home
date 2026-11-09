# HeaderEdgeFade (component)
> **What:** content fades to clear under a page or modal header over a 40 pt ramp; hard edge for Reduce Transparency, Increase Contrast and iOS 17. **Read when:** you touch a header, a scroll-edge effect or a pinned bar.
- Mockup: [header-edge-fade.html](header-edge-fade.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/HeaderEdgeFade.swift`, `apple/Sources/HassDesign/NavigationGlass.swift` · Spec: .agents/patterns/header-edge-fade.md, .agents/design/direction-g.md · Patterns: header-edge-fade, modal-sheet, page-backdrop
- States covered: rule at three offsets, live scroll (page and sheet), sheet header, hard edge, real page, geometry, ax5
- Motion: fade follows the scroll offset (not time); hard edge switch
- Devices: iPhone and iPad size classes
- Open notes: doc says onScrollGeometryChange; iOS uses a UIKit observer
- Collapsed title (owner 2026-10-27): the system's centred inline title replaces the left-aligned one on collapsing pages (iPhone, iPad with flyout); Duo and compact iPad show the system's inline title too (owner 2026-10-27), truncated by the system. See rule R7 in the pattern.
- Inline title always (owner 2026-10-28: "Not good. Keep text in header the whole time."): no page has a large title; the mock demos that draw one show the retired layout. See R7.
- Pages (owner 2026-10-28: "Still choppy. Remove the fade", chose "A. iOS standard: the system's own scroll-edge effect and bar material"): no fade on pages; the demos describe modals only. See R8.
- Duo vertical-bar title (owner 2026-10-29, 2026-10-30): folded, unfolded-landscape and partial (Book) landscape poses show the title in the bar at a fixed 24 pt semibold, never collapsing and in a bar that never minimises; unfolded portrait, iPhone and iPad keep the system large title. This mockup draws the iPhone only; the Duo page mockups draw it with the kit class `ui-t-vbar`. See R7 (6).
