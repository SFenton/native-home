# Climate room detail (target dial, vents)
> **What:** one room's page pushed in the Advanced Controls sheet: its dial, away notice and read-only vent tiles. **Read when:** you change `ClimateRoomDetail`, the dial at modal size, or the vent tiles.
- Mockup: [climate-room-detail.html](climate-room-detail.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Climate/ClimateRoomsTab.swift` (ClimateRoomDetail), `HassUI/Controls/Thermostat/ClimateThermostatDial.swift`, `HassDesign/ThermostatDial/*`, `HassCore/Climate/ClimateLogic.swift`
- Spec: `.agents/pages/climate/spec.md`, `ios.md`, `.agents/patterns/thermostat-dial.md` · Patterns: thermostat-dial, modal-sheet, dynamic-grid, entity-tile, optimistic-actions
- States covered: default (Living Room, two vents), heating, cooling, single (one target), closed-vent (Office), away, loading, error, offline, large, ax5; dark and light side by side
- Motion: handle glide (quick 0.2 s), vent fill and status colour (state 0.6 s). Transitions: push from the Rooms tab, pop
- Devices: iPhone, Duo folded, Duo unfolded landscape and portrait, iPad portrait and landscape
- Open notes: vents have no control (read-only, as on the web); the away notice is a plain row, not ClimateNotice; the dial is the shared local `SecClimate.dial`
