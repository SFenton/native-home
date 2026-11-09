# FloatingActionBar (component)

> **What:** The page's bottom toolbar of floating Liquid Glass buttons: primary capsule, secondary capsule, 52 pt circles, search. **Read when:** changing a page's floating actions or the search behaviour.

- Mockup: [floating-action-bar.html](floating-action-bar.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/FloatingActionBar.swift`, `TodoPageView.swift`, `RecipesScreen.swift`, `InventoryScreen.swift`
- Spec: `.agents/patterns/floating-actions.md` · Patterns: floating-actions, motion
- States covered: variants and states (kit), chores-add, recipes, recipes-idle, search-open, inventory, inventory-empty, ax5 (two-row reflow); usages drawn on device frames.
- Motion: search expand (standard 0.3 s), filter applied (state 0.6 s).
- Devices: iPhone, Duo folded, iPad portrait and landscape.
- Open notes: Recipes prompt is "Search recipes" in code, "Search Recipes" in the pattern record. Glass is a stand-in.
- Shared helper: `pages/settings/_household-forms.js` (household-forms batch; local icons and builders, "promote to kit" in the notes).
