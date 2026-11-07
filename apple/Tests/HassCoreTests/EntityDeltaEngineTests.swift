import Foundation
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
import HassTestSupport
import Testing

/// ``EntityDeltaEngine`` and the connection's own `subscribe_entities` subscription: each message costs work in proportion to what it
/// changed, and a full resend of unchanged values changes nothing (`.agents/platforms/apple/connection-lifecycle.md`, "Live delivery path").
@Suite(.demoHouse)
struct EntityDeltaEngineTests {
    // MARK: Fixtures

    /// `lc` of the fixtures, in epoch seconds (Home Assistant sends floats).
    private let t0 = 1_700_000_000.5

    private func message(_ fields: [String: Any]) throws -> HACompressedStatesUpdates {
        try HACompressedStatesUpdates(data: .dictionary(fields))
    }

    /// A three-entity house as the first message of a subscription: the full set under `a`.
    private func house() throws -> HACompressedStatesUpdates {
        try message(["a": [
            "light.demo_kitchen_item_1": ["s": "on", "a": ["brightness": 120.0, "friendly_name": "Kitchen"], "c": "ctx1", "lc": t0],
            "sensor.demo_temp": ["s": "21.5", "a": ["unit_of_measurement": "C"], "c": "ctx2", "lc": t0, "lu": t0 + 5],
            "switch.fan": ["s": "off", "a": [:] as [String: Any], "c": "ctx3", "lc": t0],
        ]])
    }

    private func started() throws -> EntityDeltaEngine {
        var engine = EntityDeltaEngine()
        engine.subscriptionStarted()
        _ = engine.apply(try house())
        return engine
    }

    // MARK: Full sets

    @Test func theFirstMessageIsTheWholeHouse() throws {
        var engine = EntityDeltaEngine()
        engine.subscriptionStarted()
        let change = engine.apply(try house())
        #expect(change.isFirst && change.isReplacement)
        #expect(Set(change.upserts.map(\.entityId)) == ["light.demo_kitchen_item_1", "sensor.demo_temp", "switch.fan"])
        #expect(change.removed.isEmpty)
        #expect(engine.entities["light.demo_kitchen_item_1"]?.attributes["brightness"] == .number(120))
        #expect(engine.entities["light.demo_kitchen_item_1"]?.lastChanged == Date(timeIntervalSince1970: t0))
    }

    @Test func aFullResendOfIdenticalValuesChangesNothing() throws {
        var engine = try started()
        // The socket came back: HAKit restarts the subscription and the server sends the whole house again. `sensor.demo_temp` carries a
        // `lu` and the others none, which HAKit turns into `Date()` (the cause of the old path's 4,000 phantom changes).
        engine.subscriptionStarted()
        let change = engine.apply(try house())
        #expect(change.isReplacement)
        #expect(!change.isFirst)
        #expect(change.upserts.isEmpty)
        #expect(change.removed.isEmpty)
    }

    @Test func aResendReportsOnlyWhatDiffersAndWhatIsGone() throws {
        var engine = try started()
        engine.subscriptionStarted()
        let change = engine.apply(try message(["a": [
            "light.demo_kitchen_item_1": ["s": "off", "a": ["brightness": 120.0, "friendly_name": "Kitchen"], "lc": t0 + 60],
            "sensor.demo_temp": ["s": "21.5", "a": ["unit_of_measurement": "C"], "lc": t0],
            "lock.demo_door": ["s": "locked", "a": [:] as [String: Any], "lc": t0],
        ]]))
        #expect(Set(change.upserts.map(\.entityId)) == ["light.demo_kitchen_item_1", "lock.demo_door"])
        // `switch.fan` is not in the new set: it was removed while the socket was down.
        #expect(change.removed == ["switch.fan"])
        #expect(engine.entities["switch.fan"] == nil)
    }

    // MARK: Diffs

