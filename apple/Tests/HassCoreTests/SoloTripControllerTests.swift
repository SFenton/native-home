import Foundation
@testable import HassCore
import HassTestSupport
import Testing

@MainActor
@Suite(.demoHouse)
struct SoloTripControllerTests {
    struct Harness {
        let trip: SoloTripController
        let store: EntityStore
        let responder: ScriptedResponder
        let scheduler: ManualScheduler
    }

    func make(_ away: EntityState = awayEntity()) -> Harness {
        let store = EntityStore()
        store.replaceAll([away])
        let responder = ScriptedResponder()
        let scheduler = ManualScheduler()
        let household = HouseholdAwayController(store: store, responder: responder)
        let trip = SoloTripController(household: household, scheduler: scheduler, now: { AwayTestClock.now }, calendar: AwayTestClock.calendar)
        return Harness(trip: trip, store: store, responder: responder, scheduler: scheduler)
    }

    func activeTrip(_ state: String = "active", effects: Bool = true, revision: Int = 4) -> EntityState {
        awayEntity(state, awayAttributes(mode: "solo_trip", traveler: "alex", home: "sam", revision: revision, effects: effects,
                                         startsAt: "2026-10-10 09:00:00", endsAt: "2026-10-14 18:00:00"))
    }

    // MARK: Idle

    @Test func idlePageNeedsATraveler() {
        let h = make()
        let trip = h.trip
        #expect(!trip.toggleChecked)
        #expect(trip.toggleDisabled)
        #expect(trip.toggleSubtitle == SoloTripCopy.toggleDisabled)
        #expect(trip.setupError == nil)
        #expect(trip.notice == nil)
        #expect(trip.status == nil)
        #expect(!trip.showsReturnFields)
        #expect(trip.travelerTiles.map(\.title) == ["Alex", "Sam"])
        #expect(trip.travelerTiles.allSatisfy { $0.isInteractive && !$0.isSelected && $0.subtitle == nil && $0.icon == "mdi:account" })
    }

    @Test func viewerSeesYou() {
        let h = make()
        h.trip.viewer = .resident2
        #expect(h.trip.travelerTiles.map(\.title) == ["Alex", "You"])
    }

    @Test func selectingATravelerEnablesTheToggle() {
        let h = make()
        h.trip.selectTraveler(.resident2)
        #expect(h.trip.selectedTraveler == .resident2)
        #expect(!h.trip.toggleDisabled)
        #expect(h.trip.toggleSubtitle == SoloTripCopy.toggleOff)
        #expect(h.trip.travelerTiles[1].isSelected)
        #expect(h.trip.travelerTiles[1].icon == "mdi:account-arrow-right-outline")
        h.trip.selectTraveler(.resident2)
        #expect(h.trip.selectedTraveler == nil)
    }

    // MARK: Scheduling

    @Test func scheduleWaitsForTheEchoThenCloses() async {
        let h = make()
        let trip = h.trip
        trip.selectTraveler(.resident1)
        await trip.toggle()
        #expect(trip.editorOpen)
        #expect(trip.scheduleDraft == .makeDefault(now: AwayTestClock.now, calendar: AwayTestClock.calendar))
        #expect(trip.editorAlerts.isEmpty)
        #expect(!trip.editorConfirmDisabled)
        // Selection is locked while the editor is open.
        trip.selectTraveler(.resident2)
        #expect(trip.selectedTraveler == .resident1)
        trip.scheduleDraft.start = WallClock(date: "2026-10-12", time: "08:00")
        trip.scheduleDraft.end = WallClock(date: "2026-10-15", time: "20:00")
        await trip.confirmSchedule()
        #expect(h.responder.operation(0) == "schedule")
        #expect(trip.isScheduling)
        #expect(trip.editorOpen)
        #expect(trip.editorConfirmDisabled)
        trip.closeEditor()
        #expect(trip.editorOpen)
        // A different echo doesn't confirm.
        h.store.apply([awayEntity("scheduled", awayAttributes(mode: "solo_trip", traveler: "alex", home: "sam",
                                                              startsAt: "2026-10-12 08:00:00", endsAt: "2026-10-15 21:00:00"))])
        trip.reconcile()
        #expect(trip.isScheduling)
        h.store.apply([awayEntity("scheduled", awayAttributes(mode: "solo_trip", traveler: "alex", home: "sam",
                                                              startsAt: "2026-10-12 08:00:00", endsAt: "2026-10-15 20:00:00"))])
        trip.reconcile()
        #expect(!trip.isScheduling)
        #expect(!trip.editorOpen)
        #expect(trip.toggleChecked)
        #expect(trip.toggleSubtitle == SoloTripCopy.toggleOn)
        #expect(trip.travelerTiles[0].subtitle == SoloTripCopy.travelerAway)
        #expect(trip.travelerTiles[1].subtitle == SoloTripCopy.travelerHome)
        #expect(trip.travelerTiles[1].icon == "mdi:home-account")
        #expect(!trip.travelerTiles[0].isInteractive)
    }

