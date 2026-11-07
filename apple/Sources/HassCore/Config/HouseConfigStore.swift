import Foundation
@preconcurrency import HAKit
import HassTelemetry
import Observation

/// Holds the house document the server serves: it is followed, cached and pushed into a
/// ``HouseConfigSource``, which the `*Config` facades read. The app holds no house data of its own: with no document
/// the facades answer empty values and the missing-layout states show.
///
/// **Lifecycle.** ``start()`` (called once after authentication) loads the cached document for the signed-in server,
/// and subscribes to `fenton_home/house_config/subscribe`. The server sends the current document first and HAKit
/// restarts the subscription after a reconnect, so there is no separate get. ``stop()`` ends the subscription;
/// ``clear()`` also deletes the cache (sign-out), and a cache write that finishes after it is dropped.
///
/// **Threads.** The JSON is decoded and validated off the main thread (HAKit's
/// callback queue); the main thread gets one update per change, in arrival order, and compares only the hash.
///
/// **Never worse than before.** `unknown_command` (the integration is missing or older), `{"configured": false}`, a
/// newer schema, a document that fails to decode or a role the app needs and the file lacks all leave ``current`` as it
/// was (the last good cache, or `nil`) and set ``status``. Nothing here throws to a caller or touches a screen.
@MainActor
@Observable
public final class HouseConfigStore {
    // MARK: - Types

    /// What the last attempt to get a document ended with.
    public enum Status: Equatable, Sendable {
        /// ``start()`` has not run.
        case idle
        /// Waiting for the first answer.
        case loading
        /// A document arrived and ``current`` holds it.
        case ready
        /// The server answered `{"configured": false}`.
        case notConfigured
        /// The server does not know the command: the integration is missing or older than this build.
        case integrationMissing
        /// The document's schema is newer than this build reads.
        case newerSchema(found: Int)
        /// The reply was not a usable document.
        case invalid
        /// Connected for ``timeout`` with no reply at all (the server neither sent a document nor refused).
        case timedOut
    }

    /// What a reply came to once judged, off the main thread.
    enum Verdict: Sendable {
        case document(config: HouseConfig, hash: String?)
        case notConfigured
        case integrationMissing
        case newerSchema(found: Int)
        case invalid
    }

    // MARK: - State

    /// The server's document: the last good one from this session or the cache, or `nil` when there never was one.
    public private(set) var current: HouseConfig?
    /// The server's hash of ``current``.
    public private(set) var hash: String?
    /// How the last attempt went.
    public private(set) var status: Status = .idle

    @ObservationIgnored private let server: HassServer
    @ObservationIgnored private let transport: any HouseConfigTransport
    @ObservationIgnored private let cache: HouseConfigCache
    @ObservationIgnored private let source: HouseConfigSource?
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var cancelSubscription: (@Sendable () -> Void)?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private let timeout: Duration
    @ObservationIgnored private let loadsCacheSynchronously: Bool
    /// Whether the connection is up; the timeout only counts while it is (``setConnected(_:)``).
    @ObservationIgnored private var isConnected = true
    @ObservationIgnored private let writes: WriteGate
    @ObservationIgnored private var listeners: [UUID: AsyncStream<HouseConfig>.Continuation] = [:]

    /// Creates a store; nothing happens until ``start()``.
    /// - Parameters:
    ///   - server: The signed-in server; the cache is keyed to it.
    ///   - transport: How to reach the server (``HassHouseConfigTransport``).
    ///   - cache: Where the last good document is kept.
    ///   - source: Where the accepted document is published for the facades; the app passes
    ///     ``HouseConfigSource/shared``, tests leave it `nil` or pass their own.
    ///   - timeout: How long a subscription may stay unanswered, while connected, before ``Status/timedOut`` (10 s).
    ///   - loadsCacheSynchronously: Reads the cached document inside ``start()`` instead of after a hop (the app does, so the
    ///     first page already has its saved layout and never draws a skeleton for it; the file is small).
    public init(
        server: HassServer, transport: any HouseConfigTransport, cache: HouseConfigCache = .init(),
        source: HouseConfigSource? = nil, timeout: Duration = .seconds(10), loadsCacheSynchronously: Bool = false
    ) {
        self.server = server
        self.transport = transport
        self.cache = cache
        self.source = source
        self.timeout = timeout
        self.loadsCacheSynchronously = loadsCacheSynchronously
        writes = WriteGate(cache: cache)
    }

    // MARK: - Lifecycle

    /// Loads the cache, follows the server and asks it once. Safe to call repeatedly: only the first call acts.
    public func start() {
        guard startTask == nil else { return }
        status = .loading
        let cache = cache, server = server
        if loadsCacheSynchronously {
            // A placeholder task marks the store started; the cache is already adopted when the first page builds.
            startTask = Task {}
            // The one disk read and decode on the launch path: an interval so a slow document shows in Instruments.
            let read = Telemetry.begin(Telemetry.Name.houseConfigRead)
            let cached = cache.load(for: server)
            Telemetry.end(read, detail: cached == nil ? "miss" : "hit")
            if let cached { adopt(cached) }
            follow()
            return
        }
        startTask = Task { [weak self] in
            // Disk and decode stay off the main thread; the socket is not needed for the cached copy.
            let cached = await Task.detached { cache.load(for: server) }.value
            guard let self, !Task.isCancelled else { return }
            if let cached { adopt(cached) }
            follow()
        }
    }

    private func adopt(_ cached: HouseConfigCache.Loaded) {
        guard current == nil else { return }
        current = cached.config
        hash = cached.hash
        source?.set(cached.config)
        publish(cached.config)
    }

