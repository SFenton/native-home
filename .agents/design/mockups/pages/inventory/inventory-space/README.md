# Inventory space (page)
> **What:** the six inventory pages (All Food, Pantry, Fridge, Freezer, Spice Rack, Cabinet) as one template: summary line, dense-module rows (optionally grouped by expiry), floating Search, Sort, Filter and Scan Item. **Read when:** you change InventoryScreen, InventoryRow, the sections or the editor pane, or need the state list (gate, empty, error, swipe, split).
- Mockup: [inventory-space.html](inventory-space.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Inventory/{InventoryScreen,InventoryRoute,InventorySections,InventoryPresentation,InventoryRow,InventoryRowActions,InventoryEmptyState}.swift`, `HassCore/Inventory/{InventoryCatalog,InventoryListModel}.swift`
- Spec: `.agents/pages/inventory/spec.md`, `ios.md` · Patterns: floating-actions, content-gate, module-list, motion
- States covered: default (All Food), by-expiry (+desc), loading (gate), refreshing, empty, error, offline, reconnecting (arc), long-text, ax5, search, search-empty, filter-empty, swipe-lead, swipe-trail, cart-added, row-error, redacted, not-signed-in, editor, editor-pane, prompts, delete-confirm, sort/filter/scan sheets open, five instance spaces
- Motion: page gate (page and results profiles), cart swap (none), row wash (0.6 s), editor pane slide (0.3 s). Transitions: push, three sheets, alerts
- Devices: iPhone, Duo folded, Duo unfolded portrait and landscape, iPad portrait and landscape (editor pane where it splits)
- Open notes: InventoryScreen splits in two equal halves without reading the hinge, so on the unfolded Duo the pane crosses the fold (docs say the divider goes on the hinge); spec.md describes the web rows, ios.md the native page; Not Signed In uses a stand-in glyph.
