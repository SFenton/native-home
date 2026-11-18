import Foundation
@testable import HassCore
import HassTelemetry
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

    @Test func aChangedInputIsSettledInTheNextHop() async {
        let store = store(["light.demo_a": "off"])
        let derived = DerivedValue(count(["light.demo_a"], in: store))
        set(store, "light.demo_a", "on")
        #expect(derived.current == 0, "reading never runs the logic: a reader would follow its inputs")
        #expect(derived.evaluations == 1)
        await settle()
        #expect(derived.current == 1)
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

    @Test func aReaderThatMadeTheValueIsWokenByItsOutputOnly() async {
        // The reader makes the value outside its own run (as the app does), reads it, and the inputs change to an equal result again and again.
        let store = store(["light.demo_a": "on", "light.demo_b": "off"])
        let derived = DerivedValue(count(["light.demo_a", "light.demo_b"], in: store))
        let watcher = Watcher { derived.current }
        for round in 0..<6 {
            let aOn = round % 2 == 1
            store.apply([EntityState(entityId: "light.demo_a", state: aOn ? "on" : "off"), EntityState(entityId: "light.demo_b", state: aOn ? "off" : "on")])
            await settle()
        }
        #expect(watcher.wakes == 0, "six input changes with the same sum: the reader follows the output, not the inputs")
        #expect(derived.evaluations == 7)
    }

    @Test func readingNeverMakesTheReaderFollowTheInputs() async {
        // A value that is dirty when a reader reads it: the read must not run the logic inside the reader.
        let store = store(["light.demo_a": "off", "light.demo_b": "off"])
        let derived = DerivedValue(count(["light.demo_a", "light.demo_b"], in: store))
        let watcher = Watcher { derived.current }
        set(store, "light.demo_a", "on")
        _ = derived.current
        await settle()
        let after = watcher.wakes
        for round in 0..<4 {
            store.apply([EntityState(entityId: "light.demo_a", state: round % 2 == 0 ? "off" : "on"),
                         EntityState(entityId: "light.demo_b", state: round % 2 == 0 ? "on" : "off")])
            await settle()
        }
        #expect(watcher.wakes == after, "an equal sum wakes no one, whatever read it while it was dirty")
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
        await settle()
        #expect(derived.current == 3)
        let runs = derived.evaluations
        set(store, "light.demo_a", "off")
        await settle()
        #expect(derived.evaluations == runs, "the branch left behind is no longer followed")
        set(store, "light.demo_b", "on")
        await settle()
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

    @Test func onlyTreesOverSeveralSourcesAreWorthSharing() {
        func read(_ id: String) -> ServerUIOperand { .read(sourceId: id, path: ["state"], as: .number) }
        #expect(!read("a").isWorthSharing)
        #expect(!read("a").hasManyReads)
        let wide = ServerUIOperand.format(pattern: "{n}", args: ["n": .math(.add, [read("a"), read("b"), read("c")])], formats: [:])
        #expect(wide.hasManyReads && wide.isWorthSharing, "the reads can sit anywhere in the tree")
        let predicates = ServerUIOperand.choose(cases: [.init(when: .all([.state(sourceId: "a", path: ["state"], values: ["on"]),
                                                                      .state(sourceId: "b", path: ["state"], values: ["on"])]), then: read("c"))],
                                               otherwise: .literal(.number(0)))
        #expect(predicates.hasManyReads, "a condition's reads count")
        #expect(!ServerUIOperand.choose(cases: [.init(when: .state(sourceId: "a", path: ["state"], values: ["on"]), then: .literal(.string("x")))],
                                        otherwise: .literal(.string("y"))).hasManyReads)
        #expect(!ServerUIOperand.math(.add, [read("a"), read("b")]).isWorthSharing)
        #expect(ServerUIOperand.math(.add, [read("a"), read("b"), read("c")]).isWorthSharing)
        #expect(!ServerUIOperand.math(.add, [read("a"), read("b"), .item(path: ["n"])]).isWorthSharing, "a scoped child spoils it")
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

/// One observation reading a shared key, as a page node does: runs inside its own collector, counts wake-ups and re-arms.
@MainActor
private final class SharedWatcher {
    private let readers = DerivedReaders()
    private let logic: SharedLogic<String, Int>
    private let read: @MainActor () -> Int
    private(set) var wakes = 0

    init(_ logic: SharedLogic<String, Int>, _ read: @escaping @MainActor () -> Int) {
        self.logic = logic
        self.read = read
        arm()
    }

    private func arm() {
        withObservationTracking { readers.run { _ = logic.value(for: "k", read: read) } } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                RunLoop.main.perform { MainActor.assumeIsolated { self?.wakes += 1; self?.arm() } }
            }
        }
    }
}

