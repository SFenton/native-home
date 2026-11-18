import Foundation
import HassTelemetry
import Observation

// MARK: - A value computed from other observable values

/// A value computed from other observable values, evaluated once for every reader and announced only when it changes.
///
/// Logic that several screens share (the Profile attention count, a status summed over many entities, one authored expression used
/// in ten places) would otherwise run once per reader, each in its own observation, and wake every reader whenever any input moved.
/// A derived value runs once, follows exactly what `read` reads (Observation records it, and re-records it on every run, so a branch
/// that flips changes what is followed), and writes ``current`` only when the result differs. Readers read ``current`` inside their
/// own observation like they read an ``EntityBox``: an input that moves without changing the result wakes no one.
///
/// - **No work proportional to the house.** An entity nobody's `read` reads costs nothing; a changed input costs one run per turn,
///   however many inputs changed or readers there are.
/// - **Never stale.** A change marks the value dirty at once, and ``current`` runs a dirty value before it answers, so a reader that
///   is awake for another reason in the same turn still sees the new result. The run the change also schedules finds nothing to do
///   in that case.
/// - **Session scope.** It lives as long as its owner holds it (``DerivedValues`` holds it weakly, so the last reader leaving ends it)
///   and not as long as any page: a page that goes away takes nothing with it that another page reads.
///
/// Observation only, no UI (pattern: derived-value).
@MainActor
public final class DerivedValue<Value: Equatable>: Observable {
    private let registrar = ObservationRegistrar()
    private let read: @MainActor () -> Value
    private let dirty = DirtyFlag()
    /// What this value's own runs read, so a derived value built on another keeps it alive.
    private let readers = DerivedReaders()
    private var stored: Value?
    private var isScheduled = false
    private var isCancelled = false

    /// How many times `read` ran, the first run included. Tests and the logic counters read it.
    public private(set) var evaluations = 0

    /// Computes the value now and starts following what `read` reads.
    /// - Parameter read: Reads observable state and answers. It runs on the main actor, now and after any input it read changed.
    public init(_ read: @escaping @MainActor () -> Value) {
        self.read = read
        stored = refresh()
    }

    /// The result, tracked by the observation that reads it. Runs first when an input changed since the last run.
    public var current: Value {
        if dirty.isSet, !isCancelled { settle() }
        DerivedReaders.note(self)
        registrar.access(self, keyPath: \.current)
        return stored!
    }

    /// Stops following the inputs. ``current`` keeps the last result.
    public func cancel() { isCancelled = true }

    // MARK: Running

    /// One run of `read`, tracked. Clears the dirty mark first: a change after this point marks it again.
    private func refresh() -> Value {
        dirty.clear()
        var result: Value?
        let flag = dirty
        LogicCost.measure {
            withObservationTracking { readers.run { result = read() } } onChange: { [weak self] in
                // Fires in the input's `willSet`, on whatever thread wrote it, once: mark now, run on the main actor next turn.
                flag.set()
                Task { @MainActor [weak self] in self?.schedule() }
            }
        }
        evaluations += 1
        return result!
    }

    /// Runs the dirty value and writes ``current`` only when the result is different.
    private func settle() {
        let next = refresh()
        guard stored != next else { return LogicCost.skippedEqual() }
        registrar.withMutation(of: self, keyPath: \.current) { stored = next }
    }

    /// Asks the run loop to settle once for any number of changes in this turn.
    private func schedule() {
        guard !isScheduled, !isCancelled, dirty.isSet else { return }
        isScheduled = true
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isScheduled = false
                if self.dirty.isSet, !self.isCancelled { self.settle() }
            }
        }
    }
}

// MARK: - The dirty mark

/// A flag an observation's `onChange` can set from any thread.
private final class DirtyFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
    func clear() { lock.lock(); value = false; lock.unlock() }
}
