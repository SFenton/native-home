# Sheet presentation, detents and dismissal (flow)

> **What:** How hassSheet sizes, presents and dismisses a modal. **Read when:** you add or change a sheet, SheetFit or the appearance rules.

- Mockup: [sheet-presentation.html](sheet-presentation.html) · shipped (camera viewer fitted detent drawn as in flight) · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/HassModal.swift`, `apple/Sources/HassDesign/SheetFit.swift`, `apple/Sources/HassUI/Features/Cameras/CameraViewer.swift`
- Spec: `.agents/patterns/modal-sheet.md`, `.agents/design/direction-g.md`, `.agents/design/motion.md`, `.agents/design/apple/ipados.md` · Patterns: modal-sheet, header-edge-fade, motion
- States covered: fitted, provisional-medium, large, pushed-level-inside-sheet, ax5-capped-at-large, ipad-form, ipad-page, system-light, always-dark, camera-fitted-in-flight, camera-full-main, dismiss-swipe, dismiss-close
- Motion: present, detent settle, interactive dismiss; four transitions
- Devices: iPhone, folded Duo, unfolded Duo landscape, iPad (both)
- Open notes: Camera fitted height is unconfirmed (uncommitted in the primary checkout). split-view.md and iphone.md still call the viewer full-screen or large-only.
