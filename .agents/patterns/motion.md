# Motion

> **What:** the shared components that apply the app-wide motion rules. **Read when:** you add any animation, navigation path, sheet, loading state or transition. The rules and their reasons live in [design/motion.md](../design/motion.md). Read that first.

Status: built 2026-10-18 on `claude/motion-system` (see PROGRESS.md). The sign-in lane (`claude/signin-motion`) builds the intro and the arrival on top of `MotionPolicy`, `.arrivalMotion` and `MotionTokens`.

## Canonical components

| Component | Where | Does |
|---|---|---|
| `MotionTokens` | `HassDesign/Motion/MotionTokens.swift` | The only animation values: `quick`, `state` (+ `stateReduced`), `standard`, `segment`, `contentFade`, `emphasized`, `arrivalStagger` (+ `arrival`, `reducedMoment`). Call sites never write a duration. |
| `.stateColorTransition(value:)` | `HassDesign/Motion/StateColorTransition.swift` | The only way a state-driven background, fill, tint, rim or ink colour animates: `MotionTokens.state`, scoped to the colour layer, Reduce Motion aware. Records itself in `MotionAudit` (debug and test) so tests can prove each component uses it. Every component and its status: [design/motion-components.md](../design/motion-components.md). |
| `quickTransition(_:value:)`, `stateColor`, `stateForeground`, `MotionAudit` | `HassDesign/Motion/StateColorTransition.swift` | The scoped forms of the same helper (an opacity on `quick`; ink; closure-scoped colour) and the debug-and-test registry the per-component tests read (`MotionAudit.capture`) |
| `MotionGallery` | `HassUI/Features/Gallery/MotionGallery.swift` | Every component with a state, with Toggle state and Toggle all, for visual checks and UX tests |
| `motionSafeAnimation(_:reduced:value:)` | `HassDesign/MotionSafeAnimation.swift` (exists) | Every implicit animation; Reduce Motion aware |
| `MotionPolicy` | `HassUI/App/Motion/MotionPolicy.swift` (`@Observable`, one per session, in the environment) | Remembers which moments have played this session (`hasPlayed(.signInArrival)`, `markPlayed`), and resets on sign-out. Exposes `reduceMotion`. Wraps measurement (`measure(.push(page))`). |
| `.arrivalMotion(_:index:)` | `HassUI/App/Motion/ArrivalMotion.swift` | Plays a moment's entrance for one view (fade and rise, staggered by `index`), only if the moment hasn't played this session and Reduce Motion is off. Otherwise it renders at once, or cross-fades under Reduce Motion. |
| `.zoomSource(id:in:)` / `.zoomDestination(id:in:)` | `HassUI/App/Motion/ZoomTransition.swift` | The iOS 18 zoom (`matchedTransitionSource` and `navigationTransition(.zoom)`); does nothing on iOS 17 |
| `NavigationProbe` (`.measuresNavigation(_:page:)`), `NextFrame` | `HassDesign/Motion/` | A zero-size view controller in a page, sheet or zoom destination; UIKit's appearance callbacks give the first frame and the end of the system transition. Applied by `pageChrome`, `hassSheet` and `zoomDestination`. |
| `.measuresMotion(_:value:duration:)` | `HassDesign/Motion/MotionChangeProbe.swift` | Beside every `motionSafeAnimation` that a person or a live update triggers (an insert, a swap, a badge): the `LayoutChange` signpost from the value changing to the animation settling. Perf: `LayoutChangePerformanceTests`, `tools/ios_motionperf.sh`. |
| `ScrollsToTop` (`.scrollsToTop(whenRequested:)`) | `HassUI/App/Shell/ScrollToTop.swift` | The second re-tap of the selected tab: the root's main scroll view animates to its top (`ShellNavigator.reselect`) |
| `SessionModels` | `HassUI/App/SessionModels.swift` | The Food hub's and the inventory's models for the signed-in session, so a revisit finds results loaded and its content gate opens at once |
| `UKStackMotion` (`UKStackTransition`, `UKStackInteraction`) | `HassUI/UIKitPort/App/Shell/UKStackMotion.swift` | UIKit port: push and pop on the single-page layouts, the column motion with one column ([design/single-page-motion.md](../design/single-page-motion.md)). Returned from the section stack's navigation delegate; owns the edge swipe back. Reduce Motion: a 0.2 s cross-fade |
| `NavigationTelemetry` | `HassUI/Diagnostics/NavigationTelemetry.swift` | Signposts for `TabSwitch`, `Push`, `Pop`, `SheetPresent`, `SheetDismiss`, `ZoomOpen`, `ZoomClose`, plus per-transition run-loop cost, feeding Settings → Performance |
| `ContentGate` | `HassDesign/Loading/ContentGate.swift` (exists); UIKit `UKContentGateView` and `UKContentGateDriver` | The only content entrance for network-backed pages, and (owner, 2026-11-05) the sheet reveal a modal opts into with `UKHassModalOptions.reveal` ([sheet-reveal](../design/sheet-reveal.md)) |
| `ArcSpinner` | `HassDesign/ArcSpinner.swift` (exists) | The only spinner |

