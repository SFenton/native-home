import Foundation
@testable import HassCore
import Observation
import Testing

// MARK: - Fixtures

/// Follows `value` the way a view's observation does: counts each wake-up and re-arms.
@MainActor
private final class Watcher {
    private(set) var wakes = 0
    private(set) var lastSeen: Int?

    private let read: @MainActor () -> Int

    init(_ read: @escaping @MainActor () -> Int) {
        self.read = read
        arm()
    }

    private func arm() {
        withObservationTracking { lastSeen = read() } onChange: { [weak self] in
            // One run-loop turn later, like `UKObservation`.
            Task { @MainActor [weak self] in
                RunLoop.main.perform { MainActor.assumeIsolated { self?.wakes += 1; self?.arm() } }
            }
        }
    }
}

/// Lets the run loop and the main actor drain what the last change scheduled.
@MainActor
private func settle() async { try? await Task.sleep(for: .milliseconds(80)) }

// MARK: - DerivedValue

@MainActor
struct DerivedValueTests {
    private func store(_ states: [String: String] = [:]) -> EntityStore {
        let store = EntityStore()
        store.replaceAll(states.map { EntityState(entityId: $0.key, state: $0.value) })
        return store
    }

    private func set(_ store: EntityStore, _ id: String, _ state: String) { store.apply([EntityState(entityId: id, state: state)]) }

    /// Counts the entities in `ids` that are `on`.
    private func count(_ ids: [String], in store: EntityStore) -> @MainActor () -> Int {
        { ids.filter { store.entity($0).state?.state == "on" }.count }
    }

