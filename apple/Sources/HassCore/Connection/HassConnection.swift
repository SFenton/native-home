import Foundation
@preconcurrency import HAKit
import HassTelemetry
import Observation
import os

/// The app's one Home Assistant connection: a HAKit websocket feeding ``EntityStore``.
///
/// Views never touch HAKit. They read the store and act through ``callService(_:_:data:)``.
@MainActor
@Observable
public final class HassConnection {
    // MARK: - Types

    /// Connection status for the UI.
    public enum Status: Equatable, Sendable {
        case disconnected
        case connecting
        case connected(version: String)
        case waitingToReconnect
        /// The server rejected the token; the user must sign in again.
        case rejected
    }

    /// Posted (on the main actor, object: the connection) each time the socket becomes ready for commands, including
    /// after a reconnect. Camera streams that gave up while the socket was down restart on it.
    public static let didBecomeReadyNotification = Notification.Name("HassConnection.didBecomeReady")

    // MARK: - Public state

    /// Current status.
    public private(set) var status: Status = .disconnected

    /// There is no network path (Airplane mode, no Wi-Fi or cellular). While true the socket is closed and HAKit's
    /// retry backoff is not running; the UI shows an offline state instead of "Reconnecting…", and the socket reopens
    /// the moment a path returns (``setOnline(_:)``).
    public private(set) var isOffline = false

    /// The server this connection talks to.
    public let server: HassServer

    /// Moves the websocket to Home Assistant's home network address when the phone is at home; nil keeps the
    /// public URL (tests, extensions).
    public let route: LocalServerRoute?

    /// The entity store this connection feeds.
    public let store: EntityStore

    // MARK: - Private

    @ObservationIgnored let connection: HAConnection
    @ObservationIgnored private let snapshotCache: EntitySnapshotCache
    @ObservationIgnored private var statesSubscription: HACancellable?
    // Read in `deinit`, which is nonisolated; only the main actor writes it.
    @ObservationIgnored nonisolated(unsafe) private var stateObserver: NSObjectProtocol?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Every entity as of the last `subscribe_entities` message. Touched only on ``deltaQueue``.
    @ObservationIgnored nonisolated(unsafe) private var engine = EntityDeltaEngine()
    /// What the engine changed since the last hop to the main thread. Touched only on ``deltaQueue``.
    @ObservationIgnored nonisolated(unsafe) private var batch = EntityDeltaBatch()
    /// A hop to the main thread is queued behind the messages already waiting. Touched only on ``deltaQueue``.
    @ObservationIgnored nonisolated(unsafe) private var flushScheduled = false
    /// HAKit's callback queue, in place of the main queue. Merging each `subscribe_entities` message into the house (``engine``)
    /// and batching what changed run here, so only the changed entities reach the main thread. Before this, HAKit rebuilt its whole
    /// set of entities (thousands) on every change and the diff against the last set compared them all again: over half of the
    /// main thread's CPU time, about 9 ms per delivery several times a second, longer than a 120 Hz frame
    /// (`.agents/testing/apple/performance.md`, "Scroll cost" and "Round 5").
    @ObservationIgnored private let deltaQueue = DispatchQueue(label: "com.sfenton.home.entity-delta", qos: .userInitiated)
    /// The app wants the socket open (between ``connect(subscribingToStates:)`` and ``disconnect()``).
    @ObservationIgnored var wantsConnection = false
    @ObservationIgnored private var routeTask: Task<Void, Never>?
    /// Waits for the user to stop scrolling before moving a working public socket to the home address.
    @ObservationIgnored private var switchTask: Task<Void, Never>?
    /// The URL the current socket was opened with (HAKit reads it on every connect, on its own queue).
    @ObservationIgnored let socketURL: SocketURLRecord
    /// When the user last scrolled, so a switch never lands mid-scroll.
    @ObservationIgnored let scrollActivity: ScrollActivity
    /// The reconnect policy (``ConnectionRouter``); this class feeds it events and performs its actions.
    @ObservationIgnored private var router: ConnectionRouter
    /// How long nothing may have scrolled before a working public socket moves to the home address.
    @ObservationIgnored var scrollQuietPeriod: Duration {
        get { router.quietPeriod }
        set { router.quietPeriod = newValue }
    }
    @ObservationIgnored private let reachability: (any NetworkReachability)?
    /// Gauges for what this connection registers (`ResourceCensus`).
    @ObservationIgnored private var census: ResourceCensus.Registration?

