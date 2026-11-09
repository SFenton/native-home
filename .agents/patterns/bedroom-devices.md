# Bedroom devices (wake light, bed sides)

> **What:** the Primary Bedroom's Wake-Light Alarms and bed sides: tiles, sheets, alarm editors, the active alarm and the Tonight/All Nights prompt. **Read when:** placing these on a page, touching wake-light or bed alarms, or changing Solo Trip bed behavior.

Web source: `ha-sfenton-react-dash@9ac2a46:src/components/hass/wakeLights/*`, `src/pages/DashboardViewPage.tsx:3522-6318` (Bed), `src/components/hass/{BedTemperatureScopePrompt,SleepypodActiveAlarmSection}.tsx`. Spec: `plans/bedroom-devices-spec.md` in the project files. Integrations: `SFenton/ha-wake-light`, `SFenton/eight_sleep`.

| Piece | File |
|---|---|
| Entity ids, sides, wake-light sources | `HassCore/Bedroom/BedroomConfig.swift` |
| Stages, levels, alarm records, schedule payloads | `HassCore/Bedroom/SleepypodSchedule.swift` |
| Wake-light contract (snapshot, commands, copy) and "Add to bed" planning | `HassCore/Bedroom/WakeLightContract.swift` |
| `return_response` service calls and command outcomes | `HassCore/Bedroom/ServiceResponses.swift` |
| Solo Trip bed scope (stand-in until the Vacation lane's `HouseholdAwayController` lands) | `HassCore/Bedroom/HouseholdAwayScope.swift` |
| Wake-light controller (optimistic intents, serialized queue) | `HassCore/Bedroom/WakeLightController.swift` |
| Bed side controller | `HassCore/Bedroom/BedSideController.swift` |
| Room bundle (wake light + both beds, provisioning) | `HassCore/Bedroom/BedroomDevices.swift` |
| Wake-light sheet shell and Wake Alarms tab | `HassUI/Features/Bedroom/WakeLightSheet.swift` |
| Wake-light Defaults tab | `HassUI/Features/Bedroom/WakeLightDefaultsTab.swift` |
| Wake-light alarm editor | `HassUI/Features/Bedroom/WakeLightEditor.swift` |
| Wake-light room tile | `HassUI/Features/Rooms/RoomTiles.swift` (the room page card; the dedicated tile view is deleted) |
| Bed sheet shell (hero, tabs, pushed routes, power-off prompt) | `HassUI/Features/Bedroom/BedSideSheet.swift` |
| Bed dial mapping | `HassUI/Features/Bedroom/BedDial.swift` |
| Tonight or All Nights copy | `HassUI/Features/Bedroom/BedScopeCopy.swift` |
| Active alarm card (Snooze, Stop) | `HassUI/Features/Bedroom/BedActiveAlarm.swift` |
| Temperature tab (stage levels) | `HassUI/Features/Bedroom/BedScheduleTab.swift` |
| Special Modes tab (Hot Flash) | `HassUI/Features/Bedroom/BedSpecialModesTab.swift` |
| Alarms tab, day page, alarm editor | `HassUI/Features/Bedroom/BedAlarmsTab.swift` |
| Status tab | `HassUI/Features/Bedroom/BedStatusTab.swift` |
| Bed side room tile | `HassUI/Features/Rooms/RoomTiles.swift` (the room page card; the dedicated tile view is deleted) |
| Shared rows, notices, choice grid, day picker | `HassUI/Features/Bedroom/BedroomComponents.swift` |
| Debug gallery (`FENTON_GALLERY=bedroom`) | `HassUI/Features/Gallery/BedroomGallery.swift` |

## Using it

- **Selection checkmarks (one rule).** The selected choice in a `ChoiceGrid` tile or a `WeekdayPicker` chip always draws a checkmark, with a bold (weekday) or semibold (tile) label, whatever the Differentiate Without Color setting (`selectionShowsCheckmark`). Selection is never fill and ink alone.

```swift
@State private var bedroom = BedroomDevices(store: connection.store, caller: connection, canEdit: user.isAdmin)

// The room tiles are the room page's own cards (``RoomCardView``: the wake light, and each bed side as a navigation tile with a
// Power disc whose turn-off is confirmed). `BedSideTile` and `WakeLightTile` were deleted (tile rollout R): one tile path.
ForEach(rooms.page.allCards) { card in RoomCardView(controller: rooms, card: card, fan: nil, bedroom: bedroom) { sheet = sheet(for: card) } }

.sheet(item: $sheet, onDismiss: { if let next = queued { queued = nil; sheet = next } }) { sheet in
    switch sheet {
    case let .wakeLight(tab): WakeLightSheet(devices: bedroom, initialTab: tab) { side in queued = .bed(side, .alarms) }
    case let .bed(side, tab): BedSideSheet(devices: bedroom, side: side, initialTab: tab)
    }
}
.hassSheet(.page)
```

"Open Linked-Device Alarm Editor" closes the wake-light sheet and asks the host to open that bed on Alarms; queue it until the first sheet is dismissed (see `BedroomGallery`). Create one `BedroomDevices` per page, not per tile, so both sheets share pending edits.

## Behavior

- **Home Assistant wins.** Every control shows its change at once and gives way to the live state when it confirms, when a call fails or is refused, or after its revert time (wake light 8 s; bed power, target and stages 30 s; snooze/stop 10 s; alarm lists 30 s or the schedule echo). Bed entities keep their last state for 10 s of unavailability.
- **Wake-light commands** go through `wake_light.command` with `return_response`; `accepted` and `no_change` count as success (`no_change` drops the edit quietly), anything else rolls back and shows the copy for its error code, 10 s without a reply is a transport error. Configuration commands run one at a time; Stop Wake-Light Episode skips the queue. A revision conflict on the edited alarm offers "Open Latest Alarm, Replace Draft".
- **Bed target.** The dial commits on release (no debounce). During a stage it sets tonight's target, then asks Tonight or All Nights; All Nights also sets that stage's `input_number`. Outside a stage it calls the outside-schedule script. A stage change drops a pending target and the question.
- **Stage steppers** batch presses for 300 ms, then `input_number.demo_level_1` plus an MQTT schedule rewrite; stepping the running stage goes through tonight's target and the question.
- **Bed alarms** batch for 450 ms, then publish the side's full alarm list on `sleepypod/eight-pod/cmd/set-schedules`. Saving or deleting first sets the wake-light link for that day and time and saves nothing if that is refused.
- **"Add to <bed>"** (new weekly wake alarms) creates missing bed alarms and turns links on; turned off, it turns existing links off. It never deletes bed alarms. One-time alarms send `bed_sides`.
- **Solo Trip.** The home resident's side controls the whole bed through `script.demo_ext_13` (`sleepypod_command`: `set_power`, `set_outside_level`, `set_tonight_level`, `set_stage_level`, `replace_alarms`, `snooze_alarm`, `stop_alarm`); the traveler's side is read-only.
- **Layout.** Bed sheet: hero (dial, power, hint, active alarm) beside the tabs only where a split is allowed (iPad and unfolded Duo in landscape, sheet ≥ 640 pt); stacked everywhere else. Alarm day pages and editors push inside the sheet. Tabs are the sheet's bottom `modalTabBar` (`bed.tabs`, `wake.tabs`), a menu at accessibility text sizes.
- **Contrast.** The app accent (light blue) fails as text on the cards: links use `HassTokens.Ink.primary`; the wake light's Stop and Delete use `BedroomStyle.danger` filled (deep red, white label ~6:1, not system red at 3.6:1). Snooze and the power button are grey bordered capsules with primary ink; Add, Save and Stop Alarm use `PrimaryButtonStyle` (#0071E3, white label) and selected chips `HassTokens.Ink.actionFill`. Cards and rows sit on `HassTokens.Surface.sheetCell`; bed tiles fill with the side's action family (heating or cooling), Hot Flash with cooling, the wake light with lights (direction G).
- **Accessibility.** Dial handle reads "<Name>'s Bed target level, +3" and adjusts by one step; stage rows are adjustable; confirmation dialogs guard turning a side off and deleting alarms; every control is ≥ 44 pt.
- **Departures from web.** Bed climate mode only (the legacy Free Sleep path and its Settings tab are not ported); no debug MQTT topic; the 3 s target confirmation hold is dropped because the dial commits on release; tile titles use the bed name, not "Your Side"; the wake-light bar titles drop the room name ("Primary Bedroom Wake-Light Alarms" clipped at AX5); the traveler's side shows no disabled power button during a Solo Trip, only the "Away · Read Only" hint.
- **Tests.** `HassCoreTests/BedroomContractTests.swift`, `HassCoreTests/BedroomControllerTests.swift`, hosted renders in `HassUITests/BedroomViewTests.swift`, journeys and audits in `Apps/iOSUITests/Bedroom*JourneyTests.swift` (area classes over `BedroomJourneyTestCase`) against the gallery (`FENTON_GALLERY_SCENARIO`, `FENTON_GALLERY_SHEET`, `FENTON_GALLERY_TAB`).
