#if os(iOS)
import HassCore
import HassTelemetry
import MessageUI
import Observation
import UIKit

// MARK: - App state

/// Gathers the values of the `app-state@1` source (`sh.app-state@1`): the window, the clock, the system, the notification permission
/// and the person's preferences.
///
/// It follows the app's one state path: the window comes from the window scene's size and size classes, the notification permission
/// and the dismissed banner from the one ``PushCoordinator``, the preferences from `UserDefaults`, the system facts from UIKit.
/// Nothing here is polled and nothing is written per frame:
///
/// - **window** updates on a size or size-class change (``updateWindow(size:traits:)`` writes only when a value differs);
/// - **clock** updates once a minute, on the minute, and only while something reads it: the first read starts a tick and a tick that
///   finds no read since the last one stops it, so a document with no clock reader costs no timer;
/// - **os** updates when the person changes Reduce Motion or Reduce Transparency;
/// - **notifications** and the dismissed banner follow the coordinator's own observed properties;
/// - **preferences** update on a change to the setting.
///
/// Each topic is its own observed property, so a node that reads the window re-runs when the window changes and not when the minute
/// does. A topic that has not been gathered reads `loading`, so a node that waits on it keeps what it showed.
@MainActor
@Observable
final class UKServerUIAppStateSource {
    private(set) var window: ServerUIAppState.Window?
    private(set) var clock: ServerUIClock?
    /// The wall time to the second, published once a second while something reads it (`now-second`, `sh.countdown@1`).
    private(set) var secondClock: ServerUIClock?
    private(set) var os: ServerUIAppState.OS?
    private(set) var showCountOnIcon: Bool?

    @ObservationIgnored private weak var push: PushCoordinator?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var tick = ServerUIMinuteTick()
    @ObservationIgnored private var secondTicker: Task<Void, Never>?
    /// How many times the second clock was published, for the tests of the 1 Hz path.
    @ObservationIgnored private(set) var secondTicks = 0
    /// Whether the one-second tick is scheduled: `false` until something reads `now-second`, and again one tick after the last read.
    var isSecondTicking: Bool { secondTick.isRunning }
    @ObservationIgnored private var secondReadGate: (@MainActor () -> Bool)?
    @ObservationIgnored private var secondReadInRun = false
    @ObservationIgnored private var secondTick = ServerUIMinuteTick()
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []

