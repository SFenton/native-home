import Foundation
import HassCore
import Observation
#if os(iOS)
import UIKit
#endif

/// Location reporting for the signed-in session (`.agents/platforms/apple/location.md`).
///
/// Every iOS device has one when ``LocationLaunchPolicy`` allows it. It reports to the app's own `mobile_app` device
/// tracker through the shared registration. A phone also puts that tracker on the signed-in user's person
/// (``linksPresence``, ``linkPresence(user:api:)``); an iPad never does (interim rule, owner 2026-10-27), so an iPad
/// left at home cannot mark the person home.
///
/// - Starts the ``LocationReporter`` whenever a webhook exists (this session's sync, or one saved by an earlier
///   launch) and the permission allows it; there is no separate switch. Stops on sign-out.
/// - Says whether the Setup flow still has a location step to show (``needsPermissionStep``); the flow
///   (``SetupCoordinator``) owns presenting it and remembering that it was shown.
/// - A deleted registration (410) syncs once more, which registers again, and reporting resumes on the new webhook.
@MainActor
@Observable
public final class LocationCoordinator {
    /// The reporter this session drives.
    public let reporter: LocationReporter
    /// Whether this device's tracker is put on the signed-in person. True on phones, false on iPad.
    public let linksPresence: Bool
    /// Whether the app already asked to upgrade to Always. iOS shows that alert once; afterwards the While Using
    /// stage sends people to Settings.
    public private(set) var hasAskedForAlways: Bool

    /// What the last attempt to put this phone on its person did, for Settings.
    public var mobileAppPresenceLink: PresenceLinkOutcome? { mobileApp.presenceLink }

    @ObservationIgnored private let mobileApp: MobileAppCoordinator
    @ObservationIgnored private let defaults: UserDefaults
    /// Set while a sync after a 410 runs, so one deleted registration re-registers at most once per start.
    @ObservationIgnored private var isRecovering = false
    /// Whether the app is in the background right now (`UIApplication.applicationState`); a relaunch for a zone event,
    /// a push or a refresh is.
    @ObservationIgnored private let isInBackground: @MainActor () -> Bool
    /// Whether the next time the app is in use counts as opening it, which sends one Launch update. Armed at
    /// startup and each time the app enters the background (the official `LifecycleManager`): reactivating inside
    /// one foreground session, after a system alert or the app switcher, sends nothing.
    @ObservationIgnored private var needsAppOpenUpdate = true
    /// Called by a Background App Refresh when location may not be sent in the app's state (not Always, or off),
    /// where the official app still sends its sensors. Sends the sensors alone with the Background Fetch trigger
    /// (``LocationReporter/updateSensorsOnly(_:)``); a seam so tests can observe the call.
    @ObservationIgnored public var sendSensorsOnly: @MainActor () async -> Void = {}

    /// `UserDefaults` key: the permission screen was offered after sign-in. Superseded by `setup.stepsSeen`
    /// (``SetupFlow``), which reads it once as "the location step was seen".
    nonisolated static let offeredKey = "location.permissionOffered"
    /// `UserDefaults` key: the Always alert was shown.
    nonisolated static let askedForAlwaysKey = "location.askedForAlways"

