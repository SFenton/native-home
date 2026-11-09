# Vacation date fields (start, end, range error) (component)

> **What:** Starts and Ends date-and-time pickers with the range error. **Read when:** you change vacation or schedule date pickers.

- Mockup: [vacation-date-fields.html](vacation-date-fields.html) · shipped · reviewed 2026-10-23 (author self-check; skill reviewers replace it)
- Source: `apple/Sources/HassUI/Features/Vacation/VacationModeScreen.swift`, `HassDesign/ScheduleDateFields.swift`
- Spec: `.agents/patterns/schedule-date-fields.md` · Patterns: schedule-date-fields
- States covered: valid, invalid range, single field, long labels; AX5 via the Text size control; page and sheet surface.
- Motion: none.
- Devices: iPhone and iPad size classes.
- Open note: Pickers are drawn as date and time buttons; the real control is the system compact picker.
