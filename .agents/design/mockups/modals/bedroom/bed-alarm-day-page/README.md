# Bed alarm day page (modal)
> **What:** one weekday's alarms for a bed side, pushed inside the bed sheet from the Alarms tab. **Read when:** you change `BedAlarmDayPage` or alarm rows.
- Mockup: [bed-alarm-day-page.html](bed-alarm-day-page.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Bedroom/BedAlarmsTab.swift` · Spec: .agents/patterns/bedroom-devices.md, modal-sheet.md · Patterns: bedroom-devices, modal-sheet, motion
- States covered: default (Monday), two-alarms (Saturday), empty, ringing, read-only, error (schedule unavailable), offline, large, ax5
- Motion: alarm switch, row added (standard 0.3 s); push in and out, push to the editor
- Devices: iPhone, Duo (folded, unfolded), iPad (portrait, landscape)
- Open notes: pushed pages show Back only (the root toolbar owns Close)