    @Test func anAttributeChangeReportsExactlyThatEntity() throws {
        var engine = try started()
        let change = engine.apply(try message(["c": ["light.demo_kitchen_item_1": ["+": ["a": ["brightness": 200.0]]]]]))
        #expect(!change.isReplacement)
        #expect(change.upserts.map(\.entityId) == ["light.demo_kitchen_item_1"])
        let kitchen = engine.entities["light.demo_kitchen_item_1"]
        #expect(kitchen?.attributes["brightness"] == .number(200))
        // Merged by key: the attributes the diff did not mention stay, and so do the state and `lastChanged`.
        #expect(kitchen?.attributes["friendly_name"] == .string("Kitchen"))
        #expect(kitchen?.state == "on")
        #expect(kitchen?.lastChanged == Date(timeIntervalSince1970: t0))
    }

    @Test func aStateChangeTakesTheNewStateAndLastChanged() throws {
        var engine = try started()
        let change = engine.apply(try message(["c": ["switch.fan": ["+": ["s": "on", "lc": t0 + 30, "c": "ctx9"]]]]))
        #expect(change.upserts.map(\.entityId) == ["switch.fan"])
        #expect(engine.entities["switch.fan"]?.state == "on")
        #expect(engine.entities["switch.fan"]?.lastChanged == Date(timeIntervalSince1970: t0 + 30))
    }

    @Test func aDiffThatRestatesTheCurrentValuesChangesNothing() throws {
        var engine = try started()
        let change = engine.apply(try message(["c": [
            "light.demo_kitchen_item_1": ["+": ["a": ["brightness": 120.0], "lu": t0 + 9]],
            "sensor.demo_temp": ["+": ["s": "21.5"]],
        ]]))
        #expect(change.upserts.isEmpty)
    }

    @Test func subtractionsRemoveAttributeKeys() throws {
        var engine = try started()
        let change = engine.apply(try message(["c": ["light.demo_kitchen_item_1": ["-": ["a": ["brightness"]]]]]))
        #expect(change.upserts.map(\.entityId) == ["light.demo_kitchen_item_1"])
        #expect(engine.entities["light.demo_kitchen_item_1"]?.attributes["brightness"] == nil)
        #expect(engine.entities["light.demo_kitchen_item_1"]?.attributes["friendly_name"] == .string("Kitchen"))
    }

    @Test func additionsAndSubtractionsInOneDiffApplyInOrder() throws {
        var engine = try started()
        _ = engine.apply(try message(["c": ["light.demo_kitchen_item_1": ["+": ["a": ["color": "red"]], "-": ["a": ["brightness"]]]]]))
        let attributes = engine.entities["light.demo_kitchen_item_1"]?.attributes
        #expect(attributes?["color"] == .string("red"))
        #expect(attributes?["brightness"] == nil)
    }

    @Test func removalsAndNewEntitiesInTheSameMessage() throws {
        var engine = try started()
        let change = engine.apply(try message([
            "a": ["cover.demo_garage": ["s": "closed", "a": [:] as [String: Any], "lc": t0 + 1]],
            "r": ["switch.fan"],
        ]))
        #expect(change.upserts.map(\.entityId) == ["cover.demo_garage"])
        #expect(change.removed == ["switch.fan"])
        #expect(engine.entities.count == 3)
    }

    @Test func aDiffForAnUnknownEntityIsIgnored() throws {
        var engine = try started()
        let change = engine.apply(try message(["c": ["light.demo_ghost": ["+": ["s": "on"]]]]))
        #expect(change.upserts.isEmpty && change.removed.isEmpty)
        #expect(engine.entities["light.demo_ghost"] == nil)
    }

    @Test func aNewEntityWithoutAStateIsDropped() throws {
        var engine = try started()
        let change = engine.apply(try message(["a": ["sensor.demo_stateless": ["a": ["x": 1.0]]]]))
        #expect(change.upserts.isEmpty)
        #expect(engine.entities["sensor.demo_stateless"] == nil)
    }

    @Test func aNewEntityWithoutLastChangedGetsTheClockOnce() throws {
        var engine = try started()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let change = engine.apply(try message(["a": ["sensor.demo_fresh": ["s": "1", "a": [:] as [String: Any]]]]), now: now)
        #expect(change.upserts.first?.lastChanged == now)
        // The same entity arriving again without `lc` keeps the first stamp: no phantom change.
        let again = engine.apply(try message(["a": ["sensor.demo_fresh": ["s": "1", "a": [:] as [String: Any]]]]), now: now.addingTimeInterval(99))
        #expect(again.upserts.isEmpty)
    }

