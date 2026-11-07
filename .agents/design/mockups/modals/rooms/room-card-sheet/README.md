# Room card sheet (modal)

> **What:** what a room card or chip opens without a sheet of its own: group sheets, vents, house-wide doors, fallbacks. **Read when:** you change RoomCardSheet or a room group sheet.

- Mockup: [room-card-sheet.html](room-card-sheet.html) · shipped · reviewed 2026-10-23 (author draft; skill reviewers replace it)
- Source: `apple/Sources/HassUI/` Features/Rooms/RoomSheets.swift; RoomDeviceRouting.swift; Common/RoomOverview/RoomGroupDetail*.swift, LightGroupTile.swift; HassCore/Rooms/RoomController.swift
- Spec: .agents/pages/rooms/ios.md, .agents/patterns/room-overview-sheet.md, modal-sheet.md · Patterns: modal-sheet, room-overview-sheet, entity-tile
- States covered: default (lights), loading, error, offline, lights-off/single/nightstands/switch, climate (+ single), occupancy, contacts (+ closed), all-contacts, contacts-detail, items, device-fallback, no-controls, medium/large/fitted (large only), closed, ax5; dark and light
- Motion: brightness band, sensor fill; transitions: present, dismiss, push inside sheet (no zoom)
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (page sheet)
- Open notes:
  - One detent: large (hassSheet(.page, .full)).
  - Fallback prints entity ids as titles when HA gives no friendly name.
- Shared helper: `pages/rooms/_rooms.js` (rooms batch; list of kit promotions in its header).
