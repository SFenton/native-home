# Empty and error states (component)

> **What:** Reference sheet of every empty and error message in the app (system ContentUnavailableView and the two plain-stack look-alikes). **Read when:** writing or reviewing an empty or error state.

- Mockup: [content-unavailable.html](content-unavailable.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/{Rooms/RoomScreen,Chores/TodoPageView,Food/RecipesScreen,Food/RecipeDetailView,Inventory/InventoryEmptyState,Inventory/InventoryRoute,Placeholders/PlaceholderScreen}.swift` and the others listed in the mockup
- Spec: `.agents/design/direction-g.md` · Patterns: content-gate, floating-actions
- States covered: pages (16 messages), sheets (8), in-room (a Room page), ax5.
- Motion: none (static messages).
- Devices: size class via the Device control; the in-room state draws a device frame.
- Open notes: About a dozen call sites compose their own view; there is no shared EmptyState. Recipes and Inventory avoid the system view because of text-size clipping.
- Shared helper: `pages/settings/_household-forms.js` (household-forms batch; local icons and builders, "promote to kit" in the notes).
