import FentonActivityModel
import Foundation

/// How far along an activity is in the system's eyes.
public enum LiveActivityLifecycle: String, Sendable, Equatable {
    /// On the Lock Screen and in the island.
    case active
    /// Past its stale date: the views show "Updating…" until a push arrives.
    case stale
    /// Ended by the app or the system; still on the Lock Screen until dismissed.
    case ended
    /// Removed, by the person swiping it away or by the system.
    case dismissed

    /// Whether the activity can still be updated.
    public var isLive: Bool { self == .active || self == .stale }
}

/// One Live Activity as the system reports it.
public struct LiveActivityRecord: Sendable, Equatable, Identifiable {
    /// ActivityKit's id.
    public var id: String
    /// The attributes' tag (`job.fan.demo_fan`): the key Home Assistant's `mobile_app` stores the update token under.
    public var tag: String
    /// The attributes.
    public var attributes: HomeActivityAttributes
    /// The content now.
    public var state: HomeActivityState
    /// Where it is.
    public var lifecycle: LiveActivityLifecycle
    /// The relevance score Home Assistant last set (it orders the Dynamic Island and the Lock Screen). The app keeps it
    /// when it writes its own optimistic state, so a press never re-ranks the card.
    public var relevanceScore: Double

    /// Creates a record.
    public init(id: String, attributes: HomeActivityAttributes, state: HomeActivityState, lifecycle: LiveActivityLifecycle = .active,
                relevanceScore: Double = 0) {
        self.id = id
        tag = attributes.tag
        self.attributes = attributes
        self.state = state
        self.lifecycle = lifecycle
        self.relevanceScore = relevanceScore
    }
}

/// When an ended activity leaves the Lock Screen.
public enum LiveActivityDismissal: Sendable, Equatable {
    /// At once.
    case immediate
    /// The system's default (up to four hours).
    case systemDefault
    /// At a date (the linger of a finished job; the system caps it at four hours).
    case after(Date)
}

/// ActivityKit behind a seam, so the logic that decides what to show runs against a fake in tests. The real one is
/// `SystemLiveActivityClient` in `apple/Apps/Shared`.
public protocol LiveActivityClient: Sendable {
    /// The person allows Live Activities for this app (Settings, Face ID & Passcode, Live Activities too).
    var areActivitiesEnabled: Bool { get }

    /// Every job activity the system still holds, including ones a push started while the app was closed.
    func current() async -> [LiveActivityRecord]

    /// Starts an activity with `pushType: .token`, so Home Assistant can update it.
    func request(attributes: HomeActivityAttributes, state: HomeActivityState, staleDate: Date?) async throws -> LiveActivityRecord

    /// Updates an activity's content. `timestamp` is whole seconds, never in the future (``ActivityClock/wholeSecond(_:)``):
    /// ActivityKit drops an update older than the content it holds, and the engine's confirmation must be newer than this
    /// write. `relevanceScore` is kept from the record.
    func update(id: String, state: HomeActivityState, staleDate: Date?, relevanceScore: Double, timestamp: Date) async

    /// Ends an activity, optionally with its last content (the "Done" row).
    func end(id: String, state: HomeActivityState?, dismissal: LiveActivityDismissal) async

    /// The push-to-start token, now and whenever it changes (iOS 17.2+; finishes at once on older systems).
    func pushToStartTokens() -> AsyncStream<String>

    /// Each activity that appears, including ones a push-to-start created.
    func activityUpdates() -> AsyncStream<LiveActivityRecord>

    /// An activity's update token, now and whenever it changes.
    func pushTokenUpdates(id: String) -> AsyncStream<String>

    /// An activity's lifecycle changes; finishes when it is dismissed.
    func lifecycleUpdates(id: String) -> AsyncStream<LiveActivityLifecycle>

    /// Whether the person allows activities, now and whenever the setting changes.
    func enablementUpdates() -> AsyncStream<Bool>
}

/// A client that has no activities: the simulator without ActivityKit, the iPad before iPadOS 17, tests.
public struct InertLiveActivityClient: LiveActivityClient {
    /// Creates the client.
    public init() {}

    public var areActivitiesEnabled: Bool { false }
    public func current() async -> [LiveActivityRecord] { [] }
    public func request(attributes: HomeActivityAttributes, state: HomeActivityState, staleDate: Date?) async throws -> LiveActivityRecord {
        throw LiveActivityError.disabled
    }
    public func update(id: String, state: HomeActivityState, staleDate: Date?, relevanceScore: Double, timestamp: Date) async {}
    public func end(id: String, state: HomeActivityState?, dismissal: LiveActivityDismissal) async {}
    public func pushToStartTokens() -> AsyncStream<String> { AsyncStream { $0.finish() } }
    public func activityUpdates() -> AsyncStream<LiveActivityRecord> { AsyncStream { $0.finish() } }
    public func pushTokenUpdates(id: String) -> AsyncStream<String> { AsyncStream { $0.finish() } }
    public func lifecycleUpdates(id: String) -> AsyncStream<LiveActivityLifecycle> { AsyncStream { $0.finish() } }
    public func enablementUpdates() -> AsyncStream<Bool> { AsyncStream { $0.finish() } }
}

/// Why starting an activity failed.
public enum LiveActivityError: Error, Equatable, Sendable {
    /// Live Activities are off for this app, or not available here.
    case disabled
    /// ActivityKit refused (`targetMaximumExceeded`, `globalMaximumExceeded`, a payload over 4 KB…).
    case refused(String)
}
