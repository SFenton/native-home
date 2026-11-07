import Foundation
import HassCore
import HassDemoHouse
@testable import HassUI
import Testing

/// A transport that never answers: the device is offline, or the server is not reached yet.
@MainActor
private final class SilentHouseTransport: HouseConfigTransport {
    func subscribe(_ handler: @escaping @Sendable (Result<Data, Error>) -> Void) -> @Sendable () -> Void { {} }
}

/// A transport the test pushes replies down, as HAKit would from its callback queue.
@MainActor
private final class PushHouseTransport: HouseConfigTransport {
    private var handler: (@Sendable (Result<Data, Error>) -> Void)?

    func subscribe(_ handler: @escaping @Sendable (Result<Data, Error>) -> Void) -> @Sendable () -> Void {
        self.handler = handler
        return {}
    }

    func push(_ data: Data) { handler?(.success(data)) }
}

/// The compiled house is gone (step 7b-2): a cold launch with a saved layout and no network still draws the whole layout, and
/// one with neither a saved layout nor a network shows the skeleton, never house data.
@MainActor
struct HouseLayoutColdLaunchTests {
    private let server = HassServer(baseURL: URL(string: "https://demo.example.com")!)

    private func cache() -> HouseConfigCache {
        HouseConfigCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "cold-launch-\(UUID()).json"))
    }

    private func state(_ source: HouseConfigSource, _ store: HouseConfigStore) -> HouseLayoutState {
        HouseLayoutState.resolve(hasDocument: source.read { _ in true } ?? false, status: store.status, role: .unknown)
    }

    @Test func aSavedLayoutDrawsEveryPageWithNoNetwork() throws {
        let cache = cache()
        try cache.save(DemoHouse.config, hash: "saved", server: server)
        let source = HouseConfigSource()
        let store = HouseConfigStore(server: server, transport: SilentHouseTransport(), cache: cache, source: source, loadsCacheSynchronously: true)
        store.start()

        // The layout is there when start() returns, before any answer from the server: the page never builds a skeleton.
        #expect(store.status == .loading, "the server has not answered")
        #expect(state(source, store) == .content)

        // And it is the whole layout: every facade a page reads answers the saved document, not an empty value.
        HouseConfigSource.$scoped.withValue(source) {
            let demo = DemoHouse.config
            #expect(HomeConfig.statusChips == demo.home.statusChips && !HomeConfig.statusChips.isEmpty)
            #expect(HomeConfig.cameras == demo.home.cameras)
            #expect(SecurityConfig.controlTiles == demo.security.controlTiles)
            #expect(ClimateConfig.rooms == demo.climate.rooms)
            #expect(RoomsConfig.pages == demo.rooms.pages && !RoomsConfig.pages.isEmpty)
            #expect(RoomNavigation.items == demo.rooms.grid.items)
            #expect(MediaRemotes.all == demo.media.remotes)
            #expect(Vacuums.all == demo.vacuums.vacuums)
            #expect(ChoresConfig.pages == demo.chores.pages)
            #expect(SprinklersConfig.controllers == demo.sprinklers.controllers)
            #expect(MasterBedroom.beds == demo.bedroom.beds)
        }
    }

    @Test func aSavedLayoutIsStillThereWhenTheServerRefuses() async throws {
        let cache = cache()
        try cache.save(DemoHouse.config, hash: "saved", server: server)
        let source = HouseConfigSource()
        let transport = PushHouseTransport()
        let store = HouseConfigStore(server: server, transport: transport, cache: cache, source: source, loadsCacheSynchronously: true)
        store.start()

        // A schema-1 document (below minimumSchema) and a malformed one are refused; a newer one is flagged. None blanks the page.
        let refusals: [(Data, (HouseConfigStore.Status) -> Bool)] = [
            (Data(#"{"schema": 1, "hash": "x", "config": {}}"#.utf8), { $0 == .invalid }),
            (Data(#"{"schema": 2, "hash": "x", "config": {"home": 3}}"#.utf8), { $0 == .invalid }),
            (Data(#"{"schema": 99, "hash": "x", "config": {}}"#.utf8), { $0 == .newerSchema(found: 99) }),
        ]
        for (reply, expected) in refusals {
            transport.push(reply)
            for _ in 0 ..< 200 where !expected(store.status) { try await Task.sleep(for: .milliseconds(10)) }
            #expect(expected(store.status), "the refusal reached the store: \(store.status)")
            #expect(store.current == DemoHouse.config, "the saved document is still the store's")
            #expect(state(source, store) == .content, "the page still draws the layout")
            HouseConfigSource.$scoped.withValue(source) { #expect(HomeConfig.cameras == DemoHouse.config.home.cameras) }
        }
    }

    @Test func noSavedLayoutAndNoNetworkShowsTheSkeletonNotHouseData() {
        let source = HouseConfigSource()
        let store = HouseConfigStore(server: server, transport: SilentHouseTransport(), cache: cache(), source: source, loadsCacheSynchronously: true)
        store.start()
        #expect(state(source, store) == .skeleton)
        HouseConfigSource.$scoped.withValue(source) {
            #expect(HomeConfig.statusChips.isEmpty && RoomsConfig.pages.isEmpty && MediaRemotes.all.isEmpty)
            #expect(SecurityConfig.alarmEntityId.isEmpty && ChoresConfig.people.isEmpty)
        }
    }
}
