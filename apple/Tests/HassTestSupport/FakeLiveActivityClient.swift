import FentonActivityModel
import Foundation
import HassCore

/// A scriptable ``LiveActivityClient``: holds activities in memory, records what the app asked of it, and lets a test
/// push tokens, new activities and lifecycle changes the way the system does.
public final class FakeLiveActivityClient: LiveActivityClient, @unchecked Sendable {
    /// What the app asked ActivityKit to do.
    public enum Call: Equatable, Sendable {
        case request(HomeActivityState, staleDate: Date?)
        case update(id: String, HomeActivityState, staleDate: Date?, relevanceScore: Double, timestamp: Date)
        case end(id: String, HomeActivityState?, LiveActivityDismissal)
    }

    private let lock = NSLock()
    private var enabled: Bool
    private var records: [LiveActivityRecord] = []
    private var recordedCalls: [Call] = []
    private var counter = 0
    private var startTokenSinks: [AsyncStream<String>.Continuation] = []
    private var activitySinks: [AsyncStream<LiveActivityRecord>.Continuation] = []
    private var enablementSinks: [AsyncStream<Bool>.Continuation] = []
    private var pushTokenSinks: [String: [AsyncStream<String>.Continuation]] = [:]
    private var lifecycleSinks: [String: [AsyncStream<LiveActivityLifecycle>.Continuation]] = [:]
    /// Make ``request(attributes:state:staleDate:)`` throw this.
    public var requestError: LiveActivityError?
    private var gate: CheckedContinuation<Void, Never>?
    private var holdsNextCurrent = false

    /// Creates a fake.
    /// - Parameter enabled: Whether the person allows activities.
    public init(enabled: Bool = true) {
        self.enabled = enabled
    }

    // MARK: - Test control

    /// Whether the app is listening for tokens, activities and the enablement setting.
    public var isWatching: Bool {
        lock.withLock { !startTokenSinks.isEmpty && !activitySinks.isEmpty && !enablementSinks.isEmpty }
    }

    /// Whether the app is listening to an activity's token and lifecycle.
    public func isWatching(activity id: String) -> Bool {
        lock.withLock { !(pushTokenSinks[id] ?? []).isEmpty && !(lifecycleSinks[id] ?? []).isEmpty }
    }

    /// Whether the app is listening to an activity's lifecycle.
    public func isWatchingLifecycle(of id: String) -> Bool {
        lock.withLock { !(lifecycleSinks[id] ?? []).isEmpty }
    }

    /// Everything the app asked for, in order.
    public var calls: [Call] { lock.withLock { recordedCalls } }

    /// The activities now.
    public var activities: [LiveActivityRecord] { lock.withLock { records } }

    /// The person changes the Settings switch.
    public func setEnabled(_ value: Bool) {
        let sinks = lock.withLock { () -> [AsyncStream<Bool>.Continuation] in
            enabled = value
            return enablementSinks
        }
        sinks.forEach { $0.yield(value) }
    }

    /// The system issues a push-to-start token.
    public func emitStartToken(_ token: String) {
        lock.withLock { startTokenSinks }.forEach { $0.yield(token) }
    }

    /// The system issues an update token for an activity.
    public func emitPushToken(id: String, _ token: String) {
        lock.withLock { pushTokenSinks[id] ?? [] }.forEach { $0.yield(token) }
    }

    /// The activity's lifecycle changes (ended by the system, swiped away…).
    public func emitLifecycle(id: String, _ lifecycle: LiveActivityLifecycle) {
        let sinks = lock.withLock { () -> [AsyncStream<LiveActivityLifecycle>.Continuation] in
            if let index = records.firstIndex(where: { $0.id == id }) { records[index].lifecycle = lifecycle }
            return lifecycleSinks[id] ?? []
        }
        sinks.forEach { $0.yield(lifecycle) }
        if !lifecycle.isLive && lifecycle != .ended { sinks.forEach { $0.finish() } }
    }

    /// A push starts an activity while the app is closed.
    @discardableResult
    public func startFromPush(attributes: HomeActivityAttributes = HomeActivityAttributes(), state: HomeActivityState,
                              relevanceScore: Double = 0) -> LiveActivityRecord {
        let (record, sinks) = lock.withLock { () -> (LiveActivityRecord, [AsyncStream<LiveActivityRecord>.Continuation]) in
            counter += 1
            let record = LiveActivityRecord(id: "act-\(counter)", attributes: attributes, state: state, relevanceScore: relevanceScore)
            records.append(record)
            return (record, activitySinks)
        }
        sinks.forEach { $0.yield(record) }
        return record
    }

