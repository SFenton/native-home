# Test strategy and phases

> **What:** which tests to write at which maturity, and what certification requires. **Read when:** deciding what to test for your change.

## Phases

| Phase | When | What |
|---|---|---|
| Build | Every commit | `swift build --build-tests` and the iOS app build |
| Unit | As you go | Tests for new non-UX logic (`HassCore`, policies); run only new or changed tests while iterating |
| UX tests | Every UI fix or feature, same PR | A hosted test (`apple/Tests/HassUITests`, macOS host) or an XCUITest journey that fails without the change |
| Accessibility tests | Every UI fix or feature, same PR | See below |
| Full audits | The app is complete | Whole-app audit sweeps per device family and accessibility setting |
| Screen-reader walkthroughs | After full audits | Scripted VoiceOver walkthroughs per page |

## Accessibility tests with every change

A PR that adds or changes a visible control, page, sheet, row, navigation or layout adds or updates an accessibility test on **each device family it affects** (iPhone, iPhone Duo, iPad) that would fail if accessibility regressed. A missing one is a **major** review finding. Pure logic, data or copy-only changes are exempt; say why in the PR.

| Concern | Assert |
|---|---|
| Name, role, value, state | Every interactive element has a real label, the right trait and its current state (toggled, selected, expanded) |
| Reading and focus order | Visual order, headings before content; decorative elements hidden |
| Target size | 44 pt minimum (allow 1 pt off-grid tolerance). A phone's and an iPad's sheet is scaled to fit (386 of 402 pt on an iPhone, 818 of 834 on an iPad), so frames read about 4% (2% on iPad) small inside it: compare layout size, the frame divided by the sheet's real scale (`JourneyTestCase.assertTarget(_:inSheet:)` reads it from the `FENTON_SHEETFIT_PROBE` transforms; never guess it from the sheet's width: the folded Duo's sheet is inset, 450 of 466 pt, but not scaled). |
| Text scaling | At AX5 text grows (> 1.35×), isn't clipped, and actions stay reachable |
| Motion, transparency, contrast | Reduce Motion / Reduce Transparency paths; rendered contrast ≥ 4.5:1 for text over materials or camera images |
| Keyboard (iPad) | New actions are reachable by keyboard |

Mechanisms: hosted tests in `HassUITests` for labels, traits and order; an XCUITest `performAccessibilityAudit()` journey in `apple/Apps/iOSUITests` for each new page and sheet. No blanket waivers and never a whole audit type.

## Certification gates (two, independent)

1. **Line coverage:** ≥ 95% logic (`HassCore`, `HassTelemetry`, `FentonActivityModel`, `HassDemoHouse`), measured from real LLVM reports by `tools/apple_coverage.sh` (`contracts/coverage-rules.json`). Never exclude handwritten code to pass. The script exports one report across every `*Tests.xctest` binary. UX source (`HassDesign`, `HassUI`, `FentonActivityViews`) is classified `unmeasured` ([coverage](coverage.md)); UX and accessibility tests are still owed with every UI change.
2. **Device journeys:** every journey passes on iPhone, iPhone Duo and iPad (`tools/ios_uitest.sh`). An unavailable simulator or pose is a gap, not a pass.

See [coverage](coverage.md) for how the logic gate is measured and why UX is `unmeasured`.

`tools/apple_coverage.sh` merges every test bundle's profiles and exports all bundles together: the swiftbuild backend builds one bundle per test target and `swift test --show-codecov-path` exports only one, which would leave every other module unmeasured.

Every file under `apple/Sources` must match exactly one category in `contracts/coverage-rules.json`. The script checks that first (`coverage_gate.py --classify-only`, no build) and fails naming each unclassified file and its module; a new module gets a pattern before it merges (`HassTelemetry` had none until 2026-10-16, so the gate produced no number). A classified file with no LLVM record compiled to no instrumented code on the macOS host (declarations only, or `#if os(iOS)`): it counts as zero lines and the gate lists it. A whole module with no record is an error, because its test bundle was not exported.

Hosted SwiftUI tests that need `onAppear`, `onChange` or geometry use a real `NSWindow` (`HostedWindow` in `NavigationHostedTests.swift`, `sizingOptions = []` so the window size is the input) and report through `ViewProbe`, not the accessibility tree (macOS SwiftUI builds none without an assistive client). Poll for appearance (`settle(until:)`); `onDisappear` is unreliable on the host, so assert frames instead.

Service-call doubles live once in `Tests/HassTestSupport` (`RecordingCaller` with `names` and `failNext`, `ResponseCaller` with scripted `responses`, `hold`/`release()` and `fail`, `ManualScheduler`), re-exported to `HassCoreTests` and `HassUITests` by each target's `TestSupport.swift`. Use them instead of declaring another caller in a test file; add to them when a test needs more (audit 2026-10-13).

Gates certify releases; they are not run on a slice or a PR. The full three-device suite and `tools/apple_coverage.sh` (≥95% logic gate) are the nightly tier; a change runs only the per-change tier ([test tiers](README.md#test-tiers)): the affected `swift test --filter`, then the added or changed journeys on the families they affect (`tools/ios_uitest.sh --changed`). Launch each with `tools/bg_run.py` and read its digest ([token economy](../../workflow/token-economy.md)). Workers run the device and accessibility tests they add or touch before merging and list them in the PR.
