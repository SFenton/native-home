import Foundation
@testable import HassCore
import Testing
import HassTestSupport

@MainActor
@Suite(.demoHouse)
struct VacationModeControllerTests {
    struct Harness {
        let controller: VacationModeController
        let store: EntityStore
        let caller: RecordingCaller
        let scheduler: ManualScheduler
        let responder: ScriptedResponder
    }

    func make(mode: String = "off", checklist: [String]? = nil, invalidPending: String = "off",
              start: String = "2026-10-20 09:00:00", end: String = "2026-10-27 18:00:00",
              away: EntityState = awayEntity()) -> Harness {
        var states: [String: String] = [
            Vacation.modeEntityId: mode,
            Vacation.invalidDatesPendingEntityId: invalidPending,
            Vacation.startEntityId: start,
            Vacation.endEntityId: end,
        ]
        for (index, item) in Vacation.checklist.enumerated() { states[item.entityId] = checklist?[index] ?? "off" }
        let store = makeStore(states)
        store.apply([away])
        let caller = RecordingCaller()
        let scheduler = ManualScheduler()
        let responder = ScriptedResponder()
        let household = HouseholdAwayController(store: store, responder: responder)
        let controller = VacationModeController(store: store, household: household, caller: caller, scheduler: scheduler,
                                                now: { AwayTestClock.now }, calendar: AwayTestClock.calendar)
        return Harness(controller: controller, store: store, caller: caller, scheduler: scheduler, responder: responder)
    }

    let allDone = Array(repeating: "on", count: 5)

    @Test func offWithIncompleteChecklistShowsTheChecklistAndBlocks() {
        let h = make(checklist: ["on", "off", "on", "on", "on"])
        let vacation = h.controller
        #expect(!vacation.cardEnabled)
        #expect(!vacation.showsInlineDates)
        #expect(vacation.cardSubtitle == "Off")
        #expect(!vacation.cardOpensSheet)
        vacation.tapCard()
        #expect(vacation.showsPreChecklistError)
        #expect(!vacation.isConfirming)
        // Finishing the checklist clears the error.
        vacation.toggle(Vacation.checklist[1])
        #expect(vacation.isChecked(Vacation.checklist[1]))
        #expect(vacation.checklistComplete)
        #expect(!vacation.blockedEnableAttempted)
        #expect(!vacation.showsPreChecklistError)
    }

    @Test func checklistTogglesAreExplicitAndOptimistic() async {
        let h = make(checklist: allDone)
        h.controller.toggle(Vacation.checklist[0])
        #expect(!h.controller.isChecked(Vacation.checklist[0]))
        await h.controller.drain()
        #expect(h.caller.calls == [.init(domain: "input_boolean", service: "turn_off", data: ["entity_id": Vacation.checklist[0].entityId])])
        // No echo: the optimistic value reverts.
        h.scheduler.fireAll()
        #expect(h.controller.isChecked(Vacation.checklist[0]))
    }

    @Test func unavailableChecklistRowsDoNothing() async {
        let h = make(checklist: ["unavailable", "on", "on", "on", "on"])
        #expect(h.controller.isUnavailable(Vacation.checklist[0]))
        h.controller.toggle(Vacation.checklist[0])
        await h.controller.drain()
        #expect(h.caller.calls.isEmpty)
        #expect(!h.controller.checklistComplete)
    }

    @Test func enablingAsksForDatesThenConfirms() async {
        let h = make(checklist: allDone)
        let vacation = h.controller
        #expect(vacation.cardOpensSheet)
        vacation.tapCard()
        #expect(vacation.isConfirming)
        #expect(vacation.cardSubtitle == "Pending")
        #expect(vacation.dateRange == .makeDefault(now: AwayTestClock.now, calendar: AwayTestClock.calendar))
        let picked = Vacation.DateRange(start: WallClock(date: "2026-11-01", time: "06:00"), end: WallClock(date: "2026-11-08", time: "22:00"))
        vacation.updatePendingRange(picked)
        #expect(vacation.dateRange == picked)
        vacation.confirm()
        #expect(!vacation.isConfirming)
        #expect(vacation.modeOn)
        #expect(vacation.showsInlineDates)
        await vacation.drain()
        #expect(h.caller.calls.map(\.service) == ["set_datetime", "set_datetime", "turn_off", "turn_on"])
        #expect(h.caller.calls[0].data["date"] == "2026-11-01")
        #expect(h.caller.calls[1].data["time"] == "22:00:00")
    }

