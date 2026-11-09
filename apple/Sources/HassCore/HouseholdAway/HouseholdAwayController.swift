import Foundation
import Observation

// `HassServiceResponding` and `HassConnection.callServiceWithResponse` live in `Bedroom/ServiceResponses.swift`;
// the connection returns the whole result, so ``HouseholdAwayController/outcome(from:)`` unwraps `response`.

/// Sends Household Away commands and reads the status sensor (web `useHouseholdAwayController.ts`).
///
/// Exactly one plan exists, so there is no per-item queue: one command at a time, checked against the
/// script's response, with a timeout that reports an unknown outcome instead of guessing.
@MainActor
@Observable
public final class HouseholdAwayController {
    // MARK: - Types

    /// How a command ended.
    public enum Outcome: Equatable, Sendable {
        /// The script accepted it (or found nothing to change).
        case accepted(revision: Int?)
        /// The script, the connection or the app refused it.
        case rejected(errorCode: String)
        /// No answer in time; the plan may or may not have changed.
        case unknown
    }

    /// Error codes the app raises itself.
    public enum ErrorCode {
        public static let transport = "transport"
        public static let unavailable = "unavailable"
        public static let unknownOutcome = "unknown_outcome"
    }

    // MARK: - State

    /// Live state.
    public let store: EntityStore
    /// A command is in flight.
    public private(set) var pending = false
    /// The last command's error, until cleared or the next command starts.
    public private(set) var errorCode: String?
    /// The script has refused commands for longer than ``setupGrace``: show "setup required" rather than
    /// the brief gaps while it republishes its journal and status.
    public private(set) var commandOutageConfirmed = false

    @ObservationIgnored private let responder: any HassServiceResponding
    @ObservationIgnored private let timeout: Duration
    @ObservationIgnored private let makeRequestId: @Sendable () -> String
    @ObservationIgnored private let retryDelay: Duration
    @ObservationIgnored private let setupGrace: Duration
    @ObservationIgnored private var revisionFloor = 0
    @ObservationIgnored private var outageTimer: Task<Void, Never>?

    /// How long a command may take before its outcome is unknown (web `COMMAND_TIMEOUT_MS`).
    public nonisolated static let commandTimeout: Duration = .seconds(10)
    /// How long `command_available` may stay false before the page calls it a setup problem. The status
    /// sensor's attributes compare the status with the journal when the status arrives, so each transition
    /// (schedule, activate, end) can publish one status that doesn't match the journal yet.
    public nonisolated static let defaultSetupGrace: Duration = .seconds(5)
    /// How long a retryable refusal waits for the status sensor before the command is sent again.
    public nonisolated static let defaultRetryDelay: Duration = .milliseconds(1500)
    /// Refusals that mean "the plan is moving; ask again" (`solo_trip.yaml` `household_away_command`).
    static let retryableCodes: Set<String> = ["expected_revision_mismatch", "request_in_progress", "invalid_journal_contract"]
    /// Retries after a retryable refusal. Each attempt has its own ``commandTimeout``, but refusals come back
    /// at once, so in practice the retries add at most ``defaultRetryDelay`` each.
    static let maxRetries = 3

    // MARK: - Init

    /// Creates a controller.
    /// - Parameters:
    ///   - store: Live state.
    ///   - responder: Where commands go: the connection in the app, a script in tests.
    ///   - timeout: Command timeout.
    ///   - retryDelay: Longest wait for the sensor before a retryable refusal is retried.
    ///   - setupGrace: How long commands may be unavailable before ``commandOutageConfirmed``.
    ///   - makeRequestId: Request ids (tests pass a fixed one).
    public init(
        store: EntityStore,
        responder: any HassServiceResponding,
        timeout: Duration = HouseholdAwayController.commandTimeout,
        retryDelay: Duration = HouseholdAwayController.defaultRetryDelay,
        setupGrace: Duration = HouseholdAwayController.defaultSetupGrace,
        makeRequestId: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.store = store
        self.responder = responder
        self.timeout = timeout
        self.retryDelay = retryDelay
        self.setupGrace = setupGrace
        self.makeRequestId = makeRequestId
        // A sensor that is already unavailable at launch is a setup problem, not a transition.
        commandOutageConfirmed = !snapshot.canCommand
        observeAvailability()
    }

    /// The parsed status sensor; observing it observes only that entity.
    public var snapshot: HouseholdAway.Snapshot {
        HouseholdAway.Snapshot(entity: store.entity(HouseholdAway.statusEntityId).state)
    }

    /// Commands are unavailable and have been for longer than the grace period.
    public var setupUnavailable: Bool { !snapshot.canCommand && commandOutageConfirmed }

    // MARK: - Commands

    /// Clears the shown error.
    public func clearError() { errorCode = nil }

