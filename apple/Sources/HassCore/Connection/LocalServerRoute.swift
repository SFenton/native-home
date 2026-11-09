import Foundation
@preconcurrency import Network
import HassTelemetry
import os

/// Where the websocket opens: Home Assistant's own address on the home network when the phone can reach it there,
/// otherwise the server's public URL.
///
/// At home the public URL still leaves the house through Cloudflare and comes back (40–65 ms a request, measured
/// 2026-10-15), while Home Assistant's home network address answers in about 14 ms. The route finds the server by
/// its zeroconf advertisement (`_home-assistant._tcp`), accepts it only when the advertisement names this server's
/// public URL, points at a private address and carries this server's instance id, and checks that the address
/// answers before using it. Anything else, or any network change, falls back to the public URL. See
/// `.agents/platforms/apple/connection-lifecycle.md`.
///
/// The access token goes to the home address over plain HTTP, so any Wi-Fi network (a café's too) must not be able
/// to pose as home. The advertisement's `uuid` is only ever sent on the home network, so the route pins it the
/// first time, and only while Home Assistant (over the public TLS connection) says the signed-in person is home;
/// after that, an advertisement without the pinned id is ignored.
public final class LocalServerRoute: Sendable {
    /// Home Assistant's zeroconf service type (listed in `NSBonjourServices`).
    public static let serviceType = "_home-assistant._tcp"
    /// How long to listen for the advertisement.
    static let browseTimeout: Duration = .milliseconds(1500)
    /// How long the home network address has to answer.
    static let probeTimeout: Duration = .milliseconds(1500)

    /// The signed-in server; its ``HassServer/baseURL`` stays the app's identity for caches and links.
    public let server: HassServer

    private let finder: any LocalServerFinding
    private let watcher: any NetworkPathWatching
    private let pins: any LocalServerPinStore
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var localURL: URL?
        /// Bumped by ``reset()`` so a check that started on the old network can't apply its answer.
        var generation = 0
    }

    /// Creates a route for a server.
    /// - Parameters:
    ///   - server: The signed-in server.
    ///   - finder: Finds and checks the home network address (Bonjour and HTTP in the app, a fake in tests).
    ///   - watcher: Reports network changes.
    ///   - pins: Remembers the server's instance id once it was seen at home.
    public init(server: HassServer, finder: any LocalServerFinding = BonjourLocalServerFinder(),
                watcher: any NetworkPathWatching = SystemNetworkPathWatcher(),
                pins: any LocalServerPinStore = UserDefaultsLocalServerPinStore()) {
        self.server = server
        self.finder = finder
        self.watcher = watcher
        self.pins = pins
    }

    /// The URL the websocket and REST requests should use now.
    public var currentURL: URL { state.withLock { $0.localURL } ?? server.baseURL }

    /// Whether the route currently uses the home network address.
    public var isLocal: Bool { state.withLock { $0.localURL != nil } }

    /// Calls `onChange` on every network change (and once when watching starts).
    public func startWatching(_ onChange: @escaping @Sendable () -> Void) {
        watcher.start(onChange)
    }

    /// Looks for the server on the current network and moves the route to its home network address, or back.
    /// - Parameter confirmHome: Asked only before the server's instance id is pinned: whether Home Assistant, over
    ///   the public URL, says the signed-in person is home. The default never pins.
    /// - Returns: Whether ``currentURL`` changed.
    @discardableResult
    public func refresh(confirmHome: @escaping @Sendable () async -> Bool = { false }) async -> Bool {
        let generation = state.withLock { $0.generation }
        let next = await findLocalURL(confirmHome: confirmHome)
        // A cancelled check stopped listening early; its empty answer says nothing about the network.
        guard !Task.isCancelled else { return false }
        return state.withLock { state in
            guard state.generation == generation, state.localURL != next else { return false }
            state.localURL = next
            return true
        }
    }

    /// The home network address, when the server advertises one here that it can be trusted with and it answers.
    private func findLocalURL(confirmHome: @Sendable () async -> Bool) async -> URL? {
        guard watcher.isOnLocalNetwork else { return nil }
        let server = server
        let pinned = pins.instanceID(for: server)
        guard let advertisement = await finder.firstMatch(timeout: Self.browseTimeout, accept: {
                  LocalServerMatch.localURL(for: server, advertisement: $0) != nil && LocalServerMatch.isPinned($0, to: pinned)
              }),
              let url = LocalServerMatch.localURL(for: server, advertisement: advertisement),
              let instanceID = advertisement.instanceID else { return nil }
        if pinned == nil {
            guard await confirmHome() else { return nil }
        }
        guard await finder.answers(url, timeout: Self.probeTimeout) else { return nil }
        if pinned == nil { pins.save(instanceID, for: server) }
        return url
    }

    /// Drops the home network address (the network changed or the socket failed).
    /// - Returns: Whether the route was using it.
    @discardableResult
    public func reset() -> Bool {
        state.withLock { state in
            state.generation += 1
            defer { state.localURL = nil }
            return state.localURL != nil
        }
    }

    /// Whether the app looks for the home network address this launch.
    ///
    /// Off for UI test launches (a reset, a test token or a gallery page) so journeys always use the server they
    /// were given, unless `FENTON_LOCAL_ROUTE=1`; `FENTON_LOCAL_ROUTE=0` turns it off anywhere.
    public static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        switch environment["FENTON_LOCAL_ROUTE"] {
        case "1": return true
        case "0": return false
        default:
            let testLaunch = ["FENTON_UITEST_RESET", "FENTON_HASS_TOKEN", "FENTON_GALLERY"].contains { environment[$0]?.isEmpty == false }
            return !testLaunch
        }
    }
}

