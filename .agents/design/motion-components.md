# Motion: every component

> **What:** the per-component motion checklist. It covers every shared and screen-level component, what changes its look, what animates today, what the rule in [motion.md](motion.md) says it must do, and the test that holds it there. **Read when:** you add a component, give one a new state, or touch its colours. Add a row in the same PR.

Owner, 2026-10-18: "make sure background color changes are animated, and that every single shared (or individual) component is checked for behavior and mocked/tested/validated." The inventory was taken on `main` @ `1750fac0` (146 components; 36 had state-driven background colours that changed with no animation). The mockup is board 12 of the motion canvas (`https://claude.ai/artifact/TpbCczywEXhMtJ7hsYdoo9`).

## The rule, per component

| Change | How it animates |
|---|---|
| Background, fill, tint, rim or material colour driven by state | `.stateColorTransition(value:)`: `MotionTokens.state` (0.6 s ease-in-out, or 0.2 s under Reduce Motion), scoped to the colour layer only |
| Foreground ink or glyph colour that changes with that same state | The same transition, applied in the same scope, so the ink and the ground arrive together |
| Symbol swap (lock ↔ unlock, play ↔ pause) | `.contentTransition(.symbolEffect(.replace))`, or `.identity` under Reduce Motion |
| Number or value text | `.contentTransition(.numericText(value:))` with `MotionTokens.quick` |
| Checkmark or selection mark appearing | Opacity with `MotionTokens.quick` |
| Press feedback (opacity or scale) | Instant down; release with `MotionTokens.quick` (the system button style handles this) |
| Disabled ↔ enabled | Opacity with `MotionTokens.quick` |
| Layout (size, position, order) | Never from a state change. Only a change the user caused animates layout, with `MotionTokens.standard`. *Exception: a tile's action set changing* (owner, 2026-10-26): height `standard`, discs fade `quick`; full-row tiles only, deferred while scrolling, none on snapshot or reconnect reapply, 0.2 s cross-fade under Reduce Motion ([motion.md](motion.md) §6) |

**One fix point per family.** A component that draws through a shared one inherits that component's transition and adds none of its own. For example, 17 tiles get theirs from `GlassTile`. The `Fix at` column names where the change lands.

**Status values:**
- **OK:** already matches the rule.
- **Fix:** the motion lane changes it.
- **Inherits:** correct once its parent is fixed.
- **Static:** no state-driven colour; checked and nothing to animate.
- **System:** ActivityKit or system controls own the motion.

## Shared: HassDesign

