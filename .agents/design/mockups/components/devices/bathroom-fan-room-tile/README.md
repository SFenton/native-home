# Bathroom fan room tile and rail button (component)
> **What:** the fan tile on a bathroom room page: an air navigate tile with Lock and Power rail buttons. **Read when:** you change `BathroomFanRoomTile`, `FanRailButton` or the accessory placement.
- Mockup: [bathroom-fan-room-tile.html](bathroom-fan-room-tile.html) · status shipped (action and navigation tiles, #186) · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Rooms/BathroomFanRoomTile.swift, FanRailButton.swift, HassDesign/GlassTile.swift` (paths under `apple/Sources/` unless full) · Spec: `.agents/patterns/entity-tile.md, room-device-sheets.md` · Patterns: entity-tile, room-device-sheets, dynamic-grid
- States covered: off, on, timer running, locked, unavailable, in a room page (lead row vs grid), rail variants, the sheet Power and Lock tiles, long countdown, ax5
- Motion: rail and tile fill (0.6 s), countdown tick
- Devices: compact (iPhone) and regular (iPad) width
- Open notes: nested buttons inside a navigating tile (owner design); rail offset is a local fix to promote to GlassTile
- Change log: 2026-10-27 action tiles (claude/action-nav-tiles): behavior/actions, discs, strip, volume slider, flat read-only face; see patterns/action-tiles.md.
