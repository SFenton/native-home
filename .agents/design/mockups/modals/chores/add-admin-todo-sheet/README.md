# Add admin to-do sheet (with images) (modal)
> **What:** Add Task with a public-repo disclosure and up to four images. **Read when:** you change the admin add sheet or its upload rules.
- Mockup: [add-admin-todo-sheet.html](add-admin-todo-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Features/Chores/TodoItemSheets.swift`, `HassDesign/{HassModal,SheetFit,SheetEditToolbar}.swift`, `HassCore/Todo/TodoServicing.swift` · Spec: `.agents/pages/chores/spec.md`, `ios.md` · Patterns: modal-sheet
- States covered: default, typed, with images, uploading, image-rule error, upload error, offline, detents, closed, ax5; dark and light
- Motion: confirm busy arc; present and dismiss
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (fitted form sheet, 540 pt on regular width)
- Open notes: system photo picker not drawn; thumbnails are kit stand-ins.
