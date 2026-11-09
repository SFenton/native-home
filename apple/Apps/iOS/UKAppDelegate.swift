import FentonActivityModel
import HassCore
import HassUI
import UIKit
import UserNotifications

/// The app's delegate: the one session, push, location and Live Activity wiring, with each window's root drawn by UIKit
/// (``UKSceneDelegate``, `HassUI/UIKitPort`). Supplies supported orientations (iPhone stays portrait in Info.plist, iPad
/// keeps all four, and a device with a hinge, iPhone Duo, rotates folded or unfolded; owner, 2026-10-10) and forwards push
/// callbacks to ``PushCoordinator`` (`.agents/platforms/apple/push.md`).
@main
final class UKAppDelegate: NSObject, UIApplicationDelegate {
    let push = PushLaunchPolicy.isEnabled()
        ? PushCoordinator(platform: .system)
        : PushCoordinator(platform: .system, store: InMemoryMobileAppRegistrationStore(), isEnabled: false)

    private(set) lazy var location: LocationCoordinator? =
        LocationLaunchPolicy.isEnabled()
            ? LocationCoordinator.system(mobileApp: push.mobileApp) : nil

    /// Background App Refresh for location; nil in journeys.
    private var backgroundRefresh: SystemBackgroundRefresh?

    private(set) lazy var liveActivities = LiveActivityLaunchPolicy.isEnabled()
        ? LiveActivityCoordinator(client: SystemLiveActivityClient(), mobileApp: push.mobileApp)
        : LiveActivityCoordinator.inert(mobileApp: push.mobileApp)

    /// The app's one session, shared by every window.
    @MainActor lazy var session = AppSession(push: push, location: location, liveActivities: liveActivities,
                                             spotlight: CoreSpotlightIndexer())

    override init() {
        super.init()
        // Launch to first frame and to the snapshot are timed from here (`Telemetry.beginTracked`).
        AppSession.beginLaunchMeasurement()
        #if DEBUG
        // The names (never the values) of the `FENTON_*` launch variables, so a journey that finds the app on the wrong screen can
        // tell from the simulator log whether its launch environment arrived (BackdropBlur's first launch of a coverage batch came
        // up signed out with neither its gallery nor its reuse directory, 2026-11-04).
        NSLog("UKLaunch variables: %@", ProcessInfo.processInfo.environment.keys.filter { $0.hasPrefix("FENTON_") }.sorted().joined(separator: " "))
        // UI-test speed: `FENTON_UITEST_NO_ANIMATIONS=1` (set by the journeys' launch helper, left off by the motion and
        // performance tests that measure animation) runs every window's animations 10x faster. Faster, not off: with
        // `UIView.setAnimationsEnabled(false)` a swipe on an iPhone sheet's content dismissed the sheet (2026-10-30), because
        // the sheet's drag settles through an animation.
        if ProcessInfo.processInfo.environment["FENTON_UITEST_NO_ANIMATIONS"] == "1" {
            _ = NotificationCenter.default.addObserver(forName: UIWindow.didBecomeVisibleNotification, object: nil, queue: .main) { note in
                let window = note.object as? UIWindow
                MainActor.assumeIsolated { window?.layer.speed = Self.uiTestAnimationSpeed }
            }
        }
        #endif
    }

