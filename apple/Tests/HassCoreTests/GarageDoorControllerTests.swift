import Foundation
@testable import HassCore
import Testing
import HassTestSupport

/// The garage door command state machine with a recording caller and a manual clock (web `useGarageDoorCommand`).
@MainActor
@Suite(.demoHouse)
struct GarageDoorControllerTests {
    let door = SecurityConfig.leftGarageDoorEntityId

    func controller(_ state: String?) -> (GarageDoorController, RecordingCaller, ManualScheduler) {
        let caller = RecordingCaller()
        let scheduler = ManualScheduler()
        return (GarageDoorController(entityId: door, liveState: state, caller: caller, scheduler: scheduler), caller, scheduler)
    }

    /// Runs the live timers scheduled for `delay`.
    func fire(_ scheduler: ManualScheduler, _ delay: Duration) {
        for item in scheduler.pending where item.delay == delay {
            item.cancelled = true
            item.work()
        }
    }

    @Test func commandsFollowTheLiveState() {
        #expect(GarageDoorController.command(for: "closed")?.service == "open_cover")
        #expect(GarageDoorController.command(for: "closing")?.service == "open_cover")
        #expect(GarageDoorController.command(for: "open")?.service == "close_cover")
        #expect(GarageDoorController.command(for: "opening")?.transitionState == "closing")
        #expect(GarageDoorController.command(for: "unavailable") == nil)
        #expect(GarageDoorController.command(for: nil) == nil)
    }

    @Test func missingOrUnavailableDoorsDoNothing() async {
        for state in [nil, "unavailable", "unknown"] {
            let (garage, caller, scheduler) = controller(state)
            #expect(!garage.isAvailable)
            garage.send()
            await garage.waitForCall()
            #expect(caller.calls.isEmpty)
            #expect(scheduler.items.isEmpty)
            #expect(garage.phase == .idle)
        }
    }

    /// Sending → pending once acknowledged and 1 s has passed; taps are ignored until acknowledged and 2 s.
    @Test func successfulOpenWalksThroughThePhases() async {
        let (garage, caller, scheduler) = controller("closed")
        garage.send()
        #expect(garage.phase == .sending)
        #expect(garage.opens == true)
        #expect(garage.displayState == "opening", "Shows the moving state at once")
        #expect(garage.isInteractionLocked)
        await garage.waitForCall()
        #expect(caller.calls == [.init(domain: "cover", service: "open_cover", data: ["entity_id": door])])
        #expect(garage.phase == .sending, "Feedback holds for at least a second")
        fire(scheduler, .seconds(1))
        #expect(garage.phase == .pending)
        #expect(garage.isInteractionLocked, "Locked until the 2 s lockout passes")
        garage.send()
        await garage.waitForCall()
        #expect(caller.calls.count == 1, "A tap during the lockout is ignored")
        fire(scheduler, .seconds(2))
        #expect(!garage.isInteractionLocked)

        // The door reports opening, then open: the request ends and the tile follows Home Assistant.
        garage.liveDidChange("opening")
        #expect(garage.phase == .idle)
        #expect(garage.displayState == "opening")
        #expect(scheduler.pending.isEmpty, "Every request timer is cancelled")
        garage.liveDidChange("open")
        #expect(garage.displayState == "open")
        garage.send()
        await garage.waitForCall()
        #expect(caller.calls.last?.service == "close_cover")
        #expect(garage.opens == false)
    }

    /// The timers elapse before the acknowledgement: pending and unlock wait for it.
    @Test func timersWaitForTheAcknowledgement() async {
        let (garage, _, scheduler) = controller("open")
        garage.send()
        fire(scheduler, .seconds(1))
        fire(scheduler, .seconds(2))
        #expect(garage.phase == .sending)
        #expect(garage.isInteractionLocked)
        await garage.waitForCall()
        #expect(garage.phase == .pending)
        #expect(!garage.isInteractionLocked)
    }

    @Test func failedCallsShowErrorThenClear() async {
        let (garage, caller, scheduler) = controller("closed")
        caller.failNext = true
        garage.send()
        await garage.waitForCall()
        #expect(garage.phase == .error)
        #expect(garage.opens == true)
        #expect(garage.displayState == "closed", "The optimistic state is dropped")
        #expect(!garage.isInteractionLocked)
        #expect(scheduler.pending.map(\.delay) == [.seconds(8)], "Only the error hold is left")
        fire(scheduler, .seconds(8))
        #expect(garage.phase == .idle)
        #expect(garage.opens == nil)
    }

    @Test func unacknowledgedCallsTimeOut() async {
        let (garage, _, scheduler) = controller("closed")
        garage.send()
        // The 10 s service timeout runs before the (recorded, instant) call is awaited.
        fire(scheduler, .seconds(10))
        #expect(garage.phase == .error)
        await garage.waitForCall()
        #expect(garage.phase == .error, "A late acknowledgement for a failed request is ignored")
    }

    @Test func doorsThatNeverMoveFailAfter45Seconds() async {
        let (garage, _, scheduler) = controller("closed")
        garage.send()
        await garage.waitForCall()
        fire(scheduler, .seconds(1))
        fire(scheduler, .seconds(2))
        #expect(garage.phase == .pending)
        fire(scheduler, .seconds(45))
        #expect(garage.phase == .error)
        #expect(garage.displayState == "closed")
    }

    @Test func offlineSendsFailAtOnce() async {
        let (garage, caller, _) = controller("closed")
        garage.connectionDidChange(canSend: false)
        garage.send()
        await garage.waitForCall()
        #expect(caller.calls.isEmpty)
        #expect(garage.phase == .error)
    }

    @Test func losingTheConnectionFailsTheActiveRequest() async {
        let (garage, _, _) = controller("closed")
        garage.send()
        await garage.waitForCall()
        garage.connectionDidChange(canSend: false)
        #expect(garage.phase == .error)
        garage.connectionDidChange(canSend: true)
        #expect(garage.phase == .error, "Reconnecting doesn't clear the error early")
    }

    @Test func liveChangeClearsAnError() async {
        let (garage, caller, scheduler) = controller("closed")
        caller.failNext = true
        garage.send()
        await garage.waitForCall()
        #expect(garage.phase == .error)
        garage.liveDidChange("closed")
        #expect(garage.phase == .error, "The same state is not a change")
        garage.liveDidChange(nil)
        #expect(garage.phase == .idle)
        #expect(!garage.isAvailable)
        #expect(scheduler.pending.isEmpty)
    }

    @Test func anotherSendReplacesTheErrorHold() async {
        let (garage, caller, scheduler) = controller("closed")
        caller.failNext = true
        garage.send()
        await garage.waitForCall()
        garage.send()
        #expect(garage.phase == .sending)
        #expect(!scheduler.pending.contains { $0.delay == .seconds(8) })
        await garage.waitForCall()
        fire(scheduler, .seconds(1))
        #expect(garage.phase == .pending)
    }
}
