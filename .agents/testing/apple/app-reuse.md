# App reuse in journeys

> **What:** one running app per journey class, reset between tests instead of relaunched (pilot, 2026-10-30). **Read when:** a journey class launches the gallery in every test, or a reused test misbehaves.

## Why

A cold gallery launch costs about 6.6 s: process start to `App.init` 3.3 s (dyld and static initialisers of the Debug binary), `init` to first SwiftUI frame 0.8 s, the first-frame task 0.2 s, XCUITest's launch and idle wait about 1 s, and `terminate` 1 s. Fixture load and the gallery's own first frame cost nothing measurable (0.00 s); animations already run 10x faster. The launch is process cost, so the only way to remove it is to not launch.

## How

- On by default (owner, 2026-10-31): `tools/ios_uitest.sh` exports `TEST_RUNNER_FENTON_UITEST_REUSE=1` unless the caller set it; `TEST_RUNNER_FENTON_UITEST_REUSE=0` turns it off for a run. A bare `xcodebuild test` without it runs with reuse off.
- A class opts in by launching through `startApp(_:)` (`AppReuse.swift`) instead of `app.launch()`. Bedroom was the pilot; see Opted-in classes below.
- The first test launches the app with `FENTON_UITEST_REUSE=<request dir>`. Each later test writes `<sequence>\n<FENTON_GALLERY* query>` to `<dir>/request`; the app (`GalleryReset`, Debug only) empties the tree for 0.4 s so sheets and alerts are gone, replaces its `FENTON_GALLERY*` environment, and rebuilds the gallery under a new identity. The `uitest.generation` element's label is the reset counter the test waits on.
- `XCUIApplication.open(URL)` was tried first and rejected (it re-launches UI automation and waits for idle, about 5 s a test). The request file is the only route; the URL handler is gone.

## A test must relaunch (not reuse) when

