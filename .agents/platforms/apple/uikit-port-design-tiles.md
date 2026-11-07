# UIKit port: the tiles slice of HassDesign

> **What:** the UIKit counterparts of the HassDesign tile library (`apple/Sources/HassUI/UIKitPort/Design/`), for the feature lanes that build screens on them. **Read when:** a screen needs a tile, chip rail, status pill, grid, ticker, spinner or image card in the UIKit port. Rules of the port: [uikit-port](uikit-port.md).

## Conventions

- Every view is a `@MainActor` `UIView`/`UIControl` subclass prefixed `UK`, drawn by hand (`layoutSubviews`/`sizeThatFits`), no Auto Layout inside. A parent measures a child with `sizeThatFits(CGSize(width:, height: .greatestFiniteMagnitude))` or, for the types that conform, `UKGridMeasuring.gridHeight(forWidth:)`.
- **Binding.** The views take plain values. Bind one to an entity with `UKObservationBag`: read the `EntityBox` inside `observe` and call `configure`/`update` with the result. A reused cell keeps a bag (`UKTileCell.bag`), `removeAll()` in `prepareForReuse` (the cell does it), and passes `animated: false` when it takes another item's state.
- **State changes cross-fade** (0.6 s, 0.2 s under Reduce Motion) once the view is on screen; the first configure never animates. A level (brightness, progress) glides on the quick ease-out.
- **Environment.** What SwiftUI reads from `@Environment` is `UKTileEnvironment` (surface, finish, layout, title lines, single-line subtitle, valuesPending), set per tile or per grid: `UKTileEnvironment(context:)` takes the surface and `valuesPending` from a `UKContext`. Reduce Transparency, Increase Contrast, Reduce Motion and Dynamic Type are read live and observed.
- Colours: `UIColor.token(Color)` for HassDesign tokens; `UKInk` has the dynamic ones rebuilt for UIKit (`primary`, `secondary`, `sheetCell`, `separator`, `secondaryInSheet`, `moduleThin/Dense`, `timer`, `danger`, `warning`, `action`). Fonts: `UKFont.preferred(style, weight:, monospacedDigit:, traits:)` and the token fonts (`tileTitle`, `rowTitle`, `bodyEmphasis`, `footnoteEmphasis`, `sectionTitle`). Views rebuild fonts in `ukOnContentSizeChange { }`.
- Haptics: `UKTapFeedback.tap/step/failure/confirmation` (the `TapFeedback` vocabulary). `UKDesign.animationsPaused` is `\.animationsPaused`.

## Components

