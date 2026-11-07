# Quick Links to a page (flow)

> **What:** The Quick Links sheet, its in-sheet Rooms level, and the close-then-push to a page. **Read when:** you touch QuickLinksSheet, shellSheets or pushPending.

- Mockup: [quick-links-to-page.html](quick-links-to-page.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Rooms/QuickLinksSheet.swift`, `apple/Sources/HassUI/App/Shell/ShellHeader.swift`, `apple/Sources/HassUI/Features/Home/HomeRoute.swift`
- Spec: `.agents/pages/rooms/ios.md`, `.agents/design/direction-g.md`, `.agents/patterns/modal-sheet.md`, `.agents/design/motion.md` · Patterns: modal-sheet, entity-tile, dynamic-grid, motion
- States covered: home, open-sheet, rooms-detail-pushed-in-sheet, choose-page, sheet-dismisses, page-pushes-after-dismissal, room-chosen, sprinklers-hidden, ax5
- Motion: sheet then push in order; sheet present; three transitions
- Devices: iPhone, folded Duo, unfolded Duo landscape, iPad (both)
- Open notes: Target pages are trimmed stand-ins. Media's symbol (appletvremote.gen4) is not in the kit map; tv is drawn.
