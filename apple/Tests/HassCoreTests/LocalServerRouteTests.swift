import Foundation
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
import HassTelemetry
import os
import Testing

/// The advertisement Home Assistant sent on the home network (Mac, 2026-10-15).
private let homeTXT = [
    "location_name": "Home", "version": "2026.10.1", "uuid": homeID,
    "external_url": "https://home.example.com", "internal_url": "http://169.254.7.11:8123",
    "base_url": "https://home.example.com",
]
private let homeURL = URL(string: "http://169.254.7.11:8123")!
private let homeID = "a1b2a1b2a1b2a1b2a1b2a1b2a1b2a1b2"

/// A route for the home server; pinned to the home instance unless a test is about pinning.
private func makeRoute(finder: FakeFinder, watcher: FakeWatcher = FakeWatcher(local: true),
                       pins: FakePins = FakePins(homeID)) -> LocalServerRoute {
    LocalServerRoute(server: .example, finder: finder, watcher: watcher, pins: pins)
}

/// Answers with fixed advertisements and a fixed probe result.
private final class FakeFinder: LocalServerFinding, Sendable {
    private let advertisements: [LocalServerAdvertisement]
    private let reachableNow: OSAllocatedUnfairLock<Bool>
    private let probes = OSAllocatedUnfairLock(initialState: [URL]())
    /// Runs before the finder answers, so a test can change the network mid-check.
    private let beforeAnswer: (@Sendable () -> Void)?

    init(_ advertisements: [LocalServerAdvertisement], reachable: Bool = true, beforeAnswer: (@Sendable () -> Void)? = nil) {
        self.advertisements = advertisements
        self.reachableNow = OSAllocatedUnfairLock(initialState: reachable)
        self.beforeAnswer = beforeAnswer
    }

    var probed: [URL] { probes.withLock { $0 } }

    func firstMatch(timeout: Duration, accept: @escaping @Sendable (LocalServerAdvertisement) -> Bool) async -> LocalServerAdvertisement? {
        beforeAnswer?()
        return advertisements.first(where: accept)
    }

    func answers(_ url: URL, timeout: Duration) async -> Bool {
        probes.withLock { $0.append(url) }
        return reachableNow.withLock { $0 }
    }

    /// Whether home answers from now on (a test can take it away after a failover).
    func setReachable(_ value: Bool) { reachableNow.withLock { $0 = value } }
}

/// Pins kept in memory.
private final class FakePins: LocalServerPinStore, Sendable {
    private let pinned: OSAllocatedUnfairLock<String?>

    init(_ pinned: String? = nil) { self.pinned = OSAllocatedUnfairLock(initialState: pinned) }

    var current: String? { pinned.withLock { $0 } }

    func instanceID(for server: HassServer) -> String? { pinned.withLock { $0 } }

    func save(_ instanceID: String, for server: HassServer) { pinned.withLock { $0 = instanceID } }
}

/// Counts how often the route asks whether Home Assistant says the person is home.
private final class HomeCheck: Sendable {
    private let answer: Bool
    private let asks = OSAllocatedUnfairLock(initialState: 0)

    init(_ answer: Bool) { self.answer = answer }

    var count: Int { asks.withLock { $0 } }

    var closure: @Sendable () async -> Bool {
        { [self] in
            asks.withLock { $0 += 1 }
            return answer
        }
    }
}

/// A network path the test sets by hand.
private final class FakeWatcher: NetworkPathWatching, Sendable {
    private let onLocalNetwork: OSAllocatedUnfairLock<Bool>
    private let handler = OSAllocatedUnfairLock<(@Sendable () -> Void)?>(initialState: nil)

    init(local: Bool) { self.onLocalNetwork = OSAllocatedUnfairLock(initialState: local) }

    var isOnLocalNetwork: Bool { onLocalNetwork.withLock { $0 } }

    func start(_ onChange: @escaping @Sendable () -> Void) { handler.withLock { $0 = onChange } }

