import Foundation
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
import HassTestSupport
import Testing

/// A scripted ``HouseConfigTransport``: tests set what the server sends when the subscription starts and push later
/// messages by hand.
@MainActor
final class FakeHouseConfigTransport: HouseConfigTransport {
    /// The current document the server sends first, or nil to send nothing until `emit`.
    var initial: Result<Data, Error>?
    private(set) var subscribeCount = 0
    private(set) var cancelCount = 0
    private var handler: (@Sendable (Result<Data, Error>) -> Void)?

    func subscribe(_ handler: @escaping @Sendable (Result<Data, Error>) -> Void) -> @Sendable () -> Void {
        subscribeCount += 1
        self.handler = handler
        if let initial { DispatchQueue.global().async { handler(initial) } }
        return { [weak self] in Task { @MainActor in self?.cancelCount += 1 } }
    }

    /// Sends a message down the subscription, as HAKit would from its callback queue.
    func emit(_ result: Result<Data, Error>) {
        handler?(result)
    }
}

/// Builders for the server's replies.
enum HouseReply {
    /// `{schema, hash, config}` for a document.
    static func document(_ config: HouseConfig, hash: String = "h1") throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: config.encoded()) as? [String: Any])
        let schema = object.removeValue(forKey: "schema") ?? 1
        return try JSONSerialization.data(withJSONObject: ["schema": schema, "hash": hash, "config": object])
    }

    static let notConfigured = Data(#"{"configured": false}"#.utf8)

    static var unknownCommand: Error {
        HAError.external(.init(code: "unknown_command", message: "Unknown command."))
    }

    /// The demo house with one value changed.
    static func changedHouse() -> HouseConfig {
        var config = DemoHouse.config
        config.home.weatherEntityId = "weather.demo_demo"
        return config
    }
}

/// Waits (briefly) for a condition that the store reaches after a hop off the main thread.
@MainActor
func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<500 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    return condition()
}

@MainActor
struct HouseConfigStoreTests {
    let server = HassServer(baseURL: URL(string: "https://demo.example.com")!)
    let cacheURL = FileManager.default.temporaryDirectory.appending(path: "house-\(UUID()).json")
    let transport = FakeHouseConfigTransport()

    private func makeStore(server: HassServer? = nil, cache: HouseConfigCache? = nil) -> HouseConfigStore {
        HouseConfigStore(
            server: server ?? self.server, transport: transport, cache: cache ?? HouseConfigCache(fileURL: cacheURL)
        )
    }

    // MARK: - Fetch and subscribe

    @Test func fetchesAndDecodesTheDocument() async throws {
        transport.initial = .success(try HouseReply.document(DemoHouse.config, hash: "abc"))
        let store = makeStore()
        #expect(store.status == .idle)
        store.start()
        #expect(store.status == .loading)
        #expect(await eventually { store.status == .ready })
        #expect(store.current == DemoHouse.config)
        #expect(store.hash == "abc")
        #expect(transport.subscribeCount == 1)
    }

    @Test func startIsIdempotent() async throws {
        transport.initial = .success(try HouseReply.document(DemoHouse.config))
        let store = makeStore()
        store.start()
        store.start()
        #expect(await eventually { store.status == .ready })
        #expect(transport.subscribeCount == 1)
    }

    @Test func aSubscriptionMessageReplacesTheDocument() async throws {
        transport.initial = .success(try HouseReply.document(DemoHouse.config, hash: "h1"))
        let store = makeStore()
        store.start()
        #expect(await eventually { store.status == .ready })
        let changed = HouseReply.changedHouse()
        transport.emit(.success(try HouseReply.document(changed, hash: "h2")))
        #expect(await eventually { store.hash == "h2" })
        #expect(store.current == changed)
    }