    #if DEBUG
    /// How much faster than normal the UI tests run animations (`FENTON_UITEST_NO_ANIMATIONS`): 10, or the positive number in
    /// `FENTON_UITEST_ANIMATION_SPEED` when the launch sets one (a missing, non-numeric or non-positive value keeps 10).
    static let uiTestAnimationSpeed: Float = {
        if let text = ProcessInfo.processInfo.environment["FENTON_UITEST_ANIMATION_SPEED"], let speed = Float(text),
           speed.isFinite, speed > 0 { return speed }
        return 10
    }()
    #endif

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        _ = NotificationCenter.default.addObserver(forName: UIScene.willConnectNotification, object: nil, queue: .main) { [weak self] note in
            guard let scene = note.object as? UIScene else { return }
            MainActor.assumeIsolated { self?.adoptRestoredScene(scene) }
        }
        #if DEBUG
        NSLog("UKScenes openSessions at launch: %@", application.openSessions.map {
            "\($0.configuration.name ?? "nil") -> \($0.configuration.delegateClass.map(String.init(describing:)) ?? "nil")"
        }.joined(separator: ", "))
        #endif
        // A removal that couldn't reach Home Assistant at sign-out retries now and when the network returns.
        push.mobileApp.startPendingUnregisterRetries()
        LiveActivityIntentRuntime.install(liveActivities.isEnabled ? liveActivities.intentHandler : nil)
        AppIconAppGroupSync.writeInstalledChoice()
        AppShortcutRouter.install { [push] destination in push.open(destination) }
        // Home Assistant's request_location_update push runs the location coordinator's one-shot update.
        push.locationUpdateHandler = { [weak self] in await self?.location?.handleLocationRequest() ?? false }
        if let location {
            // Background App Refresh: registered before launch finishes (iOS requires it), as in the SwiftUI app.
            let refresh = SystemBackgroundRefresh { [weak location] in await location?.backgroundFetch() ?? false }
            refresh.schedule()
            backgroundRefresh = refresh
            Task { await location.resume() }
        }
        #if DEBUG
        LiveActivityDebugLaunch.startIfRequested(client: SystemLiveActivityClient())
        DebugSystemSettings.applyIfRequested()
        PushPreview.scheduleIfRequested()
        if let command = PushPreview.command() {
            Task {
                try? await Task.sleep(for: .seconds(2))
                await push.handleBackground(userInfo: command)
            }
        }
        #endif
        return true
    }

    /// New windows get the app's own scene delegate. A session iOS restored from the SwiftUI app never comes here; see
    /// ``adoptRestoredScene(_:)``.
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: UKSceneUpgrade.configurationName, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = UKSceneDelegate.self
        return configuration
    }

    /// Upgrade over the SwiftUI app: a restored `UISceneSession` keeps the delegate class the SwiftUI app gave it, which
    /// draws no window here (black screen). Any connecting window scene whose delegate is not ``UKSceneDelegate`` gets one
    /// (`UIScene.delegate` is held strongly) and, if the connect callback already went to the foreign delegate, its window.
    @MainActor
    private func adoptRestoredScene(_ scene: UIScene) {
        guard scene is UIWindowScene, UKSceneUpgrade.needsAdoption(sceneDelegate: scene.delegate, ours: UKSceneDelegate.self)
        else { return }
        #if DEBUG
        NSLog("UKScenes adopting %@ delegate=%@", String(describing: scene), String(describing: scene.delegate))
        #endif
        let delegate = UKSceneDelegate()
        scene.delegate = delegate
        // If UIKit has not yet delivered `scene(_:willConnectTo:)` it now reaches the new delegate with the real options;
        // otherwise connect with none. `connect` ignores a second call.
        DispatchQueue.main.async { [weak scene] in
            guard let scene else { return }
            MainActor.assumeIsolated { delegate.connect(scene, options: nil) }
        }
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        FentonOrientationSupport.mask(for: window)
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await push.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {}

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await push.handleBackground(userInfo: userInfo) ? .newData : .noData
    }
}

extension UKAppDelegate: @preconcurrency UNUserNotificationCenterDelegate {
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let action: NotificationResponse = switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier: .open
        case UNNotificationDismissActionIdentifier: .dismiss
        default: .action(response.actionIdentifier, replyText: (response as? UNTextInputNotificationResponse)?.userText)
        }
        Task {
            await push.handle(action, userInfo: userInfo)
            completionHandler()
        }
    }
}

/// One window: its root is `UKApp`'s, its URLs and Spotlight taps go to the session.
final class UKSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    @MainActor private var session: AppSession? { (UIApplication.shared.delegate as? UKAppDelegate)?.session }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        MainActor.assumeIsolated { connect(scene, options: connectionOptions) }
    }

    /// Builds the window once per scene; a repeat call (the upgrade adoption racing UIKit's own) does nothing.
    @MainActor
    func connect(_ scene: UIScene, options connectionOptions: UIScene.ConnectionOptions?) {
        #if DEBUG
        NSLog("UKScenes connect window=%@ session=%@", String(describing: window), String(describing: session != nil))
        #endif
        guard window == nil, let windowScene = scene as? UIWindowScene, let appSession = self.session else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UKApp.makeRootViewController(session: appSession)
        window.makeKeyAndVisible()
        self.window = window
        connectionOptions?.urlContexts.forEach { UKApp.open($0.url, session: appSession) }
        connectionOptions?.userActivities.forEach { UKApp.continue($0, session: appSession) }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let session else { return }
        URLContexts.forEach { UKApp.open($0.url, session: session) }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let session else { return }
        UKApp.continue(userActivity, session: session)
    }
}