    /// Moves to another network without reporting it (a path update the filter takes for the same network).
    func setLocal(_ isLocal: Bool) { onLocalNetwork.withLock { $0 = isLocal } }

    /// Moves to another network and reports it.
    func change(local isLocal: Bool) {
        onLocalNetwork.withLock { $0 = isLocal }
        handler.withLock { $0 }?()
    }
}

struct LocalServerAdvertisementTests {
    @Test func readsTheTXTRecord() {
        let ad = LocalServerAdvertisement(txt: homeTXT)
        #expect(ad.internalURL == homeURL)
        #expect(ad.instanceID == homeID)
        #expect(ad.externalURL == URL(string: "https://home.example.com"))
        #expect(ad.baseURL == URL(string: "https://home.example.com"))
        #expect(LocalServerAdvertisement(txt: [:]) == LocalServerAdvertisement())
        #expect(LocalServerAdvertisement(txt: ["uuid": ""]).instanceID == nil)
    }

    @Test func pinnedInstance() {
        let home = LocalServerAdvertisement(txt: homeTXT)
        #expect(LocalServerMatch.isPinned(home, to: homeID))
        #expect(LocalServerMatch.isPinned(home, to: nil), "any id before the first time at home")
        var impostor = home
        impostor.instanceID = "c3d4c3d4c3d4c3d4c3d4c3d4c3d4c3d4"
        #expect(!LocalServerMatch.isPinned(impostor, to: homeID), "another network posing as home")
        impostor.instanceID = nil
        #expect(!LocalServerMatch.isPinned(impostor, to: nil), "no id, nothing to pin")
    }

    @Test func acceptsOurServersHomeAddress() {
        let ad = LocalServerAdvertisement(txt: homeTXT)
        #expect(LocalServerMatch.localURL(for: .example, advertisement: ad) == homeURL)
        let onlyBase = LocalServerAdvertisement(internalURL: homeURL, baseURL: HassServer.example.baseURL)
        #expect(LocalServerMatch.localURL(for: .example, advertisement: onlyBase) == homeURL, "base_url alone identifies the server")
        let trailingSlash = LocalServerAdvertisement(internalURL: URL(string: "http://169.254.7.11:8123/")!,
                                                     externalURL: URL(string: "https://Home.Example.com:443/")!)
        #expect(LocalServerMatch.localURL(for: .example, advertisement: trailingSlash) == homeURL)
    }

    @Test func rejectsOtherServersAndPublicAddresses() {
        let otherServer = LocalServerAdvertisement(internalURL: homeURL, externalURL: URL(string: "https://neighbor.example.com"))
        #expect(LocalServerMatch.localURL(for: .example, advertisement: otherServer) == nil, "someone else's Home Assistant")
        let unnamed = LocalServerAdvertisement(internalURL: homeURL)
        #expect(LocalServerMatch.localURL(for: .example, advertisement: unnamed) == nil, "no public URL to match")
        let publicHost = LocalServerAdvertisement(internalURL: URL(string: "http://203.0.113.9:8123"), externalURL: HassServer.example.baseURL)
        #expect(LocalServerMatch.localURL(for: .example, advertisement: publicHost) == nil, "never send the token to the internet over HTTP")
        let samePublic = LocalServerAdvertisement(internalURL: HassServer.example.baseURL, externalURL: HassServer.example.baseURL)
        #expect(LocalServerMatch.localURL(for: .example, advertisement: samePublic) == nil)
        let ftp = LocalServerAdvertisement(internalURL: URL(string: "ftp://169.254.7.11"), externalURL: HassServer.example.baseURL)
        #expect(LocalServerMatch.localURL(for: .example, advertisement: ftp) == nil)
    }

    @Test(arguments: [
        ("192.168.0.1", true), ("10.0.0.1", true), ("172.16.0.1", true), ("172.31.255.254", true), ("169.254.3.4", true),
        ("connection.route.local", true), ("homeassistant.local", true),
        ("fd00::1", true), ("[fe80::1]", true),
        ("172.32.0.1", false), ("172.15.0.1", false), ("8.8.8.8", false), ("2606:4700::6810:c96", false),
        ("home.example.com", false), ("10.9.8", false),
    ])
    func privateHosts(host: String, isPrivate: Bool) {
        #expect(LocalServerMatch.isPrivateHost(host) == isPrivate, "\(host)")
    }

