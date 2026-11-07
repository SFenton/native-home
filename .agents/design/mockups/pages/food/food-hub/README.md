# Food & Recipes hub (page)
> **What:** the Food hub pushed under Home: Suggested Recipes (five paged pages), the All Recipes tile, All Food and the five Food Spaces tiles in their web colours, behind the page load gate. **Read when:** you change `FoodHubScreen`, `SuggestedRecipesCarousel`, the Food tiles or how the hub waits for its suggestions.
- Mockup: [food-hub.html](food-hub.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Food/FoodHubScreen.swift`, `FoodRoute.swift`, `SuggestedRecipesCarousel.swift`, `FoodFamilies.swift`, `HassCore/Config/FoodConfig.swift`, `HassDesign/ImageCard.swift`, `Loading/ContentGate.swift`
- Spec: `.agents/pages/food/spec.md`, `ios.md` · Patterns: content-gate, image-card, entity-tile, dynamic-grid, motion
- States covered: default, loading (page gate), refreshing (= default by design), empty, error, gave-up (10 s), offline, reconnecting (+ was), long-text, page-3, recipe-open (sheet), ax5
- Motion: gate (.page profile), carousel paging (standard 0.3 s, jump under Reduce Motion), photo fade (quick 0.2 s). Transitions: Quick Links push, recipe sheet, All Recipes push, space tile push
- Devices: iPhone, Duo folded, Duo unfolded (landscape splits recipes left, inventory right; portrait single), iPad portrait and landscape
- Open notes: the hub's split is two equal columns, not `SplitPolicy.geometry`, so the Duo hinge band falls inside the trailing column (layout arithmetic, unconfirmed on a simulator); the recipe card is a sheet, not the zoom motion.md lists; helper `pages/food/_food.js` holds pieces to promote to the kit
