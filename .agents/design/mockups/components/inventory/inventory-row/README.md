# Inventory row (component)
> **What:** one inventory card: name, expiry line with tone, stock count, cart button, chevron, swipe actions; on the dense module or a sheet cell. **Read when:** you change InventoryRow, the expiry tones or the row actions.
- Mockup: [inventory-row.html](inventory-row.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Inventory/{InventoryRow,InventoryRowActions,InventoryScreen}.swift`, `Settings/Profile/ExpiredFoodList.swift`
- Spec: `.agents/pages/inventory/ios.md`, `.agents/patterns/module-list.md` · Patterns: module-list, floating-actions
- States covered: page and sheet surfaces (fresh, soon, expired, no date, count, batches, list of three), actions (cart idle/adding/added, swipes, selected, error, redacted), long-text, in-context, ax5
- Motion: cart swap (none), row wash (0.6 s)
- Devices: iPhone, iPad (size class), embedded devices
- Open notes: no low-stock state exists in the code; the whole row opens the editor via onTapGesture beside real buttons.
