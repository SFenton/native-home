import Foundation
import HassTelemetry
import Observation

public extension OptimisticIntent {
    /// An intent with the shared default revert time (``OptimisticActions/defaultRevert``).
    /// - Parameters:
    ///   - key: The overlay key, usually an entity id.
    ///   - value: The value to show until Home Assistant confirms it.
    init(_ key: String, value: String) {
        self.init(key, value, revertAfter: OptimisticActions.defaultRevert)
    }
}

/// Clears another key's pending value when it currently shows one of `values` (web `OptimisticResetIntent`), e.g.
/// pressing Stop clears a pending "playing".
public struct OptimisticReset: Equatable, Sendable {
    /// The overlay key.
    public var key: String
    /// Pending values that the command makes stale.
    public var values: [String]

    /// Creates a reset.
    public init(_ key: String, values: [String]) {
        self.key = key
        self.values = values
    }
}

/// The shared optimistic-command path (pattern: `.agents/patterns/optimistic-actions.md`).
///
/// Wraps an ``OptimisticOverlay`` with the three things every controller otherwise wires by hand, matching the web's
/// `runOptimisticServiceCommand` and `OptimisticActionStateBoundary`:
/// 1. **Commit, then call.** ``perform(_:showing:resetting:)`` shows the intents at once and sends the call.
/// 2. **Roll back on failure.** A rejected call drops exactly the values it committed (by generation), so a newer
///    tap is never undone by an older failure, and the control returns to the live value and shows the failed
///    face for 4 s (``isFailed(_:)``; the 2026-10-24 reversal of "no error state").
/// 3. **Follow live state.** It observes the live value of every tracked key and confirms (or, for
///    ``OptimisticOverlay/ClearRule/liveChange`` keys, clears) the pending value as Home Assistant reports.
///
/// Views read ``shown(_:)``; it is observable, so a view redraws when the pending or live value changes.
@MainActor
@Observable
public final class OptimisticActions {
    /// How long an optimistic value waits for Home Assistant (web `DEFAULT_OPTIMISTIC_REVERT_MS`).
    public nonisolated static let defaultRevert: Duration = .seconds(2)

    /// The pending values.
    public let overlay: OptimisticOverlay

    @ObservationIgnored private let caller: any HassServiceCalling
    @ObservationIgnored private let live: @MainActor (String) -> String?
    @ObservationIgnored private var inFlight: [Task<Void, Never>] = []
    @ObservationIgnored private var confirmations: [String: Telemetry.Interval] = [:]

    /// Creates the path over any live source.
    /// - Parameters:
    ///   - rules: Each tracked key and when its pending value clears.
    ///   - caller: Where calls go: the connection in the app, a recorder in tests and the gallery.
    ///   - scheduler: Runs revert timers (tests pass a manual one).
    ///   - live: The live value for a key; read inside observation tracking, so it must read observable state.
    public init(
        rules: [String: OptimisticOverlay.ClearRule],
        caller: any HassServiceCalling,
        scheduler: any RevertScheduler = TaskRevertScheduler(),
        live: @escaping @MainActor (String) -> String?
    ) {
        overlay = OptimisticOverlay(rules: rules, scheduler: scheduler)
        self.caller = caller
        self.live = live
        liveDidChange()
        observeLive()
    }

    /// Creates the path over entity states: each key is an entity id and its live value is the entity's state.
    public convenience init(
        store: EntityStore,
        rules: [String: OptimisticOverlay.ClearRule],
        caller: any HassServiceCalling,
        scheduler: any RevertScheduler = TaskRevertScheduler()
    ) {
        self.init(rules: rules, caller: caller, scheduler: scheduler) { [store] in store.entity($0).state?.state }
    }

    // MARK: - Reading

    /// The value to show: the pending value, else the live one.
    public func shown(_ key: String) -> String? { overlay.displayed(key, live: live(key)) }

