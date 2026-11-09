# Delete task? (confirmation dialog) (modal)
> **What:** the "Delete {title}?" confirmationDialog every delete swipe, menu and VoiceOver action asks. **Read when:** you change delete confirmations on the chore pages, Summary tabs or task sheet.
- Mockup: [todo-delete-dialog.html](todo-delete-dialog.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Features/Chores/TodoPageView.swift` (todoDeletionDialog), `Settings/Profile/SummaryChoresTab.swift`, `DonetickTaskSheet.swift` · Spec: `.agents/pages/chores/spec.md`, `ios.md` · Patterns: modal-sheet, motion
- States covered: over Chores, groceries, a resident page, the Summary sheet, the task sheet; error, offline, closed, ax5; detents and loading noted as not applicable
- Motion: dialog rises; row leaves (standard 0.3 s)
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (action sheet on compact, popover on regular)
- Open notes: iPad popover anchor not verified; docs treat destructive confirmations as alerts.
