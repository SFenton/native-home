import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// Answers Household Away commands from a script and records what was sent.
@MainActor
final class ScriptedResponder: HassServiceResponding {
    var sent: [[String: any Sendable]] = []
    var responses: [Result<JSONValue, any Error>] = []
    /// Never answers (for timeouts).
    var hangs = false
    /// Runs after a command is recorded, before it answers (tests echo into the store here).
    var onCommand: (([String: any Sendable]) -> Void)?
    /// Answers only after this long (for late answers).
    var delay: Duration?

    struct Failure: Error {}

    static func accepted(revision: Int? = nil) -> Result<JSONValue, any Error> {
        var response: [String: JSONValue] = ["status": .string("accepted")]
        if let revision { response["revision"] = .number(Double(revision)) }
        return .success(.object(response))
    }

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {}

    func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        #expect(domain == "script")
        #expect(service == "demo_household_away_command")
        sent.append(data)
        onCommand?(data)
        if let delay { try await Task.sleep(for: delay) }
        if hangs {
            try await Task.sleep(for: .seconds(60))
        }
        let next = responses.isEmpty ? Self.accepted() : responses.removeFirst()
        return try next.get()
    }

    func operation(_ index: Int) -> String? { sent[index]["operation"] as? String }
}

@MainActor
@Suite(.demoHouse)
struct HouseholdAwayControllerTests {
    func make(_ entity: EntityState? = awayEntity(), timeout: Duration = .seconds(10)) -> (HouseholdAwayController, ScriptedResponder, EntityStore) {
        let store = EntityStore()
        if let entity { store.replaceAll([entity]) }
        let responder = ScriptedResponder()
        return (HouseholdAwayController(store: store, responder: responder, timeout: timeout, makeRequestId: { "req-1" }), responder, store)
    }

    @Test func acceptedCommandSendsRevisionAndRequestId() async {
        let (controller, responder, _) = make(awayEntity("idle", awayAttributes(revision: 5)))
        responder.responses = [ScriptedResponder.accepted(revision: 6)]
        let outcome = await controller.cancel()
        #expect(outcome == .accepted(revision: 6))
        #expect(controller.errorCode == nil)
        #expect(!controller.pending)
        #expect(responder.sent[0]["expected_revision"] as? Int == 5)
        #expect(responder.sent[0]["request_id"] as? String == "req-1")
        #expect(responder.operation(0) == "cancel")
        // The acknowledged revision is the floor for the next command even before the sensor catches up.
        await controller.endNow()
        #expect(responder.sent[1]["expected_revision"] as? Int == 6)
    }

    @Test func noChangeCountsAsAccepted() async {
        let (controller, responder, _) = make()
        responder.responses = [.success(.object(["response": .object(["outcome": .string("no_change")])]))]
        #expect(await controller.updateEnd(WallClock(date: "2026-10-12", time: "09:00")) == .accepted(revision: nil))
    }

    @Test func rejectionKeepsTheErrorCode() async {
        let (controller, responder, _) = make()
        responder.responses = [
            .success(.object(["status": .string("rejected"), "error_code": .string("stale_revision")])),
            .success(.object(["status": .string("rejected"), "error": .string("busy")])),
            .success(.object(["status": .string("blocked")])),
        ]
        #expect(await controller.resolveRestore(.keepCurrent) == .rejected(errorCode: "stale_revision"))
        #expect(controller.errorCode == "stale_revision")
        #expect(await controller.endNow() == .rejected(errorCode: "busy"))
        #expect(await controller.endNow() == .rejected(errorCode: "blocked"))
        controller.clearError()
        #expect(controller.errorCode == nil)
    }

    @Test func malformedOrFailedResponseIsTransport() async {
        let (controller, responder, _) = make()
        responder.responses = [.success(.object(["context": .null])), .success(.null), .failure(ScriptedResponder.Failure())]
        for _ in 0..<3 {
            #expect(await controller.cancel() == .rejected(errorCode: "transport"))
            #expect(controller.errorCode == "transport")
        }
    }

    @Test func unavailableSensorRefusesWithoutSending() async {
        let (controller, responder, _) = make(awayEntity("idle", awayAttributes(commandAvailable: false)))
        #expect(await controller.cancel() == .rejected(errorCode: "unavailable"))
        #expect(controller.errorCode == "unavailable")
        #expect(responder.sent.isEmpty)
    }

    @Test func timeoutIsUnknown() async {
        let (controller, responder, _) = make(timeout: .milliseconds(50))
        responder.hangs = true
        #expect(await controller.endNow() == .unknown)
        #expect(controller.errorCode == "unknown_outcome")
        #expect(!controller.pending)
    }