| Component | State that changes its look | Today | Status | Fix at | Test |
|---|---|---|---|---|---|
| `GlassTile` / `GlassTileFace` | isActive, isError, isUnavailable, family, fillRGB, wash, level | Nothing animates | Fix | `GlassTileFace` ground, ink, glyph and rim under one `.stateColorTransition(value: TileColorKey)`, built from those inputs | `GlassTileMotionTests` (key changes when each input changes; transition bound) |
| `TintedGlassGround` / `TintedGlassRim` (and the solid ground) | finish, wash, level, levelTint | Nothing animates | Inherits | `GlassTileFace` puts the ground (Tinted Glass or solid) and the rim under its transition | covered above |
| `TileActionStrip` / `TileActionButtonStyle` / `TileActionSetTransition` (`HassDesign/TileActions`) | disc glyph (lock, power, garage), phase, availability, action-set change | Done: glyph `.symbolEffect(.replace)` (Reduce Motion: identity plus the colour cross-fade); unavailable dims in place on `quick`; an action-set change on a full-row tile animates height `standard` and fades discs `quick` (guard rails in [motion.md](motion.md) §6) | OK | `TileActionSymbolTransition`, `TileActionSetTransition` | `TileActionSetTransitionTests`, `LayoutChangePerformanceTests.testRemoteActionSetChangeCost` |
| `TileVolumeSlider` | drag, percent | Drag is local state and writes once on release; the fill follows the finger without animation | OK | `TileVolumeSlider` | `RemoteTransportTileTests` |
| `BrightnessTile` | shown, isDragging, tint | Level animates (0.2 snappy); tint does not | Fix | Keep the level band on `quick`; tint through `GlassTileFace` | `BrightnessTileTests` |
| `StatusPill` | tone | Nothing animates | Fix | Icon colour and capsule fill | `StatusPillMotionTests` |
| `StatusChipButton` (Home, Rooms) | isFilled, family, tint | Animates at 0.6 s, the approved reference | OK, move to token | Replace `StatusChipStyle.colorAnimation` with `MotionTokens.state` | existing chip tests, plus a token assertion |
| `PrimaryButton` | isEnabled, isPressed | Opacity jumps | Fix | Disabled opacity on `quick` | `PrimaryButtonTests` |
| `ModuleRowButtonStyle` | isPressed | Pressed background jumps | Fix | Release on `quick` (instant down) | `ModuleListTests` |
| `ModuleRow`, `ModuleList`, `ModuleRowBackground` | none at runtime | — | Static | — | — |
| `SelectableOptionRow` | isSelected, isDisabled | Stroke and check jump | Fix | Stroke colour `state`; check opacity `quick` | `SettingsSectionTests` |
| `FilterOptionRow`, `OptionPickerSheet` rows | isSelected | Check jumps | Fix | Check opacity `quick` | `FilterSheetTests` |
| `InlineAlert` | severity | Fixed per instance | Static | — | — |
| `InfoBox` | tone | Fixed per instance | Static | — | — |
| `FloatingActionBar` | action isActive, prominent, search expanded | Search animates; active tint jumps | Fix | Active glass tint and glyph | `FloatingActionBarTests` |
| `ThermostatDial` / `ClimateThermostatDial` | value, status (heat/cool/off), inactive | Value animates; arc colours jump | Fix | Arc and handle colours on `state` | `ThermostatDialTests` |
| `ThermostatTileFace` | heating/cooling/idle | Through `GlassTile` | Inherits | `GlassTileFace` | — |
| `CachedImage` | loaded | Fades 0.2 s | OK, move to token | `quick` | existing |
| `ContentGate` | phase | Profile timings | OK (owner's profile) | — | existing |
| `ArcSpinner`, `ArcProgressViewStyle` | rotation, fraction | Timeline | OK | — | existing |
| `PageSectionHeader`, `FormHeader`/`FormFooter`, `SettingsSection`, `HassModal`, `FilterSheet`, `ChipRail`, `PagedRow`, `ScheduleDateFields`, `AppIconArtwork`, `GradientSwatch`, `ImageCard` | none at runtime | — | Static | — | — |

## Shared: HassUI/Common, Controls and App

| Component | State | Today | Status | Fix at | Test |
|---|---|---|---|---|---|
| `HouseBackdrop` | image loaded | Fades 0.3 s | OK, move to token | `standard` (opacity only) | existing |
| `ModalTabBar` | selection | System segmented; content switch is a cut | OK | — | `ModalTabBarTests` asserts the cut |
| `SegmentedChoice` | selection | System | System | — | — |
| `RoomOverviewTile`, `AirQualityRoomTile` | active, AQI tint | Through `GlassTile` | Inherits | `GlassTileFace` | — |
| `LightGroupTile` | on/off, rgb | Dimmable via `BrightnessTile`; the other branch via `GlassTile` | Inherits | `GlassTileFace` | — |
| `NavigationFlyout` | open | Spring 0.3 | OK, move to token | `standard` | existing |
| `ProfileButton` | name known, attention count | Badge appears instantly | Fix | Badge colour fade via shared `stateColorTransition` (pending: PR #122 not yet on main; opacity `quick` until then); header lane owns the layout | `ProfileButtonTests` |
| `QuickLinksButton` | none | — | Static | — | — |

## Features

| Component | State | Today | Status | Fix at | Test |
|---|---|---|---|---|---|
| **Bedroom** bed side and wake light cards (`RoomCardView`) | active, family | `GlassTile` | Inherits | `GlassTileFace` | — |
| **Bedroom** `ChoiceGrid` | selected, disabled | Fill and ink jump | Fix | Fill and ink on `state` | `BedroomComponentsTests` |
| **Bedroom** `WeekdayPicker` | selected day | Capsule fill jumps | Fix | `state` | `BedroomComponentsTests` |
| **Bedroom** `BedroomRow` | none at runtime | — | Static | — | — |
| **Cameras** `CameraControlButton` | isActive (mute, record) | Glyph animates; tint overlay jumps | Fix | Overlay on `state` | `CameraViewerTests` |
| **Cameras** `CameraLiveView` | phase | Fades 0.25 s | OK, move to token | `quick` | existing |
| **Chores** `TodoItemRow` | done | Check colour jumps; row leaves with the list animation | Fix | Check fill on `state`; removal `standard` (user-caused) | `TodoListSectionTests` |
| **Chores** `DueLabel` | tone (overdue/today/soon) | Jumps | Fix | Ink on `state` | `TodoListSectionTests` |
| **Chores** `QuickLinkFace` | family, active | `GlassTileFace` | Inherits | `GlassTileFace` | — |
| **Chores** `TodoPageView` | layout key | `.default` | OK, move to token | `standard` | existing |
| **Climate** `ClimateNotice`, `ThermostatHubPill` | warning, heat/cool | Ink jumps | Fix | Ink on `state` | `ClimateComponentsTests` |
| **Climate** `ClimateToggleRow`, `EcoOptionDetail`, `HubPicker` | isOn, selected | System toggle; check jumps | Fix (check) | Check opacity `quick` | `ClimateSheetTests` |
| **CustomLights** `CustomLightTile` | on, rgb | Through `BrightnessTile` or `GlassTile` | Inherits | `GlassTileFace` | — |
| **CustomLights** `LightingModeButton`, `OtherLightSwatch` | selected, rgb | Jumps | Fix | `state` | `CustomLightsTests` |
| **Food** `SuggestedRecipesCarousel` dots | page | `.default` | OK, move to token | `quick` | existing |
| **Food** `GroceryAction` | added | Check jumps | Fix | `.symbolEffect(.replace)` and `state` | `RecipeDetailTests` |
| **Food** `PercentSliderRow`, `RecipeGrid`, `RecipeSectionHeader` | none | — | Static | — | — |
| **Home** `CameraTile`, `GuestPresenceSection` tiles | active | `GlassTile` | Inherits | `GlassTileFace` | — |
| **Home** `CameraTile` indicator | live, connecting, offline | Cross-fade in place; the label makes room | Done | `quick` (fade kept under Reduce Motion) | `CameraControlsTests` |
| **Home** `WeatherBarChart` | value present | Bar fill jumps | Fix | `state` | `WeatherTests` |
| **Home** `WeatherPagedCarousel` dots | page | Jumps | Fix | `quick` | `WeatherTests` |
| **Home** `WeatherHourlyPanel`, `WeatherDailyPanel` | mode | 0.25 s | OK, move to token | `state` (colour) / `quick` (content) | existing |
| **Home** `WeatherRail`, `WeatherCompass` | range, angle | 0.39 s smooth | OK (data viz, not layout), move to token | `standard` | existing |
| **Home** `WeatherDecoration` | scene | Timeline (paused off-screen and in the background) | OK | — | existing |
| **Home** other weather tiles and gauges | value | Ink fixed | Static | — | — |
| **Inventory** `InventoryRow` | selected, busy | Selected fill jumps | Fix | `state` | `InventoryRowTests` |
| **Inventory** `CameraStatusPill`, `ScanProductHeader`, `StateMessage` | none | — | Static | — | — |
| **Location** `LocationStatusRow` | permission | Cell fixed | Static | — | — |
| **Media** `MediaCardTile` | playing | `GlassTile` | Inherits | `GlassTileFace` | — |
| **MediaRemote** `RemoteIconButton` | pressed | 0.12 snappy | OK, move to token | `quick` | existing |
| **MediaRemote** `PowerButton` | power | Not animated | Fix | `state` | `MediaRemoteTests` |
| **MediaRemote** `AppTile` | active | `GlassTile` | Inherits | `GlassTileFace` | — |
| **RoomDevices** `GrillControls` flame badge | on/off | Fill jumps | Fix | `state` | `RoomDevicesTests` |
| **RoomDevices** `DeviceStatusPill` | status | Not animated | Fix | `state` (or adopt `StatusPill`) | `RoomDevicesTests` |
| **RoomDevices** `BathroomFanRoomTile` | power, lock | `GlassTile` | Inherits | `GlassTileFace` (fan lane owns the layout) | — |
| **Rooms** `RoomCardTile`, `QuickLinkTile` | active, alarm fill | `GlassTile` | Inherits | `GlassTileFace` (fillRGB is part of the key) | — |
| **Rooms** `RoomChip` | filled | `StatusChipButton` | OK | — | — |
| **Security** `SecurityDoorTile`, `LockTile`, `GarageDoorTile` | open/closed, locked/jammed | `GlassTile` | Inherits | `GlassTileFace`; lock glyph `.symbolEffect(.replace)` | `SecurityTilesTests` |
| **Security** `AlarmModeButton` | selected, mode | Fill and ink jump | Fix | `state` (the selected fill carries `.tintedGlassEdge`, which fades with it) | `SecuritySystemSheetTests` |
| **Security** `AlarmPanel` | alarm state, triggered | Overlay jumps | Fix | `state` (no pulse: the triggered colour holds steady) | `SecuritySystemSheetTests` |
| **Settings** `HouseholdActionTile`, `VehicleDoorsTile`, `GlassStateTile` | active | `GlassTile` | Inherits | `GlassTileFace` | — |
| **Settings** `AppIconChoiceButton` | selected | Check jumps | Fix | `quick` | `AppIconTests` |
| **Settings** `SettingsLinkRow`, `FeedbackAttachmentTile` | none | — | Static | — | — |
| **Sprinklers** `DayPicker` | day on | Fill jumps | Fix | `state` | `SprinklerControllerTests` |
| **Sprinklers** `SprinklerRow`, `ProgramRow`, `SprinklerControllerRow` | active, enabled | Ink jumps | Fix | `state` | `SprinklerControllerTests` |
| **Vacation** `TravelerTileView` | selected | `GlassTile` | Inherits | `GlassTileFace` | — |
| **Vacation** `VacationChecklistRow` | checked | Opacity jumps | Fix | `quick` | `VacationTests` |
| **Vacation** `AwayActionButton` | role | Fixed | Static | — | — |
| **Vacuums** `VacuumsPage` tiles | active | `GlassTile` | Inherits | `GlassTileFace` | — |
| **Vacuums** zone chip (`VacuumRoomsTab`) | selected | Fill jumps | Fix | `state` | `VacuumTabsTests` |
| **Vacuums** `VacuumAreaEditor` tool button | active tool | Fill and ink jump | Fix | `state` | `VacuumAreaEditorTests` |
| **Vacuums** `VacuumStatusChip` | tint | Ink jumps | Fix | `state` | `VacuumComponentsTests` |
| **Vacuums** `VacuumOrderChip`, `VacuumActionButton`, `VacuumSettingRow`, map | none at runtime / disabled | — | Static (disabled uses `quick`) | — | — |
| **Vacuums** `VacuumSheet` content swap | tab, mode | `SmoothContentSwap` | OK, move to token | `quick` / `standard` | existing |

## Live Activities (`FentonActivityViews`)

| Component | Status | Why |
|---|---|---|
| `ActivityRing`, `SeverityCircle`, `ActivityButtons`, `JobCardView`, `ProblemCardView`, island and Lock Screen views | System | ActivityKit animates between content updates with its own default transitions; we can't drive animation inside a Live Activity (see [live-activities-per-job](../platforms/apple/live-activities-per-job.md)). We don't add any. The in-app Live Activity gallery shows the before and after states. |

## How it is validated
1. **One helper.** `.stateColorTransition(value:)` (`HassDesign/Motion/StateColorTransition.swift`) is the only way a state colour animates. It applies `MotionTokens.state` (Reduce Motion aware) and records its use through `MotionAudit` in debug and test builds.
2. **Unit test per Fix row**, named in the Test column. It flips the state input and asserts:
   - the colour key changed;
   - the component's view registers a `MotionAudit` entry for the state transition, so dropping the helper fails the test.
3. **Motion gallery** (`Features/Gallery/MotionGallery.swift`). Every component in this file with a state appears with a "Toggle state" control and a "Toggle all" control, under Reduce Motion both on and off. People use it to watch the fades. UX and accessibility tests on iPhone, Duo and iPad toggle each component and assert that its accessibility value changes, its targets stay ≥44 pt and its frame doesn't move. The frame check holds the "no layout rides along" rule.
4. **Lint.** `tools/lint_motion.sh` flags a state-driven `.background`, `.fill` or `.foregroundStyle` whose argument is a ternary on state, inside a component listed as Fix or OK here, without `.stateColorTransition` in the same view. The allowlist names a reason for each entry.
5. **Perf.** Toggling all components on the gallery stays inside the run-loop budget in [motion.md §10](motion.md) (p95 ≤ 8 ms). A colour cross-fade on a scrolled-off component costs nothing.

## Implementation status (motion lane, `claude/motion-system`)

Every row above is built except the ones marked **open**. The audit name is what `MotionAudit` records and the named test asserts; the Motion gallery id is the row's card on `FENTON_GALLERY=motion`.

| Row | Status | Audit name | Test | Gallery id |
|---|---|---|---|---|
| `GlassTile` / `GlassTileFace` (and the 17 inheriting tiles) | Done: ground, rim, ink, glyph and tinted stroke under `TileColorKey`; lock-style symbols replace (`.symbolEffect(.replace)`) | `GlassTile` | `ComponentMotionTests` (key per input, transition bound) | `glassTile`, `glassTileLight`, `glassTileError` |
| `BrightnessTile` | Done: tint through the face; level band on `quick` | `GlassTile` | `ComponentMotionTests` | `brightnessTile` |
| `StatusPill` | Done: icon and capsule | `StatusPill` | `ComponentMotionTests` | `statusPill` |
| `StatusChipButton` | Done: `MotionTokens.state`, `colorAnimation` removed | `StatusChip` | `MotionComponentsTests` | `statusChip` |
| `PrimaryButton` | Done: disabled opacity on `quick` | `PrimaryButton` | `ComponentMotionTests` | `primaryButton` |
| `ModuleRowButtonStyle`, `ModuleRow` inks | Done: instant down, `quick` release; glyph and subtitle inks fade | `ModuleRowButtonStyle`, `ModuleRow` | `ComponentMotionTests` | `sprinklerControllerRow` |
| `SelectableOptionRow` | Done: stroke `state`, check `quick` | `SelectableOptionRow` | `ComponentMotionTests` | `selectableOptionRow` |
| `FilterOptionRow`, `OptionPickerSheet` rows | Done: check `quick` | `FilterOptionRow`, `OptionPickerSheet` | `ComponentMotionTests` | `filterOptionRow` |
| `FloatingActionBar` | Done: glass tint, glyph | `FloatingActionBar` | `ComponentMotionTests` | `floatingActionBar` |
| `ThermostatDial` | Done: marker, handles, trails | `ThermostatDial` | `ComponentMotionTests` | open (needs a dial configuration; the thermostat-dial gallery shows it) |
| `CachedImage`, `NavigationFlyout`, `HouseBackdrop`, weather panels, `CameraLiveView`, `TodoPageView`, inventory and recipes split | Done: moved onto tokens | n/a | `tools/lint_motion.sh` | n/a |
| `ProfileButton` badge | **Open**: the header lane owns `ShellHeader`; add the 0.2 s fade after `claude/header-profile-fill` merges | | `ProfileButtonTests` | |
| `ChoiceGrid`, `WeekdayPicker` | Done | `ChoiceGrid`, `WeekdayPicker` | `MotionComponentsTests` | `choiceGrid`, `weekdayPicker` |
| `CameraControlButton` | Done: glyph and tint overlay | `CameraControlButton` | `MotionComponentsTests` | `cameraControl` |
| `TodoItemRow`, `DueLabel` | Done: check, title and due inks | `TodoItemRow`, `DueLabel` | `MotionComponentsTests` | `dueLabel` |
| `ClimateNotice`, `ThermostatHubPill` | Done | `ClimateNotice`, `ThermostatHubPill` | `MotionComponentsTests` (`ClimateNotice`); the pill needs a `ClimateController` | `climateNotice` |
| `ClimateToggleRow`, `HubPicker` | System toggle and menu: nothing of ours to fade | | | |
| `EcoOptionDetail` | Done: check `quick` | `EcoOptionDetail` | needs a `ClimateController` | open |
| `LightingModeButton`, `OtherLightSwatch` | Done | `LightingModeButton`, `OtherLightSwatch` | `MotionComponentsTests` | `lightingMode` |
| `GroceryAction` | Done: the button/confirmation swap fades, the check replaces | `GroceryAction` | needs a `RecipeDetailModel` | open |
| `WeatherBarChart`, `WeatherPagedCarousel` | Done | `WeatherBarChart`, `WeatherPagedCarousel` | `MotionComponentsTests` (`WeatherBarChart`) | open |
| `InventoryRow` | Done: selected wash | `InventoryRow` | needs an `InventoryModels` | open |
| `PowerButton` (`RemoteButtonIcon`) | Done | `RemoteButtonIcon` | needs a `MediaRemoteController` | open |
| `GrillControls` flame badge, `DeviceStatusPill` | Done | `GrillControls`, `DeviceStatusPill` | `MotionComponentsTests` | `deviceStatusPill` |
| `AlarmModeButton`, `AlarmPanel` | Done: fill, ink, triggered wash (steady, no pulse) | `AlarmModeButton`, `AlarmPanel` | `MotionComponentsTests` | `alarmMode` |
| `AppIconChoiceButton` | Done: ring | `AppIconChoiceButton` | `MotionComponentsTests` | open |
| `DayPicker`, `SprinklerRow` | Done | `DayPicker`, `SprinklerRow` | `MotionComponentsTests` | `dayPicker`, `sprinklerRow` |
| `VacationChecklistRow` | Done | `VacationChecklistRow` | `MotionComponentsTests` | `vacationChecklistRow` |
| `VacuumRoomsTab` cards, `VacuumAreaEditor` tools | Done | `VacuumRoomsTab`, `VacuumAreaEditor` | need a `VacuumController` | open |
| `VacuumStatusChip` | Done | `VacuumStatusChip` | `MotionComponentsTests` | `vacuumStatusChip` |
