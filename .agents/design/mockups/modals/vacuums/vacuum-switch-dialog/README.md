# Use Area / Use Rooms (confirmation) (modal)
> **What:** the system alert that guards choosing Use Area or Use Rooms. **Read when:** you change the alert copy (`AlertCopy`) in `VacuumControlsTab.swift`, `VacuumSwitchToRoomsAlert.swift` or `VacuumMapPanel.swift`.
- Mockup: [vacuum-switch-dialog.html](vacuum-switch-dialog.html) · status shipped (PR #210) · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/UIKitPort/Features/Vacuums/UKVacuumTabs.swift`, `apple/Sources/HassUI/Features/Vacuums/VacuumMapPanel.swift` · Spec: `.agents/patterns/vacuum-sheet.md, .agents/pages/vacuums/spec.md` · Patterns: vacuum-sheet, modal-sheet
- States covered: Use Rooms? and Use Area? alerts, alert on the Rooms section and on the map, offline, large, closed, ax5; loading/error noted as none
- Motion: none; transitions: dialog and alert present
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape
- Open notes: the vacuum-sheet mockup used to draw an action sheet; fixed to `.alert` (code is `.alert`); the presenter is duplicated in two views (review finding)