    // MARK: Batching

    @Test func aBatchKeepsTheNewestValueOfEachEntity() throws {
        var engine = try started()
        var batch = EntityDeltaBatch()
        batch.merge(engine.apply(try message(["c": ["switch.fan": ["+": ["s": "on", "lc": t0 + 1]]]])), houseCount: 3)
        batch.merge(engine.apply(try message(["c": ["switch.fan": ["+": ["s": "off", "lc": t0 + 2]]]])), houseCount: 3)
        batch.merge(engine.apply(try message(["r": ["sensor.demo_temp"]])), houseCount: 2)
        let applied = batch.applied
        #expect(applied.changed.map(\.state) == ["off"])
        #expect(applied.removed == ["sensor.demo_temp"])
        #expect(applied.houseCount == 2)
        #expect(!applied.isFirst)
    }

    @Test func aBatchDropsAnEntityRemovedAfterItChanged() throws {
        var engine = try started()
        var batch = EntityDeltaBatch()
        batch.merge(engine.apply(try message(["c": ["switch.fan": ["+": ["s": "on"]]]])), houseCount: 3)
        batch.merge(engine.apply(try message(["r": ["switch.fan"]])), houseCount: 2)
        #expect(batch.applied.changed.isEmpty)
        #expect(batch.applied.removed == ["switch.fan"])
    }

    @Test func anEmptyFirstSetStillCountsAsAHandOver() throws {
        var engine = EntityDeltaEngine()
        var batch = EntityDeltaBatch()
        batch.merge(engine.apply(try message(["a": [:] as [String: Any]])), houseCount: 0)
        #expect(!batch.isEmpty)
        #expect(batch.applied.isFirst)
    }
}

