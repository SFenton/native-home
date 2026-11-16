# Rename to-do item sheet (modal)
> **What:** Edit Task for an admin to-do: one name field, Reset to Original, Save when changed. **Read when:** you change the rename sheet.
- Mockup: [rename-todo-item-sheet.html](rename-todo-item-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/UIKitPort/Features/Chores/UKTodoForms.swift`, `apple/Sources/HassUI/UIKitPort/ServerUI/UKServerUIFormView.swift` (the publication authors the layout) · Spec: `.agents/pages/chores/spec.md`, `ios.md` · Patterns: modal-sheet
- States covered: default, changed, saving, error, no identity, offline, detents, closed, ax5; dark and light
- Motion: confirm busy arc; present and dismiss
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (fitted form sheet, 540 pt on regular width)
- Open notes: no loading state; Reset row exists only when there is something to reset.