// MARK: - Advertisement

/// Home Assistant's zeroconf advertisement: the URLs in its `_home-assistant._tcp` TXT record.
public struct LocalServerAdvertisement: Equatable, Sendable {
    /// `uuid`: the Home Assistant instance's id, only ever advertised on the home network.
    public var instanceID: String?
    /// `internal_url`: the address on the home network (a private host and Home Assistant's port).
    public var internalURL: URL?
    /// `external_url`: the public URL.
    public var externalURL: URL?
    /// `base_url`: the URL Home Assistant prefers (public when one is set).
    public var baseURL: URL?

    /// Creates an advertisement.
    public init(instanceID: String? = nil, internalURL: URL? = nil, externalURL: URL? = nil, baseURL: URL? = nil) {
        self.instanceID = instanceID
        self.internalURL = internalURL
        self.externalURL = externalURL
        self.baseURL = baseURL
    }

    /// Reads a TXT record's keys.
    public init(txt: [String: String]) {
        self.init(
            instanceID: txt["uuid"].flatMap { $0.isEmpty ? nil : $0 },
            internalURL: txt["internal_url"].flatMap(URL.init(string:)),
            externalURL: txt["external_url"].flatMap(URL.init(string:)),
            baseURL: txt["base_url"].flatMap(URL.init(string:))
        )
    }
}

/// Decides whether an advertisement is the signed-in server's home network address.
public enum LocalServerMatch {
    /// The advertisement's internal URL when it belongs to `server` and points at a private address.
    ///
    /// The bearer token goes to this address over plain HTTP, so it must be advertised by a server that names our
    /// public URL, and it must be a home network address (private IPv4, IPv6 unique-local or link-local, or a
    /// `.local` name), never somewhere on the internet.
    public static func localURL(for server: HassServer, advertisement: LocalServerAdvertisement) -> URL? {
        let claimsServer = [advertisement.externalURL, advertisement.baseURL].contains { $0.map { isSameOrigin($0, server.baseURL) } ?? false }
        guard claimsServer, let url = advertisement.internalURL, let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = url.host(), isPrivateHost(host),
              !isSameOrigin(url, server.baseURL) else { return nil }
        return HassServer(baseURL: url).baseURL
    }

    /// Whether the advertisement carries the pinned instance id; any id passes before one is pinned.
    static func isPinned(_ advertisement: LocalServerAdvertisement, to pinned: String?) -> Bool {
        guard let id = advertisement.instanceID else { return false }
        return pinned.map { $0 == id } ?? true
    }