    @Test func theSameDocumentTwiceChangesNothing() async throws {
        transport.initial = .success(try HouseReply.document(DemoHouse.config, hash: "h1"))
        let store = makeStore()
        store.start()
        #expect(await eventually { store.status == .ready })
        transport.emit(.success(try HouseReply.document(DemoHouse.config, hash: "h1")))
        transport.emit(.success(Data(#"{"configured": false}"#.utf8)))
        #expect(await eventually { store.status == .notConfigured })
        #expect(store.current == DemoHouse.config)
    }

    @Test func changesStreamYieldsOncePerChange() async throws {
        transport.initial = .success(try HouseReply.document(DemoHouse.config, hash: "h1"))
        let store = makeStore()
        var iterator = store.changes().makeAsyncIterator()
        store.start()
        #expect(await iterator.next() == DemoHouse.config)
        transport.emit(.success(try HouseReply.document(HouseReply.changedHouse(), hash: "h2")))
        #expect(await iterator.next() == HouseReply.changedHouse())
    }

    @Test func aNewHashIsTakenAsANewDocumentWithoutComparingItOnTheMainThread() async throws {
        transport.initial = .success(try HouseReply.document(DemoHouse.config, hash: "h1"))
        let store = makeStore()
        store.start()
        #expect(await eventually { store.status == .ready })
        transport.emit(.success(try HouseReply.document(DemoHouse.config, hash: "h9")))
        #expect(await eventually { store.hash == "h9" })
    }

    @Test func aSocketResetBeforeTheFirstReplyLeavesTheStoreWaitingThenRecovers() async throws {
        // The subscription is up but the socket drops before the server answers: nothing is pending that could leak or
        // hang, the store stays loading with no document, and the resent subscription delivers it after the reconnect.
        let store = makeStore()
        store.start()
        #expect(await eventually { transport.subscribeCount == 1 })
        #expect(store.status == .loading && store.current == nil)
        transport.emit(.success(try HouseReply.document(DemoHouse.config, hash: "after-reconnect")))
        #expect(await eventually { store.status == .ready })
        #expect(store.hash == "after-reconnect")
        #expect(transport.subscribeCount == 1, "HAKit resends the subscription itself; the store does not subscribe again")
    }

    @Test func clearingWhileTheCacheLoadsKeepsTheStoreEmptyAndUnsubscribed() async throws {
        try HouseConfigCache(fileURL: cacheURL).save(DemoHouse.config, hash: "c", server: server)
        let store = makeStore()
        store.start()
        store.clear()
        try await Task.sleep(for: .milliseconds(300))
        #expect(store.current == nil && store.status == .idle)
        #expect(transport.subscribeCount == 0)
        #expect(!FileManager.default.fileExists(atPath: cacheURL.path))
    }

    @Test func aCacheWriteThatFinishesAfterSignOutIsDropped() async throws {
        let gate = HouseConfigStore.WriteGate(cache: HouseConfigCache(fileURL: cacheURL))
        gate.save(DemoHouse.config, hash: "late", server: server)
        gate.clear()
        try await Task.sleep(for: .milliseconds(300))
        #expect(!FileManager.default.fileExists(atPath: cacheURL.path))
        // A save made after the clear (the next sign-in) does write.
        gate.save(DemoHouse.config, hash: "next", server: server)
        #expect(await eventually { FileManager.default.fileExists(atPath: cacheURL.path) })
    }

    @Test func anOlderCacheWriteNeverOverwritesANewerOne() async throws {
        let cache = HouseConfigCache(fileURL: cacheURL)
        let gate = HouseConfigStore.WriteGate(cache: cache)
        gate.save(DemoHouse.config, hash: "one", server: server)
        gate.save(HouseReply.changedHouse(), hash: "two", server: server)
        #expect(await eventually { cache.load(for: server)?.hash == "two" })
        try await Task.sleep(for: .milliseconds(200))
        #expect(cache.load(for: server)?.hash == "two")
    }

    // MARK: - Deliveries after the end, cache hits

    @Test func aDeliveryAfterStopIsIgnored() async throws {
        transport.initial = .success(try HouseReply.document(DemoHouse.config, hash: "h1"))
        let store = makeStore()
        store.start()
        #expect(await eventually { store.status == .ready })
        store.stop()
        transport.emit(.success(try HouseReply.document(HouseReply.changedHouse(), hash: "h2")))
        try await Task.sleep(for: .milliseconds(200))
        #expect(store.hash == "h1" && store.current == DemoHouse.config)
    }

    @Test func aDeliveryAfterClearDoesNotBringTheDocumentBack() async throws {
        transport.initial = .success(try HouseReply.document(DemoHouse.config, hash: "h1"))
        let store = makeStore()
        store.start()
        #expect(await eventually { store.status == .ready })
        store.clear()
        transport.emit(.success(try HouseReply.document(DemoHouse.config, hash: "h3")))
        try await Task.sleep(for: .milliseconds(200))
        #expect(store.current == nil && store.status == .idle)
    }

    @Test func aCacheHitWithTheServersHashChangesNothing() async throws {
        try HouseConfigCache(fileURL: cacheURL).save(DemoHouse.config, hash: "same", server: server)
        transport.initial = .success(try HouseReply.document(DemoHouse.config, hash: "same"))
        let store = makeStore()
        store.start()
        #expect(await eventually { store.status == .ready })
        // A second identical delivery adds nothing.
        transport.emit(.success(try HouseReply.document(DemoHouse.config, hash: "same")))
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.current == DemoHouse.config && store.hash == "same")
    }

    // MARK: - Cache

    @Test func theCacheIsSavedAndLoadedBeforeTheSocketAnswers() async throws {
        transport.initial = .success(try HouseReply.document(HouseReply.changedHouse(), hash: "cached"))
        let first = makeStore()
        first.start()
        #expect(await eventually { first.hash == "cached" })
        #expect(await eventually { FileManager.default.fileExists(atPath: cacheURL.path) })

        // A new launch: the server cannot be reached (an older integration), the cached copy is what current holds.
        transport.initial = .failure(HouseReply.unknownCommand)
        let second = makeStore()
        second.start()
        #expect(await eventually { second.status == .integrationMissing })
        #expect(second.current == HouseReply.changedHouse())
        #expect(second.hash == "cached")
    }

    @Test func aCachedDocumentIsPublishedAsTheFirstChange() async throws {
        try HouseConfigCache(fileURL: cacheURL).save(DemoHouse.config, hash: "c", server: server)
        transport.initial = .failure(HouseReply.unknownCommand)
        let store = makeStore()
        var iterator = store.changes().makeAsyncIterator()
        store.start()
        #expect(await iterator.next() == DemoHouse.config)
    }

    @Test func aCachedSchemaOneDocumentIsRefusedAndTheServersCopyFillsIn() async throws {
        let cache = HouseConfigCache(fileURL: cacheURL)
        try cache.save(DemoHouse.config, hash: "old", server: server)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        var file = try decoder.decode(HouseConfigCache.File.self, from: Data(contentsOf: cacheURL))
        file.schema = 1
        file.document = Data(String(decoding: file.document, as: UTF8.self).replacingOccurrences(of: "\"schema\":2", with: "\"schema\":1").utf8)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(file).write(to: cacheURL)
        transport.initial = .success(try HouseReply.document(DemoHouse.config, hash: "fresh"))
        let store = makeStore()
        store.start()
        #expect(store.current == nil, "the old file is refused without a crash, and the layout waits for the server")
        #expect(await eventually { store.status == .ready })
        #expect(store.current == DemoHouse.config && store.hash == "fresh")
    }

    @Test func aCacheFromAnotherServerIsDiscarded() async throws {
        try HouseConfigCache(fileURL: cacheURL).save(DemoHouse.config, hash: "c", server: server)
        transport.initial = .failure(HouseReply.unknownCommand)
        let other = HassServer(baseURL: URL(string: "https://other.example.com")!)
        let store = makeStore(server: other)
        store.start()
        #expect(await eventually { store.status == .integrationMissing })
        #expect(store.current == nil)
        #expect(!FileManager.default.fileExists(atPath: cacheURL.path))
    }

    @Test func signOutClearsTheDocumentAndTheCache() async throws {
        transport.initial = .success(try HouseReply.document(DemoHouse.config))
        let store = makeStore()
        store.start()
        #expect(await eventually { FileManager.default.fileExists(atPath: cacheURL.path) })
        store.clear()
        #expect(store.current == nil)
        #expect(store.hash == nil)
        #expect(store.status == .idle)
        #expect(!FileManager.default.fileExists(atPath: cacheURL.path))
        #expect(await eventually { transport.cancelCount == 1 })
    }

    @Test func stopKeepsTheDocumentAndStartResumes() async throws {
        transport.initial = .success(try HouseReply.document(DemoHouse.config))
        let store = makeStore()
        store.start()
        #expect(await eventually { store.status == .ready })
        store.stop()
        #expect(store.current == DemoHouse.config)
        store.start()
        #expect(await eventually { transport.subscribeCount == 2 })
    }

    @Test func stopBeforeTheFirstAnswerReturnsToIdle() {
        let store = makeStore()
        store.start()
        store.stop()
        #expect(store.status == .idle)
    }

    // MARK: - Failures leave the last good document

    @Test func anOlderServerLeavesCurrentNil() async {
        transport.initial = .failure(HouseReply.unknownCommand)
        let store = makeStore()
        store.start()
        #expect(await eventually { store.status == .integrationMissing })
        #expect(store.current == nil)
    }

    @Test func aRefusedSubscriptionIsTheSameAsAMissingIntegration() async throws {
        transport.initial = .success(try HouseReply.document(DemoHouse.config))
        let store = makeStore()
        store.start()
        #expect(await eventually { store.status == .ready })
        transport.emit(.failure(HouseReply.unknownCommand))
        #expect(await eventually { store.status == .integrationMissing })
        #expect(store.current == DemoHouse.config)
    }

    @Test func notConfiguredKeepsTheCacheAndCurrent() async throws {
        try HouseConfigCache(fileURL: cacheURL).save(DemoHouse.config, hash: "c", server: server)
        transport.initial = .success(HouseReply.notConfigured)
        let store = makeStore()
        store.start()
        #expect(await eventually { store.status == .notConfigured })
        #expect(store.current == DemoHouse.config)
        #expect(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    @Test func aNewerSchemaKeepsTheLastGoodDocument() async throws {
        transport.initial = .success(try HouseReply.document(DemoHouse.config, hash: "h1"))
        let store = makeStore()
        store.start()
        #expect(await eventually { store.status == .ready })
        var object = try #require(JSONSerialization.jsonObject(with: HouseReply.document(DemoHouse.config)) as? [String: Any])
        object["schema"] = 99
        transport.emit(.success(try JSONSerialization.data(withJSONObject: object)))
        #expect(await eventually { store.status == .newerSchema(found: 99) })
        #expect(store.current == DemoHouse.config)
        #expect(store.hash == "h1")
    }

    @Test func aDecodeErrorKeepsTheLastGoodDocument() async throws {
        transport.initial = .success(try HouseReply.document(DemoHouse.config, hash: "h1"))
        let store = makeStore()
        store.start()
        #expect(await eventually { store.status == .ready })
        transport.emit(.success(Data(#"{"schema": 1, "hash": "x", "config": {"home": 3}}"#.utf8)))
        #expect(await eventually { store.status == .invalid })
        #expect(store.current == DemoHouse.config)
        // A later good document recovers.
        transport.emit(.success(try HouseReply.document(HouseReply.changedHouse(), hash: "h3")))
        #expect(await eventually { store.status == .ready && store.hash == "h3" })
    }

    @Test func aDocumentMissingARequiredRoleIsInvalid() async throws {
        var object = try #require(JSONSerialization.jsonObject(with: HouseReply.document(DemoHouse.config)) as? [String: Any])
        var config = try #require(object["config"] as? [String: Any])
        var media = try #require(config["media"] as? [String: Any])
        var select = try #require(media["sourceSelect"] as? [String: Any])
        select["sources"] = ["off": "Off"]
        media["sourceSelect"] = select
        config["media"] = media
        object["config"] = config
        transport.initial = .success(try JSONSerialization.data(withJSONObject: object))
        let store = makeStore()
        store.start()
        #expect(await eventually { store.status == .invalid })
        #expect(store.current == nil)
    }

    @Test func anOtherFetchErrorIsInvalidNotUnknownCommand() async {
        transport.initial = .failure(HAError.internal(debugDescription: "boom"))
        let store = makeStore()
        store.start()
        #expect(await eventually { store.status == .invalid })
        #expect(!HouseConfigStore.isUnknownCommand(HAError.internal(debugDescription: "x")))
        #expect(!HouseConfigStore.isUnknownCommand(HAError.external(.init(code: "other", message: "x"))))
        #expect(!HouseConfigStore.isUnknownCommand(CocoaError(.fileNoSuchFile)))
    }
}
