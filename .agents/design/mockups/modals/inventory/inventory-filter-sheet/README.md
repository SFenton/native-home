# Filter Inventory (modal)
> **What:** the form sheet with one "Show" list of seven expiry filters and an "n of N Items" subtitle that follows the draft. **Read when:** you change InventoryFilterSheet, FilterSheet or the filter windows.
- Mockup: [inventory-filter-sheet.html](inventory-filter-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Inventory/{InventoryControlSheets,InventoryListModel+Summary}.swift`, `HassDesign/{FilterSheet,SheetSubtitle}.swift`, `HassCore/Inventory/InventoryCatalog.swift`
- Spec: `.agents/pages/inventory/spec.md`, `ios.md` · Patterns: floating-actions, modal-sheet
- States covered: default, changed, expired, none, zero, medium, fitted, large, closed, ax5; light and dark; loading, error, offline have none (notes)
- Motion: option check fade (0.2 s), subtitle count swap (none, flagged). Transitions: present, Apply dismiss
- Devices: iPhone, Duo folded and unfolded, iPad
- Open notes: the subtitle is iOS 26 only, so the count is lost on iOS 17 and 18 (a fix finding); Duo unfolded sheet placement is the system's.
