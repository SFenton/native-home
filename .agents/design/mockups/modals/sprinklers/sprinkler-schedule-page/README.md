# Zone program schedule editor (pushed) (modal)

> **What:** the pushed schedule editor: enable, days, start times, budget, Apply. **Read when:** you change the program editor.

- Mockup: [sprinkler-schedule-page.html](sprinkler-schedule-page.html) · shipped · reviewed 2026-10-23 (author self-check; skill reviewers replace it)
- Source: `apple/Sources/HassUI/Features/Sprinklers/SprinklersScreen.swift`, `SprinklerControllerSheet.swift`, `apple/Sources/HassCore/Sprinklers/SprinklerFormat.swift`
- Spec: `.agents/pages/sprinklers/spec.md`, `ios.md`, `.agents/patterns/schedule-date-fields.md` · Patterns: modal-sheet, schedule-date-fields, optimistic-actions
- States covered: default, edited, disabled program, watering, no days, unavailable, sending (loading), error, offline, closed, AX5; dark and light.
- Motion: day chip colour (state 0.6 s), program switch; system push and pop.
- Devices: iPhone, Duo folded, Duo unfolded portrait and landscape, iPad portrait and landscape.
- Open note: Start times use their own DatePicker rows, not ScheduleDateFields (listed there as planned).
- Open note: Adding or removing a start time is not animated.
