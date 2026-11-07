# Scroll frame rate

> **What:** the app asks for no refresh rate while scrolling (removed 2026-10-31); iOS manages it. Scroll surfaces report to `ScrollActivity`. **Read when:** adding a scroll surface or chasing "fling feels choppy".

- **Decision (owner, 2026-10-31, verbatim "Remove the request").** The app's 120 Hz scroll frame-rate request (`ScrollFrameRateBooster`, a passive `UIUpdateLink` / `CADisplayLink` with range 80 to 120 held while a scroll was in motion; first adopted 2026-10-28 on "Yes, keep that") is removed. History: the build the owner found "super smooth" had been launched with `FENTON_TELEMETRY=1`, whose `FrameMonitor` then held a 120 Hz display link; the request reproduced that in every build.
- **Why (measured 2026-10-31, iPhone 18 Pro, a Debug gallery build compiled with -O, in-app passive `FrameMonitor`, 2 runs per cell, Settings and Recipes flings, `tools/ios_flingfps.sh --ab`).** Raw output was in `apple/.build/flingfps-20261031-110733-ab/` (not committed).

  | | With the request | Without (`FENTON_PERF_DISABLE=scrollRate`) |
  |---|---|---|
  | Mean fps (Settings, Recipes) | about 96 | about 96 (95.5, 94.9 to 95.5) |
  | Frames at 120 Hz | 87.5% | 74% |
  | What the misses are | 25 ms frames (40 fps) | an even 60 Hz (16.7 ms) |
  | Total slow-frame time, Settings | 4.4 s | 4.5 s |
  | Total slow-frame time, Recipes | 6.3 s | 6.6 s |

  The request bought more frames at 120 Hz but worse misses, and no gain in mean rate or total slow time, so it was not worth its code, battery and guards. Apple's own Settings behaves the same without a request (Round 6 control: mean 64, max 93).
- **Caveat (found in review, 2026-10-31).** The numbers above left out each run's last scroll (likely the down-flick half): the probe label was rebuilt before the collector appended the scroll that triggered it, so the final scroll never reached the `FLINGFPS-STATS` line. This hit both arms equally, so the comparison is still fair, but the absolute figures are partial. The probe now ingests and summarises in one step (`FlingFpsCollector.refresh(with:)`). A corrected re-measurement was skipped (owner, 2026-10-31: the app is moving to UIKit in another session, so no further device runs for this request).
- **Info.plist.** `CADisableMinimumFrameDurationOnPhone` stays (`project.yml`): ProMotion iPhones may run above 60 Hz. The "without" column above was measured with it set.
- **Modifier:** `.reportsScrollActivity()` (`HassDesign/ReportsScrollActivity.swift`; `onScrollPhaseChange`, iOS 18+) reports begin/end of a scroll to `ScrollActivity` with one token per surface, so `HassConnection`'s deferred route switch never lands mid-scroll. It is on every scroll surface: `modalChrome()` sheets, the Weather sheet, the flyout, sign-in, Vacation and Solo Trip, and every `.scrollTelemetry` page (`.scrollTelemetry` applies it; it does not report to `ScrollActivity` itself, which would count twice). A new scroll surface that is not inside a sheet and has no `.scrollTelemetry` must add `.reportsScrollActivity()`.
- **FrameMonitor** only measures and requests no rate. On iOS 18+ it measures with a passive `UIUpdateLink` (`requiresContinuousUpdates = false`; frame time is the gap between `UIUpdateInfo.estimatedPresentationTime`s, budget is the panel's best frame time), so a `FENTON_TELEMETRY=1` run shows the system's own rate. Below iOS 18 it falls back to a `CADisplayLink`, which does hold the panel up.
- **Scene choice:** `FrameMonitor` and the scroll-cost probe pick their scene through `ActiveWindowScene` (`HassDesign/ActiveWindowScene.swift`): the foreground-active scene whose window is key, else the first foreground-active one.
- **Not a request:** `ScrollCostProbe`'s own `CADisplayLink` (a diagnostic that drives the scroll, inert unless launched for the probe) still states a range; it is test tooling, not the app.
- **Measuring again:** `tools/ios_flingfps.sh --device <udid> [--ab-disable <switch>] --runs 2` ([performance](../testing/apple/performance.md), Round 7).
- **Tests:** `ScrollActivityTests` (`HassCoreTests/LocalServerRouteTests.swift`) cover `ScrollActivity`; `FlingFpsProbeTests` the fling summary; `HassDesignTests/PerfSwitches` parsing. `ScrollKeepsMovingJourneyTests` exercises the scroll surfaces on a simulator.
