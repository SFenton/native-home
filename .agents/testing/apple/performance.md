# Performance tests

> **What:** how scroll, navigation, launch and layout-change cost are measured, the budgets, and the rules that follow. Dated measurements and fix write-ups are in the [performance log](../../archive/performance-log.md) (why only). **Read when:** a page stutters, or after changing a page's layout, tiles, images or live-update path.

- **Two tools, two questions.**
  - *What does a surface cost the main thread?* The scroll cost probe, on a simulator (below). It reads CPU instructions and per-run-loop-turn main-thread time, which do not move with other work on the Mac.
  - *Does a frame make its deadline on the phone?* The fast-scroll tests on a physical device (further down). Simulators render with the Mac's compositor, so their hitch ratios and any GPU cost are false.

## Scroll cost (simulator)

The app measures itself (`HassUI/Diagnostics/ScrollCostProbe.swift`, `HassTelemetry/MainThreadCostMeter.swift`). With `FENTON_SCROLLCOST=1` and `FENTON_SCROLLCOST_AUTORUN=<seconds>` it waits for the page to settle, stands still for 8 s (the floor), then moves the front scroll view up and down at 900 pt/s for 8 s, twice, and reports:

| Key | Meaning |
|---|---|
| `minstr` | CPU instructions the process retired, in millions |
| `main_ms` | CPU time the main thread used |
| `over4` `over8` `over16` | run-loop turns whose main-thread CPU time passed 4, 8 and 16 ms; `over8` is a dropped frame at 120 Hz |
| `p95_ms` `worst_ms` | the 95th percentile and the longest turn |
| `deliveries` `changed` `update_ms` | live updates applied meanwhile, and the main-thread time applying them |
| `travelled` | points scrolled, to put runs of different length on one footing |

- **Run it:** `tools/ios_scrollcost.sh [--section gallery|live] [--only "Living Room"] [--env shell] [--compare BASE.tsv]`. It builds the app optimized (`-O`: the Release code path, gallery still in), runs every surface in `tools/scrollcost-surfaces.txt` on one simulator inside a devcap hold, and prints `tools/scrollcost_report.py`'s table. About a minute a surface.
- **Why not an XCUITest swipe.** The first attempt flicked pages with `swipeUp` under `XCTCPUMetric`. Every page read the same 2.6 to 2.9 G instructions, a Grid of 300 tiles included: what it measured was the accessibility snapshot the swipe asks of the app, not the page. The probe's own display link moves the scroll view, and nothing touches the app while it measures.
- **Gallery or live.** `[gallery]` surfaces run on fixtures with no connection, so the number is the page alone. `[live]` surfaces sign in with the token and open a page with `FENTON_SCROLLCOST_OPEN=<dashboard path>`: live entity updates and camera streams are in the number, which is how the owner's phone behaves. Compare like with like. Whole-process `minstr` is not comparable between live runs (the camera streams alone retire about 20 G instructions in 8 s on any page); compare `main_ms`, `over8`, `p95_ms` and `update_ms`.
- **Tile finish A/B** (`--section finish`, not part of `all`): the 300-tile grid with each `TileFinish` (`FENTON_TILE_FINISH=solid|tintedGlass`, tinted glass is the shipped default), and variants with a layer left out (`FENTON_TILE_FINISH_OMIT=sheen,rim`, Debug only). Run it after changing a finish token or layer. Numbers: direction-g.md, Tile finish.
- **Tests:** `Apps/iOSUITests/ScrollSurfacesPerformanceTests.swift` holds the surfaces that were slow to a budget (`TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1`, and the token for the `testLive*` ones). Budgets, from the post-fix numbers: p95 turn 6 ms on fixtures and 3.5 ms live, no turn over 8 ms, none over 16 ms in the warm run, 25 ms of live-update work and 100 ms of main-thread time for a standing-still live page in 8 s.
- **Unit tests:** `MainThreadCostMeterTests` (the report), `HomeColumnsTests` (the scroll-invariant container), `EntityDeliveryOffMainTests` (deliveries cross to the main actor in order, a burst is diffed once).

## Navigation (simulator and device)

Tab switches, pushes, pops, sheets and zooms are timed by the app itself, the way scrolling is ([motion](../../design/motion.md) §10, [telemetry](../../patterns/telemetry.md)).

