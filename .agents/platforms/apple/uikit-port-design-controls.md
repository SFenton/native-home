# UIKit port: design controls

> **What:** the UIKit counterparts of the HassDesign / HassUI controls in `apple/Sources/HassUI/UIKitPort/Design/` (Controls lane), and how feature lanes use them. **Read when:** building a UIKit screen that needs a button, bar, segmented control, pager, dial, slider, date field or animation. Rules for the whole port: [uikit-port](uikit-port.md).

Every view is created with its data and callbacks and **holds the value it is shown**. To follow an entity, bind with `UKObservationBag` and write into the view; never bind the view to the whole store.

```swift
private let bag = UKObservationBag()
let box = context.store.entity("climate.demo_ext_40")          // an EntityBox
bag.observe { toggle.show(box.state?.state == "on") }            // re-runs only when this box changes
```

## UKMotion (`UKMotion.swift`)

`MotionTokens` as UIKit animations, Reduce Motion aware (the counterpart of `MotionSafeAnimation`). Call sites pick a token, never a duration.

| API | Use |
|---|---|
| `UKMotion.animate(.standard) { … }` | a spring/curve for a UIView change; `reduced:` is the token used under Reduce Motion (default: change applies at once) |
| `UKMotion.stateColor { … }` | a state colour cross-fade, 0.6 s (0.2 s under Reduce Motion) |
| `UKMotion.fade(layer, keyPath: "fillColor", to: cg)` | the same for a `CALayer` property |
| `UKMotion.dissolve(view) { … }` | cross-dissolve of a view's content (a glyph or text colour that follows state) |

Tokens: `.quick` (ease out 0.2), `.state`/`.stateReduced`, `.standard` (smooth spring 0.3), `.segment` (snappy 0.2), `.contentFade`, `.emphasized`, `.arrival`, `.reducedMoment`, `.press`. Springs use `UIView.animate(springDuration:bounce:)`, curves a `UIViewPropertyAnimator`. The extra duration constants (`MotionTokens.segmentDuration` …) were added to HassDesign; the SwiftUI animations are built from them, behaviour unchanged.

`UKFont.preferred(.body, weight: .semibold, monospacedDigit: true)` is `Font.body.weight(.semibold).monospacedDigit()` (keeps the text style, so `adjustsFontForContentSizeCategory` follows Dynamic Type to AX5). `UKGlassView` / `UKNavigationGlassView` are `navigationGlass(in:)` (Liquid Glass on iOS 26, thin material before).

## Buttons and bars

| Type | Port of | Notes |
|---|---|---|
| `UKPrimaryButton("Save", systemImage:, family:, isBusy:, busyTitle:) { }` | `PrimaryButton`, `PrimaryButtonStyle` | 50 pt capsule; `isEnabled` fades 0.4; `isBusy` shows an arc and speaks "Busy"; fill it with constraints |
| `UKFloatingActionBar(actions:, search:)` + `UKFloatingAction`, `UKFloatingSearch` (`@Observable`) | `FloatingActionBar`, `FloatingBarParts` | identifiers `fab.<id>`, `fab.search`, `fab.search.field`, `fab.search.close`; glass pieces share one `UIGlassContainerEffect`; `setActive(_:forActionID:)` updates a filter circle |
| `UKPinnedBarViewController(content:, bar:, scrollView:, edge:, spacing:, barMaterial:)` | `pinnedBar`, `floatingActionBar(_:search:)` | hosts the page, pins the bar to the safe area, adds the bar height to the page's `additionalSafeAreaInsets`; iOS 26: scroll edge interaction and a soft bottom edge |
| `UKModalTabBar(tabs:, label:, title:, symbol:, badge:, selection:, identifier:) { }` | `ModalTabBar`, `BadgedTabSegment(s)` | form follows size class and Dynamic Type exactly as `ModalTabBarStyle.form`; `.inset()` returns it with the modal padding for `UKPinnedBarViewController`; `ModalTabSymbols` is shared as is |
| `UKSegmentedChoice(label:, options:, title:, selection:, identifier:) { }` | `SegmentedChoice` | segmented control, a menu at AX sizes; set `selection` from the model, it shows the device value again after a tap |
| `UKControllerToggle(isOn:) { }`, `UKActionToggle`, `UKControllerStepper`, `UKControllerPicker` | `ControllerControls` | call `show(_:)` with the controller's value; the control reverts to it after reporting intent |

```swift
let bar = UKFloatingActionBar(actions: [UKFloatingAction(id: "add", title: "Add Task", symbol: "plus") { add() }],
                              search: UKFloatingSearch(prompt: "Search Tasks"))
let page = UKPinnedBarViewController(content: listController, bar: bar, scrollView: listController.collectionView)
navigationController?.pushViewController(page, animated: true)
```

## Paging and scrolling

- `UKPageIndicator(page:, pageCount:, label:, identifier:, ink:) { page in … }` — dots, "4 of 12" past 10 pages, adjustable element, two tap zones.
- `UKPagedRowView(itemCount:, perPage:) { index in cellView }` — paging `UIScrollView`; `firstVisible` (get/set) and `onFirstVisibleChange`, `currentPage`, `firstIndex(ofPage:)`. Exposes only the page on screen to VoiceOver, pages with a three-finger swipe, announces "Page 2 of 3". `PagedRowMetrics` is reused.
- `scrollView.ukPagesByViewport()` — `NativePaging`.

## Dial, slider, dates, hinge

- `UKThermostatDial(configuration, size: .modal, surface: .sheet, rejection:) { targets in … }` — `CAShapeLayer` ring, pan handles (64 pt targets, selection haptic), tap on the ring, adjustable handles plus Raise/Lower actions, identifiers `thermostatDial`, `thermostatDial.handle.<h>`, `thermostatDial.readout`. Set `.configuration` when the entity changes and `.rejection` when a commit fails. Reuses `ThermostatDialEditor`, `ThermostatDialGeometry`, `ThermostatDialConfiguration`.
- `UKClimateThermostatDial(context:, entityId:, title:, size:, action:, commitEntityIds:)` — bound to the entity's box, calls `climate.set_temperature`, `UKFailureCaption` under it.
- `UKPercentSliderRow("Brightness", value:, identifier:) { }` — set `.value` and `.isEnabled` from the model.
- `UKScheduleDateFields(fields: [ScheduleDateField], commitDelay:)` — `update(fields:)` with the saved values; compact `UIDatePicker`s on material rows, two columns from 640 pt, flushes a pending pick when it leaves the window (`UnsentPick` reused).
- `UKHinge.frame` (set by the shell) with `UKHingeAvoidingView(child:)` (`avoidsHinge()`) and `UKHingeClearingView(content:)` (`clearsHinge()`); geometry is `HingeAvoidance`.

## Galleries

`FENTON_GALLERY=thermostat-dial | floating-actions | motion` (`Gallery/UKDesignControlsGallery.swift`). `motion` shows `PrimaryButton` and `FloatingActionBar`; other lanes add their cards with `UKMotionGallery.extraCases.append(UKMotionCase(…))`. With `FENTON_UK_EXTRAS=1` it also shows the controls above that have no SwiftUI card (segmented choice, tab bars, page indicator, slider, toggle, paged row, schedule fields).

## Not identical

See the lane report: the system slider shows no step ticks, `DynamicGridLayout`'s even-column hinge rule is not applied to `UKScheduleDateFields`, the bar's search swap uses a spring on hide/show rather than a layout transition, and `UKControlSpinnerView` is a stand-in for the tiles lane's loading arc.
