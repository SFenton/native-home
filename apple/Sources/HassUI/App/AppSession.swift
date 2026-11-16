import CryptoKit
import Foundation
import FentonActivityModel
import HassCore
import HassDesign
import HassTelemetry
import Observation

/// Signed-in state for the whole app.
@MainActor
@Observable
public final class AppSession {
    /// Where the app is.
    public enum Phase {
        case signedOut
        case signedIn(HassConnection, ConnectionLifecycle)
    }

    /// Current phase.
    public private(set) var phase: Phase = .signedOut

    /// Opens the launch intervals (`Telemetry.beginTracked`): the app calls it as early as it can, from its `App` initializer, so the
    /// first frame and the snapshot are timed from process start rather than from the first view.
    public nonisolated static func beginLaunchMeasurement() {
        Telemetry.beginTracked(Telemetry.Name.launch)
        Telemetry.beginTracked(Telemetry.Name.snapshotShown)
    }

    /// Whether a session is running (the phase is ``Phase/signedIn(_:_:)``).
    public var isSignedIn: Bool {
        if case .signedIn = phase { return true }
        return false
    }

    /// An async consumer belongs to this exact account connection, not a later sign-in.
    func isCurrentConnection(_ connection: HassConnection) -> Bool {
        guard case .signedIn(let current, _) = phase else { return false }
        return current === connection
    }

    /// Who was signed in when the session ended because Home Assistant rejected the refresh token, so sign-in can say
    /// "Welcome back, Alex" and ask for the password alone. Nil after a deliberate sign-out, a fresh install, or Use a
    /// Different Account.
    public private(set) var expiredAccount: RememberedAccount?

    /// Token source for the signed-in server, used by the Home Assistant settings web view.
    @ObservationIgnored public private(set) var tokens: TokenManager?

    /// Native notifications: registration with Home Assistant and what a notification opens.
    @ObservationIgnored public let push: PushCoordinator

    /// Location reporting on every iPhone and iPad (an iPad is never linked to a person); nil in launches that don't
    /// report (``LocationLaunchPolicy``).
    @ObservationIgnored public let location: LocationCoordinator?

    /// The after-sign-in Setup flow: Notifications, Time Sensitive, Location (`.agents/platforms/apple/push.md`).
    @ObservationIgnored public let setup: SetupCoordinator

    /// The Live Activities: tokens for Home Assistant, button presses and sign-out (nil in tests that do not need it).
    @ObservationIgnored public let liveActivities: LiveActivityCoordinator?

    /// Which one-time moments (intro, sign-in arrival) have played, and Reduce Motion. One per session; reset at sign-out
    /// (`.agents/design/motion.md`). `RootView` puts it in the environment.
    public let motion: MotionPolicy

    /// The app's pages in system search: one item per authored route the person is offered, indexed when a publication is
    /// accepted and emptied at sign-out.
    @ObservationIgnored private let spotlight: any SpotlightIndexing
    /// The routes the person is offered now: what Spotlight indexes and what Siri and Shortcuts list. Nil before a
    /// publication is accepted and after sign-out.
    @ObservationIgnored public private(set) var routeCatalog: RouteCatalog?
    /// What the route catalog knows about the signed-in person, for routes with a `visibleWhen`.
    @ObservationIgnored private var routeViewer = RouteVisibility.Viewer()
    /// The accepted publication's revision.
    @ObservationIgnored private var publishedRevision = 0
    /// Runs after the offered routes changed, so the app can refresh its App Shortcut parameters
    /// (`updateAppShortcutParameters()`). The app sets it once at launch.
    @ObservationIgnored public var routeCatalogDidChange: (@MainActor () -> Void)?

    /// The people's photos from Home Assistant, cached on the device while signed in and deleted at sign-out
    /// (`.agents/patterns/avatar.md`). `RootView` puts it in the environment.
    @ObservationIgnored public let avatars: PersonAvatars

