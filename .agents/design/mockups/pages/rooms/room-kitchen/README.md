# Kitchen room page (page)

> **What:** the Kitchen: Groceries section (Grocery List, Food) plus Appliances and Climate. **Read when:** you change the Kitchen page or KitchenGroceriesSection.

- Mockup: [room-kitchen.html](room-kitchen.html) · status shipped (action and navigation tiles, #186) · reviewed 2026-10-23 (author draft; skill reviewers replace it)
- Source: `apple/Sources/HassUI/UIKitPort/ServerUI/UKServerUIRooms.swift`, `apple/Sources/HassUI/UIKitPort/ServerUI/UKServerUIPage.swift` (the publication authors the layout)
- Spec: .agents/pages/rooms/spec.md, ios.md, .agents/pages/chores/ios.md · Patterns: status-rail, entity-tile, dynamic-grid
- States covered: default, loading, refreshing, error, offline, reconnecting (+ was), counts, groceries-1, dishwasher-running, active, long-text, groceries-only (code branch), ax5, placeholder
- Motion: dishwasher start (face cross-fade), Door chip colour; transitions: Grocery List and Food pushes, dishwasher sheet
- Devices: iPhone, Duo folded, Duo unfolded landscape and portrait, iPad portrait and landscape
- Open notes:
  - empty never shows: Groceries always draws.
  - Docs say "Food & Recipes", the tile reads "Food"; KitchenGroceriesSection is in no doc.
- Shared helper: `pages/rooms/_rooms.js` (rooms batch; list of kit promotions in its header).
- Change log: 2026-10-27 action tiles (claude/action-nav-tiles). renders the shared room-card builders, so its PC, towel rack, garage and remote cards are action tiles (see room-card-tile).
- Partly folded Duo: when the Studio sets the page to Two Sides, each section sits wholly on one side ([section-sides](../../../../section-sides.md)), at every text size; a page left on One Column draws its flat layout with the band. State `duo-part-fold`. Every other pose unchanged.