    /// How long live updates are batched before the disk snapshot is rewritten.
    static let snapshotDebounce: Duration = .seconds(10)

    // MARK: - Init

    /// Creates a connection and restores the disk snapshot into the store before any network work.
    /// - Parameters:
    ///   - server: The server to connect to.
    ///   - tokens: Supplies access tokens.
    ///   - store: The store to feed.
    ///   - snapshotCache: Disk snapshot of entity states.
    ///   - route: Uses the home network address at home (``LocalServerRoute``); nil always uses the public URL.
    public convenience init(server: HassServer, tokens: TokenManager, store: EntityStore, snapshotCache: EntitySnapshotCache = .init(),
                            route: LocalServerRoute? = nil, reachability: (any NetworkReachability)? = nil) {
        let socketURL = SocketURLRecord()
        let configuration = HAConnectionConfiguration(
            connectionInfo: { HassConnection.connectionInfo(server: server, route: route, recordingIn: socketURL) },
            fetchAuthToken: { completion in
                nonisolated(unsafe) let completion = completion
                Task {
                    do {
                        completion(.success(try await tokens.validAccessToken()))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
        )
        self.init(
            server: server, store: store, snapshotCache: snapshotCache,
            connection: HAKit.connection(configuration: configuration, connectAutomatically: false),
            route: route, reachability: reachability, socketURL: socketURL
        )
    }

    /// Creates a connection over a given HAKit connection (tests pass `HAMockConnection`).
    init(server: HassServer, store: EntityStore, snapshotCache: EntitySnapshotCache = .init(), connection: HAConnection,
         route: LocalServerRoute? = nil, reachability: (any NetworkReachability)? = nil,
         socketURL: SocketURLRecord = SocketURLRecord(), scrollActivity: ScrollActivity = .shared) {
        self.socketURL = socketURL
        self.router = ConnectionRouter(publicURL: server.baseURL)
        self.scrollActivity = scrollActivity
        self.server = server
        self.reachability = reachability
        self.store = store
        self.snapshotCache = snapshotCache
        self.connection = connection
        self.route = route
        connection.callbackQueue = deltaQueue

        if let snapshot = snapshotCache.load(for: server) {
            store.replaceAll(snapshot.entities, freshness: .snapshot(savedAt: snapshot.savedAt))
        }

        stateObserver = NotificationCenter.default.addObserver(
            forName: HAConnectionState.didTransitionToStateNotification,
            object: connection,
            queue: .main
        ) { [weak self] _ in
            Telemetry.count("connection.transitions")
            MainActor.assumeIsolated { self?.refreshStatus() }
        }

        route?.startWatching { [weak self] in
            Task { @MainActor in self?.networkDidChange() }
        }

        if let reachability {
            isOffline = !reachability.isOnline
            reachability.start { [weak self] online in
                Task { @MainActor in self?.setOnline(online) }
            }
        }

        census = ResourceCensus.shared.register { [weak self] in self?.liveResources ?? [:] }
    }

    /// What this connection has registered right now (`ResourceCensus`): each is 0 or 1, and a resume leaves them as
    /// they were.
    var liveResources: [String: Int] {
        [
            "Connection.statesSubscription": statesSubscription == nil ? 0 : 1,
            "Connection.stateObserver": stateObserver == nil ? 0 : 1,
            "Connection.saveTask": saveTask == nil ? 0 : 1,
            "Connection.routeTask": routeTask == nil ? 0 : 1,
            "Connection.switchTask": switchTask == nil ? 0 : 1,
        ]
    }

    deinit {
        // A block observer stays registered until it is removed; dropping the token would leave it behind.
        if let stateObserver { NotificationCenter.default.removeObserver(stateObserver) }
    }

    /// Where HAKit connects: the route's current URL (HAKit reads this on every connect and swaps the socket
    /// only when the URL changed).
    ///
    /// - Parameter recordingIn: Notes the URL the socket is being opened with, so the connection can tell whether it is
    ///   already on the home address. HAKit calls this on its own queue; the record is lock-protected.
    nonisolated static func connectionInfo(server: HassServer, route: LocalServerRoute?,
                                           recordingIn record: SocketURLRecord? = nil) -> HAConnectionInfo? {
        let url = route?.currentURL ?? server.baseURL
        record?.note(url)
        return try? HAConnectionInfo(url: url, userAgent: "FentonHome")
    }

    // MARK: - Lifecycle

    /// Opens the websocket and subscribes to entity states. Safe to call repeatedly.
    /// - Parameter subscribingToStates: Also subscribe to every entity's state. A notification extension that only
    ///   sends a command (a camera's stream) passes false, so it stays inside its memory limit.
    public func connect(subscribingToStates: Bool = true) {
        wantsConnection = true
        if !isOffline {
            if case .disconnected(reason: .disconnected) = connection.state {
                // No socket to swap: HAKit opens one on the route's URL (the public one after a stop or background).
                connection.connect()
            } else {
                feed { $0.connectRequested() }
            }
            refreshRoute()
        }
        guard subscribingToStates, statesSubscription == nil else { return }
        statesSubscription = Self.subscribeToStates(on: connection, for: self)
    }

    /// Closes the websocket and saves the snapshot. The store keeps its values so the UI does not blank.
    public func disconnect() {
        wantsConnection = false
        routeTask?.cancel()
        routeTask = nil
        // The router drops the pending switch, so it cannot think one is still waiting.
        feed { _ in [] }
        switchTask?.cancel()
        switchTask = nil
        // A home address is not trusted across a stop: the next connect starts public and finds home again.
        route?.reset()
        saveSnapshotNow()
        statesSubscription?.cancel()
        statesSubscription = nil
        connection.disconnect()
    }

    /// Applies a network path change. Offline closes the socket so HAKit stops retrying with backoff; online reopens it at
    /// once (no waiting out a backoff) and re-checks the route. A no-op unless the state changed.
    func setOnline(_ online: Bool) {
        guard isOffline == online else { return }
        isOffline = !online
        PushTrace.shared.record("connection: network \(online ? "online" : "offline")")
        guard wantsConnection else { return }
        if online {
            connection.disconnect()
            connection.connect()
            refreshRoute()
        } else {
            routeTask?.cancel()
            routeTask = nil
            feed { _ in [] }
            switchTask?.cancel()
            switchTask = nil
            connection.disconnect()
        }
        refreshStatus()
    }

    /// The app left the foreground. Forgets the home address now, because the process may be suspended before
    /// ``disconnect()`` ever runs and the phone may wake on another network: HAKit's retry then reads the public URL
    /// instead of sending the token in the clear to whatever answers at the old home address. A socket already open
    /// stays as it is (it dies by itself on another network and ``ConnectionRouter/socketFailed()`` handles that).
    public func didEnterBackground() {
        route?.reset()
    }

    /// Saves the snapshot immediately (entering background).
    public func saveSnapshotNow() {
        saveTask?.cancel()
        saveTask = nil
        try? snapshotCache.save(Array(store.allValues.values), server: server)
    }

    // MARK: - Route

    /// Checks whether Home Assistant answers on the home network and, when it does, moves the socket there
    /// (``homeWasFound()``). Runs on every connect and network change; the current socket keeps working meanwhile.
    public func refreshRoute() {
        guard let route else { return }
        routeTask?.cancel()
        let confirmHome: @Sendable () async -> Bool = { [weak self] in await self?.isHomeConfirmedOverPublicURL() ?? false }
        routeTask = Task { [weak self] in
            let changed = await route.refresh(confirmHome: confirmHome)
            guard changed, !Task.isCancelled else { return }
            self?.homeWasFound()
        }
    }

    /// Whether Home Assistant says the signed-in person is home, from live states that came over the public URL.
    /// The route asks this only before it has pinned the server's instance id, so a network that merely advertises
    /// our server can't receive the token.
    func isHomeConfirmedOverPublicURL() async -> Bool {
        guard route?.isLocal == false, store.freshness == .live, let user = try? await currentUser() else { return false }
        // Re-checked after the await: the states must still be ones the public URL delivered.
        guard route?.isLocal == false else { return false }
        return store.allValues.values.contains { entity in
            entity.entityId.hasPrefix("person.") && entity.attributes["user_id"]?.string == user.id && entity.state == "home"
        }
    }

    /// A new network (owner, 2026-10-27: no churn; refined 2026-10-28).
    ///
    /// The router answers with `.forgetHome` and `.checkRoute`, and, only for a socket on a home address, a reconnect on
    /// the public URL (that socket cannot work any more). A public socket stays. Forgetting the address is required so
    /// a connect on another network never sends the token to whatever answers at the old home address.
    func networkDidChange() {
        feed { $0.networkChanged() }
    }

    /// The route check found the home address (``ConnectionRouter/homeFound(url:)``).
    func homeWasFound() {
        guard let route, route.isLocal else { return }
        let url = route.currentURL
        feed { $0.homeFound(url: url) }
    }

    // MARK: - Router adapter

    /// Brings the router up to date with what this class owns (the recorded socket URL, the socket state, the route, the
    /// wants and offline flags), gives it one event and performs what it returns. State is read live, as the policy
    /// always did: HAKit's notifications arrive a hop later than the state they report.
    private func feed(_ event: (inout ConnectionRouter) -> [ConnectionRouter.Action]) {
        var actions = router.wantsConnection(wantsConnection)
        actions += router.online(!isOffline)
        router.socketOpened(url: socketURL.value)
        router.routeIs(route?.isLocal == true ? route?.currentURL : nil)
        if case .ready = connection.state { router.socketReady() } else { router.socketNotReady() }
        actions += event(&router)
        perform(actions)
    }

    private func perform(_ actions: [ConnectionRouter.Action]) {
        for action in actions {
            switch action {
            case .forgetHome:
                route?.reset()
            case .checkRoute:
                refreshRoute()
            case let .reconnect(url):
                switchTask?.cancel()
                switchTask = nil
                // Recorded now: HAKit may read the connection info a moment later, and a second failure notice must
                // already see the new URL.
                socketURL.note(url)
                reconnectOnRoute()
            case let .scheduleSwitchCheck(delay):
                switchTask?.cancel()
                switchTask = Task { [weak self] in
                    if delay > .zero { try? await Task.sleep(for: delay) }
                    guard !Task.isCancelled, let self else { return }
                    self.switchTask = nil
                    let idle = Duration.seconds(min(self.scrollActivity.idleDuration, 3_600))
                    self.feed { $0.tick(idle: idle) }
                }
            case .cancelSwitch:
                switchTask?.cancel()
                switchTask = nil
            case .connect:
                connection.connect()
            }
        }
    }

    /// Reconnects on the route's current URL (``reconnect()``: disconnect, then connect), counting which URL it chose.
    private func reconnectOnRoute() {
        guard wantsConnection, !isOffline else { return }
        Telemetry.count(route?.isLocal == true ? "connection.route.local" : "connection.route.public")
        reconnect()
    }

    // MARK: - Actions

    /// Calls a Home Assistant service.
    /// - Parameters:
    ///   - domain: e.g. `light`.
    ///   - service: e.g. `toggle`.
    ///   - data: Service data, including `entity_id`.
    public func callService(_ domain: String, _ service: String, data: [String: any Sendable] = [:]) async throws {
        let request = HATypedRequest<HAResponseVoid>.callService(
            domain: .init(rawValue: domain),
            service: .init(rawValue: service),
            data: data
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(request) { @Sendable result in
                switch result {
                case .success: continuation.resume()
                case let .failure(error): continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Sends a light power or brightness command (``LightControl``).
    public func send(_ command: LightControl.Command) async throws {
        try await callService(command.domain, command.service, data: command.serviceData)
    }

    /// Convenience for `<domain>.toggle` on one entity. Not for lights: Presence Based Lighting reverts
    /// toggles in empty rooms, so lights use ``send(_:)`` with ``LightControl``.
    public func toggle(_ entityId: String) async throws {
        let domain = String(entityId.prefix { $0 != "." })
        try await callService(domain, "toggle", data: ["entity_id": entityId])
    }

    // MARK: - Cameras

    /// Asks Home Assistant for a camera's HLS stream (`camera/stream`).
    /// - Parameter entityId: The camera entity.
    /// - Returns: The tokenized playlist path, e.g. `/api/hls/<token>/master_playlist.m3u8`.
    public func cameraStreamPath(entityId: String) async throws -> String {
        try await requestString("camera/stream", data: ["entity_id": entityId, "format": "hls"], field: "url",
                                timeout: Self.streamCommandTimeout)
    }

    /// Signs a server path so a client without the auth header (a raw websocket) can open it (`auth/sign_path`).
    /// - Parameters:
    ///   - path: The path to sign, e.g. ``CameraStreamEndpoints/webRTCSocketPath``.
    ///   - expires: Seconds the signature stays valid; it is only checked when the path is opened.
    /// - Returns: The path with its `authSig` query.
    public func signPath(_ path: String, expires: Int = 30) async throws -> String {
        try await requestString("auth/sign_path", data: ["path": path, "expires": expires], field: "path",
                                timeout: Self.streamCommandTimeout)
    }

    /// How long a camera's stream commands may go unanswered. HAKit silently drops a command caught by a socket
    /// reset, so without this a camera started across a reconnect waited forever (owner report 2026-10-16).
    static let streamCommandTimeout: Duration = .seconds(10)

    /// Error for a websocket command whose result lacks the expected field.
    public struct UnexpectedResponse: Error, Equatable {
        /// The command that answered unexpectedly.
        public let command: String
    }

    // MARK: - Private

    /// Sends a websocket command once (no retry across reconnects) and returns one string field of its result.
    private func requestString(_ command: String, data: [String: any Sendable], field: String, timeout: Duration? = nil) async throws -> String {
        guard case let .dictionary(values) = try await sendCommand(command, data: data, timeout: timeout), let value = values[field] as? String else {
            throw UnexpectedResponse(command: command)
        }
        return value
    }

    /// What a delivery changed, ready to apply on the main thread.
    struct Applied: Sendable {
        var changed: [EntityState]
        var removed: [String]
        var isFirst: Bool
        /// Entities in the house after this delivery (what "most of the house changed" is measured against).
        var houseCount = 0
    }

    /// Subscribes to `subscribe_entities` once for this socket and applies each message as a diff on ``deltaQueue``.
    ///
    /// HAKit restarts the subscription itself when the socket reconnects and calls `initiated` once per socket, which is when
    /// the engine learns that the next message is a full set. Built outside the main actor on purpose: a closure written in
    /// ``connect(subscribingToStates:)`` would inherit its isolation, and HAKit calls it on ``deltaQueue``, where Swift traps a
    /// main-actor closure.
    ///
    /// HAKit retries a request on a new socket only for `retryDuration` (10 s by default) after it was made; its own caches switch
    /// retrying off and resend on every state transition instead (the double delivery this replaces). This subscription lives as
    /// long as the connection does, so it never expires: one resend per socket, made by HAKit when the socket is ready.
    nonisolated private static func subscribeToStates(on connection: HAConnection, for owner: HassConnection) -> HACancellable {
        var subscription = HATypedSubscription<HACompressedStatesUpdates>.subscribeEntities(data: [:])
        subscription.request.shouldRetry = true
        subscription.request.retryDuration = nil
        return connection.subscribe(
            to: subscription,
            initiated: { [weak owner] result in
                guard case .success = result else { return }
                owner?.subscriptionStarted()
            },
            handler: { [weak owner] _, updates in owner?.receive(updates) }
        )
    }

    /// The server accepted the subscription on a (new) socket. Runs on ``deltaQueue``.
    nonisolated func subscriptionStarted() {
        Telemetry.count("entity.subscribes")
        engine.subscriptionStarted()
    }

    /// Merges one `subscribe_entities` message and, when it changed anything, queues one hop to the main thread behind the
    /// messages already waiting, so a burst is applied once. Costs work in proportion to the message. Runs on ``deltaQueue`` only.
    nonisolated func receive(_ updates: HACompressedStatesUpdates) {
        let change = engine.apply(updates)
        Telemetry.count("entity.received")
        if change.isReplacement { Telemetry.count("entity.fullSets") }
        batch.merge(change, houseCount: engine.entities.count)
        guard !batch.isEmpty, !flushScheduled else { return }
        flushScheduled = true
        deltaQueue.async { [weak self] in self?.flush() }
    }

    /// Hands what the engine changed so far to the main actor. Runs on ``deltaQueue`` only.
    nonisolated private func flush() {
        flushScheduled = false
        guard !batch.isEmpty else { return }
        let applied = batch.applied
        batch = EntityDeltaBatch()
        DispatchQueue.main.async { MainActor.assumeIsolated { self.apply(applied) } }
    }

    /// Applies one delivery's changes to the store. The only part of a delivery that runs on the main thread.
    ///
    /// Counts what the delivery cost for the scroll cost probe: entities compared here, boxes that really changed, deliveries
    /// that carried most of the house, and the thread's CPU time (``ScrollCostProbe``; `.agents/testing/apple/performance.md`).
    func apply(_ delta: Applied) {
        let cpuStart = ProcessCPU.currentThreadSeconds()
        let interval = Telemetry.begin(Telemetry.Name.entityUpdate)
        let boxChangesBefore = store.publishedChangeCount
        var displaced: [EntityState]
        if delta.isFirst {
            // The first live set replaces the disk snapshot, dropping entities the server no longer has.
            displaced = store.replaceAll(delta.changed, freshness: .live)
            Telemetry.count("entity.firstLiveMs", by: Int(ProcessCPU.secondsSinceProcessStart() * 1000))
            // Live presence can now confirm home for a route that has not seen this server at home yet.
            if route?.isLocal == false { refreshRoute() }
        } else {
            displaced = store.apply(delta.changed, removing: delta.removed, freshness: .live)
        }
        Telemetry.end(interval, value: Double(delta.changed.count + delta.removed.count))
        Telemetry.count("entity.deliveries")
        Telemetry.count("entity.changed", by: delta.changed.count)
        Telemetry.count("entity.compared", by: delta.changed.count + delta.removed.count)
        Telemetry.count("entity.boxChanges", by: store.publishedChangeCount - boxChangesBefore)
        if delta.houseCount > 0, (delta.changed.count + delta.removed.count) * 2 > delta.houseCount { Telemetry.count("entity.full") }
        scheduleSnapshotSave()
        if !displaced.isEmpty {
            // The values this delivery replaced are freed on the delta queue, not here.
            let carried = displaced
            displaced = []
            deltaQueue.async { withExtendedLifetime(carried) {} }
        }
        Telemetry.count("entity.mainUs", by: Int((ProcessCPU.currentThreadSeconds() - cpuStart) * 1_000_000))
    }

    private func scheduleSnapshotSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.snapshotDebounce)
            guard !Task.isCancelled, let self else { return }
            self.saveTask = nil
            // Encoding thousands of entities took tens of milliseconds on the main thread mid-scroll; only the
            // copy of the values happens here. Entering background still saves synchronously.
            let entities = Array(self.store.allValues.values)
            let cache = self.snapshotCache
            let server = self.server
            Task.detached(priority: .utility) {
                Telemetry.measure("SnapshotSave") { try? cache.save(entities, server: server) }
            }
        }
    }

    func refreshStatus() {
        let next: Status
        var failed = false
        switch connection.state {
        case .connecting, .authenticating: next = .connecting
        case let .ready(version): next = .connected(version: version)
        case let .disconnected(reason):
            switch reason {
            case .disconnected: next = .disconnected
            case .rejected: next = .rejected
            case .waitingToReconnect:
                next = .waitingToReconnect
                // A failed socket on a home address falls back to the public URL (the router forgets home); a public
                // socket's retry needs no reset, which would discard a correct check in flight.
                failed = true
            }
        }
        guard status != next else { return }
        defer { if failed { feed { $0.socketFailed() } } }
        let previous = status
        status = next
        PushTrace.shared.record("connection: \(previous) -> \(next)")
        // Reconnect start to live: opens when the socket starts or fails, closes when it answers. A socket that is
        // closed on purpose (background, sign-out) or refused abandons the interval rather than timing it.
        switch next {
        case .connecting, .waitingToReconnect: Telemetry.beginTracked(Telemetry.Name.reconnect)
        case .connected: Telemetry.endTracked(Telemetry.Name.reconnect)
        case .disconnected, .rejected: Telemetry.cancelTracked(Telemetry.Name.reconnect)
        }
        if case .connected = next {
            feed { $0.socketBecameReady() }
            // The full set follows: what it changes is a reapply, not something that happened on screen.
            store.noteReapply()
            NotificationCenter.default.post(name: Self.didBecomeReadyNotification, object: self)
        }
    }
}

// MARK: - SocketURLRecord

/// The URL the websocket was last opened with. HAKit reads the connection info on its own queue at each connect and
/// the main actor reads this, so the value sits behind a lock.
final class SocketURLRecord: Sendable {
    private let url = OSAllocatedUnfairLock<URL?>(initialState: nil)

    /// The URL of the current (or last) socket; nil before the first connect.
    var value: URL? { url.withLock { $0 } }

    func note(_ newValue: URL) { url.withLock { $0 = newValue } }
}