The base class does this on its own for the first four, because they change the *launch signature* (launch arguments plus every launch variable that is not `FENTON_GALLERY*`); a class keeps a resident app per signature, but only one of them is ever alive: a simulator runs one process per bundle id, so every launch of the app (another signature's resident, an AX5 launch) ends the previous process, and `AppReuse` drops all other residents at that launch (`dropResidents()`). The old `XCUIApplication` handle of an ended process still reports `.runningForeground`, so a reset sent to it would wait out the full 10 s (5 times a run in `SummaryJourneyTests`, 2026-11-03). Rule: the next test of a dropped signature launches at once; the 10 s fallback is only for a live app that fails to acknowledge a reset (`REUSE reset failed` in a log is then a defect in the reset, not a signature switch).

1. It needs AX5 or any launch argument (`FentonHomeApp.ax5`). `AppReuse.start` launches these fresh every time: a reset inside an app launched at AX5 left the Food hub and recipe grid failing their AX5 audits (2026-10-31; the leaking state is not found yet).
2. It needs Reduce Motion, Reduce Transparency, Increase Contrast or Bold Text (`FENTON_SYSTEM_SETTINGS`).
3. It needs a pinned appearance (`FENTON_APPEARANCE`) or animations on (`measuresAnimation` classes: motion and performance tests, which also must not pay for a resident app).
4. It sets any other launch variable (`FENTON_SKIP_INTRO=0`, `FENTON_BACKDROP_FIXTURE`, camera modes).
5. It tests launch itself: sign-in, intro, snapshot, cold start, push or Spotlight launches. Call `app.launch()` directly, never `startApp`.
6. It terminates or backgrounds the app on purpose (a resume cycle). A dead resident app is relaunched, but the test is about the process.
7. The gallery keeps state in a `static` or in the process (the Performance gallery seeds its log once per process; the Food delay variables). Such a gallery must not be reused until the static is keyed by generation.
8. The live-house journeys (`launchSignedIn`): the session and Keychain belong to the process.

Anything else that is wrong after a reset (a stale element, a sheet still up) is a defect in the reset: it falls back to a relaunch after 10 s, which `REUSE ... reused=N launched=M` in the log shows. Fix the cause, do not widen the timeout.

A fresh launch that comes up without the `uitest.generation` marker did not receive its launch environment, and `AppReuse.start` launches it once more (`REUSE <class>: the launch arrived without its environment`, counted as `withoutEnvironment=N`). That is Xcode's fault, not the app's: the first launch of a coverage batch's second `xcodebuild` invocation, right after Xcode's lazy reinstall, arrived with no `FENTON_*` variable at all in 5 of 5 runs, while every other launch got them (the app's Debug `UKLaunch variables:` log lists the names it received; 2026-11-04). Only one relaunch is made; a second miss fails in the test's own assertions. A count above zero outside that first launch is worth a look.

## Opted-in classes

Each class's launch helper goes through `startApp` (Food, whose `FoodJourneyTestCase` base is not a `JourneyTestCase`, calls `AppReuse.start` and ends the app in its own `class tearDown`). Tests that pass launch arguments (AX5) or `FENTON_APPEARANCE` relaunch by themselves through the launch signature, so they need no marker.

| Class | Reuses | Still relaunches, and why |
|---|---|---|
| Bedroom (pilot; `BedroomJourneyTestCase`, so the Tiles, Bed, Special Modes, Alarms, Wake Light, Wide Layout and Capture classes inherit the opt-in, one resident app per class) | every gallery launch | AX5 and appearance tests (signature) |
| Rooms | every gallery launch, including the capture test's room loop | AX5 (signature) |
| Climate | every gallery launch | AX5 (signature); the live test uses `launchSignedIn` |
| RoomDevices (`RoomDevicesJourneyTestCase`; Fan, Humidifier, Humidifier pose, Purifier, Grill and Capture classes inherit the opt-in, one resident app per class) | every gallery launch | AX5 and the appearance tests (signature); no `fresh: true` exceptions |
| Vacuum | every gallery launch | AX5 (signature) |
| Security | every gallery launch | the `testCaptureSecurity*` page, sheet, alert and garage captures (`fresh: true`: each starts from a clean gallery); AX5 (signature); `testSecurityTabSignedIn` is live |
| Inventory (`InventoryJourneyTestCase`; List, Row actions, Sheets, Editor, Scan and Host-covered classes inherit the opt-in, one resident app per class) | every gallery launch | the audits (`fresh: true`: the pages audit loop, the empty and error, sheet, editor and scan-step audits terminate the app between pages to keep the iPad simulator's backboardd alive); AX5 (signature); the live test (`InventoryLiveJourneyTests`) |
| Food (`FoodJourneyTestCase`; Hub, Suggestions, Recipes, Recipe sheets, Recipe detail and Wide layout classes inherit the opt-in, one resident app per class) | every `launch(...)` and the TabView test | `testLaunchRouteHubSheetSwitchesTabs` (tests the `FENTON_OPEN_FOOD` launch route); `launchLive` tests (token, Keychain); AX5 (signature) |
| Light-appearance sheets (Security, Climate, MediaRemote, RoomDevice, Bed, Vacuum, QuickLinks, Weather, Lights) | every `gallery(...)` launch of `LightAppearanceJourneyTestCase`; the pinned light appearance is part of the launch signature, so the class keeps one light process and an AX5 process | `LightAppearanceSystemJourneyTests` (`fresh: true`: it sets the simulator's appearance and terminates); the Account and Lights-overview tests (live, `launchSignedIn`); AX5 (signature) |
| ModalSizing | every gallery launch (the sheet kind is `FENTON_GALLERY_MODAL_OPEN`) | AX5 (signature); the light and dark appearance tests (each pinned appearance is its own resident app) |
| FloatingActions | every gallery launch | AX5 (signature) |
| BackdropBlur (Settings gallery; fixture and blur are `FENTON_GALLERY_BACKDROP_*`) | every gallery launch at the default AX size | AX5 and Reduce Transparency (signature) |
| DirectionG | every gallery launch (the order is `FENTON_GALLERY_DIRECTION_G_ORDER`) | AX5 (signature) |
| SheetBottomGap (camera viewer gallery: stream is `FENTON_GALLERY_CAMERA_VIEWER_OPEN`) | every gallery launch; a reset under `FENTON_SHEETFIT_RESET=1` clears the remembered sheet heights, so each test is a first presentation | none |
| CameraViewerFit (camera viewer gallery: stream is `FENTON_GALLERY_CAMERA_VIEWER_OPEN`) | every gallery launch at the default size, with and without `FENTON_SHEETFIT_RESET=1` (its own resident app; a reset under it clears the sheet memory) | AX5 (signature) |
| LightSheetCapture (the capture helper pins light or dark with `FENTON_GALLERY_APPEARANCE`, a gallery setting, so light and dark are resets of one app) | every capture except Quick Links | `testQuickLinksSheet` (`fresh: true`: a reused app drew its dark sheet's grab handle black in the full-class run, found by pixel comparison; cause not found) |
| ScrollKeepsMoving (Chores gallery, 12 chores; all settings are `FENTON_GALLERY_*`) | the default-size drag test after the first one | the AX5 tests (launch argument, rule 1); the swipe test follows an AX5 launch, so it launches |
| AdaptiveLayout (the Gate-run gallery tests: Chores, rooms, Security, Food; the signed-in tests are live and skipped by Gate) | every gallery launch | the signed-in tests use `launchSignedIn` (live house, rule 8) and AX5 (signature) |
| ChipAlignment | every gallery launch (orientation is device state; each test sets its pose) | none |
| ThermostatDial | every gallery launch | AX5 (signature) |
| Chores (`ChoresJourneyTestCase`; Check and undo, Delete, List layout, Page, Sub-pages, Swipe, Task form, Todo sheets and Wide layout classes inherit the opt-in, one resident app per class) | every gallery `launch(...)`, including a test's second launch (empty landing after an empty page) | AX5 (signature); the reduce-motion check-undo test (`FENTON_SYSTEM_SETTINGS` is its own resident app, and its teardown's `system-accessibility` launch kills it, so the next test relaunches); `ChoresLiveJourneyTests` is live (`launchSignedIn`). The gallery builds its fixtures, service and model per gallery (no statics, defaults or files), so the only `fresh: true` launches are the four tests that type into a text field (`testCreatingATask`, `testEditingATaskLoadsAndSaves`, `testAdminTodoRenamesAndCompletesWithItsScript`, `testGroceriesAddAndCheckOff`): in a reset app the page went blank when the keyboard came up, or the sheet's field never appeared (accessibility tree empty but for the reset marker; fine in a fresh process; intermittent, cause not found, 2026-11-02); `ChoresWideLayoutJourneyTests` types too but is iPad-only and was not run |
| Weather (`WeatherJourneyTests`) | every gallery `launch(...)` | AX5 (signature: the AX5 tests and the audits' AX5 pages); the gallery builds its store, forecast caller and fixtures per gallery, so no `fresh: true` exceptions. After a reset the card is in the tree before the final layout, so an absence check waits for `home.weather.hour.0` first |
| MediaRemote (`MediaRemoteJourneyTests`) | every gallery `launch(...)`, the sheet-is-live test and the capture helper | AX5 (signature: the audits' AX5 page and `testLargestTextKeepsControlsReachable`); the gallery builds its fixtures and recording caller per gallery, so no `fresh: true` exceptions |
| Summary (`SummaryJourneyTests`) | every gallery `launch(...)` | AX5 (signature: the AX5 tests and the audits' AX5 pages) and the light-appearance tests (`FENTON_APPEARANCE` is part of the signature, so they keep one light resident app); the gallery builds its fixtures and recording service per gallery, so no `fresh: true` exceptions |
| Home pages (`HomePagesJourneyTests`: Media, Custom Lights, Sprinklers) | every gallery `launch(...)` | AX5 (signature: the audits' AX5 relaunch); iPad landscape poses reset in the same process; the gallery builds its fixtures and recording caller per gallery, so no `fresh: true` exceptions |
| Weather header (`WeatherHeaderJourneyTests`) | every launch at Large, xxxLarge and AX2: the size is set in place after the reset (`AppReuse.setTextSize`), so the launch has no argument; the audits use the system's own size | AX5 tests (launch argument, fresh); Reduce Motion (signature); no `fresh: true` exceptions |
| Tile layouts (`TileLayoutJourneyTests`) | every gallery launch; the Direction G gallery takes its arrangement from `FENTON_GALLERY_DIRECTION_G_ORDER` / `_LAYOUT` (a launch argument cannot be reset) | AX5 (launch argument, fresh); no `fresh: true` exceptions |
| Live Activity cards (`LiveActivityJourneyTests`) | every gallery `launch(...)` (the scenario is `FENTON_GALLERY_SCENARIO`) | AX5 (launch argument, fresh: the nine AX5 card tests and the audits' AX5 page); `testRealActivitiesShowOnTheLockScreen` (`app.launch()`, calls `AppReuse.willLaunchOutside()` first: real ActivityKit, device lock, SpringBoard); no `fresh: true` exceptions |
| Header buttons (`HeaderButtonsJourneyTests`) | every gallery launch (state is `FENTON_GALLERY_*`, including the reconnecting and offline tests' second state and the captures' backdrop/plain pair) | AX5 (launch argument, fresh); no `fresh: true` exceptions. `UKShellHeaderGallery` reads the environment per gallery, not once per process |
| Notification settings (`NotificationSettingsJourneyTests`) | every gallery launch (a scripted push system: no system permission or Settings app is touched) | AX5 (launch argument, fresh: the audit tests' large-text shot); no `fresh: true` exceptions. After a reset the state's own row is waited for before an absence is asserted |
| Tiles round 2 (`TilesRound2JourneyTests`) | every default-signature gallery launch (Quick Links, Rooms grid, Direction G finish and sheet; the options are `FENTON_GALLERY_DIRECTION_G_*`) | AX5 (launch argument, fresh); the light-appearance tests and the Reduce Transparency / Increase Contrast launches (signatures: their own resident apps); no `fresh: true` exceptions |
| Setup (`SetupJourneyTests`: the Setup sheet fixture; not the real permission or sign-in flow) | every gallery launch (the scripted system and coordinators are built per gallery) | AX5 (launch argument, fresh: the audits' second check); no `fresh: true` exceptions |
| Vacation (`VacationJourneyTestCase`; Chooser, Mode, Confirm, Solo Trip and Capture classes inherit the opt-in, one resident app per class) | every gallery `launch(...)` (scenario `FENTON_GALLERY_AWAY`, `FENTON_GALLERY_CLEAN`); the gallery builds its store, fixture house and recorder per gallery, so no `fresh: true` exceptions. The old "does not use app reuse" note had no technical reason behind it (commit d6036a57 only made the app keep a pushed page, which a reset rebuilds) | AX5 (launch argument, fresh: the AX5 tests and the audits' AX5 page); `VacationLiveJourneyTests` is live (`launchSignedIn`) |
| Page title (`PageTitleJourneyTests`) | every gallery launch (the shell-header gallery reads `FENTON_GALLERY_*` per use) | AX5 (launch argument, fresh) and Reduce Motion (signature); no `fresh: true` exceptions |
| Settings tab (`SettingsTabJourneyTests`: the settings gallery on fixtures, no sign-in) | every gallery launch (`FENTON_GALLERY_CLEAN`) | AX5 (launch argument, fresh: the audit's second check); no `fresh: true` exceptions; the signed-in Settings journeys are not this class |
| Household settings (`HouseholdSettingsJourneyTests`) | every gallery `launch(...)` (page is `FENTON_GALLERY_HOUSEHOLD`, `FENTON_GALLERY_UNAVAILABLE` and `_CLEAN` are gallery settings); the gallery builds its store and recording caller per gallery, so no `fresh: true` exceptions | AX5 (launch argument, fresh: the audits' second check); the `testLive*` tests are live (`launchSignedIn`, rule 8) and Gate skips them and the captures |
| Home | none | the whole class is live-house (`launchSignedIn`, rule 8), plus a cold relaunch and a backgrounding test |

A `fresh: true` launch goes through `app.launch()` directly. A new test in these classes reuses by default; give it `fresh: true` (or `app.launch()`) only for a reason in the list above.

## The audit's AX5 check runs in place

`FentonHomeApp.audit` with an `ax5Page` needs the audited page at AX5 when it has a Dynamic Type or text-clipped issue to decide. In a reuse launch it no longer relaunches: `AppReuse.enlargeInPlace` writes `<sequence>\n<size>` to the request directory's `textSize` file, and the app (`GalleryReset.setTextSize`, Debug only) puts a `preferredContentSizeCategory` trait override on every window scene, which UIKit and SwiftUI follow live as they do a Control Center change, then acknowledges in `textSize.done`. The page just audited, with its sheet and scroll position, is measured at AX5, saving the relaunch and the reopen (about 28 s of a 68 s Food Filter audit, 2026-10-30). The next reset removes the override. The override lives in the app's process only, so it cannot leak into another app or test on a shared simulator.

- It falls back to the `ax5Page` relaunch when the launch has no request directory (reuse off, `launchSignedIn`, `app.launch()` tests), the app is not in the foreground, or no acknowledgement comes within 5 s (`AX5 in place not acknowledged` in the log).
- `TEST_RUNNER_FENTON_UITEST_AX5_RELAUNCH=1` forces the relaunch, to compare the two.
- In-place evidence only waives. When it would leave an issue open, the audit measures a relaunch at AX5 and that decides, as before (the Climate Tracking tab's labels did not grow after a live change but did at an AX5 launch, 2026-10-31).
- The test after an in-place audit relaunches instead of resetting: the Security disarm alert outlived the reset and took the next test's taps (2026-10-31).
- The sheet height memories key on the text size (`LargeDetent.textSize()`): the app's, or the window's marked `|override` when an in-place switch makes them differ. A sheet open during the switch keeps its height, so what it learns is filed apart; filed under plain AX5 it opened the Food hub too short at the next AX5 launch on that simulator (2026-10-31). In the shipping app the two sizes are always the same, so the key is unchanged.
- Unlike a relaunch, a sheet stays at the detent it opened with; its text grows inside it and the measuring loop scrolls to find it.

## Where a reused journey's time goes (2026-11-02, Chores sub-pages)

- **`XCUIAccessibilityAuditIssue.element` costs about 2.1 s when it cannot resolve** (it retries twice, 1 s apiece, then returns nil). One `ChoresSubPages` run had 10 such issues ("Contrast failed for UILabel", later accepted as element-less) = 21 s of the 62 s; a resolvable element costs 20-30 ms. The retry cannot be shortened from a test, and the verdict for an element-less issue differs from a resolved one, so the read is not skipped. Everything the audit does with a resolved element is already one snapshot.
- **The `uitest.generation` wait is not the cost it looks like.** The log's `Checking existence of "uitest.generation"` lines are 6 to 7 checks per reset at about 75 ms: 0.4 s of that is the deliberate blank interval (sheets and alerts gone), the rest check latency. A reset is about 0.55 s. Do not shorten `blankInterval` without proving a sheet and an alert are dismissed (the Security disarm alert).
- The other `Checking existence` lines (`TabBar`, `Done`, `Close`, `Cancel`, `scan.back`, `login.submit`) are the element-less branch of `isSystemDrawn`, 20-40 ms each, not reset waits.

## Not a reuse effect: the iPad Chores audit's "+ Add Task" (2026-11-03)

`ChoresPageJourneyTests.testChoresTabPassesAccessibilityAudit` failed on iPad one run in five with an element-less "Potentially inaccessible text" issue. It is not reuse, not the audit's snapshot reads and not a leaked override: it failed on a fresh launch too and passed alone, as a class, in Smoke and with `TEST_RUNNER_FENTON_UITEST_REUSE=0`. Text recognition read the floating bar as "+ Add Task" on the failing runs (plus glyph included), which matches no label, so the iPad status-bar rule (all unmatched strings inside the status bar band) rejected it. `unlabelledTexts` strips a leading "+" now. A flake that moves with the recognised string, not with the process, is a recognition-normalisation issue.

## Process-level state that survives a reset

A reset replaces the `FENTON_GALLERY*` environment and rebuilds the gallery, so anything a gallery keeps in a `static`, a singleton, defaults or a file outlives it. Checked for the opted-in galleries (2026-10-30):

- **`RoomsFixtures.states` (fixed).** It was a `static let` that read `FENTON_GALLERY_SCENARIO` once and stamped the fan timer ("Off in 12:34") from the clock once. Reused, the `fan-unavailable` scenario would have stuck or been missed, and the countdown would have aged. It is now a computed `static var`, built on every read.
- **Sheet memory (`SheetFitMemory`, `SheetChromeMemory`).** In-process tables mirrored to `UserDefaults`; a normal launch already starts from the disk copy, so reuse changes nothing, except for a test that sets `FENTON_SHEETFIT_RESET=1` to see a first presentation. Such a test is not in these classes; if one is added it must relaunch every time (that variable is outside the gallery prefix, so it is its own resident app, but the memory still warms inside it).
- **Immutable fixture statics** (`RoomDeviceFixture.grillStates`/`rules`, `MediaRemoteFixtures.states`, `SecurityFixtures.states`, `VacuumFixtures.services`, `FoodFixtures.catalog`): no environment, clock or mutation, so safe.
- **Food delay and mode variables** are read in `FoodGallery.init`, per gallery, so a reset applies them.
- **Inventory:** the gallery owns its `EverShelfFixtureServer` and `InventoryModels`; the `InventoryModels.shared(for:)` registry is keyed by a live connection and is not used by the gallery.
- **Not reset, and harmless here:** `ImagePipeline.shared` (Rooms forces `FENTON_GALLERY_OFFLINE=1`, so no remote artwork loads), `TileTextMeasure`'s measurement cache (pure).
- **Still open:** the Performance gallery's once-per-process log seeding. Performance classes are not opted in.

## Rolling out

Convert one class at a time: replace the launch helper's `app.launch()` with `startApp(app)`, run the class with and without reuse, and compare. Keep a test that is *about* launch on `app.launch()`. A class whose tests mostly relaunch at AX5 gains little.
