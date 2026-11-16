import Observation
import UIKit
import XCTest
@testable import HassUI

// MARK: - Tracking one scope, applying in another

/// ``UKObservation/init(track:apply:)`` re-runs `apply` for what `track` reads and for nothing `apply` reads.
@MainActor
final class UKObservationTrackApplyHostedTests: XCTestCase {
    @Observable fileprivate final class Model {
        var tracked = 0
        var untracked = 0
    }

    func testApplyRunsNowAndAfterATrackedChangeOnly() {
        let model = Model()
        var runs = 0
        let observation = UKObservation(track: { _ = model.tracked }, apply: { _ = model.untracked; runs += 1 })
        XCTAssertEqual(runs, 1, "Runs once at the start")
        model.untracked += 1
        HostedPage.wait(0.1)
        XCTAssertEqual(runs, 1, "What apply reads does not re-run it")
        model.tracked += 1
        HostedPage.wait(0.1)
        XCTAssertEqual(runs, 2, "What track reads does")
        model.tracked += 1
        model.tracked += 1
        HostedPage.wait(0.1)
        XCTAssertEqual(runs, 3, "Several changes in one turn cost one run")
        observation.cancel()
        model.tracked += 1
        HostedPage.wait(0.1)
        XCTAssertEqual(runs, 3, "A cancelled observation stops")
    }

    func testTheSingleClosureFormStillTracksEverythingItReads() {
        let model = Model()
        var runs = 0
        let observation = UKObservation { _ = model.tracked; _ = model.untracked; runs += 1 }
        model.untracked += 1
        HostedPage.wait(0.1)
        XCTAssertEqual(runs, 2)
        observation.cancel()
    }
}
