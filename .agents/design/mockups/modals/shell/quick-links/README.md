# Quick Links sheet (modal)

> **What:** the header button's sheet: up to seven solid-colour tiles; Rooms and Security System push inside, the rest open pages. **Read when:** you change Quick Links tiles, colours or routing.

- Mockup: [quick-links.html](quick-links.html) · shipped · reviewed 2026-10-23 (author draft; skill reviewers replace it)
- Source: `apple/Sources/HassUI/` Features/Rooms/QuickLinksSheet.swift; HassDesign/QuickLinkPalette.swift; HassCore/Rooms/RoomNavigation.swift
- Spec: .agents/pages/rooms/ios.md, .agents/design/direction-g.md · Patterns: modal-sheet, entity-tile, dynamic-grid
- States covered: default, loading, error, offline, sprinklers-hidden, armed-away/night, disarmed, triggered, redacted, food-counts, was-full, medium (provisional), large, fitted (shipped), closed, ax5; dark and light
- Motion: Security colour follows the alarm; transitions: present (zoom out of the header button), Rooms push (sheet refits), Security push, page link (sheet closes then pushes), dismiss
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape
- Open notes:
  - Pushed levels show Back and no Close (Close is on the root view only): read from code, confirm on device.
- Shared helper: `pages/rooms/_rooms.js` (rooms batch; list of kit promotions in its header).
- Rollout L (2026-10-28): the Security System tile has an Arm Home / Disarm disc and spans the row on a phone (the one exception to "all one size"); the other six are unchanged.
- Fitted height, 2026-10-28 (shipped in #185; owner option B of `proposals/sheet-bottom-gap`): no second 34 pt band under the last tile (20 pt on an iPad). Tiles sheet visible height: iPhone 17 Pro 587 pt (was 620), folded Duo 615 (649), iPad portrait 524 (544); the last tile ends 56, 58 and 43 pt above the window's bottom edge (89, 92, 63). The Rooms and Security System pushes follow the same rule. Still to redraw if the owner wants the band shown explicitly: `quick-links-rooms`, `quick-links-security-system`.
