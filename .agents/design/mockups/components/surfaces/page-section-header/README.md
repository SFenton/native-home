# Page section header and form header/footer (component)
> **What:** the 20 Bold page header with optional detail, FormHeader and FormFooter in a sheet, and the iOS 26 sheet subtitle. **Read when:** you add a section header, a form section or a sheet subtitle.
- Mockup: [page-section-header.html](page-section-header.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/{PageSectionHeader,FormSectionText,SheetSubtitle,FilterSheet}.swift`, `HassUI/Features/Inventory/InventoryScreen.swift`, `Food/FoodHubScreen.swift`
- Spec: `.agents/design/direction-g.md` · Patterns: modal-sheet, floating-actions
- States covered: variants (plain, with detail), in-context (Food, Inventory, Vacuums), form-and-subtitle, ax5
- Motion: none
- Devices: iPhone, iPad (size class), embedded devices
- Open notes: a bare FormHeader keeps the system header size while FilterSection sets 15 Semibold (the kit draws 15 everywhere); the subtitle is lost before iOS 26.
