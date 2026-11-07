# Climate overview (modal)
> **What:** the sheet Home's Climate chip opens: one dark card per room with its temperature range, pushing the room's sensors and vents. **Read when:** you change `RoomOverviewSheet` for `.climate` or the range text rules.
- Mockup: [room-overview-climate.html](room-overview-climate.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Common/RoomOverview/RoomOverviewSheet.swift`, `RoomOverviewGrid.swift`, `RoomOverviewTile.swift`, `RoomOverviewStyle.swift`, `HassCore/Rooms/RoomOverview.swift`, `RoomGroups.swift` · Spec: `.agents/pages/home/spec.md`, `.agents/pages/home/ios.md`, `.agents/patterns/room-overview-sheet.md` · Patterns: room-overview-sheet, modal-sheet, dynamic-grid, entity-tile, status-rail
- States covered: default (large, the one detent), loading (empty store), error (unavailable entities), offline, reconnecting, long-text (xxxLarge), ax5, pushed room (Office), closed (the presenter); dark and light side by side in the States gallery
- Motion: none of its own (climate cards never fill); transitions: present, push, pop, dismiss
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (704 pt page sheet on iPad and the unfolded Duo)
- Open notes: "1 sensors" grammar as shipped; medium and fitted detents do not exist (hassSheet .full); no true loading state; cards have no unavailable face; direction-g.md and patterns/motion.md disagree with the code (chevron and plain push, not zoom)
