import Foundation
import HassCore
import HassTelemetry
import UIKit
import XCTest
@testable import HassUI

// MARK: - Families

/// The device family a hosted run executes on, read from the simulator's name.
///
/// The hosted run happens once per family (the hosted leg of the test runner, `--only iphone|duo|ipad`). The family decides the window the
/// page is laid out in and labels the rows the suite reports.
enum LogicFamily: String, CaseIterable {
    case iphone, duo, ipad

    /// The family of the simulator this process runs in.
    static var current: LogicFamily {
        let name = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? ""
        if name.localizedCaseInsensitiveContains("Duo") { return .duo }
        return UIDevice.current.userInterfaceIdiom == .pad ? .ipad : .iphone
    }

    /// The window a page is hosted in, clamped to the scene: the phone, the Duo's inner display and the iPad's regular width.
    @MainActor
    var windowSize: CGSize {
        switch self {
        case .iphone: HostedPage.inScene(CGSize(width: 393, height: 852))
        case .duo: HostedPage.inScene(CGSize(width: 540, height: 720))
        case .ipad: HostedPage.inScene(CGSize(width: 820, height: 1000))
        }
    }
}

// MARK: - The invented house

/// A house of invented entities (`lw_` ids, no real data): thousands of bulk entities nobody reads, a small set the page watches, and a few people.
enum LogicHouse {
    /// The size of the owner's house when last counted (4,723 entities, rounded).
    static let size = 4_700
    /// How many people the house has.
    static let people = 6
    private static let bulkDomains = ["sensor", "binary_sensor", "light", "switch", "cover", "climate", "media_player"]

    /// The i-th watched entity: a `switch` the scenarios read for `state`.
    static func watched(_ index: Int) -> String { "switch.demo_lw_w\(String(format: "%03d", index))" }

    /// The i-th bulk entity, which no scenario's page reads.
    static func bulk(_ index: Int) -> String { "\(bulkDomains[index % bulkDomains.count]).demo_lw_b\(String(format: "%04d", index))" }

    /// The i-th person.
    static func person(_ index: Int) -> String { "person.demo_lw_p\(index)" }

    /// The state an entity has in `generation`: it flips on every generation, so each generation is a change.
    static func state(_ index: Int, generation: Int) -> String { (index + generation) % 2 == 0 ? "on" : "off" }

    /// The whole house: `watched` watched entities, the people, `extra`, and bulk entities up to ``size``, all in `generation`.
    static func entities(watched: Int, generation: Int = 0, extra: [EntityState] = []) -> [EntityState] {
        var states = (0..<watched).map { EntityState(entityId: Self.watched($0), state: state($0, generation: generation)) }
        states += (0..<people).map { EntityState(entityId: person($0), state: "home", attributes: ["user_id": .string("lw-user-\($0)")]) }
        states += extra
        let bulkCount = max(0, size - states.count)
        states += bulkChanges(count: bulkCount, generation: generation)
        return states
    }

    /// `count` bulk entities in `generation`.
    static func bulkChanges(count: Int, generation: Int) -> [EntityState] {
        (0..<count).map { EntityState(entityId: bulk($0), state: state($0, generation: generation),
                                      attributes: ["friendly_name": .string("Bulk \($0)"), "unit": .string("W")]) }
    }
}

// MARK: - The authored document

/// Builds a publication whose pages carry authored logic, from the schema-2 fixture the other hosted renderer tests use.
struct LogicDocument {
    /// One tab: its page's nodes and, optionally, an authored badge.
    struct Tab {
        var id: String
        var nodes: [[String: Any]]
        var badge: [String: Any]?
    }

    /// The `ha-entity` sources the operands name: source id to entity id.
    var sources: [(id: String, entity: String)] = []
    /// Model sources added as they are (the `app-state@1` clock).
    var models: [[String: Any]] = []
    var tabs: [Tab] = []

    // MARK: Operands

    static func literal(_ value: Any) -> [String: Any] { ["type": "literal", "value": value] }

    static func read(_ source: String, path: [String] = ["state"], as kind: String = "string") -> [String: Any] {
        ["type": "read", "from": ["type": "source", "sourceId": source, "path": path], "as": kind, "missing": "unavailable"]
    }

