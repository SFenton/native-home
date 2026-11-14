import FentonActivityModel
import Foundation
import HassCore
import Observation

/// The Live Activities for the signed-in session (`.agents/platforms/apple/live-activities-per-job.md` §2).
///
/// Home Assistant's `fenton_home` engine is the only writer of job content, so this coordinator does only what the phone
/// must:
/// - **Tokens**: reports the push-to-start token with the registration and each activity's update token to Home
///   Assistant (``LiveActivityTokenReporter``), so the server can start and update cards while the app is closed.
/// - **Buttons**: hands the card's button presses to ``HomeActivityActionHandler`` (``intentHandler``).
/// - **Sign-out**: ends every card (``sessionEnded()``).
///
/// It starts nothing locally and reads no entities: the foreground director, the planner and the job deriver are gone.
/// Created with the app delegate and started with each session.
@MainActor
@Observable
public final class LiveActivityCoordinator {
    /// Whether the feature runs in this launch (``LiveActivityLaunchPolicy``).
    public let isEnabled: Bool

    @ObservationIgnored private let client: any LiveActivityClient
    @ObservationIgnored private let mobileApp: MobileAppCoordinator
    @ObservationIgnored private let reporter: LiveActivityTokenReporter

    /// Creates a coordinator.
    /// - Parameters:
    ///   - client: ActivityKit, or a fake in tests.
    ///   - mobileApp: The shared registration, which carries the push-to-start token and the webhook.
    ///   - isEnabled: Run at all; off for journeys signed in with a test token.
    ///   - now: The clock.
    public init(client: any LiveActivityClient, mobileApp: MobileAppCoordinator, isEnabled: Bool = true,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.mobileApp = mobileApp
        self.isEnabled = isEnabled
        reporter = LiveActivityTokenReporter(
            client: client, webhook: mobileApp.activityWebhookProvider(),
            registerStartToken: { [mobileApp] token in await mobileApp.registerStartActivityToken(token) },
            lastKnownStartToken: { [mobileApp] in mobileApp.knownStartActivityToken() }, now: now)
    }

    /// A coordinator that never starts anything.
    public static func inert(mobileApp: MobileAppCoordinator) -> LiveActivityCoordinator {
        LiveActivityCoordinator(client: InertLiveActivityClient(), mobileApp: mobileApp, isEnabled: false)
    }

    /// The handler for the activity's buttons (installed at launch with ``LiveActivityIntentRuntime/install(_:)``).
    public var intentHandler: any LiveActivityIntentRuntime.Handler {
        HomeActivityActionHandler(client: client, webhook: mobileApp.activityWebhookProvider())
    }

    // MARK: - Session

    /// A session started: report tokens.
    public func sessionStarted() {
        guard isEnabled else { return }
        reporter.start()
    }

    /// Signing out: end every card, telling Home Assistant about each, and stop reporting.
    public func sessionEnded() async {
        await reporter.endAll()
    }
}

/// Whether Live Activities run in this launch.
public enum LiveActivityLaunchPolicy {
    /// Off for debug UI journeys (a test token, a reset launch, or the component gallery) unless
    /// `FENTON_LIVE_ACTIVITY` is set, so a journey never reacts to the real house.
    public static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        #if DEBUG
        if !(environment["FENTON_LIVE_ACTIVITY"] ?? "").isEmpty { return true }
        let journey = ["FENTON_HASS_TOKEN", "FENTON_UITEST_RESET", "FENTON_GALLERY"].contains { !(environment[$0] ?? "").isEmpty }
        return !journey
        #else
        return true
        #endif
    }
}