    /// Whether a pending value differs from the live one.
    public func isPending(_ key: String) -> Bool { overlay.hasOverride(key, live: live(key)) }

    /// Whether the last command for `key` failed and the failed face is still showing (4 s; pattern: optimistic-actions).
    public func isFailed(_ key: String) -> Bool { overlay.isFailed(key) }

    // MARK: - Acting

    /// Shows `intents` at once, clears stale `resets`, sends `call`, and rolls the intents back if it fails.
    /// - Returns: The call's task (tests await it; views ignore it).
    @discardableResult
    public func perform(_ call: ServiceCall, showing intents: [OptimisticIntent], resetting resets: [OptimisticReset] = [],
                        failing failureKey: String? = nil) -> Task<Void, Never> {
        perform(intents: intents, resets: resets, failureKey: failureKey) { caller in try await caller.call(call) }
    }

    /// Like ``perform(_:showing:resetting:)`` for a raw `domain.service` call.
    @discardableResult
    public func perform(_ domain: String, _ service: String, data: [String: any Sendable], showing intents: [OptimisticIntent],
                        resetting resets: [OptimisticReset] = [], failing failureKey: String? = nil) -> Task<Void, Never> {
        perform(intents: intents, resets: resets, failureKey: failureKey) { caller in try await caller.callService(domain, service, data: data) }
    }

    /// Waits for every call started so far (tests).
    public func waitForCalls() async {
        let tasks = inFlight
        inFlight.removeAll()
        for task in tasks { await task.value }
    }

    private func perform(intents: [OptimisticIntent], resets: [OptimisticReset], failureKey: String?,
                         send: @escaping @MainActor (any HassServiceCalling) async throws -> Void) -> Task<Void, Never> {
        for reset in resets where reset.values.contains(overlay.pending[reset.key] ?? "") && overlay.pending[reset.key] != nil {
            overlay.reset(reset.key)
        }
        var committed: [(key: String, generation: Int)] = []
        for intent in intents {
            guard let generation = overlay.commit(intent.entityId, value: intent.value, live: live(intent.entityId), revertAfter: intent.revertAfter,
                                                  failsOnTimeout: intent.failsOnTimeout)
            else { continue }
            committed.append((intent.entityId, generation))
            if overlay.pending[intent.entityId] != nil {
                confirmations[intent.entityId] = Telemetry.begin(Telemetry.Name.optimisticConfirm, intent.entityId)
            }
        }
        let caller = caller
        let task = Task { @MainActor [weak self] in
            let interval = Telemetry.begin(Telemetry.Name.serviceCall)
            do {
                try await send(caller)
                Telemetry.end(interval, detail: "ok")
            } catch {
                Telemetry.end(interval, detail: "failed")
                Telemetry.count("optimistic.rollbacks", by: committed.count)
                for (key, generation) in committed { self?.overlay.fail(key, generation: generation) }
                if let failureKey, !committed.contains(where: { $0.key == failureKey }) { self?.overlay.markFailed(failureKey) }
            }
        }
        // Only tests await these; keep a bounded tail so a long session doesn't grow the list forever.
        if inFlight.count >= 64 { inFlight.removeFirst(inFlight.count - 63) }
        inFlight.append(task)
        return task
    }

    // MARK: - Live updates

    private func liveDidChange() {
        for key in overlay.trackedKeys {
            let wasPending = overlay.pending[key] != nil
            overlay.liveChanged(key, to: live(key))
            if wasPending, overlay.pending[key] == nil, let interval = confirmations.removeValue(forKey: key) {
                Telemetry.end(interval, detail: key)
            }
        }
    }

    private func observeLive() {
        withObservationTracking {
            for key in overlay.trackedKeys { _ = live(key) }
        } onChange: { [weak self] in
            // onChange fires before the new value lands; read it on the next main-actor turn.
            Task { @MainActor [weak self] in
                self?.liveDidChange()
                self?.observeLive()
            }
        }
    }
}
