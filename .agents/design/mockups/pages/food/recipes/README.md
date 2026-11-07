# Recipes (page)
> **What:** every recipe Pantryhub can suggest: a card grid with endless loading, the shared floating Search, Sort and Filter, and a recipe that opens in a trailing pane where the window splits, else a sheet. **Read when:** you change `RecipesScreen`, its gate, the floating bar, or the recipe pane.
- Mockup: [recipes.html](recipes.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Food/RecipesScreen.swift`, `FoodModels.swift`, `RecipeDetailView.swift` (pane), `HassDesign/FloatingActionBar.swift`, `ImageCard.swift`, `Loading/ContentGate.swift`
- Spec: `.agents/pages/food/spec.md`, `ios.md` · Patterns: floating-actions, image-card, content-gate, modal-sheet, motion
- States covered: default, loading, reload, refreshing (= default), empty (filters, search), error, search-open, searched, active (sort and filter on), next-page loading and failed, hydrating, detail (pane or sheet), offline, reconnecting (+ was), long-text, ax5
- Motion: results gate (.results profile), pane slide (standard 0.3 s; opacity 0.2 s under Reduce Motion), search expand, sort/filter tint (state 0.6 s), photo fade. Transitions: card to sheet, Sort and Filter sheets, Apply reload, push from the hub
- Devices: iPhone, Duo folded and unfolded, iPad (the pane only on landscape iPad and unfolded Duo landscape)
- Open notes: the pane splits at the content midpoint, not the hinge; floating-actions.md mentions a `detents` argument the code does not have; the pane's top edge approximates the end of the large title
