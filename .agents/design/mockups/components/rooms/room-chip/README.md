# Room status rail and chip (component)

> **What:** the chips under a room title and how each kind is coloured. **Read when:** you change a room chip or the room rail.

- Mockup: [room-chip.html](room-chip.html) · shipped · reviewed 2026-10-23 (author draft; skill reviewers replace it)
- Source: `apple/Sources/HassUI/` Features/Rooms/RoomTiles.swift; Features/Home/StatusRail.swift, StatusChipAppearance.swift; HassDesign/ChipRail.swift
- Spec: .agents/patterns/status-rail.md · Patterns: status-rail, entity-tile
- States covered: lights, climate gradient, occupancy, window (four house states), plural doors, air quality, inert, unavailable, real rails, ax5
- Motion: chip colour, lights off
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait
- Open notes:
  - Contact chips draw a door glyph even for a window.
- Shared helper: `pages/rooms/_rooms.js` (rooms batch; list of kit promotions in its header).
