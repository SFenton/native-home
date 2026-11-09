import Foundation
import Observation

/// One garage door's open/close command state machine (web `useGarageDoorCommand.ts` and `garageDoorState.ts`).
///
/// A tap sends `cover.open_cover` or `cover.close_cover` chosen from the live state and shows the moving state
/// (`opening` / `closing`) at once. The tile reads "Sending Open…" for at least ``Timing/sendingFeedback``, then
/// waits quietly for the door. Taps are ignored until Home Assistant acknowledges the call and
/// ``Timing/lockout`` has passed, so a double tap can't reverse the door. The request fails, and the tile shows
/// "Error" for ``Timing/failureHold``, when the call errors, isn't acknowledged within ``Timing/serviceTimeout``,
/// the connection drops, or the door doesn't move within ``Timing/confirmTimeout``. Any live state change ends
/// the request: Home Assistant is the source of truth.
@MainActor
@Observable
public final class GarageDoorController {
    // MARK: - Types

    /// Feedback phase (web `GarageDoorCommandPhase`).
    public enum Phase: Equatable, Sendable {
        /// No request, or the last one finished.
        case idle
        /// The call was just sent: the tile says "Sending Open…" / "Sending Close…".
        case sending
        /// Acknowledged; waiting for the door to report movement.
        case pending
        /// The request failed: the tile says "Error".
        case error
    }

    /// The command a tap sends from a given state.
    public struct Command: Equatable, Sendable {
        /// Opens (true) or closes (false).
        public var opens: Bool
        /// `open_cover` or `close_cover`.
        public var service: String
        /// The moving state shown until Home Assistant reports one: `opening` or `closing`.
        public var transitionState: String
    }

    /// Timer lengths (`constants/garageDoors.ts`).
    public struct Timing: Sendable, Equatable {
        public var sendingFeedback: Duration = .seconds(1)
        public var lockout: Duration = .seconds(2)
        public var serviceTimeout: Duration = .seconds(10)
        public var confirmTimeout: Duration = .seconds(45)
        public var failureHold: Duration = .seconds(8)

        /// The web's values.
        public static let standard = Timing()
    }

    private struct Request {
        var id: Int
        var command: Command
        var acknowledged = false
        var feedbackElapsed = false
        var lockoutElapsed = false
    }

    // MARK: - Public state

    /// The cover entity.
    public let entityId: String
    /// The last live state from Home Assistant (`unavailable` when missing).
    public private(set) var liveState: String
    /// Current feedback phase.
    public private(set) var phase: Phase = .idle
    /// Whether the active or failed request opens the door.
    public private(set) var opens: Bool?
    /// Taps are ignored while true.
    public private(set) var isInteractionLocked = false
    /// The optimistic moving state, shown until a live change or a failure.
    public private(set) var optimisticState: String?

    /// The state the tile shows.
    public var displayState: String { optimisticState ?? liveState }

    /// Whether the live state has a command (closed, closing, open, opening).
    public var isAvailable: Bool { Self.command(for: liveState) != nil }

    // MARK: - Private

    @ObservationIgnored private let caller: any HassServiceCalling
    @ObservationIgnored private let scheduler: any RevertScheduler
    @ObservationIgnored private let timing: Timing
    @ObservationIgnored private var canSend = true
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var active: Request?
    @ObservationIgnored private var commandTimers: [any ScheduledWork] = []
    @ObservationIgnored private var failureTimer: (any ScheduledWork)?
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    // MARK: - Init

    /// Creates a controller.
    /// - Parameters:
    ///   - entityId: The cover entity.
    ///   - liveState: Its current state, or `nil` when missing.
    ///   - caller: Sends the service call.
    ///   - scheduler: Runs the feedback, lockout, timeout and failure timers.
    ///   - timing: Timer lengths.
    public init(entityId: String, liveState: String?, caller: any HassServiceCalling, scheduler: any RevertScheduler, timing: Timing = .standard) {
        self.entityId = entityId
        self.liveState = liveState ?? "unavailable"
        self.caller = caller
        self.scheduler = scheduler
        self.timing = timing
    }

