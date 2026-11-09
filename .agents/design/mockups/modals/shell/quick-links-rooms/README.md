# Quick Links: Rooms grid (modal)

> **What:** the sixteen room tiles, ranked by visits, pushed inside Quick Links. **Read when:** you change the Rooms grid, RoomPalette or the ranking.

- Mockup: [quick-links-rooms.html](quick-links-rooms.html) · shipped · reviewed 2026-10-23 (author draft; skill reviewers replace it)
- Source: `apple/Sources/HassUI/` Features/Rooms/QuickLinksSheet.swift (RoomNavigationGrid); HassDesign/RoomPalette.swift; HassCore/Rooms/RoomNavigation.swift
- Spec: .agents/pages/rooms/ios.md, spec.md, direction-g.md · Patterns: modal-sheet, entity-tile, dynamic-grid
- States covered: default (ranked), loading and error (configured order), offline, reranked, medium/large/fitted (large only), closed, ax5; dark and light
- Motion: none of its own; transitions: push in, room tile to room page
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape
- Open notes:
  - Fire-and-forget visit counting (try?).
- Shared helper: `pages/rooms/_rooms.js` (rooms batch; list of kit promotions in its header).
