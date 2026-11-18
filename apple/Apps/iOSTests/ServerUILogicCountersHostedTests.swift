import Foundation
@testable import HassCore
import HassTelemetry
import UIKit
import XCTest
@testable import HassUI

// MARK: - The logic counters, on a real page

/// What a live update costs in evaluations, proved on a hosted renderer through the `logic.*` counters (`LogicCost`): an entity nobody reads
/// runs nothing, an attribute-only change runs the readers of `state` and notifies no view, and a `choose` that flips reads the other branch.
///
/// These are correctness tests, not timings: they run in every hosted pass, on every family, and need no environment.
@MainActor
final class ServerUILogicCountersHostedTests: XCTestCase {
    private var wasEnabled = false
    private var scene: LogicScene?

    override func setUp() async throws {
        try await super.setUp()
        wasEnabled = Telemetry.isEnabled
        Telemetry.isEnabled = true
    }

    override func tearDown() async throws {
        scene?.close()
        scene = nil
        Telemetry.isEnabled = wasEnabled
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private struct Counts: Equatable {
        var runs = 0
        var skipped = 0
    }

    /// Counter movement across `work` and the run loop draining after it.
    private func counts(_ work: () -> Void) -> Counts {
        let before = Telemetry.log.counters
        work()
        LogicDriver(scenario: "counters").drain()
        let after = Telemetry.log.counters
        return Counts(runs: (after[LogicCost.runsCounter] ?? 0) - (before[LogicCost.runsCounter] ?? 0),
                      skipped: (after[LogicCost.skippedEqualCounter] ?? 0) - (before[LogicCost.skippedEqualCounter] ?? 0))
    }

    private func host(_ document: LogicDocument, watched: Int) throws -> LogicScene {
        let made = try LogicScene(document: document, house: LogicHouse.entities(watched: watched))
        scene = made
        return made
    }

    // MARK: Unrelated entities

    func testAnEntityNobodyReadsRunsNoEvaluation() throws {
        var document = LogicDocument()
        document.sources = (0..<20).map { ("w\($0)", LogicHouse.watched($0)) }
        document.tabs = [.init(id: "home", nodes: (0..<20).map { LogicDocument.stateText("n\($0)", source: "w\($0)") }
                          + (0..<13).map { LogicDocument.text("v\($0)", value: LogicDocument.literal("v"), visibleWhen: ["type": "viewer", "isAdmin": true]) })]
        let scene = try host(document, watched: 20)
        let unrelated = counts { _ = scene.store.apply(LogicHouse.bulkChanges(count: 500, generation: 1)) }
        XCTAssertEqual(unrelated, Counts(runs: 0, skipped: 0), "500 changed entities no node reads cost no evaluation and no view write")
        let idle = counts { HostedPage.wait(0.3) }
        XCTAssertEqual(idle.runs, 0, "a page nobody updates runs nothing")
    }

    func testOnlyTheNodeThatReadsTheChangedEntityRuns() throws {
        var document = LogicDocument()
        document.sources = (0..<20).map { ("w\($0)", LogicHouse.watched($0)) }
        document.tabs = [.init(id: "home", nodes: (0..<20).map { LogicDocument.stateText("n\($0)", source: "w\($0)") })]
        let scene = try host(document, watched: 20)
        let one = counts { _ = scene.store.apply([EntityState(entityId: LogicHouse.watched(3), state: LogicHouse.state(3, generation: 1))]) }
        XCTAssertEqual(one.runs, 1, "one box update re-runs the one node that read it")
    }

    // MARK: Equal results

    func testAnAttributeOnlyChangeRunsTheReadersOfStateAndWritesNoView() throws {
        var document = LogicDocument()
        document.sources = [("tv", "media_player.demo_lw_tv")]
        document.tabs = [.init(id: "home", nodes: (0..<6).map {
            LogicDocument.text("n\($0)", value: LogicDocument.literal("x"), visibleWhen: LogicDocument.isState("tv", in: ["playing"]))
        })]
        let made = try LogicScene(document: document, house: LogicHouse.entities(watched: 0, extra: [EntityState(entityId: "media_player.demo_lw_tv", state: "playing")]))
        scene = made
        let view = try made.view("n0", on: "home")
        XCTAssertFalse(view.isHidden)
        let churn = counts {
            _ = made.store.apply([EntityState(entityId: "media_player.demo_lw_tv", state: "playing", attributes: ["media_position": .number(12)])])
        }
        XCTAssertEqual(churn.runs, 6, "tracking is per entity, so every reader of the state re-runs")
        XCTAssertEqual(churn.skipped, 6, "and every one finds the answer it already showed, so none writes a view")
        XCTAssertFalse(view.isHidden)
        let flipped = counts { _ = made.store.apply([EntityState(entityId: "media_player.demo_lw_tv", state: "paused")]) }
        XCTAssertEqual(flipped, Counts(runs: 6, skipped: 0), "a real change is six runs and six view writes")
        XCTAssertTrue(view.isHidden)
    }

    func testATabBadgeThatComesOutTheSameWritesNothing() throws {
        var document = LogicDocument()
        document.sources = [("a", LogicHouse.watched(0)), ("b", LogicHouse.watched(1))]
        let badge = LogicDocument.choose([(LogicDocument.isState("a"), LogicDocument.literal("2")),
                                          (LogicDocument.isState("b"), LogicDocument.literal("2"))], otherwise: LogicDocument.literal("1"))
        document.tabs = [.init(id: "home", nodes: [LogicDocument.text("n", value: LogicDocument.literal("x"))], badge: badge)]
        let scene = try host(document, watched: 2)
        // a is on, b off: the badge says "2" and reads only a (the first case matches).
        XCTAssertEqual(counts { _ = scene.store.apply([EntityState(entityId: LogicHouse.watched(1), state: "on")]) }.runs, 0, "b is not read yet")
        let same = counts { _ = scene.store.apply([EntityState(entityId: LogicHouse.watched(0), state: "off")]) }
        XCTAssertEqual(same, Counts(runs: 1, skipped: 1), "the badge re-ran and found the same words")
    }

    // MARK: A choose that flips

    func testAChooseThatFlipsReadsTheOtherBranch() throws {
        var document = LogicDocument()
        document.sources = [("a", LogicHouse.watched(0)), ("b", LogicHouse.watched(1)), ("c", LogicHouse.watched(2))]
        document.tabs = [.init(id: "home", nodes: [
            LogicDocument.text("n", value: LogicDocument.choose([(LogicDocument.isState("a"), LogicDocument.read("b"))], otherwise: LogicDocument.read("c"))),
        ])]
        // Generation 0: a on, b off, c on. The node reads a and b.
        let scene = try host(document, watched: 3)
        func change(_ index: Int, _ state: String) -> Counts {
            counts { _ = scene.store.apply([EntityState(entityId: LogicHouse.watched(index), state: state)]) }
        }
        XCTAssertEqual(change(2, "off").runs, 0, "c is not read while a is on")
        XCTAssertEqual(change(1, "on").runs, 1, "b is read while a is on")
        XCTAssertEqual(change(0, "off").runs, 1, "a flips the branch")
        XCTAssertEqual(change(1, "off").runs, 0, "b is no longer read")
        XCTAssertEqual(change(2, "on").runs, 1, "c is read now: the node re-subscribed")
    }

    // MARK: The meter on a hosted page

    func testTheCountersTimeEveryRunAndTheDriverReportsThem() throws {
        var document = LogicDocument()
        document.sources = (0..<10).map { ("w\($0)", LogicHouse.watched($0)) }
        document.tabs = [.init(id: "home", nodes: (0..<10).map { LogicDocument.stateText("n\($0)", source: "w\($0)") })]
        let scene = try host(document, watched: 10)
        let store = scene.store
        let measured = LogicDriver(scenario: "LW-test").measure(iterations: 2) { iteration in
            LogicDriver.apply((0..<10).map { EntityState(entityId: LogicHouse.watched($0), state: LogicHouse.state($0, generation: iteration + 1)) }, to: store)
        }
        XCTAssertEqual(measured.runs, 20, "ten nodes, two bursts")
        XCTAssertGreaterThan(measured.runUs, 0, "the runs were timed")
        XCTAssertTrue(measured.row.hasPrefix("LOGICPERF\t"))
        XCTAssertEqual(measured.row.split(separator: "\t").count, LogicMeasurement.header.split(separator: "\t").count)
    }
}

// MARK: - The fixture's manifest

/// The fixture names the capabilities its document uses, and the compiler agrees: with them the document decodes, and without any one of them it
/// is refused as a manifest mismatch.
@MainActor
final class LogicDocumentCapabilityTests: XCTestCase {
    private func documents() -> [LogicDocument] {
        var plain = LogicDocument()
        plain.tabs = [.init(id: "a", nodes: [LogicDocument.text("t", value: LogicDocument.literal("x"))])]
        var rules = LogicDocument()
        rules.sources = [("s", LogicHouse.watched(0))]
        rules.tabs = [.init(id: "a", nodes: [LogicDocument.stateText("t", source: "s"), LogicDocument.shownWhenOn("u", source: "s")],
                            badge: LogicDocument.choose([(LogicDocument.isState("s"), LogicDocument.literal("2"))], otherwise: LogicDocument.literal("1")))]
        var clock = LogicDocument()
        clock.models = [LogicDocument.clockSource]
        clock.tabs = [.init(id: "a", nodes: [LogicDocument.text("t", value: LogicDocument.format("{m}", ["m": LogicDocument.read("clock", path: ["minute"], as: "number")]))])]
        return [plain, rules, clock]
    }

    func testTheManifestMatchesTheDocumentExactly() throws {
        for document in documents() {
            XCTAssertNoThrow(try document.publication(), "\(document.requiredCapabilities)")
            for missing in document.requiredCapabilities {
                XCTAssertThrowsError(try document.publication(capabilities: document.requiredCapabilities.filter { $0 != missing }),
                                     "without \(missing) the document is refused")
            }
            XCTAssertThrowsError(try document.publication(capabilities: document.requiredCapabilities + ["sh.conditions@1"]),
                                 "an id the document does not use is refused too")
        }
    }
}