    @ObservationIgnored private let tokenStore: TokenStore
    @ObservationIgnored private let snapshotCache: EntitySnapshotCache
    @ObservationIgnored private let houseConfigCache: HouseConfigCache
    /// The server's house document: fetched, cached and published to
    /// `HouseConfigSource.shared` for the flipped facades. Started in `start(server:tokens:)` after authentication, cleared at sign-out.
    @ObservationIgnored public private(set) var houseConfig: HouseConfigStore?
    /// Asks for the house layout again at every reconnect while the store has none (``HouseConfigStore/resubscribeIfNeeded()``).
    @ObservationIgnored private var houseConfigReconnectObserver: NSObjectProtocol?
    @ObservationIgnored private let remembered: RememberedAccountStore
    /// The server the build names, a starting point for the sign-in form and the debug token launch; never the server of a saved sign-in.
    @ObservationIgnored private let buildDefault: HassServer?
    /// The Home Assistant user the cached UI publication belongs to: the saved record's user after a cold-launch restore, the
    /// verified user once the socket says who is signed in. Nothing is persisted here; the record lives in the publication cache.
    @ObservationIgnored private var publicationUserID: String?
    @ObservationIgnored private let extensionStore: ExtensionPresentationStore?
    /// The saved route catalog Siri, Shortcuts and a cold-launch Spotlight tap read; beside ``extensionStore``.
    @ObservationIgnored private var routeCatalogStore: RouteCatalogStore? { extensionStore.map(RouteCatalogStore.init(base:)) }
    @ObservationIgnored private var extensionSessionID: String?
    @ObservationIgnored private var systemCleanup: Task<Void, Never>?
    @ObservationIgnored private var systemStart: Task<Void, Never>?
    public private(set) var publishedExtensionRoutes: [NativeExtensionPresentation.Route] = []
    #if os(iOS)
    @ObservationIgnored private var productionRuntime: UKServerUIProductionRuntime?

    /// All windows share one server publication store, but retain their own native routes.
    func productionUI(connection: HassConnection) -> UKServerUIProductionRuntime {
        if let productionRuntime { return productionRuntime }
        let runtime = UKServerUIProductionRuntime(session: self, connection: connection)
        productionRuntime = runtime
        return runtime
    }
    #endif

