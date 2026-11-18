import Foundation
import Observation
import UIKit
import XCTest
@testable import HassUI

// MARK: - A resting observation

/// A value the observations read.
@MainActor
@Observable
private final class RestInput {
    var value = 0
}

/// The branches of resting an observation (`UKObservation.pause()` and `resume()`, `UKObservationBag.pause()` and `resume()`; pattern:
/// derived-value, "Resting while away"). They are plain main-actor logic, and the hosted pass runs them once per device family.
@MainActor
final class UKObservationRestHostedTests: XCTestCase {
    private let input = RestInput()

    /// An observation of `input` that counts its runs and keeps the last value it read.
    private func observation(runs: Box) -> UKObservation {
        UKObservation(track: { [input] in runs.last = input.value }, apply: { runs.count += 1 })
    }

    private final class Box {
        var count = 0
        var last = -1
    }

    /// Lets the hop from `onChange` and the queued run happen.
    private func settle() { HostedPage.wait(0.05) }

    func testAChangeWhilePausedIsNotedOnceAndRunsNothingUntilResume() {
        let runs = Box()
        let observation = observation(runs: runs)
        XCTAssertEqual(runs.count, 1, "the first run happens when it is made")
        observation.pause()
        input.value = 1
        input.value = 2
        settle()
        XCTAssertEqual(runs.count, 1, "paused: two changes ran nothing")
        XCTAssertTrue(observation.resume(), "an input changed meanwhile, so resume ran it")
        XCTAssertEqual(runs.count, 2, "once, for both changes, in the resume call itself")
        XCTAssertEqual(runs.last, 2, "and it read the newest value")
    }

    func testResumeWithNothingChangedRunsNothing() {
        let runs = Box()
        let observation = observation(runs: runs)
        observation.pause()
        XCTAssertFalse(observation.resume())
        XCTAssertEqual(runs.count, 1)
        XCTAssertFalse(observation.resume(), "an observation that is not paused has nothing to resume")
    }

    func testARunAlreadyQueuedWhenThePauseLandsDoesNotRun() {
        let runs = Box()
        let observation = observation(runs: runs)
        input.value = 1
        // The change's hop to the main actor runs first and queues the re-run on the run loop; the pause is queued behind that hop and lands
        // before the run loop gets to the re-run.
        Task { @MainActor in observation.pause() }
        settle()
        XCTAssertEqual(runs.count, 1, "the queued run found the observation paused and noted the change instead")
        XCTAssertTrue(observation.resume())
        XCTAssertEqual(runs.last, 1)
    }

    func testAnObservationThatIsCancelledWhilePausedNeverRunsAgain() {
        let runs = Box()
        let observation = observation(runs: runs)
        observation.pause()
        input.value = 1
        settle()
        observation.cancel()
        XCTAssertFalse(observation.resume())
        input.value = 2
        settle()
        XCTAssertEqual(runs.count, 1)
    }

    func testAChangeAfterResumeRunsAsBefore() {
        let runs = Box()
        let observation = observation(runs: runs)
        observation.pause()
        input.value = 1
        settle()
        XCTAssertTrue(observation.resume())
        input.value = 2
        settle()
        XCTAssertEqual(runs.count, 3, "tracking was never dropped: the next change runs it again")
    }

    // MARK: The bag

    func testABagRestsEveryObservationAndCountsTheOnesThatCaughtUp() {
        let bag = UKObservationBag()
        let (first, second, third) = (Box(), Box(), Box())
        bag.observe(track: { [input] in first.last = input.value }, apply: { first.count += 1 })
        bag.observe(track: { [input] in second.last = input.value }, apply: { second.count += 1 })
        let other = RestInput()
        bag.observe(track: { third.last = other.value }, apply: { third.count += 1 })
        bag.pause()
        XCTAssertTrue(bag.isPaused)
        input.value = 1
        settle()
        XCTAssertEqual([first.count, second.count, third.count], [1, 1, 1])
        XCTAssertEqual(bag.resume(), 2, "two of the three read what changed")
        XCTAssertEqual([first.count, second.count, third.count], [2, 2, 1])
        XCTAssertFalse(bag.isPaused)
    }

    func testAnObservationAddedToAPausedBagRunsOnceThenRests() {
        let bag = UKObservationBag()
        bag.pause()
        let runs = Box()
        bag.observe(track: { [input] in runs.last = input.value }, apply: { runs.count += 1 })
        XCTAssertEqual(runs.count, 1, "its first run still happens, so its views are drawn")
        input.value = 1
        settle()
        XCTAssertEqual(runs.count, 1, "and then it rests with the rest of the bag")
        XCTAssertEqual(bag.resume(), 1)
        XCTAssertEqual(runs.last, 1)
    }
}
