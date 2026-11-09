# Kitchen room page (page)

> **What:** the Kitchen: Groceries section (Grocery List, Food) plus Appliances and Climate. **Read when:** you change the Kitchen page or KitchenGroceriesSection.

- Mockup: [room-kitchen.html](room-kitchen.html) · status in flight (`claude/section-sides`) (action and navigation tiles, #186) · reviewed 2026-10-23 (author draft; skill reviewers replace it)
- Source: `apple/Sources/HassUI/` RoomScreen.swift (KitchenGroceriesSection); RoomTiles.swift; HassCore/Rooms/RoomsConfig.swift (kitchen, Groceries)
- Spec: .agents/pages/rooms/spec.md, ios.md, .agents/pages/chores/ios.md · Patterns: status-rail, entity-tile, dynamic-grid
- States covered: default, loading, refreshing, error, offline, reconnecting (+ was), counts, groceries-1, dishwasher-running, active, long-text, groceries-only (code branch), ax5, placeholder
- Motion: dishwasher start (face cross-fade), Door chip colour; transitions: Grocery List and Food pushes, dishwasher sheet
- Devices: iPhone, Duo folded, Duo unfolded landscape and portrait, iPad portrait and landscape
- Open notes:
  - empty never shows: Groceries always draws.
  - Docs say "Food & Recipes", the tile reads "Food"; KitchenGroceriesSection is in no doc.
- Shared helper: `pages/rooms/_rooms.js` (rooms batch; list of kit promotions in its header).
- Change log: 2026-10-27 action tiles (claude/action-nav-tiles). renders the shared room-card builders, so its PC, towel rack, garage and remote cards are action tiles (see room-card-tile).
- In flight (`claude/section-sides`, [section-sides](../../../../section-sides.md)): partly folded Duo, each section wholly on one side (fold columns); state `duo-part-fold`. Every other pose unchanged.
