# Sort Inventory (modal)
> **What:** the fitted form sheet on FilterSheet: Sort By (Title, Expiration Date) and Sort Direction, Apply and Reset to Defaults. **Read when:** you change InventoryControlSheets, FilterSheet or the sort rules.
- Mockup: [inventory-sort-sheet.html](inventory-sort-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Inventory/InventoryControlSheets.swift`, `HassDesign/{FilterSheet,SheetEditToolbar}.swift`
- Spec: `.agents/pages/inventory/spec.md`, `ios.md` · Patterns: floating-actions, modal-sheet
- States covered: default, changed, descending, medium, fitted, large, closed (presenter), ax5; light and dark in the gallery; loading, error and offline have none (notes)
- Motion: option check fade (0.2 s). Transitions: present, Apply dismiss
- Devices: iPhone, Duo folded and unfolded, iPad (540 pt form sheet)
- Open notes: no loading, error or offline state (local draft); Duo unfolded sheet placement is the system's; the Sort button is filled while a non-default sort is applied.
