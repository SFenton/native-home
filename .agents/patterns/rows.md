# Rows (UIKit port)

> **What:** the one list row: slots for a leading glyph, check or avatar, the text (title, subtitle, value) and a trailing accessory or chevron. **Read when:** you are about to draw a title with a glyph, a value, a switch, a menu, a check or a chevron on one line, in a module list, a form cell, a settings cell or a sheet. UIKit port only (`UIKitPort/Design/UKRow.swift`); the SwiftUI app keeps `ModuleRow`, `SettingsLinkRow` and `CheckRow`.

Owner request, 2026-11-01: "Rows should inherit from a common component if they don't already (perhaps even the checkmark rows?)". About 70 row classes each carried their own stack, padding, wrap width and accessibility, which is why one wrap-width fix had to be applied row by row. There is now one component, `UKRowView`, and a row that needs something special composes its slots instead of forking its layout.

## The component

`UKRowView(UKRowContent, accessory:, textView:, surface:)` (non-final: a feature row is a thin subclass that builds its content and owns its callbacks).

| Slot | Content |
|---|---|
| Leading | `symbol` + `glyph` ink + `glyphOpacity`; `check` (the check variant: state, checked and unchecked tint, dimmed); or `leadingView` (an avatar, an app icon). `alignsLeadingToTop` for a tall text block. |
| Text | `title` (+ `titleInk`, `titleWeight`), `subtitle` (+ `subtitleInk`, or `subtitleIsValue` for an entity state that waits on `valuesPending`), `value` (+ `valueInk`; beside the text while both fit on a line, under it when they do not and at accessibility sizes), or a `textView` in place of title and subtitle (a todo item's title and due line). |
| Trailing | `accessory` (any view: switch, stepper, picker, menu button, text field with `expandsAccessory`, spinner, check mark), then `showsChevron`. `accessoryTrailingInset` sets the margin after it. |

- **Styles (`UKRowStyle`)** pick the metrics. `.module` is `ModuleRow`: 16 pt sides, 52 pt (60 with a subtitle), 24 pt glyph column (scaled with body), 14 pt gap, so hairlines start at `ModuleRowMetrics.textInset`. `.grouped` is `SettingsLinkRow`: the cell supplies the inset, 44 pt, a 34 pt title3 icon column, 12 pt gap, the icon above the text at accessibility sizes. `.form` is a row in a `Form` cell: 44 pt, 28 pt body glyph column, 12 pt gap. `verticalPadding` and `minHeight` override per row (the check rows use 11 pt; a card row 44 pt).
- **Wrapping.** Title, subtitle and value wrap at the row's own width less the leading column, value, accessory, chevron and gaps (`UKWrapWidth`, in `layoutSubviews`), never from their own width. The value-beside-or-under decision depends only on the row's width and the labels' unbounded widths, so it settles in one pass.
- **Accessibility sizes.** The accessory (and value) move under the text; in `.grouped` the icon sits above it. Min target 44 pt everywhere.
- **VoiceOver.** The text is one element "Title, subtitle" with the value as its value, then the accessory's own controls. `isTextAccessible = false` when the accessory is the element and carries the name (a switch, stepper, field, menu). A `tapTarget` (`installTapTarget`) replaces the text element: a control behind everything left of the accessory, so the accessory stays its own element and target.
- **Tappable.** `UKRowButton(row)` presses the whole row with a 10% wash and is one button named "Title, subtitle" (value as its value); `UKModuleToggleRow`, `UKClimateEntryRow`, `UKSprinklerControllerRow`, `UKVacuumRowButton`, `UKFormActionRow`, `UKGroupedRowButton`, `UKRoomsActionRow`, `UKRecipeLinkRow` and `UKTodoButtonRow` are subclasses.
- **Check variant.** `UKCheckRow` is a `UKRowView` with a `check` leading slot, a `textView` and a `UKCheckToggle` tap target ([check-row](check-row.md)); it adds no layout.
- **Card.** `drawsCard` puts the row on the secondary grouped ground with tile corners (the Setup status row).

## Inventory

| Row | Shows | Style / tap | Status |
|---|---|---|---|
| `UKRowView` (was `UKModuleRowView`) | glyph, title, subtitle, accessory, chevron | module | the component |
| `UKCheckRow` (todo item, vacation checklist, climate room rules) | check, text block, edit / Undo | module, 11 pt, tap target | variant |
| `UKSettingsLinkRowView`, `UKVersionRowView` | icon or app icon, title, subtitle, chevron; icon, title, build value | grouped | migrated (`UKRowView.settingsLink`, `.version`) |
| `UKFormSwitchRow`, `UKFormDateRow`, `UKFormStepperRow`, `UKFormFieldRow` (inventory editor, Add Item) | title, switch + arc / picker / value + stepper / field | form, accessory | migrated |
| `UKFormActionRow` | title in an ink, glyph or arc | form, `UKRowButton` | migrated |
| `UKFormLinkRow`, `UKRowLabelView`, `UKClimateToggleRowView`, `UKPredictiveToggleRow` (climate) | glyph, title, subtitle, value, check, switch | form | migrated |
| `UKGroupedRowButton`, `UKPersonRow` (Your Summary profile) | glyph + title + value + chevron; avatar + name + Home / Away | module, 44 pt | migrated |
| `UKSetupStatusRow`, `UKLocationStatusRow` | title, value in an ink | module card | migrated |
| `UKRoomsActionRow` (Custom Lights) | action glyph + title | module, `UKRowButton` | migrated |
| `UKRecipeFactRow`, `UKRecipeTextRow`, `UKRecipeLinkRow`, `UKIngredientRow` | glyph, label, value; text; link; mark + title + chips | module, sheet | migrated |
| `UKTodoPickerRow`, `UKTodoLabeledRow`, `UKTodoButtonRow` (todo forms) | title + chosen option + chevrons (menu tap target); title + control; ink title + glyph | grouped | migrated |
| `UKLabeledSwitchRow` (recipe filter), `UKVacuumSettingRow` (vacuum sheet) | glyph, title, switch / menu | form / module | migrated |

### Left, and why

- **Not list rows:** `UKSetupPointRow` and `UKRecipeStepRow` (numbered or bulleted paragraphs with their own type scale), `UKWeatherDayRow` and the weather hour cells (table columns), `UKSprinklerPillsRow` and `UKSprinklerDayPickerRow` (pill grids), `UKRemoteTransportRow` (transport buttons), `UKTodoSpinnerRow`.
- **Different controls:** `UKFlyoutRow` (rail item with selection pill), `UKLoginRowView` and the login fields, `UKSelectableOptionRow` and `UKAppIconChoiceCell` (choice cards), `UKCustomLightColorRow` (swatch grid), `UKRemoteLabelRow` family (remote tab buttons), `UKTileCell`.
- **Centred destructive button:** `UKSignOutRow`, `UKSignOutRowView` (centred title with an inline arc): needs a centred title variant.
- **Host cells, no layout of their own:** `UKSettingsCell`, `UKSettingsStackCell`, `UKTodoRowCell`, `UKTodoPlainCell`, `UKInventoryRowCell`, `UKFormRowContentView` / `UKCellContentView`, `UKSprinklerCellContentView` host a row view; they are the list plumbing.
- **Still their own layout, candidates for the next pass:** `UKInventoryRowView` (title, location, chips, quantity stepper), `UKSprinklerRowContent`, `UKBedroomRow`, `UKStageRowView`, `UKScanQuantityRow`, `UKFanTimerLengthRow`, `UKPerformanceRowView`, `UKRemote*Row`.
