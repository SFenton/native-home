import Foundation
@testable import HassCore
import HassTestSupport
import Testing

@Suite(.demoHouse)
struct EntitySnapshotCacheTests {
    private func makeCache() -> EntitySnapshotCache {
        EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "snapshot-\(UUID()).json"))
    }

    @Test func roundTripsStatesForTheSameServer() throws {
        let cache = makeCache()
        let state = EntityState(
            entityId: "weather.demo_weather_1",
            state: "sunny",
            attributes: ["temperature": .number(71), "friendly_name": .string("Pirate Weather"), "flag": .bool(true)],
            lastChanged: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try cache.save([state], server: .example, at: Date(timeIntervalSince1970: 5))
        let snapshot = try #require(cache.load(for: .example))
        #expect(snapshot.entities == [state])
        #expect(snapshot.savedAt == Date(timeIntervalSince1970: 5))
        cache.clear()
    }

    @Test func ignoresSnapshotFromAnotherServer() throws {
        let cache = makeCache()
        try cache.save([EntityState(entityId: "light.demo_a", state: "on")], server: .example)
        #expect(cache.load(for: HassServer(baseURL: URL(string: "https://other.example")!)) == nil)
        cache.clear()
    }
}