    @Test func rejectedScheduleStaysEditable() async {
        let h = make()
        h.responder.responses = [.success(.object(["status": .string("rejected"), "error_code": .string("conflict")]))]
        h.trip.selectTraveler(.resident2)
        h.trip.openEditor()
        await h.trip.confirmSchedule()
        #expect(!h.trip.isScheduling)
        #expect(h.trip.editorAlerts == [SoloTripCopy.commandFailed])
        h.trip.closeEditor()
        #expect(!h.trip.editorOpen)
        #expect(h.trip.household.errorCode == nil)
    }

    @Test func invalidDraftIsNotSent() async {
        let h = make()
        h.trip.selectTraveler(.resident2)
        h.trip.openEditor()
        h.trip.scheduleDraft.end = h.trip.scheduleDraft.start
        #expect(h.trip.editorAlerts == [SoloTripCopy.endAfterStart])
        #expect(h.trip.editorConfirmDisabled)
        await h.trip.confirmSchedule()
        #expect(h.responder.sent.isEmpty)
    }

    @Test func editorNeedsATraveler() {
        let h = make()
        h.trip.openEditor()
        #expect(!h.trip.editorOpen)
        h.trip.editorOpen = true
        #expect(h.trip.editorAlerts.first == SoloTripCopy.travelerRequired)
    }

    // MARK: Conflicts

    @Test func vacationBlocksSoloTrip() {
        let h = make(awayEntity("active", awayAttributes(mode: "vacation")))
        #expect(h.trip.setupError == SoloTripCopy.vacationConflict)
        #expect(h.trip.toggleSubtitle == SoloTripCopy.toggleOff)
        #expect(h.trip.travelerTiles.allSatisfy { $0.isMuted && !$0.isInteractive && $0.isDisabled })
    }

    @Test func unavailableScriptNeedsSetup() {
        let h = make(awayEntity("idle", awayAttributes(commandAvailable: false)))
        #expect(h.trip.setupError == SoloTripCopy.setupRequired)
        #expect(h.trip.toggleSubtitle == SoloTripCopy.setupRequiredSubtitle)
        h.trip.selectTraveler(.resident2)
        h.trip.openEditor()
        #expect(!h.trip.editorOpen)
    }

    /// Ending a trip publishes a status that briefly doesn't match the journal (`command_available` false).
    /// The page disables the toggle for that moment but shows no setup error (owner report 2026-10-13).
    @Test func aBriefOutageMidTransitionShowsNoSetupError() async {
        let h = make(activeTrip())
        h.store.apply([awayEntity("ending", awayAttributes(mode: "solo_trip", traveler: "alex", home: "sam", commandAvailable: false))])
        await Task.yield()
        await Task.yield()
        #expect(h.trip.toggleDisabled)
        #expect(h.trip.setupError == nil)
        h.store.apply([awayEntity("idle", awayAttributes(revision: 6))])
        await Task.yield()
        await Task.yield()
        #expect(h.trip.setupError == nil)
        #expect(h.trip.toggleSubtitle == SoloTripCopy.toggleDisabled)
    }

    // MARK: Engaged

    @Test func activeTripShowsNoticeAndReturnFields() {
        let h = make(activeTrip())
        let trip = h.trip
        #expect(trip.isEngaged && trip.presentedEngaged)
        #expect(trip.selectedTraveler == .resident1)
        #expect(trip.notice?.isSuccess == true)
        #expect(trip.status == nil)
        #expect(trip.showsReturnFields)
        #expect(trip.canEditReturn)
        #expect(!trip.returnFieldsDisabled)
        #expect(trip.returnDraft == WallClock(date: "2026-10-14", time: "18:00"))
        #expect(trip.returnError == nil)
    }

    @Test func endingATripIsOptimistic() async {
        let h = make(activeTrip())
        let trip = h.trip
        await trip.toggle()
        #expect(h.responder.operation(0) == "end_now")
        #expect(!trip.toggleChecked)
        #expect(trip.endPending)
        #expect(trip.notice == nil)
        #expect(!trip.showsReturnFields)
        #expect(trip.toggleDisabled)
        h.store.apply([awayEntity("idle", awayAttributes(revision: 5))])
        trip.reconcile()
        #expect(!trip.isEngaged)
        #expect(!trip.toggleChecked)
        #expect(!trip.toggleDisabled || trip.selectedTraveler == nil)
        #expect(trip.selectedTraveler == nil)
    }

