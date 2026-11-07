# Tonight or All Nights? (modal)
> **What:** the second, fitted form sheet over the bed sheet asking whether a new target applies tonight or to every night of the stage. **Read when:** you change `BedTemperatureScopeSheet` or the target commit flow.
- Mockup: [bed-temperature-scope-sheet.html](bed-temperature-scope-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Bedroom/BedSideSheet.swift`, `apple/Sources/HassUI/Features/Bedroom/BedScopeCopy.swift` · Spec: .agents/patterns/bedroom-devices.md, modal-sheet.md · Patterns: bedroom-devices, modal-sheet
- States covered: default (Asleep +4), bedtime, dawn, medium, fitted, large, offline, ax5; dark and light
- Motion: sheet over sheet (system), choice dismisses
- Devices: iPhone, Duo, iPad (form sheet 540 pt)
- Open notes: stacking a sheet on a sheet is undocumented (review: fix); nav title is "Set Bed Temperature"