    /// `state` of `source` is one of `values`.
    static func isState(_ source: String, in values: [String] = ["on"]) -> [String: Any] {
        ["type": "state", "sourceId": source, "path": ["state"], "in": values]
    }

    /// `pattern` with each `{name}` filled from `args`.
    static func format(_ pattern: String, _ args: [String: [String: Any]]) -> [String: Any] {
        ["type": "format", "pattern": pattern, "args": args]
    }

    /// The `app-state@1` clock model source, id `clock`.
    static var clockSource: [String: Any] { ["id": "clock", "kind": "model", "model": "app-state@1", "inputs": ["topic": "clock"]] }

    static func choose(_ cases: [(when: [String: Any], then: [String: Any])], otherwise: [String: Any]) -> [String: Any] {
        ["type": "choose", "cases": cases.map { ["when": $0.when, "then": $0.then] }, "otherwise": otherwise]
    }

    // MARK: Nodes

    /// A text node showing `value`, shown only while `visibleWhen` holds.
    static func text(_ id: String, value: [String: Any], visibleWhen: [String: Any]? = nil) -> [String: Any] {
        var node: [String: Any] = ["id": id, "title": id, "type": "text", "layout": ["span": 1],
                                   "props": ["value": value["type"] as? String == "literal" ? value : ["type": "expr", "value": value], "style": "body", "unavailableText": "None"]]
        if let visibleWhen { node["visibleWhen"] = visibleWhen }
        return node
    }

    /// A text node that is always shown but whose words follow `source`: "Open" while it is on.
    static func stateText(_ id: String, source: String) -> [String: Any] {
        text(id, value: choose([(isState(source), literal("Open"))], otherwise: literal("Closed")))
    }

    /// A node shown only while `source` is on.
    static func shownWhenOn(_ id: String, source: String) -> [String: Any] {
        text(id, value: literal(id), visibleWhen: isState(source))
    }

    // MARK: Publication

    /// The capability ids, beyond the fixture's own, that the document uses and no others: the manifest has to match the document exactly.
    /// `LogicDocumentCapabilityTests` fails when this list and what the compiler requires drift apart.
    var requiredCapabilities: [String] {
        let nodes = tabs.flatMap(\.nodes)
        func contains(_ type: String, in value: Any) -> Bool {
            if let object = value as? [String: Any] { return object["type"] as? String == type || object.values.contains { contains(type, in: $0) } }
            if let array = value as? [Any] { return array.contains { contains(type, in: $0) } }
            return false
        }
        var ids: [String] = []
        // A literal value is plain data; operands come in with the first expression (read, format, choose or math).
        func computed(_ node: [String: Any]) -> Bool {
            ((node["props"] as? [String: Any])?["value"] as? [String: Any])?["type"] as? String == "expr"
        }
        // A predicate that compares to a literal (`numeric` above or below) is an operand too.
        func compares(_ node: [String: Any]) -> Bool { (node["visibleWhen"]).map { contains("literal", in: $0) || contains("read", in: $0) } ?? false }
        if nodes.contains(where: computed) || nodes.contains(where: compares) || tabs.contains(where: { $0.badge != nil }) { ids.append("sh.operands@1") }
        // An expression value is a rule: it brings in the rules capability with the operands.
        if nodes.contains(where: computed) || tabs.contains(where: { $0.badge.map { contains("choose", in: $0) } ?? false }) { ids.append("sh.rules@1") }
        if nodes.contains(where: { $0["visibleWhen"] != nil }) { ids.append("sh.visible-when@1") }
        if tabs.contains(where: { $0.badge != nil }) { ids.append("sh.badges@1") }
        if !models.isEmpty { ids.append("sh.app-state@1") }
        return ids
    }

