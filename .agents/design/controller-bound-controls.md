# Controller-bound controls

> **What:** decided (owner picked O2, 2026-10-24) removal of the `Binding(get:set:)` closures in `HassUI` that forward to controllers, found by the 2026-10 swiftui-pro review of the mockup atlas. **Read when:** you are asked to fix that finding, or add a toggle, stepper or picker that sends a Home Assistant command.

Status: **decided 2026-10-24 (owner picked O2)**, built on `claude/wonderful-fermat-528916`. Proposal ([propose-first](../workflow/propose-first.md)), mockup and echo/failure simulator: [controller-bound-controls.html](mockups/proposals/controller-bound-controls/controller-bound-controls.html). 
## Built

`HassDesign/ControllerControls.swift`: `ControllerBinding.make/action`, `ControllerToggle`, `ActionToggle`, `ControllerStepper`, `ControllerPicker`; tests in `ControllerControlsTests`. Migrated: Sprinklers, Humidifier (timer, display, schedules), Climate (toggle row, Predictive Comfort, HubPicker), Vacuums (autoClean, setting picker), BedAlarmToggle, WakeLight (row, link, defaults, `setKind`), Scan and Inventory Prepared Food, MediaRemote switches. **Left on purpose:** the BedSide scope sheet `isPresented` forwarder, and group C draft transforms other than `kindBinding` (WakeLight name and date, bed toggles, schedule editor, ScanItem name and quantity): local state is the truth there, so they are not controller forwarders; a follow-up can move them onto the draft types. Rule: a hand-built `Binding(get:set:)` that forwards to a controller is a review finding; use these controls.

## Finding

The closures read controller state that already includes the optimistic overlay ([optimistic-actions](../patterns/optimistic-actions.md)), so controls flip at the tap, hold on a confirmation and roll back on a rejection or after 2 s. Rewriting them as local `@State` + `onChange` would lose the rollback, drift from other devices and loop on echoes. Do not do that.

## Groups

| Group | Sites | Answer |
|---|---|---|
| A. Controller-forward | Sprinkler Rain Delay, Smart Watering, programs; Humidifier timer and Display; Vacuum autoClean; Climate Predictive Comfort and HubPicker; BedAlarmToggle; WakeLight row toggle and defaults; BedSide scope sheet | shared `ControllerToggle`/`ControllerStepper`/`ControllerPicker` |
| B. Value-ignoring | Humidifier schedules enabled, `ClimateToggleRow`, autoClean, Scan Prepared Food, MediaRemote | `ActionToggle(isOn:, action:)` |
| C. Local draft transforms | WakeLight editor name, date, bed toggles, `kindBinding`; Humidifier schedule editor; ScanItem name and quantity | fix at the draft/model (`draft.setKind`, `dateValue`, `@Bindable` model properties); `SegmentedChoice` needs no Binding |
| D. Async-gated | `InventoryItemEditor.preparedBinding` | `ActionToggle`; reads the batch, stays off until the prompt confirms |

## Options

1. **O1 Leave, codify:** allow forwarding Bindings only when `get` reads controller state. No code; finding stays.
2. **O2 Shared controls (recommended):** the one internal Binding lives in HassDesign, tested, with the 44 pt row, identifier and hint in one place; groups C/D fixed at the source. About 14 view files, one new Design file, same pixels.
3. **O3 Writable controller properties + `@Bindable`:** removes closures but puts command side effects in setters, touches about 12 controllers and cannot express groups B or D.
4. **O4 Local state + `onChange`:** rejected (breaks HA as source of truth).

## Behaviour that must not change (all options)

| Case | Result |
|---|---|
| Echo within 2 s | Flips at the tap, overlay clears on confirmation |
| Rejected call | Generation rollback restores the old value |
| No echo | Reverts after 2 s |
| Another device changes it | Follows the live change |
| Prepared Food with a prompt | Stays off until confirmed |

## VoiceOver and tests

Label, value and trait come from the shared control (switch; adjustable for the stepper); a rollback changes the value back with no extra announcement unless the owner asks for one. Tests: HassDesign unit tests for `ControllerToggle`/`ActionToggle`; `OptimisticActionsTests` (`failNext`, `ManualScheduler`) plus one failed-call test per migrated controller; UX and accessibility journeys on iPhone, Duo and iPad (rejected command ends off, AX5, 44 pt); before/after snapshots identical.

## Open questions

Pick O1 or O2; whether a rollback should be announced; BedSide scope sheet as `.sheet(item:)` or one sanctioned `isPresented` forwarder.