    @Test func launchPolicy() {
        #expect(LocalServerRoute.isEnabled(environment: [:]))
        #expect(!LocalServerRoute.isEnabled(environment: ["FENTON_UITEST_RESET": "1"]))
        #expect(!LocalServerRoute.isEnabled(environment: ["FENTON_HASS_TOKEN": "x"]))
        #expect(!LocalServerRoute.isEnabled(environment: ["FENTON_GALLERY": "media-remote"]))
        #expect(LocalServerRoute.isEnabled(environment: ["FENTON_HASS_TOKEN": "x", "FENTON_LOCAL_ROUTE": "1"]))
        #expect(!LocalServerRoute.isEnabled(environment: ["FENTON_LOCAL_ROUTE": "0"]))
    }
}

struct LocalServerRouteTests {
    @Test func usesTheHomeAddressWhenItAnswers() async {
        let finder = FakeFinder([LocalServerAdvertisement(txt: homeTXT)])
        let route = makeRoute(finder: finder)
        #expect(route.currentURL == HassServer.example.baseURL, "public URL until a check succeeds")
        #expect(await route.refresh())
        #expect(route.currentURL == homeURL)
        #expect(route.isLocal)
        #expect(finder.probed == [homeURL])
        #expect(await route.refresh() == false, "no change on a second check")
    }

    @Test func staysPublicWhenTheHomeAddressDoesNotAnswer() async {
        let route = makeRoute(finder: FakeFinder([LocalServerAdvertisement(txt: homeTXT)], reachable: false))
        #expect(await route.refresh() == false)
        #expect(route.currentURL == HassServer.example.baseURL)
    }

    @Test func staysPublicOffWiFi() async {
        let finder = FakeFinder([LocalServerAdvertisement(txt: homeTXT)])
        let route = makeRoute(finder: finder, watcher: FakeWatcher(local: false))
        #expect(await route.refresh() == false)
        #expect(finder.probed.isEmpty, "cellular never looks for the home address")
    }

    @Test func leavingHomeDropsTheHomeAddress() async {
        let watcher = FakeWatcher(local: true)
        let route = makeRoute(finder: FakeFinder([LocalServerAdvertisement(txt: homeTXT)]), watcher: watcher)
        await route.refresh()
        watcher.change(local: false)
        #expect(route.reset())
        #expect(route.currentURL == HassServer.example.baseURL)
        #expect(await route.refresh() == false)
        #expect(route.reset() == false, "nothing to drop")
    }

    @Test func aCheckFromTheOldNetworkIsIgnored() async {
        let routeBox = OSAllocatedUnfairLock<LocalServerRoute?>(initialState: nil)
        let finder = FakeFinder([LocalServerAdvertisement(txt: homeTXT)]) { routeBox.withLock { $0 }?.reset() }
        let route = makeRoute(finder: finder)
        routeBox.withLock { $0 = route }
        #expect(await route.refresh() == false, "the network changed while the check ran")
        #expect(!route.isLocal)
    }

    @Test func refreshesOnNetworkChange() async {
        let watcher = FakeWatcher(local: true)
        let route = makeRoute(finder: FakeFinder([]), watcher: watcher)
        let calls = OSAllocatedUnfairLock(initialState: 0)
        route.startWatching { calls.withLock { $0 += 1 } }
        watcher.change(local: false)
        watcher.change(local: true)
        #expect(calls.withLock { $0 } == 2)
    }

    @Test func pinsTheServerTheFirstTimeHomeAssistantSaysYouAreHome() async {
        let pins = FakePins()
        let home = HomeCheck(true)
        let route = makeRoute(finder: FakeFinder([LocalServerAdvertisement(txt: homeTXT)]), pins: pins)
        #expect(await route.refresh(confirmHome: home.closure))
        #expect(route.isLocal)
        #expect(pins.current == homeID)
        route.reset()
        #expect(await route.refresh(confirmHome: home.closure))
        #expect(home.count == 1, "once pinned, the advertisement's id is enough")
    }

