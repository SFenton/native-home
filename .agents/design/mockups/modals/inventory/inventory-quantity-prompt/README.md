# Quantity prompt (modal)
> **What:** the alert with a decimal-pad field: Add to Groceries, Delete how many, and the editor's Delete and Prepared prompts. **Read when:** you change InventoryPrompt, EditorPrompt or the row actions.
- Mockup: [inventory-quantity-prompt.html](inventory-quantity-prompt.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Inventory/{InventoryScreen,InventoryRowActions,InventoryItemEditor,InventoryPresentation}.swift`
- Spec: `.agents/pages/inventory/spec.md`, `ios.md` · Patterns: floating-actions
- States covered: default (shopping), delete, invalid (row error), editor-delete, editor-prepared, long-text, ax5, closed; loading, error, offline, detents have none (notes)
- Motion: system alert in (scale and fade). Transitions: shopping alert, delete alert
- Devices: iPhone, Duo, iPad (keyboard drawn on compact only)
- Open notes: the Delete button is not role destructive (a fix finding); an invalid entry closes the alert and puts the error on the row; from the page the alert is always dark, from the editor it follows the sheet.
