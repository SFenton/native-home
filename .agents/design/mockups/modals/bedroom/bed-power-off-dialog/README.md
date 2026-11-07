# Turn off bed side? (modal)
> **What:** the confirmation dialog after Turn Off on the bed sheet (action sheet on iPhone, popover on iPad). **Read when:** you change the power capsule or its confirmation.
- Mockup: [bed-power-off-dialog.html](bed-power-off-dialog.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Bedroom/BedSideSheet.swift` · Spec: .agents/patterns/bedroom-devices.md, .agents/design/direction-g.md · Patterns: bedroom-devices, modal-sheet
- States covered: default (Alex), sam, whole-bed, closed, ax5; dark and light
- Motion: dialog in (system); confirm and side goes off
- Devices: iPhone, Duo, iPad (popover drawn centred)
- Open notes: loading, error, offline and detents do not apply to a system dialog
