# Inventory empty and error state (component)
> **What:** the centred basket or warning, title, description and Try Again shown instead of rows. **Read when:** you change InventoryEmptyState or InventoryCatalog.emptyState copy.
- Mockup: [inventory-empty-state.html](inventory-empty-state.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Inventory/{InventoryEmptyState,InventoryScreen}.swift`, `HassCore/Inventory/InventoryCatalog.swift`
- Spec: `.agents/pages/inventory/spec.md`, `ios.md` · Patterns: floating-actions, content-gate
- States covered: empty, error, filtered (search, search and filter, filter only), in-context (iPhone, iPad), ax5
- Motion: none (the gate belongs to the page)
- Devices: iPhone, iPad (size class), embedded devices
- Open notes: plain wrapping text, not ContentUnavailableView (it clipped at large sizes); the floating bar differs by case (Scan Item only on an empty page, all four when a search or filter hides rows).
