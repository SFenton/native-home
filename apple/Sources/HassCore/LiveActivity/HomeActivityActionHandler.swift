import FentonActivityModel
import Foundation

/// Runs a card's button presses in the app process (`.agents/platforms/apple/live-activities-per-job.md` §7, step 1).
///
/// A press:
/// 1. finds the activity by tag and checks the card still offers the control;
/// 2. writes the **pending** state, `{control, label, since_ts}` with a stale date 20 s out and a whole-second timestamp
///    that is never in the future, so the card swaps its buttons for "Stopping…" and Home Assistant's confirmation is newer;
/// 3. fires `fenton_live_activity_action {tag, job, control}` over the registration webhook, with a 10 s timeout;
/// 4. on a failure writes the previous content back with no pending state and a notice, "Couldn't reach Home".
///
/// Home Assistant's engine checks the control and the caller, calls the service from its own control map, and pushes the
/// confirmed state (or the end), which replaces the pending one. If nothing arrives the stale date passes and the views
/// give the buttons back with "Not confirmed" (`ActivityCard.isUnconfirmed`).
public struct HomeActivityActionHandler: LiveActivityIntentRuntime.Handler {
    private let client: any LiveActivityClient
    private let webhook: @Sendable () -> (any LiveActivityWebhookSending)?
    private let now: @Sendable () -> Date
    private let timeout: Duration

    /// Creates a handler.
    /// - Parameters:
    ///   - client: ActivityKit.
    ///   - webhook: The signed-in registration's webhook sender, read when the press happens; nil while signed out.
    ///   - now: The clock.
    ///   - timeout: How long the webhook may take (10 s).
    public init(client: any LiveActivityClient, webhook: @escaping @Sendable () -> (any LiveActivityWebhookSending)?,
                now: @escaping @Sendable () -> Date = { Date() }, timeout: Duration = .seconds(10)) {
        self.client = client
        self.webhook = webhook
        self.now = now
        self.timeout = timeout
    }

    /// Shown in place of the figure after a control could not reach Home Assistant.
    public static let failureNotice = "Couldn't reach Home"

    public func handle(_ action: LiveActivityAction) async -> Bool {
        let records = await client.current()
        guard let record = records.first(where: { $0.tag == action.tag && $0.lifecycle.isLive }) else { return false }
        switch action {
        case let .control(_, control):
            return await perform(control, in: record)
        }
    }

    private func perform(_ control: String, in record: LiveActivityRecord) async -> Bool {
        guard record.state.offers(control: control) else { return false }
        let stamp = ActivityClock.wholeSecond(now())
        await client.update(id: record.id, state: record.state.awaiting(control: control, now: stamp),
                            staleDate: ActivityClock.pendingStaleDate(from: stamp), relevanceScore: record.relevanceScore, timestamp: stamp)
        do {
            guard let webhook = webhook() else { throw MobileAppWebhookError.notRegistered }
            let data = ["tag": record.tag, "job": record.attributes.jobID, "control": control]
            try await Self.within(timeout) { try await webhook.fireEvent(LiveActivityEventType.action, data: data) }
            return true
        } catch {
            // Whole seconds, never in the future and never before the pending write. A failure in the same second as the
            // press can tie with it and be dropped; the pending state's stale date then gives the buttons back anyway.
            let restored = max(ActivityClock.wholeSecond(now()), stamp)
            await client.update(id: record.id, state: record.state.failing(notice: Self.failureNotice), staleDate: nil,
                                relevanceScore: record.relevanceScore, timestamp: restored)
            return false
        }
    }

    /// Runs `operation`, throwing ``HomeActivityActionHandler/TimedOut`` when it takes longer than `limit`.
    static func within<T: Sendable>(_ limit: Duration, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: limit)
                throw TimedOut()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw TimedOut() }
            return first
        }
    }

    /// The webhook did not answer in time.
    struct TimedOut: Error {}
}
