# SwiftUI Pro audit

> **What:** the vendored SwiftUI Pro rules applied to `apple/Sources`, 2026-10-13 at `d9548ba`. **Read when:** you need the evidence behind a rule, not to learn the rule.

> **Archived 2026-10-28.** Evidence from a point-in-time audit; the rules it produced live in [patterns/README.md](../../patterns/README.md#reuse-rules), [token-economy](../../workflow/token-economy.md) and the pattern docs.

Checkout: `apple` (`Sources` 222 files / 44.5k lines; `Apps/iOS` + `Apps/watchOS` 2 files / 37 lines; `Apps/iOSTests` + `Apps/iOSUITests` 24 files, counted separately and excluded from "prod" counts).
Method: mechanical grep per rule, then read to confirm. Read-only; no repo files edited.

Scope notes

- `HassCore` contains **no SwiftUI** (`import SwiftUI` appears 0 times). It is audited only for the Swift/concurrency/formatting rules in `swift.md`.
- Deployment target iOS 17 / watchOS 10, Swift 6.0 language mode (`Package.swift`: `swiftLanguageModes: [.v6]`; `project.yml`: `SWIFT_VERSION: "6.0"`). **No default MainActor isolation is configured**, so the `@Observable`-needs-`@MainActor` rule applies in full.
- Repo overrides from `.agents/workflow/swiftui-pro.md` applied: `Tab` API (iOS 18), `ConcentricRectangle`, `safeAreaBar`, `ToolbarOverflowMenu`, `reorderable`, native `WebView`, `ForEach(x.enumerated())` iOS 26 form, `.onChange`-style iOS 18 APIs are not findings. One-type-per-file is not a finding for existing files (132 of 222 Sources files hold more than one top-level type; reported as info only).
- Bottom line: this codebase is already very clean on the hard-deprecation rules. Zero hits for `foregroundColor`, `cornerRadius`, `accentColor(`, `NavigationView`, `NavigationLink(destination:)`, `navigationBarLeading/Trailing`, 1-parameter `onChange`, `.animation(_:)` without `value:`, `Task.sleep(nanoseconds:)`, `UIScreen.main`, `ObservableObject`/`@Published`/`@StateObject`/`@ObservedObject`/`@EnvironmentObject`, `PreviewProvider`, `TextEditor`, `NSLocalizedString`, `print(`, `View.if` helpers, `sizeCategory`, `autocapitalization(`, `UIImpactFeedbackGenerator`. All 50 `@Observable` classes carry `@MainActor`. All 226 `@State` properties are `private`.

## 1. Rule table

Severity: high = accessibility / correctness / hard-deprecated; medium = soft-deprecated / data-flow / perf; low = style. "Shared" = `HassDesign`, `HassUI/App`, `HassUI/Common`, `HassUI/Controls`. "Feature" = `HassUI/Features/*` (likely under active edit by other threads).

| # | Rule | Count (prod / tests) | Severity | Where | Mechanical sweep safe? |
|---|---|---|---|---|---|
| 1 | `foregroundColor(`, `.cornerRadius(`, `accentColor(`, `NavigationView`, `NavigationLink(destination:)`, `navigationBarLeading/Trailing`, 1-param `onChange`, `.animation(` without value | 0 / 0 | n/a | none | n/a |
| 2 | `ForEach(Array(x.enumerated()), id: \.offset)` and `ForEach(x.indices, id: \.self)` over mutable data | 7 (6 `\.offset`, 1 `.indices`) | **high** (1 real bug risk), medium (rest) | Sprinklers sheet, SettingsSection (shared), MediaRemoteControls, RecipeDetailView | No: needs an `Identifiable` element or stable id per site |
| 3 | Swallowed errors from user actions: `Task { try? await caller.call(...) }` | 7 sites that send a service call | **high** (correctness) | Security alarm, light, climate, guest toggle, chip sheet | No: needs a shared "show failure" path |
| 4 | Missing Reduce Motion handling on `.move(edge:)` transitions / large animations | 6 sites | medium (accessibility) | Inventory, Recipes, MediaRemote, FloatingActionBar, carousel | Partly: one `reduceMotion` env + opacity swap per site |
| 5 | `Binding(get:set:)` in view code (51 constructions, 39 on single lines) | 51 / 0 | medium | all Features; 0 in shared | No: each setter has a side effect (`controller.setX`); ~10 are `isPresented: Binding(get: { x != nil })` and convert to `sheet(item:)` / `alert(_:item:)` / `confirmationDialog(_:item:)` safely |
| 6 | Same `dynamic(light:dark:)` UIKit colour helper copy-pasted 4 times (plus a 5th UIColor provider) | 5 | medium (pattern-first violation) | HassTokens, VacationComponents, InventoryRow, ClimateComponents, HomeAssistantSettingsView | Yes: add one `HassTokens.dynamicColor(light:dark:)` and delete the copies |
| 7 | `String(format:)` | 26 / 5 | medium (user-visible ones), low (API exchange) | 22 in HassCore, 3 in Features, 1 in HassDesign | Partly (see section 3) |
| 8 | `DateFormatter` built per call, inside `Binding(get:)` | 1 UI + 4 Core | medium (perf) | `DonetickTaskSheet.swift:258` | Yes |
| 9 | Closure-form `NavigationLink { Destination } label:` | 5 | medium | Settings, Vacation, RoomSheets | No: needs route types |
| 10 | Stored escaping `@ViewBuilder var content: () -> Content` | 9 | medium (perf) | FilterSheet, BedroomComponents, TodoPageView, ChoresModel, RoomDeviceSheetChrome | Mostly: change to `@ViewBuilder var content: Content`, call sites unchanged |
| 11 | `.overlay(View)` / `.background(View)` non-closure form | 4 | medium (soft-deprecated; Xcode 27 `blendMode` ambiguity) | OptionPickerSheet, FloatingActionBar, WakeLightSheet, MainTabView | Yes |
| 12 | `@Entry` instead of `EnvironmentKey` boilerplate | 5 keys | medium | RoomSupport (3), InventoryRoute, HomePagesGallery | Yes (watch the default-value stability rule) |
| 13 | `DispatchQueue` | 4 / 0 | medium (3 are legitimate bridge code) | MainTabView:119, MediaRemoteSheet:172, ScanCamera:142,214 | No: all four are inside UIKit/AVFoundation bridges |
| 14 | `Task.detached` | 1 | low | AppSession:70 | Leave (fire-and-forget token revoke is a valid use) |
| 15 | `AnyView` | 3 | medium | ClimateScreen:27,31, ClimateGallery:29 | Yes (generic `Accessory: View`) |
| 16 | `GeometryReader` where a cheaper API fits | 12 (1 clear win) | low | GlassTile:264 level fill | One-site fix; the rest need the geometry for `SplitPolicy` |
| 17 | `onTapGesture` without button trait | 5 (0 real defects) | low | BrightnessTile (has trait), VacuumMapPanel (needs location), LoginView (focus helper), InventoryRow:40 and WakeLightSheet:167 (duplicate an accessible Edit control) | n/a |
| 18 | Icon-only Button/Menu/Image without a label | 0 real | none | scripted check (Button label closure containing `Image(` and no `Text`/`Label`) found 0 true positives; 85 `Image(systemName:)`, 64 `accessibilityHidden`, 102 `accessibilityLabel` | n/a |
| 19 | Fixed `.font(.system(size:))` | 7 (3 real) | medium | ScanItemSheet:301,358,373 (unscaled hero icons); the other 4 use `@ScaledMetric` or are a 5pt bullet | Yes (use `@ScaledMetric` or a text style) |
| 20 | `fontWeight(` | 3 | low | TodoListSection:142, VacuumComponents:253, MediaRemoteControls:95 | Yes |
| 21 | `.bold()` | 3 (already correct) | none | | n/a |
| 22 | `.weight(.semibold/.medium/.bold/.heavy)` scattered | 96 | low | 15 shared, 81 features | No (design decision) |
| 23 | `RoundedRectangle(cornerRadius:, style: .continuous)` redundant style | 57 | low | 16 shared, 41 features | Yes (delete `, style: .continuous`) |
| 24 | `RoundedRectangle(cornerRadius:)` vs `.rect(cornerRadius:)` | 58 | low | | Yes but cosmetic |
| 25 | `CGFloat` where `Double` works | 144 / 6 | low | 68 shared (55 HassDesign), 76 features | No: most are API-mandated (`CGFloat` in `ScaledMetric`, `CGPoint`); not worth a sweep |
| 26 | `Date()` vs `.now` | 15 / 19 | low | | Yes |
| 27 | `replacingOccurrences` | 15 / 1 | low | 14 HassCore, 1 `ChipSheet:44` | Yes for plain-literal ones; 3 use `.regularExpression` (keep, or switch to `replacing(_:with:)` with a regex literal) |
| 28 | `filter { }.count` instead of `count(where:)` | 17 | low | HassCore 15, Features 2 | Yes |
| 29 | `localizedCaseInsensitiveContains` for user filtering | 1 prod (gallery fixture) | low | FloatingActionsGallery:33 | Yes |
| 30 | `ForEach` over `filter {}` in the initialiser | 3 | low | TodoPageView:29,45 (real); FloatingActionsGallery:33 (gallery) | No |
| 31 | Computed `some View` helpers (non-`body`) | 201 (59 non-private) | low | spread widely; top: MediaRemoteControls 12, ScanItemSheet 11, WakeLightSheet 8, NavigationFlyout 8 | No (override says small private helpers can stay) |
| 32 | Two-column skeleton duplicated, branch inside `Group { if twoColumns ... }` | 7 sheets | medium (pattern + state identity) | BedSideSheet, MediaRemoteSheet, VacuumSheet, HumidifierSheet, VacuumsScreen, FoodHubScreen, RecipesScreen/InventoryScreen (own split transitions) | No: extract a shared `TwoColumnSheetLayout`, owner lane |
| 33 | `Button("x") { dismiss() }` | 33 | low | everywhere | Leave (`dismiss()` closure is the idiom) |
| 34 | `tabItem` | 3 | none (override: iOS 17) | MainTabView:26, FoodGallery | Leave |
| 35 | `showsIndicators: false` | 2 | low | StatusRail:14, RoomTiles:13 | Yes (`.scrollIndicators(.hidden)`) |
| 36 | `UIGraphicsImageRenderer` | 1 prod (image downscale, not view rendering) | none | ScanCamera:236 | Leave |
| 37 | `caption2` | 2 | low | RecipeDetailView:174, RoomsGallery:32 | Judgement |
| 38 | Localization: no String Catalog, no `bundle:`, 141 `Text(variable)` | n/a | low (English-only app) | | n/a |
| 39 | Single-child `Group` | 0 (all 28 wrap conditionals) | none | | n/a |
| 40 | `Locale.current` / `Calendar.current` | 4 | low | BedroomComponents:225,228,232; WakeLightSheet:403 | Yes (`@Environment(\.calendar)`) |

## 2. Detail with examples

### 2.1 High

**2.1.1 `ForEach(times.indices, id: \.self)` with in-row deletion (correctness)**
`Sources/HassUI/Features/Sprinklers/SprinklerControllerSheet.swift:314`. The row binds `$times[index]` and its button runs `times.remove(at: index)`; removing from a mutable array while iterating by index is the textbook crash/identity-reset case (`data.md`).
```swift
// Before
ForEach(times.indices, id: \.self) { index in DatePicker(..., selection: $times[index], ...) ... times.remove(at: index) }
// After: give each start time an id
struct StartTime: Identifiable { let id = UUID(); var date: Date }
ForEach($times) { $time in DatePicker("Start", selection: $time.date, ...) ; Button { times.removeAll { $0.id == time.id } } ... }
```
Related, medium: `ForEach(Array(x.enumerated()), id: \.offset)` identifies by position at `SprinklerControllerSheet.swift:81,119` (zone list, `snapshot.zones`), `MediaRemoteControls.swift:349` (nil-slot grid, fixed 3 columns, fine as is), `RecipeDetailView.swift:237,359`, `SettingsSection.swift:27` (HassDesign, paragraphs). The ones fed by immutable-per-render snapshots are low risk; the zone lists rows keep state (`ProgramRow`) so give `SprinklerSnapshot.Zone` an id (valve entity id exists: `zone.demo_zone_1.valveEntityId`) and use `\.element.valveEntityId`. Sweep: not mechanical.
Fine already (do not touch): the 25 other `id: \.self` hits are small enums, `allCases`, or short unique strings. One to check: `ForEach(status.actions, id: \.self)` (SoloTripScreen:132) is an enum, fine; `ForEach(lines, id: \.self)` (BedroomComponents:126, SprinklerControllerSheet:178) will mis-diff if two lines are equal strings.

**2.1.2 Silent failure of user-initiated service calls (`swift.md`: "errors triggered by a user action are swallowed")**
The app has no `print(` anywhere, but it swallows with `try?` inside `Task {}`:
- `Sources/HassUI/Features/Security/SecuritySystemSheet.swift:84` `Task { try? await caller.call(mode.call) }` (arm/disarm alarm)
- `Sources/HassUI/Features/Security/SecurityTiles.swift:43` (garage/lock tile call)
- `Sources/HassUI/Features/Home/ChipSheet.swift:35` `Task { try? await connection?.send(command) }`
- `Sources/HassUI/Features/Home/GuestPresenceSection.swift:37` (presence toggle)
- `Sources/HassUI/Features/CustomLights/CustomLightSheet.swift:131,163`
- `Sources/HassUI/Controls/Thermostat/ClimateThermostatDial.swift:92` (set_temperature)
```swift
// Before
Task { try? await caller.call(mode.call) }
// After: surface the failure through the existing optimistic-revert / banner path
Task { do { try await caller.call(mode.call) } catch { failure = error } }   // then .alert / BedroomNotice-style InfoBox
```
Controllers elsewhere (`WakeLightController`, `VacuumController`) already expose an `error` banner; these seven bypass them. Sweep: no (needs a per-screen error surface). Some of these are fire-and-forget by design (HA is source of truth, optimistic state reverts when the entity does not change); if that is the documented contract, downgrade to medium and record it in the pattern doc.

### 2.2 Medium

**Reduce Motion gaps (`accessibility.md`).** `accessibilityReduceMotion` is read in only 4 files (ThermostatDial, NavigationFlyout, OnDemandSplit, CameraLiveView), but these move content with no fallback:
- `InventoryScreen.swift:46` `.transition(.move(edge: .trailing))` + `:84` `.animation(.default, value: canSplit && editing != nil)`
- `RecipesScreen.swift:56` `.transition(.move(edge: .trailing))` + `:70` `.animation(.snappy, value: split && detail != nil)`
- `MediaRemoteControls.swift:427` `.transition(.opacity.combined(with: .move(edge: .top)))`
- `SuggestedRecipesCarousel.swift:127` `withAnimation { page = ... }` (paging)
- `FloatingActionBar.swift:89` (HassDesign) `.animation(.snappy, value: ...)` on search expand
```swift
// Before
.transition(.move(edge: .trailing))
// After
.transition(reduceMotion ? .opacity : .move(edge: .trailing))
```
Inventory and Recipes re-implement the "detail slides in beside the list" behaviour that `OnDemandSplit` already provides (with Reduce Motion handled). Reusing it is the real fix (pattern-first).

**Duplicated dynamic colour helper (pattern-first).** Identical `dynamic(light:dark:)` with `UIColor { traits in ... }` and a macOS branch in:
`HassDesign/HassTokens.swift:63`, `Vacation/VacationComponents.swift:27`, `Inventory/InventoryRow.swift:173`, `Climate/ClimateComponents.swift:22` (`adaptive`), plus a variant at `Settings/HomeAssistantSettingsView.swift:153`. Move to one internal-API `HassTokens.dynamic(light:dark:)` (public) and delete the copies. Mechanical and safe; touches 3 feature files (small, localised edit).

**`Binding(get:set:)` (`data.md`).** 51 constructions, all in feature screens. Three groups:
1. Presentation bindings that should be item-based (safe sweep, ~10): `VacuumTabs.swift:54` `confirmationDialog(isPresented: Binding(get: { confirming != nil }...)`, `VacuumTabs.swift:193`, `InventoryScreen.swift:78,189`, `InventoryItemEditor.swift:95`, `BedSideSheet.swift:98` `.sheet(isPresented: Binding(get: { controller.scopeRequest != nil }...))`, `RoomScreen.swift:101`.
```swift
// Before
.confirmationDialog(title, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), ...)
// After (Xcode 27 overload, back-deploys)
.confirmationDialog(title, item: $confirming) { item in ... }
```
2. Setter side-effects through controller methods (`Toggle(isOn: Binding(get: { controller.rainDelay }, set: { controller.setRainDelay($0) }))`: SprinklerControllerSheet:107,111,156,296; HumidifierSheet:221,238; ScanItemSheet:277,403,407; DonetickTaskSheet:205,213). Fix: expose writable computed properties on the `@Observable` model so views bind `$controller.rainDelay`. Not mechanical; setter semantics (equal-value writes, `Task {}` in setter at WakeLightSheet:157) differ from `onChange`.
3. Binding adapters allocated per body: `DonetickTaskSheet.swift:268-283` builds `DateFormatter` per get/set (below).

**`DateFormatter` allocation in a Binding.** `Sources/HassUI/Features/Chores/DonetickTaskSheet.swift:258` `static func formatter(_ format:) -> DateFormatter` is invoked from `hasDate`, `hasTime`, `dueDate`, `dueTime` bindings (lines 268-283), so every body pass allocates formatters. Cache two `static let` formatters, or use `Date.FormatStyle`/`Date(_:strategy:)` for the `yyyy-MM-dd`/`HH:mm` exchange strings. Safe, single file. The other `DateFormatter(dateFormat:)` uses in HassCore are fixed API-exchange formats (en_US_POSIX / UTC) and are correctly outside the rule; only `WakeLightContract.swift:393` produces user-visible text and it already uses `setLocalizedDateFormatFromTemplate` (but with `yyyy`; template should be `y`).

**`String(format:)` (`swift.md`).** 26 prod. User-visible (medium), worth converting to `FormatStyle`:
- `Sources/HassCore/Climate/ClimateLogic.swift:60` `String(format: "%.1f", $0) + unit` → `value.formatted(.number.precision(.fractionLength(1)))`
- `Sources/HassUI/Features/Vacuums/VacuumAreaEditor.swift:207` `"%.2f m² selected"` (unit not localised; use `Measurement(value:unit: .squareMeters).formatted()`)
- `Sources/HassDesign/ThermostatDial/ThermostatDialModel.swift:340`, `Sources/HassCore/Bedroom/SleepypodSchedule.swift:67,104,147,162,398,404,412` (`"%d:%02d Remaining"`, 12-hour clock strings), `Sources/HassCore/Inventory/InventoryCalendar.swift:73` (`MM/dd/yyyy` shown to the user, US order hard-coded), `Sources/HassCore/Sprinklers/SprinklerFormat.swift:49,115`, `Sources/HassCore/Vacuums/VacuumStatus.swift:436,443`.
Low (fixed API exchange, leave): `%04d-%02d-%02d` and `%02d:%02d` wire formats in WakeLightContract:411,435, HouseholdAwayContract:208-209, HumidifierSchedule:157, BedroomComponents:233, HumidifierSchedulesTab:260, InventoryCalendar:79,94.
Because HassCore unit tests assert exact strings, convert only with their tests. Sweep: no.

**Closure-form `NavigationLink`.** `SettingsScreen.swift:46,58`, `VacationScreen.swift:86,93`, `RoomSheets.swift:151` (destination built inline; RoomSheets also embeds a whole `ScrollView`). Move to `NavigationLink(value:)` + `navigationDestination(for:)`. The stacks using them do not also register `navigationDestination(for:)`, so there is no active mixing bug today (each of the 17 registered stacks registers a type once). Sweep: no.

**Stored escaping builder closures (`performance.md`).** `@ViewBuilder var content: () -> Content` in `FilterSheet.swift:19,93` (HassDesign), `BedroomComponents.swift:113,267`, `TodoPageView.swift:13`, `ChoresModel.swift:68`, `RoomDeviceSheetChrome.swift:28,70,91`.
```swift
// Before
@ViewBuilder var content: () -> Content   // body calls content()
// After
@ViewBuilder var content: Content          // body uses content; trailing-closure call sites unchanged
```
The repo already uses the second form in 14 places (`SettingsSection`, `ClimateComponents`, `VacationComponents`), so the pattern is established. `RoomDeviceSheetChrome`/`FilterSheet` are shared; check call sites compile.

**`.overlay(View)` / `.background(View)` non-closure form (`api.md`).**
- `HassDesign/OptionPickerSheet.swift:105` `.overlay(Capsule().strokeBorder(...))`
- `HassDesign/FloatingActionBar.swift:154` same
- `Bedroom/WakeLightSheet.swift:336` `.overlay(RoundedRectangle(...).strokeBorder(...))`
- `App/MainTabView.swift:92` `.background(TabControllerAccessibilityHider(hidden: isFlyoutOpen))`
```swift
// Before
.overlay(Capsule().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
// After
.overlay { Capsule().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1) }
```
The `.background(x, in: Shape)` and `.background(.style)` forms (about 90 more) are style overloads and correct.

**`EnvironmentKey` → `@Entry` (`api.md`).** 5 keys: `RoomSupport.swift:8,14,19`, `InventoryRoute.swift:13`, `HomePagesGallery.swift:127`. `RoomServiceCallerKey` also needs `nonisolated(unsafe) static let defaultValue` under Swift 6; `@Entry` removes that. Defaults are all `nil`/`false`, so the equal-across-reads rule is satisfied. `@Entry` is already used twice (NavigationFlyout:277, WindowHinge:10). Safe mechanical conversion.

**`AnyView` (3).** `Climate/ClimateScreen.swift:27,31` (`sheetAccessory: AnyView?`) and its only caller `Gallery/ClimateGallery.swift:29`. Make `ClimateScreen` generic over `Accessory: View` or store `@ViewBuilder`-built content; or drop (gallery is the only user). Safe.

**Two-column sheet skeleton duplicated, with a branch that resets state (`resizability.md`).** The same `GeometryReader { proxy in let twoColumns = ... ; Group { if twoColumns { HStack{ ScrollView; ScrollView } } else { ScrollView{ VStack } } } }` appears in `BedSideSheet.swift:61`, `MediaRemoteSheet.swift:48`, `VacuumSheet.swift:59`, `HumidifierSheet.swift:63`, `VacuumsScreen.swift:39`, `FoodHubScreen.swift:35`, and a variant in `InventoryScreen.swift:50` / `RecipesScreen.swift`. Folding the iPhone Duo flips `twoColumns`, which swaps the hierarchy and drops `@State` of anything inside. Extract one shared layout (HassDesign) that keeps `hero`/`tabs` identity stable (e.g. `ViewThatFits`/`Layout`, or hoist state above the branch). This is the highest-value structural cleanup but is owner-lane work in feature files.

**Fixed-size fonts that ignore Dynamic Type.** `Inventory/ScanItemSheet.swift:301` `.font(.system(size: 64))`, `:358` (56), `:373` (42). Decorative hero symbols, still unscaled.
```swift
// Before
Image(systemName: "checkmark.circle.fill").font(.system(size: 64))
// After
@ScaledMetric(relativeTo: .largeTitle) private var heroSize = 64   // then .font(.system(size: heroSize))
```
The ThermostatDial/WeatherSummaryCard usages already scale; `RecipeDetailView:249` is a 5pt bullet glyph (fine).

**`DispatchQueue` (4).** All inside UIKit/AVFoundation bridge code: `MainTabView.swift:119` (hop out of `updateUIView`), `MediaRemoteSheet.swift:172` (`ProbeView.onChange` callback), `ScanCamera.swift:142` (dedicated capture queue, required by AVFoundation), `ScanCamera.swift:214` (delegate callback). Candidates to replace with `Task { @MainActor in }`: `MainTabView:119`, `MediaRemoteSheet:172`, `ScanCamera:214`. Keep the capture queue. Not a drive-by sweep (timing "next turn" semantics matter at MainTabView:118).

**`onAppear` doing async-ish work (`performance.md`).** `CameraLiveView.swift:54` `model.start(...)`, `FoodRoute.swift:38,92`, `FoodHubScreen.swift:56`, `RecipeDetailView.swift:87`, `RecipesScreen.swift:65`. Each model stores and cancels its own `Task`, so this is acceptable; low priority.

**Possible variable-shape `ForEach` rows (`performance.md`).** `SprinklerControllerSheet.swift:119-121` (`if let program` inside the row), `WakeLightSheet.swift:104-106` (`if alarm.isNative {…} else {…}`), `FloatingActionBar.swift:78-83` (`if action.showsTitle`). If the container is a `List`, SwiftUI cannot derive identity from ids and runs every row body each update. Verify with `-LogForEachSlowPath YES`; fix by wrapping in a `VStack` or filtering beforehand. Low risk, medium in a long list.

### 2.3 Low

- `GlassTile.swift:264` (HassDesign, used by dozens of tiles): `GeometryReader { Rectangle().frame(width: proxy.size.width * level) }` for the level fill. Replace with `Rectangle().containerRelativeFrame(.horizontal) { w, _ in w * level }` (iOS 17) or `scaleEffect(x:anchor:.leading)`. Other `GeometryReader`s feed `SplitPolicy`/hit-test maths and are justified.
- `showsIndicators:` (`StatusRail.swift:14`, `RoomTiles.swift:13`) → `.scrollIndicators(.hidden)`.
- `Calendar.current` in views (`BedroomComponents.swift:225,228,232`, `WakeLightSheet.swift:403`) → `@Environment(\.calendar)`.
- `.fontWeight(tone == .future ? .regular : .semibold)` → `Font` weight or `bold()` (`TodoListSection.swift:142`, `VacuumComponents.swift:253`, `MediaRemoteControls.swift:95`).
- `Date()` → `.now` (HassCore Auth ×5, HassDesign ThermostatDialModel ×4, galleries ×4, default arguments).
- `filter{}.count` → `count(where:)` (ClimateLogic:226-228, HomeConfig:122,132, RecipeGroceryPolicy:67-70, RecipeParsing:334-335, SleepypodSchedule:263, BedSideController:533, InventoryCalendar:105, ChoresGallery:117).
- `Text(frontend.origin + page.path)` (`HomeAssistantWebPage.swift:60`): string addition in `Text`; it is a verbatim URL, so only style.
- `replacingOccurrences` (15): `ChipSheet.swift:44` is the only UI one (`state.replacingOccurrences(of: "_", with: " ").capitalized`); the rest are HassCore key normalisation. Replace with `replacing("_", with: " ")` where a plain literal is used.
- `InventoryRow.swift:40` / `WakeLightSheet.swift:167`: `onTapGesture` on a whole row that duplicates an accessible control (an `Edit` button exists in `actions(...)`, and the wake row has `accessibilityAction(named: "Edit")`). No VoiceOver defect; if touched, add `.accessibilityAddTraits(.isButton)` or promote the row to a `Button`.
- `localizedCaseInsensitiveContains` only in `FloatingActionsGallery.swift:33` (debug gallery). No production search filter exists yet; when one is added use `localizedStandardContains`.
- `NavigationFlyout`/`WindowHinge` use `userInterfaceIdiom` once (`OrientationPolicy.swift:117`) to read the declared Info.plist orientation set for the app delegate (`UIDevice.current` fallback). This is the orientation policy, not a layout decision, so it fits the "SplitPolicy is geometric" invariant. Leave.
- `UIColor(color).getRed(...)` at `CustomLightSheet.swift:172` extracts RGB from a `Color`; on iOS 17 `Color.resolve(in:)` replaces it (`api.md` "Obtain color components with `color.resolve(in:)`"). Safe one-site change.
- `Equatable` conformances for observable stored value types: not audited line-by-line; 156 `Equatable` mentions suggest this is already widespread in HassCore.
- Localization: no `.xcstrings`/`.strings` anywhere, no `bundle:`, 141 `Text(variable)` and 31 interpolated literals. Fine for an English-only owner app; record the decision, and note `Text("…", bundle: #bundle)` would be needed in the packages the day a second language is added.
- `Info.plist`/`project.yml`: `UILaunchScreen` is declared (hygiene rule satisfied); no `UIRequiresFullScreen`; `UIApplicationSupportsMultipleScenes: true`. Window-scoped state: tab selection uses `@SceneStorage` (good), but `SettingsScreen.swift:35` uses `@AppStorage` for `viewerUserId`, which couples scenes (low; non-sensitive id).
- `Task.detached` (`AppSession.swift:70`): credential revoke after sign-out must outlive the session object; acceptable.
- `nonisolated(unsafe)`: `HassConnection.swift:58`, `WebRTCCameraPeer.swift:16`, `RoomSupport.swift:10`, `RecipeParsing.swift:232-233`; `@unchecked Sendable`: `WebRTCCameraPeer`, `CaptureSessionBox`, `InMemoryTokenStore`. Each has a bridge/test reason; `TodoListController.swift:184` `private static var registry` is `@MainActor` isolated (class is `@MainActor`), fine.
- Force unwraps: 14 in HassCore/Features, mostly on known-present config (`SecurityConfig.disarmMode`, `RoomController.swift:149-151` `card.alternate!`, `TodoItem.swift:63` `TimeZone(identifier: "UTC")!`). `RoomController.swift:149-151` repeats `card.alternate!` three times; `if let alternate = useAlternate ? card.alternate : nil` is cleaner. Two `as!` on `layerClass` overrides are standard.
- Body length: 301 `body`s, longest 101 lines (`InventoryItemEditor.swift:185`), only 9 over 60 lines. No finding.
- Computed `some View` helpers: 201 (59 non-private). Per override they can stay if small and private; the largest concentration is `MediaRemoteControls.swift` (12) and `ScanItemSheet.swift` (11).

## 3. Shared / HassDesign vs feature screens

Safe to batch-edit now (shared files, low merge-conflict risk with feature threads):

| File | Fix |
|---|---|
| `HassDesign/OptionPickerSheet.swift:105`, `FloatingActionBar.swift:154` | `.overlay` closure form |
| `HassDesign/GlassTile.swift:264` | replace `GeometryReader` fill with `containerRelativeFrame` |
| `HassDesign/FilterSheet.swift:19,93` | stored builder closure → stored `Content` (check call sites in Features) |
| `HassDesign/FloatingActionBar.swift:89` | Reduce Motion guard |
| `HassDesign/SettingsSection.swift:27` | `enumerated()/\.offset` identity for paragraphs (low risk, immutable text) |
| `HassDesign/HassTokens.swift:63` | host the single `dynamic(light:dark:)` helper |
| `HassDesign` `style: .continuous` (16) and `CGFloat` (55) | style-only; do only with a project-wide formatter pass |
| `HassUI/App/MainTabView.swift:92` | `.background { ... }` closure form; `:119` `DispatchQueue` hop |
| `HassUI/App` `@Entry` already adopted | none |

Likely under heavy edit by feature threads (avoid or coordinate; one sweep PR after those land):
`Features/Sprinklers` (indices bug, Binding adapters), `Features/Bedroom` (WakeLightSheet, BedSideSheet, BedroomComponents), `Features/Inventory` (ScanItemSheet fixed fonts, InventoryScreen/Recipes reduce-motion + split), `Features/Chores` (DonetickTaskSheet formatter/bindings, TodoPageView, ChoresModel), `Features/Vacuums`, `Features/RoomDevices`, `Features/Food` (RecipeDetailView, RecipesScreen, carousel), `Features/Security`, `Features/CustomLights`, `Features/Climate` (AnyView, colour helper), `Features/Vacation`, `Features/Settings` + `Rooms` (closure-form NavigationLink, EnvironmentKey → @Entry), `Features/Home` (ChipSheet, GuestPresenceSection).

HassCore (no SwiftUI): 22 of the 26 `String(format:)` and 14 of the 15 `replacingOccurrences` are here; fix only alongside their unit tests.

## 4. Prioritised summary (top 5)

1. **Silent service-call failures (`try?` in `Task {}`), 7 sites, high.** Alarm arm/disarm (`SecuritySystemSheet.swift:84`), garage (`SecurityTiles.swift:43`), thermostat (`ClimateThermostatDial.swift:92`), lights, chips, presence. Route errors through the existing controller error banner or an alert.
2. **Index-based identity in a mutable list (`SprinklerControllerSheet.swift:314`) plus `\.offset` identities (SprinklerControllerSheet:81,119; RecipeDetailView:237,359; SettingsSection:27), high/medium.** Give rows stable ids; remove-at-index while iterating by index can crash or reset row state.
3. **Reduce Motion gaps, 6 sites, medium (accessibility).** `InventoryScreen.swift:46,84`, `RecipesScreen.swift:56,70`, `MediaRemoteControls.swift:427`, `SuggestedRecipesCarousel.swift:127`, `FloatingActionBar.swift:89`. Better: reuse `OnDemandSplit` for the Inventory/Recipes detail slide.
4. **Shared duplicated code that the pattern-first rule forbids, medium.** The `dynamic(light:dark:)` colour helper (4 copies), the two-column sheet skeleton (7 copies, which also rebuilds the view hierarchy and resets state when the Duo folds), and ~10 `isPresented: Binding(get: { x != nil })` presenters that should be `sheet/alert/confirmationDialog(item:)`.
5. **Small mechanical API modernisation batch, medium/low, safe to sweep in one PR.** 4 non-closure `.overlay/.background`, 5 `EnvironmentKey` → `@Entry`, 3 `AnyView`, 9 stored builder closures → stored `Content`, `DateFormatter` allocated per binding (`DonetickTaskSheet.swift:258`), 3 fixed `.font(.system(size:))` in `ScanItemSheet`, 2 `showsIndicators`, 57 redundant `style: .continuous`, `Date()` → `.now`, `filter{}.count` → `count(where:)`.

Runner-ups: `String(format:)` for user-visible numbers/times (ClimateLogic:60, VacuumAreaEditor:207, SleepypodSchedule remaining-time strings); the 5 closure-form `NavigationLink`s; the three `ForEach` rows whose first child is an `if` (verify with `-LogForEachSlowPath`).
