# Room group detail (modal)
> **What:** the page a room card pushes inside an overview sheet: group title, live subtitle, tiles; lights are live, the rest read-only. **Read when:** you change `RoomGroupDetailPage`, `RoomGroupDetail` or how lights, vents, sensors and doors read in a room.
- Mockup: [room-group-detail.html](room-group-detail.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Common/RoomOverview/RoomGroupDetailPage.swift`, `RoomGroupDetail.swift`, `LightGroupTile.swift`, `HassDesign/BrightnessTile.swift` · Spec: `.agents/patterns/room-overview-sheet.md`, `.agents/pages/home/ios.md` · Patterns: room-overview-sheet, dynamic-grid, entity-tile, optimistic-actions
- States covered: default (Living Room Lights with group slab), single light, nightstands, dragging, quiet, climate (closed and open vent), occupancy, contacts, loading, error per kind, offline, reconnecting, long-text, ax5, redacted, from-security, overview
- Motion: brightness drag (lift, bubble, band), optimistic power with revert, vent fills, sensor fills. Transitions: push, pop, dismiss
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (704 pt page sheet on iPad and the unfolded Duo)
- Open notes: Home's pages draw headings; room pages hide the occupancy and contact headings; medium and fitted do not exist; `turn_on` and `turn_off`, never toggle (recorded departure)
