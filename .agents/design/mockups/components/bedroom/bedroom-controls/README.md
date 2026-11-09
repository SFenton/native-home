# Bedroom controls (component)
> **What:** BedroomRow, BedroomSectionHeader, ChoiceGrid, WeekdayPicker, ClockTimeField shared by the wake-light and bed sheets. **Read when:** you change `BedroomComponents.swift`.
- Mockup: [bedroom-controls.html](bedroom-controls.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Bedroom/BedroomComponents.swift` · Spec: .agents/patterns/bedroom-devices.md, dynamic-grid.md · Patterns: bedroom-devices, dynamic-grid, schedule-date-fields, motion
- States covered: rows, choice grid, weekday picker, fields, ax5; light and dark sheet
- Motion: choice and weekday fill (state 0.6 s), switch
- Devices: iPhone and iPad size classes