    /// Restores OAuth synchronously without a network request. The product root restores its last-good publication from the
    /// disk cache before its first frame, then follows the server's publication over the one connection.
    /// - Parameters:
    ///   - tokenStore: Where the refresh token lives; shared with the notification service extension.
    ///   - snapshotCache: The disk snapshot of entity states.
    ///   - houseConfigCache: The disk copy of the server's house document (app group container).
    ///   - push: The app's push coordinator (the app delegate's, so system callbacks reach it).
    ///   - location: The app's location coordinator (the app delegate's, created at launch for zone relaunches).
    ///   - liveActivities: The app's Live Activity coordinator (the app delegate's, so its buttons work at launch).
    ///   - spotlight: Where the app's pages are indexed; inert unless the app passes ``CoreSpotlightIndexer``.
    ///   - motion: The session's motion policy; tests inject one with a fake Reduce Motion source.
    ///   - remembered: Where the last username and the person's name are kept (``expiredAccount``).
    ///   - avatars: The people's photos; nil is the app's (Application Support), or a throwaway directory in a host test.
    ///   - buildDefault: The server the build names; tests inject one to prove a saved sign-in keeps its own.
    ///   - launchArguments: Debug preview launches leave the saved account untouched and never start its connection.
    public init(tokenStore: TokenStore = KeychainTokenStore(accessGroup: KeychainTokenStore.sharedAccessGroup),
                snapshotCache: EntitySnapshotCache = .init(), houseConfigCache: HouseConfigCache = .init(),
                push: PushCoordinator = .inert(),
                location: LocationCoordinator? = nil, liveActivities: LiveActivityCoordinator? = nil,
                spotlight: any SpotlightIndexing = InertSpotlightIndexer(),
                motion: MotionPolicy = MotionPolicy(),
                remembered: RememberedAccountStore = RememberedAccountStore(),
                avatars: PersonAvatars? = nil,
                buildDefault: HassServer? = HassServer.buildDefault(),
                launchArguments: [String] = ProcessInfo.processInfo.arguments,
                extensionStore: ExtensionPresentationStore? = nil) {
        self.buildDefault = buildDefault
        self.extensionStore = extensionStore
        let avatars = avatars ?? Self.defaultAvatars()
        self.avatars = avatars
        self.spotlight = spotlight
        self.motion = motion
        self.remembered = remembered
        self.tokenStore = tokenStore
        self.snapshotCache = snapshotCache
        self.houseConfigCache = houseConfigCache
        self.push = push
        self.location = location
        self.setup = SetupCoordinator(push: push, location: location)
        self.liveActivities = liveActivities
        // A Spotlight tap names a route id; before a publication is restored the saved catalog answers.
        push.routeCatalog = { [weak self] in self?.routeCatalog ?? self?.routeCatalogStore?.read() }
        #if DEBUG
        if ServerUIPreviewLaunch.isEnabled(arguments: launchArguments)
            || GalleryFixtureLaunch.isEnabled(arguments: launchArguments) { return }
        // UI tests start signed out: FENTON_UITEST_RESET=1 clears the saved sign-in and snapshot, and the location
        // screen is offered again.
        if ProcessInfo.processInfo.environment["FENTON_UITEST_RESET"] == "1" {
            tokenStore.clear()
            snapshotCache.clear()
            houseConfigCache.clear()
            avatars.removeAll()
            LocationCoordinator.resetOffers()
            remembered.forget()
            remembered.forgetServer()
        }
        // FENTON_EXPIRED_ACCOUNT=<username>|<name> starts signed out as if that account's session had just ended, so
        // journeys can look at the welcome back sign-in.
        if let value = ProcessInfo.processInfo.environment["FENTON_EXPIRED_ACCOUNT"], tokenStore.load() == nil {
            let parts = value.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            expiredAccount = RememberedAccount(username: parts[0], name: parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil)
        }
        // FENTON_HASS_TOKEN signs in with a long-lived access token for this launch only (never saved),
        // so journeys can run against the real server without a password. Host tests ignore it: the variable lives in the
        // developer's shell for live journeys (`--env shell`), and `swift test` inherits that shell (``honoursLaunchToken``).
        let launch = LaunchEnvironment.current
        if let token = launch["FENTON_HASS_TOKEN"], !token.isEmpty,
           let server = launch["FENTON_HASS_SERVER"].flatMap(URL.init(string:)).map(HassServer.init(baseURL:)) ?? buildDefault {
            let tokens = AuthTokens(accessToken: token, expiresAt: .distantFuture, refreshToken: "")
            motion.markPlayed(.signInArrival)
            start(server: server, tokens: TokenManager(store: InMemoryTokenStore(), initial: tokens))
            return
        }
        #endif
        if let stored = tokenStore.load() {
            // Resuming a saved sign-in is not an arrival: nothing introduces the app to someone already in it.
            motion.markPlayed(.signInArrival)
            // An install from before the server field never saved its server; keep it for the next sign-in form and welcome back.
            if remembered.server == nil { remembered.remember(server: stored.server) }
            start(server: stored.server, tokens: TokenManager(store: tokenStore))
        }
    }

    /// The app's people photos. A host test process gets a temporary directory, so a test that signs out can never wipe the
    /// developer's real photos.
    private static func defaultAvatars() -> PersonAvatars {
        #if DEBUG
        if isHostTestProcess {
            return PersonAvatars(store: PersonAvatarStore(directory: FileManager.default.temporaryDirectory
                .appending(path: "PersonAvatars-host-test-\(UUID().uuidString)")))
        }
        #endif
        return PersonAvatars()
    }

    #if DEBUG
    /// Whether this process is the host test runner (`swift test` runs XCTest and Swift Testing in `xctest` or
    /// `swiftpm-testing-helper`), not the app.
    static var isHostTestProcess: Bool {
        isHostTestProcess(name: ProcessInfo.processInfo.processName, environment: ProcessInfo.processInfo.environment)
    }

    /// The rule behind ``isHostTestProcess``, testable without a process.
    static func isHostTestProcess(name: String, environment: [String: String]) -> Bool {
        LaunchEnvironment.isHostTestProcess(name: name, environment: environment)
    }
    #endif

    /// Why a sign-in could not complete.
    public enum SignInError: Error, Equatable {
        /// A session is already running; sign-in is for a signed-out app.
        case alreadySignedIn
    }

