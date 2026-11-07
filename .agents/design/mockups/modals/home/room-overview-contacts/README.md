# Contact Sensors overview (modal)
> **What:** the sheet the Contact Sensors chip opens on Home and on Security: rooms with doors and windows, filled soft green while something is open. **Read when:** you change `RoomOverviewSheet` for `.contacts` or the door and window summaries.
- Mockup: [room-overview-contacts.html](room-overview-contacts.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Common/RoomOverview/RoomOverviewSheet.swift`, `RoomOverviewGrid.swift`, `RoomOverviewTile.swift`, `RoomOverviewStyle.swift`, `HassCore/Rooms/RoomOverview.swift`, `RoomGroups.swift`, `Features/Security/SecurityScreen.swift` · Spec: `.agents/pages/home/spec.md`, `.agents/pages/home/ios.md`, `.agents/patterns/room-overview-sheet.md` · Patterns: room-overview-sheet, modal-sheet, dynamic-grid, entity-tile, status-rail
- States covered: default (large, the one detent), loading (empty store), error (unavailable entities), offline, reconnecting, long-text (xxxLarge), ax5, pushed room, closed (the presenter); dark and light side by side in the States gallery; quiet (all closed), from-security (page behind)
- Motion: door opens (0.6 s colour, glyph swap). Transitions: present, push, pop, dismiss
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (704 pt page sheet on iPad and the unfolded Duo)
- Open notes: medium and fitted detents do not exist (hassSheet .full); no true loading state; cards have no unavailable face; direction-g.md and patterns/motion.md disagree with the code (chevron and plain push, not zoom)
