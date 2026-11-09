# Telemetry

> **What:** how the app measures its own performance. **Read when:** adding a page, a scroll view, a loader or anything that could cost frames.

- **Module:** `HassTelemetry` (`Telemetry`, `TelemetryLog`). It has no dependencies; every other module may use it.
  - **Signposts** (`OSSignposter`, subsystem `com.sfenton.home`, category `Performance`) are always on. Instruments and `XCTOSSignpostMetric` read them.
  - **In-app log**: a 4000-sample ring with counters and per-page scroll stats. It records while `Telemetry.isEnabled`: Debug builds, `FENTON_TELEMETRY=1`, or the switch on the Performance screen.
- **Names** (`Telemetry.Name`; tests depend on them): `EntityUpdate`, `ContentReady`, `ImageFetch`, `ImageDecode`, `ServiceCall`, `OptimisticConfirm`, `Scroll` and `Hitch`. `SnapshotSave` measures the debounced snapshot write. Navigation: `TabSwitch`, `Push`, `Pop`, `SheetPresent`, `SheetDismiss`, `ZoomOpen`, `ZoomClose`; moments: `Intro`, `Arrival`; `HouseConfigRead` (the synchronous cached house document read at session start, ending `hit` or `miss`). A transition records a `firstFrame` and a `settled` sample and its `p95Turn` and `worstTurn` (`Telemetry.Phase`, in the record's `detail`; `TelemetryLog.phaseStats` keys them `Push.settled@Room`).
- **Scrolling:**
  - Every page's main `ScrollView` / `List` carries `.scrollTelemetry("<Page>")` (`HassUI/Diagnostics/FrameMonitor.swift`).
  - While it scrolls, a display link times each frame. A frame later than half a budget counts as a hitch, and the page's hitch ratio (ms per s) is recorded.
  - A new page must add the modifier; it is one line.
  - `CADisableMinimumFrameDurationOnPhone` is set, so ProMotion iPhones may run above 60 Hz (iOS decides the rate).
  - `FrameMonitor` measures with a passive `UIUpdateLink` on iOS 18+ (a `CADisplayLink` below), so measuring does not hold the panel at 120 Hz.
  - The app requests no refresh rate during scrolls (removed 2026-10-31); iOS manages it: [scroll-frame-rate](scroll-frame-rate.md).
- **Scroll cost:** `MainThreadCostMeter` (HassTelemetry) reads the process' CPU instructions and, per main run-loop turn, the main thread's CPU time; `ScrollCostProbe` (HassUI) drives the front scroll view by itself and reports it. Both are inert unless `FENTON_SCROLLCOST=1`, in any build, and need no test to drive the app. `tools/ios_scrollcost.sh` runs it over every page and sheet; a turn over 8 ms is a dropped frame at 120 Hz. Details, numbers and budgets: [performance](../testing/apple/performance.md). `EntityUpdate` now times only the main-thread part of a live delivery (applying the changed entities); the diff runs on `HassConnection.deltaQueue`.
- **MetricKit:** `MetricKitCollector` keeps daily metric and diagnostic payloads (scroll hitch ratio, hangs) under `Caches/MetricKit`. It only runs on physical devices.
- **Navigation:** `NavigationMeasurement` times a transition and meters the main thread meanwhile; `.measuresNavigation(_:page:)` puts it on a page, `MotionPolicy.measure(_:)` / `measureCut(_:)` on code. Budgets and the runner: [performance](../testing/apple/performance.md), "Navigation".
- **Seeing it:**
  - Settings → Performance (`PerformanceScreen`) shows scrolling per page, navigation per surface, page loading, live updates, actions and images.
  - **Export Telemetry** shares one JSON file containing the log plus the MetricKit payloads.
  - Gallery: `FENTON_GALLERY=performance` (seeded).
- **Privacy:** nothing leaves the device unless the user exports it. Records carry page names and entity ids, never values or credentials.

- **Owned files** (also in `contracts/patterns.json`): `PerfSwitches.swift`.
