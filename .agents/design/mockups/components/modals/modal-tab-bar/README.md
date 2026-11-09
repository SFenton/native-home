# ModalTabBar (component)
> **What:** the section switcher of a tabbed sheet: a segmented control on a glass capsule at the bottom, icons on compact width, titles on regular, a menu at accessibility sizes, badged segments for Your Summary. **Read when:** you add a section to a sheet or change `ModalTabBar`.
- Mockup: [modal-tab-bar.html](modal-tab-bar.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Common/ModalTabBar.swift`, `BadgedTabSegments.swift`, `BadgedTabSegment.swift`, `ModalTabSymbols.swift`, `Features/Food/RecipeDetailView.swift`, `Settings/Profile/YourSummarySheet.swift` · Spec: `.agents/patterns/modal-sheet.md`, `motion.md` 4.4 · Patterns: modal-sheet, motion
- States covered: forms (icons, titles, menu), badged, every tabbed sheet's sections, recipe detail and Your Summary in context, ax5
- Motion: the badged bar's selection glide (`.snappy(0.2)`, not a MotionToken); content swap is a cut
- Devices: iPhone and iPad via the Device control
- Open notes: the catalog hint "selection is a cut" holds for the content only; the kit draws a white selected pill, the badged bar really lifts onto the sheet cell
