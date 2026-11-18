import Foundation
@testable import HassCore
import HassTelemetry
import UIKit
import XCTest
@testable import HassUI

// MARK: - The worst-case suite

/// What authored logic costs the main thread when a live update is as bad as the house can make it: the scenarios of
/// `build/research/logic-worst-case.md` (a local note), each run on iPhone, iPhone Duo and iPad.
///
/// Every scenario drives a real `UKServerUIRenderer` over an invented house of about 4,700 entities, applies entity changes the way a
/// delivery does (one main-queue turn per batch) and measures the main thread's run-loop turns (`MainThreadCostMeter`) and the
/// `logic.*` counters (`LogicCost`). The budgets are the ones in `.agents/testing/apple/logic-evaluation.md`: p95 turn at most 8 ms and no
/// turn over 16 ms; a standing-still live page at most 25 ms of update work in 8 s.
///
/// Where `main` already misses a budget, the assertion is wrapped in an expected failure that names the scenario (``knownBreaches``); the
/// budget is never loosened. The expected failure is not strict, so the fix that makes it pass does not fail the suite.
///
/// The suite runs only with `TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1`: its numbers move with the Mac's load. Rows (``LogicMeasurement/row``) go to
/// `FENTON_LOGICPERF_FILE` when set.
@MainActor
final class LogicWorstCasePerformanceTests: XCTestCase {
    /// The scenarios whose budget `main` misses, with the reason; filled from the baseline run.
    static let knownBreaches: [String: String] = [
        "LW-a-replay": "one delivery applies 1,880 changed entities and wakes 100 evaluations in the same stretch of turns: p95 8.2 to 9.4 ms on Duo and iPad, one 16 ms turn on iPad in an earlier run",
        "LW-h-minute-tick": "40 clock readers and 40 entity readers wake in one turn; the evaluations are about 2 ms of it and the rest is the labels' layout: iPad 12 to 17 ms turns",
    ]

    /// What a listed breach may not exceed: p95 and the longest turn, in milliseconds.
    static let breachCeilingP95Ms = 10.0, breachCeilingTurnMs = 20.0