    /// Tells the store whether the connection is up. The ``Status/timedOut`` clock runs only while it is: going down cancels it,
    /// coming up starts it again for a subscription still waiting for its first reply. A store never told assumes it is up.
    public func setConnected(_ connected: Bool) {
        guard connected != isConnected else { return }
        isConnected = connected
        if connected {
            if status == .loading, cancelSubscription != nil { armTimeout(epoch: epoch) }
        } else {
            timeoutTask?.cancel()
            timeoutTask = nil
        }
    }

    /// Ends the subscription and keeps ``current`` and the cache (a stop for the background or a switch of route).
    public func stop() {
        epoch += 1
        startTask?.cancel()
        startTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        cancelSubscription?()
        cancelSubscription = nil
        if status == .loading { status = .idle }
    }

    /// Sign-out: stops, forgets the document and deletes the cache.
    public func clear() {
        stop()
        writes.clear()
        source?.set(nil)
        current = nil
        hash = nil
        status = .idle
    }

    /// Subscribes again when the last attempt was refused or timed out (a subscription still waiting is alive: HAKit retries it): on every reconnect, every return to the
    /// foreground and the Try Again of a timeout. HAKit retries a live subscription, not a refused one, so a store that is
    /// not ``Status/ready`` asks again itself and the page changes without the person doing anything. A status change never
    /// clears ``current`` (a saved layout always wins).
    public func resubscribeIfNeeded() {
        guard startTask != nil, cancelSubscription != nil, status != .ready, status != .loading else { return }
        epoch += 1
        cancelSubscription?()
        cancelSubscription = nil
        status = .loading
        follow()
    }

    /// Every document that replaces ``current``, one element per change, on the main actor. The cached document counts
    /// as the first change. A new stream per call; it ends when the store is released.
    public func changes() -> AsyncStream<HouseConfig> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<HouseConfig>.makeStream()
        listeners[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.listeners[id] = nil }
        }
        return stream
    }

    // MARK: - Receiving

    private func follow() {
        guard cancelSubscription == nil else { return }
        let epoch = epoch
        if isConnected { armTimeout(epoch: epoch) }
        cancelSubscription = transport.subscribe { [weak self] result in
            // On HAKit's callback queue: judge here, then one hop to the main thread, in arrival order.
            let verdict = Self.judge(result)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply(verdict, epoch: epoch) } }
        }
    }

    /// After ``timeout`` with the subscription still unanswered the status becomes ``Status/timedOut``.
    private func armTimeout(epoch armed: Int) {
        timeoutTask?.cancel()
        let timeout = timeout
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, armed == epoch, status == .loading else { return }
            status = .timedOut
        }
    }

    /// Judges a reply. Runs off the main thread, so a large document costs the main thread nothing.
    nonisolated static func judge(_ result: Result<Data, Error>) -> Verdict {
        switch result {
        case let .failure(error):
            return isUnknownCommand(error) ? .integrationMissing : .invalid
        case let .success(data):
            do {
                let envelope = try HouseConfigEnvelope.decode(data)
                guard let config = envelope.config else { return .notConfigured }
                return .document(config: config, hash: envelope.hash)
            } catch HouseConfig.DecodeError.unsupportedSchema(let found, _) {
                return .newerSchema(found: found)
            } catch {
                return .invalid
            }
        }
    }

    /// Whether the server refused because it has no such command.
    nonisolated static func isUnknownCommand(_ error: Error) -> Bool {
        guard case let .external(external)? = error as? HAError else { return false }
        return external.code == "unknown_command"
    }

    private func apply(_ verdict: Verdict, epoch delivered: Int) {
        // A delivery that was already in flight when the subscription ended (stop, sign-out) is dropped.
        guard delivered == epoch else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        switch verdict {
        case let .document(config, newHash):
            Telemetry.count("houseconfig.received")
            status = .ready
            // The server's hash names the content, so equal hashes need no whole-document comparison on the main thread.
            guard newHash == nil || newHash != hash || current == nil else { return }
            current = config
            hash = newHash
            writes.save(config, hash: newHash, server: server)
            source?.set(config)
            publish(config)
        case .notConfigured: status = .notConfigured
        case .integrationMissing: status = .integrationMissing
        case let .newerSchema(found): status = .newerSchema(found: found)
        case .invalid: status = .invalid
        }
    }

    private func publish(_ config: HouseConfig) {
        for continuation in listeners.values { continuation.yield(config) }
    }
}

// MARK: - Cache writes

extension HouseConfigStore {
    /// Orders the cache's writes against sign-out: one lock covers every save and the clear, saves are numbered, and
    /// a save that is older than the last one written, or that started before a clear, does nothing. A write
    /// that finishes after sign-out can therefore never bring the document back.
    final class WriteGate: @unchecked Sendable {
        private let cache: HouseConfigCache
        private let lock = NSLock()
        private var issued = 0
        private var written = 0
        private var generation = 0

        init(cache: HouseConfigCache) {
            self.cache = cache
        }

        /// Saves in the background unless a clear or a newer save overtakes it.
        func save(_ config: HouseConfig, hash: String?, server: HassServer) {
            let (ticket, started) = lock.withLock { () -> (Int, Int) in
                issued += 1
                return (issued, generation)
            }
            Task.detached { [self] in
                lock.withLock {
                    guard started == generation, ticket > written else { return }
                    written = ticket
                    try? cache.save(config, hash: hash, server: server)
                }
            }
        }

        /// Deletes the file now and drops every save that has not written yet.
        func clear() {
            lock.withLock {
                generation += 1
                cache.clear()
            }
        }
    }
}