    init(push: PushCoordinator?, defaults: UserDefaults = .standard) {
        self.push = push
        self.defaults = defaults
        let center = NotificationCenter.default
        let refreshOS: @Sendable (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.refreshOS() } }
        tokens = [
            center.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main, using: refreshOS),
            center.addObserver(forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil, queue: .main,
                               using: refreshOS),
            center.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshPreferences() }
            },
            // A change of day, zone or clock setting moves the minute without waiting for the tick.
            center.addObserver(forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.publishClock() }
            },
        ]
    }

    isolated deinit {
        ticker?.cancel()
        secondTicker?.cancel()
        tokens.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: Reading

    /// What reading `field` of `topic` gives, and the one place a read starts what that topic needs: the clock's tick, the first gather.
    ///
    /// A value is gathered before it is read, so the first read answers with it instead of `loading` and a re-run.
    func read(_ topic: ServerUIAppState.Topic, field: String) -> ServerUIReadResult {
        switch topic {
        case .window: return ServerUIAppState(window: window).read(topic, field: field)
        case .clock:
            noteClockRead()
            return ServerUIAppState(clock: clock).read(topic, field: field)
        case .os:
            if os == nil { os = Self.currentOS() }
            return ServerUIAppState(os: os).read(topic, field: field)
        case .notifications:
            guard let push else { return ServerUIAppState().read(topic, field: field) }
            return ServerUIAppState(notifications: Self.notifications(of: push)).read(topic, field: field)
        case .preferences:
            if showCountOnIcon == nil { showCountOnIcon = Self.showCount(defaults) }
            let state = ServerUIAppState(preferences: .init(showCountOnIcon: showCountOnIcon ?? true,
                                                            notificationBannerDismissed: push?.bannerDismissed ?? false))
            return state.read(topic, field: field)
        }
    }

    /// The clock for `clock` and `date` operands. Reading it is a clock read: it starts the minute tick.
    func clockForReading() -> ServerUIClock? {
        noteClockRead()
        return clock
    }

    /// The clock for `now-second`. Reading it is a second-clock read: it starts the one-second tick (`sh.countdown@1`).
    func secondClockForReading() -> ServerUIClock? {
        secondReadInRun = true
        // Read from a page that is not on screen: the time now, with no tick started or kept and nothing tracked, so it ticks for nobody.
        if let gate = secondReadGate, !gate() { return ServerUIAppState.clock(at: Date()) }
        let starts = secondTick.noteRead()
        if secondClock == nil || starts { publishSecondClock() }
        if starts { startSecondTicking() }
        return secondClock
    }

    /// Runs `body`, one run of a node's observations, with its second-clock reads gated by `isOnScreen`; `true` when `body` read the second clock.
    ///
    /// The gate is read only when the clock is read, inside the observation, so the node tracks the page's presence exactly when it ticks: it runs again
    /// when the page comes back.
    func gatingSecondClock(_ isOnScreen: @escaping @MainActor () -> Bool, _ body: @MainActor () -> Void) -> Bool {
        let outerGate = secondReadGate, outerRead = secondReadInRun
        secondReadGate = isOnScreen
        secondReadInRun = false
        body()
        let read = secondReadInRun
        secondReadGate = outerGate
        secondReadInRun = outerRead || read
        return read
    }

    // MARK: Window

    /// Records the window's size and size classes. Writes only when a value differs, so a layout pass that changes nothing costs nothing.
    func updateWindow(size: CGSize, traits: UITraitCollection) {
        let value = ServerUIAppState.Window(
            widthClass: traits.horizontalSizeClass == .regular ? .regular : .compact,
            heightClass: traits.verticalSizeClass == .regular ? .regular : .compact,
            width: Double(size.width.rounded()), height: Double(size.height.rounded()))
        if window != value { window = value }
    }

    // MARK: Clock

    private func noteClockRead() {
        let starts = tick.noteRead()
        // Gather before the property is read, so the read that starts the tick already has a value. While the tick runs it keeps the
        // value current, so a read costs nothing.
        if clock == nil || starts { publishClock() }
        if starts { startTicking() }
    }

    /// Publishes the clock when the minute has moved: one write a minute, never more. Not private so a hosted test can move the minute.
    func publishClock(now: Date = Date()) {
        let next = ServerUIAppState.clock(at: now)
        if let clock, clock.now.prefix(16) == next.now.prefix(16), clock.utcOffsetMinutes == next.utcOffsetMinutes { return }
        clock = next
    }

    private func startTicking() {
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(ServerUIAppState.secondsToNextMinute(from: Date()) + 0.05))
                guard let self, !Task.isCancelled else { return }
                // Nobody read the clock since the last tick: stop. The next read starts it again.
                guard self.tick.fire() else { self.ticker = nil; return }
                self.publishClock()
            }
        }
    }

    /// Publishes the wall time when the second has moved: one write a second, and only while a document reads it.
    private func publishSecondClock(now: Date = Date()) {
        let interval = Telemetry.begin(Telemetry.Name.secondTick, page: "SecondClock")
        let next = ServerUIAppState.clock(at: now)
        if secondClock != next { secondClock = next }
        Telemetry.end(interval)
        secondTicks += 1
    }

    private func startSecondTicking() {
        secondTicker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1) + 0.005))
                guard let self, !Task.isCancelled else { return }
                // Nobody read the second clock since the last tick: stop. The next read starts it again.
                guard self.secondTick.fire() else { self.secondTicker = nil; return }
                self.publishSecondClock()
            }
        }
    }

    // MARK: System and preferences

    private static func currentOS() -> ServerUIAppState.OS {
        ServerUIAppState.OS(major: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                            supportsAlternateIcons: UIApplication.shared.supportsAlternateIcons,
                            reduceMotion: UKMotion.reduceMotion,
                            reduceTransparency: UIAccessibility.isReduceTransparencyEnabled,
                            canSendMail: MFMailComposeViewController.canSendMail())
    }

    private func refreshOS() {
        guard os != nil else { return }
        let value = Self.currentOS()
        if os != value { os = value }
    }

    private static func showCount(_ defaults: UserDefaults) -> Bool {
        defaults.object(forKey: AppIconBadgeSync.enabledKey) as? Bool ?? true
    }

    private func refreshPreferences() {
        guard showCountOnIcon != nil else { return }
        let value = Self.showCount(defaults)
        if showCountOnIcon != value { showCountOnIcon = value }
    }

    private static func notifications(of push: PushCoordinator) -> ServerUIAppState.Notifications {
        let permission: String = switch push.authorization {
        case .notDetermined: "not-determined"
        case .granted: "authorized"
        case .denied: "denied"
        }
        let timeSensitive: String = switch push.timeSensitive {
        case .enabled: "enabled"
        case .disabled: "disabled"
        case .notSupported: "not-supported"
        }
        return .init(permission: permission, timeSensitive: timeSensitive)
    }
}
#endif
