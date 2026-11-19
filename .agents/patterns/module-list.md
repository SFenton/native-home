# Module list

> **What:** inset lists on the wallpaper (direction G, Controls: Lists). **Read when:** a page shows rows rather than tiles.

- `ModuleList { … }` puts rows on one `.module()` card with hairlines inset to the text (iOS 18+; flush rows on iOS 17). Use `.dense` when a row carries red or orange text.
- `ModuleRow(title, subtitle:, symbol:, glyph:, glyphOpacity:, showsChevron:) { accessory }`: a family-coloured glyph, the title and an optional subtitle (read as one element), then a trailing accessory (a state capsule, a pop-up menu). 52 pt tall, 60 pt with a subtitle; at accessibility sizes the accessory moves under the text.
- A row that does something is a `Button` around the row with `ModuleRowButtonStyle` (pressed highlight; disabled text never fades). Give the button the label, value and hint; hide a decorative accessory from VoiceOver.
- Unavailable rows dim only the glyph (`glyphOpacity: 0.5`), like tiles.
- Sheets use the system `Form` where they can. A sheet that can't be a `Form` (a map, a bottom section bar) can use the list: under `modalChrome()` (`tileSurface == .sheet`) it draws on the sheet cell colour instead of a module.
- In a sheet the list and rows follow the sheet's appearance: `Surface.sheetCell` ground (white in light), `Ink.primary` title, `Surface.secondaryInSheet` subtitle and chevron, `Surface.separator` hairlines, and a `Ink.primary` 10% press highlight. On a page they are the fixed white-on-module look. `ModuleRow(glyph:)` is optional: nil draws the row's own secondary ink for the surface it is on, so never pass `Surface.secondaryOnModule` from a view that can appear in a sheet.
- A lazy page whose rows swipe uses `SwipeActionRow` ([swipe-row](swipe-row.md)) with `ModuleRowBackground` behind it (Chores todo lists, 2026-10-27). A page whose rows need the system swipe actions on every OS (they need a `List` before iOS 27) is a `List`: each row draws its share of the module with `.listRowBackground(ModuleRowBackground(density, isFirst:, isLast:))` and its hairline with `.moduleRowSeparator(isFirst:)` over `.listRowSeparator(.hidden)` (Chores todo lists, 2026-10-16; Inventory uses it with `.dense` and `selected:` for the split pane's wash).
- **In a sheet (2026-10-17, Your Summary):** `ModuleRowBackground` and the Inventory row's card draw the sheet cell colour when `tileSurface` is `.sheet`, and rows take their secondary ink from `TileSurface.secondaryInk` (the module's fixed light ink on a page, the sheet's adaptive ink in a sheet), so `TodoListSection` and `InventoryRow` serve a page and a sheet alike. Never hard-code `Surface.secondaryOnModule` in a row that can appear in a sheet.
- `hasGlyphs: false` starts hairlines at the 16 pt margin for rows of text alone (recipe steps and facts). A feature row that can't be a `ModuleRow` (a tinted title) uses `ModuleRowMetrics` so it lines up with the hairlines.
- Users: Security's Doors and car lists, Climate's Thermostat Hub and Advanced Controls, Chores todo lists (and the Your Summary sheet's Overdue and Upcoming tabs), the Vacation checklist, Food link rows and recipe sheet lists, the Vacuums Auto-Clean list and vacuum sheet lists, Custom Lights' Front Yard list and light sheet colour group, Sprinklers' controller cards.

- Rows that leave, and the card corners when its first or last row does: [list-row-removal](list-row-removal.md).

## Switch rows

A row whose control is a switch is a `ModuleToggleRow` (`HassDesign/ModuleToggleRow.swift`), not a `ModuleRow` with a `Toggle` accessory: the whole 52 or 60 pt row flips the switch (the system switch alone is 51 x 31), and VoiceOver gets one switch element named by the title (an `accessibilityRepresentation` of `ActionToggle`, with the hint) instead of a text element and a second stop for the switch. Pass the state to show and an action that asks for the opposite; the controller stays the source of truth. Used by the Vacuums auto-clean rows and Custom Lights' manual control.

- **Owned files** (also in `contracts/patterns.json`): `ModuleRowParts.swift`.

- **UIKit port (2026-11-01):** every list row is the one `UKRowView` ([rows](rows.md)); `UKModuleRowView` is its module style.

## Rows in a stack need a height

- A module list is a `UIStackView`, so every row has an Auto Layout height.
- A row that only measures by width (`UKGridMeasuring`) goes through `ukStackRow(_:)`, which hosts it in `UKMeasuredView`.
- `UKMeasuredView` is the one mechanism; add no other. A bare row is 0 pt tall or a hairline and draws over its neighbours.
- A fitting container calls `ukPrepareMeasuredViews(in:width:)`, lays out once at its width, then fits once.
- A row's padding lives in its constraints, set when its kind changes, not in `layoutSubviews`: a fit before layout counts it.
- A row in a module list never draws its own fill, corners or hairline; the list draws one group. A hairline takes its leading and trailing insets from the row above it.
- A row declares its hairline insets through `UKSeparatorInsetDeclaring` (`UKSeparatorInsets`); a row that declares nothing keeps the list's own inset (the scaled text inset, or 16 pt without glyphs) and a hairline flush to the trailing edge, so the other call sites do not move. Only the settings rows declare ([settings-section](settings-section.md#settings-rows-in-a-module-list)).
- A settings link in a module-list section is a row of the group (`UKSettingsStackCell.isListRow`): clear fill, no corners, no hairline of its own, with its padding, content insets and press wash. In a plain section it keeps its card. The list's clipping rounds the wash on the first and last rows.