@MainActor
struct SharedLogicTests {
    private func store() -> EntityStore {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "light.demo_a", state: "on")])
        return store
    }

    @Test func oneReaderEvaluatesInPlaceAndMakesNoDerivedValue() async {
        let store = store()
        let logic = SharedLogic<String, Int>()
        let reader = DerivedReaders()
        var runs = 0
        let read: @MainActor () -> Int = { runs += 1; return store.entity("light.demo_a").state?.state == "on" ? 1 : 0 }
        for _ in 0..<3 { reader.run { #expect(logic.value(for: "k", read: read) == 1) } }
        await settle()
        #expect(runs == 3, "the same observation re-running evaluates where it is")
        #expect(logic.sharedCount == 0)
    }

    @Test func aSecondReaderMakesItOneSharedValueInTheNextHop() async {
        let store = store()
        let logic = SharedLogic<String, Int>()
        let first = DerivedReaders(), second = DerivedReaders(), third = DerivedReaders()
        var runs = 0
        let read: @MainActor () -> Int = { runs += 1; return store.entity("light.demo_a").state?.state == "on" ? 1 : 0 }
        first.run { _ = logic.value(for: "k", read: read) }
        second.run { #expect(logic.value(for: "k", read: read) == 1) }
        #expect(logic.sharedCount == 0, "not made inside the reader's run")
        #expect(runs == 2, "both evaluated in place this once")
        await settle()
        #expect(logic.sharedCount == 1)
        #expect(runs == 3, "the shared value ran once")
        third.run { #expect(logic.value(for: "k", read: read) == 1) }
        first.run { #expect(logic.value(for: "k", read: read) == 1) }
        second.run { #expect(logic.value(for: "k", read: read) == 1) }
        #expect(runs == 3, "readers after that read the shared value")
        #expect(first.count == 1 && second.count == 1 && third.count == 1, "each holds the value it read")
    }

    @Test func aReaderMovedOverIsNotWokenByAnEqualResult() async {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "light.demo_a", state: "on"), EntityState(entityId: "light.demo_b", state: "off"),
                          EntityState(entityId: "light.demo_c", state: "off")])
        let logic = SharedLogic<String, Int>()
        let read: @MainActor () -> Int = {
            ["light.demo_a", "light.demo_b", "light.demo_c"].filter { store.entity($0).state?.state == "on" }.count
        }
        let watchers = (0..<3).map { _ in SharedWatcher(logic, read) }
        await settle()
        // One real change moves every reader over.
        store.apply([EntityState(entityId: "light.demo_c", state: "on")])
        await settle()
        await settle()
        let moved = watchers.map(\.wakes)
        for round in 0..<4 {
            let aOn = round % 2 == 1  // the sum stays 2: c plus one of a and b
            store.apply([EntityState(entityId: "light.demo_a", state: aOn ? "on" : "off"), EntityState(entityId: "light.demo_b", state: aOn ? "off" : "on")])
            await settle()
        }
        #expect(watchers.map(\.wakes) == moved, "an input change with the same sum wakes no reader, the first included")
    }

    @Test func aReadOutsideAnyObservationIsPlain() {
        let logic = SharedLogic<String, Int>()
        var runs = 0
        for _ in 0..<3 { #expect(logic.value(for: "k") { runs += 1; return 7 } == 7) }
        #expect(runs == 3)
        #expect(logic.sharedCount == 0)
    }

    @Test func theValueEndsWhenItsReadersLetGo() async {
        let logic = SharedLogic<String, Int>()
        var first: DerivedReaders? = DerivedReaders(), second: DerivedReaders? = DerivedReaders()
        first?.run { _ = logic.value(for: "k") { 1 } }
        second?.run { _ = logic.value(for: "k") { 1 } }
        await settle()
        second?.run { _ = logic.value(for: "k") { 1 } }
        #expect(logic.sharedCount == 1)
        second = nil
        #expect(logic.sharedCount == 0, "nothing holds it: the shared value ended")
        first = nil
    }

    @Test func keysNotWorthSharingAreForgottenOnASweep() {
        let logic = SharedLogic<Int, Int>()
        let reader = DerivedReaders()
        reader.run { for key in 0..<1000 { _ = logic.value(for: key, eligible: false) { key } } }
        #expect(logic.slotCount < 300, "the memory of what is not worth sharing is bounded")
    }

    // MARK: A closed page's unclaimed value

    @Test func aClosedPagesUnclaimedValueEnds() async {
        let logic = SharedLogic<String, Int>()
        var first: DerivedReaders? = DerivedReaders(), second: DerivedReaders? = DerivedReaders()
        first?.run { _ = logic.value(for: "k") { 1 } }
        second?.run { _ = logic.value(for: "k") { 1 } }
        await settle()
        #expect(logic.unclaimedCount == 1, "made in the hop and held for a reader to take over")
        #expect(logic.sharedCount == 1)
        // Both readers' page closes before either runs again: nothing will ever claim the value.
        first = nil
        second = nil
        #expect(logic.unclaimedCount == 0)
        #expect(logic.sharedCount == 0, "it stopped evaluating with the page, it did not wait for 256 others to pile up")
    }

    @Test func theFirstReadersEndLetsGoOfAValueNobodyClaimed() async {
        let logic = SharedLogic<String, Int>()
        var first: DerivedReaders? = DerivedReaders()
        let second = DerivedReaders()
        first?.run { _ = logic.value(for: "k") { 1 } }
        second.run { _ = logic.value(for: "k") { 1 } }
        await settle()
        first = nil
        #expect(logic.sharedCount == 0, "the reader it was made for has gone")
        // Left alone, the second reader evaluates in place: one reader needs no shared value.
        second.run { #expect(logic.value(for: "k") { 1 } == 1) }
        await settle()
        #expect(logic.sharedCount == 0, "a reader on its own is not given one")
        // A new reader asks again and is served in the hop after, and the second moves over on its next run.
        let third = DerivedReaders()
        third.run { _ = logic.value(for: "k") { 1 } }
        await settle()
        #expect(logic.sharedCount == 1, "two readers are served again")
        second.run { #expect(logic.value(for: "k") { 1 } == 1) }
        #expect(second.count == 1, "and the one that was left takes it on its next run")
        #expect(logic.unclaimedCount == 0, "a reader's read is a claim")
        third.run { #expect(logic.value(for: "k") { 1 } == 1) }
        #expect(third.count == 1)
    }

    @Test func aClaimedValueOutlivesTheReaderItWasMadeFor() async {
        let logic = SharedLogic<String, Int>()
        var first: DerivedReaders? = DerivedReaders()
        let second = DerivedReaders()
        first?.run { _ = logic.value(for: "k") { 1 } }
        second.run { _ = logic.value(for: "k") { 1 } }
        await settle()
        second.run { _ = logic.value(for: "k") { 1 } }
        #expect(logic.unclaimedCount == 0, "claimed")
        first = nil
        #expect(logic.sharedCount == 1, "the one reader still reading it keeps it")
    }

    // MARK: Counted for one owner

    @Test func theSharedValuesRunsAreCountedInTheOwnersTally() async {
        let wasEnabled = Telemetry.isEnabled
        defer { Telemetry.isEnabled = wasEnabled }
        Telemetry.isEnabled = true
        let store = store()
        let mine = LogicCost.Tally(), other = LogicCost.Tally()
        let logic = SharedLogic<String, Int>(tally: mine)
        let first = DerivedReaders(), second = DerivedReaders()
        let read: @MainActor () -> Int = { store.entity("light.demo_a").state?.state == "on" ? 1 : 0 }
        first.run { _ = logic.value(for: "k", read: read) }
        second.run { _ = logic.value(for: "k", read: read) }
        await settle()
        #expect(mine.runs == 1, "the shared value's first run")
        store.apply([EntityState(entityId: "light.demo_a", state: "off")])
        await settle()
        #expect(mine.runs == 2)
        store.apply([EntityState(entityId: "light.demo_a", state: "off", attributes: ["x": .number(1)])])
        await settle()
        #expect(mine.runs == 3 && mine.skippedEqual == 1, "an input that moves and leaves the answer equal is a skipped-equal run")
        #expect(other.runs == 0, "another owner's tally never hears of it")
    }
}