    @Test func runsOnceAndAnswersWithoutRunningAgain() {
        let store = store(["light.demo_a": "on", "light.demo_b": "off"])
        let derived = DerivedValue(count(["light.demo_a", "light.demo_b"], in: store))
        #expect(derived.evaluations == 1)
        for _ in 0..<20 { #expect(derived.current == 1) }
        #expect(derived.evaluations == 1, "reading is free")
    }

    @Test func anEntityNobodyReadsRunsNothing() async {
        let store = store(["light.demo_a": "on", "light.demo_z": "off"])
        let derived = DerivedValue(count(["light.demo_a"], in: store))
        set(store, "light.demo_z", "on")
        await settle()
        #expect(derived.evaluations == 1)
    }

    @Test func aChangedInputIsSeenAtOnce() {
        let store = store(["light.demo_a": "off"])
        let derived = DerivedValue(count(["light.demo_a"], in: store))
        set(store, "light.demo_a", "on")
        #expect(derived.current == 1, "a reader awake in the same turn never sees the old answer")
        #expect(derived.evaluations == 2)
    }

    @Test func aBurstIsOneRun() async {
        let ids = (0..<50).map { "light.demo_\($0)" }
        let store = store(Dictionary(uniqueKeysWithValues: ids.map { ($0, "off") }))
        let derived = DerivedValue(count(ids, in: store))
        store.apply(ids.map { EntityState(entityId: $0, state: "on") })
        await settle()
        #expect(derived.evaluations == 2, "one run for fifty changes")
        #expect(derived.current == 50)
        #expect(derived.evaluations == 2, "and the scheduled run found nothing left to do")
    }

    @Test func aReaderWakesWhenTheResultChanges() async {
        let store = store(["light.demo_a": "off", "light.demo_b": "off"])
        let derived = DerivedValue(count(["light.demo_a", "light.demo_b"], in: store))
        let watcher = Watcher { derived.current }
        set(store, "light.demo_a", "on")
        await settle()
        #expect(watcher.wakes == 1)
        #expect(watcher.lastSeen == 1)
    }

    @Test func anInputThatLeavesTheResultEqualWakesNoOne() async {
        let store = store(["light.demo_a": "on", "light.demo_b": "off"])
        let derived = DerivedValue(count(["light.demo_a", "light.demo_b"], in: store))
        let watcher = Watcher { derived.current }
        // One goes off while the other comes on: the sum is still 1.
        store.apply([EntityState(entityId: "light.demo_a", state: "off"), EntityState(entityId: "light.demo_b", state: "on")])
        await settle()
        #expect(derived.evaluations == 2, "it ran")
        #expect(watcher.wakes == 0, "and no reader heard of it")
    }

    @Test func tenReadersShareOneRun() async {
        let ids = (0..<32).map { "light.demo_\($0)" }
        let store = store(Dictionary(uniqueKeysWithValues: ids.map { ($0, "off") }))
        let derived = DerivedValue(count(ids, in: store))
        let watchers = (0..<10).map { _ in Watcher { derived.current } }
        set(store, "light.demo_3", "on")
        await settle()
        #expect(derived.evaluations == 2)
        #expect(watchers.map(\.wakes) == Array(repeating: 1, count: 10))
        #expect(watchers.allSatisfy { $0.lastSeen == 1 })
    }

    @Test func aBranchThatFlipsFollowsTheNewInputs() async {
        let store = store(["light.demo_switch": "off", "light.demo_a": "on", "light.demo_b": "on"])
        let derived = DerivedValue<Int> {
            store.entity("light.demo_switch").state?.state == "on" ? (store.entity("light.demo_b").state?.state == "on" ? 2 : 3)
                                                                   : (store.entity("light.demo_a").state?.state == "on" ? 0 : 1)
        }
        #expect(derived.current == 0)
        set(store, "light.demo_b", "off")
        await settle()
        #expect(derived.evaluations == 1, "the other branch is not followed")
        set(store, "light.demo_switch", "on")
        #expect(derived.current == 3)
        let runs = derived.evaluations
        set(store, "light.demo_a", "off")
        await settle()
        #expect(derived.evaluations == runs, "the branch left behind is no longer followed")
        set(store, "light.demo_b", "on")
        #expect(derived.current == 2)
    }

    @Test func aCancelledValueStopsFollowing() async {
        let store = store(["light.demo_a": "off"])
        let derived = DerivedValue(count(["light.demo_a"], in: store))
        derived.cancel()
        set(store, "light.demo_a", "on")
        await settle()
        #expect(derived.current == 0)
        #expect(derived.evaluations == 1)
    }

    @Test func aValueNobodyHoldsStopsRunning() async {
        let store = store(["light.demo_a": "off"])
        var runs = 0
        var derived: DerivedValue<Int>? = DerivedValue { runs += 1; return store.entity("light.demo_a").state?.state == "on" ? 1 : 0 }
        #expect(derived?.current == 0)
        derived = nil
        set(store, "light.demo_a", "on")
        await settle()
        #expect(runs == 1)
    }
}

// MARK: - DerivedValues

@MainActor
struct DerivedValuesTests {
    @Test func theSameKeyIsTheSameValueAndRunsOnce() {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "light.demo_a", state: "on")])
        let values = DerivedValues<String, Int>()
        var runs = 0
        let read: @MainActor () -> Int = { runs += 1; return store.entity("light.demo_a").state?.state == "on" ? 1 : 0 }
        let first = values.value(for: "count", read: read)
        let second = values.value(for: "count", read: read)
        #expect(first === second)
        #expect(runs == 1)
        #expect(values.value(for: "other", read: read) !== first)
    }

    @Test func anEntryEndsWithItsLastReader() {
        let values = DerivedValues<Int, Int>()
        var held: [DerivedValue<Int>] = (0..<5).map { key in values.value(for: key) { key } }
        #expect(values.liveCount == 5)
        held.removeLast(2)
        #expect(values.liveCount == 3)
        values.sweep()
        #expect(values.liveCount == 3)
    }

    @Test func aSweepRunsOnItsOwnWhileKeysKeepComing() {
        let values = DerivedValues<Int, Int>()
        for key in 0..<500 { _ = values.value(for: key) { key } }
        #expect(values.liveCount == 0, "nothing holds them")
    }

    @Test func identicalAuthoredOperandsShareAKey() {
        let sum = ServerUIOperand.math(.add, [.read(sourceId: "a", path: ["state"], as: .number), .literal(.number(1))])
        let same = ServerUIOperand.math(.add, [.read(sourceId: "a", path: ["state"], as: .number), .literal(.number(1))])
        let other = ServerUIOperand.math(.add, [.read(sourceId: "b", path: ["state"], as: .number), .literal(.number(1))])
        #expect(sum.hashValue == same.hashValue && sum == same)
        #expect(sum != other)
        #expect(Set([sum, same, other]).count == 2)
    }

    @Test func onlyScopeFreeOperandsAreShareable() {
        let read = ServerUIOperand.read(sourceId: "a", path: ["state"], as: .string)
        #expect(read.isShareable)
        #expect(ServerUIOperand.viewer(.userId).isShareable)
        #expect(!ServerUIOperand.item(path: ["name"]).isShareable)
        #expect(!ServerUIOperand.index.isShareable)
        #expect(!ServerUIOperand.param(name: "x").isShareable)
        #expect(!ServerUIOperand.control.isShareable)
        #expect(!ServerUIOperand.clock(.now).isShareable, "a clock read starts and stops its tick with its node")
        #expect(!ServerUIOperand.math(.add, [read, .item(path: ["n"])]).isShareable, "one scoped child spoils the tree")
        #expect(!ServerUIOperand.format(pattern: "{a}", args: ["a": .index], formats: [:]).isShareable)
        let choose = ServerUIOperand.choose(cases: [.init(when: .compare(.eq, left: .item(path: ["k"]), right: .literal(.string("x"))), then: read)],
                                            otherwise: read)
        #expect(!choose.isShareable, "the scope can hide in a case's condition")
        let plain = ServerUIOperand.choose(cases: [.init(when: .state(sourceId: "a", path: ["state"], values: ["on"]), then: read)], otherwise: read)
        #expect(plain.isShareable)
    }
}

