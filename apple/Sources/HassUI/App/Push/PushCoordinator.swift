import FentonActivityModel
import Foundation
import HassCore
import Observation

/// Native notifications for the signed-in session (`.agents/platforms/apple/push.md`).
///
/// Asks for notification permission, hands the APNs token to the session's shared `mobile_app` registration
/// (``mobileApp``), and decides what a notification tap or button does. The app delegate forwards system callbacks
/// here; the shell observes ``pendingRequest`` and opens the page (``ShellNavigator/open(_:)``). Home Assistant
/// stays the source of truth: a button fires `mobile_app_notification_action` and the automation decides what
/// happens.
@MainActor
@Observable
public final class PushCoordinator {
    /// The page a notification asked to open, until the shell opens it.
    public private(set) var pendingRequest: PushNavigationRequest?

    /// The session's `mobile_app` registration, which location and sensors share.
    @ObservationIgnored public let mobileApp: MobileAppCoordinator

    /// The system's answer, read when the session connects and after each ask. ``showsPermissionBanner`` and the
    /// Settings row read it.
    public private(set) var authorization: PushAuthorization = .denied
    /// The Time Sensitive switch, read with ``authorization`` (when the session connects, after each ask, and when the
    /// app becomes active, so Settings and the Setup step are right after the person returns from iOS Settings).
    /// ``TimeSensitiveSetting/notSupported`` until read and while notifications are not allowed.
    public private(set) var timeSensitive: TimeSensitiveSetting = .notSupported
    /// Whether the person chose Not Now on the Home banner (kept across launches; the Settings row stays).
    public private(set) var bannerDismissed: Bool

    /// The key ``bannerDismissed`` is kept under.
    public static let bannerDismissedKey = "push.permissionBannerDismissed"
    @ObservationIgnored private let defaults: UserDefaults

    /// Whether the Setup flow's Notifications step has been shown (``SetupFlow``). Until it has, the flow is about to
    /// ask, so the Home banner waits; afterwards the banner is the fallback for a person who never answered.
    public internal(set) var setupHasShownNotifications: Bool

    /// Whether Home offers to turn notifications on: never asked, not dismissed, and the Setup flow is not about to ask.
    public var showsPermissionBanner: Bool { authorization == .notDetermined && !bannerDismissed && setupHasShownNotifications }

    @ObservationIgnored private let platform: PushPlatform
    @ObservationIgnored private var server: HassServer?
    @ObservationIgnored private var requestID = 0
    /// Set once the session connected, or the person answered the ask: the first moment the system's answer is read.
    @ObservationIgnored private var isConnected = false

    /// Creates a coordinator.
    /// - Parameters:
    ///   - platform: System services.
    ///   - store: Saved webhooks.
    ///   - transport: HTTP to Home Assistant.
    ///   - isEnabled: Register and ask for permission. Off for UI journeys signed in with a test token, so they
    ///     neither prompt nor add `mobile_app` devices to the real server.
    public init(platform: PushPlatform, store: any MobileAppRegistrationStore = KeychainMobileAppRegistrationStore(),
                transport: any FeedbackHTTPTransport = URLSessionFeedbackTransport(), isEnabled: Bool = true,
                defaults: UserDefaults = .standard) {
        self.platform = platform
        self.defaults = defaults
        bannerDismissed = defaults.bool(forKey: Self.bannerDismissedKey)
        setupHasShownNotifications = SetupFlow.seen(in: defaults).contains(.notifications)
        mobileApp = MobileAppCoordinator(device: platform.device, store: store, transport: transport, isEnabled: isEnabled)
    }

    /// A coordinator that never registers or prompts.
    public static func inert() -> PushCoordinator {
        PushCoordinator(platform: .inert, store: InMemoryMobileAppRegistrationStore(), isEnabled: false)
    }

    // MARK: - Session

    /// A session started on a server.
    /// - Parameters:
    ///   - server: The signed-in server.
    ///   - accessToken: Valid access tokens for it.
    func sessionStarted(server: HassServer, accessToken: @escaping @Sendable () async throws -> String) {
        self.server = server
        mobileApp.sessionStarted(server: server, accessToken: accessToken)
    }

    /// The websocket is up and the user is known: ask for permission (first time only), register for remote
    /// notifications, and sync the registration.
    /// - Parameters:
    ///   - userID: The signed-in Home Assistant user.
    ///   - userName: Their display name, which names a phone the system reports only as "iPhone".
    public func didConnect(userID: String, userName: String? = nil) async {
        guard mobileApp.canBegin(userID: userID) else { return }
        isConnected = true
        // Read before the user begins, so no sync runs before it knows whether the saved APNs token may go.
        await readSettings()
        guard mobileApp.begin(userID: userID, userName: userName) else { return }
        if authorization == .granted { platform.registerForRemoteNotifications() }
        await mobileApp.sync()
    }

    #if DEBUG
    /// Marks the session connected without registering, so the gallery's scripted system is read (debug galleries only).
    func simulateConnected() { isConnected = true }
    #endif

