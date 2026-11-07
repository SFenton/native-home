import Foundation
import Observation

// MARK: - Scheduling

/// A scheduled piece of work that can be cancelled.
@MainActor
public protocol ScheduledWork: AnyObject {
    /// Cancels the work if it has not run.
    func cancel()
}

/// Runs work after a delay. Injected so tests drive revert and hold timers without waiting.
@MainActor
public protocol RevertScheduler: AnyObject {
    /// Runs `work` on the main actor after `delay` unless cancelled.
    func schedule(after delay: Duration, _ work: @escaping @MainActor () -> Void) -> any ScheduledWork
}

/// The production scheduler: a main-actor `Task` that sleeps.
@MainActor
public final class TaskRevertScheduler: RevertScheduler {
    private final class Work: ScheduledWork {
        var task: Task<Void, Never>?
        func cancel() { task?.cancel() }
    }

    /// Creates the scheduler.
    public init() {}

    public func schedule(after delay: Duration, _ work: @escaping @MainActor () -> Void) -> any ScheduledWork {
        let item = Work()
        item.task = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            work()
        }
        return item
    }
}

// MARK: - Intents

/// An optimistic value shown for an entity right after a command, until Home Assistant confirms it or
/// ``revertAfter`` passes (web `OptimisticStateIntent`, `src/constants/actionIntents.ts`).
public struct OptimisticIntent: Hashable, Sendable, Codable {
    public var entityId: String
    public var value: String
    public var revertAfter: Duration
    /// Shows the failed face when ``revertAfter`` passes without Home Assistant confirming the value, not only when the call
    /// throws (a tracked script action that never reached its state, ``ScriptPowerActions``).
    public var failsOnTimeout: Bool

    /// Creates an intent.
    public init(_ entityId: String, _ value: String, revertAfter: Duration, failsOnTimeout: Bool = false) {
        self.entityId = entityId
        self.value = value
        self.revertAfter = revertAfter
        self.failsOnTimeout = failsOnTimeout
    }
}

// MARK: - Overlay

/// Optimistic values layered over live Home Assistant state (web `OptimisticActionStateBoundary` and
/// `useOptimisticState`, `src/hooks/useOptimisticState.ts`).
///
/// A committed value shows at once. It clears when Home Assistant confirms it (or, for
/// ``ClearRule/liveChange`` keys, on any live change), when the command fails, or when its revert time passes,
/// so a control never keeps claiming a state the house did not reach. Only keys the overlay was created with
/// take optimistic values; intents for other entities are ignored, as on the web.
@MainActor
@Observable
public final class OptimisticOverlay {
    /// When a pending value gives way to the live one.
    public enum ClearRule: Sendable {
        /// When the live value becomes the pending value.
        case confirmation
        /// On any live change.
        case liveChange
    }

    /// How long the failed face shows after a rejected or unconfirmed command (owner, 2026-10-24).
    public nonisolated static let failureDuration: Duration = .seconds(4)

    /// Pending values by key. Observed by views.
    public private(set) var pending: [String: String] = [:]

    /// Keys whose last command failed and whose failed face is still showing. Observed by views.
    public private(set) var failures: Set<String> = []

    @ObservationIgnored private let rules: [String: ClearRule]
    @ObservationIgnored private let scheduler: any RevertScheduler
    @ObservationIgnored private var generations: [String: Int] = [:]
    @ObservationIgnored private var timers: [String: any ScheduledWork] = [:]
    @ObservationIgnored private var lastLive: [String: String?] = [:]
    @ObservationIgnored private var ruleOverrides: [String: ClearRule] = [:]
    @ObservationIgnored private var failureTimers: [String: any ScheduledWork] = [:]
    @ObservationIgnored private var failureGenerations: [String: Int] = [:]
    @ObservationIgnored private var failsOnTimeout: Set<String> = []

    /// Creates an overlay for the given keys.
    /// - Parameters:
    ///   - rules: Each tracked key and when its pending value clears.
    ///   - scheduler: Runs revert timers.
    public init(rules: [String: ClearRule], scheduler: any RevertScheduler) {
        self.rules = rules
        self.scheduler = scheduler
    }

    /// Whether `key` takes optimistic values.
    public func isTracked(_ key: String) -> Bool { rules[key] != nil }

    /// Every tracked key.
    public var trackedKeys: [String] { Array(rules.keys) }

    /// The value to show: the pending value, else `live`.
    public func displayed(_ key: String, live: String?) -> String? { pending[key] ?? live }

    /// Whether a pending value differs from `live`.
    public func hasOverride(_ key: String, live: String?) -> Bool {
        guard let value = pending[key] else { return false }
        return value != live
    }

    /// Shows `value` for `key` until confirmed or `revertAfter` passes. Committing the live value clears any
    /// pending one instead.
    /// - Parameter rule: Clears this commit by `rule` instead of the key's own (a robot in an error state flaps
    ///   through other states while it tries the command; only the confirmation or the revert time ends the value).
    /// - Parameter failsOnTimeout: Shows the failed face when the revert time passes without a confirmation (a vacuum
    ///   that never took the command), not only when the call throws.
    /// - Returns: The commit's generation (pass it to ``reset(_:generation:)`` to undo only this commit), or
    ///   `nil` when the key is not tracked.
    @discardableResult
    public func commit(_ key: String, value: String, live: String?, revertAfter: Duration, clearing rule: ClearRule? = nil,
                       failsOnTimeout: Bool = false) -> Int? {
        guard isTracked(key) else { return nil }
        clearFailure(key)
        if failsOnTimeout { self.failsOnTimeout.insert(key) } else { self.failsOnTimeout.remove(key) }
        ruleOverrides[key] = rule
        if lastLive[key] == nil { lastLive[key] = .some(live) }
        let generation = (generations[key] ?? 0) + 1
        generations[key] = generation
        timers[key]?.cancel()
        timers[key] = nil
        if value == live {
            clear(key)
            return generation
        }
        pending[key] = value
        timers[key] = scheduler.schedule(after: revertAfter) { [weak self] in
            guard let self, self.generations[key] == generation else { return }
            self.timers[key] = nil
            let timedOut = self.pending[key] != nil
            self.clear(key)
            if timedOut, self.failsOnTimeout.contains(key) { self.markFailed(key) }
        }
        return generation
    }

