import Foundation
@testable import HassCore
import HassTestSupport
import Observation
import os
import Testing

@MainActor
@Suite(.demoHouse)
struct EntityStoreTests {
    @Test func boxesAreStableAndOnlyChangedEntitiesPublish() {
        let store = EntityStore()
        let kitchen = store.entity("light.demo_kitchen_item_1")
        let office = store.entity("light.demo_office_light_item_1")
        store.replaceAll([
            EntityState(entityId: "light.demo_kitchen_item_1", state: "on"),
            EntityState(entityId: "light.demo_office_light_item_1", state: "off"),
        ])
        #expect(store.publishedChangeCount == 2)

        // A reconnect delivers the full set again with one change.
        store.replaceAll([
            EntityState(entityId: "light.demo_kitchen_item_1", state: "on"),
            EntityState(entityId: "light.demo_office_light_item_1", state: "on"),
        ])
        #expect(store.publishedChangeCount == 3)
        #expect(store.entity("light.demo_kitchen_item_1") === kitchen)
        #expect(store.entity("light.demo_office_light_item_1") === office)
        #expect(office.state?.state == "on")
    }

    @Test func removedEntitiesClearTheirBox() {
        let store = EntityStore()
        let box = store.entity("sensor.demo_gone")
        store.replaceAll([EntityState(entityId: "sensor.demo_gone", state: "1")])
        store.replaceAll([])
        #expect(box.state == nil)
    }

    @Test func freshnessMovesFromSnapshotToLive() {
        let store = EntityStore()
        let saved = Date(timeIntervalSince1970: 1_000)
        store.replaceAll([EntityState(entityId: "light.demo_kitchen_item_1", state: "off")], freshness: .snapshot(savedAt: saved))
        #expect(store.freshness == .snapshot(savedAt: saved))
        store.replaceAll([EntityState(entityId: "light.demo_kitchen_item_1", state: "off")])
        #expect(store.freshness == .live)
    }

    @Test func resetClearsEverything() {
        let store = EntityStore()
        let box = store.entity("light.demo_kitchen_item_1")
        store.replaceAll([EntityState(entityId: "light.demo_kitchen_item_1", state: "on")])
        store.reset()
        #expect(box.state == nil)
        #expect(store.freshness == .empty)
        #expect(store.allValues.isEmpty)
    }
}

/// `reapplyGeneration` tells animated layout (a remote's action set) that the whole state was handed back at once.
@MainActor
@Suite(.demoHouse)
struct EntityStoreReapplyTests {
    @Test func aFullSetAndAReconnectBumpTheGenerationButALiveChangeDoesNot() {
        let store = EntityStore()
        #expect(store.reapplyGeneration == 0)
        store.replaceAll([EntityState(entityId: "media_player.demo_a", state: "off")], freshness: .snapshot(savedAt: .now))
        #expect(store.reapplyGeneration == 1, "the cold launch from the disk snapshot")
        store.replaceAll([EntityState(entityId: "media_player.demo_a", state: "playing")], freshness: .live)
        #expect(store.reapplyGeneration == 2, "the first live set replacing it")
        store.apply([EntityState(entityId: "media_player.demo_a", state: "paused")], removing: [], freshness: .live)
        store.apply([EntityState(entityId: "media_player.demo_a", state: "playing")])
        #expect(store.reapplyGeneration == 2, "an ordinary update is something that happened on screen")
        store.noteReapply()
        #expect(store.reapplyGeneration == 3, "a reconnect")
    }

    // MARK: A delivery applied in place

    @Test func aDeliveryReplacesOnlyWhatDiffersAndHandsBackWhatItDisplaced() {
        let store = EntityStore()
        _ = ["light.demo_a", "light.demo_b", "light.demo_c"].map(store.entity)
        store.replaceAll([EntityState(entityId: "light.demo_a", state: "on"), EntityState(entityId: "light.demo_b", state: "on")])
        let before = store.publishedChangeCount
        let displaced = store.apply([
            EntityState(entityId: "light.demo_a", state: "on"),                       // the same: nothing to do
            EntityState(entityId: "light.demo_b", state: "off"),                      // changed
            EntityState(entityId: "light.demo_c", state: "on"),                       // new
        ])
        #expect(store.publishedChangeCount == before + 2, "an equal value is not republished; a changed and a new one are")
        #expect(displaced.map(\.entityId) == ["light.demo_b"], "only a replaced value is handed back, a new one displaces nothing")
        #expect(store.value("light.demo_b")?.state == "off")
        #expect(store.value("light.demo_c")?.state == "on")
        #expect(store.value("light.demo_a")?.state == "on")
    }

    @Test func aChangeToOneEntityIsOneBoxUpdateAndWakesOnlyItsReaders() {
        let store = EntityStore()
        store.replaceAll((0..<200).map { EntityState(entityId: "sensor.demo_\($0)", state: "0") })
        let read = store.entity("sensor.demo_7"), other = store.entity("sensor.demo_8")
        let woke = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking { _ = read.state } onChange: { woke.withLock { $0 += 1 } }
        let displaced = store.apply([EntityState(entityId: "sensor.demo_7", state: "1")])
        #expect(woke.withLock { $0 } == 1, "the one reader of the changed box was told")
        #expect(displaced.count == 1)
        #expect(other.state?.state == "0", "a neighbouring box is untouched")
        #expect(store.publishedChangeCount == 1, "one box update, for the one box that exists and changed")
    }

    @Test func thePeopleRevisionMovesWhenAPersonComesOrChangesUserAndNotOtherwise() {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "person.demo_a", state: "home", attributes: ["user_id": .string("u1")])])
        let start = store.peopleRevision
        store.apply([EntityState(entityId: "person.demo_a", state: "away", attributes: ["user_id": .string("u1")])])
        #expect(store.peopleRevision == start, "a person's state moving is not a change of who they are")
        store.apply([EntityState(entityId: "person.demo_a", state: "away", attributes: ["user_id": .string("u2")])])
        #expect(store.peopleRevision == start + 1, "a person pointing at another user is")
        store.apply([EntityState(entityId: "person.demo_b", state: "home")])
        #expect(store.peopleRevision == start + 2, "a new person is")
        store.apply([EntityState(entityId: "sensor.demo_person_like", state: "1"), EntityState(entityId: "sensor.demo_person_like", state: "2")])
        #expect(store.peopleRevision == start + 2, "an entity that only looks like one, or a plain change, is not")
    }
}
