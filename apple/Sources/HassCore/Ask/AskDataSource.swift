import Foundation

// MARK: - Rows

/// One logbook row for one entity (`logbook/get_events`).
public struct AskLogbookRow: Sendable, Equatable {
    /// When the row was written.
    public var when: Date
    /// The state the entity changed to, when the row is a state change.
    public var state: String?
    /// The event kind behind the row: `automation_triggered`, `call_service`, `script_started`, `state_changed`, nil for none.
    public var contextEventType: String?
    /// The name of the automation, script or entity that caused it.
    public var contextName: String?
    /// The logbook's message ("triggered by time pattern").
    public var contextMessage: String?
    /// The entity that caused it.
    public var contextEntityId: String?
    /// The domain of the cause.
    public var contextDomain: String?
    /// The service called, for a service call.
    public var contextService: String?
    /// The user that called it.
    public var contextUserId: String?
    /// The state of the causing entity, for a derived change.
    public var contextState: String?

    /// Creates a row.
    public init(
        when: Date, state: String? = nil, contextEventType: String? = nil, contextName: String? = nil, contextMessage: String? = nil,
        contextEntityId: String? = nil, contextDomain: String? = nil, contextService: String? = nil, contextUserId: String? = nil,
        contextState: String? = nil
    ) {
        self.when = when
        self.state = state
        self.contextEventType = contextEventType
        self.contextName = contextName
        self.contextMessage = contextMessage
        self.contextEntityId = contextEntityId
        self.contextDomain = contextDomain
        self.contextService = contextService
        self.contextUserId = contextUserId
        self.contextState = contextState
    }

    /// Whether the row names no cause at all (the device reported it itself).
    public var hasNoContext: Bool {
        contextEventType == nil && contextName == nil && contextEntityId == nil && contextService == nil && contextUserId == nil && contextDomain == nil
    }
}

/// One point of an entity's history (`history/history_during_period`, minimal response).
public struct AskHistoryPoint: Sendable, Equatable {
    /// When the state began.
    public var at: Date
    /// The state.
    public var state: String

    /// Creates a point.
    public init(at: Date, state: String) {
        self.at = at
        self.state = state
    }
}

// MARK: - Source

/// The two reads the answerer may make at answer time, each with a window and a deadline.
///
/// The app implements it over `HassConnection` (`logbook/get_events` and `history/history_during_period`, both open to any
/// signed-in user); the eval harness implements it over the snapshot files. A thrown error means "no data": the answerer
/// falls back to what it already holds and says so.
public protocol AskDataSource: Sendable {
    /// Logbook rows for one entity inside `[from, to]`, oldest first, capped by the source.
    func logbook(entityId: String, from: Date, to: Date) async throws -> [AskLogbookRow]
    /// The entity's state periods inside `[from, to]`, oldest first. The first point may begin before `from`.
    func history(entityId: String, from: Date, to: Date) async throws -> [AskHistoryPoint]
}

/// A source that holds no data: every read throws, so answers come from the states alone.
public struct AskNoDataSource: AskDataSource {
    /// The error every read throws.
    public struct Unavailable: Error, Equatable {}

    /// Creates the empty source.
    public init() {}
    public func logbook(entityId: String, from: Date, to: Date) async throws -> [AskLogbookRow] { throw Unavailable() }
    public func history(entityId: String, from: Date, to: Date) async throws -> [AskHistoryPoint] { throw Unavailable() }
}

// MARK: - Deadline

/// Runs a read against a deadline.
public enum AskDeadline {
    /// The error thrown when the deadline passes first.
    public struct TimedOut: Error, Equatable {}

    /// Runs `operation`; throws ``TimedOut`` when it has not finished after `seconds`.
    public static func run<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                throw TimedOut()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw TimedOut() }
            return first
        }
    }
}
