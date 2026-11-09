# Action tiles

> **What:** the one way a tile shows and runs actions: trailing or below discs, the chevron beside them, feedback kinds, availability motion. **Read when:** giving any tile an action button, a chevron with actions, or a read-only face.

Decision: [action-navigation-tiles](../design/action-navigation-tiles.md) (owner, option B, 2026-10-26). Architecture and tests: [architecture.md](../design/mockups/proposals/action-navigation-tiles/architecture.md). **Status: first build merged (#186); rollout in progress on `claude/tile-rollout`** (lane F, the shared foundations, is in; each feature lane adopts them in its own folder). Defaults the build chose where the decision was silent are in [the decision doc](../design/action-navigation-tiles.md#defaults-chosen-in-the-build).

- **Components (built):** HassCore `TileActions/`: `TileActionSpec`, `TileActionProviding` (+ `stateTextCandidates`), providers `LockActions`, `CoverActions` (morphing garage disc), `PowerToggleActions`, `MediaTransportActions`, `FanRailActions`, `VacuumActions`, `TileActionCatalog`, `TileClassification`. HassDesign `TileActions/`: `TileActionItem`, `TileActionButtonStyle`, `TileActionInk`, `TileActionSymbolTransition`, `TileActionStrip`, `TileVolumeSlider`, `TileActionSetTransition`; `TileActionPlacement` and `TileBehavior`; `GlassTile(…, behavior:, actions:, perform:)`; `TileMinimumWidth` and `TileTextMeasure`. HassUI `Features/TileActions/TileActionItem+Spec.swift` maps spec → item and classification → behaviour (HassDesign has no HassCore dependency); `RemoteTileSupport.swift` holds the remote's transport. Never hand-build a disc or a rail in a feature.
- **Grid (owner, 2026-10-30):** every tile has one minimum width (150 pt) and a grid fits up to four per row, leading aligned, all tracks equal; a tile never takes more tracks for its text (see [dynamic-grid](dynamic-grid.md), one tile rule). `TileMinimumWidth` no longer changes spans. Three `ViewThatFits` variants, no measurement feedback: natural one line, then a ticker with discs trailing down to the 96 pt text floor, then a ticker with the strip below.
- **Transport:** a playing remote shows prev, play/pause and next below its text and a `TileVolumeSlider` (writes on release); off shows Power beside the chevron.
- **Classes:** action (*text · disc*, body does the disc's action), navigation (*glyph · text · chevron*, up to two discs left of the chevron, more below), read-only (glyph, flat face).
- **Feedback kinds:** momentary, optimistic, tracked; declared by the provider and tested.
- **Availability:** one action unavailable dims in place; a changing action set animates height (full-row tiles only, motion.md §6 exception).
- **Text:** one line; a ticker (or the strip below) when the track is too narrow, never a wider tile; wrap under Reduce Motion and accessibility sizes.
- **Choice indicator (selection tiles).** A choice is `TileActionItem.selection` (`TileSelection`: `.single(isSelected:)` a check, `.ordered(position:)` the 1-based number): see the Selection face under Rollout foundations. The vacuum's Rooms and Auto-Clean tiles (`VacuumChoiceTile`, #210) use it; use it for any multi-select grid instead of a switch or checkmark row.
 **Accessibility:** a single-action tile is one element (the disc hidden only when it repeats the body exactly); otherwise the body plus each disc as a button labelled "verb title"; identifiers `<tile-id>.action.<spec.id>`.

## Rollout foundations (lane F, `claude/tile-rollout`, owner 2026-10-27)

What a feature lane uses; none of it is wired into a screen yet. Decision: [Rollout to every page](../design/action-navigation-tiles.md#rollout-to-every-page-owner-2026-10-27).

- **Providers** (HassCore `TileActions/`, each a pure value type with its own suite in `Tests/HassCoreTests/TileActions/RolloutProvidersTests.swift`):

  | Provider | Tile | Disc | Feedback | Notes |
  |---|---|---|---|---|
  | `CommandActions` | Admin power recovery (`.powerRecovery`) | action glyph (`bolt.fill`), label "Run power recovery" | momentary | optional `confirmation`; optional availability entity dims it |
  | `SourceSelectActions` | Studio sources (`.musicRoom(.console/.server/.pc/.launcher)`, the roles of `media.sourceSelect`) | selection: `checkmark` / `circle` | optimistic | chosen when `sensor.demo_studio_source_1` is one of `selectedStates` (Game Console also reads chosen for Game); chosen tap = `script.demo_ext_7`, label "Turn Off TV"; Game keeps today's relaunch. The view's `OptimisticActions` tracks `SourceSelectActions.trackedEntityIds` |
  | `ScriptPowerActions` | Handheld Console, Media Room Streamer (`ScriptPowerActions.all`, the document's `media.scriptPowerDevices`) | toggle-styled `power` | **tracked** | see below |
  | `BedSidePowerActions` | bed sides on the room page | toggle-styled `power` | optimistic | turning off carries a destructive **dialog** "Turn off <Name>'s Bed?"; no `call` (the bed controller's `setPower(on:)` owns the effect); `isReadOnly` (a Solo Trip traveler) dims it |
  | `HotFlashActions` | Hot Flash Mode in the bed sheet | `snowflake` → `stop.fill`, not toggle-styled | optimistic | one id `hot_flash`, labels "Start/Cancel Hot Flash Mode"; body and disc both cancel; the bed controller also commits power on start |
  | `AlarmModeActions` | Quick Links Security System | `shield.lefthalf.filled` "Arm Home" → `shield.slash` "Disarm" | tracked | Disarm carries `AlarmModeActions.disarmConfirmation` (= `AlertCopy.disarm`); only `disarming` is in flight; `arming` and `pending` (the exit and entry delays) keep a tappable Disarm |
  | `SprinklerActions` | sprinkler controller card | `stop.fill` "Stop Watering" | momentary | ready while a valve is `open` / `opening`, **dimmed in place** while idle; `actions(for: SprinklerSnapshot)` picks the active valve |
  | `SelectionActions` (not a provider) | vacuum rooms, Solo Trip travelers | builders `single(isSelected:)`, `ordered(position:)` | optimistic | the choice lives in a controller that already owns it, so there is no entity to read and no `call`: the body and the disc both run the feature's own toggle |

  `TileActionKind` gains `momentaryCommand`, `sourceSelect`, `scriptPower`, `bedSidePower`, `hotFlash`, `alarmMode`, `sprinkler`, `selection`. `TileActionCatalog` maps the Studio source cards and the Switch/Streamer cards (room page and Media page) today; beds, Hot Flash, Quick Links and sprinklers have no configured `Entry` yet, so their lane adds the mapping with the screen (a bed card changing from navigation(0) to navigation(1) is a visible change).
- **Confirmation.** `TileActionSpec.confirmation` (`title`, `message`, `confirmVerb`, `isDestructive`, `style` alert or dialog) maps to HassDesign's `TileActionConfirmation` on `TileActionItem`. `GlassTile` asks for a disc tap **and** for a body tap that performs that action (`TileActionConfirmation.required(forPerforming:in:)`, pure), and runs `perform` only on confirm; Cancel does nothing, and a waiting or unavailable action never asks. Identifiers `<tile-id>.confirm` and `<tile-id>.cancel`. Words come from `AlertCopy`: `TileActionSpec.Confirmation(AlertCopy.disarm)` (HassUI) builds one, so the tile and its sibling sites ask the same question ([alerts](alerts.md)). A provider sets `confirmation` only on the spec that needs it (the bed's turn *off*, the alarm's *Disarm*); Front Door stays one tap.
- **Selection face** (option C). A spec with `selection` (`.single(isSelected:)`, `.ordered(position:)`) is drawn by `TileSelectionIndicator` inside the 44 pt target: a 28 pt ring while not chosen, a white disc with the family-fill `checkmark` or the cleaning order while chosen. `GlassTile` makes the tile's `isActive` and its `kind` (`.selection(isSelected:)`) from the item, so a chosen tile fills in its family colour and VoiceOver reads the *selected* trait, never a switch or On/Off (`TileActionStrip.traits(for:)`, `value(for:)`). Tile ground and disc ink come from `TileActionInk` (white disc, family glyph). Motion: choosing fills the ring and scales the check in from 50% (`quick`); a number that changes rolls (`numericText`); Reduce Motion cross-fades for 0.2 s (`stateReduced`) with no scale or roll, forced in tests by `reduceMotionOverride`. A one-action selection tile is one element (disc hidden, hint = verb); beside other actions the disc is its own selected button.
- **A whole label.** `TileActionSpec.label` replaces "verb title" when the verb already names the object ("Turn Off TV", "Cancel Hot Flash Mode", "Run power recovery").
- **Tracked power through a script** (`ScriptPowerActions`; the lock's mechanism, reused). Off: "Turn On" runs the tile's own script. On: "Turn Off" runs `script.demo_ext_19`. The view builds the specs with `actions(live:pending:onScript:offScript:)`, where `live` is the `input_boolean.demo_input_boolean_*_active` state (the glyph and fill move only when it reports), `pending` is `actions.overlay.pending[activeId]` and the two scripts are their `script.*` states. In flight is `pending != live`, or either script `on`. The tap goes through `OptimisticActions.perform(spec)`, which commits the spec's `tracking` intent (the target on the boolean, rule `.confirmation`, 45 s, `failsOnTimeout`), so a rejected call or a state that never arrives shows "Didn't Respond" (`actions.isFailed(activeId)`) and the disc animates back. `OptimisticIntent` gained `failsOnTimeout`.
- **Accessibility identifiers.** Unchanged scheme `<tile-id>.action.<spec.id>`: `source`, `power`, `hot_flash`, `alarm`, `stop`, `select`, `power_recovery`; plus `<tile-id>.confirm` / `.cancel` for the question.
- **Wiring a feature view** (what a lane writes):

```swift
let provider = SourceSelectActions.musicRoom(.console)
let specs = provider.actions(for: store.entity(provider.entityId).state)
GlassTile(title: "Game Console", subtitle: nil, symbol: "gamecontroller", family: .media, isActive: false,
          behavior: TileBehavior(classification, primary: SourceSelectActions.actionId),
          actions: specs.items, perform: { id in if let spec = specs.first(where: { $0.id == id }) { actions.perform(spec) } })
    .tileStateCandidates(provider.stateTextCandidates)
    .tileIdentifier("media.source.xbox")
```
  `isActive` is overridden by a selection item. For an alarm, bed or Hot Flash tile, `perform` calls the feature's own controller for the spec id when the spec has no `call`.

## Rollout R: rooms, media and device sheets (`claude/tile-rollout`, lane R)

Adopted in `Features/{Rooms,Media,Bedroom,RoomDevices}`; the pure support is `Features/TileActions/RolloutTileSupport.swift`.

| Tile | Class and disc | Notes |
|---|---|---|
| Air Purifier, Humidifier (room page) | navigation + toggle-styled `power`, optimistic | `PowerToggleActions.entity` on `fan.<room>_demo_purifier` / `switch.demo_power_1` (`TileActionCatalog.powerEntityId(of:)`); the purifier tile fills with the fan, not its mode select |
| Vents | navigation, no disc | stays as it was; read-only in the climate sheets |
| Bed sides | navigation + `power`, off is confirmed (dialog) | `BedSidePowerActions` fed the controller's shown power; the disc runs `BedSideController.setPower(on:)`; mapped as `.bedSidePower` (`TileActionCatalog.bedSide(of:)`) |
| Studio sources (room page, Media page, Game) | action + selected face, check disc | `SourceSelectActions`; the tap is today's toggle through the shared `MediaRemoteController` (chosen = TV off, Game relaunches); state line "On the TV" while chosen, none otherwise; Game Console and Game both read chosen with Game active |
| Handheld Console, Media Room Streamer (room page, Media page) | action + toggle-styled `power`, tracked | `ScriptPowerActions` through `RolloutTileSupport.scriptSpecs` / `scriptActions`; "Turning On…" / "Turning Off…" while in flight, then On / Off; "Didn't Respond" on failure |
| Hot Flash Mode (bed sheet) | action, snowflake -> stop | `HotFlashActions`; the body cancels while it runs; the countdown is the state line; the separate cancel button is gone |
| Bathroom fan sheet Power, Lock | action | `FanRailActions` (`BathroomFanController.railSpecs`) one disc each; `fan.power` / `fan.lock` identifiers kept; the Lock tile now reads its state line ("Locked"), not On / Off |
| Grill Keep Warm, Smoke Boost | action + `power` | `PowerToggleActions.entity`; the readings stay flat |

One tile path: `BedSideTile`, `WakeLightTile` and the dead `RemoteGlassTile` are deleted. The Bedroom Devices gallery draws the room page's cards; the wake light remains the generic room card (it reads its status sensor), so its subtitle on the page did not change.

## Rollout L: lights, Custom Lights, overview rooms and Quick Links (`claude/tile-rollout`, lane L)

Adopted in `Features/{CustomLights,Rooms/QuickLinksSheet}` and `Common/RoomOverview`; vents in `Features/Climate` and the room sheets are unchanged.

| Tile | Class and disc | Notes |
|---|---|---|
| Light or switch, no dimming (room lights sheet, overview detail) | action + `power` | `LightGroupTile` through `PowerToggleActions.entity`; explicit `turn_on` / `turn_off`; the leading glyph goes (the disc carries it) |
| Dimmable light (`BrightnessTile`, no `onOpen`; the Custom Light sheet) | action + `power` | `BrightnessTile` is now a `GlassTile` with the drag laid over its body (`tileBodyOverlay`, `tileAdjustable`), so the disc is the pattern's; tap = power, horizontal drag = brightness, VoiceOver adjusts by 10 |
| Custom Lights page tiles | navigation + `power` | the same tile with `onOpen`: glyph, text, the disc left of the chevron; two tracks wide; **no disc while unavailable** (the mockup's choice, as today) |
| Home overview Lights room cards | navigation + room `power` | `RoomLightsPowerActions` (HassCore; not a `TileActionProviding`: it reads many entities): on = any light on; the call is one `turn_on` / `turn_off` on the room's group light (what the room's lights sheet makes for the whole room; web `toggleEntityId`); optimistic on the group and every light |
| Quick Links Security System | navigation + `alarm` | `AlarmModeActions`: Arm Home while disarmed, Disarm (confirmed with `AlertCopy.disarm`) while armed, the arc only while disarming (Disarm stays tappable through the exit and entry delays); **no disc while screenshots are redacted** (its verb and glyph would give the mode away) and none without a caller |
| Vents (Climate room detail, room card sheet, group detail) | read-only | already `kind: .state`; held by tests, nothing changed |

A tile with discs takes its identifier from `tileIdentifier` (a `.accessibilityIdentifier` set from outside is inherited by the disc and replaces its own): `LightGroupTile`, `BrightnessTile` and `QuickLinkTile` take it as a parameter. A navigation tile with a disc has no VoiceOver hint (a hint set from outside would also be read on the disc); `OpensHint` adds one to those without. `BrightnessTile`'s old `brightness.power` identifier is `<tile-id>.action.power`.

### Content-aware span, decided (owner, 2026-11-01)

A tile whose content (text, states, discs, chevron) does not fit two tracks takes its row; it is never squeezed to keep a column count. Two consequences are accepted: on the folded iPhone Duo the Quick Links **Security System** tile takes a full row, so the sheet is five rows and **scrolls** (the sheet is already at its largest height; the bottom-band check applies with the last tile scrolled into view); and on iPad a room page's **Air Purifier** (Living Room, Climate section) is a full-width tile beside the Devices section instead of a half-width one, so the proof that sections sit side by side is the sections' frames, not "three tiles across". Tests: `SheetBottomGapJourneyTests/testQuickLinksHasNoBandUnderItsTiles`, `TilesRound2JourneyTests/testQuickLinkTilesAreOneSizeAndColoured`, `AdaptiveLayoutJourneyTests/testRoomSectionsSitSideBySideOnIPad`.

## Rollout S: Settings, Household and Admin (`claude/tile-rollout`, lane S)

Adopted in `Features/Settings/Household`; the pure rules are HassCore `TileActions/HouseholdTileActions.swift`, the catalog lists every Settings tile as `settings.<entity>`.

| Tile | Class and disc | Notes |
|---|---|---|
| Front Door Auto-Lock | action + toggle-styled disc, `lock.fill` while on, `lock.open` while off | `PowerToggleActions.entity(_, symbol:)`; the mockup's glyph, not `power` |
| Relay Control Mode, Outdoor Faucets, Holiday Lights, the 14 Auto-Reset rooms, High AQI Mode | action + `power` | no leading glyph; state line On / Off |
| Power recovery | action, momentary `bolt.fill` | `CommandActions.powerRecovery`; keeps the red "Didn't Respond" from `controller.powerRecoveryFailed`; id `admin.powerRecovery` |
| High AQI Mode | as above, **confirmed** | the spec's `confirmation` is `AlertCopy.highAqiMode(turningOn:)` for the flip it would make (an alert); body and disc ask the same; ids `<tile-id>.confirm` / `.cancel` |
| Guest Controls | action + `power`, occupancy family | "Guests staying" / "No guests"; ids `guest.tile.<entity>` (the Home page's) |
| car Doors | action + lock disc, Settings blue | `LockActions` through `OptimisticActions` (`.liveChange`, shows "Unlocking" / "Locking"); the other four tiles stay read-only |

`HouseholdActionTile` replaces `HouseholdToggleTile`. The switch tiles keep `HouseholdSettingsController` as their engine (explicit `turn_on` / `turn_off` from the shown state, the optimistic value, the failed face and the spoken refusal); the spec only draws the disc and the tile's `perform` calls `controller.flip`. A single-action tile is one VoiceOver element, so the disc has no identifier of its own in the tree.

## Rollout M: Chores, Vacation, Sprinklers and Vacuums (`claude/tile-rollout`, lane M)

Adopted in `Features/{Chores,Vacation,Sprinklers,Vacuums}`; the pure rules are HassCore `TileActions/AwayTileActions.swift`, `ChoresConfig.openSubtitle` and the `SprinklerActions` shown-valve overload.

| Tile | Class and disc | Notes |
|---|---|---|
| Chores quick links | navigation, no disc | the open count moves into the state line, "3 open · 2 overdue" ("3 open", "Nothing open"; Groceries "3 open"); the numeral and `QuickLinkFace` are gone; ids `chores.link.<page>` |
| Vacation Mode card | action + toggle-styled `power`, **confirmed when on** | `AwayTileActions.vacationMode`; off opens the dates sheet (or shows the checklist error) through `VacationModeController.tapCard()`, pending shows "Cancel", on asks `AlertCopy.turnOffVacation` as the tile's confirmation and runs `confirmDisable()`; ids `vacation.modeCard`, `.confirm`, `.cancel` |
| Solo Trip toggle | action + `power`, **confirmed when on** | `AwayTileActions.soloTrip`; off opens the editor, on asks `AlertCopy.endSoloTrip`; dims until a traveler is chosen; ids `soloTrip.toggle`, `.confirm`, `.cancel` |
| Solo Trip travelers | action + selected face, check disc | `SelectionActions.single`; no leading glyph; locked trips dim the disc; fills in the **Vents** family blue (Solo Trip's own blue is not a family) |
| Sprinkler controller card | navigation + `stop.fill` | `SprinklerActions.actions(for:shownValve:)`; the tap is `SprinklerController.stopWatering()` (optimistic valve); dims the moment Stop is tapped and while idle; `isUnavailable` is not passed, so the card still opens its sheet offline; ids `sprinklers.controller.<id>`, `.action.stop` |
| Vacuums page robots | navigation + `start_pause` and `dock` | `VacuumActions` through `OptimisticActions` (as the room page's vacuum tile); ids `vacuums.tile.<map>`, `.action.start_pause`, `.action.dock` |
| Vacuum Rooms and Auto-Clean tiles | action + selected face (`TileSelection`), ring or numbered / check disc | superseded by the Vacuum sheet redesign (#210): `VacuumChoiceTile` / `VacuumChoiceTileView` build the tile on `.ordered(position:)` / `.single`; VoiceOver reads "selected" and the order or the Included / Skipped value from `VacuumSheetModel`; signpost and renumber motion are the selection face's |
| Selected Rooms / Full Clean | list row | kept from #210 (not a tile): the order chips, or the Full Clean warning, in a module row that opens the Rooms section; id `vacuum.selectedRooms` |

A tile with discs speaks no outside hint; the single-action tiles read the verb as theirs. The Vacation and Solo Trip confirmations moved from the screens' alerts to the tile (`vacation.disable.*` and `soloTrip.end.*` for the toggle became `<tile-id>.confirm` / `.cancel`; End Solo Trip Now in the status block keeps its own alert and `soloTrip.end.*` ids).

- **Owned files** (also in `contracts/patterns.json`): `TileActionDisc.swift`, `TileActionFace.swift`, `TileActionShape.swift`, `TileActionSlot.swift`, `TileVolumeInteraction.swift`.

## Momentary command tiles and availability (owner, 2026-11-03)

Question: "should the power-recovery tile dim and do nothing when its automation is unavailable, like other tiles?" Owner: "Yes". `CommandActions.powerRecovery` carries `availabilityEntityId` (the automation it triggers); the tile shows "Unavailable", dims and fires no `automation.trigger` while that entity is unavailable or missing. It is the only momentary command tile today; any new one sets its availability entity.