    /// Sends one command. A retryable refusal (the plan moved under it) waits for the status sensor and
    /// is sent again with the fresh revision, so a tap during a transition still lands.
    @discardableResult
    public func send(_ command: HouseholdAway.Command) async -> Outcome {
        guard !pending else { return .rejected(errorCode: ErrorCode.transport) }
        guard snapshot.canCommand else {
            errorCode = ErrorCode.unavailable
            return .rejected(errorCode: ErrorCode.unavailable)
        }
        pending = true
        errorCode = nil
        defer { pending = false }
        var attempt = 0
        while true {
            let current = snapshot
            revisionFloor = max(revisionFloor, current.revision)
            let data = HouseholdAway.serviceData(for: command, expectedRevision: revisionFloor, requestId: makeRequestId())
            guard let result = await callWithTimeout(data.mapValues(\.foundationValue)) else {
                errorCode = ErrorCode.unknownOutcome
                return .unknown
            }
            let outcome = Self.outcome(from: result)
            switch outcome {
            case let .accepted(revision):
                if let revision { revisionFloor = max(revisionFloor, revision) }
            case let .rejected(code) where Self.retryableCodes.contains(code) && attempt < Self.maxRetries && !Task.isCancelled:
                attempt += 1
                await waitForStatusChange(from: current)
                // The script's journal is the authority: take the sensor's revision as is, even if lower.
                revisionFloor = snapshot.revision
                continue
            case let .rejected(code):
                errorCode = code
            case .unknown:
                break
            }
            return outcome
        }
    }

    /// Waits until the status sensor publishes something new, or ``retryDelay`` passes.
    private func waitForStatusChange(from previous: HouseholdAway.Snapshot) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: retryDelay)
        while clock.now < deadline, snapshot == previous {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
    }

    /// Reads the script's response (web `responseFrom` and the outcome branch of `send`).
    static func outcome(from result: Result<JSONValue, any Error>) -> Outcome {
        guard case let .success(value) = result else { return .rejected(errorCode: ErrorCode.transport) }
        let response = value["response"].flatMap { $0.isObject ? $0 : nil } ?? value
        guard let status = response["status"]?.string ?? response["outcome"]?.string else {
            return .rejected(errorCode: ErrorCode.transport)
        }
        let revision = response["revision"]?.number.flatMap { $0 == $0.rounded() ? Int($0) : nil }
        if status == "accepted" || status == "no_change" {
            return .accepted(revision: revision)
        }
        // The script admitted the request but timed out waiting for its own echo (`status_echo_timeout`,
        // `journal_echo_timeout`): the change is under way, so the page waits for the sensor instead of
        // reporting a failure. Native departure from the web, which shows "could not apply".
        if status == "indeterminate" {
            return .accepted(revision: nil)
        }
        return .rejected(errorCode: response["error_code"]?.string ?? response["error"]?.string ?? status)
    }

    /// Calls the script, or returns `nil` once ``timeout`` passes first. The call itself can't be cancelled,
    /// so a late answer is dropped.
    private func callWithTimeout(_ data: [String: any Sendable]) async -> Result<JSONValue, any Error>? {
        let gate = ResumeGate()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Result<JSONValue, any Error>?, Never>) in
            Task { @MainActor [self] in
                let result: Result<JSONValue, any Error>
                do {
                    result = .success(try await responder.callServiceWithResponse(HouseholdAway.commandDomain, HouseholdAway.commandService, data: data))
                } catch {
                    result = .failure(error)
                }
                if gate.claim() { continuation.resume(returning: result) }
            }
            Task { @MainActor [timeout] in
                try? await Task.sleep(for: timeout)
                if gate.claim() { continuation.resume(returning: nil) }
            }
        }
    }

    // MARK: - Availability

    /// Confirms an outage only after ``setupGrace`` of continuous unavailability.
    private func availabilityChanged() {
        if snapshot.canCommand {
            outageTimer?.cancel()
            outageTimer = nil
            if commandOutageConfirmed { commandOutageConfirmed = false }
        } else if !commandOutageConfirmed, outageTimer == nil {
            let grace = setupGrace
            outageTimer = Task { @MainActor [weak self] in
                try? await Task.sleep(for: grace)
                guard !Task.isCancelled, let self else { return }
                outageTimer = nil
                if !snapshot.canCommand { commandOutageConfirmed = true }
            }
        }
    }

    private func observeAvailability() {
        withObservationTracking {
            _ = store.entity(HouseholdAway.statusEntityId).state
        } onChange: { [weak self] in
            // onChange fires before the new value lands; read it on the next main-actor turn.
            Task { @MainActor [weak self] in
                self?.availabilityChanged()
                self?.observeAvailability()
            }
        }
    }

    // MARK: - Convenience

    @discardableResult
    public func cancel() async -> Outcome { await send(.cancel) }
    @discardableResult
    public func endNow() async -> Outcome { await send(.endNow) }
    @discardableResult
    public func resolveRestore(_ action: HouseholdAway.ResolveAction) async -> Outcome { await send(.resolveRestore(action)) }
    @discardableResult
    public func scheduleSoloTrip(traveler: HouseholdResident, draft: SoloTripDraft) async -> Outcome {
        await send(.scheduleSoloTrip(traveler: traveler, start: draft.start, end: draft.end))
    }
    @discardableResult
    public func updateEnd(_ end: WallClock) async -> Outcome { await send(.updateEnd(end)) }
}

/// Lets exactly one of two racing tasks resume a continuation.
@MainActor
private final class ResumeGate {
    private var claimed = false
    func claim() -> Bool {
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

extension JSONValue {
    /// Whether this is an object.
    var isObject: Bool { if case .object = self { true } else { false } }
}
