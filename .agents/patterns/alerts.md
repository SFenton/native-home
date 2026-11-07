# Alerts and confirmations

> **What:** how the app asks "are you sure?" and reports a failure: one presenter, one set of words, one role per decision. **Read when:** you add or change an alert, a confirmation dialog or a delete button.

- Proposal and decision: [alert-conventions](../design/mockups/proposals/alert-conventions/alert-conventions.html), decided 2026-10-24. HIG: Alerts, Action sheets.
- Canonical copy and presenters: `HassUI/Common/AlertCopy.swift`. **All alert and dialog copy lives in the `AlertCopy` namespace** (like `LoginCopy`): a `Spec` (title, optional message, confirming `Action`, Cancel) per decision, with `Action.Role` (`plain`, `destructive`, `cancel`) so the tests state roles. Never write an alert title or button as a literal in a view. Two modifiers present a spec: `alert(_:isPresented:confirmID:cancelID:onCancel:onConfirm:)` (and an `item:` variant that hands the item to the button) and `confirmationDialog(_:isPresented:confirmID:onConfirm:)`.
- Tests: `AlertCopyTests` (strings, roles, the long-name rule, the grocery rule). A new alert adds its spec there.

## The rules

| Rule | Convention |
|---|---|
| Presenter | An **alert** for a yes or no about a state change or a session (Sign Out, Disarm, Turn Off Vacation Mode, Use Rooms, Use Area, End Solo Trip, Reset All Lights, Apply to All Lights, Reset Measurements, High AQI Mode). A **confirmation dialog**, attached to the control that raised it, for deleting a thing (alarm, activity, task, item), so the iPad popover anchors to it. The same decision uses the same presenter on every path. |
| Title | Title Case, a short question naming the object ("Turn Off Vacation Mode?"); never "Are you sure you want to...". At most two lines at default size. |
| Delete | Button "Delete <Noun>" (Alarm, Activity, Task, Item); title "Delete <name>?". A name longer than `AlertCopy.titleNameLimit` (28) moves to the message and the title is "Delete <Noun>?". `AlertCopy.delete(_:named:detail:)` builds it. |
| Role | Destructive only where data or the session is lost: Delete, Sign Out, Reset Measurements. Disarm, Turn Off, Use Rooms or Use Area (owner, 2026-10-28: not "Switch to"), End Solo Trip and the bulk light resets are **plain**, and the plain confirming button is the bold default (`.keyboardShortcut(.defaultAction)`). A destructive button is never the default. |
| Cancel | Every alert and dialog has "Cancel" with the cancel role, leading. A dialog lists it too; a popover drops it by itself. |
| Failure | Say what happened and offer the next step: "Couldn't Sign Out" / "Signing out needs a connection so this phone stops reporting its location. Connect and try again." with Try Again and Cancel. One string per failure, shared by every site. |
| Retry label | "Try Again" everywhere (`AlertCopy.tryAgain`): Recipes, Inventory, the Home Assistant web page, a failed sign-out. |
| Confirm or not | Confirm what is bulk or hard to undo (every light, the whole telemetry log, ending a Solo Trip, a single-unit inventory delete from the editor as from the page). Do not confirm what is cheap to redo: grocery removal goes at once (the swipe is the deliberate act), Clear Image Cache is instant. High AQI Mode is reversible but changes every purifier at once, so it asks (`AlertCopy.highAqiMode(turningOn:)`, owner 2026-10-26; `HouseholdToggleTile(confirmation:)`). |
| Validation | An invalid quantity in a quantity prompt cannot keep the alert open; it reports on the row (`InventoryPresentation.submit`). |
| Discard guard | Not here: the form sheets' "Discard changes?" guard is owned by the sheets pattern ([modal-sheet](modal-sheet.md)). |

## Sites

Sign Out: `YourSummarySheet`, `HomeAssistantSettingsView` (the failure alert is a sibling of the Sign Out button so the button owns one presenter). Vacation: `VacationModeScreen`. Alarm: `SecuritySystemSheet`. Vacuum: `VacuumControlsTab` (the Use Rooms and Use Area tiles), `View.switchToRoomsAlert` (room tiles and map, one presenter). Solo Trip: `SoloTripScreen`. Lights: `CustomLightsScreen`, `CustomLightSheet`. Diagnostics: `PerformanceScreen`. Deletes: `WakeLightSheet`, `BedAlarmEditor`, `HumidifierSchedulesTab`, `DonetickTaskFormFields` (on the Delete Task button), `TodoListSection` (on the row; `TodoListSection.Deletion` says confirm, immediate or unavailable), `InventoryRow` and `BatchSection` (on the row or the Delete button).

## Guards

Checked by `python3 tools/pattern_guard.py` against `contracts/patterns.json` (comment lines are ignored).

- `alerts/literal-alert-title`: Alert and dialog titles come from AlertCopy, never a literal in a view (alerts). Scans `HassUI/Features/**/*.swift`.

### Known debt

Each file below still breaks its guard and is allowed until it is fixed; remove the row and the registry `debt` entry together.

| File | Guard | What to do |
|---|---|---|