    @Test func neverPinsWithoutHomeAssistantSayingYouAreHome() async {
        let pins = FakePins()
        let finder = FakeFinder([LocalServerAdvertisement(txt: homeTXT)])
        let route = makeRoute(finder: finder, pins: pins)
        #expect(await route.refresh() == false, "the default never confirms home")
        #expect(await route.refresh(confirmHome: HomeCheck(false).closure) == false)
        #expect(!route.isLocal)
        #expect(pins.current == nil)
        #expect(finder.probed.isEmpty, "the token never goes to an unconfirmed address")
    }

    @Test func ignoresAnImpostorOncePinned() async {
        var impostor = LocalServerAdvertisement(txt: homeTXT)
        impostor.instanceID = "c3d4c3d4c3d4c3d4c3d4c3d4c3d4c3d4"
        let finder = FakeFinder([impostor])
        let home = HomeCheck(true)
        let route = makeRoute(finder: finder)
        #expect(await route.refresh(confirmHome: home.closure) == false)
        #expect(!route.isLocal)
        #expect(home.count == 0, "pinned: presence can't override the id")
        #expect(finder.probed.isEmpty)
    }

    @Test func ignoresAnAdvertisementWithoutAnID() async {
        var unnamed = LocalServerAdvertisement(txt: homeTXT)
        unnamed.instanceID = nil
        let pins = FakePins()
        let route = makeRoute(finder: FakeFinder([unnamed]), pins: pins)
        #expect(await route.refresh(confirmHome: HomeCheck(true).closure) == false)
        #expect(pins.current == nil)
    }

    @Test func doesNotPinWhenTheAddressDoesNotAnswer() async {
        let pins = FakePins()
        let route = makeRoute(finder: FakeFinder([LocalServerAdvertisement(txt: homeTXT)], reachable: false), pins: pins)
        #expect(await route.refresh(confirmHome: HomeCheck(true).closure) == false)
        #expect(pins.current == nil)
    }
}

@MainActor
struct HassConnectionRouteTests {
    @Test func connectionInfoFollowsTheRoute() async throws {
        #expect(HassConnection.connectionInfo(server: .example, route: nil)?.url == HassServer.example.baseURL)
        let route = makeRoute(finder: FakeFinder([LocalServerAdvertisement(txt: homeTXT)]))
        #expect(HassConnection.connectionInfo(server: .example, route: route)?.url == HassServer.example.baseURL)
        await route.refresh()
        let info = try #require(HassConnection.connectionInfo(server: .example, route: route))
        #expect(info.webSocketURL == URL(string: "http://169.254.7.11:8123/api/websocket"))
    }

