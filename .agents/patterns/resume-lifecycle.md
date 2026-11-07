# Resume lifecycle

> **What:** the rule that a background and foreground leaves the app exactly as the first launch did, and the census that proves it. **Read when:** adding anything that registers on launch or resume (an observer, a subscription, a task, a timer, a display link, a player, a socket), or when scrolling gets worse the longer the app has been open.

**Rule.** Every resume-time registration is idempotent and torn down on background (or released with its owner). Nothing is added by a resume that the next background does not take away. Owner report 2026-10-16 (Release build): scrolling stuttered more after every background and foreground.

## What to do when you add one

- **Observers.** A block observer (`NotificationCenter.addObserver(forName:…using:)`) stays registered until `removeObserver`; dropping the token adds one per call. Keep the token and remove it in `deinit` (mark the property `nonisolated(unsafe)` to read it there), or before registering again (`SceneAppearanceProbe`).
- **Subscriptions and tasks.** Keep the handle in an optional; cancel and nil it before replacing it (`ConnectionLifecycle.disconnectTask`), and guard start with `== nil` where starting twice must be one (`HassConnection.statesSubscription`).
- **Players and sockets.** Stopping must release what the system keeps beyond your reference: empty an `AVPlayer` (`replaceCurrentItem(with: nil)`), end a peer's `URLSession`. Check with the heap census below, not by reading the code.
- **Gauge.** Give the owner a `liveResources: [String: Int]` (`Owner.thing` → 0 or 1, or a count) and register it: `census = ResourceCensus.shared.register { [weak self] in self?.liveResources ?? [:] }` (`HassTelemetry/ResourceCensus.swift`). Gauges present today: `Connection.*`, `Lifecycle.pendingDisconnect`, `CameraPool.*`, `Camera.*`, `Weather.*`, `Appearance.activationObservers`, `FrameMonitor.displayLinks`.
- **Unit test.** Start twice → one registration; background and foreground ×N → `liveResources` equal to the first launch (`ResumeLifecycleTests`, `CameraStreamPoolTests`, `WeatherForecastStoreTests`).
- **Journey.** `ResumeCyclesJourneyTests` launches with `FENTON_RESOURCE_CENSUS=1` (Debug; element `diagnostics.resources`, `HassUI/Diagnostics/ResourceCensusProbe.swift`), reads the census after the first scroll and after each of six background and foreground cycles (one past the 30 s grace), and requires the exact gauges to match and the bounded ones to stay under their bound. A new gauge goes in `exact` (steady-state) or `bounded` (follows what is in flight).

## Measuring a resume leak the gauges can't name

Gauges only see what the app registers. System objects (SwiftUI, AVFoundation, CFNetwork) leak without a gauge, so measure the process:

1. Run the app in a simulator inside a `tools/devcap.py` hold (a journey that cycles `XCUIDevice.shared.press(.home)` and `app.activate()`, scrolling Home each time).
2. After each scroll, `heap <pid> -s` (the app is a normal macOS process). Compare class counts across cycles: a class that grows by the same amount every cycle and not while idle is the leak. `MallocStackLogging=1` in the launch environment plus `heap <pid> -addresses all` and `malloc_history <pid> <addr>` names who allocated it.
3. Control: the same run without the background (idle) must stay flat, or the growth is not a resume leak.
4. Scroll cost: the app's CPU time (`ps -o time`) across a fixed scroll sequence per cycle. 30 to 60 cycles show a slope; simulator hitch ratios mean nothing, CPU time per fixed work does.

## Found (2026-10-16, iPhone 17 Pro simulator, iOS 27.0, Debug)

| Per resume | Cause | Fix |
|---|---|---|
| +14 SwiftUI observation records per paged carousel (+21 on Home) and the CPU of a fixed scroll creeping up (Home: 7.06 s to 7.36 s, +4%, over 30 resumes; the weather card alone: 2.29 s to 2.36 s, +3%, over 60) | `scrollTargetBehavior(.paging)`: each environment change (the scene phase is in it) makes SwiftUI build a new `ScrollEnvironmentStorage` and never release the old one's observation state | `pagesScrollViewByViewport()` (`HassDesign/NativePaging.swift`) turns on the `UIScrollView`'s own paging; records flat (58 to 58 over 5 resumes); with the modifier removed the 60-resume CPU slope disappeared (2.29 s to 2.36 s before, 4.04 s to 4.00 s after, same scroll) |
| +4 `URLSessionWebSocketTask` objects with their certificate chains (about 170 KB), 30 resumes added 5 MB | The camera peers' signalling sockets (`WebRTCCameraPeer`); the TCP connections close, the task objects stay. A private `URLSession` per peer with `invalidateAndCancel()` did not release them | **Open.** Memory only; not fixed |
| +4 notification observers, +16 timebases, +4 listener keys (HLS fallback only) | An `AVPlayer` dropped without emptying it | `tearDownPlayers` empties the player first |

Not a leak, measured and ruled out: threads (flat), HAKit subscriptions (one, cancelled and resubscribed on a 30 s background), notification observers the app registers (flat), display links, tasks the gauges see.

## Still open

- One live Swift task more per resume in the weather gallery (`Task stack` 7 to 12 over five resumes); not yet attributed, no gauge names it.
- The process grows about 1.8 MB per resume on Home in the simulator (627 MB to 681 MB over 30), most of it not in the classes above.
- The camera peers' signalling socket objects (table above).

## Not verified here

Hitch ratio on a phone. Simulators render with the Mac's compositor, so the cost above is CPU per scroll, not frames. Run `tools/ios_perf.sh --device <iPhone>` after a day of use and again after a relaunch to compare ([performance](../testing/apple/performance.md)).
