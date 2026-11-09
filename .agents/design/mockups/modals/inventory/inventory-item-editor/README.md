# Item editor (modal)
> **What:** the per-batch editor (Quantity, Expiration Date, Prepared Food, Delete): a form sheet, or the trailing pane where the window splits. **Read when:** you change InventoryItemEditor, InventoryEditorModel or the split behaviour.
- Mockup: [inventory-item-editor.html](inventory-item-editor.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Inventory/{InventoryItemEditor,InventoryRow,InventoryPresentation}.swift`, `HassCore/Inventory/InventoryEditorModel.swift`, `HassDesign/{SheetEditToolbar,FormSectionText,SheetSubtitle}.swift`
- Spec: `.agents/pages/inventory/ios.md`, `.agents/patterns/modal-sheet.md` · Patterns: modal-sheet
- States covered: default (one batch), multiple-batches, changes, prepared, prepared-updating, saving, deleting, error, offline, no-expiry, delete-prompt, pane, medium, fitted, large, closed, ax5
- Motion: toggle (0.3 s / 0.6 s), save arc, pane slide (0.3 s). Transitions: present, Save dismiss, how-many alert
- Devices: iPhone, Duo folded, unfolded portrait (sheet), iPad and Duo landscape (pane)
- Open notes: landscape devices show the pane for every state (use a portrait device for the sheet); the pane's ground (black, #1C1C1E cells) is unconfirmed; Form header size is the system's for a bare FormHeader.
