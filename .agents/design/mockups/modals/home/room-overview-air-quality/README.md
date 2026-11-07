# Air Quality overview (modal)
> **What:** the sheet Home's Air Quality chip opens: six read-only room cards with AQI and PM2.5, glyph and rim in each room's AQI colour. **Read when:** you change `RoomOverviewSheet` for `.airQuality` or `AirQualityRoomTile`.
- Mockup: [room-overview-air-quality.html](room-overview-air-quality.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Common/RoomOverview/RoomOverviewSheet.swift`, `RoomOverviewGrid.swift`, `RoomOverviewTile.swift`, `RoomOverviewStyle.swift`, `HassCore/Rooms/RoomOverview.swift`, `RoomGroups.swift`, `AirQualityRoomTile.swift` · Spec: `.agents/pages/home/spec.md`, `.agents/pages/home/ios.md`, `.agents/patterns/room-overview-sheet.md` · Patterns: room-overview-sheet, modal-sheet, dynamic-grid, entity-tile, status-rail
- States covered: default, loading (empty store), error (unavailable sensors), offline, reconnecting, long-text, ax5, closed; no pushed room (read-only); dark and light in the States gallery
- Motion: AQI band change (0.6 s rim and glyph). Transitions: present, dismiss
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (704 pt page sheet on iPad and the unfolded Duo)
- Open notes: nothing pushes (catalog hint is wrong, detail branch is dead code); AQI band carried by colour only (review: fix); medium and fitted detents do not exist (hassSheet .full); no true loading state; cards have no unavailable face; direction-g.md and patterns/motion.md disagree with the code (chevron and plain push, not zoom)
