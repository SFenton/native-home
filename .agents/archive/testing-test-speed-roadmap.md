# Test speed roadmap

Status as of 2026-11-04. This file is the backlog of ideas for making tests faster, written for whoever picks them up next. Each proposal says:

- why it matters, with evidence from our own logs;
- what to try, step by step, and which files to touch;
- how to measure it, and the guardrails that keep it from weakening a test;
- the gain and effort, and any decision that needs the owner;
- sources: Apple's guidance first, then other projects.

What's already done, with per-class numbers, is in [journey-speed](journey-speed.md). Change this file when a proposal lands or is rejected, and move its result into journey-speed.

## Contents

1. [Where we are](#1-where-we-are)
2. [Where the time goes now](#2-where-the-time-goes-now)
3. Proposals, best first:
   - [P1 A resident AX5 app (the AX5 reset leak)](#p1-a-resident-ax5-app-the-ax5-reset-leak)
   - [P2 A cheaper cold launch](#p2-a-cheaper-cold-launch)
   - [P3 Fewer explicit terminates](#p3-fewer-explicit-terminates)
   - [P4 Reuse for the Performance gallery](#p4-reuse-for-the-performance-gallery)
   - [P5 Typed element queries](#p5-typed-element-queries)
   - [P6 Idle waits: app timers and animation speed](#p6-idle-waits-app-timers-and-animation-speed)
   - [P7 The remaining fixed sleeps](#p7-the-remaining-fixed-sleeps)
   - [P8 The Chores typing tests under reuse](#p8-the-chores-typing-tests-under-reuse)
   - [P9 Compilation caching (owner decision)](#p9-compilation-caching-owner-decision)
   - [P10 Tooling and capacity hygiene](#p10-tooling-and-capacity-hygiene)
   - [P11 Hardware](#p11-hardware)
4. [Tried or rejected](#4-tried-or-rejected)
5. [How to measure](#5-how-to-measure)
6. [Sources](#6-sources)

## 1. Where we are

**The journey speed rollout is finished (2026-11-04).** Every UI-test class has a row in [journey-speed](journey-speed.md). The rows with a measured baseline went from 156 to 111 minutes of iPhone test time (1.41×). The rollout used three levers:

- **App reuse.** One resident app per class and launch signature, reset through a request file. See [app-reuse](app-reuse.md), `apple/Apps/iOSUITests/AppReuse.swift` and `GalleryReset`.
- **One accessibility snapshot per element.**
  - `reveal` helpers take one snapshot per drag and stop after three drags that don't move the element.
  - The shared `isReachable(_:)` in `JourneyTestCase.swift`.
  - `ElementFacts` reads in the audit.
- **Waits instead of sleeps,** wherever a sleep wasn't asserting that nothing happens.

**Already in place, so don't redo it:**

- **Builds:**
  - Journeys don't gather coverage.
  - There is one build per tree, shared through the products cache (`tools/products_cache.py`).
- **Test selection and runs:**
  - Test tiers and plans (`apple/TestPlans/*.xctestplan`), affected-only runs (`tools/affected_tests.py`) and the tier guard.
  - Families run in parallel in the nightly.
  - Hang-proofing (`tools/xc_watch.py`).
- **App-side test support:**
  - Layer animations run at 10× (`UKAppDelegate.uiTestAnimationSpeed`).
  - The AX5 audit check runs in place (`AppReuse.enlargeInPlace`).
  - Text sizes up to AX2 are set in place (`AppReuse.setTextSize`).
  - A DEBUG background-grace switch (`FENTON_BACKGROUND_GRACE_SECONDS`).

**The full host `swift test` is not a target.** It measured 20 s for 2,678 tests on 2026-11-04. The UIKit port moved the hosted-window suites out of it, so moving suites off `@MainActor` would save less than run-to-run noise (journey-speed, "Host swift test"). Its cost now is the build: 168 s with a warm cache.

## 2. Where the time goes now

The last full attribution was taken before the rollout, from 62 logs written after 2026-10-31, 27.4 h in total. Every XCUITest step (`t = …s`) is charged until the next step:

| Step | Share | Count | Average |
|---|---|---|---|
| `Checking existence of …` | 29.6% | 176,821 | 165 ms |
| `Find the …` | 29.4% | 189,386 | 153 ms |
| `Wait for … to idle` | 15.4% | 32,029 | 475 ms |
| `Setting up automation session` (each launch) | 14.5% | 5,166 | 2.8 s |
| `Terminate` | 6.0% | 4,611 | 1.3 s |
| The rest | ~5% | | |

The rollout cut the first two rows (lookups) and the launch rows sharply. **Re-run the attribution script in [section 5](#5-how-to-measure) over a fresh nightly before choosing the next proposal.** The rows in journey-speed show where the remaining time sits:

- **AX5 relaunches and the audits they serve.** One audit that ends the app takes 75–90 s; for example, `SecurityJourneyTests` spends 162 s of 237 s in two audits. This is the largest cost left in almost every family. See P1.
- **Launches that must stay.** These are launch, sign-in, live-house, Spotlight, push and resume tests, and anything with a launch argument. See P2 and P3.
- **Reveal drags.** These are deliberately slow drags (low velocity, a short hold) so the scroll doesn't coast past the target. See P6.

## 3. Proposals

Every proposal follows the same rules as the rollout:

- Never weaken what a test checks: no narrower audits, no waivers, no skipped assertions.
- Never change the default animation speed (10) without the owner.
- A change the owner would see, or one that changes VoiceOver, is recorded as an open item, not made.
- A/B every change on the pinned simulator, alternating baseline and lane runs ([section 5](#5-how-to-measure)).
- Write the result as a row in journey-speed.

### P1. A resident AX5 app (the AX5 reset leak)

**Why.** AX5 is the largest text size, and our accessibility rules need every page checked at it (44 pt targets, no clipping, [accessibility](accessibility.md)). Today an AX5 test can't share the class's resident app:

- A test that needs AX5 passes `FentonHomeApp.ax5` as a launch argument. That changes the launch signature, so `AppReuse.start` launches a fresh process (rule 1 in [app-reuse](app-reuse.md)).
- The audits already switch the running app to AX5 in place (`AppReuse.enlargeInPlace`, which saved about 28 s on a 68 s Food audit). Even so, the class's next test relaunches, because `enlargeInPlace` puts the app in the `enlarged` set.
- The reason for both is one finding from 2026-10-31: a reset inside an app launched at AX5 left the Food hub and recipe grid failing their AX5 audits. The leaking state was never found.

Each AX5 relaunch costs about 4 s of XCTest launch and terminate steps, plus a cold start of about 6.6 s ([app-reuse](app-reuse.md)), plus the next test's relaunch. AX5 is used in 165 places in the journeys.

**What to try.**

1. **Reproduce the leak in one class.** Use Food: `FoodJourneyTestCase`, hub and recipe grid.
   - Launch at default size, run an AX5 audit in place, reset, then run the same AX5 audit again in place. Compare with a fresh AX5 launch.
   - Capture `app.debugDescription` and the audit issues from both, and diff them.
   - The difference is the leaking state.
2. **Look in the usual places first:**
   - Cached measurements keyed by size class but not by content size, such as `UKScrollFit`, the column titles and the tile prototypes ("prototype once per width" in `UKPerformanceGallery` is one example of the pattern).
   - `UIFontMetrics` results stored in a `static`.
   - Collection or table layouts that don't invalidate on `traitCollectionDidChange` or on `registerForTraitChanges`.
   - `UIContentSizeCategory` read once at launch, not observed.
   - A trait override left on a window scene that the reset didn't remove (`GalleryReset.setTextSize(nil)` removes it from `connectedScenes` only).
   - Apple's guidance is that views must update when `preferredContentSizeCategory` changes; [Scaling fonts automatically](https://developer.apple.com/documentation/uikit/scaling-fonts-automatically) and the `UITraitCollection` / `registerForTraitChanges` docs cover this. Any view that only reads the size at creation is the leak, and also a real bug: a person who changes text size in Control Center hits the same path. That makes the fix product work as well as test work, so propose-first applies if it changes anything visible.
3. **Once the leak is fixed, change the reuse rules:**
   - Let `enlargeInPlace` stop adding to `enlarged`, so the next reset (back to the launch's size) carries on in the same process.
   - Move AX5 launches onto `AppReuse.setTextSize(app, FentonHomeApp.ax5[1])`, the way `WeatherHeaderJourneyTests` already does for Large, xxxLarge and AX2, instead of a launch argument. AX5 then no longer changes the launch signature.
   - Update rule 1 in app-reuse.md and the opted-in table.
4. **Keep an escape hatch.** `FENTON_UITEST_AX5_RELAUNCH=1` already forces the old relaunch, so a regression can be bisected.

**How to measure.**

- First, Food and Summary (both heavy on AX5), alternating three base and three lane runs. Then every family on the Gate plan.
- Check that each AX5 audit gives the **same verdict** in place as in a fresh launch. Run the class once with `FENTON_UITEST_AX5_RELAUNCH=1` and once without, and diff the audit issues.

**Gain.** *Estimate:* one AX5 relaunch plus one follow-on relaunch saved per AX5 test, about 10–20 s each. Families with several audits save the most: Security, Inventory, Food, Summary, LightAppearance and Bedroom. On the order of 10–20% of Gate time. **Effort:** a debugging task, unknown length; probably one day to find the state and less to change the rules. **Risk:** a missed leak gives a wrong audit verdict. The verdict diff above is the guardrail.

**Sources.**

- Apple, [Performing accessibility audits for your app](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app).
- WWDC23, [Perform accessibility audits for your app](https://developer.apple.com/videos/play/wwdc2023/10035/), which notes that an audit covers only what is on screen.
- `UITraitCollection.preferredContentSizeCategory`: [docs](https://developer.apple.com/documentation/uikit/uitraitcollection/preferredcontentsizecategory).
- `UIMutableTraits.preferredContentSizeCategory` (what `traitOverrides` sets): [docs](https://developer.apple.com/documentation/uikit/uimutabletraits-8l00o/preferredcontentsizecategory).
- The `-UIPreferredContentSizeCategoryName` launch argument is community practice, not documented by Apple ([Appetize guide](https://docs.appetize.io/guides-and-samples/test-accessibility-font-sizes)). That's one more reason to prefer the in-process trait override.

### P2. A cheaper cold launch

**Why.** The launches that remain are the ones that must stay:

- launch, sign-in, intro, Spotlight, push, resume and live-house tests (relaunch rules 5–8);
- tests with a launch argument;
- the first test of every class.

[app-reuse](app-reuse.md) measured about 6.6 s per cold gallery launch. **3.3 s of that is from process start to `App.init`**: dyld loading, static initialisers and Swift metadata in the Debug binary. On top of that, XCTest adds about 2.8 s for "Setting up automation session" and 1.3 s for "Terminate".

**What to try.**

1. **Profile before changing anything.** Record a Debug simulator launch with Instruments' **App Launch** template. From the command line, `xcrun xctrace record --template 'App Launch' --device <sim UDID> --launch -- <path to .app>`; check the flags against `xcrun xctrace help record` on the current Xcode. Read the App Life Cycle lane: process initialization, UIKit initialization, initial scene rendering, first frame. Compare a Release build, to separate Debug-only costs.
2. **If dyld dominates:** count the dynamic frameworks the Debug app loads (`otool -L` on the app binary and its `Frameworks/`). Apple's levers:
   - fewer dynamic libraries;
   - **mergeable libraries**, which give Debug builds static-like launch while keeping dynamic linking for fast rebuilds;
   - static linking where a package allows it.
   SwiftPM products default to static unless declared `.dynamic`, so check which ones are dynamic and why.
3. **If our own startup dominates** (`didFinishLaunching` or the first scene): skip non-essential startup when the gallery or a UI test launches the app. XCTest doesn't start a test until `didFinishLaunching` returns (WWDC18). Candidates are telemetry setup, warm caches, and widget or Live Activity sync that a gallery launch never uses. Guard each with the existing gallery launch environment, never with a test-only code path that changes behaviour under test.
4. **XCTest's own 2.8 s:** there is no public lever for automation-session setup. The only way to avoid paying it is to launch less, which is P1 and P3.

**How to measure.** Launch-time telemetry already exists (`LaunchPerformanceTests` and the Perf plan, [performance](performance.md)). Add the Instruments trace to the PR, and A/B a launch-heavy class such as `SystemSettingsJourneyTests`, which is all launches.

**Gain.** *Estimate:* every 1 s off the cold start saves about 1 s per remaining launch. The Gate run still makes hundreds of launches per family. Users see the cold start too, so a Release-side win helps the product. **Effort:** half a day to profile; the fix depends on what the profile shows. **Risk:** low for profiling. Startup skips must not change what a test checks.

**Sources.**

- Apple, [Reducing your app's launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time). This covers the App Launch template, the life-cycle phases, and keeping the main thread free during launch.
- WWDC19, [Optimizing App Launch](https://developer.apple.com/videos/play/wwdc2019/423/) ([notes](https://wwdcnotes.com/notes/wwdc19/423)).
- WWDC22, [Link fast: Improve build and launch times](https://developer.apple.com/videos/play/wwdc2022/110362/).
- WWDC23, [Meet mergeable libraries](https://developer.apple.com/videos/play/wwdc2023/10268/).
- WWDC18, [Testing Tips & Tricks](https://developer.apple.com/videos/play/wwdc2018/417/), on XCTest waiting for `didFinishLaunching` and launch-argument setup for tests.

### P3. Fewer explicit terminates

**Why.** `Terminate` was 6% of journey time: 4,611 steps at 1.3 s each. The journeys still make **34 explicit `terminate()` calls in 21 files** (2026-11-04). Many of them come just before a `launch()`, which ends the old process anyway. `AppReuse` also ends the resident app in each class's `tearDown`.

**What to try.**

1. List each call: `grep -n "\.terminate()" apple/Apps/iOSUITests/*.swift`. Sort them into three groups:
   - **Needed:** a resume cycle; restoring simulator settings (`SystemSettingsJourneyTests`); keeping the iPad simulator's backboardd alive between Inventory audits; a Live Activity on the lock screen.
   - **Redundant:** immediately followed by `launch()` of the same bundle.
   - **Teardown-only:** the next class launches anyway.
2. Remove the redundant ones. For teardown-only calls, check that the next class's first launch still starts clean. `launch()` always replaces a running instance, so it should.
3. For the class-level teardown in `AppReuse`, consider leaving the last resident app running when the next class has the same launch signature. That's an extension of `dropResidents()`. Measure before keeping it: one class's state must never reach another.

**Gain.** About 1.3 s per removed call, times its runs per family. Small but certain. **Effort:** an hour or two. **Risk:** low, provided that a test checking the app *closes* keeps its terminate.

**Sources.** Apple, [`XCUIApplication.terminate()`](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/terminate()) and [`launch()`](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/launch()). `launch()` terminates any running instance first.

### P4. Reuse for the Performance gallery

**Why.** Relaunch rule 7 says a gallery that keeps state in a `static`, or anywhere in the process, must not be reused. The Performance gallery seeds its log once per process, and the Food delay variables are the other named case. That keeps the performance classes that don't measure animation on fresh launches.

**What to try.**

1. **Confirm the state is still process-wide.** Check `apple/Sources/HassUI/UIKitPort/Gallery/UKPerformanceGallery.swift` and its telemetry log, and list every `static var` and `nonisolated(unsafe) static`.
2. **Key that state by `GalleryReset`'s generation counter,** the same mechanism the other galleries use, so a reset reseeds it.
3. Opt in only the Perf classes that **don't** measure animation or launch. `measuresAnimation` classes stay on real-speed, fresh launches by rule 3.

**Gain.** Small. These are Perf-plan classes, which run nightly. **Effort:** small. **Risk:** a perf metric changing because the process is warm. A/B the metric itself, not just the run time.

### P5. Typed element queries

**Why.** The most common lookup in the logs was ``Checking existence of `"ID" Any` ``, about 83k of them. It comes from the shared helper `element(_:in:)` (`JourneyTestCase.swift:195`, `FoodJourneyTestCase.swift:68`), which is `app.descendants(matching: .any)[id].firstMatch`. There are 168 `descendants(matching: .any)` sites in the journeys. A query on type `.any` makes XCTest match every node. A typed query (`app.buttons[id]`) narrows the search, and `firstMatch` stops at the first hit.

**What to try.**

1. Add `button(_:)`, `staticText(_:)`, `other(_:)` and `cell(_:)` helpers next to `element(_:in:)` in `JourneyTestCase`, each `app.<type>[id].firstMatch`.
2. Use them where the element's type is known and stable, starting with the classes that make the most lookups (count them from a fresh attribution run). Leave `.any` wherever the type differs between iPhone, Duo and iPad, or between UIKit versions. A wrong type fails the test, which is safe but noisy.
3. A/B one heavy class before sweeping: sweep the pattern only once it has proven itself.

**Gain.** *Uncertain.* Snapshot reads already cut lookup counts, and much of a lookup's cost is the IPC snapshot itself, not the matching. One open-source project went from about 25 s to 0.3 s on one fill by leaving `.any`, but that was a pathological tree. Expect a few percent here. **Effort:** small per helper; the sweep is medium. **Risk:** low.

**Sources.**

- Apple, [`firstMatch`](https://developer.apple.com/documentation/xcuiautomation/xcuielementtypequeryprovider/firstmatch): it stops traversing as soon as it finds a match. Contrast [`element`](https://developer.apple.com/documentation/xcuiautomation/xcuielementquery/element), which checks for uniqueness.
- WWDC17, [What's New in Testing](https://developer.apple.com/videos/play/wwdc2017/409/), where `firstMatch` was introduced along with advice to narrow queries.
- [`XCUIElementSnapshotProviding.snapshot()`](https://developer.apple.com/documentation/xcuiautomation/xcuielementsnapshotproviding/snapshot()) and [`XCUIElementSnapshot`](https://developer.apple.com/documentation/xcuiautomation/xcuielementsnapshot), the read-many pattern the rollout used.
- [callstack/agent-device#632](https://github.com/callstack/agent-device/pull/632), the typed-query fix.
- The [Appium XCUITest driver's element attributes](https://appium.github.io/appium-xcuitest-driver/latest/reference/element-attributes/), on why `isHittable` is the expensive read.

### P6. Idle waits: app timers and animation speed

**Why.** After every tap, swipe or launch, XCUITest waits for the app to go idle: no animation running and the main run loop quiet. That was 15% of journey time: 32k waits averaging 475 ms. Layers already run at 10× (`window.layer.speed`, set in `UKAppDelegate.uiTestAnimationSpeed`, override `FENTON_UITEST_ANIMATION_SPEED`).

**What to try.**

1. **Wall-clock timers in the app.** `layer.speed` speeds up Core Animation, not `Task.sleep`, `DispatchQueue.asyncAfter`, `Timer` or debounce delays. Find the ones that hold off idleness after a tap: spinner thresholds, toast lifetimes, debounced saves, the reconnect chip, pending-value bars. One way is to grep for `Task.sleep`, `asyncAfter` and `Timer.scheduledTimer` under `apple/Sources/HassUI/UIKitPort`. The other is to read the slowest `Wait for … to idle` steps in a log and match them to what the test just did.
   - A delay that isn't what the test checks can get a DEBUG launch override, following the `FENTON_GALLERY_*_DELAY_MS` and `FENTON_BACKGROUND_GRACE_SECONDS` pattern.
   - Earlier candidates, from the Feedback animations-idle stall: `UKPendingValueBar.swift:62`, `UKArcSpinnerView.swift:114`, `UKWeatherBackdrop.swift:173` and `UKTickerLabel.swift:313`. A repeating animation that never ends also costs CPU and battery for users, so check whether any of these should stop when nothing changes.
2. **Animation speed above 10× (owner decision).** EarlGrey and Chromium's iOS tests run at 100×. PSPDFKit used 100 on the key window, and reported that very high values such as 10000 broke things. We chose 10 because an iPhone sheet's drag settles through an animation.
   - The proposal: an A/B of 10 against 30 against 100 on tap-heavy classes that have **no** sheet drags, through `FENTON_UITEST_ANIMATION_SPEED` (it already exists). Keep 10 for drag classes and real speed for `measuresAnimation` classes.
   - The pilot measured 30× on `ChoresSubPagesJourneyTests` ([journey-speed](journey-speed.md) first row).
   - **The owner said to keep the default at 10 (2026-11-02), so this needs their go-ahead.** Bring the A/B as the evidence.
3. **Reveal drag velocity and hold.** Reveal helpers drag slowly with a short hold, so the scroll stops where the finger lifts. Each drag is about 2.3 s (the Vacuum row). A/B a faster drag that still lands. That means checking the element ends up hittable, not just measuring time, in one family before sweeping.

**Gain.** *Estimate:* a third to a half of the idle-wait share on classes that can take it, plus whatever the timers hold. **Effort:** small to try. **Risk:** gestures that settle through animation, which is why 10× was chosen. Motion tests must stay at real speed.

**Sources.**

- Apple, [`CAMediaTiming.speed`](https://developer.apple.com/documentation/quartzcore/camediatiming/speed): local time runs faster than parent time when speed is above 1.
- [EarlGrey `GREYTestHelper`](https://google.github.io/EarlGrey/Classes/GREYTestHelper.html) (fast animation, 100×).
- [Chromium's EarlGrey test case interface](https://chromium.googlesource.com/chromium/src/+/891de733b481fff05ae0d07658b8e3bd4b622a6e/ios/testing/earl_grey/base_earl_grey_test_case_app_interface.h).
- PSPDFKit, [Running UI tests on iOS with ludicrous speed](https://engineered.at/articles/running-ui-tests-on-ios-with-ludicrous-speed).
- Jesse Squires, [Xcode UI testing reliability tips](https://www.jessesquires.com/blog/2021/03/17/xcode-ui-testing-reliability-tips/): speed animations up rather than turning them off.
- WWDC22, [Author fast and reliable tests for Xcode Cloud](https://developer.apple.com/videos/play/wwdc2022/110361/).

### P7. The remaining fixed sleeps

The rollout replaced the sleeps that could become waits. Each one left has a reason, and some can still go:

| Where | Sleep | Why it's there | Proposal | Gain |
|---|---|---|---|---|
| `ResumeCyclesJourneyTests` (Live) | `sleep(35)` in cycle 5 | Outlast the 30 s background grace so the socket drops | Launch with `FENTON_BACKGROUND_GRACE_SECONDS` about 10 and sleep about 13. **Keep the grace above the 4–8 s short-cycle absences**, so those cycles still keep the socket. `CameraJourneyTests` already does this (60 s became 5 s). | ~22 s a run (nightly) |
| `ResumeCyclesJourneyTests` | `sleep(8)`, `sleep(6)`, `sleep(4)`; census `usleep(1.2 s)` | Streams settle; the census probe refreshes every 0.5 s | Leave them. Waiting on census gauges would change what the test asserts. | — |
| `PushJourneyTests` (Live) | `sleep(4)` | The app runs the clear command | Wait on the banner or badge state, if the app exposes one | ~3 s |
| `NavigationPerformanceTests`, `ScrollSurfacesPerformanceTests` (Perf) | 10 s, 14 s before measuring | Wait for first states, weather and images | Wait on a ready signal instead: a telemetry mark or an accessibility value the gallery sets when its data is in. The settle must stay **outside** the measured window. | ~20 s (nightly) |
| `PerformanceJourneyTests`, `MotionJourneyTests` | 1 s before an audit; 1 s after a cancelled swipe | Wait for an animation with no observable end | Expose an animation-end signal in DEBUG (an accessibility value that flips when the transition completes) and wait on it | small |
| `ChoresSwipeJourneyTests` | `usleep(900_000)` | Asserts nothing happens after the app's 350/450 ms timers | Keep it; it asserts a negative | — |
| `FlingFrameRateControlTests` | 8 s head start, 2 s between flicks | Inside the measured window | Keep them | — |

**Rule:** the testing README's "no wall-clock budgets" ([README](README.md), "Order-independent tests"). A sleep is fine only to assert that nothing happens, or to wait out a real timer that is itself the subject of the test.

### P8. The Chores typing tests under reuse

**Why.** Four Chores tests type into a text field: `testCreatingATask`, `testEditingATaskLoadsAndSaves`, `testAdminTodoRenamesAndCompletesWithItsScript` and `testGroceriesAddAndCheckOff`. They launch fresh (`fresh: true`), because in a reset app the page went blank when the keyboard came up, or the sheet's field never appeared. The accessibility tree held only the reset marker. It was intermittent, and the cause wasn't found (2026-11-02, [app-reuse](app-reuse.md), Chores row).

**What to try.**

1. Reproduce it: reset, then focus a field, in a loop. Log `UIApplication.shared.connectedScenes` and each window's `isKeyWindow`, `rootViewController` and `isHidden` before and after `GalleryReset`'s blank interval.
2. Suspects:
   - the reset swaps the root view controller while the old one still owns first responder;
   - the keyboard's `UIInputSetHostView` window sits on the old scene;
   - `GalleryReset`'s blank view isn't removed when a keyboard window becomes key.
   Resign first responder (`endEditing(true)`) as the first step of a reset.
3. This may be a real app bug: a screen swap while the keyboard is up. If so, fix it in the app.

**Gain.** Four launches per run of the Chores family, about 10 s each, plus whatever other typing tests could then reuse. **Effort:** debugging, unknown. **Risk:** low.

### P9. Compilation caching (owner decision)

**The owner said no to shared build or compilation caches (2026-11-02).** This section records the option for when that changes.

**Why.** The products cache makes an unchanged tree free. But any edit under `apple/` changes the hash and forces a full `build-for-testing`: a 0.9 min median, 8 min at p90, and 84 misses in two days (late October). The host `swift test` is now 20 s of tests and 168 s of build. Most rebuilt trees differ from an existing build in a few files.

**Options.**

1. **The Xcode 26 compilation cache.** It is content-addressed per compile job and local only. Settings to try:
   - `COMPILATION_CACHE_ENABLE_CACHING=YES`;
   - `SWIFT_ENABLE_PREFIX_MAPPING=YES` and `CLANG_ENABLE_PREFIX_MAPPING=YES`, so absolute worktree paths don't split the cache;
   - one shared cache location (the setting name is *unverified*; Xcode's Settings has a Compilation Cache location).
   Explicitly built modules are required, and they're on by default in Xcode 26. The products-cache key already hashes build settings, so it would separate cached from uncached builds.
2. **SwiftPM compilation caching** (`--enable-build-caching`). It's experimental, merged in October 2026. The pitch reports 67–75% faster fully cached clean builds. Check that it works with `swift test` before relying on it.
3. **`COMPILER_INDEX_STORE_ENABLE=NO`** for command-line test builds, since nobody browses their index. This is community advice and *unverified*.

**How to measure.** Make two fresh worktrees from one commit and make a one-line edit in the second. Time `build-for-testing` there with and without the settings, and read the cache hit rate in the build log.

**Gain.** Mostly on p90 misses. *Estimate:* 8 min down to 3–5. Tuist measured 19–77% faster builds with the local cache, and AvdLee measured 5–14% on clean builds and 12–87% on incremental ones. **Risk:** low as a setting. The cache adds to disk pressure (see P10).

**Sources.**

- WWDC25, [What's new in Xcode](https://developer.apple.com/videos/play/wwdc2025/247/).
- [Xcode 26 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes).
- Swift forums, [shared compilation cache across machines](https://forums.swift.org/t/about-swift-shared-cache-across-machines/81850): caching is local only and needs prefix mapping; one report saw about 80% reuse across directories.
- SwiftPM: [PR #10246](https://github.com/swiftlang/swift-package-manager/pull/10246) and [the pitch](https://forums.swift.org/t/pitch-compilation-caching-support-in-swiftpm/88079).
- [Tuist on the Xcode cache](https://canary.tuist.dev/blog/2025/10/22/xcode-cache).
- [AvdLee, Xcode build optimisation](https://www.avanderlee.com/xcode/xcode-build-optimization-using-6-agent-skills/).
- [Bitrise compilation cache FAQ](https://docs.bitrise.io/en/bitrise-build-cache/build-cache-for-xcode/xcode-compilation-cache-faq.html): in the 26.0 beta, Swift package targets weren't cacheable yet.

### P10. Tooling and capacity hygiene

Problems the rollout hit that cost time without being test code:

| Problem | Seen | Proposal |
|---|---|---|
| **The disk filled.** The data volume reached 100% (405 MiB free) and a baseline compile failed with ENOSPC (2026-11-04). The biggest users were simulators (134 GB), session scratchpads (36 GB), the products cache (33 GB) and DerivedData (30 GB). | One lost run, plus a manual diagnosis | **(a)** Give the products cache a hard ceiling that also applies to entries in use. Its 8 GB cap exempts anything used in the last 2 h (`tools/products_cache.py` `IN_USE_SECONDS`), so busy days blow past it. Evict the oldest in-use entry when free disk falls below a floor. **(b)** Run `tools/ci_hygiene.py preflight --min-gb 15` at the top of `tools/ios_uitest.sh` and `tools/apple_coverage.sh`, so a run fails in seconds with a clear message instead of mid-compile. |
| **The turn-cap reminder miscounted** (history). The old context hook counted a subagent's tool calls into the parent transcript and applied the main-role cap. | Agents stopped mid-task | Removed in #269 with the session caps; nothing to fix. |
| **The mockup-hub guard false-positives.** `tools/hooks/mockup_hub_guard.py` blocks Stop for a session that never touched `.agents/design/mockups/`, because it counts mockup files in the primary checkout's diff against `origin/main` that changed after the session started, including other sessions' merges. | Dozens of blocked stops in one session | Count only files this session wrote: from its own worktree, or from the transcript's Edit and Write paths. Don't count the primary checkout's branch diff. |
| **bg_run gave a false PASS** when xcodebuild reported a different count than the tests run. | Fixed: `log_digest.py` now reports MISMATCH or FLAKY and `bg_run.py` exits 1 on MISMATCH | Keep it |

### P11. Hardware

From the 2026-11-02 estimate in the handoff report:

- Journeys are mostly lookups, which is CPU work over IPC. An M5 Max should run them **about 1.5–1.8×** faster, and builds **about 2.4×** (multi-core).
- With the queue gone, new hardware buys shorter runs, not more lanes, until lane counts rise.
- **Disk matters as much as CPU** (P10). Size it for the simulator pool per family, the products cache and DerivedData per tree. The 2026-11-04 incident filled a 1 TB volume.

## 4. Tried or rejected

| Idea | Why not | When |
|---|---|---|
| `UIView.setAnimationsEnabled(false)` | It broke sheet drags: an iPhone sheet's drag settles through an animation, so a swipe dismissed the sheet | 2026-10-30 |
| `XCUIApplication.open(URL)` for resets | About 5 s a test | 2026-10-31 |
| Parallel simulator clones (`-parallel-testing-enabled`, worker counts) | They cost CPU we don't have, fight devcap slots and warm-pool reuse, and Xcode 26.2 has a stale-clone bug ([forums 817089](https://developer.apple.com/forums/thread/817089)). Parallel families already gives the useful parallelism. | 2026-11-02 |
| `-parallelize-tests-among-destinations` | The three families aren't interchangeable; every journey runs per family by rule | 2026-11-02 |
| Bluepill, Tuist or Bazel migrations, remote cache servers | Built for CI fleets; a large migration for one Mac | 2026-11-02 |
| `-retry-tests-on-failure` | Costs time; hides the flakiness the health rules want fixed | 2026-11-02 |
| `swift test --parallel` / `--num-workers` | XCTest only; our host tests are Swift Testing | 2026-11-02 |
| Moving host suites off `@MainActor` | The host run is 20 s; the saving is below noise | 2026-11-04 |
| Moving journeys to snapshot tests wholesale | The host-covered rule already moves what a host test can carry; snapshot runtimes vary widely ([Bitrise report](https://discuss.bitrise.io/t/snapshot-unit-testing-bad-performance-up-to-200-seconds-per-test/23110)) | 2026-11-02 |
| Narrowing audits or adding waivers | Weakens what the tests check; never | standing rule |
| Snapshot reads in LightAppearance, Login, Chores (non-pilot) | Measured: no saving beyond noise, reverted | 2026-11-04 |

## 5. How to measure

### A/B one change

1. Note the lane HEAD and make a detached baseline worktree there: `git worktree add --detach .claude/worktrees/speed-classbase <HEAD>`.
2. Pin one simulator, `FENTON_SIM_IPHONE="iPhone 17 Pro (pool 4)"`, and use the same settings on both sides: `--force` (so the ledger doesn't skip an already-passed run) and `-only-testing:FentonHomeUITests/<Class>` with the class's plan.
3. Run **six runs alternating base, lane, base, lane, base, lane** from one background script through `tools/bg_run.py`, so load drift hits both sides equally.
4. Report:
   - the medians;
   - **the paired deltas** (base minus lane per adjacent pair) and their median;
   - **best of three** per side;
   - the 1-minute load average at the start of each run.
   Mark the saving **soft** when the paired deltas disagree in sign. On this Mac the load average often runs 90–360, which makes plain medians unreliable.
5. Every lane run must pass. A failure that also happens on the baseline is pre-existing: record it and carry on.
6. If a shared helper changed, run `--plan Smoke` on Duo and on iPad as **two separate commands** (`--only` takes one family).
7. Remove the baseline worktree. Add the row to [journey-speed](journey-speed.md).

### Step attribution

Run this script, saved outside the repo, over a set of journey logs, for example all logs since a date: `find .claude/worktrees/*/build -name '*.log' -newermt 2026-11-04 -print0 | xargs -0 grep -l "Test Case '"`. It prints test-case percentiles and each step type's share of the time.

```python
import re, sys, collections
step = re.compile(r"^\s*t = +([0-9.]+)s +(.*)$")
case = re.compile(r"Test Case '-\[\S+ (\S+)\]' (passed|failed) \(([0-9.]+) seconds\)")
KINDS = ["Wait for", "Launch", "Setting up automation session", "Terminate", "Requesting snapshot", "Get all elements",
         "Checking existence", "Find the", "Tap", "Swipe", "Waiting", "Synthesize event", "Press", "Type",
         "Get number of matches", "Audit", "Open", "Check for interrupting"]
kind = lambda s: next((k for k in KINDS if s.startswith(k)), "other")
total, count, durations, grand = collections.Counter(), collections.Counter(), [], 0.0
for path in sys.argv[1:]:
    prev = None
    for line in open(path, errors="ignore"):
        if m := case.search(line):
            durations.append(float(m.group(3))); prev = None; continue
        if not (m := step.match(line)): continue
        t, k = float(m.group(1)), kind(m.group(2).strip())
        if prev and 0 <= t - prev[0] < 120:
            d = t - prev[0]; total[prev[1]] += d; count[prev[1]] += 1; grand += d
        prev = (t, k)
durations.sort(); n = len(durations)
print(f"cases={n} p10={durations[n//10]:.1f}s median={durations[n//2]:.1f}s p90={durations[n*9//10]:.1f}s")
for k, v in total.most_common(12):
    print(f"{v/grand*100:5.1f}%  {v/3600:5.2f} h  n={count[k]:6d}  avg={v/count[k]*1000:5.0f} ms  {k}")
```

A fixed `sleep` emits no step, so its time is charged to the step before it.

### Other signals

- **Launches per class:** the `REUSE … reused=N launched=M` line, or the count of `Setting up automation session` lines.
- **Builds:** the `products: hit|built` line in a digest, and `uitest build` hold times in `~/.devcap/devcap.log`.
- **Queue health:** `~/.devcap/devcap.log` `acquire <pool> slot i/n after Ns …` lines. Sum `after` per pool, and count distinct `cwd`s per hour for the lane count.
- **Switches that already exist:**
  - `TEST_RUNNER_FENTON_UITEST_REUSE=0|1`
  - `FENTON_UITEST_AX5_RELAUNCH=1`
  - `FENTON_UITEST_ANIMATION_SPEED`
  - `FENTON_BACKGROUND_GRACE_SECONDS` (DEBUG)
  - `TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1`

## 6. Sources

**Apple: documentation**

- [Reducing your app's launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time)
- [Performing accessibility audits for your app](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app)
- [Scaling fonts automatically](https://developer.apple.com/documentation/uikit/scaling-fonts-automatically)
- [`UITraitCollection.preferredContentSizeCategory`](https://developer.apple.com/documentation/uikit/uitraitcollection/preferredcontentsizecategory) and [`UIMutableTraits.preferredContentSizeCategory`](https://developer.apple.com/documentation/uikit/uimutabletraits-8l00o/preferredcontentsizecategory)
- [`XCUIElementSnapshotProviding.snapshot()`](https://developer.apple.com/documentation/xcuiautomation/xcuielementsnapshotproviding/snapshot()) and [`XCUIElementSnapshot`](https://developer.apple.com/documentation/xcuiautomation/xcuielementsnapshot)
- [`firstMatch`](https://developer.apple.com/documentation/xcuiautomation/xcuielementtypequeryprovider/firstmatch) and [`element`](https://developer.apple.com/documentation/xcuiautomation/xcuielementquery/element)
- [`XCUIApplication.launch()`](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/launch()), [`terminate()`](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/terminate()) and [`activate()`](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/activate())
- [`CAMediaTiming.speed`](https://developer.apple.com/documentation/quartzcore/camediatiming/speed)
- [Determining how much code your tests cover](https://developer.apple.com/documentation/xcode/determining-how-much-code-your-tests-cover), on the cost of gathering coverage
- [Xcode 26 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes)

**Apple: WWDC sessions**

- [Testing Tips & Tricks (WWDC18)](https://developer.apple.com/videos/play/wwdc2018/417/)
- [What's New in Testing (WWDC17)](https://developer.apple.com/videos/play/wwdc2017/409/)
- [Optimizing App Launch (WWDC19)](https://developer.apple.com/videos/play/wwdc2019/423/)
- [Link fast (WWDC22)](https://developer.apple.com/videos/play/wwdc2022/110362/)
- [Author fast and reliable tests for Xcode Cloud (WWDC22)](https://developer.apple.com/videos/play/wwdc2022/110361/)
- [Meet mergeable libraries (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10268/)
- [Perform accessibility audits for your app (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10035/)
- [Go further with Swift Testing (WWDC24)](https://developer.apple.com/videos/play/wwdc2024/10195/)
- [What's new in Xcode (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/247/)

**Swift project**

- [Swift Testing parallelization](https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/Testing.docc/Parallelization.md)
- [Shared compilation cache thread](https://forums.swift.org/t/about-swift-shared-cache-across-machines/81850)
- [SwiftPM caching PR #10246](https://github.com/swiftlang/swift-package-manager/pull/10246) and [pitch](https://forums.swift.org/t/pitch-compilation-caching-support-in-swiftpm/88079)

**Other projects and write-ups** (third party; their numbers come from their own apps)

- [EarlGrey `GREYTestHelper`](https://google.github.io/EarlGrey/Classes/GREYTestHelper.html) and [Chromium's EarlGrey base test case](https://chromium.googlesource.com/chromium/src/+/891de733b481fff05ae0d07658b8e3bd4b622a6e/ios/testing/earl_grey/base_earl_grey_test_case_app_interface.h): fast animations
- [PSPDFKit: UI tests with ludicrous speed](https://engineered.at/articles/running-ui-tests-on-ios-with-ludicrous-speed)
- [Jesse Squires: Xcode UI testing reliability tips](https://www.jessesquires.com/blog/2021/03/17/xcode-ui-testing-reliability-tips/)
- [callstack/agent-device#632](https://github.com/callstack/agent-device/pull/632): typed queries
- [Appium XCUITest element attributes](https://appium.github.io/appium-xcuitest-driver/latest/reference/element-attributes/)
- [Tuist on the Xcode cache](https://canary.tuist.dev/blog/2025/10/22/xcode-cache), [AvdLee build optimisation](https://www.avanderlee.com/xcode/xcode-build-optimization-using-6-agent-skills/) and the [Bitrise cache FAQ](https://docs.bitrise.io/en/bitrise-build-cache/build-cache-for-xcode/xcode-compilation-cache-faq.html)
- [XCKnife sharding](https://developer.squareup.com/blog/xcknife-faster-distributed-tests-for-ios/) and [XcodeSelectiveTesting](https://github.com/mikeger/XcodeSelectiveTesting): selective and distributed runs, for comparison with `tools/affected_tests.py`
- [Appetize: testing accessibility font sizes](https://docs.appetize.io/guides-and-samples/test-accessibility-font-sizes): the `-UIPreferredContentSizeCategoryName` launch argument
- [WWDC19 Optimizing App Launch notes](https://wwdcnotes.com/notes/wwdc19/423) and [WWDC23 accessibility audit notes](https://wwdcnotes.com/notes/wwdc23/10035)
