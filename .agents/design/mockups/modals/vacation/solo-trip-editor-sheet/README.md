# Solo Trip schedule editor sheet (modal)

> **What:** the Schedule Solo Trip form sheet: Departs, Returns, alerts, primary button. **Read when:** you change the editor or its alerts.

- Mockup: [solo-trip-editor-sheet.html](solo-trip-editor-sheet.html) · shipped · reviewed 2026-10-23 (author self-check; skill reviewers replace it)
- Source: `apple/Sources/HassUI/Features/Vacation/SoloTripScreen.swift`, `HassDesign/ScheduleDateFields.swift`, `HassCore/HouseholdAway/SoloTripController.swift`
- Spec: `.agents/pages/vacation/spec.md`, `ios.md` · Patterns: schedule-date-fields, modal-sheet
- States covered: default, range error, no traveler, scheduling (loading), command failed (error), setup required, Vacation engaged, offline, medium, large, fitted, closed, AX5; dark and light.
- Motion: none of its own; system sheet present and dismiss.
- Devices: iPhone, Duo folded, Duo unfolded portrait and landscape, iPad portrait and landscape (form sheet 540 pt on iPad).
- Open note: Not dismissible while scheduling; no spinner in the button (review fix candidate).
- Open note: Unfolded Duo placement across the hinge is the system's; unverified.