    /// Whether `key`'s last command failed and the failed face is still showing.
    public func isFailed(_ key: String) -> Bool { failures.contains(key) }

    /// A command for `key` was rejected: drops the pending value (only this commit's, with a generation) and shows
    /// the failed face for ``failureDuration``. An older failure never undoes a newer tap (a stale generation is ignored).
    public func fail(_ key: String, generation: Int? = nil) {
        if let generation, let current = generations[key], generation != current { return }
        if isTracked(key) { reset(key, generation: generation) }
        markFailed(key)
    }

    /// Shows the failed face for `key` for ``failureDuration``, for a command that carried no optimistic value (a
    /// one-tap automation, a lock that stays put). Any key works, tracked or not. A new commit or failure restarts it.
    public func markFailed(_ key: String) {
        failures.insert(key)
        let generation = (failureGenerations[key] ?? 0) + 1
        failureGenerations[key] = generation
        failureTimers[key]?.cancel()
        failureTimers[key] = scheduler.schedule(after: Self.failureDuration) { [weak self] in
            guard let self, self.failureGenerations[key] == generation else { return }
            self.failureTimers[key] = nil
            self.failures.remove(key)
        }
    }

    /// Hides the failed face now (the next tap, or the control closing).
    public func clearFailure(_ key: String) {
        failureTimers[key]?.cancel()
        failureTimers[key] = nil
        failureGenerations[key] = (failureGenerations[key] ?? 0) + 1
        if failures.contains(key) { failures.remove(key) }
    }

    /// Drops the pending value; with a generation, only if no newer commit replaced it (a failed call).
    public func reset(_ key: String, generation: Int? = nil) {
        guard isTracked(key) else { return }
        if let generation, generation != generations[key] { return }
        generations[key] = (generations[key] ?? 0) + 1
        timers[key]?.cancel()
        timers[key] = nil
        clear(key)
    }

    /// Reports the live value. A change confirms (or, for ``ClearRule/liveChange``, clears) the pending value.
    public func liveChanged(_ key: String, to live: String?) {
        guard let rule = ruleOverrides[key] ?? rules[key] else { return }
        guard let previous = lastLive[key] else {
            lastLive[key] = .some(live)
            return
        }
        guard previous != live else { return }
        lastLive[key] = .some(live)
        guard let value = pending[key] else { return }
        if rule == .liveChange || value == live {
            timers[key]?.cancel()
            timers[key] = nil
            clear(key)
        }
    }

    private func clear(_ key: String) {
        if pending[key] != nil { pending[key] = nil }
    }
}

// MARK: - Active hold

/// Keeps a device showing active for a while after its live state drops (web `useHeldDeviceState`), so the
/// Music Room Xbox tile doesn't flicker off while the console's cloud state catches up.
@MainActor
@Observable
public final class ActiveHoldTracker {
    struct Entry: Equatable {
        var holding: Bool
        var liveActive: Bool
        var resetKey: String
    }

    private(set) var entries: [String: Entry] = [:]
    @ObservationIgnored private let scheduler: any RevertScheduler
    @ObservationIgnored private var timers: [String: any ScheduledWork] = [:]

    /// Creates a tracker.
    public init(scheduler: any RevertScheduler) { self.scheduler = scheduler }

    /// Feeds the latest live facts for `key`.
    /// - Parameters:
    ///   - liveActive: The live (not optimistic) state counts as active.
    ///   - hasOverride: An optimistic value is showing; it wins over any hold.
    ///   - hold: How long to hold; `nil` disables holding.
    ///   - resetKey: Changes when a related entity changes, which ends the hold.
    public func update(_ key: String, liveActive: Bool, hasOverride: Bool, hold: Duration?, resetKey: String) {
        guard let current = entries[key] else {
            entries[key] = Entry(holding: false, liveActive: liveActive, resetKey: resetKey)
            return
        }
        var next = current
        if resetKey != current.resetKey || liveActive != current.liveActive || ((hold == nil || hasOverride) && current.holding) {
            next.holding = resetKey != current.resetKey || hold == nil || hasOverride
                ? false
                : liveActive || current.liveActive || current.holding
            next.liveActive = liveActive
            next.resetKey = resetKey
        }
        let changed = next != current
        if changed { entries[key] = next }
        guard let hold, !hasOverride, !next.liveActive, next.holding else {
            timers[key]?.cancel()
            timers[key] = nil
            return
        }
        // Like the web effect, the timer restarts only when the hold's own inputs change.
        if changed || timers[key] == nil {
            timers[key]?.cancel()
            timers[key] = scheduler.schedule(after: hold) { [weak self] in
                guard let self, var entry = self.entries[key], entry.holding, !entry.liveActive else { return }
                entry.holding = false
                self.entries[key] = entry
                self.timers[key] = nil
            }
        }
    }

    /// The state to show: the first active state while holding, else `displayed`.
    public func held(_ key: String, displayed: String, activeStates: [String], hasOverride: Bool, hold: Duration?) -> String {
        guard let entry = entries[key], hold != nil, !hasOverride, !entry.liveActive, entry.holding else { return displayed }
        return activeStates.first ?? displayed
    }
}
