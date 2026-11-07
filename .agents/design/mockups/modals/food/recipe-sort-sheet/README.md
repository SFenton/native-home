# Sort Recipes (modal)
> **What:** the sheet the Sort circle on Recipes opens: three single-choice rows with explanations in a fitted form sheet on `FilterSheet`, Apply and Reset to Defaults. **Read when:** you change `RecipeSortSheet` or `RecipeSort`.
- Mockup: [recipe-sort-sheet.html](recipe-sort-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Food/RecipesScreen.swift`, `HassCore/Recipes/RecipeModels.swift` (RecipeSort), `HassDesign/FilterSheet.swift`, `SheetEditToolbar.swift`
- Spec: `.agents/pages/food/spec.md`, `ios.md`, `.agents/patterns/floating-actions.md` · Patterns: floating-actions, modal-sheet, motion
- States covered: default, changed, expiring, applied, medium, large, fitted, closed, ax5; dark and light in the gallery
- Motion: check cross-fade (quick 0.2 s). Transitions: present, Apply dismiss
- Devices: iPhone, Duo folded and unfolded, iPad (540 pt form sheet)
- Open notes: no loading, error or offline state (a local draft); "medium" is only the provisional detent before measurement
