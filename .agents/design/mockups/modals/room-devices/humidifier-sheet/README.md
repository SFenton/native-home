# Humidifier sheet (Controls, Schedules, Info) (modal)
> **What:** the humidifier sheet: mist dial and power, then Controls, Schedules and Info in the bottom bar; two columns where a split is allowed. **Read when:** you change `HumidifierSheet` or its tabs.
- Mockup: [humidifier-sheet.html](humidifier-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/RoomDevices/HumidifierSheet.swift, HumidifierDials.swift, HumidifierSchedulesTab.swift, HassDesign/ThermostatDial/ThermostatDial.swift` (paths under `apple/Sources/` unless full) · Spec: `.agents/patterns/room-device-sheets.md, thermostat-dial.md` · Patterns: room-device-sheets, thermostat-dial, modal-sheet, status-pill
- States covered: controls (Auto, Manual, Sleep, off, target above 60%), tank removed, water low, unavailable, offline, schedules (loading, list, running, empty, vacation, not admin, error), info, ax5; medium/fitted do not exist
- Motion: dial handle (0.2 s), pill tone (0.6 s); transitions: present, dismiss, tab cut, push to editor
- Devices: iPhone, Duo folded, Duo unfolded landscape (two columns), iPad portrait, iPad landscape (two columns)
- Open notes: tab switch is a cut here (the vacuum sheet fades); `.page, height: .full` only
