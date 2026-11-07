import Foundation
@testable import HassCore
import Testing

/// The failed face on ``OptimisticOverlay`` (pattern: optimistic-actions, "Failure"): shown for 4 s after a rejected or
/// unconfirmed command, cleared by the timer or the next commit.
@MainActor
struct OptimisticFailureTests {
    private func make(timeout: Bool = false) -> (OptimisticOverlay, ManualScheduler) {
        let scheduler = ManualScheduler()
        return (OptimisticOverlay(rules: ["a": .confirmation, "b": .confirmation], scheduler: scheduler), scheduler)
    }

    @Test func failingResetsThePendingValueAndShowsTheFaceFourSeconds() {
        let (overlay, scheduler) = make()
        let generation = overlay.commit("a", value: "on", live: "off", revertAfter: .seconds(2))
        overlay.fail("a", generation: generation)
        #expect(overlay.pending["a"] == nil)
        #expect(overlay.isFailed("a"))
        #expect(scheduler.pending.map(\.delay) == [.seconds(4)])
        scheduler.fireAll()
        #expect(!overlay.isFailed("a"))
    }

    @Test func aStaleGenerationNeverShowsAFailure() {
        let (overlay, _) = make()
        let first = overlay.commit("a", value: "on", live: "off", revertAfter: .seconds(2))
        overlay.commit("a", value: "off", live: "on", revertAfter: .seconds(2))
        overlay.fail("a", generation: first)
        #expect(!overlay.isFailed("a"))
        #expect(overlay.pending["a"] == "off")
    }

    @Test func anUntrackedKeyCanStillFail() {
        let (overlay, _) = make()
        overlay.fail("automation.demo_power")
        #expect(overlay.isFailed("automation.demo_power"))
        overlay.clearFailure("automation.demo_power")
        #expect(!overlay.isFailed("automation.demo_power"))
        overlay.clearFailure("automation.demo_power")
        #expect(!overlay.isFailed("automation.demo_power"))
    }

    @Test func aSecondFailureRestartsTheTimer() {
        let (overlay, scheduler) = make()
        overlay.markFailed("a")
        let first = scheduler.items[0]
        overlay.markFailed("a")
        #expect(first.cancelled)
        scheduler.fireAll()
        #expect(!overlay.isFailed("a"))
    }

    @Test func aNewCommitClearsTheFailedFace() {
        let (overlay, _) = make()
        overlay.markFailed("a")
        overlay.commit("a", value: "on", live: "off", revertAfter: .seconds(2))
        #expect(!overlay.isFailed("a"))
    }

    @Test func aTimeoutFailsOnlyWhenTheCommitAsksFor() {
        let (overlay, scheduler) = make()
        overlay.commit("a", value: "on", live: "off", revertAfter: .seconds(2))
        scheduler.fireAll()
        #expect(!overlay.isFailed("a"), "A default commit just reverts")

        overlay.commit("a", value: "on", live: "off", revertAfter: .seconds(8), failsOnTimeout: true)
        scheduler.fireAll()
        #expect(overlay.pending["a"] == nil)
        #expect(overlay.isFailed("a"))
        scheduler.fireAll()

        // A confirmation before the timeout is not a failure.
        overlay.commit("a", value: "on", live: "off", revertAfter: .seconds(8), failsOnTimeout: true)
        overlay.liveChanged("a", to: "on")
        scheduler.fireAll()
        #expect(!overlay.isFailed("a"))

        // The flag belongs to one commit: the next plain commit does not inherit it.
        overlay.commit("a", value: "off", live: "on", revertAfter: .seconds(2))
        scheduler.fireAll()
        #expect(!overlay.isFailed("a"))
    }
}
