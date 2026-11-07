# Filter Recipes (modal)
> **What:** the sheet the Filter circle on Recipes opens: Ingredient Coverage, Expiring Ingredients and Ranking Strength in a fitted form sheet on `FilterSheet`. **Read when:** you change `RecipeFilterSheet`, its sliders or the horizon control.
- Mockup: [recipe-filter-sheet.html](recipe-filter-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Food/RecipesScreen.swift`, `FoodModels.swift` (RecipeFilters), `RecipeSectionHeader.swift`, `HassDesign/FilterSheet.swift`, `SheetEditToolbar.swift`
- Spec: `.agents/pages/food/spec.md`, `ios.md`, `.agents/patterns/floating-actions.md` · Patterns: floating-actions, modal-sheet, motion
- States covered: default, coverage, expiring, two filters, weights only, alphabetical, applied, medium, large, fitted, closed, ax5; dark and light in the gallery
- Motion: switch knob and track, slider; Apply and subtitle change without animation. Transitions: present, Apply dismiss
- Devices: iPhone, Duo folded and unfolded, iPad (540 pt form sheet)
- Open notes: loading, error and offline do not exist (a local draft); floating-actions.md says `FilterSheet(detents:)`, the code has `height:`; the 7 / 30 / 90 Days control is a menu at AX sizes