## Rules for call sites
- **No raw animation values or transitions:**
  - no `.animation(_:)` without a value;
  - no `withAnimation(.easeInOut(duration:))` with literal timings;
  - no `.transition(...)` on navigation content.

  Use `MotionTokens` with `motionSafeAnimation` or `withAnimation(MotionTokens.x)`.
- **No entrance animations in `onAppear`** for content that came from `EntityStore` or a cache.
- **A pressed control answers where it was pressed** ([design/motion.md §5](../design/motion.md)): `PrimaryButton(isBusy:busyTitle:)` swaps its label for an inline `ArcSpinner` and a present-tense title ("Starting", "Applying", "Scheduling"), keeps its colour and width and ignores presses (VoiceOver: title, value "Busy"); a toolbar check uses `SheetConfirmItem(isBusy:)`; a Sign Out row uses `SignOutRow`; a retry uses `StateMessage(actionBusyTitle:)`. Do not just `.disabled` a control while its call is out.
- Rows and form sections that leave: [list-row-removal](list-row-removal.md).
- **Tab switches and sheet-tab switches are cuts.**
- **Background colour changes always animate,** through `.stateColorTransition(value:)`. A new component, or a new state on one, gets a row in [design/motion-components.md](../design/motion-components.md), a unit test and a gallery entry in the same PR.
- **Zoom only for tiles that are what they open** ([design/motion.md §4.3](../design/motion.md)).
- **Every new navigation surface** gets its `NavigationTelemetry` interval and a row in `NavigationPerformanceTests`.