    /// Creates a coordinator.
    /// - Parameters:
    ///   - platform: Core Location, or a fake in tests.
    ///   - mobileApp: The shared registration.
    ///   - transport: HTTP to Home Assistant.
    ///   - batteryLevel: The battery percentage sent with each update.
    ///   - linksPresence: Whether the tracker follows the signed-in person (phones); false on iPad.
    ///   - defaults: Where the once-per-install flags and the cached zones live.
    ///   - backgroundTime: Keeps the app awake while a location event is reported.
    ///   - statusSource: Reads the device for the sensors sent with every update; nil sends no sensors.
    ///   - appVersion: The app version; the sensors are registered again when it changes.
    public init(platform: any LocationPlatform, mobileApp: MobileAppCoordinator,
                transport: any FeedbackHTTPTransport = URLSessionFeedbackTransport(),
                batteryLevel: @escaping @MainActor () -> Int? = { nil }, linksPresence: Bool = true,
                defaults: UserDefaults = .standard, backgroundTime: any BackgroundTime = NoBackgroundTime(),
                isInBackground: @escaping @MainActor () -> Bool = { false },
                statusSource: (any DeviceStatusSource)? = nil, appVersion: String = "") {
        self.isInBackground = isInBackground
        let client = MobileAppWebhookClient(source: mobileApp.webhookSource, transport: transport)
        let sensors = statusSource.map {
            SensorReporter(client: client, source: $0, appVersion: appVersion, memory: SensorRegistrationMemory(defaults))
        }
        reporter = LocationReporter(platform: platform, client: client, linksPresence: linksPresence, batteryLevel: batteryLevel,
                                    zoneStore: UserDefaultsZoneStore(defaults: defaults), backgroundTime: backgroundTime,
                                    deviceInfo: { [weak mobileApp] in mobileApp?.eventDeviceInfo ?? [:] }, sensors: sensors)
        self.linksPresence = linksPresence
        self.mobileApp = mobileApp
        self.defaults = defaults
        hasAskedForAlways = defaults.bool(forKey: Self.askedForAlwaysKey)
        mobileApp.onRegistrationChange { [weak self] registration in
            Task { await self?.registrationChanged(registration) }
        }
        reporter.onPermissionChange = { [weak self] permission in
            Task { await self?.permissionChanged(permission) }
        }
        sendSensorsOnly = { [weak self] in await self?.reporter.updateSensorsOnly(.backgroundFetch) }
    }

    // MARK: - Lifecycle

    /// The app launched (in the foreground or for a location event): report on the webhook saved by an earlier
    /// launch, without waiting for the websocket.
    public func resume() async {
        await startIfReady()
    }

    /// The app became active: start if a webhook and permission arrived while it was away, and send the app-open
    /// fix (the only report While Using allows) if this is the first activation since launch or since the app was
    /// in the background (``didEnterBackground()``).
    public func didBecomeActive() async {
        await startIfReady()
        await sendAppOpenUpdateIfNeeded()
        await recoverIfGone()
    }

    /// The app entered the background: the next activation opens it again and sends a Launch update.
    public func didEnterBackground() {
        needsAppOpenUpdate = true
    }

    /// Sends the Launch update once per foreground session. Never in the background: a relaunch for a zone event
    /// or a push is not the person opening the app.
    private func sendAppOpenUpdateIfNeeded() async {
        guard needsAppOpenUpdate, reporter.isRunning, !isInBackground() else { return }
        needsAppOpenUpdate = false
        await reporter.report(.launch)
    }

    // MARK: - Requests from outside

    /// Home Assistant asked for a location update by push (`request_location_update`,
    /// `.agents/platforms/apple/location.md`). Starts reporting if a relaunch for the push got here first, holds
    /// background time, takes a one-shot fix (10 s at most) and sends it with the Push Notification trigger.
    /// - Returns: Whether an update was sent; false without a webhook or the permission the app's state needs.
    @discardableResult
    public func handleLocationRequest() async -> Bool {
        // Background time first, and no network before the fix: the zones are read after the send, inside the hold.
        await reporter.requestUpdate(.pushNotification, inBackground: isInBackground()) { [self] in
            await startIfReady(deferZoneRefresh: true)
        }
    }

    /// A Background App Refresh ran (``BackgroundRefresh``): sends a location update with the Background Fetch
    /// trigger when location is allowed in the app's state; otherwise runs ``sendSensorsOnly``, as the official app
    /// does.
    /// - Returns: Whether the refresh did its job: an update was sent, or there was nothing to send location to.
    @discardableResult
    public func backgroundFetch() async -> Bool {
        await startIfReady(deferZoneRefresh: true)
        guard hasWebhook else { return false }
        if reporter.canReport(inBackground: isInBackground()) {
            return await reporter.requestUpdate(.backgroundFetch, inBackground: isInBackground())
        }
        await sendSensorsOnly()
        return true
    }