    /// The decoded publication.
    @MainActor
    func publication(capabilities: [String]? = nil) throws -> ServerUICompositionPublication {
        var root = try Self.object(ServerUIRendererFixture.json())
        var document = try XCTUnwrap(root["document"] as? [String: Any])
        var pages = try XCTUnwrap(document["pages"] as? [[String: Any]])
        let template = pages[0]
        var navigation = try XCTUnwrap(document["navigation"] as? [String: Any])
        let icon = ["type": "sf-symbol", "name": "square.grid.2x2", "rendering": "canonical", "unavailable": "reject"] as [String: Any]
        var newPages: [[String: Any]] = []
        var newTabs: [[String: Any]] = []
        for tab in tabs {
            var page = template
            page["id"] = "page-\(tab.id)"
            page["title"] = tab.id
            page["components"] = tab.nodes
            newPages.append(page)
            var entry: [String: Any] = ["id": tab.id, "label": tab.id, "icon": icon, "pageId": "page-\(tab.id)", "arguments": [String: Any]()]
            if let badge = tab.badge { entry["badge"] = ["type": "value", "value": badge] }
            newTabs.append(entry)
        }
        // The fixture's own pages stay (no tab opens them), so its manifest still matches what the document uses.
        pages = newPages + pages
        navigation["tabs"] = newTabs
        navigation["initialTabId"] = tabs[0].id
        navigation["initialPageId"] = "page-\(tabs[0].id)"
        document["pages"] = pages
        document["navigation"] = navigation
        var dataSources = try XCTUnwrap(document["dataSources"] as? [[String: Any]])
        dataSources += sources.map { ["id": $0.id, "kind": "ha-entity", "entityId": ["type": "literal", "value": $0.entity]] }
        dataSources += models
        document["dataSources"] = dataSources
        root["document"] = document
        root["capabilities"] = Array(Set((root["capabilities"] as? [String] ?? []) + (capabilities ?? requiredCapabilities))).sorted()
        return try ServerUICompositionPublication.decode(JSONSerialization.data(withJSONObject: root))
    }