## Lint
`tools/lint_motion.sh` (a per-change check in the [test tiers](../testing/apple/README.md#test-tiers) table; also run by `tools/apple_coverage.sh`) flags:
- `.animation(` without `value:`;
- literal `duration:` outside `MotionTokens.swift`;
- `.transition(` in `HassUI/App` and `HassUI/Features` (allowed only for in-place view swaps, listed in the script's allowlist with a reason);
- `repeatForever` outside `ArcSpinner` and the pending pulse.

## Tests
- **Unit:** `MotionPolicyTests` (session memory, reset on sign-out, Reduce Motion paths) and `ArrivalMotionTests` (plays once, never on a second appearance, instant under the "already played" flag).
- **UX and accessibility** (iPhone, iPhone Duo, iPad), through the gallery or app:
  - a tab switch shows the destination's content in the first frame, with no opacity ramp;
  - the second Home appearance has no stagger;
  - the push and sheet still work with Reduce Motion on;
  - the zoom works on iOS 18 simulators and falls back on 17.
- **Perf:** `NavigationPerformanceTests` and `tools/ios_navperf.sh`, with budgets in [design/motion.md §10](../design/motion.md).

## Tabs, pages and revisits (as built)
- The tab bar is the system `TabView` (no custom bar). A switch is a cut: `.transaction(value: selection) { $0.animation = nil }` keeps any animation off the content. The selection binding's setter also runs for a tap on the selected tab, which is how `ShellNavigator.tabTapped` sees the re-tap: first tap pops to the root, the next scrolls the root to its top.
- Each tab keeps its own path (`ShellNavigator.paths`) and scroll position (the system keeps each tab's stack mounted).
- **Entrance animations audited (2026-10-18): none to remove.** No tab root, pushed page or `hassSheet` content fades or rises in `onAppear`; the only entrances are `ContentGate` (network-backed pages) and `CachedImage`'s 0.2 s photo fade. Revisits were the problem, not entrances: the Food hub and the inventory pages built their models in view `@State`, so every push reloaded them and ran the gate's spinner again. They now come from `SessionModels`.

## The sign-in lane (`claude/signin-and-launch-motion`)
It owns Login, the intro and the arrival choreography and wrote its own first versions of `Moment`, `MotionPolicy`, `MotionTokens`, `ArrivalKind` and `.arrivalMotion(_:kind:index:)` (driven by its `HomeArrival` environment state). This lane's versions are supersets so its call sites compile unchanged: `Moment` and `ArrivalKind` are its files verbatim, `MotionPolicy()` keeps its no-argument init and `hasPlayed` / `markPlayed` / `reset` / `reduceMotion`, `MotionTokens` carries its `Intro`, `Arrival`, `crossFade` and `press` names beside the spec's, and `arrivalMotion` takes its `(moment, kind, index)` signature. When both branches are merged:
- keep this lane's `MotionPolicy.swift` and `MotionTokens.swift` (`state` is 0.6 s now, not its draft 0.25 s);
- keep the sign-in lane's `ArrivalMotion.swift`, since `HomeArrival` is what actually choreographs Home, and delete this lane's policy-driven one and `ArrivalMotionTests` (`ArrivalMotionPlan`);
- `AppSession.motion` and the `RootView` environment line exist in both; keep one.

## Departures
- **Single-page push and pop (owner, 2026-11-02).** The UIKit port's section stacks replace the system push with `UKStackMotion` (both pages a full width on `standard`, no dim, shadow or fade, one still wallpaper) and drive the swipe back themselves; "no custom transition on navigation" above stands everywhere else. Record: [design/single-page-motion.md](../design/single-page-motion.md). Tab switches stay a cut.
- **Zoom corner radius.** The design says 26 pt, which is the module radius. Tiles are 22 pt (`HassTokens.Radius.tile`; 28 pt only in the web-port finish), so a 26 pt source clipped the tile wrong. `zoomSource(id:in:cornerRadius:)` defaults to 26 pt and room tiles pass 22 pt.
- **Where the zoom is applied (decided 2026-10-24).** Only where a tile is the thing it opens, never inside a sheet (owner, 2026-10-22). The camera card on Home and Security is a `zoomSource` (`CameraGrid.zoomNamespace`) and `CameraViewer` is the `zoomDestination` of the sheet it opens (the viewer stays a content-fitted sheet; below iOS 18 it is the plain sheet, recorded as `SheetPresent`). Home has no room tile, the overview sheets' room tiles are inside a sheet, and Quick Links rows are list rows, so none zoom. The destination's probe wins over the sheet's (`NavigationProbe` `resolved`), so the open is recorded as `ZoomOpen`; `NavigationPerformanceTests.testZoomOpenAndCloseStaysWithinBudget` measures it. **Quick Links (owner, 2026-10-26: "it doesn't 'zoom in' to the modal like clicking a camera does"):** its sheet grows out of the header button. `ShellSheets` owns the namespace and hands it down (`\.quickLinksZoom`), the bar item is the source (`ToolbarContent.matchedTransitionSource`, iOS 26) and the sheet the destination. iOS 18 to 25 keep the rise: a bar item cannot be a source there.
- **`TileColorKey` carries `hasLevel`, not the level.** The brief put `level` in the key. A numeric level inside the 0.6 s colour fade would make a dragged brightness lag the finger, so a band appearing or vanishing is a colour change and its width is progress, kept on `quick` by `BrightnessTile`.
- **`Pop` is recorded for the UIKit section stacks** (`UKSectionNavigationController.willShow`, through the transition coordinator, which the custom animator keeps). **`Pop` and `ZoomClose` are not recorded yet** in the SwiftUI path. The probe times a page's way in (`Push`, `ZoomOpen`, `SheetPresent`) and a sheet's way out (`SheetDismiss`), but UIKit's disappearance for a popped page does not reach it (`viewWillDisappear` and SwiftUI's `onDisappear` were both tried), so `NavigationPerformanceTests` requires them only when present. The next step is a `UINavigationController` hook that does not replace SwiftUI's delegate.
- **Navigation "intent" is the page being built** for pushes, sheets and zooms (the page cannot see the tap that caused it); tab switches time the real tap.
- **Done (2026-10-24): `ProfileButton` badge opacity.** The badge fades in and out with `quick` (`ShellHeader.swift`).
- **Controller-bound components are not in the Motion gallery** (`ThermostatHubPill`, `ThermostatDial` in the page, `GroceryAction`, `InventoryRow`, `EcoOptionDetail`, `WeatherPagedCarousel`, `VacuumRoomsTab` cards, the area editor's tools, the power key): they need a store or controller the gallery page does not own. Their audit tests render them where a fixture exists; the rest are named in `motion-components.md`.
- **The status-chip timing (0.6 s) is the one colour animation over 0.4 s**, per the owner's 2026-10-18 correction; nothing that moves exceeds 0.4 s.

Any further exception (a page that should re-animate on revisit, a custom transition) needs the owner's approval and a line here, and in the design doc §3.

- **Owned files** (also in `contracts/patterns.json`): `AnimationsPaused.swift`, `ArcProgressViewStyle.swift`, `PrimaryButton.swift`, `PrimaryButtonStyle.swift`, `ReduceMotionOverride.swift`, `SmoothContentSwap.swift`, `ListUpdateCause.swift`, `ListUpdateLedger.swift`, `ListUpdateTransition.swift` (the rules of [list-row-removal](list-row-removal.md): when a diffable list animates a row that leaves).
