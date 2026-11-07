# Ingredient row, fact list, chip flow (component)
> **What:** the rows of the recipe sheet's inset lists: ingredient (mark, title, chips, source), fact, plain name, step, source link, and the Add to Grocery List action in every state. **Read when:** you change the recipe detail's rows or the grocery action.
- Mockup: [recipe-ingredient-row.html](recipe-ingredient-row.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Food/RecipeDetailView.swift`, `RecipeDetailRows.swift`, `RecipeSectionHeader.swift`, `HassCore/Recipes/RecipeFormatting.swift`, `RecipeGroceryPolicy.swift` · Spec: `.agents/pages/food/spec.md`, `ios.md` · Patterns: module-list, modal-sheet
- States covered: have, missing, uncertain, staple, optional, override; groups; quantities-only; facts, names, link, notice, steps; chip flow; grocery idle, adding, added, failed, disabled; ax5
- Motion: grocery button cross-fade (state 0.6 s), inline arc
- Devices: sheet surface; size class via the Device control
- Open notes: rows are read-only (per-row grocery add and overrides not ported); ios.md says fact rows drop the glyph at AX sizes, the code keeps it
