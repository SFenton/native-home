# Humidifier activity editor (pushed) (modal)
> **What:** the page pushed inside the humidifier sheet to add or edit a scheduled activity. **Read when:** you change `HumidifierActivityEditor` or the schedule controller.
- Mockup: [humidifier-activity-editor.html](humidifier-activity-editor.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/RoomDevices/HumidifierSchedulesTab.swift, HumidifierDials.swift, HassCore/RoomDevices/HumidifierSchedule.swift` (paths under `apple/Sources/` unless full) · Spec: `.agents/patterns/schedule-date-fields.md, room-device-sheets.md` · Patterns: room-device-sheets, thermostat-dial, modal-sheet
- States covered: new, edit (Auto Humidity), edit Sleep, overlap, no days, saving, save failed, delete confirmation, offline, large, closed, ax5
- Motion: none of its own; transitions: push, pop, delete dialog
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (page sheet)
- Open notes: uses time-only DatePickers, not ScheduleDateFields; Save drawn as a glass capsule (iOS 26 look unchecked); also covers schedule-delete-dialog
