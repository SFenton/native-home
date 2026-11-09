import Foundation
@preconcurrency import HAKit
@testable import HassCore
import HassTestSupport
import Testing

/// The store's missing-layout behaviour (`.agents/design/house-config-states.md` rules 10 and 13): a timeout status, a resubscribe
/// while there is no document, and a saved layout that survives every status.
@MainActor
struct HouseConfigStoreStatusTests {
    let server = HassServer(baseURL: URL(string: "https://demo.example.com")!)
    let cacheURL = FileManager.default.temporaryDirectory.appending(path: "house-status-\(UUID()).json")
    let transport = FakeHouseConfigTransport()

    private func makeStore(timeout: Duration = .seconds(60)) -> HouseConfigStore {
        HouseConfigStore(server: server, transport: transport, cache: HouseConfigCache(fileURL: cacheURL), timeout: timeout)
    }

    private func newerSchemaReply() throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: HouseReply.document(DemoHouse.config)) as? [String: Any])
        object["schema"] = 99
        return try JSONSerialization.data(withJSONObject: object)
    }

    // MARK: - Timeout

    @Test func aSubscriptionWithNoReplyTimesOut() async {
        let store = makeStore(timeout: .milliseconds(50))
        store.start()
        #expect(await eventually { store.status == .timedOut })
        #expect(store.current == nil)
    }

    @Test func aReplyBeforeTheTimeoutCancelsIt() async throws {
        transport.initial = .success(try HouseReply.document(DemoHouse.config))
        let store = makeStore(timeout: .milliseconds(200))
        store.start()
        #expect(await eventually { store.status == .ready })
        try? await Task.sleep(for: .milliseconds(400))
        #expect(store.status == .ready, "The timer ended with the first reply")
    }

    @Test func aLateReplyAfterTheTimeoutStillArrives() async throws {
        let store = makeStore(timeout: .milliseconds(50))
        store.start()
        #expect(await eventually { store.status == .timedOut })
        transport.emit(.success(try HouseReply.document(DemoHouse.config, hash: "late")))
        #expect(await eventually { store.status == .ready })
        #expect(store.hash == "late")
    }

    // MARK: - Resubscribe

    @Test func aStoreWithoutADocumentAsksAgainOnEveryCall() async throws {
        transport.initial = .failure(HouseReply.unknownCommand)
        let store = makeStore()
        store.start()
        #expect(await eventually { store.status == .integrationMissing })
        #expect(transport.subscribeCount == 1)
        store.resubscribeIfNeeded()
        #expect(store.status == .loading, "A retry shows as loading until the server answers")
        #expect(transport.subscribeCount == 2)
        #expect(await eventually { transport.cancelCount == 1 })
        #expect(await eventually { store.status == .integrationMissing })
        // The integration is installed meanwhile.
        transport.initial = .success(try HouseReply.document(DemoHouse.config))
        store.resubscribeIfNeeded()
        #expect(await eventually { store.status == .ready })
        #expect(store.current == DemoHouse.config)
    }

    @Test func aReadyStoreDoesNotResubscribe() async throws {
        transport.initial = .success(try HouseReply.document(DemoHouse.config))
        let store = makeStore()
        store.start()
        #expect(await eventually { store.status == .ready })
        store.resubscribeIfNeeded()
        #expect(transport.subscribeCount == 1)
        #expect(store.status == .ready)
    }

    @Test func aStoreThatNeverStartedDoesNotResubscribe() {
        let store = makeStore()
        store.resubscribeIfNeeded()
        #expect(transport.subscribeCount == 0 && store.status == .idle)
    }

    @Test func aTimeoutRestartsWithEachResubscribe() async {
        let store = makeStore(timeout: .milliseconds(50))
        store.start()
        #expect(await eventually { store.status == .timedOut })
        store.resubscribeIfNeeded()
        #expect(store.status == .loading)
        #expect(await eventually { store.status == .timedOut })
        #expect(transport.subscribeCount == 2)
    }

    // MARK: - A saved layout always wins

    @Test func aCachedDocumentSurvivesEveryStatus() async throws {
        try HouseConfigCache(fileURL: cacheURL).save(DemoHouse.config, hash: "saved", server: server)
        let replies: [(Result<Data, Error>?, HouseConfigStore.Status)] = [
            (.failure(HouseReply.unknownCommand), .integrationMissing),
            (.success(HouseReply.notConfigured), .notConfigured),
            (.success(Data(#"{"schema": 1, "hash": "x", "config": {"home": 3}}"#.utf8)), .invalid),
            (.success(try newerSchemaReply()), .newerSchema(found: 99)),
            (nil, .timedOut),
        ]
        let store = makeStore(timeout: .milliseconds(80))
        transport.initial = replies[0].0
        store.start()
        #expect(await eventually { store.status == replies[0].1 })
        #expect(store.current == DemoHouse.config && store.hash == "saved")
        for (reply, status) in replies.dropFirst() {
            transport.initial = reply
            store.resubscribeIfNeeded()
            #expect(await eventually { store.status == status }, "status \(status)")
            #expect(store.current == DemoHouse.config && store.hash == "saved", "A \(status) status never clears the saved layout")
        }
    }

    @Test func aStatusChangeAfterADocumentKeepsIt() async throws {
        transport.initial = .success(try HouseReply.document(DemoHouse.config, hash: "h1"))
        let store = makeStore()
        store.start()
        #expect(await eventually { store.status == .ready })
        transport.emit(.failure(HouseReply.unknownCommand))
        #expect(await eventually { store.status == .integrationMissing })
        store.resubscribeIfNeeded()
        #expect(store.status == .loading && store.current == DemoHouse.config)
    }

    // MARK: - Connected clock

    @Test func theTimeoutClockRunsOnlyWhileConnected() async {
        let store = makeStore(timeout: .milliseconds(60))
        store.setConnected(false)
        store.start()
        try? await Task.sleep(for: .milliseconds(250))
        #expect(store.status == .loading, "Offline longer than the timeout is still the skeleton")
        store.setConnected(true)
        #expect(store.status == .loading)
        #expect(await eventually { store.status == .timedOut }, "The clock starts when the connection comes up")
    }

    @Test func goingOfflineStopsTheClock() async {
        let store = makeStore(timeout: .milliseconds(200))
        store.start()
        try? await Task.sleep(for: .milliseconds(50))
        store.setConnected(false)
        try? await Task.sleep(for: .milliseconds(400))
        #expect(store.status == .loading)
    }

    @Test func aReconnectDoesNotCancelASubscriptionStillWaiting() async {
        let store = makeStore()
        store.start()
        #expect(await eventually { transport.subscribeCount == 1 })
        store.resubscribeIfNeeded()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(transport.subscribeCount == 1 && transport.cancelCount == 0, "HAKit retries a live subscription itself")
    }

    // MARK: - Cold launch with a saved layout

    @Test func aSynchronousStartAdoptsTheCacheBeforeAnyPageBuilds() throws {
        try HouseConfigCache(fileURL: cacheURL).save(DemoHouse.config, hash: "saved", server: server)
        let source = HouseConfigSource()
        let store = HouseConfigStore(server: server, transport: transport, cache: HouseConfigCache(fileURL: cacheURL), source: source,
                                     loadsCacheSynchronously: true)
        store.start()
        #expect(store.current == DemoHouse.config && source.current == DemoHouse.config, "The saved layout is there when start() returns")
        #expect(store.status == .loading && transport.subscribeCount == 1)
    }
}
