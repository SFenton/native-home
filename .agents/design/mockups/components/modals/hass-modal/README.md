# HassModal, SheetCloseItem and hassSheet sizing (component)
> **What:** the container every sheet is built from: inline title, circle x Close, content fading under the header with no material band, and `hassSheet` for the detent, the iPad form or page size, the grabber and the appearance. **Read when:** you present a sheet or change `HassModal`, `SheetFit` or the sizing rules.
- Mockup: [hass-modal.html](hass-modal.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/HassModal.swift`, `SheetFit.swift`, `SheetEditToolbar.swift`, `HassUI/Features/Settings/AppIcon/AppIconPickerSheet.swift`, `Features/Food/RecipeDetailView.swift` · Spec: `.agents/patterns/modal-sheet.md`, `direction-g.md` (Sheets) · Patterns: modal-sheet, header-edge-fade, motion
- States covered: header states (viewing, edit, pushed), sizing (iPhone fitted and full, iPad form and page), always-dark, ax5; dark and light
- Motion: system sheet present and dismiss (Play); fitted resize is the system's
- Devices: iPhone and iPad via the Device control (the sizing panel draws both)
- Open notes: only the App Icon picker calls `HassModal`; every other sheet assembles the same parts by hand (modal-sheet.md says new modals use it)