    @Test func oneCommandAtATime() async {
        // A timeout a busy main actor cannot overtake before `cancel()` runs (200 ms lost that race under load).
        let (controller, responder, _) = make(timeout: .seconds(1))
        responder.hangs = true
        async let first = controller.endNow()
        await Task.yield()
        #expect(controller.pending)
        #expect(await controller.cancel() == .rejected(errorCode: "transport"))
        #expect(await first == .unknown)
        #expect(responder.sent.count == 1)
    }

    @Test func scheduleSendsTheDraft() async {
        let (controller, responder, _) = make()
        let draft = SoloTripDraft(start: WallClock(date: "2026-10-12", time: "08:00"), end: WallClock(date: "2026-10-14", time: "18:00"))
        await controller.scheduleSoloTrip(traveler: .resident1, draft: draft)
        #expect(responder.sent[0]["traveler"] as? String == "alex")
        #expect(responder.sent[0]["end_time"] as? String == "18:00")
    }

    @Test func snapshotFollowsTheStore() {
        let (controller, _, store) = make()
        #expect(controller.snapshot.mode == .none)
        store.apply([awayEntity("scheduled", awayAttributes(mode: "solo_trip", traveler: "sam"))])
        #expect(controller.snapshot.state == .scheduled)
    }

    @Test func aResponseThatIsNotAnObjectIsTransport() async {
        let (controller, responder, _) = make()
        responder.responses = [.success(.object(["response": .string("oops")]))]
        // The wrapper's own fields hold no status, and a non-object `response` is not unwrapped.
        #expect(await controller.cancel() == .rejected(errorCode: "transport"))
    }

    @Test func aWrappedResponseIsUnwrapped() async {
        let (controller, responder, _) = make()
        responder.responses = [.success(.object(["response": .object(["status": .string("accepted"), "revision": .number(9)])]))]
        #expect(await controller.cancel() == .accepted(revision: 9))
    }

    @Test func aFractionalRevisionIsIgnored() async {
        let (controller, responder, _) = make(awayEntity("idle", awayAttributes(revision: 5)))
        responder.responses = [.success(.object(["status": .string("accepted"), "revision": .number(6.5)]))]
        #expect(await controller.cancel() == .accepted(revision: nil))
        // The floor stays at the sensor's revision.
        await controller.endNow()
        #expect(responder.sent[1]["expected_revision"] as? Int == 5)
    }

    @Test func aLateAnswerAfterTheTimeoutIsDropped() async {
        // The answer is far enough behind the timeout that a stalled main actor cannot deliver both at once and let the
        // answer win (20 ms against 120 ms did under load).
        let (controller, responder, _) = make(timeout: .milliseconds(20))
        responder.delay = .milliseconds(800)
        responder.responses = [ScriptedResponder.accepted(revision: 8)]
        #expect(await controller.endNow() == .unknown)
        // The answer arrives after the outcome was already reported unknown: it changes nothing.
        try? await Task.sleep(for: .milliseconds(1000))
        #expect(controller.errorCode == "unknown_outcome")
        #expect(!controller.pending)
        responder.delay = nil
        responder.responses = [ScriptedResponder.accepted()]
        await controller.cancel()
        #expect(responder.sent[1]["expected_revision"] as? Int == 3)
    }

    @Test func theTimeoutFiringAfterAnAnswerIsIgnored() async {
        // The timeout outlasts any stall before the answer is read (60 ms lost that race under load).
        let (controller, _, _) = make(timeout: .milliseconds(500))
        #expect(await controller.cancel() == .accepted(revision: nil))
        try? await Task.sleep(for: .milliseconds(700)) // The timer fires and must change nothing.
        #expect(controller.errorCode == nil)
    }

    @Test func requestIdsAreUniqueByDefault() async {
        let store = EntityStore()
        store.replaceAll([awayEntity()])
        let responder = ScriptedResponder()
        let controller = HouseholdAwayController(store: store, responder: responder)
        await controller.cancel()
        await controller.cancel()
        let ids = responder.sent.compactMap { $0["request_id"] as? String }
        #expect(ids.count == 2)
        #expect(Set(ids).count == 2)
        #expect(ids.allSatisfy { $0 == $0.lowercased() && UUID(uuidString: $0) != nil })
        #expect(HouseholdAwayController.commandTimeout == .seconds(10))
    }

    // MARK: - Transitions (owner report 2026-10-13: errors flashed around ending a Solo Trip)