    /// Completes sign-in with fresh tokens.
    /// - Throws: ``SignInError/alreadySignedIn`` when a session is already running, or the token store's failure.
    public func didSignIn(server: HassServer, tokens: AuthTokens) throws {
        guard !isSignedIn else { throw SignInError.alreadySignedIn }
        try tokenStore.save(StoredCredentials(server: server, refreshToken: tokens.refreshToken))
        expiredAccount = nil
        start(server: server, tokens: TokenManager(store: tokenStore, initial: tokens))
    }

    /// Ends the session because Home Assistant rejected the token, and keeps who it was for the sign-in's welcome back (a
    /// silent blank form told the person nothing). With no remembered username (a phone signed in before the app kept one)
    /// the plain sign-in shows.
    public func sessionExpired() {
        let account = remembered.account
        signOut()
        // The welcome back screen is not a first launch: the 1.2 s intro does not play again (owner, 2026-10-24,
        // navigation-flows 3 A). `signOut()` forgot every moment; the sign-in's arrival should still play, so only the intro is kept.
        motion.markPlayed(.intro)
        expiredAccount = account
        // The whole screen is swapped for the sign-in: tell VoiceOver why, and move it there.
        Announcer.screenChanged(announcing: Self.expiredAnnouncement(account))
    }

    /// What VoiceOver hears when a refused token sends the person back to sign in.
    static func expiredAnnouncement(_ account: RememberedAccount?) -> String {
        let who = (account?.name).flatMap { $0.isEmpty ? nil : $0 }.map { "Welcome back, \($0). " } ?? ""
        return "Your session ended. \(who)Sign in again to continue."
    }

    /// Reacts to the connection's status: a refused token ends the session (``sessionExpired()``); every other status
    /// is the connection's own business.
    public func connectionStatusChanged(_ status: HassConnection.Status) {
        if status == .rejected { sessionExpired() }
    }

    /// Forgets the account a rejected session left behind (Use a Different Account): the next sign-in asks for a username.
    public func forgetExpiredAccount() {
        remembered.forget()
        expiredAccount = nil
    }

    /// Why a confirmed sign-out stayed signed in.
    public struct SignOutFailure: Error, Equatable {}

    // MARK: - Publication delivery

    /// Why a publication could not be delivered to the extensions.
    enum DeliveryError: Error, Equatable, ServerUIDiagnosable {
        /// No session is running.
        case signedOut

        var diagnostic: String { "delivery: \(self)" }
    }

    /// Validated target copy is delivered only by the publication commit, never by fetch or parse.
    func deliverExtensions(_ publication: ServerUICompositionPublication, applying: () throws -> Void = {}) throws {
        guard isSignedIn else { throw DeliveryError.signedOut }
        // A launch with no extension store or session (a debug journey, a container that failed to open) has no widget or Live
        // Activity to feed: the presentation is not written and the layout still commits. Never a reason to reject it.
        var previous: ExtensionPresentationSnapshot?
        if let extensionStore {
            do { previous = try extensionStore.read() }
            catch { Telemetry.event("serverui.extensionPresentationRejected", detail: "saved presentation invalid") }
        }
        do {
            if let extensionStore, let extensionSessionID {
                try extensionStore.write(.init(sessionID: extensionSessionID, revision: Int64(publication.revision),
                    activities: publication.document.liveActivities, targets: publication.document.extensions))
            }
            try applying()
        } catch {
            if let extensionStore, let extensionSessionID {
                do {
                    if let previous { try extensionStore.write(previous) }
                    else { try extensionStore.clearPresentation(sessionID: extensionSessionID) }
                } catch { Telemetry.event("serverui.extensionPresentationRollbackFailed"); throw error }
            }
            throw error
        }
        publishedExtensionRoutes = publication.document.extensions?.routes ?? []
        publishedRevision = publication.revision
        push.updateLinkPrefixes(publication.document.extensions?.linkPrefixes)
        publishRouteCatalog()
    }

    /// Records who is signed in for routes that carry a `visibleWhen`, and offers the routes that now hold.
    /// - Parameters:
    ///   - userID: Home Assistant's user id.
    ///   - isAdmin: Whether the user is an administrator, when known.
    func setRouteViewer(userID: String, isAdmin: Bool?) {
        let viewer = RouteVisibility.Viewer(userId: userID, isAdmin: isAdmin)
        guard viewer != routeViewer else { return }
        routeViewer = viewer
        publishRouteCatalog()
    }