- **What is measured.** `NavigationMeasurement` (HassTelemetry) times one transition from its intent to its first frame and to settled, and meters the main thread meanwhile (`MainThreadCostMeter`: the transition's p95 and longest run-loop turn). Names: `TabSwitch`, `Push`, `Pop`, `SheetPresent`, `SheetDismiss`, `ZoomOpen`, `ZoomClose`.
  - **Tab switch:** the intent is the tab tap (`MotionPolicy.measureCut`); first frame and settled are the next display tick, because a cut has no animation.
  - **Push, pop, sheet, zoom:** `measuresNavigation` (`pageChrome`, `hassSheet`, `zoomDestination`) puts a zero-size view controller in the page. The page being built is the intent; `viewWillAppear` plus the next display tick is the first frame; `viewDidAppear` is settled (and the same on the way out). A non-animated appearance (cold launch, restored path, tab becoming visible) is not a transition and records nothing.
- **In the app:** Settings → Performance → Navigation shows p50, p95 and the worst turn per surface. Export Telemetry carries them as `phases` (`Push.settled@Room`) next to the raw records.
- **Simulator budgets** (CPU only; simulator hitch ratios and GPU cost are false): each transition's p95 run-loop turn at most 8 ms, none over 16 ms; a tab tap to its first frame at most 50 ms (p95); push and sheet tap to settled at most 600 ms.
- **Run it:** `tools/ios_navperf.sh [--env shell] [--only iphone|duo|ipad] [--test testTabCycleStaysWithinBudget]`. It builds once under a `build` hold, then runs `NavigationPerformanceTests` on the iPhone, iPhone Duo and iPad simulators, each in its own devcap hold, and prints one row per surface (p50 and p95 for first frame and settled, p95 and worst turn). Raw rows: `apple/.build/navperf-<label>.tsv`.
- **The tests** (`Apps/iOSUITests/NavigationPerformanceTests.swift`), skipped unless `TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1`:
  - tab cycle (each tab x 3) and Home revisit x 10 (live, navigation only);
  - push and pop a room page x 10 and sheet open and close x 10 (the Rooms gallery: fixtures, no house);
  - zoom open and close a Home camera card into its viewer x 10 (live; the sheet before iOS 18).

  The app reports through `diagnostics.navperf` (`FENTON_NAVPERF=1`, `NavigationPerfProbe`): a test posts `com.sfenton.home.navperf.reset` before, and `...report` after, so the report itself never disturbs a measurement.
- **Device** (`testDeviceNavigationTransitionMetrics`, `testDeviceZoomTransitionMetrics`): `XCTOSSignpostMetric.navigationTransitionMetric` plus the app's own `Push`, `Pop`, `SheetPresent`, `SheetDismiss`, `ZoomOpen` and `ZoomClose` signposts, ten iterations. They skip on a simulator and need the owner's say-so before anyone runs them on the phone: `tools/ios_perf.sh --device <UDID> --suite nav` (in a devcap device hold). Target: hitch ratio under 5 ms/s.
- **First numbers (2026-10-18, simulators on a Mac running about 400 load average, so wall times are inflated; the turn costs are CPU and are not).** iPhone 17 Pro / iPhone Duo / iPad Pro 11 (iOS 27), live house for the tab and zoom rows, Rooms gallery for push and sheet. First frame and settled are p50 / p95 in ms; turn is the transition's p95 and worst run-loop turn.

  | Surface | iPhone | iPhone Duo | iPad |
  |---|---|---|---|
  | Tab revisit, first frame | 67 / 71 | 3 / 89 | (flyout) |
  | Tab cycle, first frame (turn p95 / worst) | 94 / 220 (15.6) | 78 / 116 (9.2) | (flyout) |
  | Tab first visit, first frame | 304 / 481 | 325 / 468 | (flyout) |
  | Push room, first frame / settled | 89 / 201, 563 / 673 | 93 / 251, 580 / 736 | 78 / 218, 570 / 712 |
  | Push turn p95 / worst | 0.8 / 10.5 | 0.6 / 3.2 | 0.9 / 11.6 |
  | Sheet present, settled | 610 / 817 | 626 / 903 | 600 / 726 |
  | Sheet dismiss turn p95 / worst | 0.3 / 23.3 | 0.4 / 22.8 | 0.2 / 15.0 |
  | Zoom open, settled | 960 / 1002 (first run) | 944 / 974 | 958 / 988 |

  Against the budgets: transitions cost the main thread very little (turn p95 under 1.3 ms everywhere), but a sheet dismissal's longest turn (22 to 23 ms on the phones) and one tab-revisit turn (15.6 ms iPhone) break the 16 ms rule, and push and sheet "settled" p95 sit above 600 ms (the system animations are about 0.5 s plus the build). `Pop` and `ZoomClose` are not recorded yet (see `patterns/motion.md`, Departures).
- **Settings push/pop (single-page, 2026-11-03).** `testSettingsPushAndPopStaysWithinBudget`, iPhone: p95 turn 3.6 ms (base 66ae0c9f system push 2.9), longest turn 73 to 77 ms (base 139). Most of the push's p95 is a page build, not the slide: `UKStackTransition` lays the destination out before the first frame, and Settings → Performance reads its report after `viewDidAppear`. The longest turn is the page's forty-row layout, held to 100 ms for this scenario (the base broke 16 ms too).
- **Adding a navigation surface:** give it a `measuresNavigation` (or a `MotionPolicy.measure`) and a row in `NavigationPerformanceTests` ([patterns/motion.md](../../patterns/motion.md)).
## Launch and sign-in

What the launch intro, a signed-in relaunch and the sign-in arrival cost, measured the way scrolling is: a simulator's hitch ratio is false, so the number is the main thread's CPU time per run-loop turn (`MainThreadCostMeter`) plus the signpost intervals the run recorded. Motion design: [direction G, Launch and sign-in motion](../../design/direction-g.md#launch-and-sign-in-motion).

**Signposts** (`com.sfenton.home` / `Performance`, begun in one place and ended in another with `Telemetry.beginTracked` / `endTracked`; also records in the in-app log and Settings → Performance):

| Name | From | To |
|---|---|---|
| `Launch` | the `App` initializer | the first frame (`RootView`, after one turn) |
| `SnapshotShown` | the `App` initializer | the tabs' first appearance with the disk snapshot in the store (a signed-in relaunch; cancelled when signed out) |
| `SignIn` | Sign In pressed | Home Assistant hands back tokens |
| `Intro` | the intro's first animation | the form in place (≈1.2 s) |
| `Arrival` | tokens in hand | the end of the arrival animation (0.9 s of motion plus the build of Home) |
| `Reconnect` | the socket starts or fails | it is live again (cancelled when closed on purpose) |
| `HouseConfigRead` | the session start reads the cached house document from disk (main thread, synchronous) | the document is decoded (`hit`) or absent (`miss`) |

**Probe and script.** With `FENTON_LAUNCHCOST=1` the app measures three phases by itself (`LaunchCostProbe`) and appends `LAUNCHCOST<TAB>phase<TAB>key=value…` to `FENTON_LAUNCHCOST_FILE`: `intro` (the two seconds after the first frame of a signed-out launch), `snapshot` (the same, signed in), and `arrival` (the animation, after `arrival-build`: tokens to Home built behind the sign-in layer, which is one long turn). `FENTON_AUTOSIGNIN=1` signs in with the prefilled credentials so no test drives the app. **Run it:** `tools/ios_launchperf.sh --env shell [--only intro,arrival,snapshot] [--no-budget]` (simulator only, inside devcap holds; builds `-O` like the scroll cost run; `apple/.build/launchperf-<label>.tsv`, table by `tools/launchcost_report.py`, which exits 1 on a missed budget). Never run it on a phone without the owner's say-so.

**Tests** (`Apps/iOSUITests/LaunchPerformanceTests.swift`; cost tests need `TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1`, so the normal journeys never run them):
- Metrics (baselines per device in Xcode): `XCTApplicationLaunchMetric` plus the `Launch` and `SnapshotShown` interval metrics (`XCTOSSignpostMetric`) for a cold signed-out launch, a launch with the intro off, and a warm signed-in relaunch.
- Budgets read from the probe's label (`diagnostics.launchcost`): intro (and the Reduce Motion intro), warm relaunch to the snapshot, and the arrival.
- Hitch ratios (`XCTHitchMetric`, iOS 26) for the intro and the arrival run **on a physical device only** and skip on a simulator, like `FastScrollPerformanceTests`; the target is under 5 ms/s. Device runs need the owner's say-so.
- Unit: `TrackedIntervalsTests`, `LaunchCostProbeTests`, `ReconnectingPolicyTests`, `RememberedAccountTests`; hosted: `LoginTests` (model, screen, flows, root choreography).

**Budgets (simulator, from design/motion.md section 10).** p95 run-loop turn ≤ 8 ms and no turn over 16 ms in any phase; `Intro` ≤ 1500 ms; `SnapshotShown` ≤ 400 ms; `Arrival` ≤ 1000 ms. The measured baselines and today's misses (Arrival over budget on Home's first layout) are in the [performance log](../../archive/performance-log.md). Hitch metrics are device-only and are written but not run.

## What only a phone can settle

Run these on the iPhone 18 Pro (nothing here has been run on it):

```bash
# 1. The fix, on the real house, release build: scroll cost per live page (the whole loop is one devcap device hold).
tools/ios_scrollcost.sh --device 00008160-00022D8230914036 --label phone-base
# 2. GPU layers, one at a time. headerFade is the mask under the navigation bar (a full-page offscreen pass while scrolling);
#    backdrop is the blurred house photo. Compare the two runs: p95 and over8 should not move if the layer is free.
tools/ios_scrollcost.sh --device 00008160-00022D8230914036 --label phone-nofade --disable headerFade
tools/ios_scrollcost.sh --device 00008160-00022D8230914036 --label phone-nobackdrop --disable backdrop
python3 tools/scrollcost_report.py apple/.build/scrollcost-phone-nofade.tsv --compare apple/.build/scrollcost-phone-base.tsv
# 3. Hitches the system sees (FastScrollPerformanceTests, below), before and after. Every device run holds the phone through
#    `devcap.py run --device`, so runs queue behind each other.
tools/ios_perf.sh --device 00008160-00022D8230914036 --live --env shell --suite scroll
# 4. The other device-only suites, one .xcresult each (apple/.build/perf-<suite>-<time>.xcresult).
tools/ios_perf.sh --device 00008160-00022D8230914036 --env shell --suite nav     # also launch, motion, ticker, or all
```

`FENTON_PERF_DISABLE` (`HassDesign/PerfSwitches.swift`) only turns a layer off for that launch; a normal launch has everything on.

## Rules

- **No work on the main thread proportional to the number of entities.** A change to one entity costs the main thread one box update ([connection lifecycle](../../platforms/apple/connection-lifecycle.md)).
- **No SwiftUI observer on a scrolling page's offset.** `onScrollGeometryChange` (and `onScrollPhaseChange` with a state write) makes SwiftUI update the page's view graph on every frame, even when the value it reads does not change. Observe the scroll view's `contentOffset` from UIKit (`UIKitScrollOffset`) and write to SwiftUI when a clamped value changes. A/B anything that touches every page with `FENTON_PERF_DISABLE` in one alternating hold before believing a number.
- **No state written from a geometry read that moves with a scroll.** `onGeometryChange` / `GeometryReader` in or around scrolling content that reads `frame(in: .global)` (or any scrolling space) fires every frame; return a value that does not change with the scroll (the size, the horizontal position) or write nothing.
- **A closure given to HAKit runs off the main thread.** Mark it `@Sendable` or build it in a `nonisolated` function.
- **Measure CPU with instructions and run-loop turns, never with an XCUITest swipe or a simulator hitch ratio.**

## Fast-scroll tests (physical device)

- `Apps/iOSUITests/FastScrollPerformanceTests.swift`. Each page from the debug gallery's fixtures is flicked down and up with strong flicks (a drag across 60% of the scroll view, released at 7,000 pt/s, not `swipeUp(velocity: .fast)`; owner, 2026-10-27), five measured iterations after a warm-up pass. Metrics:
  - `scrollDecelerationMetric` and `scrollDraggingMetric` (the system hitch ratio);
  - the app's `EntityUpdate` and `ImageDecode` signposts (`EntityUpdate` is now the main-thread part only: applying the changed entities);
  - clock and CPU.
  - `testFlickLiveTabs` flicks Home, Security and Climate on the live server (`TEST_RUNNER_FENTON_PERF_LIVE=1` plus credentials). Home has no gallery fixture, so this is its only flick test.
  - Fixture pages include Settings (`settings.list`), Chores and Chores (long house, `FENTON_GALLERY_CHORES=12`), Climate and the Food pages: `testFlickSettings`, `testFlickChores`, `testFlickChoresLongHouse`, `testFlickClimate`, `testFlickFood`, `testFlickRecipes`.
- **Physical device only.** Simulators report false hitch data, so the measured tests skip there. The smoke tests `testPageFlicks<Page>WithoutLosingContent` (one per page) run everywhere and are part of the normal journeys.
- **Running:** `tools/ios_perf.sh --device "<iPhone name|UDID>" [--suite scroll|nav|launch|motion|ticker|all]` (default `scroll`). Add `--live --env shell` for live pages, or `--only testFlickRecipes` for one test (resolved against the suite's class). Each suite runs inside a `tools/devcap.py run --device` hold (`--hold SECONDS`, default 3600) and writes its own `apple/.build/perf-<suite>-<timestamp>.xcresult`; open it in Xcode to read metrics and set baselines per device.
  - `scroll`: `FastScrollPerformanceTests`. `nav`: `testDeviceNavigationTransitionMetrics`, `testDeviceZoomTransitionMetrics`. `launch`: the cold, no-intro and warm launch metrics plus `testIntroHitchRatioOnADevice` and `testArrivalHitchRatioOnADevice` (the warm and arrival tests need `--env shell` credentials; the `…WithinBudget` tests assert simulator budgets and are not run). `motion`: `LayoutChangePerformanceTests`. `ticker`: `WeatherTickerPerformanceTests`. `all`: every suite in turn.
- **In the app:** Settings → Performance shows the same pages' hitch ratios from real use, plus MetricKit's daily scroll hitch ratio. Export Telemetry shares the JSON. See [telemetry](../../patterns/telemetry.md).
- **Targets (Apple):** hitch ratio under 5 ms/s is good, 5–10 is noticeable, over 10 is bad.
- **Adding a page:**
  1. Give its scroll view an identifier and `.scrollTelemetry("<Page>")`.
  2. Add a `Page` entry and a `testFlick<Page>` method.
  3. Add its launch to `tools/scrollcost-surfaces.txt`.
- **Chip rail:** `testSwipeChipRail` swipes Home's six-chip rail along a 120-tile page (`FENTON_GALLERY_PERF=chips`), device only like the others; `testChipRailSwipesWithoutLosingContent` runs everywhere. Set the baseline per device in Xcode.
- **Finding a nested-scroll cost on the simulator** (chip rail, 2026-10-16). Hitch metrics are false there, and `XCTCPUMetric` is dominated by XCUITest's accessibility snapshots (every variant measured the same), so profile instead: build Release with `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DEBUG'` (keeps the gallery), start the swipe test, `xcrun xctrace record --template "Time Profiler" --device <UDID> --attach <app PID> --time-limit 25s` (attach by PID: `--attach FentonHome` matches the UI test runner), `xctrace export --xpath '/trace-toc/run/data/table[@schema="time-profile"]'`, and count main-thread samples under `ScrollViewCommitMutation.apply`, `ViewGraphRootValueUpdater._updateViewGraph` and `CA::Transaction::commit`. Vary one thing at a time (tile count, chips, the header fade); a cost that grows with the *page* rather than the scrolled content means the scroll is writing into the page's view graph. Logging body evaluations (`NSLog` in `body`) shows whether a swipe re-renders anything.

## Layout changes

Rows and sections that a person (or a live update) inserts, removes or swaps animate with `standard` (0.3 s) or `quick` (0.2 s) ([motion](../../design/motion.md) §6, proposal `motion-timings`): Custom Lights' manual control, the Vacation dates and range error, the bedside alarm, the remote keyboard form and the Profile badge.

- **Signpost:** `LayoutChange` (subsystem `com.sfenton.home`, category `Performance`), one interval per change from `measuresMotion` seeing its value change to the animation being due to settle (a frame later under Reduce Motion); the interval's page names the change (`CustomLights.manual`, `Vacation.dates`, `Vacation.rangeError`, `Bedside.alarm`, `MediaRemote.keyboard`, `Profile.badge`).
- **Run it:** `tools/ios_motionperf.sh [--only iphone|duo|ipad]`. It builds once under a devcap `build` hold and runs `LayoutChangePerformanceTests` on each family's simulator in its own `--sim` hold. Never on the owner's phone without asking.
- **Tests:** `testManualControlInsertCost` and `testManualControlInsertCostReduceMotion` flip Custom Lights' switch (the mode row and eight tiles in and out) five times per iteration and measure `XCTCPUMetric`, `XCTOSSignpostMetric` on `LayoutChange` and, on iOS 26 and later, `XCTHitchMetric`. They skip on a simulator unless `TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1` (the runner sets it). Unit: `LayoutChangeMotionTests`.
- **Remote action set:** `testRemoteActionSetChangeCost` and `testRemoteActionSetChangeCostReduceMotion` (same file, same runner) cycle Media Room Streamer on the Media gallery page between Power-beside-the-chevron and previous / play-pause / next with the volume slider below, three times per iteration; each swap is one `LayoutChange` interval with page `TileActionSet` (about 0.8 s: `quick` out, `standard` height, `quick` in; 0.2 s under Reduce Motion). The pure rules are `TileActionSetTransitionTests`. The slider's drag writes nothing per frame and sends one `volume_set` on release (`RemoteTransportAXTests.aDragWritesOnceOnRelease`). Run: `tools/ios_motionperf.sh --only iphone` (add `--label remote` to keep the logs apart).
- **Vacuum setting rows:** `testVacuumSettingRowCost` and `testVacuumSettingRowCostReduceMotion` (same file, same runner) pick Mode Vacuum then Vacuum and Mop on the Studio vacuum's Controls tab, three times per iteration, so the Water row collapses and returns (`VacuumRowReveal`: height `standard`, content `quick`; Reduce Motion: height at once, 0.2 s cross-fade). Each change is one `LayoutChange` interval with page `Vacuum.settingRows`; rooms ⇄ area logs `Vacuum.target`. Never on a reapply, at once while the sheet scrolls (`VacuumShapeMotion`). The pure rules and the reveal are `VacuumShapeMotionTests`. Run: `tools/ios_motionperf.sh --only iphone --label vacuum`. First run (iPhone 17 Pro simulator, 2026-10-29): `LayoutChange` 0.331 s per change (token 0.3 s plus a frame), 0.113 s under Reduce Motion; CPU is dominated by the Mode menu opening and closing, not the row.
- **Budgets:** no run-loop turn over 16 ms during a flip, and the interval is the token length plus a frame; hitch ratio under 5 ms/s on a device. First numbers are recorded when the orchestrator runs the script.

## Weather card ticker

The Home weather card's condition scrolls as a ticker when it is wider than its column ([ticker pattern](../../patterns/ticker.md), the exception in [motion](../../design/motion.md) §9). It is the one motion in the app that runs for seconds at a time, so it is measured.

- **Signpost:** `TickerRun` (subsystem `com.sfenton.home`, category `Performance`), one interval per run, from the ticker starting (or resuming) to it pausing, finishing or restarting; the end message says why (`paused`, `finished`, `restart`, `disappear`).
- **Run it:** `tools/ios_tickerperf.sh [--only iphone|duo|ipad] [--skip-scrollcost]`. It builds once under a devcap `build` hold, runs `WeatherTickerPerformanceTests` on each family's simulator in its own `--sim` hold, then runs `tools/ios_scrollcost.sh` on the two `Weather card …` surfaces. Never on the owner's phone without asking: a phone run is `tools/ios_perf.sh`-style (`--device`), the metrics below, and the owner's say-so first.
- **Tests:** `testTickerRunningCost` (ten seconds with the ticker running) and `testStillCardCost` (the same with a label that fits) measure `XCTCPUMetric`, `XCTOSSignpostMetric` on `TickerRun` and, on iOS 26 and later, `XCTHitchMetric`. They skip on a simulator unless `TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1` (the runner sets it).
- **Scroll cost:** surfaces `Weather card short label` and `Weather card ticking label` (the gallery pads the page with `FENTON_GALLERY_WEATHER_FILL`) scroll the page and stand still with and without a ticking label. The ticker pauses while the page scrolls (iOS 18 and later), so the two scroll rows should match; the idle rows show the ticker's cost.
- **Budgets** (the measured numbers are in the [performance log](../../archive/performance-log.md)):

  | What | Budget |
  |---|---|
  | Ticking card against the still card, CPU over 10 s (simulator) | at most 10% of one core more |
  | Hitch time ratio while the ticker runs (device only; simulator values are false) | under 5 ms/s (Apple's "good") |
  | Weather card ticking label, scrolled 8 s: main-thread p95 turn, turns over 8 ms | within 0.5 ms of the short label, none over 8 ms |
  | Ticker paused (scrolling, off screen, scene inactive) | no `TickerRun` interval open, timeline paused |
- **What keeps it cheap:** the moving text is one clipped, masked overlay driven by a `TimelineView` that is paused whenever the label is not running; nothing re-lays out (the layout line is a hidden truncating copy); no state is written per frame; it stops itself after three passes.

## Round 5 (2026-10-27): live delivery path

**Question.** On the phone, standing still for 8 s on Climate, Home, Food hub and Recipes showed 4,000 to 9,000 `changed` entities and 2 to 4 main-thread turns of 45 to 53 ms, though `update_ms` (the apply loop) was 4 to 6 ms. Why, and what does the live path cost per delivery?

**Causes (audit, HAKit `0535d4a`).**
- *A: phantom changes.* `HACompressedEntity.asEntity` sets `lastUpdated: lastUpdated ?? Date()` (Home Assistant omits `lu` when it equals `lc`) and `HAEntity ==` compares `lastUpdated`, so after any full resend nearly every entity counted as changed, was converted to `EntityState` and was deep-compared on the main thread. Few boxes really changed.
- *B: double resend.* `HACache` (the thing behind `caches.states()`) switches HAKit's own retry off (`shouldRetry = false`) and re-sends `subscribe_entities` on every `HAConnectionState.didTransitionToStateNotification`, so one reconnect delivered the house about twice (base reconnect rows: `received` 20 to 104 in 8 s, `compared` about 4,450 per reconnect, up to 9,200 when two sets arrived).

**Fix.** `HassConnection` subscribes with `connection.subscribe(to: .subscribeEntities(data: [:]), initiated:handler:)` and merges each compressed message itself (`EntityDeltaEngine`, `EntityDeltaBatch`): `a` adds or refreshes, `r` removes, `c` applies `+` (state and `lc` replaced, attributes merged per key) and `-` (attribute keys removed). An entity is reported only when its `EntityState` (state, attributes, `lastChanged`) differs; `lu` and the context are not kept. `initiated` (once per socket) marks the next message as a full set, which also removes entities it lacks. Messages are merged on `deltaQueue`, merged into one batch per burst, and one main-thread hop applies only the changed entities; the values that hop replaces are released on `deltaQueue`. The request sets `shouldRetry = true` and `retryDuration = nil`: HAKit's default 10 s retry window would otherwise drop the subscription on a reconnect later than 10 s after launch (found in the first smoke run: after a forced blip no full set arrived).

**Instrumentation (kept).** The scroll cost line now carries, per window: `deliveries`, `changed`, `received` (messages from HAKit), `full` (deliveries that changed more than half the house), `compared` (entities the main thread compared), `boxes` (boxes that really changed), `transitions` (HAKit connection state transitions), `subscribes` and `fullsets` (subscription starts and full sets the engine saw), `delivery_ms` (main-thread CPU in `HassConnection.apply`, including the store diff and releasing what it replaced), `update_ms` (the old signpost, the apply loop). A `launch` line (counters from process start, `firstlive_ms`, `ping_reconnects`) and, with `FENTON_SCROLLCOST_RECONNECT=1` (Debug builds), a `reconnect` line (a network blip, `HassConnection.debugBlip`, one second into an 8 s idle window). `tools/ios_scrollcost.sh --ab "base=KEY=VALUE;fix=" --rounds N [--launch-env ...]` runs the variants alternately surface by surface in one hold; `tools/scrollcost_ab.py LABEL` prints the tables below. The base was the same optimized app with the old path switched on by a temporary `FENTON_LEGACY_STATES=1`, since removed.

**Run.** iPhone 17 Pro simulator, iOS 27.0, optimized build, live house (about 4,800 entities), one hold, 3 alternating rounds, mean with [min-max]. Other lanes were using the Mac.

### Standing still 8 s (mean over rounds, [min-max])

| surface | variant | changed | deliveries | full | transitions | compared on main | boxes changed | update_ms | delivery_ms | main_ms | over8 | worst ms |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Live Home | base | 39 [17-79] | 15 [10-24] | 0 [0-0] | 0 [0-0] | 39 [17-79] | 6 [0-16] | 0.4 [0.2-0.7] | 0.7 [0.4-1.3] | 175 [23-284] | 0 [0-0] | 3.4 [0.4-5.1] |
| Live Home | fix | 53 [49-59] | 28 [20-33] | 0 [0-0] | 0 [0-0] | 53 [49-59] | 5 [1-10] | 0.4 [0.3-0.4] | 0.8 [0.7-0.9] | 28 [25-31] | 0 [0-0] | 2.6 [1.7-4.2] |
| Live Climate | base | 47 [28-79] | 22 [16-32] | 0 [0-0] | 0 [0-0] | 47 [28-79] | 8 [0-17] | 0.5 [0.3-0.9] | 1.1 [0.7-1.7] | 43 [42-44] | 0 [0-0] | 1.4 [1.1-2.0] |
| Live Climate | fix | 33 [17-45] | 19 [13-27] | 0 [0-0] | 0 [0-0] | 33 [17-45] | 2 [0-6] | 0.4 [0.2-0.6] | 1.0 [0.5-1.5] | 48 [41-57] | 0 [0-0] | 1.7 [1.1-2.7] |
| Live Chores | base | 41 [29-64] | 21 [15-28] | 0 [0-0] | 0 [0-0] | 41 [29-64] | 4 [2-5] | 0.4 [0.3-0.6] | 0.9 [0.7-1.2] | 40 [32-46] | 0 [0-0] | 1.1 [1.1-1.2] |
| Live Chores | fix | 39 [27-60] | 23 [19-27] | 0 [0-0] | 0 [0-0] | 39 [27-60] | 0 [0-0] | 0.4 [0.3-0.5] | 0.9 [0.7-1.0] | 46 [41-52] | 0 [0-0] | 1.5 [1.0-1.7] |
| Live Settings | base | 24 [23-27] | 17 [16-17] | 0 [0-0] | 0 [0-0] | 24 [23-27] | 0 [0-0] | 0.3 [0.2-0.3] | 0.6 [0.6-0.6] | 41 [38-43] | 0 [0-0] | 0.7 [0.6-0.7] |
| Live Settings | fix | 49 [40-59] | 25 [21-29] | 0 [0-0] | 0 [0-0] | 49 [40-59] | 0 [0-1] | 0.5 [0.3-0.6] | 1.1 [0.9-1.3] | 45 [39-52] | 0 [0-0] | 1.7 [1.1-2.4] |
| Live Food hub | base | 27 [22-32] | 17 [15-19] | 0 [0-0] | 0 [0-0] | 27 [22-32] | 0 [0-0] | 0.3 [0.2-0.4] | 0.7 [0.5-0.8] | 6 [5-6] | 0 [0-0] | 1.0 [0.4-1.4] |
| Live Food hub | fix | 44 [19-87] | 23 [12-38] | 0 [0-0] | 0 [0-0] | 44 [19-87] | 3 [0-8] | 0.5 [0.2-0.9] | 1.2 [0.6-2.0] | 9 [3-18] | 0 [0-0] | 1.2 [0.2-1.7] |
| Live Recipes | base | 38 [28-51] | 19 [16-22] | 0 [0-0] | 0 [0-0] | 38 [28-51] | 1 [0-2] | 0.3 [0.3-0.4] | 0.8 [0.6-1.0] | 9 [6-10] | 0 [0-0] | 1.4 [1.0-1.7] |
| Live Recipes | fix | 63 [25-103] | 33 [14-46] | 0 [0-0] | 0 [0-0] | 63 [25-103] | 3 [0-5] | 0.7 [0.2-1.0] | 1.7 [0.7-2.3] | 14 [5-19] | 0 [0-0] | 1.8 [1.4-2.3] |

### Scrolling 8 s (mean over rounds, [min-max])

| surface | variant | changed | deliveries | full | transitions | compared on main | boxes changed | update_ms | delivery_ms | main_ms | over8 | worst ms |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Live Chores | base | 38 [16-57] | 18 [12-24] | 0 [0-0] | 0 [0-0] | 38 [16-57] | 0 [0-2] | 0.4 [0.2-0.5] | 0.8 [0.4-1.0] | 962 [894-1038] | 5 [0-9] | 15.3 [8.0-22.9] |
| Live Chores | fix | 28 [16-41] | 17 [12-21] | 0 [0-0] | 0 [0-0] | 28 [16-41] | 1 [0-5] | 0.2 [0.1-0.3] | 0.5 [0.3-0.7] | 1027 [921-1091] | 4 [0-9] | 14.8 [7.9-24.4] |
| Live Settings | base | 22 [13-30] | 14 [10-15] | 0 [0-0] | 0 [0-0] | 22 [13-30] | 1 [0-5] | 0.2 [0.1-0.4] | 0.5 [0.3-0.7] | 1019 [1003-1042] | 12 [5-16] | 15.3 [11.0-20.4] |
| Live Settings | fix | 33 [21-46] | 21 [15-30] | 0 [0-0] | 0 [0-0] | 33 [21-46] | 1 [0-5] | 0.2 [0.2-0.3] | 0.6 [0.5-0.9] | 1023 [884-1119] | 11 [4-17] | 15.1 [8.9-20.9] |
| Live Food hub | base | 26 [21-33] | 14 [11-21] | 0 [0-0] | 0 [0-0] | 26 [21-33] | 0 [0-1] | 0.2 [0.2-0.3] | 0.6 [0.5-0.8] | 932 [876-1012] | 6 [4-9] | 14.9 [10.0-21.4] |
| Live Food hub | fix | 44 [28-102] | 24 [16-47] | 0 [0-0] | 0 [0-0] | 44 [28-102] | 1 [0-3] | 0.3 [0.1-0.6] | 0.7 [0.4-1.3] | 907 [863-952] | 6 [1-13] | 12.8 [8.2-17.1] |
| Live Recipes | base | 51 [28-78] | 21 [15-25] | 0 [0-0] | 0 [0-0] | 51 [28-78] | 5 [0-13] | 0.5 [0.3-0.6] | 1.0 [0.7-1.2] | 952 [822-1132] | 7 [1-12] | 14.0 [8.0-19.5] |
| Live Recipes | fix | 43 [24-75] | 26 [19-38] | 0 [0-0] | 0 [0-0] | 43 [24-75] | 2 [0-5] | 0.3 [0.2-0.6] | 0.8 [0.6-1.3] | 947 [897-1001] | 6 [2-11] | 13.6 [9.0-19.7] |

### Cold launch to the page settling (counters since process start)

| surface | variant | first live ms | deliveries | received | full | subscribes | full sets | transitions | compared | boxes | delivery_ms | main_ms | over8 | worst ms |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Live Home | base | 2186 [1871-2697] | 45 [38-50] | 119 [93-157] | 1 [1-1] | 0 [0-0] | 0 [0-0] | 3 [3-3] | 4811 [4789-4830] | 86 [83-89] | 9.2 [8.7-9.6] | 0 [0-0] | 0 [0-0] | 0.0 [0.0-0.0] |
| Live Home | fix | 3035 [1789-4869] | 52 [37-71] | 112 [67-176] | 1 [1-1] | 1 [1-1] | 1 [1-1] | 3 [3-3] | 4821 [4784-4877] | 84 [83-85] | 9.3 [9.0-9.5] | 0 [0-0] | 0 [0-0] | 0.0 [0.0-0.0] |
| Live Climate | base | 2441 [1840-3250] | 33 [23-39] | 78 [44-96] | 1 [1-2] | 0 [0-0] | 0 [0-0] | 4 [3-7] | 6259 [4753-9214] | 129 [127-133] | 12.3 [8.4-18.5] | 0 [0-0] | 0 [0-0] | 0.0 [0.0-0.0] |
| Live Climate | fix | 2042 [1983-2145] | 45 [37-59] | 88 [71-114] | 1 [1-1] | 1 [1-1] | 1 [1-1] | 3 [3-3] | 4798 [4784-4818] | 130 [128-132] | 9.3 [9.0-9.7] | 0 [0-0] | 0 [0-0] | 0.0 [0.0-0.0] |
| Live Chores | base | 2199 [2191-2204] | 30 [30-31] | 73 [60-82] | 1 [1-1] | 0 [0-0] | 0 [0-0] | 3 [3-3] | 4782 [4770-4791] | 111 [109-114] | 8.6 [8.3-9.0] | 0 [0-0] | 0 [0-0] | 0.0 [0.0-0.0] |
| Live Chores | fix | 2084 [2014-2222] | 40 [32-46] | 84 [77-95] | 1 [1-1] | 1 [1-1] | 1 [1-1] | 3 [3-3] | 4797 [4789-4807] | 113 [113-113] | 8.9 [8.8-9.0] | 0 [0-0] | 0 [0-0] | 0.0 [0.0-0.0] |
| Live Settings | base | 2516 [2431-2660] | 29 [24-37] | 58 [46-69] | 1 [1-1] | 0 [0-0] | 0 [0-0] | 3 [3-3] | 4770 [4761-4780] | 87 [83-89] | 8.4 [8.2-8.7] | 0 [0-0] | 0 [0-0] | 0.0 [0.0-0.0] |
| Live Settings | fix | 2703 [2457-3051] | 38 [29-53] | 74 [46-128] | 1 [1-1] | 1 [1-1] | 1 [1-1] | 3 [3-3] | 4788 [4762-4837] | 82 [80-83] | 9.1 [8.2-9.9] | 0 [0-0] | 0 [0-0] | 0.0 [0.0-0.0] |
| Live Food hub | base | 2160 [1948-2382] | 34 [23-46] | 80 [50-103] | 1 [1-2] | 0 [0-0] | 0 [0-0] | 4 [3-7] | 6262 [4762-9210] | 92 [90-94] | 12.2 [8.0-19.5] | 0 [0-0] | 0 [0-0] | 0.0 [0.0-0.0] |
| Live Food hub | fix | 2224 [1953-2700] | 50 [40-60] | 102 [75-152] | 1 [1-1] | 1 [1-1] | 1 [1-1] | 3 [3-3] | 4815 [4790-4862] | 93 [87-102] | 10.3 [9.8-10.9] | 0 [0-0] | 0 [0-0] | 0.0 [0.0-0.0] |
| Live Recipes | base | 2252 [1929-2564] | 40 [26-56] | 107 [50-171] | 1 [1-1] | 0 [0-0] | 0 [0-0] | 3 [3-3] | 4812 [4763-4871] | 93 [90-97] | 9.2 [8.7-10.0] | 0 [0-0] | 0 [0-0] | 0.0 [0.0-0.0] |
| Live Recipes | fix | 2065 [1987-2158] | 63 [55-69] | 114 [99-126] | 1 [1-1] | 1 [1-1] | 1 [1-1] | 3 [3-3] | 4828 [4812-4841] | 94 [92-96] | 10.2 [9.6-10.8] | 0 [0-0] | 0 [0-0] | 0.0 [0.0-0.0] |

### Forced reconnect (network blip 1 s into an 8 s idle window)

| surface | variant | first live ms | deliveries | received | full | subscribes | full sets | transitions | compared | boxes | delivery_ms | main_ms | over8 | worst ms |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Live Home | base | 0 [0-0] | 17 [15-21] | 43 [29-58] | 1 [1-1] | 0 [0-0] | 0 [0-0] | 5 [5-5] | 4457 [4441-4470] | 4 [3-5] | 11.6 [10.7-12.5] | 161 [144-176] | 4 [4-5] | 33.2 [28.6-37.3] |
| Live Home | fix | 0 [0-0] | 23 [18-30] | 49 [42-60] | 0 [0-0] | 1 [1-1] | 1 [1-1] | 5 [5-5] | 45 [36-56] | 4 [0-10] | 0.8 [0.6-1.1] | 165 [133-218] | 4 [3-5] | 38.0 [28.8-55.7] |
| Live Climate | base | 0 [0-0] | 19 [16-22] | 43 [38-51] | 1 [1-1] | 0 [0-0] | 0 [0-0] | 5 [5-5] | 4456 [4450-4459] | 2 [0-5] | 12.1 [11.1-13.4] | 193 [187-201] | 4 [4-4] | 36.3 [29.2-47.2] |
| Live Climate | fix | 0 [0-0] | 14 [8-20] | 22 [13-35] | 0 [0-0] | 1 [1-1] | 1 [1-1] | 5 [5-5] | 36 [20-55] | 2 [0-5] | 0.7 [0.6-0.9] | 170 [156-182] | 3 [3-4] | 35.0 [30.4-38.9] |
| Live Chores | base | 0 [0-0] | 14 [8-23] | 28 [14-52] | 1 [1-1] | 0 [0-0] | 0 [0-0] | 5 [5-5] | 4443 [4431-4460] | 0 [0-0] | 10.1 [9.1-11.5] | 211 [205-214] | 5 [4-5] | 37.5 [36.7-38.0] |
| Live Chores | fix | 0 [0-0] | 18 [13-23] | 33 [31-35] | 0 [0-0] | 1 [1-1] | 1 [1-1] | 5 [5-5] | 35 [29-38] | 1 [0-2] | 0.7 [0.6-0.9] | 186 [179-191] | 3 [3-3] | 36.1 [32.4-40.4] |
| Live Settings | base | 0 [0-0] | 18 [11-22] | 36 [18-48] | 1 [1-1] | 0 [0-0] | 0 [0-0] | 5 [5-5] | 4450 [4436-4461] | 2 [0-5] | 10.6 [9.0-12.3] | 204 [194-214] | 4 [4-4] | 35.1 [30.8-38.8] |
| Live Settings | fix | 0 [0-0] | 19 [12-23] | 33 [18-46] | 0 [0-0] | 1 [1-1] | 1 [1-1] | 5 [5-5] | 38 [20-48] | 2 [0-5] | 0.9 [0.5-1.1] | 177 [163-189] | 3 [3-4] | 38.0 [35.2-39.6] |
| Live Food hub | base | 0 [0-0] | 12 [11-14] | 20 [16-28] | 1 [1-1] | 0 [0-0] | 0 [0-0] | 5 [5-5] | 4434 [4430-4438] | 0 [0-1] | 9.9 [9.4-10.2] | 152 [144-167] | 3 [3-4] | 31.6 [28.4-35.2] |
| Live Food hub | fix | 0 [0-0] | 20 [8-34] | 38 [14-70] | 0 [0-0] | 1 [1-1] | 1 [1-1] | 5 [5-5] | 44 [17-86] | 0 [0-1] | 0.9 [0.4-1.5] | 142 [124-155] | 2 [2-3] | 34.4 [31.8-35.8] |
| Live Recipes | base | 0 [0-0] | 26 [17-32] | 81 [39-104] | 1 [1-1] | 0 [0-0] | 0 [0-0] | 5 [5-5] | 4485 [4453-4503] | 5 [0-11] | 11.3 [10.7-12.2] | 160 [157-164] | 4 [3-5] | 34.8 [32.2-38.7] |
| Live Recipes | fix | 0 [0-0] | 21 [14-28] | 44 [19-57] | 0 [0-0] | 1 [1-1] | 1 [1-1] | 5 [5-5] | 48 [21-63] | 0 [0-1] | 0.9 [0.6-1.1] | 148 [139-157] | 2 [2-3] | 35.5 [32.4-39.4] |

**Reading it.**
- *Reconnect is the win.* After a forced blip the old path compared about 4,450 entities on the main thread (one full delivery, `received` up to 104) and spent 10 to 12 ms of main-thread CPU in the delivery; the new path compared 35 to 48 and spent 0.7 to 0.9 ms (13 to 17 times less), with exactly one subscribe and one full set per reconnect. `main_ms`, `over8` and `worst ms` of the reconnect window fell a little (over8 4 to 5 down to 2 to 4) but the worst turn is still about 35 ms in both: that turn is not the delivery (`delivery_ms` is about 1 ms), so it is something else on a reconnect (the status change re-rendering is the suspect, not measured) and the next thing to look at.
- *Cold launch.* One full delivery in both (about 4,800 entities, about 9 ms of main-thread CPU, first live set at about 2.0 to 2.5 s). The old path sometimes delivered the house twice in the first 19 s (Climate and Food hub, one round each: `full` 2, `compared` 9,200, `transitions` 7); the new path never did (3 transitions, 1 subscribe, 1 full set, every round).
- *Idle and scroll on the simulator did not reproduce the phone's 4,000 to 9,000.* `changed` is 17 to 100 per 8 s in both variants, `full` 0, `over8` 0 idle and the scroll rows are within noise (Settings 1019 vs 1023 ms, Chores 962 vs 1027 ms, Food hub 932 vs 907 ms, Recipes 952 vs 947 ms). The simulator never runs the home-network route switch or `ensureLive` reconnects, and the phone's thousands are a resend landing in the measured window: the resend now costs about 40 entities on the main thread instead of about 4,450, so the phone symptom should be gone, but only a phone run can show it. Home and Climate fit one screen, so only their idle rows exist. Live Home's base idle `main_ms` (175 [23-284]) is one noisy round.
- *Counters that do not move:* `update_ms` and `delivery_ms` of ordinary deliveries (0.5 to 1.5 ms per 8 s), because a delivery of a few entities was already cheap.

### Reconnect cost: status fan-out

**Question.** The reconnect window's worst main-thread turn is about 35 ms in both delivery paths (`delivery_ms` about 1 ms). The suspect was the status fan-out: `MainTabView.body` read `connection.status` for `.task(id: isConnected)` and `RootView.body` for `.onChange(of: connection.status)`, so each of a reconnect's 2 to 3 status changes re-evaluated the whole shell.

**Profile first** (Time Profiler on the simulator, Debug-optimized app, Live Home, `FENTON_SCROLLCOST_RECONNECT=1`, the blip window): the long turns were not the shell. In the 62 s trace the turns over 8 ms were 17, 14, 10 and 11 ms and went to:
- `HassConnection.setOnline` → `HAConnectionImpl.disconnect`: about 10 ms, nearly all one cold `swift_conformsToProtocol` / `swift_dynamicCast` inside HAKit's string interpolation of its disconnect log (first disconnect of the process; HAKit, not ours). Debug-only `PushTrace.record` adds 3 to 4 ms in the same turn (it reads and atomically rewrites its file on the main thread; Release builds record nothing).
- `WeatherSummaryCard`'s `.onChange(of: isConnected)` → `WeatherForecastStore.setConnected` → `refresh()`: about 7 ms of the turn, twice per reconnect, parsing the hourly forecasts' ISO 8601 text (`HassDates.iso8601` through `WeatherForecast.start`) in `pruneHourly` and for the timer deadlines each time.
- SwiftUI graph work for the status readers was the rest and small.

**Fixes.** (1) The two status reads moved out of the shell's bodies into zero-size children: `ProfileLoadOnConnect` (owns `.task(id: isConnected)` for `loadProfileName()`, which still runs on appear and each time the socket becomes ready) and `ConnectionStatusRelay` (owns the `.onChange` that tells `AppSession`). (2) `WeatherForecastStore` caches each hourly entry's expiry by its `datetime` text, so a refresh parses nothing it has seen. No visible change.

**Proof.** `StatusFanOutTests`: a status change (connecting, then disconnected, driven through `setOnline`) leaves `MainTabView`'s body count (`ShellRenderProbe`, Debug) unchanged, and the profile load runs once, not again. With the old reads restored the same test fails (`mainTabBodies == before`).

**Run.** iPhone 17 Pro simulator, one hold, 3 alternating rounds, mean [min-max], Live Home, Climate and Settings. Both arms below already have the weather fix; `base` restores the old status reads (`FENTON_LEGACY_STATUS=1`, a temporary switch, removed). Earlier, before the weather fix, the same A/B (base against fix of the status reads only) gave worst ms 28.2 against 28.0 (Home), 33.3 against 32.6 (Climate) and 31.1 against 31.4 (Settings): the status fan-out alone moved nothing.

| surface | variant | main_ms | over8 | worst ms | transitions | delivery_ms |
|---|---|---|---|---|---|---|
| Live Home | base | 206 [113-369] | 2 [2-2] | 23.4 [13.4-36.2] | 5 [5-5] | 0.7 [0.6-1.0] |
| Live Home | fix | 194 [111-357] | 2 [2-2] | 22.2 [20.7-24.2] | 5 [5-5] | 0.4 [0.4-0.5] |
| Live Climate | base | 169 [162-181] | 2 [2-3] | 34.7 [34.0-35.6] | 5 [5-5] | 0.8 [0.6-1.0] |
| Live Climate | fix | 160 [150-169] | 2 [2-2] | 24.1 [20.2-27.1] | 5 [5-5] | 1.0 [0.7-1.2] |
| Live Settings | base | 179 [170-187] | 2 [2-3] | 33.3 [31.9-35.5] | 5 [5-5] | 1.2 [0.8-1.8] |
| Live Settings | fix | 175 [157-210] | 2 [2-3] | 31.5 [29.1-35.4] | 5 [5-5] | 0.9 [0.6-1.2] |

Idle rows are unchanged (main_ms 45 to 50 on Climate and Settings in both; Home's 173 and 120 are one noisy first round each). The scroll row for Settings was not re-run.

**Reading it.**
- The status fan-out was not the 35 ms. Re-rendering the shell cost too little to see (worst turn within noise before the weather fix; after it, `main_ms` 2 to 6% lower and `over8` the same).
- What the 35 ms was: two or three turns of 10 to 18 ms, each a different thing (a cold cast in HAKit's disconnect log plus Debug-only trace I/O; the weather store's date parsing, twice). The probe's blip calls `setOnline` on the main thread, as the reachability monitor does.
- The weather fix is real but its A/B effect is inside the noise on this machine (worst ms 28 to 33 before, 22 to 35 after, ranges overlap); the profile, not the table, is the evidence for it.
- Left alone: HAKit's cold conformance lookup on first disconnect (about 10 ms once per process, in a dependency; a Release phone run decides whether it matters) and `PushTrace` (Debug only). Neither is a reconnect problem on a Release build.

**Left alone, on purpose.**
- The route switch after the first live set (`apply` calls `refreshRoute()` while the route is the public one) already reconnects only when the route changed (`LocalServerRoute.refresh` returns false otherwise); when it does change it is a needed reconnect (the unpinned case must confirm home from live states first). With the new path that reconnect costs one subscribe and about 40 compared entities. Its call restarts an in-flight route check, which delays an already-pinned switch by up to 1.5 s: not changed, behaviour.
- `ensureLive`'s 3 s ping reconnect: no spurious firing seen (`ping_reconnects=0` in every launch row; counter `connection.pingReconnects` stays so a phone run can show it). A delivery no longer holds `deltaQueue` for long, which removes the one plausible cause (a ping answer queued behind a 100 ms diff).
- The snapshot save, `EntitySnapshotCache` and `replaceAll` on the first set are unchanged.

### Per-entity subscriptions: would they help?

Measured from the live house (one 5-minute window, 2026-10-27, an unfiltered `subscribe_entities` from a Node probe with the app's token; the window was quiet, so busy periods differ):

| What | Number |
|---|---|
| Entities in the house | 4,723 |
| Initial full set on the wire | 1.57 MB |
| Steady updates | 1,072 messages in 307 s (3.5 per second), 238 KB (0.78 KB/s) |
| Entity ids the app can ever show (string literals in `HassCore`/`HassUI` that exist live: 505, plus templated ids such as vacuum rooms, climate keys and sleep pod entities matched by pattern: 278, plus `person.*` for the profile list: 2) | about 755 (16% of the house; an upper bound, the template match can over-count) |
| Updates from entities the app never shows | 62% of updates, 73% of bytes (about 2.2 per second, 0.33 KB/s); the top ones are `number.*_Bed_*_target_level` (163 each, but those are in the app's bedroom page), `script.demo_ext_41` and `automation.demo_ext_42` (122 each), `sensor.demo_sensor_*` |
| Updates from entities it does show | 1.3 per second, 0.12 KB/s |

The app never enumerates the store by domain except `person.*`, so the union is a closed set computable from config and code.

- **(a) Whole house (today).** Cost: 1.57 MB once per socket, parsed and converted off the main thread (about 9 ms on the main thread on apply), then about 0.8 KB/s and 2 to 3 irrelevant updates per second, all off the main thread and, with the engine, free for the main thread (an update for an entity nobody reads still costs a box lookup, nothing else). A reconnect re-sends the 1.57 MB. This is what Home Assistant's own frontend does.
- **(b) One filtered subscription to the app-wide union.** `entity_ids` cuts the full set to about 16% (about 250 KB) and the steady state to about 40% of the messages, so a reconnect on cellular moves 1.3 MB less and the delta queue merges about 16% of the entities. Costs: the id list must be built from config (including templated ids and ids from dashboard data the app reads at runtime), a missed id means a tile that silently never updates, a changed list means a re-subscribe (a full set for the new subset), and `person.*` plus anything dynamic still has to be listed. It does not touch the main thread at all, which was the problem. Worth doing only for bytes on cellular and radio wake-ups; as a small change after the engine is proven it is safe if the list is generated from the same config the pages use and a debug check fails when a page reads an id outside it.
- **(c) Subscribe and unsubscribe per page, component or modal.** Each open pays a round trip (tens of milliseconds at home, 40 to 65 ms through the public URL before the route switch) before the first value, which is exactly the blank-until-loaded the "no reload on reopen" invariant forbids; the disk snapshot would have to cover every page, and then it is the old state painted until the subscription answers. SwiftUI's appear and disappear fire on every tab switch, lazy-list scroll, sheet and navigation pop (the tab bar keeps views alive, so appear is not "visible"), which turns into subscribe and unsubscribe churn, each carrying a full initial set for its ids and a server-side listener; HA registers a state listener per subscription, so many small subscriptions cost the server more than one. Reconnect must resend every active subscription in order, and a page that opens while a reconnect is in flight races the resend; two pages that share a tile need reference counting. Overlap with the cheap fix is nil: the main-thread cost was never the subscription's size.

**Recommendation.** Keep (a) now: the engine makes a message cost O(changed) and a resend about 40 main-thread entities, which removes the measured problem. (b) is the only option worth considering later, for cellular bytes (1.3 MB less per reconnect, about 60% fewer wake-ups), not for the main thread. Do not do (c): it trades a measured non-problem for blank pages on open and subscription churn. Revisit (b) only if a phone run still shows radio cost.

**Not measured.** The phone (unavailable): the idle `changed` of 4,000 to 9,000 and the 45 to 53 ms turns are expected to be gone but are unconfirmed; run `tools/ios_scrollcost.sh --device ... --only "Live Climate,Live Home,Live Food hub,Live Recipes"` and read `full`, `compared` and `transitions`. The `reconnect` row needs a Debug build, so it is simulator-only. The 35 ms worst turn on reconnect is a separate cost (status UI), not addressed.

## Round 6 (2026-10-28): large-title collapse

**Question.** How much of the remaining scroll stutter is the system large-title collapse in the navigation bar, and does a first-party alternative remove it?

**Tooling added.** The variants below were switched in source by temporary `FENTON_PERF_DISABLE` layers (`leadingTitle`, `headerButtons`, `largeTitle`, `inlineLargeTitle`) and a `FENTON_VANILLA_HEADER` build flag. **They are removed (2026-10-28, cleanup): the experiments are over, the layer names below are history, and a new run cannot select those variants.** Kept:
- `FENTON_GALLERY_FLYOUT=1` (Debug) runs gallery pages in the flyout chrome. Surfaces `Settings (flyout)`, `Recipes (flyout)` and `Chores long house (flyout)` are in the `[flyout]` section of `tools/scrollcost-surfaces.txt`. `--section` takes a comma list (`flyout,live`).
- The probe's `Mover` now remembers the largest top inset seen, across runs, so every pass goes into the expanded large-title zone and back (before, it clamped to the collapsed inset and never re-entered it). The probe line carries `inset_changes=` (an `adjustedContentInsetDidChange` hook on the driven scroll view) and `inset_kvo=` (KVO on `adjustedContentInset`). **KVO never fires** (0 in every run); use `inset_changes`.
- `scrollcost_ab.py --compact` prints the table below. `ios_flingfps.sh` takes `--disable`, `--flyout`, `--tag`, `--ab-disable <switch>` (A/B any `FENTON_PERF_DISABLE` switch in one device hold: `--runs N` of each test with the default build, then with the switch, interleaved, and a table at the end; variants `default` and `<switch>-off`), and builds with `-O`.

### Simulator (iPhone 17 Pro, optimized, 3 alternating rounds x 2 scroll runs = 6 runs per cell, mean [min-max])

Variants: `shipped` = fade + left-aligned collapsing title; `vanilla` = `headerFade,leadingTitle` off (system large title); `inline` = those plus `largeTitle` (inline titles); `inlineLarge` = vanilla with `.inlineLarge`.

| surface | variant | main_ms | over8 | over16 | worst ms | p95 ms | inset_changes |
|---|---|---|---|---|---|---|---|
| Settings (flyout) | shipped | 860 | 6 [4-7] | 1 [0-3] | 17.6 [10.3-23.5] | 2.1 | 6 |
| Settings (flyout) | vanilla | 962 | 3 [1-5] | 0 | 9.5 [8.2-10.8] | 2.5 | 6 |
| Settings (flyout) | inline | 913 | 0 | 0 | 3.1 | 2.3 | 0 |
| Settings (flyout) | inlineLarge | 966 | 0 | 0 | 6.6 | 2.2 | 0 |
| Recipes (flyout) | shipped | 1239 | 8 [5-11] | 0 | 12.8 | 4.3 | 0 |
| Recipes (flyout) | vanilla | 1083 | 2 [0-5] | 0 [0-2] | 13.0 | 3.7 | 0 |
| Recipes (flyout) | inline | 1150 | 4 [0-5] | 0 [0-2] | 13.8 | 3.9 | 0 |
| Recipes (flyout) | inlineLarge | 1042 | 4 [0-8] | 0 [0-1] | 13.8 | 3.6 | 0 |
| Chores long house (flyout) | shipped | 1716 | 3 [2-5] | 0 [0-2] | 16.0 | 4.8 | 2 |
| Chores long house (flyout) | vanilla | 1698 | 2 [1-3] | 0 | 10.9 | 4.7 | 2 |
| Chores long house (flyout) | inline | 1725 | 0 | 0 | 5.2 | 4.7 | 0 |
| Chores long house (flyout) | inlineLarge | 1660 | 0 [0-1] | 0 | 6.7 | 4.5 | 0 |
| Live Settings | shipped | 1047 | 4 [2-5] | 0 [0-1] | 12.2 | 2.6 | 5 |
| Live Settings | vanilla | 1091 | 3 [2-5] | 0 | 10.7 | 2.8 | 5 |
| Live Settings | inline | 953 | 0 | 0 | 3.5 | 2.4 | 0 |
| Live Settings | inlineLarge | 1019 | 1 [0-1] | 0 | 8.5 | 2.3 | 0 |

**Reading (simulator).**
- Every turn over 8 ms on Settings and Chores comes with the collapse: each top crossing makes UIKit change the inset 2 to 7 times (`inset_changes` > 0 exactly where over8 > 0). With inline titles or `.inlineLarge` the inset never changes and over8 goes to 0 (inlineLarge: 0 to 1) and the worst turn to 3 to 8 ms. main_ms barely moves (CPU is not the story, turn length is).
- The left-aligned title controller adds to the worst turn (shipped 12 to 18 ms against vanilla 9.5 to 11 ms) but the system collapse itself remains in vanilla (1 to 5 turns over 8 ms).
- Recipes (flyout) shows **0 inset changes in every variant** and over8 does not follow the variant: its page does not enter the large-title collapse in the gallery (it owns its own stack and chrome), so it says nothing about the title. Its 2 to 8 turns over 8 ms are the grid, not the bar.

### Phone (iPhone 18 Pro, Release, live; INCOMPLETE)

Only round 1 ran. The phone then locked (`FBSOpenApplicationErrorDomain 7, Locked`; the passcode is the owner's) and round 2 produced no rows, and the `inlineLarge` Live Settings row is missing. Treat these as indicative, not as a result. The Live Recipes cells mix one run taken while a second launch overlapped (an idle window of 95 s in `shipped`), so they are not usable. Installed build for every row: bundle container `160174E6-...`, my Release of 2026-10-27 22:23 (left-aligned collapsing title and fade as before the owner's centred-title decision); it did not change during the run.

| surface | variant | runs | main_ms | over8 | over16 | worst ms | p95 ms | inset_changes |
|---|---|---|---|---|---|---|---|---|
| Live Settings | shipped | 2 | 2210 | 10 [9-11] | 1 | 42.4 [19.6-65.2] | 3.1 | 0 (hook did not fire) |
| Live Settings | vanilla | 2 | 2314 | 26 [15-38] | 2 [0-4] | 39.5 [12.9-66.1] | 4.7 | 16 |
| Live Settings | inline | 2 | 1751 | 0 | 0 | 5.9 | 2.6 | 0 |

Even with one round, the pattern matches the simulator: inline titles remove every long turn on live Settings on the phone, while the collapsing variants show 10 to 38 turns over 8 ms with worst turns of 40 to 66 ms. The `shipped` row's `inset_changes=0` against `vanilla`'s 16 is unexplained (the hook may be bypassed by the left-aligned title's `titleView` path); do not read it as "no inset changes".

**Not done (blocked by the locked phone, owner asleep; the `--disable ...largeTitle` variants need the removed layers, so only the shipped build can be run now):** the touch-fling hitch counts per variant (`ios_flingfps.sh`) and the SwiftUI Instruments trace of the live Settings fling. Command for the morning, phone unlocked: `tools/ios_flingfps.sh --device 00008160-00022D8230914036 --live --tests testFlingLiveSettings --disable headerFade,leadingTitle,largeTitle --tag inline` and the same without `--disable`; for the trace, `xctrace record --template 'SwiftUI' --attach <pid>` during `testFlingLiveSettings` (delete the trace afterwards, it can hold the token in its environment section).

**What `.inlineLarge` changes.** Large type in the bar's own row (no extra band under the bar, so the content starts higher and the bar never changes height). Apple's caveat: leading and centred bar items move to the overflow menu. Here that would hit the flyout menu button and Back (leading items); not verified on screen (visible change, owner decides). Simulator: it removes the inset changes like inline titles do.

**Next steps (evidence-backed).**
1. The collapse is the cause of the over-8 ms turns on Settings and Chores in the simulator, and the phone round agrees. The cheapest fix that keeps a large title look is to avoid the bar changing height: `.inlineLarge` (needs the menu-button/Back check and owner approval) or inline titles.
2. If the owner keeps the collapsing title (centred, as decided), the remaining cost is the system's: 2 to 7 inset changes per crossing. Check whether freeing the page from `safeAreaInset`/ignoring-safe-area readers under the title shortens those turns, measuring with `inset_changes` and over8.
3. Finish the phone rounds and the fling/Instruments run with the phone unlocked, on the new centred-title Release.

## Round 7 (2026-10-28, closed 2026-10-31): scroll frame-rate request, measured, removed

Owner decision 2026-10-28, verbatim: "Yes, keep that" (a 120 Hz request while scrolling). Measured 2026-10-31 on the iPhone 18 Pro with `tools/ios_flingfps.sh --ab` (then; now `--ab-disable`), the app's in-app passive `FrameMonitor`, 2 runs per cell, Settings and Recipes flings. Owner decision 2026-10-31, verbatim: "Remove the request". Table and reasoning: [scroll-frame-rate](../../patterns/scroll-frame-rate.md). Mean fps was the same (about 96); with the request 87.5% of frames were at 120 Hz but the misses were 25 ms frames, without it 74% were at 120 Hz and iOS stepped to an even 60 Hz; total slow-frame time was equal. The request, `ScrollFrameRateBooster` and `FENTON_PERF_DISABLE=scrollRate` are gone. **Caveat (review, 2026-10-31):** these numbers excluded each run's last scroll (likely the down-flick half), equally in both arms, because the probe label lagged one scroll; fixed since (`FlingFpsCollector.refresh(with:)`). A corrected re-measurement was skipped (owner, 2026-10-31: the app is moving to UIKit in another session). For a future A/B of another layer: `tools/ios_flingfps.sh --device <udid> --ab-disable <switch> --runs 2`.