    @MainActor
    private static func object(_ json: JSONValue) throws -> [String: Any] {
        let data = try JSONEncoder().encode(json)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

// MARK: - The hosted renderer

/// A renderer over a house, hosted in a window of the family's size, with a viewer who matches no person (the worst case for a `viewer` read).
@MainActor
final class LogicScene {
    let store = EntityStore()
    let renderer: UKServerUIRenderer
    let window: UIWindow

    /// Builds and shows the renderer, then lets its first run settle.
    init(document: LogicDocument, house: [EntityState], family: LogicFamily = .current, viewerKnown: Bool = true) throws {
        _ = store.replaceAll(house)
        renderer = try UKServerUIRenderer(publication: document.publication(), context: UKContext(store: store, caller: HostedCaller()),
                                          backdrop: ServerUIRendererFixture.backdrop())
        if viewerKnown { renderer.viewerSource.set(HassUser(id: "lw-stranger", name: nil, isOwner: false, isAdmin: false)) }
        window = HostedPage.show(renderer, size: family.windowSize)
        HostedPage.wait(0.2)
    }

    /// Takes the window down.
    func close() { window.isHidden = true }

    /// The page of a tab, loaded (so its observations run) whether or not the tab is the one on screen.
    func page(_ tab: String) throws -> UKServerUIPage {
        let page = try XCTUnwrap(renderer.stacks[.tab(tab)]?.viewControllers.first as? UKServerUIPage)
        page.loadViewIfNeeded()
        return page
    }

    /// The view of node `id` on `tab`.
    func view(_ id: String, on tab: String) throws -> UIView {
        try XCTUnwrap(page(tab).nodes[id]?.view, "node \(id)")
    }
}

// MARK: - The measurement driver

/// What one scenario cost the main thread and how many evaluations it caused.
struct LogicMeasurement {
    var scenario: String
    var family: LogicFamily
    var iterations = 0
    /// The 95th percentile run-loop turn and the longest, in milliseconds (`MainThreadCostMeter`).
    var p95Ms = 0.0
    var worstMs = 0.0
    var turns = 0
    var over8 = 0
    var over16 = 0
    /// `logic.runs`, `logic.runUs` and `logic.skippedEqual` over the measured window.
    var runs = 0
    var runUs = 0
    var skippedEqual = 0
    /// The main thread's CPU time inside the store's `apply` calls the scenario made, in microseconds.
    var applyUs = 0
    var seconds = 0.0
    /// The 1-minute load average when the suite started; a baseline wants it under 40.
    var load1 = 0.0

    /// Logic and apply time together, in milliseconds: the "update work" a standing-still page is budgeted.
    var updateWorkMs: Double { Double(runUs + applyUs) / 1000 }

    /// One tab-separated row; ``header`` names the columns.
    var row: String {
        ["LOGICPERF", family.rawValue, scenario, "\(iterations)", String(format: "%.2f", p95Ms), String(format: "%.2f", worstMs), "\(turns)",
         "\(over8)", "\(over16)", "\(runs)", "\(runUs)", "\(skippedEqual)", "\(applyUs)", String(format: "%.1f", seconds), String(format: "%.1f", load1)].joined(separator: "\t")
    }

    static let header = "LOGICPERF\tfamily\tscenario\titerations\tp95_ms\tworst_ms\tturns\tover8\tover16\truns\trunUs\tskippedEqual\tapplyUs\tseconds\tload1"
}

/// Drives a scenario the way a delivery does: each step runs in its own main-queue turn (the store applying a batch), then the run loop drains
/// the observations it scheduled until a pass runs nothing more.
@MainActor
struct LogicDriver {
    var scenario: String
    var family = LogicFamily.current
    /// How long one run-loop pass waits; a pass with nothing to do is one idle turn.
    var pass: TimeInterval = 0.1

    /// Runs `step` `iterations` times, each followed by a drain, and reports the measured window. `step` returns the CPU microseconds its
    /// own store writes took.
    func measure(iterations: Int, interval: TimeInterval = 0, _ step: @escaping @MainActor (Int) -> Int) -> LogicMeasurement {
        let counters = Telemetry.log.counters
        let meter = MainThreadCostMeter()
        var result = LogicMeasurement(scenario: scenario, family: family, iterations: iterations)
        let started = ContinuousClock.now
        meter.begin()
        for iteration in 0..<iterations {
            let applied = Applied()
            DispatchQueue.main.async { MainActor.assumeIsolated { applied.microseconds = step(iteration) } }
            drain()
            result.applyUs += applied.microseconds
            if interval > 0 { RunLoop.main.run(until: Date().addingTimeInterval(interval)) }
        }
        let report = meter.finish()
        let after = Telemetry.log.counters
        func delta(_ key: String) -> Int { (after[key] ?? 0) - (counters[key] ?? 0) }
        result.p95Ms = report.p95TurnMs
        result.worstMs = report.worstTurnMs
        result.turns = report.turns
        result.over8 = report.turnsOver8
        result.over16 = report.turnsOver16
        result.runs = delta(LogicCost.runsCounter)
        result.runUs = delta(LogicCost.runMicrosecondsCounter)
        result.skippedEqual = delta(LogicCost.skippedEqualCounter)
        let elapsed = (ContinuousClock.now - started).components
        result.load1 = Self.load1
        result.seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        return result
    }

    /// The 1-minute load average now.
    static var load1: Double {
        var loads = [Double](repeating: 0, count: 3)
        return getloadavg(&loads, 3) > 0 ? loads[0] : 0
    }

    private final class Applied { var microseconds = 0 }

    /// Runs the main run loop until two passes in a row ran no authored logic.
    func drain() {
        var quiet = 0
        var last = Telemetry.log.counters[LogicCost.runsCounter] ?? 0
        var passes = 0
        while quiet < 2, passes < 60 {
            RunLoop.main.run(until: Date().addingTimeInterval(pass))
            let now = Telemetry.log.counters[LogicCost.runsCounter] ?? 0
            quiet = now == last ? quiet + 1 : 0
            last = now
            passes += 1
        }
    }

    /// Applies `changes` to `store` and returns the main thread's CPU microseconds that took.
    static func apply(_ changes: [EntityState], to store: EntityStore) -> Int {
        let start = ProcessCPU.currentThreadSeconds()
        _ = store.apply(changes)
        return Int((ProcessCPU.currentThreadSeconds() - start) * 1_000_000)
    }
}