    /// Builds the catalog of the routes the person is offered; when it differs from the last one, saves it for Siri and
    /// Shortcuts, indexes it in Spotlight and tells the app to refresh its shortcut parameters. Writes no more than once for a
    /// publication or viewer that changes nothing visible.
    private func publishRouteCatalog() {
        guard isSignedIn else { return }
        let sessionID = extensionSessionID ?? String(repeating: "0", count: 64)
        let catalog = RouteCatalog(sessionID: sessionID, revision: max(publishedRevision, 1), routes: publishedExtensionRoutes,
                                   viewer: routeViewer)
        guard catalog.routes != routeCatalog?.routes else { return }
        routeCatalog = catalog
        if let routeCatalogStore {
            do { try routeCatalogStore.write(catalog) }
            catch { Telemetry.event("serverui.routeCatalogWriteFailed") }
        }
        spotlight.indexPages(SpotlightCatalog.entries(for: catalog))
        routeCatalogDidChange?()
    }

    /// Records which Home Assistant user the cached publication belongs to (the saved record's after a restore, the verified
    /// user's after the socket authenticates).
    func setPublicationUser(_ userID: String, connection: HassConnection) {
        guard isCurrentConnection(connection) else { return }
        publicationUserID = userID
    }

    /// The user the cached publication was delivered to, before the socket has said who is signed in.
    func cachedPublicationUserID(for connection: HassConnection) -> String? {
        isCurrentConnection(connection) ? publicationUserID : nil
    }

    /// Signs out only once Home Assistant confirms this phone is off the user's person (already off counts). Any
    /// failure throws and leaves the session signed in, so the caller shows its alert and the person can retry.
    /// Debug builds take `FENTON_SIGNOUT_FAIL=1` to fail without a server (journeys).
    public func confirmedSignOut() async throws {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FENTON_SIGNOUT_FAIL"] == "1" { throw SignOutFailure() }
        #endif
        guard case let .signedIn(owner, _) = phase else { return }
        if let location, location.linksPresence {
            do {
                let user = try await owner.currentUser()
                guard isCurrentConnection(owner) else { throw SignOutFailure() }
                try await location.unlinkPresence(user: user, api: owner)
            } catch {
                throw SignOutFailure()
            }
        }
        guard isCurrentConnection(owner) else { throw SignOutFailure() }
        signOut()
    }

    /// Signs out: stops pushes to this phone, then revokes the refresh token; clears the Keychain, cache and
    /// store. Home Assistant gets the empty push registration before the token is revoked (contract v1, rule 2).
    public func signOut() {
        systemStart?.cancel()
        systemStart = nil
        push.invalidateSession()
        if let extensionSessionID {
            do { try extensionStore?.endSession(extensionSessionID) }
            catch { Telemetry.event("serverui.extensionPresentationCleanupFailed") }
        }
        extensionSessionID = nil
        publishedExtensionRoutes = []
        publishedRevision = 0
        routeViewer = RouteVisibility.Viewer()
        routeCatalog = nil
        #if os(iOS)
        productionRuntime?.endSession()
        productionRuntime = nil
        #endif
        publicationUserID = nil
        setup.sessionEnded()
        if case let .signedIn(connection, _) = phase {
            connection.disconnect()
            connection.store.reset()
        }
        let stored = tokenStore.load()
        tokenStore.clear()
        snapshotCache.clear()
        houseConfig?.clear()
        houseConfig = nil
        if let observer = houseConfigReconnectObserver { NotificationCenter.default.removeObserver(observer) }
        houseConfigReconnectObserver = nil
        houseConfigCache.clear()
        // Nothing of the signed-out person's face stays on the device: every cached photo, file and in-memory image.
        avatars.removeAll()
        TodoItemsCache().clear()
        WeatherForecastDiskCache().clear()
        UserDefaults.standard.removeObject(forKey: ChoresModel.viewerDefaultsKey)
        // Remembered sheet heights and chrome go too (owner, 2026-10-26: "we clear everything on sign-out").
        SheetMemory.clearAll()
        tokens = nil
        spotlight.removeAll()
        routeCatalogDidChange?()
        // A second sign-in plays its arrival again, and the signed-out screen its intro.
        motion.reset()
        phase = .signedOut
        let push = push, liveActivities = liveActivities
        let priorCleanup = systemCleanup
        systemCleanup = Task {
            await priorCleanup?.value
            // Nothing of the signed-in person stays on a Lock Screen.
            await liveActivities?.sessionEnded()
            await push.finishSessionEnd()
            await AppIconBadgeSync.shared.clear()
            if let stored { await HassLoginFlow.revoke(server: stored.server, refreshToken: stored.refreshToken) }
        }
    }