    /// Reads the system's answer and the Time Sensitive switch again: the app became active, or the Setup flow
    /// evaluates. Does nothing before the session connects (journeys that never ask stay as they are).
    public func refreshSettings() async {
        guard isConnected else { return }
        let before = mobileApp.notificationsGranted
        await readSettings()
        // Permission was turned on or off in iOS Settings: the registration gains or loses the APNs token.
        if before != nil, mobileApp.notificationsGranted != before { await mobileApp.sync() }
    }

    private func readSettings() async {
        authorization = await platform.authorization()
        timeSensitive = authorization == .granted ? await platform.timeSensitiveSetting() : .notSupported
        _ = mobileApp.setNotificationsGranted(authorization == .granted)
    }

    /// The person tapped Turn On Notifications (Home banner or Settings row): the one place the system alert is
    /// requested, after the app has said what the alerts are for.
    public func enableNotifications() async {
        let granted = await platform.requestAuthorization()
        isConnected = true
        await refreshSettings()
        if granted { platform.registerForRemoteNotifications() }
    }

    /// The person tapped Not Now on the Home banner.
    public func dismissPermissionBanner() {
        bannerDismissed = true
        defaults.set(true, forKey: Self.bannerDismissedKey)
    }

    /// The system issued an APNs token.
    public func didRegister(deviceToken: Data) async {
        guard mobileApp.setPushToken(PushToken.hex(deviceToken)) else { return }
        await mobileApp.sync()
    }

    /// Signing out: remove this phone's registration from Home Assistant (before the refresh token is revoked).
    func sessionEnded() async {
        server = nil
        pendingRequest = nil
        await mobileApp.sessionEnded()
    }

    // MARK: - Notifications

    /// A tap, dismissal or button press on a notification.
    /// - Parameters:
    ///   - response: What the person did.
    ///   - userInfo: The notification's `userInfo`.
    public func handle(_ response: NotificationResponse, userInfo: [AnyHashable: Any]) async {
        guard let payload = PushPayload(userInfo: userInfo) else { return }
        switch response {
        case .dismiss:
            return
        case .open:
            if let url = payload.url { open(link: url) }
        case let .action(id, replyText):
            guard let action = payload.action(id) else { return }
            if let uri = action.uri {
                open(link: uri)
            } else {
                try? await mobileApp.fireAction(PushActionEvent(action: id, tag: payload.tag, replyText: replyText))
            }
        }
    }

    /// Takes a location update for a `request_location_update` push; the app sets it to
    /// ``LocationCoordinator/handleLocationRequest()``. Returns whether an update was sent.
    @ObservationIgnored public var locationUpdateHandler: (@MainActor () async -> Bool)?

    /// A background push (or a foreground one that carries a command): runs its command.
    /// - Returns: Whether the push carried a command this version runs and it had an effect: notifications were
    ///   cleared or a location update was sent. The app maps this to the fetch completion result.
    @discardableResult
    public func handleBackground(userInfo: [AnyHashable: Any]) async -> Bool {
        switch PushPayload(userInfo: userInfo)?.command {
        case let .clearNotification(tag)?:
            let ids = await platform.deliveredNotifications().filter { $0.tag == tag }.map(\.identifier)
            if !ids.isEmpty { platform.removeDelivered(ids) }
            return true
        case .requestLocationUpdate?:
            return await locationUpdateHandler?() ?? false
        case .unsupported?, nil:
            return false
        }
    }

    /// The shell opened ``pendingRequest``.
    public func didOpen(_ request: PushNavigationRequest) {
        if pendingRequest == request { pendingRequest = nil }
    }

    /// A tap on the Home Live Activity (`fentonhome://liveactivity?url=…`): opens the focused job's page.
    /// - Returns: Whether the URL was a Live Activity link.
    @discardableResult
    public func openLiveActivity(_ url: URL) -> Bool {
        guard let link = ActivityDeepLink.link(from: url) else { return false }
        open(link: link)
        return true
    }

    /// Opens a page of the app from outside it: a Spotlight result or an App Shortcut. The shell opens it the way it
    /// opens a notification's page (``pendingRequest``), including a launch the tap itself caused.
    /// - Parameter destination: The page.
    public func open(_ destination: PushDestination) {
        requestID += 1
        pendingRequest = PushNavigationRequest(id: requestID, destination: destination)
    }

    /// Opens the page a tapped Spotlight result stands for.
    /// - Parameter userInfo: The `NSUserActivity` for `CSSearchableItemActionType`.
    /// - Returns: Whether the result was one of the app's pages.
    @discardableResult
    public func open(spotlightUserInfo userInfo: [AnyHashable: Any]?) -> Bool {
        guard let identifier = SpotlightLink.identifier(in: userInfo),
              let destination = SpotlightCatalog.destination(forIdentifier: identifier) else { return false }
        open(destination)
        return true
    }

    /// Opens a notification link: an app page, Home Assistant's own page, or another site.
    func open(link: String) {
        switch PushLink(link, server: server) {
        case let .dashboard(path, anchor)?:
            requestID += 1
            pendingRequest = PushNavigationRequest(id: requestID, destination: PushDestination(dashboardPath: path), anchor: anchor)
        case let .homeAssistant(path)?:
            if let server { platform.openExternal(server.url(path)) }
        case let .external(url)?:
            platform.openExternal(url)
        case nil:
            return
        }
    }
}
