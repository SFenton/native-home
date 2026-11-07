# Room overview tile (component)
> **What:** the room card of an overview sheet in each of its five kinds, lit or filled only while something is on, occupied or open. **Read when:** you change `RoomOverviewTile`, `AirQualityRoomTile` or `RoomOverviewStyle`.
- Mockup: [room-overview-tile.html](room-overview-tile.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Common/RoomOverview/RoomOverviewTile.swift`, `RoomOverviewStyle.swift`, `AirQualityRoomTile.swift`, `HassDesign/GlassTile.swift` · Spec: `.agents/patterns/room-overview-sheet.md`, `.agents/patterns/entity-tile.md` · Patterns: room-overview-sheet, entity-tile, dynamic-grid
- States covered: lights, climate, occupancy, contacts, air quality (good to unavailable), in-context grids, ax5; sheet surface, dark and light
- Motion: card fills (0.6 s colour, glyph swap), AQI rim change
- Devices: size class via the Device control (iPhone, iPad)
- Open notes: chevron on four kinds versus direction-g "not navigation"; no unavailable face; AQI band is colour only
- Rollout L (2026-10-28): a Lights card carries a room power disc left of its chevron (any light on turns the room off, else on; one call on the room's group light) and is two tracks wide; the other kinds are unchanged.
