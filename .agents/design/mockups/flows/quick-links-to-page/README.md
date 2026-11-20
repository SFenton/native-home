# Quick Links to a page (flow)

> **What:** The Quick Links sheet, its in-sheet Rooms level, and the close-then-push to a page. **Read when:** you touch QuickLinksSheet, shellSheets or pushPending.

- Mockup: [quick-links-to-page.html](quick-links-to-page.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/UIKitPort/App/Shell/UKShellHeaderItems.swift`
- Spec: `.agents/pages/rooms/ios.md`, `.agents/design/direction-g.md`, `.agents/patterns/modal-sheet.md`, `.agents/design/motion.md` · Patterns: modal-sheet, entity-tile, dynamic-grid, motion
- States covered: home, open-sheet, rooms-detail-pushed-in-sheet, choose-page, sheet-dismisses, page-pushes-after-dismissal, room-chosen, other-tab-rooms-in-sheet, other-tab-room-on-home-tab, other-tab-left-unchanged, sprinklers-hidden, ax5
- Motion: sheet then push in order; sheet then tab cut (a homed page from another tab); sheet present; four transitions
- Devices: iPhone, folded Duo, unfolded Duo landscape, iPad (both)
- Rule: a page link in any sheet closes every level of it, then pushes; a level stays in the sheet. See `.agents/patterns/modal-sheet.md`.
- Other tab: a homed page lands under its home tab by a cut after the sheet closes; Back pops there.
- Open notes: Target pages are trimmed stand-ins. Media's symbol (appletvremote.gen4) is not in the kit map; tv is drawn.
