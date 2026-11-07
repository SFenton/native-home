# Vacation dates (confirmation sheet) (modal)

> **What:** the Confirm Vacation form sheet: Starts, Ends, range error, primary button. **Read when:** you change the vacation confirmation.

- Mockup: [vacation-confirmation-sheet.html](vacation-confirmation-sheet.html) · shipped · reviewed 2026-10-23 (author self-check; skill reviewers replace it)
- Source: `apple/Sources/HassUI/Features/Vacation/VacationComponents.swift`, `HassDesign/ScheduleDateFields.swift`, `HassCore/Config/VacationConfig.swift`
- Spec: `.agents/pages/vacation/spec.md`, `ios.md`, `.agents/patterns/schedule-date-fields.md` · Patterns: schedule-date-fields, modal-sheet
- States covered: default, invalid range, loading and error (notes), offline, medium, large, fitted, closed, AX5; dark and light.
- Motion: none of its own; system sheet present and dismiss.
- Devices: iPhone, Duo folded, Duo unfolded portrait and landscape, iPad portrait and landscape (form sheet 540 pt on iPad).
- Open note: Departure: the primary action is a content button, not the toolbar check.