    /// Same scheme, host and port (default ports filled in).
    static func isSameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        func origin(_ url: URL) -> String? {
            guard let scheme = url.scheme?.lowercased(), let host = url.host()?.lowercased() else { return nil }
            let port = url.port ?? (scheme == "https" ? 443 : 80)
            return "\(scheme)://\(host):\(port)"
        }
        return origin(lhs) != nil && origin(lhs) == origin(rhs)
    }

    /// A host only reachable on the local network.
    static func isPrivateHost(_ host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host.hasSuffix(".local") { return true }
        if host.contains(":") {
            // IPv6: unique-local (the fc and fd prefixes) or link-local (fe80 to febf).
            return host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe8") || host.hasPrefix("fe9")
                || host.hasPrefix("fea") || host.hasPrefix("feb")
        }
        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (192, 168), (169, 254): return true
        case let (172, second): return (16...31).contains(second)
        default: return false
        }
    }
}

// MARK: - Seams

/// Finds Home Assistant on the current network and checks an address answers.
public protocol LocalServerFinding: Sendable {
    /// Listens for advertisements for up to `timeout`, returning the first one `accept` takes.
    func firstMatch(timeout: Duration, accept: @escaping @Sendable (LocalServerAdvertisement) -> Bool) async -> LocalServerAdvertisement?
    /// Whether `url` answers as Home Assistant within `timeout`.
    func answers(_ url: URL, timeout: Duration) async -> Bool
}

/// Remembers each server's instance id (the advertisement's `uuid`) once it was seen at home.
public protocol LocalServerPinStore: Sendable {
    /// The pinned id, or nil before the first time at home.
    func instanceID(for server: HassServer) -> String?
    /// Pins the id.
    func save(_ instanceID: String, for server: HassServer)
}

/// Reports whether the phone is on a local network (Wi-Fi or Ethernet) and when that changes.
public protocol NetworkPathWatching: Sendable {
    /// The current path uses Wi-Fi or Ethernet.
    var isOnLocalNetwork: Bool { get }
    /// Starts watching; `onChange` runs when the network changes (``NetworkPathSignature``), not on every path update.
    func start(_ onChange: @escaping @Sendable () -> Void)
}

/// What identifies the network the phone is on, for deciding whether a path update is a new network.
///
/// `NWPathMonitor` also reports updates that leave the network as it was: a tunnel or the Mac's USB link coming and
/// going, cellular attaching beside Wi-Fi, a constrained or expensive flag flipping. Each one used to drop the home
/// address and reconnect twice (public, then home again), a 50 ms main-thread stall each, on a phone lying still
/// (phone run, 2026-10-27: 1 to 3 reconnects every 8 s). Only the fields here count: whether the path works, whether
/// it is local, the interface it prefers, and its gateways (another Wi-Fi network keeps `en0` but not its router).
public struct NetworkPathSignature: Equatable, Sendable {
    public var isSatisfied: Bool
    public var isLocal: Bool
    /// The preferred interface, `type:name` (for example `wifi:en0`); nil without one.
    public var primaryInterface: String?
    /// The path's gateways, sorted.
    public var gateways: [String]

    public init(isSatisfied: Bool, isLocal: Bool, primaryInterface: String?, gateways: [String]) {
        self.isSatisfied = isSatisfied
        self.isLocal = isLocal
        self.primaryInterface = primaryInterface
        self.gateways = gateways.sorted()
    }
}

/// Passes on a path update only when its ``NetworkPathSignature`` differs from the last one seen.
///
/// - Important: This is a de-duplication filter, **not a network identity**. Two Wi-Fi networks that share a gateway
///   address (many routers share one factory default) have equal signatures, so a move between them is
///   not reported. Nothing may trust a home address because the signature did not change: the connection forgets the
///   home address when the app goes to the background or stops (``HassConnection/didEnterBackground()``), and only
///   the route check (pinned instance id, `manifest.json`) brings it back.
public struct NetworkPathChangeFilter: Sendable {
    private var last: NetworkPathSignature?

