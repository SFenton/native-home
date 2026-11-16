# Add grocery item sheet (modal)
> **What:** one Item field with subtitle "Groceries"; Add disabled until text. **Read when:** you change the grocery add prompt.
- Mockup: [add-grocery-item-sheet.html](add-grocery-item-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/UIKitPort/Features/Chores/UKTodoForms.swift`, `apple/Sources/HassUI/UIKitPort/ServerUI/UKServerUIFormView.swift` (the publication authors the layout) · Spec: `.agents/pages/chores/spec.md`, `ios.md` · Patterns: modal-sheet
- States covered: default, typed, saving, error, offline, detents, closed, ax5; dark and light
- Motion: confirm busy arc; present and dismiss
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (fitted form sheet, 540 pt on regular width)
- Open notes: no loading state; keyboard not drawn.
