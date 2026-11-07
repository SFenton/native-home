# Optimistic actions

> **What:** how a control shows its new value at once and stays honest. **Read when:** a control calls a service and should not wait for Home Assistant before it looks changed.

- **Component:** `OptimisticActions` (`HassCore/Optimism/OptimisticActions.swift`) over `OptimisticOverlay` (`HassCore/Entities/OptimisticOverlay.swift`). Web source: `useOptimisticState` and `runOptimisticServiceCommand` (`ha-sfenton-react-dash@f5a7bf9:src/hooks/useOptimisticState.ts`, `src/components/hass/optimisticActionState.ts`).
- **Behavior (web parity):**
  - `perform(call, showing: [OptimisticIntent], resetting: [OptimisticReset])` shows the intents immediately, then sends the call.
  - The pending value clears quietly when the live value matches it (`.confirmation`), or on any live change (`.liveChange`).
  - If neither happens, it reverts after `revertAfter` (default `OptimisticActions.defaultRevert`, 2 s, web `DEFAULT_OPTIMISTIC_REVERT_MS`).
  - A failed call rolls back exactly the values it committed, using generations, so an older failure never undoes a newer tap, **and shows the failed face for 4 s** (see Failure below).
- **Clear rule:**
  - Use `.confirmation` for selects, modes and switches Home Assistant echoes as-is.
  - Use `.liveChange` when something else may override the result. Lights under Presence Based Lighting are the example: if the light reverts, the tile follows the truth instead of holding the tapped value.
- **Live source:** `init(store:rules:caller:)` tracks entity states. `init(rules:caller:live:)` takes any observable value, such as an attribute (`fan_mode`) or a derived key.
- **Reading:** views read `shown(key)`. `isPending(key)` tells a control it is waiting, for example to dim a spinner. `isFailed(key)` is true for 4 s after a rejected call (see Failure).
- **Failure (owner, 2026-10-24; reverses the earlier "no error state between pending and live" rule).** A rejected call, or for a commit that asks (`failsOnTimeout`, the vacuum switches) no confirmation by the revert time, rolls the value back **and** marks the key failed for 4 s (`OptimisticOverlay.fail`, `markFailed`, `isFailed`, `failureDuration`). A new commit on the key clears it. The hook is once, in the overlay: every controller's catch block calls `overlay.fail(key, generation:)` instead of `reset`. How it shows:
  - **Tiles:** pass `isError: isFailed(key)` and the subtitle "Didn't Respond" to `GlassTile`. `GlassTile` itself plays the `.error` haptic and posts the VoiceOver announcement ("Title, Didn't Respond") when `isError` turns true.
  - **Rows and cards with no face to turn red:** an `InlineAlert(severity: .error)` under the control plus `.failureAnnouncement(failed, message)` (alarm card, presence override detail).
  - **Sliders and dials:** `TransientFailure` + `FailureCaption` under the control, one footnote line in the error ink (`ClimateThermostatDial`: "Couldn't set 68°. Check the connection.").
  - **No optimistic value to roll back** (Power Recovery, a script): `markFailed(key)` on any key, or `perform(..., failing: key)`.
  - Announcements go through `announceFailure(_:)` (HassDesign), one place to swap for `Announcer`.
- **Pending state (decided with the failed face).** A control keeps its optimistic colour while `isPending`; a long call (lock, garage, alarm) may show a small spinner in place of its trailing glyph, a static ellipsis under Reduce Motion. Not built as a tile-wide input yet: the tile outline stays out; the failed face is the new state.
- **Telemetry:** each call is a `ServiceCall` signpost, each confirmation an `OptimisticConfirm` interval, and rollbacks are counted (`optimistic.rollbacks`).
- **Adopting:**
  - New controllers use `OptimisticActions`.
  - Existing controllers that wire `OptimisticOverlay` + `observeLive` + `perform` by hand (Climate, room devices, vacuums, sprinklers, bed sides, household settings, Vacation, Solo Trip) move over when next touched. Their behavior is already identical.
  - `try?` around a service call that shows an optimistic value is a review finding: route it through `perform` so a failure rolls back.
- **Tests:** `Tests/HassCoreTests/OptimisticActionsTests.swift`, `OptimisticFailureTests.swift`. Use `RecordingCaller` (`failNext`) with `ManualScheduler`.
- **Controls:** show a controller's value with `ControllerToggle`, `ActionToggle`, `ControllerStepper` or `ControllerPicker` (`HassDesign/ControllerControls.swift`); they keep no copy, so a rollback shows the old value. Do not hand-build `Binding(get:set:)` to a controller or mirror it in `@State` + `onChange` ([decision](../design/controller-bound-controls.md)).
- **Undo for an easy action that removes content (owner, 2026-10-24; proposal `todo-undo`, option B).** A ticked todo row stays listed in its done look for 5 s with an Undo button, then collapses: `TodoListController.recentlyCompleted` (one timer per item, `undoGrace`), shown by `visibleItems`, drawn by `TodoItemRow(onUndo:)` (a 44 pt button, under the title at accessibility sizes, also a VoiceOver custom action; the completion is announced "{title} completed. Undo available"). `undo(_:)` always calls `todo.update_item` with `needs_action`, also on the Admin To-Do, whose completion runs a script that has no reopen. It covers Groceries, Chores, Resident and Unassigned Chores, Admin To-Do and the Summary chore tabs, since all use `TodoListSection`. A failed tick drops the grace. Tests: `TodoListControllerTests`, `ChoresViewTests`, `ChoresFlowTests`, `ChoresCheckUndoJourneyTests`.
