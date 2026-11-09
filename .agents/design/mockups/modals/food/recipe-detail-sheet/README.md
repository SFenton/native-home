# Recipe detail (modal)
> **What:** a recipe opened from a card: a full-height page sheet (a trailing pane on iPad and Duo landscape from Recipes) with General, Ingredients and Instructions on the bottom glass bar and one primary action, Add to Grocery List. **Read when:** you change `RecipeDetailView`, `RecipeDetailRows`, the grocery action or the section bar.
- Mockup: [recipe-detail-sheet.html](recipe-detail-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Food/RecipeDetailView.swift`, `RecipeDetailRows.swift`, `FoodModels.swift`, `HassCore/Recipes/RecipeFormatting.swift`, `RecipeGroceryPolicy.swift`, `HassUI/Common/ModalTabBar.swift`
- Spec: `.agents/pages/food/spec.md`, `ios.md`, `.agents/patterns/modal-sheet.md` · Patterns: modal-sheet, image-card, module-list, motion, optimistic-actions
- States covered: General, Ingredients, Instructions (+ grouped), Cookidoo General and Instructions, no photo, no ingredients, no instructions, truncated, grocery adding, added, failed, none, loading, error, unsupported, offline, large, pane (iPad, Duo), long-text, ax5; dark and light in the gallery
- Motion: grocery button to confirmation (state 0.6 s), inline arc, photo fade (0.2 s), tab switch is a cut. Transitions: present, dismiss, loading to loaded, tab cut
- Devices: iPhone, Duo folded and unfolded, iPad (page sheet 704 pt); pane on landscape
- Open notes: always `.large` (never fitted or medium); ios.md says "8/9 ingredients", the code says "8 of 9 Ingredients"; per-row grocery, overrides and the product picker are not ported