    @Test func tappingWhileConfirmingCancels() {
        let h = make(checklist: allDone)
        h.controller.tapCard()
        h.controller.tapCard()
        #expect(!h.controller.isConfirming)
        h.controller.tapCard()
        h.controller.cancelConfirmation()
        #expect(!h.controller.isConfirming)
        // Edits outside the sheet are ignored.
        h.controller.updatePendingRange(.makeDefault())
        #expect(!h.controller.isConfirming)
    }

    @Test func invalidPendingRangeCannotConfirm() async {
        let h = make(checklist: allDone)
        h.controller.tapCard()
        h.controller.updatePendingRange(Vacation.DateRange(start: WallClock(date: "2026-11-08", time: "06:00"), end: WallClock(date: "2026-11-01", time: "06:00")))
        #expect(h.controller.invalidDateRange)
        #expect(!h.controller.recoveringInvalidDates)
        h.controller.confirm()
        await h.controller.drain()
        #expect(h.caller.calls.isEmpty)
        #expect(h.controller.isConfirming)
    }

    @Test func disablingResetsEverything() async {
        let h = make(mode: "on", checklist: allDone)
        let vacation = h.controller
        #expect(vacation.cardEnabled)
        #expect(vacation.showsInlineDates)
        #expect(vacation.cardSubtitle == "On")
        vacation.tapCard()
        #expect(vacation.isConfirmingDisable)
        vacation.confirmDisable()
        #expect(!vacation.isConfirmingDisable)
        #expect(!vacation.modeOn)
        await vacation.drain()
        #expect(h.caller.calls.count == 7)
        #expect(h.caller.calls.allSatisfy { $0.service == "turn_off" })
    }

    @Test func liveChangeClearsTheOptimisticValue() async {
        let h = make(mode: "on", checklist: allDone)
        h.controller.tapCard()
        h.controller.confirmDisable()
        #expect(!h.controller.modeOn)
        h.store.apply([EntityState(entityId: Vacation.modeEntityId, state: "off")])
        await Task.yield()
        await Task.yield()
        #expect(h.scheduler.pending.isEmpty || !h.controller.modeOn)
        #expect(!h.controller.modeOn)
    }

    /// Turning an engaged vacation off asks first; Cancel changes nothing (owner, 2026-10-13).
    @Test func disablingAsksFirstAndCancelKeepsItOn() async {
        let h = make(mode: "on", checklist: allDone)
        let vacation = h.controller
        vacation.tapCard()
        #expect(vacation.isConfirmingDisable)
        #expect(vacation.modeOn)
        #expect(vacation.cardAccessibilityHint == "Asks before turning Vacation Mode off.")
        vacation.cancelDisable()
        #expect(!vacation.isConfirmingDisable)
        await vacation.drain()
        #expect(vacation.modeOn)
        #expect(h.caller.calls.isEmpty)
        // Yes works even when SwiftUI cleared the alert's binding first.
        vacation.tapCard()
        vacation.cancelDisable()
        vacation.confirmDisable()
        #expect(!vacation.modeOn)
    }

    @Test func cardHintSaysWhatATapDoes() {
        #expect(make(checklist: allDone).controller.cardAccessibilityHint == "Asks for the vacation dates.")
        #expect(make().controller.cardAccessibilityHint == "")
        #expect(make(mode: "unavailable").controller.cardAccessibilityHint == "")
    }

