# Bed alarm editor (modal)
> **What:** adds or edits one Bed alarm, pushed inside the bed sheet (days picker or locked day, time, enabled, wake lights, Save, Delete). **Read when:** you change `BedAlarmEditor`, `WeekdayPicker` or the alarm save and delete flow.
- Mockup: [bed-alarm-editor.html](bed-alarm-editor.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Bedroom/BedAlarmsTab.swift`, `apple/Sources/HassUI/Features/Bedroom/BedroomComponents.swift` · Spec: .agents/patterns/bedroom-devices.md, schedule-date-fields.md · Patterns: bedroom-devices, modal-sheet, schedule-date-fields, optimistic-actions
- States covered: default (day locked), add-days, edit, edit-disabled, problem-days, saving, delete-confirm, error, unavailable, read-only, ringing, offline, large, ax5
- Motion: day chip fill (state 0.6 s), wake switch, Save label; push in, pop to the Alarms tab, delete dialog
- Devices: iPhone, Duo (folded, unfolded), iPad (portrait, landscape)
- Open notes: long nav title ("Add Alex's Bed Monday Alarm") at AX5 needs a device check
