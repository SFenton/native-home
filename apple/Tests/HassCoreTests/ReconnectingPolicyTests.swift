import Foundation
@testable import HassCore
import Testing

/// When the reconnecting arc counts the connection as down.
struct ReconnectingPolicyTests {
    @Test func everyStateThatIsNotLiveOrRefusedIsDown() {
        #expect(!ReconnectingPolicy.isDown(.connected(version: "2026.10")))
        #expect(!ReconnectingPolicy.isDown(.rejected), "a refused token ends the session; no arc")
        #expect(ReconnectingPolicy.isDown(.disconnected))
        #expect(ReconnectingPolicy.isDown(.connecting))
        #expect(ReconnectingPolicy.isDown(.waitingToReconnect))
    }

    @Test func theArcWaitsTwoSeconds() {
        #expect(ReconnectingPolicy.delay == .seconds(2))
    }
}

/// A sleep the test releases by hand, so the indicator's timing is driven by signals and never by a wall clock.
@MainActor
final class GatedSleeper {
    private struct Waiter {
        let id: Int
        let continuation: CheckedContinuation<Void, any Error>
    }

    /// Every duration the indicator asked to wait, in order.
    private(set) var requested: [Duration] = []
    private var waiters: [Waiter] = []
    private var arrivals: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var nextID = 0

    /// The sleep to hand to ``ReconnectingIndicator/follow(isDown:delay:fade:lead:sleep:)``: it parks until ``release()`` or cancellation.
    var sleep: (Duration) async throws -> Void { { [self] in try await park($0) } }

    private func park(_ duration: Duration) async throws {
        try Task.checkCancellation()
        nextID += 1
        let id = nextID
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                requested.append(duration)
                waiters.append(Waiter(id: id, continuation: continuation))
                let ready = arrivals.filter { requested.count >= $0.count }
                arrivals.removeAll { requested.count >= $0.count }
                for arrival in ready { arrival.continuation.resume() }
                if Task.isCancelled { cancel(id) }
            }
        } onCancel: {
            Task { @MainActor [self] in cancel(id) }
        }
    }

    private func cancel(_ id: Int) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    /// Returns once the indicator has asked to wait `count` times in total.
    func waitForSleeps(_ count: Int) async {
        if requested.count >= count { return }
        await withCheckedContinuation { arrivals.append((count, $0)) }
    }

    /// Lets the oldest parked sleep finish.
    func release() {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().continuation.resume()
    }
}

/// When the reconnecting arc is in the header and when it is lit.
@MainActor
struct ReconnectingIndicatorTests {
    private let delay: Duration = .seconds(2)
    private let fade: Duration = .milliseconds(350)
    private let lead: Duration = .milliseconds(100)

    /// A sleep that finishes at once, for setup that must not wait.
    private let instant: (Duration) async throws -> Void = { _ in }

    /// A sleep that fails the test: the call under test must not wait.
    private let forbidden: (Duration) async throws -> Void = { _ in Issue.record("the indicator waited when it must not") }

    @Test func anOutageShorterThanTheDelayNeverShows() async {
        let indicator = ReconnectingIndicator()
        let sleeper = GatedSleeper()
        let down = Task { await indicator.follow(isDown: true, delay: delay, fade: fade, lead: lead, sleep: sleeper.sleep) }
        await sleeper.waitForSleeps(1)
        #expect(sleeper.requested == [delay])
        down.cancel()
        await down.value
        await indicator.follow(isDown: false, fade: fade, sleep: forbidden)
        #expect(!indicator.isPresent)
        #expect(!indicator.isLit)
    }

    @Test func theArcIsPlacedAfterTheDelayAndLitALeadLater() async {
        let indicator = ReconnectingIndicator()
        let sleeper = GatedSleeper()
        let down = Task { await indicator.follow(isDown: true, delay: delay, fade: fade, lead: lead, sleep: sleeper.sleep) }
        await sleeper.waitForSleeps(1)
        #expect(!indicator.isPresent, "still inside the delay")
        sleeper.release()
        await sleeper.waitForSleeps(2)
        #expect(sleeper.requested == [delay, lead])
        #expect(indicator.isPresent && !indicator.isLit, "placed unlit so it fades up rather than popping")
        sleeper.release()
        await down.value
        #expect(indicator.isPresent && indicator.isLit)
    }

    @Test func comingBackDimsTheArcThenRemovesIt() async {
        let indicator = ReconnectingIndicator()
        await indicator.follow(isDown: true, delay: delay, fade: fade, lead: lead, sleep: instant)
        let sleeper = GatedSleeper()
        let up = Task { await indicator.follow(isDown: false, fade: fade, sleep: sleeper.sleep) }
        await sleeper.waitForSleeps(1)
        #expect(sleeper.requested == [fade])
        #expect(indicator.isPresent && !indicator.isLit, "dimmed but still in the bar while it fades")
        sleeper.release()
        await up.value
        #expect(!indicator.isPresent && !indicator.isLit)
    }

    @Test func goingDownAgainMidFadeLightsTheArcWhereItIsWithNoWait() async {
        let indicator = ReconnectingIndicator()
        await indicator.follow(isDown: true, delay: delay, fade: fade, lead: lead, sleep: instant)
        let sleeper = GatedSleeper()
        let up = Task { await indicator.follow(isDown: false, fade: fade, sleep: sleeper.sleep) }
        await sleeper.waitForSleeps(1)
        up.cancel()
        await up.value
        await indicator.follow(isDown: true, delay: delay, fade: fade, lead: lead, sleep: forbidden)
        #expect(indicator.isPresent && indicator.isLit, "no 2 s wait: the arc is already in the bar")
    }

    @Test func comingBackWithNothingShownDoesNothing() async {
        let indicator = ReconnectingIndicator()
        await indicator.follow(isDown: false, fade: fade, sleep: forbidden)
        #expect(!indicator.isPresent && !indicator.isLit)
    }

    @Test func cancelledWhileDownLeavesNothingHalfPlaced() async {
        let indicator = ReconnectingIndicator()
        let sleeper = GatedSleeper()
        let down = Task { await indicator.follow(isDown: true, delay: delay, fade: fade, lead: lead, sleep: sleeper.sleep) }
        await sleeper.waitForSleeps(1)
        sleeper.release()
        await sleeper.waitForSleeps(2)
        down.cancel()
        await down.value
        #expect(indicator.isPresent && !indicator.isLit, "cancelled between placing and lighting; the next call lights it")
    }

    @Test func theFadeIsAThirdOfASecondAndTheLeadIsShort() {
        #expect(ReconnectingPolicy.fade == .milliseconds(350))
        #expect(ReconnectingPolicy.insertLead < ReconnectingPolicy.fade)
    }
}