    /// The helpers echo one at a time: after the new start lands but before the new end, the saved range is
    /// the new start against the last vacation's end. The confirmed dates stay on screen until both echo,
    /// so the range error never flashes (owner report, 2026-10-13).
    @Test func confirmedDatesHoldUntilBothHelpersEcho() async {
        let h = make(checklist: allDone, start: "2026-10-01 09:00:00", end: "2026-10-05 18:00:00")
        let vacation = h.controller
        vacation.tapCard()
        let picked = Vacation.DateRange(start: WallClock(date: "2026-10-13", time: "08:00"), end: WallClock(date: "2026-10-14", time: "08:00"))
        vacation.updatePendingRange(picked)
        vacation.confirm()
        #expect(vacation.dateRange == picked)
        h.store.apply([EntityState(entityId: Vacation.startEntityId, state: "2026-10-13 08:00:00")])
        await Task.yield()
        await Task.yield()
        // The saved range alone is reversed here, which used to show the error.
        #expect(vacation.savedRange.isInvalid(calendar: AwayTestClock.calendar))
        #expect(!vacation.invalidDateRange)
        #expect(!vacation.recoveringInvalidDates)
        #expect(vacation.dateRange == picked)
        h.store.apply([EntityState(entityId: Vacation.endEntityId, state: "2026-10-14 08:00:00")])
        await Task.yield()
        await Task.yield()
        #expect(vacation.confirmedRange == nil)
        #expect(vacation.dateRange == picked)
    }

    @Test func inlineDateChangesSaveOneHelper() async {
        let h = make(mode: "on")
        let range = h.controller.savedRange
        var changed = range
        changed.end = WallClock(date: "2026-10-30", time: "18:00")
        h.controller.updateSavedRange(changed, changedEnd: true)
        changed.start = WallClock(date: "2026-10-21", time: "09:00")
        h.controller.updateSavedRange(changed, changedEnd: false)
        await h.controller.drain()
        #expect(h.caller.calls.map { $0.data["entity_id"] } == [Vacation.endEntityId, Vacation.startEntityId])
    }

    @Test func fixingPausedDatesReenables() async {
        let h = make(mode: "off", invalidPending: "on", start: "2026-10-27 09:00:00", end: "2026-10-20 09:00:00")
        let vacation = h.controller
        #expect(vacation.invalidDateRange)
        #expect(vacation.recoveringInvalidDates)
        #expect(vacation.cardEnabled)
        #expect(vacation.cardDisabled)
        vacation.tapCard()
        var fixed = vacation.savedRange
        fixed.end = WallClock(date: "2026-11-02", time: "09:00")
        vacation.updateSavedRange(fixed, changedEnd: true)
        await vacation.drain()
        #expect(h.caller.calls.map(\.service) == ["set_datetime", "turn_on", "turn_off"])
    }

    @Test func pastDatesDoNotReenable() async {
        let h = make(mode: "off", invalidPending: "on", start: "2026-10-01 09:00:00", end: "2026-10-02 09:00:00")
        var range = h.controller.savedRange
        range.start = WallClock(date: "2026-10-01", time: "08:00")
        h.controller.updateSavedRange(range, changedEnd: false)
        await h.controller.drain()
        #expect(h.caller.calls.map(\.service) == ["set_datetime"])
    }

    @Test func unavailableModeDisablesTheCard() {
        let h = make(mode: "unavailable", checklist: allDone)
        #expect(h.controller.modeUnavailable)
        #expect(h.controller.cardDisabled)
        #expect(h.controller.cardSubtitle == "Unavailable")
        h.controller.tapCard()
        #expect(!h.controller.isConfirming)
    }

    @Test func backendVacationAndSoloTrip() {
        let backend = make(away: awayEntity("active", awayAttributes(mode: "vacation")))
        #expect(backend.controller.backendVacationEngaged)
        #expect(backend.controller.cardEnabled)
        let solo = make(away: awayEntity("active", awayAttributes(mode: "solo_trip", traveler: "sam")))
        #expect(solo.controller.soloTripEngaged)
    }
}
