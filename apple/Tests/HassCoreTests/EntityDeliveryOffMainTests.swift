import Foundation
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
import Testing

/// HAKit's callbacks and the entity merge run off the main thread; only the changed entities are applied on it (the merge itself: ``EntityDeltaEngineTests``)
/// (`.agents/testing/apple/performance.md`, "Scroll cost": the diff of thousands of entities took over half of the main
/// thread's CPU time).
@MainActor
struct EntityDeliveryOffMainTests {
    private func make() -> (HassConnection, EntityStore, HAMockConnection) {
        let mock = HAMockConnection()
        let store = EntityStore()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "offmain-\(UUID()).json"))
        return (HassConnection(server: .example, store: store, snapshotCache: cache, connection: mock), store, mock)
    }

    @Test func hakitCallsBackOffTheMainQueue() {
        let (_, _, mock) = make()
        #expect(mock.callbackQueue !== DispatchQueue.main)
    }
}
