# Delete item confirmation (modal)
> **What:** the confirmation dialog before deleting a single unit: "Delete <item> from the <place>?" with a red Delete. **Read when:** you change the single-unit delete path or the dialog copy.
- Mockup: [inventory-delete-dialog.html](inventory-delete-dialog.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Inventory/{InventoryScreen,InventoryRowActions,InventoryPresentation}.swift`
- Spec: `.agents/pages/inventory/spec.md`, `ios.md` · Patterns: floating-actions
- States covered: default (library), fridge, spice-rack, long-text, ax5, closed (swipe open); loading, error, offline, detents have none (notes)
- Motion: system action sheet rise (popover on regular). Transition: swipe Delete to dialog
- Devices: iPhone, Duo, iPad (popover drawn centred)
- Open notes: attached to the whole screen, so the iPad popover has no row anchor (fix finding); All Food says "library"; direction-g says destructive confirms are alerts, this is a dialog.
