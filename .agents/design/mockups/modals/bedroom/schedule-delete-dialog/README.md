# Delete alarm or activity? (modal)
> **What:** the one confirmation-dialog pattern used by the wake alarm editor, the bed alarm editor and the humidifier activity editor. **Read when:** you change any delete confirmation for a schedule.
- Mockup: [schedule-delete-dialog.html](schedule-delete-dialog.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Bedroom/WakeLightEditor.swift`, `apple/Sources/HassUI/Features/Bedroom/BedAlarmsTab.swift`, `apple/Sources/HassUI/Features/RoomDevices/HumidifierSchedulesTab.swift` · Spec: .agents/patterns/bedroom-devices.md, room-device-sheets.md · Patterns: bedroom-devices, room-device-sheets, modal-sheet
- States covered: default (wake alarm), bed, humidifier, ax5; dark and light
- Motion: dialog in (system)
- Devices: iPhone, Duo, iPad (popover drawn centred)
- Open notes: the humidifier editor behind is a trimmed copy (another batch owns it); button wording differs by site
