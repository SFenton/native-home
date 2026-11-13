import Foundation
import HassCore
import Observation

/// The signed-in session's one `mobile_app` registration, shared by push, location and sensors
/// (`.agents/platforms/apple/mobile-app.md`).
///
/// Owns the session's ``MobileAppRegistrar``, the user it registered for, and the install's APNs and push-to-start tokens
/// (kept in the store across launches and sign-out, so no sync drops one). ``PushCoordinator``
/// starts the session, supplies the token and fires notification buttons through it; ``LocationCoordinator`` sends
/// through ``webhookSource`` and starts when ``registration`` appears.
@MainActor
@Observable
public final class MobileAppCoordinator {
    /// The registration this session synced; nil until the first sync succeeds, and after sign-out.
    public private(set) var registration: MobileAppRegistration?

    /// What the last attempt to put this phone's tracker on the signed-in user's person did; nil before one.
    public private(set) var presenceLink: PresenceLinkOutcome?

    /// Register at all. Off for UI journeys signed in with a test token, so they never add `mobile_app` devices
    /// to the real server.
    public let isEnabled: Bool

    /// Whether the registrar may register or update; off in the simulator (``MobileAppRegistrationPolicy``), where a
    /// webhook saved before that rule is ignored too.
    public let allowsRegistration: Bool

    @ObservationIgnored private let device: @MainActor @Sendable () -> MobileAppDevice
    @ObservationIgnored private let store: any MobileAppRegistrationStore
    @ObservationIgnored private let transport: any FeedbackHTTPTransport
    @ObservationIgnored private var registrar: MobileAppRegistrar?
    /// Watches the network for pending-removal retries; retained so its monitor keeps running.
    @ObservationIgnored private var reachability: (any NetworkReachability)?
    /// The one retrier, so overlapping triggers (launch and network return) don't send twice.
    @ObservationIgnored private lazy var pendingRetrier: PendingUnregisterRetrier = {
        let device = device
        return PendingUnregisterRetrier(store: store, transport: transport) { await MainActor.run { device() } }
    }()
    @ObservationIgnored private(set) var userID: String?
    @ObservationIgnored private var userName: String?
    /// The last APNs token the system issued, seeded from the store at launch so the first sync carries it.
    @ObservationIgnored private var token: String?
    /// The Home activity's push-to-start token a sync sends: seeded from the store at launch, nil while Live Activities
    /// are off or unsupported.
    @ObservationIgnored private var startActivityToken: String?
    /// The last push-to-start token the system issued, kept while Live Activities are off so turning them on restores it.
    @ObservationIgnored private(set) var lastStartActivityToken: String?
    /// Whether notification permission is granted; nil until the system's answer is read. While it is false a sync
    /// sends no APNs token, so the registration stays websocket-only like a phone that never had permission.
    @ObservationIgnored private(set) var notificationsGranted: Bool?
    /// The running sync, so a token arriving mid-sync waits for it instead of racing it.
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    /// The registration and user the person link last succeeded for, so a reconnect doesn't repeat it.
    @ObservationIgnored private var linkedKey: String?
    /// The user and websocket of the last link, so a permission change can unlink and relink without a screen.
    @ObservationIgnored private var linkContext: (user: HassUser, api: any HassCommandSending)?
    @ObservationIgnored private var listeners: [@MainActor (MobileAppRegistration?) -> Void] = []

    /// Creates a coordinator.
    /// - Parameters:
    ///   - device: This phone's registration facts.
    ///   - store: Saved webhooks.
    ///   - transport: HTTP to Home Assistant.
    ///   - isEnabled: Register at all.
    ///   - allowsRegistration: Whether this build may register (the simulator may not, unless told to).
    public init(device: @escaping @MainActor @Sendable () -> MobileAppDevice,
                store: any MobileAppRegistrationStore = KeychainMobileAppRegistrationStore(),
                transport: any FeedbackHTTPTransport = URLSessionFeedbackTransport(), isEnabled: Bool = true,
                allowsRegistration: Bool = MobileAppRegistrationPolicy.allowsRegistration()) {
        self.device = device
        self.store = store
        self.transport = transport
        self.isEnabled = isEnabled
        self.allowsRegistration = allowsRegistration
        let saved = store.deviceTokens
        token = saved.push
        startActivityToken = saved.startActivity
        lastStartActivityToken = saved.startActivity
    }

