import Foundation
@testable import HassCore
import HassTestSupport
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
}
