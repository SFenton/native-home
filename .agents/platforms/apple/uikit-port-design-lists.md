# UIKit port: lists and sheets components

> **What:** the UIKit counterparts of HassDesign's module lists, settings sections, sheets and loading/empty states, for the feature lanes of the UIKit port. **Read when:** building a screen in `apple/Sources/HassUI/UIKitPort/Features/` that has a list, a sheet, a form, an empty state or a gate. Rules of the port: [uikit-port](uikit-port.md). Code: `apple/Sources/HassUI/UIKitPort/Design/` (and `Common/UKSmoothContentSwap.swift`).

All types are internal to HassUI, prefixed `UK`, `@MainActor`. Inks and surfaces come from `UKDesignInk` / `UKDesignSurface` (dynamic `UIColor`s from the same palette values and Increase Contrast rule as `HassTokens.Ink` / `Surface`); fonts from `UIFont.ukFont(_:weight:monospacedDigit:)` and `UILabel.uk(_:…)` (Dynamic Type, `adjustsFontForContentSizeCategory`). Where a component has a `surface`, `.page` draws the fixed white inks on the module tint, `.sheet` the sheet's adaptive inks on the sheet cell (`UKContext.surface`).

## Module look

| SwiftUI | UIKit |
|---|---|
| `.module(_:cornerRadius:)` | `UKModuleView(.thin / .dense, cornerRadius:, surface:)`, `UKModuleView.wrapping(view, insets:)` |
| `ModuleRow` | `UKModuleRowView(UKModuleRowContent("Title", subtitle:, symbol:, glyph:, subtitleInk:, glyphOpacity:, subtitleIsValue:, showsChevron:), accessory: UIView?, surface:)` |
| `Button { ModuleRow }.buttonStyle(ModuleRowButtonStyle())` | `UKModuleRowButton(row) { action }` (pressed highlight, one button element "Title, subtitle") |
| `ModuleList { rows }` | `UKModuleListView(.thin, hasGlyphs:, surface:, rows: [UIView])` (stack of rows on one card, hairlines inset to the text) |
| `ModuleToggleRow` | `UKModuleToggleRow("Title", subtitle:, symbol:, glyph:, isOn:, hint:, surface:) { flip }`, `setOn(_:)` |
| `ModuleRowBackground` + `moduleRowSeparator` + system `List` | `UKModuleRowBackgroundView` inside the feature's own collection cell (`UKTodoRowCell`, `UKInventoryRowCell`) |
| `PendingValueBar` | `UKPendingValueBar` (used by the row when `valuesPending`) |

```swift
// A short list inside a scrolling page
let list = UKModuleListView(rows: [
    UKModuleRowButton(UKModuleRowView(.init("Room Thermostats", subtitle: "View each room's temperature.", symbol: "house", showsChevron: true))) { open() },
    UKModuleToggleRow("Automatic Cleaning", symbol: "sparkles", isOn: model.auto, hint: "Turns automatic cleaning on or off.") { model.setAuto(!model.auto) },
])
```

Bind live values the port's way: put a label or capsule in `accessory`, and bind that view to its `EntityBox` with a `UKObservationBag`; never rebuild the list for a state change. `row.update(content, accessory:)` changes a row in place (colours cross-fade over the state token).

### Long or live lists

A long or live list is its own `UICollectionView` with self-sizing cells and a diffable data source keyed by id; the cell's background is `UKModuleRowBackgroundView` (the density's tint, 26 pt first/last corners). `UKTodoRowCell` and `UKInventoryRowCell` are the two in use. The generic `UKModuleListViewController` was removed on 2026-11-03 (no caller in any target, never tested); rebuild it from those cells if a third list needs it.