    /// Where location and sensor commands go: the signed-in user's webhook, read at send time.
    public var webhookSource: any MobileAppWebhookSource { store }

    /// The webhook saved by an earlier launch, so location can report before this launch's sync (a background
    /// relaunch for a zone event never reaches the shell).
    public var savedWebhookExists: Bool { isEnabled && allowsRegistration && store.active != nil }

    /// Calls `listener` whenever ``registration`` changes (location now; sensors later).
    public func onRegistrationChange(_ listener: @escaping @MainActor (MobileAppRegistration?) -> Void) {
        listeners.append(listener)
    }

    // MARK: - Pending removals

    /// Sends the sign-out removals Home Assistant has not confirmed yet (``PendingUnregisterRetrier``). Needs no session.
    public func retryPendingUnregisters() async {
        guard isEnabled, !store.pendingUnregisters.isEmpty else { return }
        await pendingRetrier.run()
    }

    /// Retries now (launch) and again whenever the network comes back, whether or not anyone is signed in. The watcher
    /// is kept for the life of the coordinator (a dropped `NWPathMonitor` cancels itself); calling again does nothing.
    /// - Parameter reachability: The path watcher (the app's ``SystemNetworkReachability``).
    public func startPendingUnregisterRetries(reachability: any NetworkReachability = SystemNetworkReachability()) {
        guard isEnabled, self.reachability == nil else { return }
        self.reachability = reachability
        reachability.start { [weak self] isOnline in
            guard isOnline else { return }
            Task { @MainActor in await self?.retryPendingUnregisters() }
        }
        Task { await retryPendingUnregisters() }
    }

    // MARK: - Session

    /// A session started on a server.
    /// - Parameters:
    ///   - server: The signed-in server.
    ///   - accessToken: Valid access tokens for it.
    func sessionStarted(server: HassServer, accessToken: @escaping @Sendable () async throws -> String) {
        userID = nil
        linkedKey = nil
        presenceLink = nil
        setRegistration(nil)
        let client = HomeAssistantPushClient(server: server, accessToken: accessToken, transport: transport)
        registrar = MobileAppRegistrar(server: server, client: client, store: store, device: device(),
                                       allowsRegistration: allowsRegistration)
    }

    /// Takes the signed-in user, once per session.
    /// - Returns: Whether the user is new to this session (a reconnect as the same user returns false), so the
    ///   caller syncs; false too when disabled or before a session starts.
    func begin(userID: String, userName: String?) -> Bool {
        guard isEnabled, registrar != nil, self.userID != userID else { return false }
        self.userID = userID
        self.userName = userName
        return true
    }

    /// The system issued an APNs token (lowercase hex).
    /// - Returns: Whether it differs from the last one, so the caller syncs.
    func setPushToken(_ hex: String) -> Bool {
        guard hex != token else { return false }
        token = hex
        persistTokens()
        return true
    }

    /// The system's notification answer was read.
    /// - Returns: Whether it differs from the last answer, so the caller syncs.
    func setNotificationsGranted(_ granted: Bool) -> Bool {
        guard granted != notificationsGranted else { return false }
        notificationsGranted = granted
        return true
    }

    /// The Home activity's push-to-start token changed, or Live Activities were turned off (nil).
    /// - Returns: Whether it differs from the last one, so the caller syncs.
    func setStartActivityToken(_ hex: String?) -> Bool {
        if let hex { lastStartActivityToken = hex }
        persistTokens()
        guard hex != startActivityToken else { return false }
        startActivityToken = hex
        return true
    }

    /// Keeps the last tokens for the next launch. Turning Live Activities off drops the token from the next sync only;
    /// the last one stays here so turning them on restores it.
    private func persistTokens() {
        store.setDeviceTokens(DeviceTokens(push: token, startActivity: lastStartActivityToken))
    }

    /// Takes the Home activity's push-to-start token (nil removes it) and syncs the registration when it changed, so
    /// Home Assistant can start the activity while the app is closed (`.agents/platforms/apple/live-activities.md` §6).
    public func registerStartActivityToken(_ hex: String?) async {
        guard setStartActivityToken(hex) else { return }
        await sync()
    }