    // MARK: - LiveActivityClient

    public var areActivitiesEnabled: Bool { lock.withLock { enabled } }

    public func current() async -> [LiveActivityRecord] {
        let hold = lock.withLock { () -> Bool in
            defer { holdsNextCurrent = false }
            return holdsNextCurrent
        }
        if hold {
            await withCheckedContinuation { continuation in lock.withLock { gate = continuation } }
        }
        return activities
    }

    /// Makes the next ``current()`` wait until ``releaseCurrent()``, so a test can change things mid-pass.
    public func holdNextCurrent() {
        lock.withLock { holdsNextCurrent = true }
    }

    /// Whether a ``current()`` is waiting.
    public var isHoldingCurrent: Bool { lock.withLock { gate != nil } }

    /// Lets the waiting ``current()`` return.
    public func releaseCurrent() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { gate = nil }
            return gate
        }
        continuation?.resume()
    }

    public func request(attributes: HomeActivityAttributes, state: HomeActivityState, staleDate: Date?) async throws -> LiveActivityRecord {
        if let requestError { throw requestError }
        lock.withLock { recordedCalls.append(.request(state, staleDate: staleDate)) }
        return startFromPush(attributes: attributes, state: state)
    }

    public func update(id: String, state: HomeActivityState, staleDate: Date?, relevanceScore: Double, timestamp: Date) async {
        lock.withLock {
            recordedCalls.append(.update(id: id, state, staleDate: staleDate, relevanceScore: relevanceScore, timestamp: timestamp))
            if let index = records.firstIndex(where: { $0.id == id }) { records[index].state = state }
        }
    }

    public func end(id: String, state: HomeActivityState?, dismissal: LiveActivityDismissal) async {
        lock.withLock { recordedCalls.append(.end(id: id, state, dismissal)) }
        emitLifecycle(id: id, dismissal == .immediate ? .dismissed : .ended)
    }

    public func pushToStartTokens() -> AsyncStream<String> {
        AsyncStream { continuation in lock.withLock { startTokenSinks.append(continuation) } }
    }

    public func activityUpdates() -> AsyncStream<LiveActivityRecord> {
        AsyncStream { continuation in lock.withLock { activitySinks.append(continuation) } }
    }

    public func pushTokenUpdates(id: String) -> AsyncStream<String> {
        AsyncStream { continuation in lock.withLock { pushTokenSinks[id, default: []].append(continuation) } }
    }

    public func lifecycleUpdates(id: String) -> AsyncStream<LiveActivityLifecycle> {
        AsyncStream { continuation in lock.withLock { lifecycleSinks[id, default: []].append(continuation) } }
    }

    public func enablementUpdates() -> AsyncStream<Bool> {
        AsyncStream { continuation in lock.withLock { enablementSinks.append(continuation) } }
    }
}

/// A ``LiveActivityWebhookSending`` that records what it was asked to send, and can be told to fail.
public final class RecordingActivityWebhook: LiveActivityWebhookSending, @unchecked Sendable {
    /// What was sent.
    public enum Sent: Equatable, Sendable {
        case token(tag: String, token: String, expiresAt: Date)
        case dismissed(tag: String)
        case event(String, [String: String])
    }

    private let lock = NSLock()
    private var recorded: [Sent] = []
    /// Make every send throw.
    public var fails = false
    /// Make every send wait this long before it records (a webhook that never answers).
    public var delay: Duration?

    /// Creates a recorder.
    public init() {}

    /// What was sent, in order.
    public var sent: [Sent] { lock.withLock { recorded } }

    public func reportToken(tag: String, token: String, expiresAt: Date) async throws {
        try await wait()
        try record(.token(tag: tag, token: token, expiresAt: expiresAt))
    }

    public func reportDismissed(tag: String) async throws {
        try await wait()
        try record(.dismissed(tag: tag))
    }

    public func fireEvent(_ type: String, data: [String: String]) async throws {
        try await wait()
        try record(.event(type, data))
    }

    private func wait() async throws {
        if let delay { try await Task.sleep(for: delay) }
    }

    private func record(_ item: Sent) throws {
        if fails { throw MobileAppWebhookError.network }
        lock.withLock { recorded.append(item) }
    }
}