    public init() {}

    /// Records `signature`; true when it is the first or differs from the previous one.
    public mutating func isChange(_ signature: NetworkPathSignature) -> Bool {
        defer { last = signature }
        return last != signature
    }
}

// MARK: - System implementations

/// Browses `_home-assistant._tcp` with Bonjour and checks addresses with `GET /manifest.json`.
public struct BonjourLocalServerFinder: LocalServerFinding {
    private static let queue = DispatchQueue(label: "com.sfenton.home.local-server")
    private let session: URLSession

    /// Creates a finder.
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    public func firstMatch(timeout: Duration, accept: @escaping @Sendable (LocalServerAdvertisement) -> Bool) async -> LocalServerAdvertisement? {
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: LocalServerRoute.serviceType, domain: nil), using: .tcp)
        let found = OSAllocatedUnfairLock<LocalServerAdvertisement?>(initialState: nil)
        browser.browseResultsChangedHandler = { results, _ in
            for result in results {
                guard case let .bonjour(record) = result.metadata else { continue }
                let advertisement = LocalServerAdvertisement(txt: record.dictionary)
                guard accept(advertisement) else { continue }
                found.withLock { $0 = $0 ?? advertisement }
            }
        }
        browser.start(queue: Self.queue)
        defer { browser.cancel() }
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline, !Task.isCancelled {
            if let advertisement = found.withLock({ $0 }) { return advertisement }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return found.withLock { $0 }
    }

    public func answers(_ url: URL, timeout: Duration) async -> Bool {
        var request = URLRequest(url: url.appending(path: "manifest.json"))
        let (seconds, attoseconds) = timeout.components
        request.timeoutInterval = Double(seconds) + Double(attoseconds) / 1e18
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}

/// Pins in `UserDefaults`, keyed by the server's public URL. The id is not a secret: it only shows that the
/// advertisement comes from the house's own network.
public struct UserDefaultsLocalServerPinStore: LocalServerPinStore {
    /// Creates the store.
    public init() {}

    public func instanceID(for server: HassServer) -> String? {
        UserDefaults.standard.string(forKey: Self.key(for: server))
    }

    public func save(_ instanceID: String, for server: HassServer) {
        UserDefaults.standard.set(instanceID, forKey: Self.key(for: server))
    }

    private static func key(for server: HassServer) -> String { "localServerRoute.instanceID.\(server.baseURL.absoluteString)" }
}

/// Watches the network path with `NWPathMonitor`.
public final class SystemNetworkPathWatcher: NetworkPathWatching, @unchecked Sendable {
    // Unchecked: `monitor` is configured once in `start` (guarded by `started`) and only touched again by `deinit`.
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.sfenton.home.network-path")
    private let local = OSAllocatedUnfairLock(initialState: false)
    private let started = OSAllocatedUnfairLock(initialState: false)
    private let filter = OSAllocatedUnfairLock(initialState: NetworkPathChangeFilter())

    /// Creates a watcher; nothing happens until ``start(_:)``.
    public init() {}

    deinit { monitor.cancel() }

    public var isOnLocalNetwork: Bool { local.withLock { $0 } }

    public func start(_ onChange: @escaping @Sendable () -> Void) {
        let first = started.withLock { started in
            defer { started = true }
            return !started
        }
        guard first else { return }
        monitor.pathUpdateHandler = { [local, filter] path in
            let isLocal = path.status == .satisfied && (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))
            local.withLock { $0 = isLocal }
            Telemetry.count("connection.pathUpdates")
            let signature = NetworkPathSignature(
                isSatisfied: path.status == .satisfied, isLocal: isLocal,
                primaryInterface: path.availableInterfaces.first.map { "\($0.type):\($0.name)" },
                gateways: path.gateways.map { "\($0)" }
            )
            guard filter.withLock({ $0.isChange(signature) }) else { return }
            Telemetry.count("connection.networkChanges")
            onChange()
        }
        monitor.start(queue: queue)
    }
}
