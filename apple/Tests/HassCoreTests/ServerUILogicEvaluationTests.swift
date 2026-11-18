import Foundation
@testable import HassCore
import Observation
import Testing

// MARK: - A watch over an authored expression

/// Re-runs one evaluation when something it read changes, the way the app's observation does for a node: it runs now, records what the
/// run read, and runs again after a change to any of it. A run that comes out equal to the last answer is counted apart and notifies nobody.
@MainActor
private final class Watch {
    private(set) var runs = 0
    private(set) var notified = 0
    private(set) var skippedEqual = 0
    private(set) var answer: ServerUIReadResult?
    private let evaluate: @MainActor () -> ServerUIReadResult
    private let dirty = Flag()

    init(_ evaluate: @escaping @MainActor () -> ServerUIReadResult) {
        self.evaluate = evaluate
        run()
    }

    /// Runs again if a change reached the last run's reads.
    func drain() { if dirty.takeRaised() { run() } }

    private func run() {
        runs += 1
        let flag = dirty
        let result = withObservationTracking(evaluate) { flag.raise() }
        if result == answer { skippedEqual += 1 } else { answer = result; notified += 1 }
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    func raise() { lock.lock(); raised = true; lock.unlock() }
    func takeRaised() -> Bool { lock.lock(); defer { lock.unlock() }; let value = raised; raised = false; return value }
}

/// Reads `store.entity(sourceId).state`: a source id is an entity id here, and exactly the entities an evaluation touches are tracked.
private struct StoreReader: ServerUIReading {
    let store: EntityStore
    var viewer: ServerUIViewer?
    var controlValue: JSONValue?
    var clock: ServerUIClock?
    var item: JSONValue?
    var index: Int?
    var isFlow = false
    var locale: Locale?

    func read(sourceId: String, path: [String]) -> ServerUIReadResult {
        MainActor.assumeIsolated {
            guard let state = store.entity(sourceId).state else { return .unavailable }
            return .value(.string(state.state))
        }
    }
    func readRaw(sourceId: String) -> ServerUIReadResult { read(sourceId: sourceId, path: ["state"]) }
    func viewerPersonState() -> ServerUIReadResult { .unavailable }
    func parameter(_ name: String) -> JSONValue? { nil }
    func spend() {}
}

private func isOn(_ id: String) -> ServerUIPredicate { .state(sourceId: id, path: ["state"], values: ["on"]) }
private func text(_ value: String) -> ServerUIOperand { .literal(.string(value)) }
private func read(_ id: String) -> ServerUIOperand { .read(sourceId: id, path: ["state"], as: .string) }

// MARK: - When logic runs

@MainActor
@Suite struct ServerUILogicEvaluationTests {
    private func house(_ states: [String: String]) -> EntityStore {
        let store = EntityStore()
        _ = store.replaceAll(states.map { EntityState(entityId: $0.key, state: $0.value) })
        return store
    }

    @Test func anEntityNoRunReadCostsNoEvaluation() {
        var states = Dictionary(uniqueKeysWithValues: (0..<500).map { ("sensor.demo_lw_\($0)", "1") })
        states["switch.demo_lw_a"] = "off"
        let store = house(states)
        let watch = Watch { ServerUIOperand.choose(cases: [.init(when: isOn("switch.demo_lw_a"), then: text("Open"))], otherwise: text("Closed"))
            .evaluate(StoreReader(store: store)) }
        _ = store.apply((0..<500).map { EntityState(entityId: "sensor.demo_lw_\($0)", state: "2") })
        watch.drain()
        #expect(watch.runs == 1, "500 changed entities that no read touched ran nothing")
        _ = store.apply([EntityState(entityId: "switch.demo_lw_a", state: "on")])
        watch.drain()
        #expect(watch.runs == 2)
        #expect(watch.answer == .value(.string("Open")))
    }

    @Test func aChangeThatLeavesTheAnswerEqualNotifiesNoOne() {
        let store = house(["media_player.demo_lw_tv": "playing"])
        let watch = Watch { ServerUIPredicate.state(sourceId: "media_player.demo_lw_tv", path: ["state"], values: ["playing"]).evaluate(StoreReader(store: store)) == .yes ? .value(.bool(true)) : .value(.bool(false)) }
        #expect(watch.notified == 1)
        // An attribute-only change replaces the entity's whole value, so the run happens; its answer is the same.
        _ = store.apply([EntityState(entityId: "media_player.demo_lw_tv", state: "playing", attributes: ["media_position": .number(5)])])
        watch.drain()
        #expect(watch.runs == 2, "tracking is per entity")
        #expect(watch.skippedEqual == 1, "the equal answer is recorded as skipped")
        #expect(watch.notified == 1, "and nobody was notified")
        _ = store.apply([EntityState(entityId: "media_player.demo_lw_tv", state: "paused")])
        watch.drain()
        #expect(watch.notified == 2)
    }

    @Test func aChooseThatFlipsReadsTheEntitiesOfTheNewBranch() {
        let store = house(["a": "on", "b": "x", "c": "y"])
        let watch = Watch { ServerUIOperand.choose(cases: [.init(when: isOn("a"), then: read("b"))], otherwise: read("c")).evaluate(StoreReader(store: store)) }
        func change(_ id: String, _ state: String) -> Int {
            let before = watch.runs
            _ = store.apply([EntityState(entityId: id, state: state)])
            watch.drain()
            return watch.runs - before
        }
        #expect(change("c", "z") == 0, "c is not read while a is on")
        #expect(change("b", "w") == 1)
        #expect(change("a", "off") == 1, "the flip")
        #expect(change("b", "v") == 0, "b is no longer read")
        #expect(change("c", "u") == 1, "c is: the run re-subscribed")
        #expect(watch.answer == .value(.string("u")))
    }

    @Test func aSumRunsOncePerTurnWhateverNumberOfEntitiesChanged() {
        let ids = (0..<32).map { "switch.demo_lw_\($0)" }
        let store = house(Dictionary(uniqueKeysWithValues: ids.map { ($0, "off") }))
        func entry(_ id: String) -> ServerUIOperand { .choose(cases: [.init(when: isOn(id), then: .literal(.number(1)))], otherwise: .literal(.number(0))) }
        let groups = stride(from: 0, to: 32, by: 8).map { ServerUIOperand.math(.add, ids[$0..<($0 + 8)].map(entry)) }
        let count = ServerUIOperand.math(.add, groups)
        let watch = Watch { count.evaluate(StoreReader(store: store)) }
        #expect(watch.answer == .value(.number(0)))
        _ = store.apply(ids.map { EntityState(entityId: $0, state: "on") })
        watch.drain()
        #expect(watch.runs == 2, "32 changes in one delivery are one re-run")
        #expect(watch.answer == .value(.number(32)))
    }

    @Test func aWholeHouseReplayRunsOnlyTheEvaluationsThatReadIt() {
        var states = Dictionary(uniqueKeysWithValues: (0..<4_700).map { ("sensor.demo_lw_\($0)", "0") })
        states["switch.demo_lw_a"] = "off"
        let store = house(states)
        let watch = Watch { ServerUIOperand.choose(cases: [.init(when: isOn("switch.demo_lw_a"), then: text("1"))], otherwise: text("0")).evaluate(StoreReader(store: store)) }
        _ = store.apply((0..<4_700).map { EntityState(entityId: "sensor.demo_lw_\($0)", state: "1") })
        watch.drain()
        #expect(watch.runs == 1, "a 4,700-entity replay leaves the evaluation that reads none of it alone")
    }
}