    private var wasTelemetryEnabled = false
    private var scene: LogicScene?

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FENTON_PERF_ON_SIMULATOR"] == "1",
                          "Performance numbers need TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1.")
        let load = LogicDriver.load1
        if load >= 40 { Self.note("LOAD OVER 40: 1-minute load \(String(format: "%.1f", load)) at start; these numbers are not a baseline") }
        wasTelemetryEnabled = Telemetry.isEnabled
        Telemetry.isEnabled = true
        warmUpTheProcess()
    }

    /// The first scene a freshly launched app draws pays for the app's own first frame, its backdrop and the first layout: hundreds of
    /// milliseconds in one turn that belong to no scenario. The first test of the process builds and closes one small scene before it meters.
    private func warmUpTheProcess() {
        guard !Self.processWarmed else { return }
        Self.processWarmed = true
        var document = LogicDocument()
        document.sources = [("w0", LogicHouse.watched(0))]
        document.tabs = [.init(id: "home", nodes: [LogicDocument.stateText("n0", source: "w0")])]
        guard let warm = try? LogicScene(document: document, house: LogicHouse.entities(watched: 1)) else { return }
        HostedPage.wait(1)
        warm.close()
        HostedPage.hideTracked()
    }

    private static var processWarmed = false

    override func tearDown() async throws {
        scene?.close()
        scene = nil
        Telemetry.isEnabled = wasTelemetryEnabled
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Scenarios

    /// (a) Reconnect replay: the full state of a 4,700-entity house comes back with 1,880 entities changed, every one of the 150 watched among
    /// them. The 150 nodes sit on two pages (a page holds at most 100), both loaded; 13 more nodes carry viewer predicates, which do not re-run
    /// because no person is added. Expected evaluations: one per watched node per replay.
    func testReplayOfTheWholeHouse() throws {
        let watched = 150, viewerNodes = 13
        var document = LogicDocument()
        let first = (0..<100).map { LogicDocument.stateText("n\($0)", source: "w\($0)") }
        var second = (100..<watched).map { LogicDocument.stateText("n\($0)", source: "w\($0)") }
        for index in 0..<viewerNodes {
            second.append(LogicDocument.text("v\(index)", value: LogicDocument.literal("viewer"), visibleWhen: ["type": "viewer", "isAdmin": index % 2 == 0]))
        }
        document.sources = (0..<watched).map { ("w\($0)", LogicHouse.watched($0)) }
        document.tabs = [.init(id: "home", nodes: first), .init(id: "more", nodes: second)]
        let scene = try show(document, house: LogicHouse.entities(watched: watched))
        _ = try scene.page("more")
        HostedPage.wait(0.3)
        let store = scene.store
        let measured = driver("LW-a-replay").measure(iterations: 5) { iteration in
            let generation = iteration + 1
            var changes = (0..<watched).map { EntityState(entityId: LogicHouse.watched($0), state: LogicHouse.state($0, generation: generation)) }
            changes += (0..<LogicHouse.people).map { EntityState(entityId: LogicHouse.person($0), state: generation % 2 == 0 ? "home" : "away",
                                                                   attributes: ["user_id": .string("lw-user-\($0)")]) }
            changes += LogicHouse.bulkChanges(count: 1_880 - changes.count, generation: generation)
            return LogicDriver.apply(changes, to: store)
        }
        // The first page is on screen and the second is loaded and away: only the first evaluates (the viewer nodes read nothing that changes).
        finish(measured, expectingRuns: 5 * 100, atMostRuns: 5 * 100 + 50)
    }

    /// (b) Burst: 50 changed boxes feeding 50 tiles on one page ("all lights off"). Expected evaluations: 50 per burst.
    func testBurstOfFiftyChangedBoxes() throws {
        let count = 50
        var document = LogicDocument()
        document.sources = (0..<count).map { ("w\($0)", LogicHouse.watched($0)) }
        document.tabs = [.init(id: "home", nodes: (0..<count).map { LogicDocument.stateText("n\($0)", source: "w\($0)") })]
        let scene = try show(document, house: LogicHouse.entities(watched: count))
        let store = scene.store
        let measured = driver("LW-b-burst").measure(iterations: 10) { iteration in
            LogicDriver.apply((0..<count).map { EntityState(entityId: LogicHouse.watched($0), state: LogicHouse.state($0, generation: iteration + 1)) },
                              to: store)
        }
        finish(measured, expectingRuns: 10 * count)
    }

    /// (c1) Attribute churn: a media player's position moves every second while 24 nodes read only its `state`. Tracking is per whole
    /// entity, so each tick re-runs all 24 for an answer that did not change. A standing-still page: 8 seconds, 25 ms of update work.
    func testAttributeChurnOnAMediaPosition() throws {
        try attributeChurn(scenario: "LW-c1-media-position", entity: "media_player.demo_lw_tv", baseState: "playing",
                           condition: LogicDocument.isState("tv", in: ["playing"])) { tick in
            EntityState(entityId: "media_player.demo_lw_tv", state: "playing", attributes: ["media_position": .number(Double(tick))])
        }
    }

    /// (c2) Attribute churn: a power sensor ticks every second while 24 nodes ask only whether it is above 100 W; the answer stays yes.
    func testChurnOfAOneSecondPowerSensor() throws {
        try attributeChurn(scenario: "LW-c2-power-sensor", entity: "sensor.demo_lw_power", baseState: "120",
                           condition: ["type": "numeric", "sourceId": "tv", "path": ["state"], "above": LogicDocument.literal(100)]) { tick in
            EntityState(entityId: "sensor.demo_lw_power", state: String(120 + tick % 20))
        }
    }

    /// (d1) Large count: a 32-entry count (`math add` over 32 `choose`) used in 10 places, one counted entity changing at a time.
    /// Expected evaluations: 10 per change, 32 reads in each.
    func testLargeCountOneEntityAtATime() throws {
        let count = try LargeCount(sites: 10)
        scene = count.scene
        let measured = driver("LW-d1-count32-single").measure(iterations: 32) { iteration in
            LogicDriver.apply([EntityState(entityId: LogicHouse.watched(iteration), state: LogicHouse.state(iteration, generation: 1))],
                              to: count.scene.store)
        }
        finish(measured, expectingRuns: 32 * 10)
        XCTAssertEqual(count.shown(), Array(repeating: "16", count: 10), "the ten copies agree: half the entities are on")
    }

    /// (d3) The same 32-entry count as one `count` operand (`sh.count@1`), used in 10 places, one counted entity changing at a time. One node and 32
    /// tracked reads in each evaluation, no pattern match; the answer is the same "16" as (d1), and the runs are the same 10 per change.
    func testCountOperandOneEntityAtATime() throws {
        let count = try LargeCount(sites: 10, operand: .count)
        let measured = LogicDriver(scenario: "LW-d3-count-operand-single").measure(iterations: 32) { iteration in
            LogicDriver.apply([EntityState(entityId: LogicHouse.watched(iteration), state: LogicHouse.state(iteration, generation: 1))],
                              to: count.scene.store)
        }
        scene = count.scene
        finish(measured, expectingRuns: 32 * 10)
        XCTAssertEqual(count.shown(), Array(repeating: "16", count: 10), "the ten copies agree: half the entities are on")
    }

    /// (d4) The `count` operand with all 32 counted entities changing in one delivery: one shared evaluation, ten redraws only when the answer differs.
    func testCountOperandAllAtOnce() throws {
        let count = try LargeCount(sites: 10, operand: .count)
        let measured = LogicDriver(scenario: "LW-d4-count-operand-all").measure(iterations: 5) { iteration in
            LogicDriver.apply((0..<32).map { EntityState(entityId: LogicHouse.watched($0), state: LogicHouse.state($0, generation: iteration + 1)) },
                              to: count.scene.store)
        }
        scene = count.scene
        finish(measured, expectingRuns: 5)
    }

    /// (d2) Large count: all 32 counted entities change in one delivery. One run per place, not one per entity.
    func testLargeCountAllAtOnce() throws {
        let count = try LargeCount(sites: 10)
        scene = count.scene
        let measured = driver("LW-d2-count32-all").measure(iterations: 5) { iteration in
            LogicDriver.apply((0..<32).map { EntityState(entityId: LogicHouse.watched($0), state: LogicHouse.state($0, generation: iteration + 1)) },
                              to: count.scene.store)
        }
        // One shared evaluation of the sum per delivery; the ten readers redraw only when the sum differs.
        finish(measured, expectingRuns: 5)
    }

    /// (e) Viewer predicates: 13 `visibleWhen` rules that each ask a state and the viewer (`all` evaluates every child) in a 4,700-entity house
    /// whose viewer matches no person, so each viewer read scans the whole house. Each step changes the 13 entities and adds a person, which
    /// moves the people revision those reads also depend on.
    func testThirteenViewerPredicates() throws {
        let nodes = 13
        var document = LogicDocument()
        document.sources = (0..<nodes).map { ("w\($0)", LogicHouse.watched($0)) }
        document.tabs = [.init(id: "home", nodes: (0..<nodes).map { index in
            let viewer: [String: Any]
            switch index % 3 {
            case 0: viewer = ["type": "viewer", "isAdmin": true]
            case 1: viewer = ["type": "viewer", "userIds": ["lw-user-\(index)"]]
            default: viewer = ["type": "viewer-person", "in": ["home"]]
            }
            return LogicDocument.text("v\(index)", value: LogicDocument.literal("viewer"),
                                      visibleWhen: ["type": "all", "of": [LogicDocument.isState("w\(index)"), viewer]])
        })]
        let scene = try show(document, house: LogicHouse.entities(watched: nodes))
        let store = scene.store
        let measured = driver("LW-e-viewer13").measure(iterations: 20) { iteration in
            var changes = (0..<nodes).map { EntityState(entityId: LogicHouse.watched($0), state: LogicHouse.state($0, generation: iteration + 1)) }
            changes.append(EntityState(entityId: "person.demo_lw_new\(iteration)", state: "home", attributes: ["user_id": .string("lw-new-\(iteration)")]))
            return LogicDriver.apply(changes, to: store)
        }
        finish(measured, expectingRuns: 20 * nodes)
    }

    /// (f) Every tab visited: five tabs (six need an extended-tabs capability the app does not ship), each shown once and left for the first, each page
    /// reading the same 30 shared entities plus its own; three tabs carry a badge. Only the page on screen evaluates: one shared change costs one
    /// page's 30 runs and the three badges, which belong to the renderer, not four more pages' 120 runs.
    func testEveryTabVisited() throws {
        let tabs = 5, shared = 30
        var document = LogicDocument()
        document.sources = (0..<(shared + tabs)).map { ("w\($0)", LogicHouse.watched($0)) }
        document.tabs = (0..<tabs).map { tab in
            var nodes = (0..<shared).map { LogicDocument.stateText("t\(tab)s\($0)", source: "w\($0)") }
            nodes += (0..<10).map { LogicDocument.shownWhenOn("t\(tab)o\($0)", source: "w\(shared + tab)") }
            let badge = tab % 2 == 0 ? LogicDocument.choose([(LogicDocument.isState("w0"), LogicDocument.literal("2"))], otherwise: LogicDocument.literal("1")) : nil
            return .init(id: "tab\(tab)", nodes: nodes, badge: badge)
        }
        let scene = try show(document, house: LogicHouse.entities(watched: shared + tabs))
        // Visit every tab, then come back to the first: four pages are built, shown once and left.
        for tab in 1..<tabs { try scene.renderer.perform(.selectTab(tabId: "tab\(tab)"), from: scene.page("tab\(tab - 1)")) }
        try scene.renderer.perform(.selectTab(tabId: "tab0"), from: scene.page("tab\(tabs - 1)"))
        HostedPage.wait(0.3)
        let store = scene.store
        let measured = driver("LW-f-every-tab").measure(iterations: 10) { iteration in
            LogicDriver.apply((0..<shared).map { EntityState(entityId: LogicHouse.watched($0), state: LogicHouse.state($0, generation: iteration + 1)) },
                              to: store)
        }
        // The page on screen reads each shared entity once; the three badges read the first. The four hidden pages run nothing.
        finish(measured, expectingRuns: 10 * (shared + 3), atMostRuns: 10 * (shared + 3) + shared)
    }

    /// (g) Flip storm: 24 nodes each `choose` a branch by one entity and read the other entities of that branch; every update flips every branch,
    /// so every run re-subscribes.
    func testFlipStorm() throws {
        let nodes = 24
        var document = LogicDocument()
        for index in 0..<nodes {
            document.sources += [("a\(index)", LogicHouse.watched(index)), ("b\(index)", LogicHouse.watched(nodes + index)),
                                 ("c\(index)", LogicHouse.watched(2 * nodes + index))]
        }
        document.tabs = [.init(id: "home", nodes: (0..<nodes).map { index in
            LogicDocument.text("n\(index)", value: LogicDocument.choose([(LogicDocument.isState("a\(index)"), LogicDocument.read("b\(index)"))],
                                                                         otherwise: LogicDocument.read("c\(index)")))
        })]
        let scene = try show(document, house: LogicHouse.entities(watched: 3 * nodes))
        let store = scene.store
        let measured = driver("LW-g-flip-storm").measure(iterations: 40) { iteration in
            let generation = iteration + 1
            var changes: [EntityState] = []
            for index in 0..<nodes {
                for offset in 0..<3 {
                    let entity = index + offset * nodes
                    changes.append(EntityState(entityId: LogicHouse.watched(entity), state: LogicHouse.state(entity, generation: generation)))
                }
            }
            return LogicDriver.apply(changes, to: store)
        }
        finish(measured, expectingRuns: 40 * nodes)
    }

    /// (h) Minute tick during a burst: the clock moves to the next minute in the same turn as 40 changed boxes. 40 nodes read the clock and
    /// 40 read the entities.
    func testMinuteTickInTheMiddleOfABurst() throws {
        let count = 40
        var document = LogicDocument()
        document.models = [LogicDocument.clockSource]
        document.sources = (0..<count).map { ("w\($0)", LogicHouse.watched($0)) }
        var nodes = (0..<count).map { LogicDocument.stateText("n\($0)", source: "w\($0)") }
        nodes += (0..<count).map { index in
            LogicDocument.text("c\(index)", value: LogicDocument.format("{m}", ["m": LogicDocument.read("clock", path: ["minute"], as: "number")]))
        }
        document.tabs = [.init(id: "home", nodes: nodes)]
        let scene = try show(document, house: LogicHouse.entities(watched: count))
        let store = scene.store
        let appState = scene.renderer.bindings.appState
        let start = Date()
        let measured = driver("LW-h-minute-tick").measure(iterations: 20) { iteration in
            appState.publishClock(now: start.addingTimeInterval(Double(iteration + 1) * 60))
            return LogicDriver.apply((0..<count).map { EntityState(entityId: LogicHouse.watched($0), state: LogicHouse.state($0, generation: iteration + 1)) },
                                     to: store)
        }
        finish(measured, expectingRuns: 20 * 2 * count)
    }

    /// (i) Template copies: one logic template (a count over eight entities, `math add` over `choose`) expanded ten times, as Studio expands
    /// it before publishing. Ten copies are ten observations and ten evaluations of the same sum.
    func testTemplateExpandedTenTimes() throws {
        let entities = 8, copies = 10
        var document = LogicDocument()
        document.sources = (0..<entities).map { ("w\($0)", LogicHouse.watched($0)) }
        let template: [String: Any] = ["type": "math", "op": "add", "args": (0..<entities).map { index in
            LogicDocument.choose([(LogicDocument.isState("w\(index)"), LogicDocument.literal(1))], otherwise: LogicDocument.literal(0))
        }]
        document.tabs = [.init(id: "home", nodes: (0..<copies).map {
            LogicDocument.text("copy\($0)", value: LogicDocument.format("{n}", ["n": template]))
        })]
        let scene = try show(document, house: LogicHouse.entities(watched: entities))
        let store = scene.store
        let measured = driver("LW-i-template10").measure(iterations: 10) { iteration in
            LogicDriver.apply((0..<entities).map { EntityState(entityId: LogicHouse.watched($0), state: LogicHouse.state($0, generation: iteration + 1)) },
                              to: store)
        }
        // One shared evaluation per burst; the ten copies redraw only when the count differs.
        finish(measured, expectingRuns: 10)
    }

    // MARK: Helpers

    /// A driver that counts the scene's own runs (`LogicCost.Tally`), not the process's.
    private func driver(_ scenario: String) -> LogicDriver {
        var driver = LogicDriver(scenario: scenario)
        driver.tally = scene?.renderer.bindings.logicTally
        return driver
    }

    private func show(_ document: LogicDocument, house: [EntityState]) throws -> LogicScene {
        let made = try LogicScene(document: document, house: house)
        scene = made
        return made
    }

    /// A page of 24 nodes that read only `state` of one entity (named by source `tv`), which then changes in an attribute or a value every second
    /// for eight seconds.
    private func attributeChurn(scenario: String, entity: String, baseState: String, condition: [String: Any],
                                update: @escaping @Sendable (Int) -> EntityState) throws {
        let readers = 24
        var document = LogicDocument()
        document.sources = [("tv", entity)]
        document.tabs = [.init(id: "home", nodes: (0..<readers).map {
            LogicDocument.text("n\($0)", value: LogicDocument.literal("reader"), visibleWhen: condition)
        })]
        let scene = try show(document, house: LogicHouse.entities(watched: 0, extra: [EntityState(entityId: entity, state: baseState)]))
        let store = scene.store
        let measured = driver( scenario).measure(iterations: 8, interval: 0.5) { tick in
            LogicDriver.apply([update(tick + 1)], to: store)
        }
        finish(measured, expectingRuns: 8 * readers, standingStill: true)
        XCTAssertEqual(measured.skippedEqual, measured.runs, "\(scenario): every one of those runs reached the answer it already had")
    }

    /// Reports the measurement, checks that the scenario did evaluate what it models, and holds it to the budgets.
    private func finish(_ measured: LogicMeasurement, expectingRuns: Int, atMostRuns: Int? = nil, standingStill: Bool = false,
                        file: StaticString = #filePath, line: UInt = #line) {
        report(measured)
        XCTAssertGreaterThanOrEqual(measured.runs, expectingRuns, "\(measured.scenario): fewer evaluations than the model expects", file: file, line: line)
        if let atMostRuns {
            XCTAssertLessThanOrEqual(measured.runs, atMostRuns, "\(measured.scenario): more evaluations than the model allows", file: file, line: line)
        }
        let key = measured.scenario
        let assertBudgets = {
            XCTAssertLessThanOrEqual(measured.p95Ms, 8, "\(key) \(measured.family): p95 run-loop turn over 8 ms", file: file, line: line)
            XCTAssertEqual(measured.over16, 0, "\(key) \(measured.family): a turn over 16 ms (worst \(measured.worstMs) ms)", file: file, line: line)
            if standingStill {
                XCTAssertLessThanOrEqual(measured.updateWorkMs, 25, "\(key) \(measured.family): update work over 25 ms in 8 s", file: file, line: line)
            }
        }
        let outside = measured.p95Ms > 8 || measured.over16 > 0 || (standingStill && measured.updateWorkMs > 25)
        if Self.knownBreaches[key] != nil, !outside {
            Self.note("UNDER BUDGET on \(measured.family): knownBreaches[\"\(key)\"] is a prune candidate if every family stays inside on two runs (p95 \(measured.p95Ms) ms, worst \(measured.worstMs) ms)")
        }
        if let reason = Self.knownBreaches[key] {
            // A listed breach has a ceiling, so a regression still fails: p95 at most 10 ms and no turn over 20 ms on every family.
            XCTAssertLessThanOrEqual(measured.p95Ms, Self.breachCeilingP95Ms, "\(key) \(measured.family): over the ceiling of a known breach (p95)", file: file, line: line)
            XCTAssertLessThanOrEqual(measured.worstMs, Self.breachCeilingTurnMs, "\(key) \(measured.family): a turn over the ceiling of a known breach (\(measured.worstMs) ms)", file: file, line: line)
            let options = XCTExpectedFailure.Options()
            options.isStrict = false
            XCTExpectFailure("\(key): \(reason)", options: options, failingBlock: assertBudgets)
        } else {
            assertBudgets()
        }
    }

    private static var wroteHeader = false

    private func report(_ measured: LogicMeasurement) {
        var text = ""
        if !Self.wroteHeader { text += LogicMeasurement.header + "\n"; Self.wroteHeader = true }
        text += measured.row + "\n"
        if !measured.turnTrace.isEmpty { text += "LOGICPERF_TURNS\t\(measured.family.rawValue)\t\(measured.scenario)\t\(measured.turnTrace)\n" }
        let add = XCTAttachment(string: measured.row)
        add.name = measured.scenario
        add.lifetime = .keepAlways
        self.add(add)
        Self.append(text)
    }

    /// Prints a line and adds it to the rows file, so a fix to a listed breach or a loaded Mac is seen in the numbers.
    private static func note(_ line: String) { append("LOGICPERF_NOTE\t\(line)\n") }

    private static func append(_ text: String) {
        print(text, terminator: "")
        guard let path = ProcessInfo.processInfo.environment["FENTON_LOGICPERF_FILE"], let data = text.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}

// MARK: - A count too large for one published expression

/// A 32-entry count read from ten places, written as `math add` over 32 `choose` (scenarios d1 and d2) or as the one `count` operand (d3 and d4).
/// A published expression holds 64 operands and the expanded count needs 129, so it is built here as an operand tree, and each place evaluates it
/// in an observation the way a node does.
@MainActor
final class LargeCount {
    let scene: LogicScene
    private let bag = UKObservationBag()
    private var labels: [UILabel] = []

    /// How the count is written: `math add` over `choose` (a published expression holds 64 operands, so only a tree built here can), or the one
    /// `count` operand a published document uses (`sh.count@1`).
    enum Operand { case expanded, count }

    init(sites: Int, entries: Int = 32, operand style: Operand = .expanded) throws {
        var document = LogicDocument()
        document.sources = (0..<entries).map { ("w\($0)", LogicHouse.watched($0)) }
        document.tabs = [.init(id: "home", nodes: [LogicDocument.text("n", value: LogicDocument.literal("count"))])]
        scene = try LogicScene(document: document, house: LogicHouse.entities(watched: entries))
        func entry(_ index: Int) -> ServerUIOperand {
            .choose(cases: [.init(when: .state(sourceId: "w\(index)", path: ["state"], values: ["on"]), then: .literal(.number(1)))],
                    otherwise: .literal(.number(0)))
        }
        let groups = stride(from: 0, to: entries, by: 8).map { start in
            ServerUIOperand.math(.add, (start..<min(start + 8, entries)).map(entry))
        }
        let operand = style == .count
            ? ServerUIOperand.count((0..<entries).map { .init(test: .state(sourceId: "w\($0)", path: ["state"], values: ["on"]), personEntityIds: nil) })
            : ServerUIOperand.math(.add, groups)
        bag.evaluatesAuthoredLogic = true
        bag.logicTally = scene.renderer.bindings.logicTally
        let renderer = scene.renderer
        labels = (0..<sites).map { _ in UILabel() }
        for label in labels {
            bag.observe { [weak label, weak renderer] in
                guard let label, let renderer else { return }
                let text: String
                // The path a text expression takes in the app (`UKServerUIBindings.string`): identical copies share one evaluation.
                if case .ready(let value) = renderer.bindings.string(.expression(operand, fallback: nil)) { text = value } else { text = "?" }
                if label.text == text { LogicCost.skippedEqual() } else { label.text = text }
            }
        }
    }

    /// What each place shows.
    func shown() -> [String] { labels.map { $0.text ?? "" } }
}
