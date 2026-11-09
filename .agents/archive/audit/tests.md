# Test and tooling duplication audit

> **What:** duplicated journey helpers, test doubles, gallery recorders and dead tooling, 2026-10-13 at `5c78202`. **Read when:** you need the evidence behind a rule, not to learn the rule.

> **Archived 2026-10-28.** Evidence from a point-in-time audit; the rules it produced live in [patterns/README.md](../../patterns/README.md#reuse-rules), [token-economy](../../workflow/token-economy.md) and the pattern docs.

Scope: `apple/Tests` (HassCoreTests, HassUITests, HassDesignTests), `apple/Apps/iOSUITests`, `apple/Apps/iOSTests`,
`apple/Sources/HassUI/Features/Gallery`, `tools/*`, `apple/project.yml`, `apple/Package.swift`.
Tree audited: main @ 5c78202. Read-only; nothing edited.
All paths below are relative to that tree. "Lines saved" is net of the shared helper.

The testing rules (AGENTS.md, `.agents/testing/apple/*`) say nothing about where shared test helpers live, and
`FentonHomeApp.swift:3` calls itself "Launch helpers shared by every journey" while 13 of 21 journeys bypass it.
Two structural facts explain most findings:

1. `HassCoreTests` and `HassUITests` are separate SwiftPM test targets, so a double defined in one cannot be used in the
   other. Hence the same recorder shape was rewritten in the UI target. Fix: a non-test `HassTestSupport` target.
2. The XCUITest journeys are one XCTestCase per file with no common base class or mixin, so every file re-declares its
   own helpers (and they have drifted).

---------------------------------------------------------------------------------------------------------------

## Ranked list (value / risk)

| # | Finding | Lines saved | Risk |
|---|---|---|---|
| 1 | Journey base: orientation `setUp`/`tearDown` copy-pasted in 23 files | ~200 | Low |
| 2 | Journey helpers `element` / `expectCall` / `lastCall` / `assertTarget` / `launch` boilerplate per journey | ~250 | Low |
| 3 | Gallery "Last call" Text copied ~15 times (+ `FENTON_GALLERY_CLEAN` read 11 ways) | ~130 | Low |
| 4 | Service-call test doubles rewritten ~10 times across the test targets | ~120 | Low-Med |
| 5 | `makeConnection` + `pendingRequest` copied in 8 files | ~75 | Low |
| 6 | iPad orientation loop (`orientations` array) in 17 places, one helper exists in only one file | ~90 | Low |
| 7 | `keep()` screenshot handshake re-implemented in 3 journeys, drifted from `keepScreenshot` | ~45 | Low |
| 8 | `reveal` scroll helper: 7 near-identical variants | ~100 | Med |
| 9 | Gallery recorders: describe/echo/set/update boilerplate x9 | ~90 | Med |
| 10 | HassUITests render helpers x17 and size constants x8 | ~80 | Low |
| 11 | `tools/coverage_gate.py` dead XML/JaCoCo branch | ~110 | Very low |
| 12 | Hosted `NSWindow` hosts: 4 implementations | ~60 | Med |
| 13 | `EntityState` factory + `EntityStore` builders (galleries/tests) | ~70 | Low |
| 14 | Waiters (`waitFor`, `waitForValue`, `expectValue`) x6 | ~30 | Low |
| 15 | Navigation helpers (`goBack` x4, settings tab x4) | ~40 | Low |
| 16 | Debug scaffolding left in `FoodJourneyTests` (`diagnose`, `logResetFrame`) | ~35 | Very low |
| 17 | UTC Gregorian calendar x4, `Failure: Error` structs x12 | ~35 | Very low |
| 18 | `project.yml` / `Package.swift` repeated settings | ~10 | Low |
| 19 | Dead helper `UIHost.snapshot` | 6 | Very low |

---------------------------------------------------------------------------------------------------------------

## 1. Journey base class for orientation `setUp` / `tearDown`  (value: high, risk: low)

Every XCUITest journey declares `continueAfterFailure = false`, and most rotate an iPad to landscape when
`FENTON_UITEST_ORIENTATION=landscape`, then force it back to portrait in `tearDown`. 23 files, 3 spellings.

Same logic (iPad landscape opt-in + iPad reset to portrait), 10 files:
- ChoresJourneyTests.swift:6-16, FloatingActionsJourneyTests.swift:6-16, HouseholdSettingsJourneyTests.swift:7-17,
  InventoryJourneyTests.swift:7-17, SecurityJourneyTests.swift:9-20, SettingsJourneyTests.swift:6-18,
  VacationJourneyTests.swift:7-17 (identical body to the others, only formatting differs).

tearDown-only (iPad reset to portrait), 12 files:
- BedroomJourneyTests.swift:8-13, ClimateJourneyTests.swift:11, HomePagesJourneyTests.swift:11-16,
  MediaRemoteJourneyTests.swift:8-13, NavigationJourneyTests.swift:9-14, RoomDevicesJourneyTests.swift:8-13,
  RoomsJourneyTests.swift:8-13, ThermostatDialJourneyTests.swift:8-13, VacuumJourneyTests.swift:11-16,
  LayoutJourneyTests.swift:8-13 (Duo-excluded variant), HomeJourneyTests.swift:114 (inline), CameraJourneyTests.swift:89.

Different on purpose: FoodJourneyTests.swift:7-24 (own `FENTON_ORIENTATION` env var, sets orientation for every
non-iPhone family on both setUp and tearDown; the env var name differs from the other 10 files, an accident of history).
LayoutJourneyTests.swift:8-13 only resets non-Duo.

Proposed home: `apple/Apps/iOSUITests/JourneyTestCase.swift`, `class JourneyTestCase: XCTestCase` with `setUp`
(continueAfterFailure, landscape opt-in) and `tearDown` (iPad to portrait). Each journey then subclasses it and deletes its
overrides. Unify `FENTON_ORIENTATION` and `FENTON_UITEST_ORIENTATION` (document one in `.agents/testing/apple/devices.md`).
Lines saved: ~200. Risk low; a base class in the XCUITest target compiles with the others via XcodeGen (`sources: Apps/iOSUITests`).
The `MainActor.assumeIsolated` wrapper in tearDown is also inconsistent (some files use it, some don't); the base class fixes that once.

---------------------------------------------------------------------------------------------------------------

## 2. Per-journey gallery helpers  (value: high, risk: low)

The same five helpers are re-declared in each gallery journey. Bodies are identical unless noted.

`element(_ id:, in app:)` = `app.descendants(matching: .any)[id].firstMatch`:
- BedroomJourneyTests.swift:34, ClimateJourneyTests.swift:30, HomePagesJourneyTests.swift:40, MediaRemoteJourneyTests.swift:33,
  RoomDevicesJourneyTests.swift:35, RoomsJourneyTests.swift:33, VacuumJourneyTests.swift:41, FoodJourneyTests.swift:54,
  ChoresJourneyTests.swift:32 (argument order flipped: `(app, id)`).
- Different: VacationJourneyTests.swift:37 uses `.matching(identifier:)` (same result); SecurityJourneyTests.swift:42 `tile()` is
  `app.buttons[id]`.

`expectCall(_ expected:, in:)` = wait for `gallery.lastCall` label to equal `"Last call: \(expected)"` (timeout 10):
- identical: MediaRemoteJourneyTests.swift:38, RoomsJourneyTests.swift:36, RoomDevicesJourneyTests.swift:38,
  VacuumJourneyTests.swift:44, SecurityJourneyTests.swift:46.
- near-identical (BEGINSWITH via predicate, timeout 4 or 10): ClimateJourneyTests.swift:63 (4 s), BedroomJourneyTests.swift:37 and :44
  (BEGINSWITH and CONTAINS variants), HomePagesJourneyTests.swift:43, FoodJourneyTests.swift:57, VacationJourneyTests.swift:43 (CONTAINS, 10 s),
  HouseholdSettingsJourneyTests.swift:67.
- plus 6 `lastCall(app)` readers: ChoresJourneyTests.swift:35, ClimateJourneyTests.swift:61, HouseholdSettingsJourneyTests.swift:65,
  InventoryJourneyTests.swift:80, MediaRemoteJourneyTests.swift:36, VacationJourneyTests.swift:40.
  Two use `.firstMatch`, two don't; this matters because some galleries show the line twice (footer + sheet bar).

`assertTarget` (44 pt, 43 pt after tolerance), byte-identical body: BedroomJourneyTests.swift:86, FloatingActionsJourneyTests.swift (inline),
FoodJourneyTests.swift:76, HomePagesJourneyTests.swift:89 (takes id), MediaRemoteJourneyTests.swift:68, RoomDevicesJourneyTests.swift:61,
RoomsJourneyTests.swift:58, SecurityJourneyTests.swift:68, VacationJourneyTests.swift:94 (takes id), VacuumJourneyTests.swift:120.
It is also open-coded in ThermostatDialJourneyTests. The tolerance (43 vs the documented 44 pt minus 1 pt) lives in 10 places.

`launch` boilerplate: `let app = FentonHomeApp.makeApp(); app.launchEnvironment["FENTON_GALLERY"] = ...; if clean {...CLEAN...};
app.launchArguments += arguments; app.launch(); waitForExistence(30); sleep(1) // Mid-animation`:
- BedroomJourneyTests.swift:17-31, ClimateJourneyTests.swift:16-27, HomePagesJourneyTests.swift:20-37, MediaRemoteJourneyTests.swift:17-30,
  RoomDevicesJourneyTests.swift:18-32, RoomsJourneyTests.swift:17-30, SecurityJourneyTests.swift:32-40, VacationJourneyTests.swift:26-34,
  VacuumJourneyTests.swift:21-38, ChoresJourneyTests.swift:20-29, HouseholdSettingsJourneyTests.swift:22-32, InventoryJourneyTests.swift:24-39.
- Only FloatingActionsJourneyTests.swift:18 and ThermostatDialJourneyTests.swift:15 use the existing `FentonHomeApp.launchGallery`.
- `sleep(1) // Mid-animation frames fail contrast and clipping.` appears 8 times (Bedroom:29, HomePages:35, RoomDevices:30, Food:83,
  MediaRemote:28, Rooms:28, Security:78, Vacuum:36); the comment itself is copied.

Proposed home: extend `FentonHomeApp` (or add `GalleryDriver.swift` beside it) with
`launchGallery(_ page:, environment: [String:String], clean: Bool, arguments:, ready: (XCUIApplication)->XCUIElement, settle: Bool = true)`,
and `extension XCTestCase { func element(_:in:); func expectLastCall(_ mode: .equals|.startsWith|.contains, ...); func assertTarget(_:) }`.
Keep `Tile`/`Page` enums per file. Lines saved: ~250 (about 24 per file x 10). Risk low: bodies are mechanical. Care point: ClimateJourneyTests
`expectCall` uses a 4 s timeout deliberately; make timeout a parameter.

---------------------------------------------------------------------------------------------------------------

## 3. Gallery "Last call" line copied ~15 times  (value: high, risk: low)

Each gallery builds the same `Text("Last call: \(x.lastCall)").font(.caption.monospaced())...accessibilityIdentifier("gallery.lastCall")`
with trailing modifiers that differ by accident:

- Identical to the base form (secondary ink, `lineLimit(3)`, leading frame): ClimateGallery.swift:37-46, VacuumGallery.swift:45-52,
  MediaRemoteGallery.swift:50-57, SecurityGallery.swift:28-38 (inline), ChoresGallery.swift:38-48 (inline), VacationGallery.swift:26-36 (inline),
  HomePagesGallery.swift:149-159 (inline in `GalleryLastCallBanner`), HouseholdSettingsGallery.swift:53-63 (`HouseholdGalleryLastCall`).
- Different ink: BedroomGallery.swift:88-95, RoomDevicesGallery.swift:61-68 and FoodGallery.swift:79-86 use `Ink.primary` with the same comment
  ("Secondary ink rendered 2.2:1 on the iPad sheet's bar"). That is a known contrast bug fixed in 3 of ~15 copies. The other 12
  still use `Ink.secondary` and `.background(.bar)` bars; they pass only because the audit covers those pages elsewhere.
- Different font/lines: RoomsGallery.swift:30-39 (`caption2`, 2 lines) and :58-63; InventoryGallery.swift:44-54 (2 lines);
  FloatingActionsGallery.swift:26-31 ("Last action:" label, same identifier).

The `FENTON_GALLERY_CLEAN=1` switch is evaluated three ways: `MediaRemoteGallery.isClean` (MediaRemoteGallery.swift:47, used by 9 files),
raw `ProcessInfo...["FENTON_GALLERY_CLEAN"] != "1"` in SecurityGallery.swift:28, InventoryGallery.swift:44, FoodGallery.swift:66. An unrelated page
owning the shared flag (`MediaRemoteGallery.isClean`) is also a smell.

Proposed home: `Sources/HassUI/Features/Gallery/GalleryChrome.swift` holding `enum GalleryEnvironment { static var isClean; static func flag(_:), string(_:), raw<T: RawRepresentable>(_:) }`
and `struct GalleryLastCall: View { let text: String }` (ink primary, `lineLimit(3)`, optional bar background) plus a
`.galleryLastCall(_ text:)` safe-area modifier. Delete the 15 copies and the per-file `lastCall` computed properties.
Lines saved: ~130. Risk low; behavior change is only the contrast fix, which is desired. Must keep identifier `gallery.lastCall`.

---------------------------------------------------------------------------------------------------------------

## 4. Service-call test doubles rewritten ~10 times  (value: high, risk: low-med)

All implement `HassServiceCalling` / `HassServiceResponding` (HassCore/MediaRemote/HassServiceCalling.swift:6, Bedroom/ServiceResponses.swift:7) or
`TodoServicing`. They record `domain.service` (+data), some fail on demand, some return queued responses.

| Type | File:line | Records | Fails | Responses | Extras |
|---|---|---|---|---|---|
| RecordingCaller | HassCoreTests/MediaRemoteTests.swift:9 | Call{domain,service,data:[String:String]} + raw | failNext (once) | none | - |
| ResponseCaller | HassCoreTests/BedroomControllerTests.swift:9 | Call{domain,service,data,name} | fail | queue, default accepted | hold/release, `names` |
| RecordingResponder | HassCoreTests/RecipeServiceTests.swift:9 | Call{domain,service,data} | no | queue, default .null | - |
| ScriptedResponder | HassCoreTests/HouseholdAwayControllerTests.swift:7 | `sent` data only | Result queue | Result queue, `accepted()` | hangs, delay, onCommand |
| ScriptedCaller (UI) | HassUITests/BedroomViewTests.swift:166 | `calls: [String]` | fail | queue, default accepted | - |
| CallLog (UI) | HassUITests/VacuumViewCoverageTests.swift:96 | `calls` w/ entity ids, `datas` | fails | no | - |
| NullCaller (UI) | HassUITests/MediaRemoteViewTests.swift:13 | `calls: [String]` | no | no | used by Rooms/RoomDevice/HomePages/Household/Climate/Vacuum tests (43 refs) |
| Caller (UI) | HassUITests/SecurityViewTests.swift:10 | `domain.service entity` | no | no | - |
| RejectingResponder (UI) | HassUITests/VacationInteractionTests.swift:308 | none | no | fixed rejected | - |
| MockTodoService | HassCoreTests/TodoListControllerTests.swift:7 | `calls: [String]` | failure | single | gate/holdsLoads, uploads |
| MockFailingService (UI) | HassUITests/ChoresViewTests.swift:281 | none | always | throws | - |
| InventoryStubCaller | HassCoreTests/InventoryTestSupport.swift:41 | calls w/ JSONValue | per-service errors | per-service queues | (EverShelfCalling, genuinely different) |
| MemoryScheduleStore | HassCoreTests/HumidifierScheduleTests.swift:153 | in-memory | Failure | - | duplicates GalleryScheduleStore (RoomDevicesGallery.swift:264) |

Identical vs different: the first nine are the same idea in different spellings (`Failure: Error {}` is also re-declared in
HouseholdAwayControllerTests.swift:17, BedroomControllerTests.swift:24, MediaRemoteTests.swift:20, HumidifierScheduleTests.swift:159,
BedroomViewTests.swift:171, ChoresViewTests.swift:282). The call-string format differs (`domain.service`, `domain.service entity`,
`domain.service k=v`), so assertions are not directly portable; that is the main migration cost.

Proposed home: new SwiftPM target `HassTestSupport` (`apple/Tests/HassTestSupport/`, a regular `.target` depending on `HassCore`;
added to both `HassCoreTests` and `HassUITests`). Contents: one `@MainActor final class RecordingServiceCaller: HassServiceResponding`
with `calls: [Call]` (`name`, `entityId`, `data`, `names`, `described`), `failure: Error?`, `failNext`, `responses: [Result<JSONValue,Error>]`
(default `.object(["outcome":"accepted"])`), `hold/release`, `delay`, `hangs`, `onCommand`; `static func accepted(revision:)`;
a shared `TestFailure: Error`; keep `NullCaller` as a typealias. Also fold `MemoryScheduleStore` and `GalleryScheduleStore` (the gallery one
would stay in HassUI because it ships in a Debug page; HassTestSupport can reuse it via `@testable import HassUI`, or accept the duplicate).
Lines saved: ~120 (types ~170 lines become ~70). Risk low-medium: ~45 assertion sites compare the old per-type formats; migrate one target at a time.

---------------------------------------------------------------------------------------------------------------

## 5. `makeConnection` + `pendingRequest` copied in 8 files  (value: high, risk: low)

Byte-identical except the cache file prefix string:
- HassCoreTests/VacuumEdgeCaseTests.swift:10-19, BedroomContractTests.swift:368-377 (also renamed `pending`), RecipeServiceTests.swift:131-140,
  TodoServicingTests.swift:9-18, HassConnectionUserTests.swift:9-18, HouseholdAwayConnectionTests.swift:10-19, EverShelfClientTests.swift:431-440.
- HassUITests/SettingsViewTests.swift:83-87 (`mockConnection`) and the inline wait loops at :136 and :142.
Each builds `HAMockConnection()`, an `EntitySnapshotCache` in a UUID temp file, `HassConnection(server:.fentonHome, store:, snapshotCache:, connection: mock)`,
and polls `for _ in 0..<1_000 where mock.pendingRequests.isEmpty { sleep 10ms }`.

Proposed home: `HassTestSupport/MockHassConnection.swift`: `func makeMockConnection(prefix:) -> (HassConnection, HAMockConnection)` and
`extension HAMockConnection { func nextPendingRequest(count: Int = 1) async throws -> PendingRequest }`. Also `waitForStatus` (SettingsViewTests.swift:90).
Lines saved: ~75. Risk low. The shared copy removes 8 copies of a 1000x10 ms busy-poll (10 s worst case each) that could be centralised and tuned once.

---------------------------------------------------------------------------------------------------------------

## 6. iPad orientation loop in 17 places  (value: medium, risk: low)

The line `let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]` plus
`for orientation in orientations { if orientation != .unknown { XCUIDevice.shared.orientation = orientation } ... }` appears at:
BedroomJourneyTests.swift:268, CameraJourneyTests.swift:79, ClimateJourneyTests.swift:394, HomeJourneyTests.swift:97,
HouseholdSettingsJourneyTests.swift:253, MediaRemoteJourneyTests.swift:276 and :307, NavigationJourneyTests.swift:290,
RoomDevicesJourneyTests.swift:224 and :256, RoomsJourneyTests.swift:207 and :232, SecurityJourneyTests.swift:246,
SettingsJourneyTests.swift:204, VacationJourneyTests.swift:309, VacuumJourneyTests.swift:318 and :351.
Variants: three add `XCUIApplication().terminate()` before rotating (HouseholdSettingsJourneyTests.swift:255, SecurityJourneyTests.swift:248,
SettingsJourneyTests.swift:207); the capture suffix mapping `landscape/portrait/current` is re-coded in MediaRemote:309, RoomDevices:257, Rooms,
Vacation, Vacuum; only BedroomJourneyTests.swift:371 has `forEachCaptureOrientation`; HomePagesJourneyTests.swift:98-111 and
FoodJourneyTests.swift (`auditAndCapture`) use a string-array flavour.

Proposed home: in the base class from finding 1: `func forEachPose(terminate: Bool = false, _ body: (_ suffix: String) throws -> Void) rethrows`.
Lines saved: ~90. Risk low. This also fixes a latent inconsistency: the `terminate()` variants exist because rotation with a live app is flaky,
but 14 other copies don't terminate.

---------------------------------------------------------------------------------------------------------------

## 7. Screenshot handshake re-implemented in three journeys  (value: medium, risk: low)

The shared helper `XCTestCase.keepScreenshot` (FentonHomeApp.swift:451-472) writes `<name>.ready`, waits up to 180 s for `<name>.done`,
and withdraws the request on timeout (so a miss is a gap, not a mislabel). Three journeys re-implement it with different behavior:
- MediaRemoteJourneyTests.swift:325-343 `keep` (30 s wait, never withdraws; renders an "upright" image from `XCUIScreen.main`)
- NavigationJourneyTests.swift:330-342 `keep` (120 s, no withdraw, `app.screenshot()`)
- VacationJourneyTests.swift:322-338 `keep` (30 s, upright image, no withdraw)
So the file header comment in `keepScreenshot` ("A loaded host can take well over 30 s... late capture lands on the next screen") documents
exactly the bug that 2 of the 3 copies still have (30 s). `RenderedContrast.swift:...` is the only place the "upright" fix is explained.

Proposed home: fold the optional upright rendering into `keepScreenshot(_:_:upright: Bool = false)` and delete the three copies.
Lines saved: ~45. Risk low. Behavior fix: 30 s timeouts become 180 s with withdraw.

---------------------------------------------------------------------------------------------------------------

## 8. `reveal` scroll helper: 7 near-identical variants  (value: medium, risk: medium)

Same drag recipe (`press(forDuration: 0.05, thenDragTo:, withVelocity: .slow, thenHoldForDuration: 0.3)` from a window-anchored origin, Duo x clamp
`min(x, window.maxX - 96)`), differing in the "above" test, iteration cap and obstruction check:
- MediaRemoteJourneyTests.swift:46-66 (24 iters; has the explanatory comments), RoomsJourneyTests.swift:43-56, RoomDevicesJourneyTests.swift:46-59,
  BedroomJourneyTests.swift:52-67 (adds leading-edge clamp), HomePagesJourneyTests.swift:58-71 (uses `inView`, 20 iters),
  VacuumJourneyTests.swift:51-93 (adds last-call-bar occlusion and column detection, +43 lines).
- The Duo clamp line appears 7 times: Bedroom:57, HomePages:63, RoomDevices:51, MediaRemote:56, Rooms:48, Vacuum:63 and :88.
- Different strategies (not mergeable as-is): ClimateJourneyTests.swift:35-59 (sheet-relative), VacationJourneyTests.swift:64-81 (`swipeUp/Down`),
  FoodJourneyTests.swift:70-74, SettingsJourneyTests.swift:74-79, InventoryJourneyTests.swift:52-74, SecurityJourneyTests.swift:59-66,
  ThermostatDialJourneyTests.swift:32-45.
The 14 `press(forDuration: 0.05, thenDragTo:` call sites are the evidence that a single `dragScroll(in:from:direction:)` primitive is missing.

Proposed home: `ScrollDriver.swift` in iOSUITests: `func slowDrag(in app:, x:, fromFraction:, by:)` (the 14-site primitive including the Duo clamp) and
`func reveal(_ element:, in app:, region: ..., obstructions: [XCUIElement] = [], maxSteps:)`. Keep Climate/Food/Inventory/Security/Thermostat bespoke
but have them call the primitive. Lines saved: ~100. Risk medium: reveal behavior is tuned per page for Duo/AX5 and these tests need simulators to
verify; change one journey at a time and re-run on all three families.

---------------------------------------------------------------------------------------------------------------

## 9. Gallery recorders: describe/echo/set/update boilerplate x9  (value: medium, risk: medium)

Each gallery owns a `@MainActor @Observable final class ...Recorder: HassServiceCalling` with `lastCall`, `init(store:)`, an async `callService` that
does `lastCall = GalleryServiceRecorder.describe(...)`, `Task.sleep`, then an `echo` switch. Plus a private `set(id, state)` / `update(id, change)`:
- Recorders: GalleryServiceRecorder (MediaRemoteGallery.swift:63), PageGalleryRecorder (HomePagesGallery.swift:67, wraps the former),
  HouseholdGalleryRecorder (HouseholdSettingsGallery.swift:69), BedroomGalleryRecorder (BedroomGallery.swift:104), SecurityGalleryRecorder
  (SecurityGallery.swift:47), RoomDeviceGalleryRecorder + nested Caller (RoomDevicesGallery.swift:174-197), RoomsGalleryCaller
  (RoomsGallery.swift:81), VacationGalleryHouse (VacationGallery.swift:44), ChoresFixtureService (ChoresGallery.swift:103), FixtureRecipeService
  (FoodGallery.swift:94).
- Private `set/update` copies: MediaRemoteGallery.swift:88 (nested), SecurityGallery.swift:85, VacationGallery.swift:102 (all `store.value(id) ?? EntityState(...)`
  then `entity.state = state; store.apply([entity])`), BedroomGallery.swift:127 + :133, HomePagesGallery.swift:85, RoomDevicesGallery.swift:203 (adds attributes),
  VacuumGallery.swift:142.
- Echo delay constants differ by accident: 400 ms (MediaRemote, HomePages, Household, RoomDevices, Vacation default), 300 ms (Bedroom), 300/2500 ms (Security).
- Different: Security's door moves through opening/open; Bedroom's returns `response` objects; Vacation's rewrites status attributes with revisions.
  Those echo tables are genuinely feature-specific.

Proposed home: `GalleryRecorder.swift`: `@MainActor @Observable open class GalleryRecorder: HassServiceCalling` owning `lastCall`, `store`, `delay`, a
`record(_:_:_:)`, `setState(_:_:)`, `update(_:_:)`, and an overridable `echo(domain:service:data:)`. Each gallery subclass keeps only its echo table.
Better: add `EntityStore.update(_ id:, _ change:)` and `setState(_:_:)` to HassCore (they are also hand-rolled in tests: finding 13).
Lines saved: ~90. Risk medium (`@Observable` + inheritance, Swift 6 strict concurrency, `@ObservationIgnored` on stored props). Do the `EntityStore` helpers first
(low risk) and the base class second.

---------------------------------------------------------------------------------------------------------------

## 10. HassUITests render helpers x17 and size constants x8  (value: medium, risk: low)

`ImageRenderer(content: view.dynamicTypeSize(t).frame(width:height:))`, `proposedSize`, `.cgImage`:
- identical core: RoomDeviceViewTests.swift:14, VacuumViewTests.swift:19 (named `image`), BedroomViewTests.swift:23,
  VacuumViewCoverageTests.swift:699, HomePagesViewTests.swift:15 (+NavigationStack), ClimateViewTests.swift:21 (+store env),
  ChoresViewTests.swift:29 (+fixture env), RoomsViewTests.swift:18 (+store/NullCaller env).
- without proposedSize/DT: HouseholdSettingsViewTests.swift:18, VacationViewTests.swift:11, VacationInteractionTests.swift:51 (all three are NavigationStack at 402x874),
  FoodModelTests.swift:193 and FoodStateTests.swift:53 (also +env), InventoryPresentationTests.swift:19, InventoryViewTests.swift:13 (return Bool),
  HassDesignTests/FloatingActionBarTests.swift:7, ImageCardTests.swift:8.
- `static let phone = CGSize(width: 402, height: 874)` / `tabletLandscape = CGSize(width: 1210, height: 834)` copies: RoomDeviceViewTests.swift:11-12,
  VacuumViewTests.swift:15-16, MediaRemoteViewTests.swift:23-24, HomePagesViewTests.swift:12-13, BedroomViewTests.swift:13-14 (+:246-247 aliases),
  ClimateViewTests.swift:12-13, ChoresViewTests.swift:12-13, RoomsViewTests.swift:15-16. Two names (`tablet` and `tabletLandscape`) for the same size. The literal
  `CGSize(width: 402, height: 874)` appears in 13 files, and those numbers are also baked in `NavigationShellTests.swift` and `LayoutPolicyTests.swift`.
Proposed home: `HassTestSupport/ViewRendering.swift`: `enum TestScreen { static let phone, tabletLandscape }` and
`@MainActor func renderImage(_ view: some View, size: CGSize, typeSize:, navigation: Bool, environment: ...) -> CGImage?`
(HassDesign tests would need the support target to depend only on SwiftUI, so keep this file target-agnostic).
Lines saved: ~80. Risk low.

---------------------------------------------------------------------------------------------------------------

## 11. `tools/coverage_gate.py` dead XML branch  (value: medium, risk: very low)

`tools/coverage_gate.py` is the only Python and the only script besides `apple_coverage.sh` and `ios_uitest.sh`.
`xml_file_totals` (lines 105-172) and `_resolve_xml_source` (80-102), ~95 lines of JaCoCo/Cobertura parsing, are unreachable:
`argparse` restricts `--language` to `choices=("swift",)` (line 269) and `main` only reaches the `else` branch (278-283) when it is not swift.
It is a leftover from FestivalNativeApps (the docstring says "host and device test reports"). `import xml.etree.ElementTree as ET`
(line 8) goes with it. Delete lines 80-172, the `else:` at 278-283 (keep `llvm_file_totals`), and the ET import. Also `rules["thresholds"]` is validated per
category even though the only caller passes the fixed rules file; fine.
Lines saved: ~110. Risk very low (no tests exist for the script; run `tools/apple_coverage.sh` once to confirm).
Not duplicated: `tools/apple_coverage.sh` and `tools/ios_uitest.sh` do not overlap (one is SwiftPM host coverage, the other XCUITest on simulators). No other shell
scripts or build scripts exist in the repo (`find` for `*.sh`/`*.py`: only these three).
Gap worth noting (not duplication): `ios_uitest.sh` runs the whole `FentonHome` scheme, which includes `FentonHomeTests`
(`ThermostatDialAccessibilityTests`, the only iOS unit-test-bundle file), so the "journeys" gate silently also runs that one XCTest.

---------------------------------------------------------------------------------------------------------------

## 12. Hosted `NSWindow` hosts: 4 implementations  (value: medium, risk: medium)

All host a SwiftUI view in an off-screen macOS window, with a `settle`:
- `HostedView` (BedroomViewTests.swift:188-243): NSHostingView, titled window at (-4000,-4000), dark scheme, `settle(rounds:)`, fingerprint/distinctColors, close.
- `UIHost` + `KeyWindow` (VacuumViewCoverageTests.swift:11-94): borderless key window, RunLoop `pump`, KeyViewProxy `frames()`, mouse-event `click`, `snapshot`.
- `HostedWindow` (NavigationHostedTests.swift:16-64): NSHostingController, `sizingOptions = []`, async `settle(until:)`, `resize`, plus `ViewProbe`/`probed`.
- `SheetHostWindow` (SheetHostWindow.swift:8-60): NSHostingView, `sizingOptions = []`, sync `settle`, `hasSheet`, `contains`, `views(ofType:)`.
Used by: BedroomViewTests (3 refs), NavigationHostedTests (9), ScheduleDateFieldsTests (2), VacationInteractionTests (5), VacuumViewCoverageTests (3).
The strategy doc (`.agents/testing/apple/strategy.md:38`) names only `HostedWindow` and `ViewProbe`, so the other three are undocumented parallels.
Different: pointer-driven click support (UIHost), pixel fingerprint (HostedView), sheet/view-tree queries (SheetHostWindow), async probing (HostedWindow). Real differences,
but the window creation (`NSApplication.shared`, `isReleasedWhenClosed = false`, `orderFrontRegardless`/`orderBack`, `layoutSubtreeIfNeeded`, `RunLoop` pump) is the same 8 lines x4.

Proposed home: one `HostedWindow` in `HassTestSupport` (macOS-only) with options (`keyWindow`, `colorScheme`, `sizing`), and extensions for `click`/`frames` (pointer),
`fingerprint`/`distinctColors` (pixels) and `views`/`contains`/`hasSheet` (hierarchy). Lines saved: ~60. Risk medium: these tests are timing-sensitive
(`onDisappear` is unreliable, first window in a process lays out slowly) and run only under `swift test` on macOS; migrate one suite at a time.

---------------------------------------------------------------------------------------------------------------

## 13. `EntityState` factories and `EntityStore` builders  (value: low-medium, risk: low)

Identical `entity(_ id:, _ state:, _ attributes: = [:]) -> EntityState { EntityState(entityId: id, state: state, attributes: attributes) }`
(a pure positional wrapper of the memberwise init) in galleries: BedroomGallery.swift:264, RoomDevicesGallery.swift:109, HomePagesGallery.swift:168,
MediaRemoteGallery.swift:180, ClimateGallery.swift:73; VacuumGallery.swift:84 adds `lastChanged`. Plus `options(_:)`/`strings(_:)` array-wrapping JSON helpers
at MediaRemoteGallery.swift:183, VacuumGallery.swift:87, ClimateGallery.swift:76.

Store builders (`let store = EntityStore(); store.replaceAll(states, freshness: .live); return store`), 10 galleries: BedroomGallery.swift:35, SecurityGallery.swift:96,
ClimateGallery.swift:66, HomePagesGallery.swift:23 and :178, MediaRemoteGallery.swift:174, RoomDevicesGallery.swift:93, RoomsGallery.swift:104, VacuumGallery.swift:79,
VacationGallery.swift:148, HouseholdSettingsGallery.swift:101; tests: 19 more two-liners `= EntityStore()` then `replaceAll` (BedroomControllerTests.swift:48-52
`bedroomStore`, MediaRemoteTests.swift:68 `makeStore`, HomePagesViewTests.swift:23 `store`, RoomsViewTests.swift:18 x8, HouseholdAwayControllerTests x2,
SoloTripControllerTests, ClimateViewTests, BedroomViewTests x2, MediaRemoteViewTests).

Global test funcs with colliding generic names live in the HassCoreTests module namespace: `set` (MediaRemoteTests.swift:74), `update` (BedroomControllerTests.swift:56),
`makeStore` (MediaRemoteTests.swift:68), `utc` (BedroomContractTests.swift:12), `zlib`, `pngChunk`, `rectangleCells`: and a near-copy `set` in
RoomDeviceViewTests.swift:214 (UI target).

Proposed home: HassCore gets `EntityStore.init(live states: [EntityState])`, `EntityStore.setState(_ id:, _ state:, attributes:)` and
`EntityStore.update(_ id:, _ change:)`; HassUI's `Gallery` gets `EntityState.fixture(_ id:, _ state:, _ attributes:)` (or just use the memberwise init with labels). Delete the globals.
Lines saved: ~70. Risk low (additive API in HassCore; `EntityStore` is `@MainActor`).

---------------------------------------------------------------------------------------------------------------

## 14. Waiters  (value: low, risk: low)

- `waitFor(_ element:, _ format:, _ argument:, timeout: 10)` identical: FoodJourneyTests.swift:63, MediaRemoteJourneyTests.swift:75.
- Value equality waiters, 4 spellings: CameraJourneyTests.swift:19 (30 s, asserts), HouseholdSettingsJourneyTests.swift:60 (6 s, returns Bool),
  SecurityJourneyTests.swift:52 (10 s, asserts), VacationJourneyTests.swift:53 (5 s, hand polling with `usleep(200_000)`).
- Raw `XCTWaiter().wait(for: [XCTNSPredicateExpectation...])` inline: 25 times. `element.wait(for: \.keyPath, toEqual:)` (the XCUITest native API) is used 17 times;
  both styles coexist.
Proposed home: `extension XCUIElement { func waitForValue(_:timeout:) -> Bool; func waitForPredicate(_:timeout:) }` plus `XCTestCase.assertValue`. Lines saved: ~30. Risk low.

---------------------------------------------------------------------------------------------------------------

## 15. Navigation helpers  (value: low, risk: low)

- Back button: HouseholdSettingsJourneyTests.swift:73-76 and SettingsJourneyTests.swift:94-97 are byte-identical; NavigationJourneyTests.swift:32-41
  (edge swipe fallback) and ClimateJourneyTests.swift:85-96 (verifies the parent heading) are variants of the same operation.
- Settings tab in three forms: SettingsJourneyTests.swift:21-34 (poll tab bar/toolbar/rail 15 s: the most robust), HouseholdSettingsJourneyTests.swift:310-325
  (flyout or tab bar, 3+10 s), SecurityJourneyTests.swift:232-239 (`showSecurityTab`, the same tab-bar-or-rail lookup for Security).
  NavigationJourneyTests.swift:25 `tab(_:in:)` and :44 `flyout` exist too. The folded-Duo "rail" quirk is documented only in SettingsJourneyTests.swift:22-25,
  so the Household and Security copies do not have that fix.
Proposed home: `AppNavigation.swift` in iOSUITests: `goBack(in:)`, `openTab(_ title:, symbol:, in:)` (poll tab bar, toolbar, flyout, rail). Lines saved: ~40.
Risk low, with a real bug-fix upside (Household/Security tab helpers fail where Settings' passes).

---------------------------------------------------------------------------------------------------------------

## 16. Debug scaffolding left in `FoodJourneyTests`  (value: low, risk: very low)

`logResetFrame` (FoodJourneyTests.swift:288-297; called at :327 and :330) and `diagnose` (:510-521; 8 call sites :499, :502, :535, :538, :557, :560 and the two
signed-in/grid variants) print `FOODDIAG` lines and attach the whole `app.debugDescription` hierarchy on every run. Both are labelled as
investigations (FilterSheet audit findings; "iPad live-sheet investigation, 2026-10-12"). `launchLive` also sets `FENTON_FOOD_DEBUG=1`, which in HassUI
(`RecipeDetailView.swift:165-172`) exposes an on-screen `recipe.debug` marker. If the investigation is closed, remove the helpers, the call sites and
the `FENTON_FOOD_DEBUG` view. `testSignedInFixtureSheetSwitchesTabs` (:526-540) exists "to separate live data from the signed-in app", also an investigation test.
Lines saved: ~35 (+ the debug view in HassUI). Risk very low. Check with the owner whether the investigation is closed.

---------------------------------------------------------------------------------------------------------------

## 17. Small repeats  (value: low, risk: very low)

- UTC Gregorian calendar x4: `AwayTestClock.calendar` (HouseholdAwayContractTests.swift:6-17), `InventoryFixtures.utcCalendar` (InventoryTestSupport.swift:7-12),
  `utc` (BedroomContractTests.swift:12-16), inline in VacationViewTests.swift:52-53. Plus non-UTC `Calendar(identifier: .gregorian)` at
  FoodConfigTests.swift:7-8 (machine-dependent time zone, a latent flake), ChoresViewTests.swift:213. Proposed: `TestCalendar.utc` / `TestCalendar.now` in HassTestSupport.
- `struct Failure: Error {}`: HouseholdAwayControllerTests.swift:17, BedroomControllerTests.swift:24, MediaRemoteTests.swift:20, HumidifierScheduleTests.swift:159,
  BedroomViewTests.swift:171, ChoresViewTests.swift:282, plus `Plain`/`Boom`/`Offline`/`Missing`/`PlainFailure` (EverShelfClientTests.swift:414, TodoListControllerTests.swift:79,
  BedroomControllerTests.swift:659, RecipeServiceTests.swift:116, VacationInteractionTests.swift:39, FoodStateTests.swift:46). One `TestFailure` plus a LocalizedError twin.
- Polling helpers: `eventually` is defined twice (HassCoreTests/InventoryTestSupport.swift:71 and VacationInteractionTests.swift:41) and ad-hoc `for _ in 0..<N ... Task.sleep` loops
  appear in 10+ places (e.g. SettingsViewTests.swift:90, :136, :142).
- URLProtocol stubs: `StubURLProtocol` (HassLoginFlowTests.swift:6, path-keyed queue) and `StubMapProtocol` (VacuumEdgeCaseTests.swift:79, fixed scheme). Different behavior;
  consolidate only if a third one appears.
- `ManualScheduler` (HassCoreTests/MediaRemoteTests.swift:34, can fire) vs `ManualRevertScheduler` (HassUITests/VacuumViewTests.swift:150, never fires).
  Different on purpose, but both are `RevertScheduler` fakes that belong in HassTestSupport.
Lines saved: ~35 total. Risk very low.

---------------------------------------------------------------------------------------------------------------

## 18. `project.yml` and `Package.swift`  (value: low, risk: low)

- `apple/project.yml`: `TARGETED_DEVICE_FAMILY: "1,2"` x3 (FentonHome, FentonHomeUITests, FentonHomeTests), `GENERATE_INFOPLIST_FILE: YES` x3
  (FentonHomeWatch, FentonHomeUITests, FentonHomeTests), `PRODUCT_BUNDLE_IDENTIFIER: com.sfenton.home.*` x4 (could derive from `options.bundleIdPrefix` as
  `$(...)`). The two test bundles repeat `platform: iOS` + `dependencies: - target: FentonHome`. XcodeGen `targetTemplates` (e.g. `iOSTestBundle`) would remove ~10 lines.
  Do not hoist `TARGETED_DEVICE_FAMILY` into project-level `settings.base`: the watch target must not inherit "1,2".
  The scheme `coverageTargets: [FentonHome]` only measures the app target, not the HassCore/HassDesign/HassUI package products the app links, so the Xcode coverage
  is not the gate (the real gate is `tools/apple_coverage.sh`); keep, but document in `.agents/testing/apple/strategy.md`.
- `apple/Package.swift`: `.product(name: "HAKit+Mocks", package: "HAKit")` is declared on both `HassCoreTests` and `HassUITests`; fine, but if a `HassTestSupport`
  target is added (finding 4), declare it once there and drop it from both. No other duplication (the three library targets and three test targets are minimal).
Lines saved: ~10. Risk low.

---------------------------------------------------------------------------------------------------------------

## 19. Dead code in test support

Searched every `func`/type/`let`/`var` declared under Tests, iOSUITests, iOSTests and Gallery for symbols referenced once repo-wide. Nothing material is dead; the
helper layer is lean in that sense. Exceptions:
- `UIHost.snapshot(_:)` (VacuumViewCoverageTests.swift:67-72): zero callers ("debugging" aid). Remove or keep; 6 lines.
- `ControlProbe.first` (ControlProbe.swift:25) is used (13 refs); `SheetHostWindow.views(ofType:)` has 1 caller (ScheduleDateFieldsTests.swift:34) and
  `hasSheet` 2 callers, both live.
- The `tools/coverage_gate.py` XML path (finding 11) is the only substantial dead code.
- `FentonHomeApp.credentials` (FentonHomeApp.swift:19) is used only inside `launchSignedIn`; fine.
Not dead but out of scope: only `FoodGallery`, `InventoryGallery` and `ComponentGallery` contain `#if DEBUG` (1, 1 and 3 occurrences). The other 14 gallery
files and their fixtures and recorders (~2,700 lines) have no guard, so they compile into Release builds (`RootView.swift:13` reaches `ComponentGallery`;
check whether that call site is itself DEBUG-only). Consider wrapping the whole `Gallery/` folder in one flag; commit 1fb35cc "Gate the Food gallery to Debug so
Release builds compile (#26)" fixed one symptom of the same cause. It would also let finding 3's shared chrome be debug-only.

---------------------------------------------------------------------------------------------------------------

## Suggested order

1. Findings 11 and 16 and 19 (deletions, no new abstractions).
2. Findings 3 and 13 (additive, in HassUI/HassCore, no test impact).
3. Findings 1, 2, 6, 7, 14, 15 together as one "journey support" change, then 8 separately with device re-runs on iPhone, Duo and iPad.
4. Findings 4, 5, 10, 17, 12 as the `HassTestSupport` target (one SwiftPM change; migrate suites incrementally).
5. Finding 9 (gallery recorder base) after 13.
6. Finding 18 last.
Estimated total: ~1,400 lines removed, ~350 added in shared helpers; net ~1,000 lines.