    @Test func aFailedSocketFallsBackToThePublicURL() async throws {
        let finder = FakeFinder([LocalServerAdvertisement(txt: homeTXT)])
        let route = makeRoute(finder: finder)
        await route.refresh()
        let mock = HAMockConnection()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "route-\(UUID()).json"))
        // The socket was opened on the home address, through the real connection-info closure (it writes the record the
        // router reads), and the app wants it.
        let record = SocketURLRecord()
        mock.configuration = HAConnectionConfiguration(
            connectionInfo: { HassConnection.connectionInfo(server: .example, route: route, recordingIn: record) },
            fetchAuthToken: { $0(.success("token")) }
        )
        let connection = HassConnection(server: .example, store: EntityStore(), snapshotCache: cache, connection: mock,
                                        route: route, socketURL: record)
        connection.wantsConnection = true
        mock.connect()
        #expect(record.value == homeURL)
        // Home stops answering, so the failover re-check (rule 3) cannot flip the route straight back.
        finder.setReachable(false)
        // Not waiting for the callback queue: it is the main queue this test runs on.
        mock.setState(.disconnected(reason: .waitingToReconnect(lastError: URLError(.networkConnectionLost), atLatest: Date(), retryCount: 1)),
                      waitForQueue: false)
        for _ in 0..<100 where route.isLocal { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!route.isLocal)
        // The router moved the socket to the public URL at once (the failover reconnect), whatever state the mock then reports.
        #expect(record.value == HassServer.example.baseURL)
    }

    @Test func leavingTheNetworkDropsTheHomeAddress() async throws {
        let watcher = FakeWatcher(local: true)
        let route = makeRoute(finder: FakeFinder([LocalServerAdvertisement(txt: homeTXT)]), watcher: watcher)
        await route.refresh()
        let mock = HAMockConnection()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "route-\(UUID()).json"))
        let connection = HassConnection(server: .example, store: EntityStore(), snapshotCache: cache, connection: mock, route: route)
        watcher.change(local: false)
        for _ in 0..<100 where route.isLocal { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!route.isLocal)
        #expect(connection.route === route)
    }

    /// A connection on the public URL whose store holds the signed-in person (user `abc`) in `state`.
    private func presence(_ state: String, freshness: EntityStore.Freshness = .live,
                          userID: String = "abc") -> (HassConnection, HAMockConnection) {
        let route = makeRoute(finder: FakeFinder([]), pins: FakePins())
        let mock = HAMockConnection()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "route-\(UUID()).json"))
        let store = EntityStore()
        let connection = HassConnection(server: .example, store: store, snapshotCache: cache, connection: mock, route: route)
        store.replaceAll([
            EntityState(entityId: "person.demo_alex", state: state, attributes: ["user_id": .string(userID)]),
            EntityState(entityId: "person.demo_guest", state: "home", attributes: ["user_id": .string("other")]),
        ], freshness: freshness)
        return (connection, mock)
    }

    /// Answers the `auth/current_user` request with user `abc`.
    private func answerCurrentUser(_ mock: HAMockConnection) async throws {
        for _ in 0..<1_000 where mock.pendingRequests.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        let request = try #require(mock.pendingRequests.first)
        #expect(request.request.type == .currentUser)
        request.completion(.success(HAData(value: ["id": "abc", "name": "Alex", "is_owner": true, "is_admin": true])))
    }

    @Test func homeIsConfirmedByTheSignedInPersonsLiveState() async throws {
        let (connection, mock) = presence("home")
        async let confirmed = connection.isHomeConfirmedOverPublicURL()
        try await answerCurrentUser(mock)
        #expect(await confirmed)
    }

    @Test func homeIsNotConfirmedAwayOrFromAnotherPerson() async throws {
        let (away, awayMock) = presence("not_home")
        async let awayConfirmed = away.isHomeConfirmedOverPublicURL()
        try await answerCurrentUser(awayMock)
        #expect(await awayConfirmed == false)

        let (someoneElse, otherMock) = presence("home", userID: "xyz")
        async let otherConfirmed = someoneElse.isHomeConfirmedOverPublicURL()
        try await answerCurrentUser(otherMock)
        #expect(await otherConfirmed == false, "only the signed-in person's presence counts")
    }

    @Test func homeIsNotConfirmedFromTheDiskSnapshot() async {
        let (connection, mock) = presence("home", freshness: .snapshot(savedAt: Date()))
        #expect(await connection.isHomeConfirmedOverPublicURL() == false)
        #expect(mock.pendingRequests.isEmpty)
    }
}

/// Only a new network reconnects: path updates that leave the network as it was (a tunnel, the Mac's USB link, cellular
/// beside Wi-Fi) do not (phone run, 2026-10-27: 1 to 3 reconnects every 8 s on a phone lying still).
struct NetworkPathChangeFilterTests {
    private let homeWiFi = NetworkPathSignature(isSatisfied: true, isLocal: true, primaryInterface: "wifi:en0",
                                                gateways: ["169.254.7.12:0"])

    @Test func theFirstPathCounts() {
        var filter = NetworkPathChangeFilter()
        let changed = filter.isChange(homeWiFi)
        #expect(changed)
    }

