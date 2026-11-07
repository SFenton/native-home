# ScheduleDateFields (component)

> **What:** Labelled compact date and time pickers on material rows, two per row when they fit. **Read when:** adding a schedule start, end or alarm time.

- Mockup: [schedule-date-fields.html](schedule-date-fields.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/ScheduleDateFields.swift`, `VacationModeScreen.swift`, `SoloTripScreen.swift`
- Spec: `.agents/patterns/schedule-date-fields.md` · Patterns: schedule-date-fields, settings-section
- States covered: variants (range, long label), date and time, single, date only and time only, vacation dates, invalid, disabled, ax5; page and sheet surfaces.
- Motion: commit delay timeline (0.9 s, 3 s fallback; a timer, not an animation).
- Devices: size class via the Device control.
- Open notes: The kit draws chips for the system compact picker; its popover is not drawn.
- Shared helper: `pages/settings/_household-forms.js` (household-forms batch; local icons and builders, "promote to kit" in the notes).