    @Test func scheduledTripIsCancelled() async {
        let h = make(awayEntity("scheduled", awayAttributes(mode: "solo_trip", traveler: "sam", home: "alex",
                                                            startsAt: "2026-10-12 08:00:00", endsAt: "2026-10-15 20:00:00")))
        await h.trip.toggle()
        #expect(h.responder.operation(0) == "cancel")
    }

    @Test func failedEndRevertsTheToggle() async {
        let h = make(activeTrip())
        h.responder.responses = [.failure(ScriptedResponder.Failure())]
        await h.trip.toggle()
        #expect(h.trip.toggleChecked)
        #expect(h.trip.household.errorCode == "transport")
    }

    @Test func endRevertsWhenHomeAssistantNeverConfirms() async {
        let h = make(activeTrip())
        await h.trip.toggle()
        #expect(!h.trip.toggleChecked)
        h.scheduler.fireAll()
        #expect(h.trip.toggleChecked)
    }

    @Test func movingTheReturnSendsUpdateEnd() async {
        let h = make(activeTrip())
        let trip = h.trip
        await trip.updateReturn(WallClock(date: "2026-10-16", time: "18:00"))
        #expect(h.responder.operation(0) == "update_end")
        #expect(trip.returnFieldsDisabled)
        h.store.apply([awayEntity("active", awayAttributes(mode: "solo_trip", traveler: "alex", home: "sam", effects: true,
                                                           startsAt: "2026-10-10 09:00:00", endsAt: "2026-10-16 18:00:00"))])
        trip.reconcile()
        #expect(!trip.returnFieldsDisabled)
        #expect(!trip.returnDraftDirty)
        #expect(trip.returnDraft == WallClock(date: "2026-10-16", time: "18:00"))
    }

    @Test func invalidReturnShowsAnError() async {
        let h = make(activeTrip())
        await h.trip.updateReturn(WallClock(date: "2026-10-11", time: "08:00"))
        #expect(h.trip.returnError == SoloTripCopy.endInFuture)
        await h.trip.updateReturn(WallClock(date: "2026-10-09", time: "08:00"))
        #expect(h.trip.returnError == SoloTripCopy.endInFuture)
        // Unchanged return: nothing to send.
        await h.trip.updateReturn(WallClock(date: "2026-10-14", time: "18:00"))
        #expect(h.trip.returnError == nil)
        #expect(h.responder.sent.isEmpty)
    }

    @Test func returnBeforeDeparture() async {
        let h = make(awayEntity("scheduled", awayAttributes(mode: "solo_trip", traveler: "sam", home: "alex",
                                                            startsAt: "2026-10-20 08:00:00", endsAt: "2026-10-25 20:00:00")))
        await h.trip.updateReturn(WallClock(date: "2026-10-19", time: "08:00"))
        #expect(h.trip.returnError == SoloTripCopy.endAfterStart)
    }

    @Test func restoreRequired() async {
        let h = make(activeTrip("restore_required", effects: false))
        let trip = h.trip
        #expect(trip.toggleChecked)
        #expect(trip.toggleDisabled)
        #expect(trip.status?.actions == [.keepCurrent, .restoreSaved])
        #expect(!trip.restoreDisabled)
        await trip.resolveRestore(.keepCurrent)
        #expect(h.responder.sent[0]["resolve_action"] as? String == "keep_current")
        #expect(trip.restoreAwaitingSnapshot)
        #expect(trip.restoreDisabled)
        h.store.apply([activeTrip()])
        trip.reconcile()
        #expect(!trip.restoreAwaitingSnapshot)
    }

    @Test func degradedAndEndingStatus() {
        #expect(make(activeTrip("degraded", effects: false)).trip.status?.title == SoloTripCopy.degradedTitle)
        let ending = make(activeTrip("ending", effects: false)).trip
        #expect(ending.status?.title == SoloTripCopy.endingTitle)
        #expect(!ending.canEditReturn)
        #expect(ending.toggleDisabled)
        #expect(make(activeTrip("active", effects: false)).trip.status?.description == nil)
    }

    @Test func liveUpdatesReconcileOnTheirOwn() async {
        let h = make()
        h.store.apply([activeTrip()])
        for _ in 0..<5 { await Task.yield() }
        #expect(h.trip.selectedTraveler == .resident1)
    }
}