    @Test func theSameNetworkAgainDoesNot() {
        var filter = NetworkPathChangeFilter()
        _ = filter.isChange(homeWiFi)
        let first = filter.isChange(homeWiFi)
        let second = filter.isChange(homeWiFi)
        #expect(!first)
        #expect(!second)
    }

    @Test func gatewaysInAnotherOrderAreTheSameNetwork() {
        var filter = NetworkPathChangeFilter()
        _ = filter.isChange(NetworkPathSignature(isSatisfied: true, isLocal: true, primaryInterface: "wifi:en0",
                                                 gateways: ["169.254.7.12:0", "fe80::1%en0:0"]))
        let reordered = filter.isChange(NetworkPathSignature(isSatisfied: true, isLocal: true, primaryInterface: "wifi:en0",
                                                             gateways: ["fe80::1%en0:0", "169.254.7.12:0"]))
        #expect(!reordered)
    }

    @Test func anotherWiFiNetworkOnTheSameInterfaceCounts() {
        var filter = NetworkPathChangeFilter()
        _ = filter.isChange(homeWiFi)
        var cafe = homeWiFi
        cafe.gateways = ["169.254.7.13:0"]
        let changed = filter.isChange(cafe)
        #expect(changed)
    }

    @Test func leavingWiFiForCellularCounts() {
        var filter = NetworkPathChangeFilter()
        _ = filter.isChange(homeWiFi)
        let changed = filter.isChange(NetworkPathSignature(isSatisfied: true, isLocal: false, primaryInterface: "cellular:pdp_ip0",
                                                           gateways: []))
        #expect(changed)
    }

    @Test func losingTheNetworkAndGettingItBackCountsBothWays() {
        var filter = NetworkPathChangeFilter()
        _ = filter.isChange(homeWiFi)
        let lost = filter.isChange(NetworkPathSignature(isSatisfied: false, isLocal: false, primaryInterface: nil, gateways: []))
        let back = filter.isChange(homeWiFi)
        #expect(lost)
        #expect(back)
    }
}

// MARK: - Reconnect rules

/// A network change never reconnects by itself; the socket dropping does (owner, 2026-10-27). One test per rule.
@MainActor
struct HassConnectionReconnectRuleTests {
    /// A connection over a mock socket that opens (and goes ready) through the real connection-info closure, so the
    /// recorded URL, the count of connects and the URLs they used are what HAKit would see.
    private struct Rig {
        let connection: HassConnection
        let mock: HAMockConnection
        let route: LocalServerRoute
        let watcher: FakeWatcher
        let scroll: ScrollActivity
        let urls: OSAllocatedUnfairLock<[URL]>
        let finder: FakeFinder

        var connects: Int { urls.withLock { $0.count } }
        var lastURL: URL? { urls.withLock { $0.last } }
    }

