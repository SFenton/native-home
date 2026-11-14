#if DEBUG
import Foundation
import HassCore

/// A scripted house config transport: nothing is sent until ``emit(_:)``.
@MainActor
final class StubHouseTransport: HouseConfigTransport {
    private var handler: (@Sendable (Result<Data, Error>) -> Void)?
    /// How many times a store subscribed.
    private(set) var subscribeCount = 0

    func subscribe(_ handler: @escaping @Sendable (Result<Data, Error>) -> Void) -> @Sendable () -> Void {
        subscribeCount += 1
        self.handler = handler
        return {}
    }

    /// Answers the subscription, as the server would.
    func emit(_ result: Result<Data, Error>) { handler?(result) }
}

/// A house config source, scripted transport and store built in the **app's** copy of HassCore, for hosted tests of the layout gate.
///
/// The hosted test bundle links its own copy of HassCore, so a source, transport or store the test makes is a different object from
/// the one the app's gate observes, and the gate never sees its changes (`.agents/testing/apple/README.md`, "Hosted tests see two
/// copies"). Building them here puts them in the copy the screens under test use; the test passes them to a page through
/// ``UKContext/houseConfigStore`` and ``UKContext/houseConfigSource``.
@MainActor
final class GalleryHouseRig {
    /// The source the store writes and the gate reads.
    let source = HouseConfigSource()
    /// The transport the store follows.
    let transport = StubHouseTransport()
    private let server = HassServer(baseURL: URL(string: "https://demo.example.com")!)

    /// Whether the source holds a document.
    var hasDocument: Bool { source.read { _ in true } ?? false }
    /// How the last store's attempt went (`.idle` before any store).
    private(set) var store: HouseConfigStore?

    /// How the store's last attempt went.
    var status: HouseConfigStore.Status { store?.status ?? .idle }

    /// Puts a document in the source, or clears it, as a cache read would.
    func setDocument(_ config: HouseConfig?) { source.set(config) }

    /// A started store over ``transport`` and ``source``. Everything that touches the store runs here, in the app's copy of HassCore:
    /// the test's own copy would run its own code on these objects.
    /// - Parameters:
    ///   - timeout: How long the store waits for the first answer.
    ///   - cached: A document and hash already on disk, read before the first page builds when `loadsCacheSynchronously`.
    ///   - loadsCacheSynchronously: Reads the cache in `start()`, as a cold launch does.
    func makeStore(timeout: Duration = .seconds(60), cached: (config: HouseConfig, hash: String)? = nil,
                   loadsCacheSynchronously: Bool = false) throws -> HouseConfigStore {
        let cache = HouseConfigCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "rig-\(UUID()).json"))
        if let cached { try cache.save(cached.config, hash: cached.hash, server: server) }
        let made = HouseConfigStore(server: server, transport: transport, cache: cache, source: source, timeout: timeout,
                                    loadsCacheSynchronously: loadsCacheSynchronously)
        made.start()
        store = made
        return made
    }
}
#endif