    static func rejected(_ code: String) -> Result<JSONValue, any Error> {
        .success(.object(["status": .string("rejected"), "error_code": .string(code), "retryable": .bool(true)]))
    }

    /// A tap that lands while the plan is moving is retried once the sensor publishes the new revision.
    @Test func aRevisionMismatchIsRetriedWithTheFreshRevision() async {
        let store = EntityStore()
        store.replaceAll([awayEntity("active", awayAttributes(mode: "solo_trip", traveler: "alex", revision: 7))])
        let responder = ScriptedResponder()
        responder.responses = [Self.rejected("expected_revision_mismatch"), ScriptedResponder.accepted(revision: 9)]
        responder.onCommand = { _ in
            // Home Assistant had already moved to revision 8; the sensor catches up after the refusal.
            if responder.sent.count == 1 {
                store.apply([awayEntity("active", awayAttributes(mode: "solo_trip", traveler: "alex", revision: 8))])
            }
        }
        let controller = HouseholdAwayController(store: store, responder: responder, retryDelay: .milliseconds(200))
        #expect(await controller.endNow() == .accepted(revision: 9))
        #expect(controller.errorCode == nil)
        #expect(responder.sent.map { $0["expected_revision"] as? Int } == [7, 8])
        #expect(Set(responder.sent.compactMap { $0["request_id"] as? String }).count == 2)
    }

    @Test func requestInProgressIsRetriedThenGivesUp() async {
        let (_, responder, store) = make()
        responder.responses = Array(repeating: Self.rejected("request_in_progress"), count: HouseholdAwayController.maxRetries + 1)
        let controller = HouseholdAwayController(store: store, responder: responder, retryDelay: .milliseconds(20))
        #expect(await controller.cancel() == .rejected(errorCode: "request_in_progress"))
        #expect(responder.sent.count == HouseholdAwayController.maxRetries + 1)
        #expect(controller.errorCode == "request_in_progress")
    }

    @Test func aNonRetryableRefusalIsNotRetried() async {
        let (controller, responder, _) = make()
        responder.responses = [Self.rejected("solo_trip_not_scheduled")]
        #expect(await controller.cancel() == .rejected(errorCode: "solo_trip_not_scheduled"))
        #expect(responder.sent.count == 1)
    }

    /// The script admitted the change but timed out on its own echo: not a failure.
    @Test func anIndeterminateAnswerIsNotAnError() async {
        let (controller, responder, _) = make()
        responder.responses = [.success(.object(["response": .object([
            "status": .string("indeterminate"), "error_code": .string("status_echo_timeout"), "revision": .number(4),
        ])]))]
        #expect(await controller.endNow() == .accepted(revision: nil))
        #expect(controller.errorCode == nil)
    }

    /// A status that briefly doesn't match the journal is not "setup required"; a lasting one is.
    @Test func setupUnavailableWaitsOutTheGrace() async {
        let store = EntityStore()
        store.replaceAll([awayEntity("active", awayAttributes(mode: "solo_trip", traveler: "alex"))])
        let controller = HouseholdAwayController(store: store, responder: ScriptedResponder(), setupGrace: .milliseconds(600))
        #expect(!controller.setupUnavailable)
        // Unavailable and available again with no suspension between: the grace cannot have elapsed, however busy the
        // host is. (Sleeps of 40 and 200 ms around a 150 ms grace failed under load.)
        store.apply([awayEntity("ending", awayAttributes(mode: "solo_trip", traveler: "alex", commandAvailable: false))])
        #expect(!controller.setupUnavailable)
        store.apply([awayEntity("idle", awayAttributes())])
        try? await Task.sleep(for: .milliseconds(900)) // Past the grace: nothing was ever shown.
        #expect(!controller.setupUnavailable)
        #expect(!controller.commandOutageConfirmed)
        // Unavailable past the grace: shown (wait for the grace to run out instead of guessing when).
        store.apply([awayEntity("idle", awayAttributes(commandAvailable: false))])
        for _ in 0..<1000 where !controller.setupUnavailable { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(controller.setupUnavailable)
        store.apply([awayEntity("idle", awayAttributes())])
        for _ in 0..<1000 where controller.setupUnavailable { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(!controller.setupUnavailable)
    }

    /// Unavailable at launch is a setup problem at once (no grace).
    @Test func unavailableAtLaunchShowsSetupAtOnce() {
        let store = EntityStore()
        store.replaceAll([awayEntity("idle", awayAttributes(commandAvailable: false))])
        let controller = HouseholdAwayController(store: store, responder: ScriptedResponder())
        #expect(controller.setupUnavailable)
    }
}