    private func makeRig(advertised: Bool = true) -> Rig {
        let watcher = FakeWatcher(local: true)
        let finder = FakeFinder(advertised ? [LocalServerAdvertisement(txt: homeTXT)] : [])
        let route = makeRoute(finder: finder, watcher: watcher)
        let record = SocketURLRecord()
        let urls = OSAllocatedUnfairLock(initialState: [URL]())
        let mock = HAMockConnection()
        mock.configuration = HAConnectionConfiguration(
            connectionInfo: {
                let info = HassConnection.connectionInfo(server: .example, route: route, recordingIn: record)
                if let url = info?.url { urls.withLock { $0.append(url) } }
                return info
            },
            fetchAuthToken: { $0(.success("token")) }
        )
        let scroll = ScrollActivity()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "rules-\(UUID()).json"))
        let connection = HassConnection(server: .example, store: EntityStore(), snapshotCache: cache, connection: mock,
                                        route: route, socketURL: record, scrollActivity: scroll)
        connection.scrollQuietPeriod = .milliseconds(200)
        connection.wantsConnection = true
        return Rig(connection: connection, mock: mock, route: route, watcher: watcher, scroll: scroll, urls: urls, finder: finder)
    }

    /// The socket opened first, on the public URL, and the phone is then found at home.
    private func publicSocketAtHome() async -> Rig {
        let rig = makeRig()
        rig.mock.connect()
        await rig.route.refresh()
        return rig
    }

    /// The socket opened on the home address.
    private func homeSocket() async -> Rig {
        let rig = makeRig()
        await rig.route.refresh()
        rig.mock.connect()
        return rig
    }

    private func settle(_ milliseconds: Int = 150) async throws { try await Task.sleep(for: .milliseconds(milliseconds)) }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    }

    private var failure: HAConnectionState {
        .disconnected(reason: .waitingToReconnect(lastError: URLError(.networkConnectionLost), atLatest: Date(), retryCount: 1))
    }

    @Test func aNetworkChangeOnAPublicSocketForgetsHomeWithoutReconnecting() async throws {
        let rig = await publicSocketAtHome()
        #expect(rig.route.isLocal)
        rig.watcher.change(local: false)
        try await settle()
        #expect(!rig.route.isLocal, "the home address is forgotten")
        #expect(rig.connects == 1, "and nothing reconnects")
        #expect(rig.lastURL == HassServer.example.baseURL)
    }

    @Test func leavingHomeReplacesTheHomeSocketAtOnce() async throws {
        let rig = await homeSocket()
        #expect(rig.lastURL == homeURL)
        rig.watcher.change(local: false)
        try await waitUntil { rig.connects == 2 }
        try await settle()
        #expect(!rig.route.isLocal)
        #expect(rig.connects == 2, "one reconnect, not two")
        #expect(rig.lastURL == HassServer.example.baseURL, "Wi-Fi to cellular: the dead home socket is replaced now")
    }

    @Test func connectDuringAPendingSwitchLeavesTheSocketOnItsURL() async throws {
        let rig = await publicSocketAtHome()
        rig.scroll.begin(page: "Rooms")
        rig.connection.homeWasFound()
        try await settle()
        rig.connection.connect(subscribingToStates: false)
        try await settle(300)
        #expect(rig.connects == 1, "no in-place URL change under a live socket")
        rig.scroll.end(page: "Rooms")
        try await waitUntil { rig.connects == 2 }
        #expect(rig.lastURL == homeURL, "the pending switch still lands")
    }

    @Test func disconnectCancelsThePendingSwitchAndForgetsHome() async throws {
        let rig = await publicSocketAtHome()
        rig.scroll.begin(page: "Rooms")
        rig.connection.homeWasFound()
        try await settle()
        rig.connection.disconnect()
        #expect(!rig.route.isLocal, "a home address is not trusted across a stop")
        rig.scroll.end(page: "Rooms")
        try await settle(400)
        #expect(rig.connects == 1)
    }

    @Test func aForegroundOnAnotherNetworkWithTheSameGatewayConnectsToThePublicURLFirst() async throws {
        let rig = await homeSocket()
        #expect(rig.lastURL == homeURL)
        // Backgrounded at home. The gateway on the café's Wi-Fi is the same address, so the path filter reports no change.
        rig.connection.didEnterBackground()
        rig.connection.disconnect()
        rig.watcher.setLocal(false)
        rig.connection.connect(subscribingToStates: false)
        #expect(rig.lastURL == HassServer.example.baseURL, "the token never goes to the old home address on a foreign network")
        try await settle()
        #expect(rig.urls.withLock { Array($0.dropFirst()) }.allSatisfy { $0 == HassServer.example.baseURL })
    }

    @Test func backgroundForgetsHomeButKeepsAnOpenSocket() async throws {
        let rig = await homeSocket()
        rig.connection.didEnterBackground()
        #expect(!rig.route.isLocal)
        #expect(rig.connects == 1)
    }

    @Test func aFailoverToPublicChecksForHomeOnceWhenTheSocketIsReady() async throws {
        let rig = await homeSocket()
        rig.mock.setState(failure, waitForQueue: false)
        try await waitUntil { rig.connects == 2 }
        // The public socket is ready and home still answers: found again through the check, not stuck on public.
        try await waitUntil { rig.route.isLocal }
        #expect(rig.route.isLocal, "home is re-checked after the failover")
    }

    @Test func homeFoundWhileAPublicSocketIsReadyReconnectsOnceToHome() async throws {
        let rig = await publicSocketAtHome()
        rig.connection.homeWasFound()
        try await waitUntil { rig.connects == 2 }
        try await settle()
        #expect(rig.connects == 2)
        #expect(rig.lastURL == homeURL)
    }

    @Test func homeFoundWhileScrollingWaitsForTheScrollToStop() async throws {
        let rig = await publicSocketAtHome()
        rig.scroll.begin(page: "Rooms")
        rig.connection.homeWasFound()
        try await settle(500)
        #expect(rig.connects == 1, "no switch mid-scroll")
        let stopped = ContinuousClock.now
        rig.scroll.end(page: "Rooms")
        try await waitUntil { rig.connects == 2 }
        #expect(rig.connects == 2)
        #expect(rig.lastURL == homeURL)
        #expect(ContinuousClock.now - stopped >= .milliseconds(150), "it waits out the quiet period after the scroll")
        try await settle()
        #expect(rig.connects == 2, "exactly one switch")
    }

    @Test func homeFoundWhileTheSocketIsNotReadyConnectsNow() async throws {
        let rig = makeRig()
        rig.mock.setState(failure, waitForQueue: false)
        rig.scroll.begin(page: "Rooms")
        await rig.route.refresh()
        rig.connection.homeWasFound()
        #expect(rig.connects == 1, "no waiting out the backoff or the scroll")
        #expect(rig.lastURL == homeURL)
    }

    @Test func homeFoundWhileAlreadyOnHomeDoesNothing() async throws {
        let rig = await homeSocket()
        rig.connection.homeWasFound()
        try await settle(300)
        #expect(rig.connects == 1)
    }

    @Test func aHomeSocketThatDropsReconnectsOnThePublicURLOnce() async throws {
        let rig = await homeSocket()
        // The failover re-check runs once the public socket is ready (rule 3); home has gone, so nothing moves back.
        rig.finder.setReachable(false)
        rig.mock.setState(failure, waitForQueue: false)
        try await waitUntil { rig.connects == 2 }
        #expect(rig.connects == 2)
        #expect(rig.lastURL == HassServer.example.baseURL)
        #expect(!rig.route.isLocal)
        try await settle()
        // The public socket failing too is HAKit's to retry; no loop of our own.
        rig.mock.setState(failure, waitForQueue: false)
        try await settle(300)
        #expect(rig.connects == 2)
    }

    @Test func afterANetworkChangeTheSocketNeverGoesBackToTheHomeAddressByItself() async throws {
        let rig = await homeSocket()
        rig.watcher.change(local: false)
        try await waitUntil { rig.connects == 2 }
        rig.mock.setState(failure, waitForQueue: false)
        try await settle()
        #expect(rig.urls.withLock { Array($0.dropFirst()) }.allSatisfy { $0 == HassServer.example.baseURL },
                "the token only goes to the home address while the route has confirmed it")
    }
}

/// Scroll activity: a timestamp per frame, pages that are mid-scroll count as active.
@MainActor
struct ScrollActivityTests {
    @Test func idleDurationFollowsTheClock() {
        nonisolated(unsafe) var now = 100.0
        let activity = ScrollActivity { now }
        #expect(activity.idleDuration == .infinity)
        activity.noteScroll()
        now += 0.4
        #expect(abs(activity.idleDuration - 0.4) < 0.001)
    }

    @Test func aPageMidScrollIsNeverIdle() {
        nonisolated(unsafe) var now = 0.0
        let activity = ScrollActivity { now }
        activity.begin(page: "A")
        now += 5
        #expect(activity.idleDuration == 0)
        activity.end(page: "A")
        #expect(activity.idleDuration == 0)
        now += 1
        #expect(abs(activity.idleDuration - 1) < 0.001)
    }
}
