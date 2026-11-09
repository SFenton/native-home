# HassCore duplication audit

> **What:** duplicated logic in `HassCore` (helpers, controller shells, service bridges, entity ids), 2026-10-13 at `d9548ba`. **Read when:** you need the evidence behind a rule, not to learn the rule.

> **Archived 2026-10-28.** Evidence from a point-in-time audit; the rules it produced live in [patterns/README.md](../../patterns/README.md#reuse-rules), [token-economy](../../workflow/token-economy.md) and the pattern docs.

Scope: `apple/Sources/HassCore` (98 files, ~21k lines; checkout at `d9548ba`). Read-only. Paths below are relative to that directory. Tests and HassUI galleries were only grepped to size the protocol/mock fan-out.

Ranking is by value divided by risk. "Identical" means byte-for-byte logic; otherwise the semantic difference is stated.

Rough totals if everything is done: about 700-800 lines removed, about 200 added (a net reduction of roughly 500-600). Findings 1-4 and 6-7 together are about 80% of it.

---

## 1. Seven near-identical controller shells: in-flight tracking, `waitForCalls()`, `observeLive()`, optimistic `perform`

**Where (all `@MainActor @Observable` controllers that talk to `OptimisticOverlay`):**

| Concern | Files:lines |
|---|---|
| `inFlight: [Task<Void,Never>]` + `waitForCalls()` (identical 5 lines) | Climate/ClimateController.swift:18,105; MediaRemote/MediaRemoteController.swift:82,274; Vacuums/VacuumController.swift:96,558; Vacuums/VacuumAutoCleanController.swift:20,57; Sprinklers/SprinklerController.swift:21,160; Settings/HouseholdSettingsController.swift:39,170; Bedroom/BedSideController.swift:78,685; RoomDevices/RoomDeviceCommands.swift:17,67; Rooms/RoomController.swift:106,327 (also awaits child remotes) |
| `observeLive()` (withObservationTracking, onChange hops to `Task{@MainActor}`, run handler, re-arm) | Climate:129; MediaRemote:403; Vacuums/VacuumController:597; VacuumAutoClean:63; Sprinkler:222; HouseholdSettings:185; BedSide:732; RoomDeviceCommands:75; HouseholdAway/VacationModeController:221; HouseholdAway/SoloTripController:333; RoomDevices/BathroomFanController:44 (a variant: observes a computed `situationKey`) |
| optimistic `perform`: commit intents, `await caller.call`, on throw `overlay.reset(key, generation:)` | RoomDeviceCommands:44-58; MediaRemoteController:255-270; ClimateController:112-121; HouseholdSettingsController:152-165; VacuumAutoCleanController:51-55 (inline); SprinklerController:178-194 (`run`, returns Bool + sets `errorMessage`); BedSideController ~640-680 (with response outcome); VacuumController:548 (no overlay rollback, `onFailure` closure) |

The `// onChange fires before the new value lands; read it on the next main-actor turn.` comment is copy-pasted in at least 5 of them.

**Identical or different?**
- `waitForCalls()` is identical in every file except `RoomController` (extra loop over `remotes`) and `HumidifierScheduleController:164` (delegates to `commands`).
- `observeLive()` has the same skeleton. Differences are only (a) which ids are tracked (`overlay.trackedKeys` vs a computed id list vs `Vacuum.pageEntityIds`), (b) what the handler does (`liveDidChange()` or an inline loop), (c) `VacuumAutoCleanController:63` captures `ids` once outside the closure, so it never picks up new tracked keys, while `RoomDeviceCommands:75` re-reads `overlay.trackedKeys` per cycle. ClimateController tracks `liveValue(key)`, which can read an attribute (`fan_mode`), and the others track `store.entity(id).state`; both register the same dependency since the box is one `@Observable`.
- `perform` differs in return type (Sprinkler returns Bool), error surface (Sprinkler sets `errorMessage`; BedSide sets `commandError`) and a post-hook (`updateHolds()` in MediaRemote). The commit-then-rollback core is identical.
- `RoomController.send` (323) and `VacationModeController.send` (~205) deliberately swallow errors with `try?` and have no rollback, so they should keep a "fire and forget" mode.
- `RoomDeviceCommands` already is the shared plumbing for BathroomFan, AirPurifier, Humidifier and HumidifierSchedule, but the other 7 controllers re-implemented it.

**Proposed single home:** new `Entities/ObservedControllerSupport.swift`, or extend `MediaRemote/OptimisticOverlay.swift` and move it to `Entities/Optimistic/`:
```swift
@MainActor public final class CallTracker {            // replaces inFlight + waitForCalls
    public func track(_ task: Task<Void, Never>)
    public func waitForCalls() async
}
@MainActor public func observeEntities(
    _ store: EntityStore, ids: @escaping @MainActor () -> [String], onChange: @escaping @MainActor () -> Void)
extension OptimisticOverlay {
    /// commit + call + rollback in one place
    @discardableResult @MainActor public func perform(
        _ call: ServiceCall, via caller: any HassServiceCalling,
        intents: [OptimisticIntent], live: (String) -> String?, tracker: CallTracker,
        onFailure: ((Error) -> Void)? = nil)
}
```
Each controller keeps `liveDidChange()` and passes it as `onChange`. `BathroomFanController` can use `observeEntities` with a trivial closure, or keep its own.

**Estimated lines removed:** ~300 (about 10 lines of `waitForCalls`/decl x 9, about 14 lines of `observeLive` x 11, about 12 lines of `perform` x 6), minus about 70 added. Net about 230.
**Risk:** Medium. Behavior is simple, but these classes are `@Observable` with `@ObservationIgnored` members, and `[weak self]` re-arm timing matters for the "no reload on reopen" invariant. The existing controller tests (all call `waitForCalls()`) are the safety net. Do it as one controller per commit. Start with the 4 mechanical ones (Climate, HouseholdSettings, VacuumAutoClean, Sprinkler `observeLive`) and the `waitForCalls` tracker (zero risk).

---

## 2. Websocket "send one command, bridge to async" written six times, plus two competing service-with-response protocols

**Where (each is a `withCheckedThrowingContinuation` + `connection.send(HARequest(... shouldRetry: false))`):**
- Connection/HassConnection.swift:184 `requestString`
- Bedroom/ServiceResponses.swift:12-30 `callServiceWithResponse` (returns the whole result, via `JSONValue(haData:)`)
- Connection/HassConnection+ServiceResponse.swift:15-35 `callServiceForResponse` (returns the `response` member only)
- Todo/TodoServicing.swift:35 `sendCommand`
- RoomDevices/HumidifierScheduleController.swift:191 `requestJSON`
- Vacuums/HassServiceCatalog.swift:13-30 `serviceNames`
- (`callService` at Connection/HassConnection.swift:128 and `currentUser` at Connection/HassConnection+User.swift:34 use the typed HAKit requests and are fine.)

**Two protocols for one capability:**
- `HassServiceResponding` (Bedroom/ServiceResponses.swift:7) used by WakeLightController, BedSideController, BedroomDevices, HouseholdAwayController, EverShelfRecipeService (Recipes/RecipeService.swift:31), VacationScreen, RoomScreen.
- `EverShelfCalling` (Connection/HassConnection+ServiceResponse.swift:9) used only by EverShelfClient (inventory) and EverShelfFixtureServer.
- `TodoServicing` (Todo/TodoServicing.swift:11) re-declares `callServiceForResponse` as its own requirement (and its comment admits the implementation comes from the EverShelfCalling conformance).
- The same method signature is therefore declared in 3 protocols under 2 names. Conformers outside HassCore sources: 14 mocks/recorders (Tests: ScriptedCaller, ResponseCaller, ScriptedResponder, RecordingResponder, InventoryStubCaller, MockTodoService, MockFailingService, RejectingResponder; HassUI galleries: BedroomGalleryRecorder, RoomsGalleryCaller, VacationGalleryHouse, ChoresFixtureService, plus EverShelfFixtureServer in HassCore).

**Identical or different?** The request build is character-for-character identical (`call_service`, `domain`, `service`, `service_data`, `return_response: true`, `shouldRetry: false`). The result handling differs:
- `callServiceWithResponse` returns the *entire* result converted with `JSONValue(haData:)`. Arrays and primitives are preserved. Callers unwrap later:
  - `JSONValue.commandResponse` (ServiceResponses.swift:36): `response` if it is an object, else self if self is an object.
  - `RecipeParsing.payload` (Recipes/RecipeParsing.swift:17): `result.first("response","service_response") ?? result`.
- `callServiceForResponse` returns only `values["response"]`, `.null` for a non-dictionary or missing key, then `EverShelfClient.payload` (Inventory/EverShelfClient.swift:146) additionally unwraps `service_response`.
- So there are three different envelope unwrappers (`commandResponse`, `RecipeParsing.payload`, `EverShelfClient.payload`) applied to what is the same HA result. A bare result with no `response` wrapper yields `.null` in one path and the object in the other. The tests `callServiceWithResponseResultsUnwrapForRecipes` and `...HandlesBareAndFailedResults` (RecipeServiceTests.swift:142-170) pin the whole-result behavior.

**Proposed single home:** new `Connection/HassConnection+Commands.swift`:
```swift
extension HassConnection {
    func sendCommand(_ type: String, data: [String: any Sendable]) async throws -> HAData   // one continuation bridge, shouldRetry:false
}
extension JSONValue { init(haData: HAData) }              // move out of HumidifierScheduleController.swift
```
and one protocol in `MediaRemote/HassServiceCalling.swift` (rename the folder later):
```swift
public protocol HassServiceResponding: HassServiceCalling {
    func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue   // whole result, unchanged
}
public extension HassServiceResponding {
    func callServiceForResponse(...) async throws -> JSONValue { try await callServiceWithResponse(...).serviceResponse }   // = result["response"] ?? .null
}
extension JSONValue { var serviceResponse: JSONValue }    // single envelope unwrapper (response, then service_response)
```
`EverShelfCalling` becomes `typealias EverShelfCalling = HassServiceResponding`, then deleted. `TodoServicing` drops its own `callServiceForResponse` requirement. Keep the whole-result semantics at the transport level (it is a superset), and move the unwrapping into one tolerant helper that the three unwrappers call.

**Estimated lines removed:** ~85 (5 x about 13 lines of continuation plumbing, the extra protocol and conformance, 2 of the 3 unwrappers). About 30 added. Net about 55. Each test mock that conforms to `EverShelfCalling` or `TodoServicing` gets simpler (one method to implement).
**Risk:** Low-Medium. Pure plumbing, covered by the HAKit mock tests (`pendingRequest`). The only real risk is the envelope semantics: do not change what `callServiceForResponse` returns to inventory callers, which is why the helper above derives it rather than replacing it.

---

## 3. `isUnavailable` / "missing, unavailable or unknown" in about 12 places with at least two different semantics

| # | Where | Behavior |
|---|---|---|
| a | Entities/EntityState.swift:35 (`var isUnavailable`) | `state == "unavailable" \|\| "unknown"`, exact match |
| b | MediaRemote/MediaRemoteLogic.swift:6 `MediaRemoteState.isUnavailable(String?)` | nil -> true, else (a) |
| c | RoomDevices/RoomDeviceCommands.swift:95 `DeviceState.isUnavailable(String?)` | **identical to (b)** |
| d | Config/SecurityConfig.swift:171 (non-optional `String`) | (a) on a String |
| e | Rooms/RoomFormat.swift:66 (`EntityState?`) | delegates to (b) |
| f | Climate/ClimateController.swift:61 | `entity(id).map(\.isUnavailable) ?? true` (i.e. (b) on an entity id) |
| g | Vacuums/VacuumStatus.swift:181 `VacuumStatusResolver.isUnavailable(String?)` | **different:** trims whitespace, lowercases, and treats the **empty string** as unavailable. (b) treats `""` as available. |
| h | HouseholdAway/VacationModeController.swift:65 (`modeUnavailable`) and :106-108 (`isUnavailable(item)`) | inline `state == "unavailable" \|\| "unknown"`; nil -> true |
| i | Settings/PresenceOverrideState.swift:23 | inline; the nil entity is handled separately |
| j | Bedroom/WakeLightContract.swift:204 and HouseholdAway/HouseholdAwayContract.swift:79 | `entity != nil && state != "unknown" && state != "unavailable" && compatible && ...`, using `entity?.state ?? "unavailable"` |
| k | Sprinklers/SprinklerSnapshot.swift:122 `isAvailable(EntityState?)` | `!entity.isUnavailable`, nil -> false |
| l | Vacuums/VacuumStatus.swift:162-166 `availability()` | tri-state (.unknown vs .unavailable vs .available); legitimately different, keep |
| m | Bedroom/HouseholdAwayScope.swift:30-32 | different on purpose (idle/scheduled), keep |
| n | Config/MediaRemotes.swift:31 `deviceOffStates`, Rooms/RoomsConfig.swift:306 | data lists, not logic; keep |

Also three non-optional "missing means `"unavailable"` string" defaults: `?? "unavailable"` in MediaRemoteController:203,285,397, VacationModeController:107, BathroomFanController:61, GarageDoorController:104,165, SprinklerSnapshot:97,161.

**Identical or different?** (b), (c), (d), (e), (f), (h), (k) are the same predicate. (g) is the only real semantic outlier (trim/lowercase/empty), and the vacuum path feeds it raw state strings from a Valetudo integration, so keep that behavior behind a distinct name, e.g. `VacuumStatusResolver.isUnavailable` documented as lenient.

**Proposed single home:** `Entities/EntityState.swift`:
```swift
public extension EntityState {
    static func isUnavailable(_ state: String?) -> Bool   // nil, "unavailable", "unknown"
    var isUnavailable: Bool { Self.isUnavailable(state) } // instance form stays
    var isAvailable: Bool
}
public extension Optional where Wrapped == EntityState { var isUnavailable: Bool }   // nil -> true
```
Replace `MediaRemoteState.isUnavailable`, `DeviceState.isUnavailable`, `SecurityConfig.isUnavailable`, `RoomFormat.isUnavailable`, `SprinklerSnapshot.isAvailable` and the 4 inline copies with it. Contract parsers (j) can use `!EntityState.isUnavailable(entity?.state)`.
**Estimated lines removed:** ~35. **Risk:** Low. Leave (g), (l), (m) alone and add a comment pointing at the shared one.

---

## 4. Title-casing a snake_case state: nine variants with three behaviors

| # | Where | Behavior |
|---|---|---|
| a | MediaRemote/MediaRemoteLogic.swift:15 `MediaRemoteState.titleCase(String?)` | nil/empty -> `"Unknown"`; `split("_", omittingEmptySubsequences: false)` (so `a__b` -> `"A  B"`); only first letter changed, rest kept |
| b | Climate/ClimateLogic.swift:12 `ClimateLogic.titleCase(String?)` | **identical to (a)** |
| c | Vacuums/VacuumStatus.swift:389 `VacuumFormat.titleCase(String)` | non-optional; `""` -> `""`; keeps empty subsequences (as (a)) |
| d | Bedroom/BedSideController.swift:750 `BedSideController.titleCase(String)` | non-optional; `split("_")` **drops empty parts** (`a__b` -> `"A B"`); `""` -> `""` |
| e | RoomDevices/RoomDeviceCommands.swift:106 `DeviceState.titleCase(String)` | splits on **`_` or space**, drops empties; `""` -> `""` |
| f | Settings/HouseholdSettingsController.swift:140 `format(String?)` | nil/empty -> `"Unknown"`; `split("_")` drops empties |
| g | Config/SecurityConfig.swift:166 `stateText(String?)` | **identical to (f)** |
| h | Config/HomeConfig.swift:125 | `split("_").map { $0.capitalized }`: **lowercases the remaining letters** (`armed_AWAY` -> `Armed Away`, others give `Armed AWAY`) |
| i | Bedroom/SleepypodSchedule.swift:414 | first letter only, no split (single word metric); plus Bedroom/SleepypodSchedule.swift:10,58 and Bedroom/BedroomConfig.swift:17 `label` on raw-value enums |

Callers that cross modules: `RoomFormat` calls `MediaRemoteState.titleCase` (Rooms/RoomFormat.swift:19,32,39,45); `ClimateLogic` calls its own.

**Differences that could change output:** double underscores (a/b/c vs d/e/f/g/h), embedded spaces (only e splits on them), empty input (a/b/f/g return "Unknown", c/d/e return ""), mixed-case input (only h lowercases). Real HA states are lowercase snake_case, so a single implementation with (a)'s empty handling would change nothing visible. Verify by running the existing format tests.

**Proposed single home:** `Entities/StateText.swift`:
```swift
public enum StateText {
    public static func titleCase(_ state: String?) -> String      // nil/empty -> "Unknown"
    public static func titleCase(_ state: String, fallback: String) -> String   // if a caller needs "" for ""
}
public extension String { var titleCasedState: String }
```
Make the 7 other entry points `@available(*, deprecated)` forwarders for one commit, then delete.
**Estimated lines removed:** ~40. **Risk:** Low. Decide once on `omittingEmptySubsequences` (recommend `true`; it only differs for `__`) and pin it in a test.

---

## 5. Seven loose "JSON to number" parsers with different edge cases

| # | Where | number | string | non-finite handling |
|---|---|---|---|---|
| a | Climate/ClimateLogic.swift:49 `number(JSONValue?)` | `.number`, finite only | `Double(text)` **untrimmed**, whitespace-only -> nil, finite filter | filtered |
| b | Sprinklers/SprinklerSnapshot.swift:127 `number(JSONValue?)` | finite only | `Double(text)` **untrimmed**, finite filter | filtered |
| c | Bedroom/SleepypodSchedule.swift:208 `BedAlarm.number(JSONValue)` | finite only | **trimmed**, but `Double("inf")`/`"nan"` **not filtered** | strings not filtered |
| d | Recipes/RecipeParsing.swift:479 `JSONValue.loose` | finite only | trimmed, finite filter | filtered (the best version) |
| e | Inventory/InventoryItem.swift:204 `JSONValue.looseNumber` | **not** finite-filtered | trimmed, not filtered | none |
| f | HouseholdAway/HouseholdAwayContract.swift:118 `integer(JSONValue?)` | `value.number ?? value.string.flatMap(Double.init) ?? 0` then isFinite -> else 0, then clamp to >= 0, rounded | untrimmed | filtered after |
| g | Bedroom/WakeLightContract.swift:460 `integer`, :462 `clamped` | via (c) | via (c) | as (c) |
| h | RoomDevices/RoomDeviceCommands.swift:113 `DeviceState.number(EntityState?)` | parses `entity.state`, finite | n/a | filtered |
| i | Entities/EntityState.swift:43 `numericState` | `Double(state)` **no finite check** ("nan"/"inf" pass) | - | none |
| j | Bedroom/BedSideController.swift:142,278,432,465,718 `Double($0.state)`; MediaRemoteController.swift:343; SleepypodSchedule.swift:411; VacuumStatus.swift:414,424 | repeated `.flatMap { Double($0.state) }` | | none |

**Differences:** trimming (a, b, f do not trim; c, d, e do), finite filtering for strings (c and e skip it), and fallback to 0 (f only). Only (d) is the correct superset: `Double(" 5 ")` is nil in Swift without the trim, and HA does sometimes send padded numeric strings via template sensors.

**Proposed single home:** `Entities/JSONValue.swift` (next to the other accessors):
```swift
public extension JSONValue {
    /// number or numeric string (trimmed), finite only. Replaces climate/sprinkler/bed/recipe/inventory variants.
    var looseNumber: Double?
    var looseInteger: Int?                  // rounded; optional nonNegative variant
}
public extension Optional where Wrapped == JSONValue { var looseNumber: Double? }
public extension EntityState { var numericState: Double? }   // trims and filters isFinite
public extension EntityState { var numericValue: Double? }   // nil when unavailable
```
Then `RecipeParsing.loose`, `InventoryItem.looseNumber`, `ClimateLogic.number`, `SprinklerSnapshot.number`, `BedAlarm.number`, `DeviceState.number` and `HouseholdAwayContract.integer` become one-line calls or are deleted. Keep `RecipeParsing.flag`/`nonNegativeInt` where they are (they build on `loose`).
**Estimated lines removed:** ~45. **Risk:** Low-Medium. Behavior tightens slightly (strings like `"inf"` no longer pass in (c) and (e); padded strings now parse in (a) and (b)). The lenient behavior is a superset for normal data, but run the Bedroom, Sprinkler and Inventory tests, because `BedAlarm.number` feeds alarm payload round-tripping.

---

## 6. ISO-8601 / date parsing in seven places with different fallback chains

| # | Where | Chain |
|---|---|---|
| a | Sprinklers/SprinklerSnapshot.swift:180 `date(String?)` | plain ISO8601 -> fractional; empty/nil -> nil |
| b | Vacuums/VacuumStatus.swift:448 `VacuumDates.parse` | fractional -> plain |
| c | Bedroom/WakeLightContract.swift:423 `timestamp` | fractional -> plain (mutates one formatter) |
| d | Todo/TodoItem.swift:60-80 `parseDue` | 10-char date as **UTC midnight**; fractional -> plain -> local `yyyy-MM-dd'T'HH:mm:ss` |
| e | Recipes/RecipeFormatting.swift:242 `parseDate` | `Date(text, strategy: .iso8601)` (strict) -> fractional -> `yyyy-MM-dd` of first 10 chars in **current time zone** |
| f | RoomDevices/BathroomFanController.swift:127 `parseLocalDateTime` | `yyyy-MM-dd HH:mm:ss` (T replaced by space), POSIX, current tz |
| g | Bedroom/BedSideController.swift:240-244 | **inline copy of (f)** (same format string, POSIX, no T replace) |

All create a fresh `ISO8601DateFormatter`/`DateFormatter` per call (expensive; vacuum parsing runs for every condition on every state change).

**Differences:** (a) vs (b)/(c) differ only in order (result is identical for valid input). (d) and (e) differ in how a date-only string is interpreted (UTC midnight vs local midnight). That is a real behavior difference, but each matches its own web source (`new Date("2026-10-11")` is UTC; the recipe freshness label is a calendar-day display), so keep both as named variants rather than forcing one. (f)/(g) are the same parser, but (g) does not accept a `T` separator.

**Proposed single home:** `Entities/HassDates.swift`:
```swift
public enum HassDates {
    public static func iso8601(_ text: String?) -> Date?            // fractional then plain, cached static formatters
    public static func localDateTime(_ text: String) -> Date?       // "yyyy-MM-dd HH:mm:ss" or with T, POSIX, current tz
    public static func dateOnly(_ text: String, utc: Bool) -> Date? // "yyyy-MM-dd"
}
```
Rebuild a/b/c/d/e/f/g on those three. Use `nonisolated(unsafe) static let` cached formatters (`ISO8601DateFormatter` is thread-safe for `date(from:)`).
**Estimated lines removed:** ~55. **Risk:** Low. The existing parse tests per file (Vacuum, Sprinkler, Todo, WakeLight, Recipe) will catch regressions. Keep (d) and (e)'s date-only handling as explicit parameters.

---

## 7. "Compact entity state" (`formatCompactEntityState`) and contact/occupancy predicates ported four times

| Where | Behavior |
|---|---|
| Rooms/RoomFormat.swift:12 `compact(EntityState?)` | missing/"unavailable" -> "Unavailable"; `binary_sensor.contact*` Open/Closed; other binary_sensor Active/Clear; light On/Off; sensor + input_text raw; else titleCase |
| Climate/ClimateLogic.swift:23 `compactState(_:state:)` | **same table** as RoomFormat.compact (adds an optimistic `state` override) |
| RoomDevices/RoomDeviceCommands.swift:119 `DeviceState.compact(_:fallback:)` | **different:** no contact/light/input_text branch; `sensor.` prefix check; missing -> configurable fallback |
| Settings/HouseholdSettingsController.swift:146 `compactState` | **different:** only sensor domain raw, else `format()`; no binary_sensor/light mapping |
| Climate/ClimateLogic.swift:157 `isOccupied`, :136 `isContactOpen`, :145 `contactState` | **identical** to Rooms/RoomFormat.swift:48 `isOccupied`, :52 `isContactOpen`, :36 `contact` (verbatim copies) |
| Rooms/RoomFormat.swift:59 `isActive` and Settings/HouseholdSettingsController.swift:135 `webActiveStates` | the same 7-state set, written twice; plus `EntityState.isActive` (Entities/EntityState.swift:38) with a *different* set (comment in RoomFormat acknowledges this) |

**Proposed single home:** `Entities/EntityDisplay.swift`:
```swift
public enum EntityDisplay {
    public static func compactState(_ entity: EntityState?, state override: String? = nil, fallback: String = "Unavailable") -> String
    public static func contactState(_ entity: EntityState?) -> String
    public static func isOccupied(_ entity: EntityState?) -> Bool
    public static func isContactOpen(_ entity: EntityState?) -> Bool
    public static let webActiveStates: Set<String>
}
```
`RoomFormat` and `ClimateLogic` keep thin forwarders (they're public API consumed by HassUI), then those are migrated and removed. The two *different* compact variants (DeviceState and HouseholdSettings) should be checked against the web `formatCompactEntityState` source (`ha-sfenton-react-dash@<sha>:src/components/hass/entityState.ts`) and made equal if the web function is a single function (it is, per their own doc comments). That is a behavior change on those two pages (e.g. a light shows "On"/"Off"), so treat it as a separate, visible step.
**Estimated lines removed:** ~45. **Risk:** Medium for the two divergent variants (behavior change); Low for the verbatim copies.

---

## 8. Entity ids defined (or re-typed) in more than one place, and outside `Config/`

Verified by scanning every `"domain.object_id"` literal under HassCore. Duplicates:

| Entity | Locations |
|---|---|
| `todo.demo_todo_1` (4) | Config/ChoresConfig.swift:124; Rooms/RoomsConfig.swift:470; Recipes/RecipeService.swift:73 (`groceryTodoEntityId`); Inventory/EverShelfClient.swift:10 (`groceryListEntityId`) |
| `input_boolean.demo_mode_4` (4) | Config/ChoresConfig.swift:118; Config/ClimateConfig.swift:21; Config/RoomDeviceConfig.swift:235; Config/VacationConfig.swift:12 |
| `sensor.demo_away_2` (2) | Bedroom/BedroomConfig.swift:132 (`MasterBedroom.householdAwayEntityId`); HouseholdAway/HouseholdAwayContract.swift:10 (`statusEntityId`) |
| Pantryhub sensors (6 ids) | Config/FoodConfig.swift:10-33; Rooms/RoomNavigation.swift:150-154 (same list re-typed) |
| `alarm_control_panel.demo_alarm_control_panel_1` | Config/HomeConfig.swift:32; Config/SecurityConfig.swift:11; Rooms/RoomNavigation.swift:129 (`securityEntityId`) |
| 10 contact sensors | Config/ClimateConfig.swift:120-131; Rooms/RoomGroups.swift:203-215; Rooms/RoomsConfig.swift (one per room) |
| 15+ lights | Config/HomeConfig.swift:92-107; Rooms/RoomGroups.swift:60-97; Rooms/RoomsConfig.swift |
| `binary_sensor.demo_contact_2` | Config/ClimateConfig.swift:25; Config/HomeConfig.swift:35; Config/SecurityConfig.swift:20 |
| `lock.demo_lock_..._doorlock` | Config/HouseholdSettingsConfig.swift:181; Config/SecurityConfig.swift:18 |
| 8+ media players | Config/MediaRemotes.swift (2 places each); Config/MediaPageConfig.swift; Rooms/RoomsConfig.swift |
| vacuums, air-purifier PM2.5 sensors, bathroom fan switches, humidifier switch, wake-light sensor, grill state | Config/VacuumConfig.swift vs Rooms/RoomsConfig.swift; Config/RoomDeviceConfig.swift vs Rooms/RoomsConfig.swift; Bedroom/BedroomConfig.swift:140 vs Rooms/RoomsConfig.swift:38 |
| `input_text.*_climate_range` (13) | Rooms/RoomGroups.swift vs Rooms/RoomsConfig.swift (each room twice) |

Entity ids defined *outside* `Config/` and outside Rooms: Bedroom/BedroomConfig.swift:126-178 (the bed entities, templated by side/person; this is acceptable as a config file but sits in the feature folder), HouseholdAway/HouseholdAwayContract.swift:10, Recipes/RecipeService.swift:73, Inventory/EverShelfClient.swift:10, Rooms/RoomNavigation.swift:27,129,150-154. The Rooms folder has two 100-line-scale configs (RoomsConfig 482 lines, RoomGroups 217 lines) that restate Config ids rather than reference them.

**Proposed single home:** `Config/EntityIds.swift` with small namespaced enums (`Ids.Grocery.todoList`, `Ids.Vacation.mode`, `Ids.HouseholdAway.status`, `Ids.Security.panel`, `Ids.Food.sensors`, ...) that the config files and `RoomsConfig`/`RoomGroups` reference by symbol. For the per-room tables (contact sensors, lights, climate-range inputs), `RoomsConfig` could derive them from `ClimateConfig.rooms`/`HomeConfig.lightGroups` instead of re-typing.
**Estimated lines removed:** ~20 lines of literals, but the value is drift protection (an entity rename currently needs 3-4 edits). **Risk:** Low for the named singletons; Medium for restructuring the Rooms tables.

---

## 9. Whole-number-else-one-decimal / "+Int-if-whole" number formatting, six copies

- Sprinklers/SprinklerFormat.swift:114 `SprinklerFormat.number`: `value == rounded ? Int : "%.1f"`
- Vacuums/VacuumStatus.swift:442 `VacuumFormat.number`: **identical**
- Bedroom/SleepypodSchedule.swift:104 (`format`, adds a `+` sign) and :398 (`BedFormat.temperature`, adds unit): same core, inline
- Bedroom/SleepypodSchedule.swift:412 (`metric`): same but rounds with `(n*10).rounded(.toNearestOrAwayFromZero)/10` to mimic JS `toFixed(1)`. This is the only intentionally different rounding (`String(format: "%.1f", 91.25)` can print `91.2`, JS prints `91.3`), and the other copies have that latent difference
- Climate/ClimateLogic.swift:60 `temperature`: always one decimal (`72.0°F`), `--°F` when nil. Matches web `formatTemperatureValue`; different on purpose
- Recipes/RecipeFormatting.swift:9 `number`: locale-aware up to 3 fraction digits; different on purpose (user-facing recipe quantities)
- Inventory/InventoryCalendar.swift:92 `quantity`: up to 6 decimals trimmed; different (parser round-trip)
- Percent/duration formatters also repeated with different shapes: RoomDevices/HumidifierController.swift:172 `percent`, RoomDevices/BathroomFanController.swift:122 `durationTitle`, :114 `formatRemaining`, Bedroom/WakeLightContract.swift:417,420 `rampLabel`/`durationLabel`, Sprinklers/SprinklerFormat.swift:87 `minutes`, Recipes/RecipeFormatting.swift:22 `duration` (`1 hr 15 min`), RoomDevices/HumidifierController.swift:159 `formatMinutes` (`1h 15m`). These are all web-parity strings with different wording, so they should stay separate, but the fractional-number helper should be one.

**Proposed single home:** `Entities/NumberText.swift`:
```swift
public enum NumberText {
    public static func trimmed(_ value: Double) -> String      // Int if whole, else JS-toFixed(1) rounding
    public static func signed(_ value: Double) -> String
}
```
**Estimated lines removed:** ~15. **Risk:** Low. Adopting the JS-style rounding everywhere changes 91.25 -> `91.3` only for values with an exact binary tie, which is the web's behavior anyway.

---

## 10. Smaller duplicates worth sweeping in the same pass

1. **Integer-coercion for service data** (whole Double -> Int, `abs < 1e15`): `JSONValue.foundationValue` (MediaRemote/HassServiceCalling.swift:22), `EverShelfClient.number` (Inventory/EverShelfClient.swift:153), `RecipeServiceData.percent` (Recipes/RecipeService.swift:126). The first already does it for the full tree; the other two can call it. About 8 lines, Low risk.
2. **Failure text for service errors:** `ServiceErrorText.message` (Connection/HassConnection+ServiceResponse.swift:37), `TodoListController.message` (Todo/TodoListController.swift:142, drops the HAError branches), `SprinklerController.message` (Sprinklers/SprinklerController.swift:192, falls back to `String(describing:)` so it can show `external(...)` debug text). Collapse onto `ServiceErrorText`. About 12 lines, Low risk; Sprinkler/Todo error banners would show HA's own message more often.
3. **Non-empty / trimmed string helpers:** `nonEmpty` in Bedroom/WakeLightContract.swift:455 (String?), HouseholdAway/HouseholdAwayContract.swift:123 (JSONValue?), Vacuums/VacuumOutcomes.swift:197 (JSONValue?), `JSONValue.text` (Recipes/RecipeParsing.swift:471), `String.trimmed` (Vacuums/VacuumStatus.swift:458, internal; 73 other `trimmingCharacters` calls spell it out, some `.whitespaces` and some `.whitespacesAndNewlines`). One `JSONValue.nonEmptyString` plus `String.trimmed` in `Entities/` would do. About 20 lines, Low risk. Mixed `.whitespaces` vs `.whitespacesAndNewlines` is a real, tiny semantic difference (newline-only strings).
4. **Misc `JSONValue` accessors reinvented per feature:** `strings(_:)` (Bedroom/WakeLightContract.swift:466 string-only, filters empty; Climate/ClimateLogic.swift:276 accepts string/number/bool), `object(_:)` (Bedroom/WakeLightContract.swift:450), `objectValue` (Recipes/RecipeParsing.swift:468), `flag` (Recipes/RecipeParsing.swift:489) vs `isTrue` (Settings/PresenceOverrideState.swift:34). Move `objectValue`, `flag` and a strict/loose `strings` into `JSONValue`. About 25 lines, Low risk.
5. **`entity.attributes["friendly_name"]` with empty -> nil** (Sprinklers/SprinklerSnapshot.swift:144,166) vs `EntityState.friendlyName` (Entities/EntityState.swift:31) which never filters empty. Add `EntityState.attributeString(_:)` returning non-empty. About 6 lines.
6. **`unit_of_measurement` readers:** `ClimateLogic.unit(of:)` (Climate/ClimateLogic.swift:64), `RoomFormat.withUnit`/`temperature` (Rooms/RoomFormat.swift:73,129), `BedFormat.metric` (Bedroom/SleepypodSchedule.swift:~413) each read the attribute and decide on a space before the unit (`unit.hasPrefix("°")` rule in only one). Add `EntityState.unit` and `EntityState.valueWithUnit`. About 15 lines.
7. **Infra types that live in feature folders** (import-by-accident, encourages new parallel versions): `ServiceCall` is in Config/MediaRemoteConfig.swift:8; `HassServiceCalling` and `JSONValue.foundationValue` in MediaRemote/HassServiceCalling.swift; `OptimisticOverlay`/`RevertScheduler`/`TaskRevertScheduler` in MediaRemote/OptimisticOverlay.swift; `HassServiceResponding` in Bedroom/ServiceResponses.swift; `HassServiceCatalog` in Vacuums/; `JSONValue(haData:)` in RoomDevices/HumidifierScheduleController.swift:205; `UnexpectedResponse` (Connection) vs `UnexpectedSchedule` (RoomDevices/HumidifierScheduleController.swift:171). Move to `Connection/` and `Entities/` (file moves only, zero logic change). This is the lowest-risk step and the best enabler for 1-2: a new feature agent greps by filename.
8. **Mocks:** 14 hand-written `HassServiceCalling`/`Responding`/`EverShelfCalling`/`TodoServicing` conformers in Tests/ and HassUI/Features/Gallery (list in finding 2). After finding 2, one `RecordingCaller` in a shared test-support target (`ScriptedCaller` in `Tests/HassUITests/BedroomViewTests.swift:166` and `ResponseCaller` in `Tests/HassCoreTests/BedroomControllerTests.swift:9` are already nearly the same) could replace at least 6 of them. Estimated 100+ test lines, outside HassCore.
9. **`isActive` for "on-like" states** exists three times with different sets: `EntityState.isActive` (Entities/EntityState.swift:38; includes `opening`, `unlocked`, `cleaning`, `heat_cool`, excludes `recording`), `RoomFormat.isActive` (Rooms/RoomFormat.swift:59) and `HouseholdSettings.webActiveStates` (Settings/HouseholdSettingsController.swift:135). The doc comment already says the narrower one is intentional. Name them (`isActiveForHomeRail` vs `isActiveForRoomCard`) instead of leaving three look-alikes.

---

## Recommended order

1. Finding 10.7: file moves only (no behavior change), then 3 (`isUnavailable`) and 4 (`titleCase`): highest hit count, lowest risk.
2. Finding 6 (dates) and 5 (numbers): small and well tested, with caching as a free perf win.
3. Finding 2 (one websocket bridge plus one response protocol): removes the confusing double-named protocol that agents will keep copying.
4. Finding 1 (controller shell): biggest line savings, do last and one controller per commit.
5. Findings 7, 8, 9, 10.1-10.6 as a sweep.