    // MARK: - Commands

    /// The command for a live state (`garageDoorCommandForState`): closed or closing opens, open or opening closes.
    public nonisolated static func command(for state: String?) -> Command? {
        switch state {
        case "closed", "closing": Command(opens: true, service: "open_cover", transitionState: "opening")
        case "open", "opening": Command(opens: false, service: "close_cover", transitionState: "closing")
        default: nil
        }
    }

    /// Sends the command for the live state. Ignored while locked or when the state has no command.
    public func send() {
        guard !isInteractionLocked, let command = Self.command(for: liveState) else { return }
        cancelCommandTimers()
        cancelFailureTimer()
        sequence += 1
        let id = sequence
        active = Request(id: id, command: command)
        isInteractionLocked = true
        optimisticState = command.transitionState
        opens = command.opens
        phase = .sending

        schedule(after: timing.sendingFeedback) { [weak self] in
            self?.update(id) { $0.feedbackElapsed = true }
        }
        schedule(after: timing.lockout) { [weak self] in
            self?.update(id) { $0.lockoutElapsed = true }
        }
        schedule(after: timing.confirmTimeout) { [weak self] in self?.fail(id) }

        guard canSend else {
            fail(id)
            return
        }
        schedule(after: timing.serviceTimeout) { [weak self] in
            guard let self, self.active?.id == id, self.active?.acknowledged == false else { return }
            self.fail(id)
        }
        let call = ServiceCall("cover", command.service, target: entityId)
        inFlight = Task { [weak self, caller] in
            do {
                try await caller.call(call)
                self?.update(id) { $0.acknowledged = true }
            } catch {
                self?.fail(id)
            }
        }
    }

    // MARK: - Live input

    /// Reports the live state. Any change ends the request and clears its feedback.
    public func liveDidChange(_ state: String?) {
        let state = state ?? "unavailable"
        guard state != liveState else { return }
        liveState = state
        finishActive()
        cancelFailureTimer()
        optimisticState = nil
        opens = nil
        phase = .idle
    }

    /// Reports whether the connection can send. Losing it fails the active request.
    public func connectionDidChange(canSend: Bool) {
        self.canSend = canSend
        if !canSend, let id = active?.id { fail(id) }
    }

    /// Waits for the in-flight service call (tests).
    public func waitForCall() async {
        await inFlight?.value
    }

    // MARK: - Private

    private func schedule(after delay: Duration, _ work: @escaping @MainActor () -> Void) {
        commandTimers.append(scheduler.schedule(after: delay, work))
    }

    /// Applies `change` to the active request `id`, then advances the phase and the lock.
    private func update(_ id: Int, _ change: (inout Request) -> Void) {
        guard var request = active, request.id == id else { return }
        change(&request)
        active = request
        if request.acknowledged, request.feedbackElapsed, phase == .sending { phase = .pending }
        if request.acknowledged, request.lockoutElapsed, isInteractionLocked { isInteractionLocked = false }
    }

    private func fail(_ id: Int) {
        guard let request = active, request.id == id else { return }
        finishActive()
        cancelFailureTimer()
        optimisticState = nil
        opens = request.command.opens
        phase = .error
        failureTimer = scheduler.schedule(after: timing.failureHold) { [weak self] in
            guard let self, self.phase == .error, self.active == nil else { return }
            self.failureTimer = nil
            self.phase = .idle
            self.opens = nil
        }
    }

    private func finishActive() {
        active = nil
        isInteractionLocked = false
        cancelCommandTimers()
    }

    private func cancelCommandTimers() {
        commandTimers.forEach { $0.cancel() }
        commandTimers.removeAll()
    }

    private func cancelFailureTimer() {
        failureTimer?.cancel()
        failureTimer = nil
    }
}