    /// Where the Live Activity buttons and tokens go: the signed-in user's webhook, looked up when each is sent so the
    /// App Intents work in a process the app was launched into in the background. Nil while signed out, not yet
    /// registered, disabled, or in a build that may not register (the simulator).
    public nonisolated func activityWebhookProvider() -> @Sendable () -> (any LiveActivityWebhookSending)? {
        let store = store, transport = transport, enabled = isEnabled && allowsRegistration
        return {
            guard enabled, let active = store.active else { return nil }
            return MobileAppLiveActivityWebhook(
                client: MobileAppWebhookClient(source: FixedMobileAppWebhookSource(active.webhook), transport: transport))
        }
    }

    /// Registers or updates for the session's user with the current token. Waits for a running sync first.
    public func sync() async {
        await syncTask?.value
        guard isEnabled, let registrar, let userID else { return }
        // Permission refused or revoked: the stored token is stale, so the registration goes websocket-only.
        let token = notificationsGranted == false ? nil : token, userName = userName, startActivityToken = startActivityToken
        let task = Task { [weak self] in
            guard let outcome = try? await registrar.sync(userID: userID, userName: userName, token: token,
                                                          startActivityToken: startActivityToken) else { return }
            self?.setRegistration(outcome.registration)
        }
        syncTask = task
        await task.value
    }

    /// The device fields the official app adds to the events it fires (`sourceDevicePermanentID`, `sourceDeviceName`,
    /// `sourceDeviceID`), so an automation can tell which phone fired. The vendor id stands in for the permanent id.
    public var eventDeviceInfo: [String: String] {
        let device = device()
        return ["sourceDevicePermanentID": device.deviceID, "sourceDeviceName": device.deviceName, "sourceDeviceID": device.deviceID]
    }

    /// Adds this phone's `device_tracker` to the signed-in user's person (``PresenceLinker``), once per registration and
    /// user while it holds. Call after each sync; every outcome shows in ``presenceLink``.
    /// - Parameters:
    ///   - user: The signed-in user.
    ///   - api: The websocket.
    public func linkPresence(user: HassUser, api: any HassCommandSending) async {
        guard isEnabled, allowsRegistration, let registration else { return }
        linkContext = (user, api)
        let key = registration.webhookID + "|" + user.id
        guard linkedKey != key else { return }
        let outcome = await PresenceLinker.link(webhookID: registration.webhookID, user: user, api: api)
        guard self.registration == registration else { return }
        presenceLink = outcome
        linkedKey = outcome.isLinked ? key : nil
    }

    /// Takes this phone's tracker off the signed-in user's person (``PresenceLinker/unlink(webhookID:user:api:)``).
    /// - Throws: When Home Assistant doesn't confirm, so sign-out can stay signed in.
    public func unlinkPresence(user: HassUser, api: any HassCommandSending) async throws {
        // Journeys and simulators never write to the person or entity registry.
        guard isEnabled, allowsRegistration, let webhookID = registration?.webhookID ?? store.active?.webhookID else { return }
        try await PresenceLinker.unlink(webhookID: webhookID, user: user, api: api)
        linkedKey = nil
        presenceLink = nil
    }

    /// Location was turned off: the phone can no longer say where it is, so take it off the person rather than leave a
    /// stale "home". Best effort; the next enable links again.
    public func locationWithdrawn() async {
        guard let context = linkContext else { return }
        try? await unlinkPresence(user: context.user, api: context.api)
    }

    /// Location was turned back on: put the phone back on its person when it isn't.
    public func locationRestored() async {
        guard let context = linkContext else { return }
        await linkPresence(user: context.user, api: context.api)
    }

    /// Signing out: remove this phone's registration from Home Assistant (before the refresh token is revoked).
    func sessionEnded() async {
        let registrar = registrar
        self.registrar = nil
        userID = nil
        linkedKey = nil
        presenceLink = nil
        setRegistration(nil)
        await registrar?.signOut()
    }

    /// Fires a notification button's event on the signed-in user's webhook.
    func fireAction(_ event: PushActionEvent) async throws {
        guard let registrar else { throw PushClientError.signedOut }
        try await registrar.fireAction(event)
    }

    private func setRegistration(_ new: MobileAppRegistration?) {
        guard new != registration else { return }
        registration = new
        listeners.forEach { $0(new) }
    }
}
