import ActivityKit
import FentonActivityModel
import Foundation
import HassCore

/// ActivityKit for the Home activity: the real ``LiveActivityClient``.
///
/// It lives in the app target, outside the SwiftPM coverage gate, because ActivityKit does not run on the macOS test host;
/// everything that decides what to do with it is in `HassCore/LiveActivity` and tested against a fake. This file only
/// translates (`.agents/platforms/apple/live-activities.md` §9).
struct SystemLiveActivityClient: LiveActivityClient {
    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func current() async -> [LiveActivityRecord] {
        Activity<HomeActivityAttributes>.activities.map(Self.record)
    }

    func request(attributes: HomeActivityAttributes, state: HomeActivityState, staleDate: Date?) async throws -> LiveActivityRecord {
        guard areActivitiesEnabled else { throw LiveActivityError.disabled }
        do {
            let activity = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: staleDate),
                                                pushType: .token)
            return Self.record(activity)
        } catch {
            throw LiveActivityError.refused(String(describing: error))
        }
    }

    func update(id: String, state: HomeActivityState, staleDate: Date?, relevanceScore: Double, timestamp: Date) async {
        let content = ActivityContent(state: state, staleDate: staleDate, relevanceScore: relevanceScore)
        guard let activity = Self.activity(id) else { return }
        if #available(iOS 17.2, *) {
            // ActivityKit drops an update older than the content it holds: the stamp is whole seconds, never in the future.
            await activity.update(content, alertConfiguration: nil, timestamp: timestamp)
        } else {
            await activity.update(content)
        }
    }

    func end(id: String, state: HomeActivityState?, dismissal: LiveActivityDismissal) async {
        let policy: ActivityUIDismissalPolicy = switch dismissal {
        case .immediate: .immediate
        case .systemDefault: .default
        case let .after(date): .after(date)
        }
        await Self.activity(id)?.end(state.map { ActivityContent(state: $0, staleDate: nil) }, dismissalPolicy: policy)
    }

    func pushToStartTokens() -> AsyncStream<String> {
        guard #available(iOS 17.2, *) else { return AsyncStream { $0.finish() } }
        return AsyncStream { continuation in
            let task = Task {
                for await token in Activity<HomeActivityAttributes>.pushToStartTokenUpdates { continuation.yield(PushToken.hex(token)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func activityUpdates() -> AsyncStream<LiveActivityRecord> {
        AsyncStream { continuation in
            let task = Task {
                for await activity in Activity<HomeActivityAttributes>.activityUpdates { continuation.yield(Self.record(activity)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func pushTokenUpdates(id: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            // Looked up inside the task: an `Activity` is not Sendable, so it cannot cross into it.
            let task = Task {
                if let activity = Self.activity(id) {
                    for await token in activity.pushTokenUpdates { continuation.yield(PushToken.hex(token)) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func lifecycleUpdates(id: String) -> AsyncStream<LiveActivityLifecycle> {
        AsyncStream { continuation in
            let task = Task {
                guard let activity = Self.activity(id) else {
                    continuation.finish()
                    return
                }
                for await state in activity.activityStateUpdates {
                    let lifecycle = Self.lifecycle(state)
                    continuation.yield(lifecycle)
                    if lifecycle == .dismissed { break }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func enablementUpdates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let task = Task {
                for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates { continuation.yield(enabled) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Translating

    private static func activity(_ id: String) -> Activity<HomeActivityAttributes>? {
        Activity<HomeActivityAttributes>.activities.first { $0.id == id }
    }

    private static func record(_ activity: Activity<HomeActivityAttributes>) -> LiveActivityRecord {
        LiveActivityRecord(id: activity.id, attributes: activity.attributes, state: activity.content.state,
                           lifecycle: lifecycle(activity.activityState), relevanceScore: activity.content.relevanceScore)
    }

    private static func lifecycle(_ state: ActivityState) -> LiveActivityLifecycle {
        // iOS 26 added `.pending` (an activity scheduled to start later). It exists and takes updates, so it counts as
        // active. Compared rather than switched on: a `case` cannot carry an availability check, and a switch without
        // `.pending` warns on the iOS 27 SDK while one with it does not build for iOS 17.
        if #available(iOS 26.0, *), state == .pending { return .active }
        if state == .active { return .active }
        if state == .stale { return .stale }
        if state == .dismissed { return .dismissed }
        return .ended
    }
}