    /// Feeds the house config store whether the socket is up, for as long as both live (``HouseConfigStore/setConnected(_:)``).
    private static func followConnection(_ connection: HassConnection, _ store: HouseConfigStore) {
        withObservationTracking {
            let up: Bool
            if case .connected = connection.status { up = true } else { up = false }
            store.setConnected(up)
        } onChange: { [weak connection, weak store] in
            Task { @MainActor in
                guard let connection, let store else { return }
                followConnection(connection, store)
            }
        }
    }

    private func start(server: HassServer, tokens: TokenManager) {
        publicationUserID = nil
        if let credentials = tokenStore.load(), credentials.server == server, let extensionStore {
            let id = Self.extensionSessionID(credentials)
            do {
                try extensionStore.beginSession(id)
                extensionSessionID = id
            } catch {
                Telemetry.event("serverui.extensionPresentationSessionFailed")
            }
        }
        // At home the socket uses Home Assistant's home network address instead of the public URL (LocalServerRoute).
        let route = LocalServerRoute.isEnabled() ? LocalServerRoute(server: server) : nil
        let connection = HassConnection(server: server, tokens: tokens, store: EntityStore(), snapshotCache: snapshotCache, route: route,
                                        reachability: SystemNetworkReachability())
        let lifecycle = ConnectionLifecycle(connection: connection)
        // The same websocket, after authentication. The store publishes into `HouseConfigSource.shared`, which the flipped
        // `*Config` facades read.
        let houseConfig = HouseConfigStore(server: server, transport: HassHouseConfigTransport(connection: connection),
                                           cache: houseConfigCache, source: .shared, loadsCacheSynchronously: true)
        self.houseConfig = houseConfig
        // The timeout clock runs only while connected: offline stays the skeleton.
        houseConfig.setConnected(false)
        houseConfig.start()
        Self.followConnection(connection, houseConfig)
        // HAKit retries a live subscription, not a refused one: a store without a document asks again at every reconnect.
        houseConfigReconnectObserver = NotificationCenter.default.addObserver(
            forName: HassConnection.didBecomeReadyNotification, object: connection, queue: .main) { [weak houseConfig] _ in
            MainActor.assumeIsolated {
                houseConfig?.setConnected(true)
                houseConfig?.resubscribeIfNeeded()
            }
        }
        self.tokens = tokens
        if let systemCleanup {
            systemStart = Task { [weak self] in
                await systemCleanup.value
                guard !Task.isCancelled, let self, self.isCurrentConnection(connection) else { return }
                self.push.sessionStarted(server: server) { try await tokens.validAccessToken() }
                self.liveActivities?.sessionStarted()
            }
        } else {
            push.sessionStarted(server: server) { try await tokens.validAccessToken() }
            liveActivities?.sessionStarted()
        }
        // The Bearer token goes only to this server's host (`PersonAvatarSyncer.sendsToken`).
        avatars.start(entityStore: connection.store,
                      server: .init(baseURL: server.baseURL, accessToken: { try? await tokens.validAccessToken() }))
        phase = .signedIn(connection, lifecycle)
        lifecycle.didBecomeActive()
    }

    /// Names this OAuth session for the extensions' presentation store: a digest of the origin and the refresh token, derived on
    /// demand and never stored. A new sign-in is a new session, so the previous one's presentation can never be read again.
    static func extensionSessionID(_ credentials: StoredCredentials) -> String {
        let origin = credentials.server.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return SHA256.hash(data: Data((origin + "\u{0}" + credentials.refreshToken).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// Old-account cleanup finishes before the new account can register push or ActivityKit tokens.
    func waitForSystemServices() async { await systemStart?.value }
}
