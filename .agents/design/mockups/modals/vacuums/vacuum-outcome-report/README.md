# Cleaning outcome report (pushed) (modal)
> **What:** the room-by-room cleaning report pushed from the vacuum sheet. **Read when:** you change `VacuumOutcomeDetailView` or `VacuumOutcomeText`.
- Mockup: [vacuum-outcome-report.html](vacuum-outcome-report.html) · status shipped (PR #210) · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Vacuums/VacuumMapPanel.swift, HassCore/Vacuums/VacuumOutcomes.swift, VacuumOutcomeFixtures.swift` (paths under `apple/Sources/` unless full) · Spec: `.agents/patterns/vacuum-sheet.md, .agents/pages/vacuums/spec.md` · Patterns: vacuum-sheet, module-list, modal-sheet
- States covered: interrupted fixture, all completed, stuck, unverified, offline, large, closed, ax5; loading/error noted as none
- Motion: none; transition: push from the report row
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (page sheet)
- Open notes: the report has no map; only the sheet behind it changes (no names, status tiles); spec.md lists "Cleaning Evidence" and a Back label the native page does not have