| SwiftUI | UIKit | Notes |
|---|---|---|
| `GlassTile` | `UKGlassTileView(model:environment:action:)` | `UIControl`. `UKGlassTileModel(title:subtitle:symbol:tint:family:fillRGB:isActive:isUnavailable:isError:kind:wash:progress:progressTint:identifier:spokenValue:announcesFailure:)`. `configure(model, environment:, animated:, action:)`. `setAccessory(view)` for the rail of buttons (a separate accessibility element; moves under the text at AX sizes). Accessibility: label = title, value as `GlassTile`, `.toggleButton`/`.selected`/`.notEnabled` traits, identifier on the control. |
| `GlassTileFace` | `UKGlassTileFaceView` + `UKTileFaceContent` | The drawing. Tiles that handle their own tap wrap it (`UKBrightnessTileView`); a navigation row can host a face. |
| `BrightnessTile` | `UKBrightnessTileView(title:symbol:tint:fillTint:percent:isUnavailable:)` | Set `onPower`, `onBrightness`, `onOpen`, `identifier`; call `update(fillTint:percent:isUnavailable:)` from the observation. Horizontal pan (vertical goes to the scroll view), bubble, lift, selection haptic, VoiceOver adjust/activate, optimistic value with the 4 s timeout: all via `BrightnessInteraction` and the `BrightnessTile` statics. |
| `StatusPill` | `UKStatusPillView(label:value:detail:symbol:tone:surface:)` | `configure(...)`; `valuesPending`. |
| `PendingValueBar` | `UKPendingValueBar` | Used by tiles and pills; breathes with one layer animation. |
| `ChipRail` | `UKChipRailView` | `setChips([UIView])` (any views with `sizeThatFits`); scrolls in compact width, wraps in regular and at AX sizes; `hinge` (window coordinates) stops it 24 pt short of the fold. Identifier `chipRail.scroll`. |
| `FlowLayout` | `UKFlowView(spacing:)` | `setChildren`. `UKFlowSolver` is the arithmetic. |
| `DynamicGridLayout` (few items) | `UKDynamicGridView(configuration:)` | `setItems([UKGridItem(view, span:, isHeader:)])`; `hinge`. Measures every child once per width. `UKGridConfiguration` = `minCellWidth`, `maxColumns`, `spacing`, `equalRowHeights`. |
| `DynamicGridLayout` (long lists) | `UKDynamicGridLayout` + `UKTileCell` | A `UICollectionViewLayout` on the same `DynamicGridMetrics`: columns, spans, headings, equal rows, hinge band. The delegate (`UKDynamicGridLayoutDelegate`) gives spans and heights; measure with a prototype `UKGlassTileFaceView.measuredHeight(content:environment:width:traits:)` (text only), never by self-sizing. `contentInsets` is the SwiftUI `.padding()`. |
| `PageSectionHeader` | `UKPageSectionHeaderView(_:detail:inSheet:)` | Title is a header element. |
| `ImageCard` | `UKImageCardView(title:subtitle:imageURL:fallbackImageURL:placeholderSymbol:accessibilityHint:action:)` | Photo card or AX row; VoiceOver frame is the caption. |
| `RemoteImage` / `CachedImage` | `UKRemoteImageView(url:fallbackURL:placeholderSymbol:)` / `UKCachedImageView` | `ImagePipeline.shared`, memory hit on the first frame, 0.2 s cross-fade for a new image. `onReadyChange` feeds a content gate. |
| `TickerLabel` | `UKTickerLabel(_:textStyle:weight:wraps:truncatesWhenStill:probe:)` | `TickerPlan`/`TickerClock` unchanged; one `CADisplayLink` while it runs. `scrollView.ukPausesTickersWhileScrolling()` is `pausesTickersWhileScrolling()`; `isSectionOnScreen` is `tickerIsOnScreen`. |
| `ArcSpinner` | `UKArcSpinnerView(_ size:label:maxScale:)` | `color` (default `.label`). One rotation animation, in step with the clock. |
| `ArcProgressViewStyle` | `UKArcProgressView(title:size:surface:)` | `fractionCompleted`. |
| `HouseHeartShape` | `UKHouseHeartView` | `color`. |
| `UKColumnView`, `UKColumnScrollView`, `UKInsetView` | n/a | Hand-laid vertical column and its scroll view, for pages of a few dozen items. |

Reused unchanged: `GlassTileKind`, `TileFaceStyle`, `TileFinish`, `TileLayout`, `TileMetrics`, `TileSurface`, `TileAppearance`, `ColorFamily` (+ `Glass`), `ThermostatTileFace` (pass its `family`/`isActive` to a model), `LitTile`, `ChipTint`, `ChipRailMode/Metrics`, `DynamicGridMetrics`, `TickerPlan`, `MotionTokens`, `TimerInk` (`UKInk.timer`).

## Examples

```swift
// A toggle tile bound to a light.
let tile = UKGlassTileView(model: UKGlassTileModel(title: "Kitchen", symbol: "lightbulb", family: .lights, isActive: false))
bag.observe { [weak tile] in
    let light = store.entity("light.demo_kitchen_item_1")
    tile?.configure(UKGlassTileModel(title: "Kitchen", subtitle: light.state == "on" ? "On" : "Off", symbol: "lightbulb",
                                     family: .lights, isActive: light.state == "on", identifier: "room.kitchen.light"),
                    environment: UKTileEnvironment(context: context)) { toggle(light) }
}

// A grid of tiles.
let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: 150, maxColumns: 4, equalRowHeights: true))
grid.setItems(tiles.map { UKGridItem($0) } )          // headings: UKGridItem(heading, isHeader: true)

// A long list: collection view + layout + UKTileCell (see UKGridWorkloadViewController).
let layout = UKDynamicGridLayout(configuration: UKGridConfiguration(minCellWidth: 150, maxColumns: 6))
layout.delegate = self                                  // heights from a prototype face
layout.contentInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
```

## Cost model