    /// Whether a webhook exists to send to.
    private var hasWebhook: Bool { mobileApp.registration != nil || mobileApp.savedWebhookExists }

    /// Off (denied, restricted, or no longer precise enough to say home): stop and take the phone off its person so
    /// it doesn't hold a stale "home". On: start at once (a fresh update, zones again) and put it back on.
    func permissionChanged(_ permission: LocationPermission) async {
        if permission.isAuthorized {
            await startIfReady()
            if linksPresence { await mobileApp.locationRestored() }
        } else {
            await reporter.stop()
            if linksPresence { await mobileApp.locationWithdrawn() }
        }
    }

    func startIfReady(deferZoneRefresh: Bool = false) async {
        guard hasWebhook, reporter.permission.isAuthorized, !reporter.isRunning else { return }
        await reporter.start(reportLaunch: false, deferZoneRefresh: deferZoneRefresh)
        await sendAppOpenUpdateIfNeeded()
        await recoverIfGone()
    }

    func registrationChanged(_ registration: MobileAppRegistration?) async {
        if registration == nil {
            await reporter.stop()
        } else {
            await startIfReady()
        }
    }

    /// After a 410 the reporter has stopped; one sync registers again, and the new registration restarts it.
    private func recoverIfGone() async {
        guard reporter.lastError == .registrationGone, !isRecovering else { return }
        isRecovering = true
        defer { isRecovering = false }
        await mobileApp.sync()
    }

    // MARK: - Presence

    /// Puts this phone's tracker on the signed-in user's person. Does nothing on an iPad, which reports but never
    /// follows a person (``PresenceLinker`` is not reached).
    public func linkPresence(user: HassUser, api: any HassCommandSending) async {
        guard linksPresence else { return }
        await mobileApp.linkPresence(user: user, api: api)
    }

    /// Takes this phone's tracker off the signed-in user's person before sign-out. An iPad never linked, so it has
    /// nothing to remove and nothing to wait for.
    /// - Throws: When Home Assistant doesn't confirm, so sign-out can stay signed in.
    public func unlinkPresence(user: HassUser, api: any HassCommandSending) async throws {
        guard linksPresence else { return }
        try await mobileApp.unlinkPresence(user: user, api: api)
    }

    // MARK: - Permission

    /// Whether the Setup flow's location step has something to ask: nothing is set yet, or While Using can still be
    /// upgraded to Always (iOS shows that alert once). Always, Off and Approximate have nothing to ask.
    public var needsPermissionStep: Bool {
        switch reporter.permission.stage {
        case .notDetermined: true
        case .whenInUse: !hasAskedForAlways
        default: false
        }
    }

    /// Shows the next system alert, remembering the Always request (iOS shows it once).
    public func requestPermission() {
        if reporter.permission.authorization == .whenInUse {
            hasAskedForAlways = true
            defaults.set(true, forKey: Self.askedForAlwaysKey)
        }
        reporter.requestPermission()
    }

    /// Forgets the once-per-install flags, the Setup flow's seen steps included (UI journeys that start from a reset).
    public static func resetOffers(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: offeredKey)
        defaults.removeObject(forKey: SetupFlow.seenKey)
        defaults.removeObject(forKey: askedForAlwaysKey)
    }
}

#if os(iOS)
public extension LocationCoordinator {
    /// The app's coordinator on Core Location, sending the battery level with each update. Create it at launch, on
    /// the main thread, so a relaunch for a zone event reopens the zone monitor.
    static func system(mobileApp: MobileAppCoordinator) -> LocationCoordinator {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return LocationCoordinator(platform: CoreLocationPlatform(), mobileApp: mobileApp, batteryLevel: {
            let level = UIDevice.current.batteryLevel
            return level < 0 ? nil : Int((level * 100).rounded())
        }, linksPresence: LocationReporter.deviceLinksPresence, backgroundTime: UIKitBackgroundTime(),
        isInBackground: { UIApplication.shared.applicationState == .background },
        statusSource: SystemDeviceStatusSource(), appVersion: SystemDeviceStatusSource.appVersion)
    }
}
#endif