// MARK: - SharedLogic

@MainActor
struct SharedLogicTests {
    private func store() -> EntityStore {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "light.demo_a", state: "on")])
        return store
    }

    @Test func oneReaderEvaluatesInPlaceAndMakesNoDerivedValue() {
        let store = store()
        let logic = SharedLogic<String, Int>()
        let reader = DerivedReaders()
        var runs = 0
        let read: @MainActor () -> Int = { runs += 1; return store.entity("light.demo_a").state?.state == "on" ? 1 : 0 }
        for _ in 0..<3 { reader.run { #expect(logic.value(for: "k", read: read) == 1) } }
        #expect(runs == 3, "the same observation re-running evaluates where it is")
        #expect(logic.sharedCount == 0)
    }

    @Test func aSecondReaderMakesItOneSharedValue() {
        let store = store()
        let logic = SharedLogic<String, Int>()
        let first = DerivedReaders(), second = DerivedReaders(), third = DerivedReaders()
        var runs = 0
        let read: @MainActor () -> Int = { runs += 1; return store.entity("light.demo_a").state?.state == "on" ? 1 : 0 }
        first.run { _ = logic.value(for: "k", read: read) }
        #expect(runs == 1)
        second.run { #expect(logic.value(for: "k", read: read) == 1) }
        #expect(logic.sharedCount == 1)
        #expect(runs == 2, "the promotion runs the logic once, inside the derived value")
        third.run { #expect(logic.value(for: "k", read: read) == 1) }
        first.run { #expect(logic.value(for: "k", read: read) == 1) }
        #expect(runs == 2, "readers after that read the shared value")
        #expect(second.count == 1 && third.count == 1 && first.count == 1, "each holds the value it read")
    }

    @Test func aReadOutsideAnyObservationIsPlain() {
        let logic = SharedLogic<String, Int>()
        var runs = 0
        for _ in 0..<3 { #expect(logic.value(for: "k") { runs += 1; return 7 } == 7) }
        #expect(runs == 3)
        #expect(logic.sharedCount == 0)
    }

    @Test func theValueEndsWhenItsReadersLetGo() {
        let logic = SharedLogic<String, Int>()
        var first: DerivedReaders? = DerivedReaders(), second: DerivedReaders? = DerivedReaders()
        first?.run { _ = logic.value(for: "k") { 1 } }
        second?.run { _ = logic.value(for: "k") { 1 } }
        #expect(logic.sharedCount == 1)
        second = nil
        #expect(logic.sharedCount == 0, "nothing holds it: the shared value ended")
        first = nil
    }
}
