# Bathroom fan sheet (modal)
> **What:** the bathroom fan sheet: Power and Lock tiles and an off timer (six lengths, or a running orange countdown). **Read when:** you change `BathroomFanSheet`, the fan timer controls or the fan tile.
- Mockup: [bathroom-fan-sheet.html](bathroom-fan-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/RoomDevices/BathroomFanSheet.swift, FanTimer*.swift, TintedCapsuleButtonStyle.swift, RoomDeviceSheetChrome.swift` (paths under `apple/Sources/` unless full) · Spec: `.agents/patterns/room-device-sheets.md, entity-tile.md` · Patterns: room-device-sheets, modal-sheet, entity-tile
- States covered: off + picker, running + locked, on without timer, unavailable, offline, medium, large, fitted, closed, ax5 (picker and running)
- Motion: tile colour (0.6 s), countdown tick (1 Hz, no animation); transitions: present, dismiss, picker to running (cut)
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (form sheet)
- Open notes: no loading state; Live Activity is started by Home Assistant (job tag), not this sheet
- Change log: 2026-10-28 tile rollout R: Power and Lock are action tiles (text . disc, FanRailActions).
