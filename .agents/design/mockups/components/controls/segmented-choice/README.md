# SegmentedChoice and percent slider row (component)

> **What:** A short single choice (segmented, a menu at AX) and the labelled 0 to 100 slider row. **Read when:** adding a two to four option choice or a percentage slider.

- Mockup: [segmented-choice.html](segmented-choice.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Common/SegmentedChoice.swift`, `RecipesScreen.swift` (PercentSliderRow)
- Spec: `.agents/design/direction-g.md`, `.agents/patterns/floating-actions.md` · Patterns: floating-actions, modal-sheet
- States covered: variants (three, two, menu), real usages, no selection, disabled, slider rows, Filter Recipes context, ax5; sheet surface.
- Motion: none of its own (system segment and slider; explained).
- Devices: size class via the Device control.
- Open notes: RecipeHorizonPicker repeats the segmented-or-menu switch instead of using SegmentedChoice.
- Shared helper: `pages/settings/_household-forms.js` (household-forms batch; local icons and builders, "promote to kit" in the notes).
