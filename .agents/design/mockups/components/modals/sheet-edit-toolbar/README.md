# SheetCancelItem and SheetConfirmItem (component)
> **What:** the toolbar of create and edit sheets: circle x Cancel leading, a filled #0071E3 check trailing, dimmed until there is a change, an inline arc while saving. **Read when:** you build an edit sheet or change `SheetEditToolbar`.
- Mockup: [sheet-edit-toolbar.html](sheet-edit-toolbar.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/SheetEditToolbar.swift`, `HassModal.swift` (SheetCloseItem), `ArcSpinner.swift`, `FilterSheet.swift`, `Features/Chores/TodoItemSheets.swift` · Spec: `.agents/patterns/modal-sheet.md`, `direction-g.md` (Sheets) · Patterns: modal-sheet, motion
- States covered: buttons (Cancel, Cancel dimmed, confirm enabled, disabled, busy, Close), headers (new, valid, saving, edit, filter), in context, ax5; dark and light
- Motion: enable (system), saving arc (0.82 s a turn, half speed under Reduce Motion)
- Devices: iPhone and iPad via the Device control
- Open notes: humidifier schedule, feedback and the bed and wake-light editors still use text buttons (modal-sheet.md); pre-iOS 26 draws icon-only buttons, the kit draws the iOS 26 glass circles