/// The connection's subscription: one `subscribe_entities` per connection, a diff per message, a full set only when the socket
/// really restarted it.
@MainActor
@Suite(.demoHouse)
struct EntitySubscriptionTests {
    private func make() -> (HassConnection, EntityStore, HAMockConnection) {
        let mock = HAMockConnection()
        let store = EntityStore()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "sub-\(UUID()).json"))
        return (HassConnection(server: .example, store: store, snapshotCache: cache, connection: mock), store, mock)
    }

    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    /// Delivers a message the way HAKit does: on its callback queue.
    private func deliver(_ mock: HAMockConnection, _ fields: [String: Any]) {
        let subscription = mock.pendingSubscriptions[0]
        nonisolated(unsafe) let data = HAData.dictionary(fields)
        mock.callbackQueue.async { subscription.handler(subscription.cancellable, data) }
    }

    private func restart(_ mock: HAMockConnection) {
        let subscription = mock.pendingSubscriptions[0]
        mock.callbackQueue.async { subscription.initiated(.success(.empty)) }
    }

    @Test func connectingSubscribesToEntitiesOnce() {
        let (connection, _, mock) = make()
        connection.connect()
        connection.connect()
        #expect(mock.pendingSubscriptions.count == 1)
        #expect(mock.pendingSubscriptions[0].request.type == .subscribeEntities)
    }

    @Test func theSubscriptionIsRetriedOnEverySocketForever() {
        let (connection, _, mock) = make()
        connection.connect()
        let request = mock.pendingSubscriptions[0].request
        #expect(request.shouldRetry)
        #expect(request.retryDuration == nil)
    }

    @Test func noStatesSubscriptionWhenTheCallerOnlySendsCommands() {
        let (connection, _, mock) = make()
        connection.connect(subscribingToStates: false)
        #expect(mock.pendingSubscriptions.isEmpty)
    }

    @Test func disconnectCancelsTheSubscription() {
        let (connection, _, mock) = make()
        connection.connect()
        connection.disconnect()
        #expect(mock.cancelledSubscriptions.count == 1)
    }

    @Test func aFullSetThenDiffsReachTheStore() async {
        let (connection, store, mock) = make()
        connection.connect()
        restart(mock)
        deliver(mock, ["a": ["light.demo_a": ["s": "on", "a": ["brightness": 10.0], "lc": 1_700_000_000.0],
                             "sensor.demo_b": ["s": "3", "a": [:] as [String: Any], "lc": 1_700_000_000.0]]])
        await settle { store.freshness == .live }
        #expect(store.entity("light.demo_a").state?.state == "on")
        #expect(store.freshness == .live)

        let before = store.publishedChangeCount
        deliver(mock, ["c": ["light.demo_a": ["+": ["a": ["brightness": 20.0]]]]])
        await settle { store.entity("light.demo_a").state?.attributes["brightness"] == .number(20) }
        #expect(store.entity("light.demo_a").state?.attributes["brightness"] == .number(20))
        #expect(store.publishedChangeCount == before + 1)
        #expect(store.entity("sensor.demo_b").state?.state == "3")
    }

    @Test func aResendAfterAReconnectPublishesNothingForUnchangedEntities() async {
        let (connection, store, mock) = make()
        connection.connect()
        // A box for every fixture entity up front, so a spurious publish for either one is counted.
        _ = store.entity("light.demo_a")
        _ = store.entity("sensor.demo_b")
        let house: [String: Any] = ["a": ["light.demo_a": ["s": "on", "a": [:] as [String: Any], "lc": 1_700_000_000.0],
                                          "sensor.demo_b": ["s": "3", "a": [:] as [String: Any], "lc": 1_700_000_000.0]]]
        restart(mock)
        deliver(mock, house)
        await settle { store.freshness == .live }
        let before = store.publishedChangeCount
        // The socket came back: the server restarts the subscription and sends the whole house again.
        restart(mock)
        deliver(mock, house)
        deliver(mock, ["c": ["sensor.demo_b": ["+": ["s": "4", "lc": 1_700_000_100.0]]]])
        await settle { store.entity("sensor.demo_b").state?.state == "4" }
        #expect(store.entity("sensor.demo_b").state?.state == "4")
        #expect(store.publishedChangeCount == before + 1)
    }

    @Test func aResendDropsWhatTheServerNoLongerHas() async {
        let (connection, store, mock) = make()
        connection.connect()
        restart(mock)
        deliver(mock, ["a": ["light.demo_a": ["s": "on", "a": [:] as [String: Any], "lc": 1_700_000_000.0],
                             "sensor.demo_b": ["s": "3", "a": [:] as [String: Any], "lc": 1_700_000_000.0]]])
        await settle { store.entity("sensor.demo_b").state != nil }
        _ = store.entity("sensor.demo_b")
        restart(mock)
        deliver(mock, ["a": ["light.demo_a": ["s": "on", "a": [:] as [String: Any], "lc": 1_700_000_000.0]]])
        await settle { store.entity("sensor.demo_b").state == nil }
        #expect(store.entity("sensor.demo_b").state == nil)
        #expect(store.entity("light.demo_a").state?.state == "on")
    }

    @Test func theFirstLiveSetReplacesTheDiskSnapshot() async {
        let (connection, store, mock) = make()
        store.replaceAll([EntityState(entityId: "sensor.demo_old", state: "1")], freshness: .snapshot(savedAt: .now))
        connection.connect()
        restart(mock)
        deliver(mock, ["a": ["light.demo_a": ["s": "on", "a": [:] as [String: Any], "lc": 1_700_000_000.0]]])
        await settle { store.freshness == .live }
        #expect(store.entity("sensor.demo_old").state == nil)
        #expect(store.entity("light.demo_a").state?.state == "on")
    }

    @Test func aBurstOfDiffsLeavesTheNewestValue() async {
        let (connection, store, mock) = make()
        connection.connect()
        restart(mock)
        deliver(mock, ["a": ["sensor.demo_n": ["s": "0", "a": [:] as [String: Any], "lc": 1_700_000_000.0]]])
        for step in 1...50 { deliver(mock, ["c": ["sensor.demo_n": ["+": ["s": "\(step)", "lc": 1_700_000_000.0 + Double(step)]]]]) }
        await settle { store.entity("sensor.demo_n").state?.state == "50" }
        #expect(store.entity("sensor.demo_n").state?.state == "50")
    }
}