A tile is a flat ground layer, an optional level band (clipped to the tile's corners only while partial), and one finish layer whose image (sheen, lit hairline, tint stroke) is drawn once per tile size and shared (`UKTileFinishImage`, a 64-entry cache): scrolling redraws nothing, no live blur, no shadow at rest. A pending bar is one `CABasicAnimation`; a spinner one rotation. Layout is by hand and measuring is text only.

## Differences from the SwiftUI views

See the lane report: right-to-left band direction in the level band, the symbol-replace transition on a tile's glyph uses `setSymbolImage(contentTransition:)`, and a state cross-fade dissolves the whole face (so a subtitle that changes in the same update fades rather than swapping).

## Tile rollout in the UIKit port (uk-tiles, 2026-11-01)

The UIKit app replaces the SwiftUI app, so every tile class and behaviour of the SwiftUI tile rollout (#261, `.agents/patterns/action-tiles.md`, Rollout foundations to Rollout M) is drawn here on `UKGlassTileView`, `UKTileActions` and the shared providers in `HassCore/TileActions` (the same `TileActionSpec` to `TileActionItem` mapping as SwiftUI, `.items`).

**Core behaviours added to the tile**
- **Confirmation.** A disc tap and a body tap that performs the action with a `TileActionItem.confirmation` ask first: an alert (`style .alert`) or an action sheet anchored to the tile (`.dialog`; a popover on iPad), Cancel on the left, the plain confirming button the bold default, destructive only for a loss. The action runs only on confirm and only if it is unchanged (same id, state, verb and question), exactly `GlassTile.confirmed`. Identifiers: `<tile-id>.confirm`, `<tile-id>.cancel`. The old per-screen alerts (`vacation.disable.*`, High AQI, `soloTrip.end.*` for the toggle) are gone.
- **Selection face.** A selection item (`TileSelection`) makes the tile fill when chosen (`isActive`, kind `.selection`) and draws `UKChoiceDiscView`: a 28 pt ring (white 85%) while not chosen, a white disc with the family-fill check or the 1-based order while chosen, scaling with text to 1.5x inside the 44 pt target. Choosing scales the mark in from 50% over `quick`; a changed number rolls; Reduce Motion cross-fades over `stateReduced`. VoiceOver: selected trait, no value, never "switch".
- **Whole label and hint.** An item's own `label` replaces "verb title" ("Turn Off TV"). A body hint is `UKGlassTileModel.bodyHint` (set on navigation tiles that carry a disc, never on the disc); a tile whose one disc is hidden hints that disc's label.
- **Body gestures.** `UKGlassTileModel.useCommandSemantics()` (a button that speaks its value) and `UKGlassTileView.onAdjust` (VoiceOver swipe up and down) are what `tileCommandSemantics` and `tileAdjustable` are.

**Brightness tile.** `UKBrightnessTileView` is a `UKGlassTileView` with a horizontal pan laid over the tile (the disc is excluded from the pan's touches): an action tile with a `power` disc, or with `onOpen` a navigation tile with the same disc left of the chevron and none while unavailable. Disc: `<identifier>.action.power`.

**Where each class is drawn**

| Class | UIKit file |
|---|---|
| power on purifier, humidifier (navigation + power disc), source select, script power (Switch, Streamer), bed side power | `Features/Rooms/UKRoomCards.swift` (`provision`), Media page cards in `UKMediaViewController` |
| room lights power | `UKRoomOverviewViewController.roomTile` (Home overview Lights cards) |
| alarm mode | `UKQuickLinksRootPage.tile` (Security System) |
| lights and switches | `UKRoomsBind.lightTile`, `UKLightGroupTileView`, `UKBrightnessTileView`, Custom Lights |
| sprinkler | `UKSprinklerControllerCard` (tile + Stop Watering disc, then the module of pills) |
| vacuum robots | `UKVacuumsViewController.buildRobots` (start/pause and dock discs, optimistic) |
| Chores links | `UKChoreQuickLinksView` (navigation tile, state line "3 open · 2 overdue") |
| Admin, Auto-Reset, High AQI, Guest Controls, car Doors, power recovery | `UKHouseholdTiles` |
| Vacation Mode, Solo Trip toggle and travelers | `UKVacation.swift` |
| Hot Flash Mode | `UKBedSpecialModesTab` (one disc; the countdown is the state line) |
| fan sheet Power and Lock, grill Keep Warm and Smoke Boost | `UKRoomDeviceSheets.swift` |

`UKRoomCards.provision` lists every `TileActionKind`: a room card that reaches a class it does not draw trips an `assertionFailure` in DEBUG, so a future catalog class cannot silently fall through to a plain tile.
