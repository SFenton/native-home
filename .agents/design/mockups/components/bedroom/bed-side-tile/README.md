# Bed side and wake light tiles (component)
> **What:** the Bedroom 1's bed side and wake light cards (the room page's RoomCardView; the dedicated BedSideTile and WakeLightTile views are deleted): GlassTile navigation tiles in the heating, cooling and lights families, a bed side with a Power disc. **Read when:** you change the Bedroom 1 tiles or their subtitles.
- Mockup: [bed-side-tile.html](bed-side-tile.html) · status in-flight:claude/tile-rollout · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Rooms/RoomTiles.swift`, `apple/Sources/HassUI/Features/Bedroom/BedSpecialModesTab.swift` · Spec: .agents/patterns/bedroom-devices.md, entity-tile.md · Patterns: bedroom-devices, entity-tile, motion
- States covered: bed states (heating, idle, cooling, off, unavailable, ringing, hot flash, Solo Trip), wake states (armed, active, recovering, none, blocked, vacation, unavailable), in the Sleep & Wake grid, ax5
- Motion: tile colour fade (state 0.6 s), countdown tick (no animation)
- Devices: iPhone and iPad size classes
- Open notes: idle tile is filled (doc says dark); ringing does not change the tile
- Change log: 2026-10-28 tile rollout R: bed sides gain a toggle-styled Power disc (off is confirmed); BedSideTile and WakeLightTile deleted, the gallery draws the room page's cards.
