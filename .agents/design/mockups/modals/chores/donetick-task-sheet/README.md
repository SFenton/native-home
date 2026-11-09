# Task sheet (create and edit) (modal)
> **What:** New Task and Edit Task for Choreapp chores, with recurrence, due date and delete. **Read when:** you change the task form, its footers or its delete flow.
- Mockup: [donetick-task-sheet.html](donetick-task-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Features/Chores/DonetickTaskSheet.swift`, `HassDesign/{HassModal,SheetFit,SheetEditToolbar}.swift`, `HassCore/Todo/DonetickTaskForm.swift` · Spec: `.agents/pages/chores/spec.md`, `ios.md`, patterns `schedule-date-fields` · Patterns: modal-sheet, schedule-date-fields
- States covered: default (create), loading task, load error, offline, create-filled, due, interval, days of week, edit, edit-changed, saving, create error, delete confirm, medium, large, fitted, closed, ax5; dark and light
- Motion: confirm busy arc; present and dismiss
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (fitted form sheet, 540 pt on regular width)
- Open notes: ios.md large-detent claim is out of date; the delete popover anchor on iPad is not verified.
