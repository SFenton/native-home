# FilterSheet, FilterSection, FilterOptionRow (component)
> **What:** the shared sort and filter sheet: Cancel and Apply, titled sections of single-choice rows, a blue Reset to Defaults row shown only when there is something to reset. **Read when:** you add a sort or filter sheet or change `FilterSheet`.
- Mockup: [filter-sheet.html](filter-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/FilterSheet.swift`, `SheetEditToolbar.swift`, `HassUI/Features/Food/RecipesScreen.swift`, `Inventory/InventoryControlSheets.swift` · Spec: `.agents/patterns/floating-actions.md`, `modal-sheet.md` · Patterns: floating-actions, modal-sheet, motion
- States covered: anatomy (defaults, changed, option row), toolbar states, Sort and Filter Recipes and Inventory in context, iPad form sheet, ax5; dark and light with the Sheet appearance control
- Motion: check cross-fade (quick 0.2 s); Apply enabling has none of its own
- Devices: iPhone and iPad via the Device control (in-context panels draw both)
- Open notes: floating-actions.md says `detents` (medium, large) and `[.large]` for Inventory; the code has `height: .fitted/.full`, Inventory is fitted too
