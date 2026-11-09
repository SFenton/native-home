# Food & Recipes

> **What:** the Food & Recipes hub, the Recipes grid and the recipe detail. **Read when:** porting or changing `Features/Food` or the Pantryhub recipe services.

Web source: `ha-sfenton-react-dash@9ac2a46` `src/pages/FoodHubPage.tsx`, `src/pages/RecipesPage.tsx`, `src/components/hass/recipes/*`, `src/constants/everShelfFood.ts`; copy from `src/i18n/locales/en/pages/food.json` and `modals/recipe.json`. Project plan: `plans/recipes-spec.md`.

## Routes

- Every page waits behind the shared load gate (spinner, then content; web `DashboardPageLoadGate`).
- `food` "Food & Recipes" (hub) → `recipes` "Recipes", `all-food` and the five space inventories. Every Food detail route goes back to `food`.
- Entry points: At-a-Glance quick access and the Kitchen page's Food tile (subtitle `FoodConfig.foodSummarySubtitle`).

## Hub

1. **Suggested Recipes:** paged carousel, 5 pages; columns `clamp(ceil((w + 10) / 230), 2...10)`, rows 3 (2 at ≥ 900 pt). `evershelf.recipe_query {kind: recommendations, limit}`. Placeholders while loading; "Suggested recipes are temporarily unavailable." on failure. A card opens the recipe detail.
2. **All Recipes** tile (web blue) → `recipes`.
3. **All Food** tile (web sage green), subtitle `{n Items} • {n Expiring Soon}` from `sensor.demo_sensor_15` (fallback: the spaces' sum) and `sensor.demo_sensor_11`.
4. **Food Spaces:** Pantry, Fridge, Freezer, Spice Rack, Cabinet, each in its web tile colour (`everShelfFood.ts:13-18`); each subtitle counts its sensor and the `expiring_list` items at its location expiring within 7 days (`pantry → dispensa`, `fridge → frigo`).

## Recipes

- Criteria: search (250 ms debounce, whitespace collapsed), sort (Ingredients Available default, Expiring Soon, Alphabetical), filters (minimum coverage 0, availability weight 100, expiry weight 25, expiring only with 7 / 30 / 90 days).
- `recipe_query {kind: browse, q, sort, availability_weight, expiry_weight, minimum_coverage, expiring_within_days?, limit: 50, cursor?}`; the next page loads 8 cards from the end; a failed page shows Retry.
- Hydration for queries of 3+ characters: after 600 ms `recipe_hydration {query}`, then poll `{search_id}` every `next_poll_ms` (1 s default, 30 s cap) until complete, exhausted or failed; new cards that pass the filters are appended and announced.
- States: loading, "Unable to Load Recipes" + Retry, "No Recipes Found" (search or filter copy).
- Floating actions: Search ("Search recipes"), Sort, Filter, tinted when active; sheets edit a draft with Cancel / Apply / Reset to Defaults.

## Recipe detail

- `recipe_detail {recipe_id}` (`recipe_detail_v1`); errors "Recipe Details Unsupported" / "Unable to Load Recipe". Tabs General, Ingredients, Instructions.
- **General:** hero, facts (Yield, times, Difficulty, Category only with general metadata, else the Cookidoo notice), Source, Locale, Content Language, Freshness; Devices, Optional Devices, Additional Equipment; Open Source Recipe / Open in Cookidoo.
- **Ingredients:** grouped sections ("Section n", "Other Ingredients"), status per row (overrides win; uncertain reads as missing), chips, and "Add to Grocery List" (the web says "Add Missing Ingredients to Groceries"; owner rename 2026-10-16, with the description "Adds the missing ingredients for this recipe to your shopping list."): `recipe_grocery_add {recipe_id, selections [{key, position}] ≤ 100, idempotency_key, todo_entity_id: todo.demo_todo_2}`; disabled reasons and the result sentence port `recipeGroceryState.ts` and `groceryFeedback`. The idempotency key is reused until a definitive answer so a retry replays instead of doubling.
- **Instructions:** local grouped steps, vertically centred in the sheet while they fit (owner, 2026-10-16); Cookidoo recipes never show step text and link out instead.

## Not ported yet

- Per-row grocery add / remove (`todo.remove_item`), ingredient overrides, the Choose Product picker and identity feedback (`recipe_ingredient_decision`, `recipe_ingredient_override`, `recipe_identity_feedback`).
- "Add to My Week" (`recipe_planner_add`).
- The hub's "Scan Item" action (inventory lane).
- The inventory routes show a placeholder until the Inventory lane lands.
