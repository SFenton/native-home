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
/// - **Readers follow the output only.** Observation merges what a nested tracking scope reads into the scope around it, so a value
///   is never evaluated inside a reader's run: make it where no observation is running (an owner's `init`, ``SharedLogic``'s hop), and
///   it settles on the main actor in the hop after a change, ahead of the readers' own re-run. A reader that runs in between reads the
///   last result, and is woken again if the settled result differs.
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
    private var isCancelled = false
    /// The owner whose counts this value's runs belong to (``LogicCost/Tally``), or `nil` for the process-wide counters only.
    private let tally: LogicCost.Tally?

    /// How many times `read` ran, the first run included. Tests and the logic counters read it.
    public private(set) var evaluations = 0

    /// Computes the value now and starts following what `read` reads. Call it where no observation is running, or that observation
    /// follows every input too (Observation merges the scopes).
    /// - Parameters:
    ///   - tally: The owner's tally, so a test or a renderer counts the runs of its own values apart from every other owner's.
    ///   - read: Reads observable state and answers. It runs on the main actor, now and after any input it read changed.
    public init(tally: LogicCost.Tally? = nil, _ read: @escaping @MainActor () -> Value) {
        self.read = read
        self.tally = tally
        stored = refresh()
    }

    /// The result, tracked by the observation that reads it. It never runs `read`: the last settled result, held by the reader's run.
    public var current: Value {
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
        LogicCost.measure(in: tally) {
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
        guard stored != next else { return LogicCost.skippedEqual(in: tally) }
        registrar.withMutation(of: self, keyPath: \.current) { stored = next }
    }

    /// Settles in the main-actor hop after the change, once for any number of changes in the turn, ahead of the readers' re-run.
    private func schedule() {
        guard !isCancelled, dirty.isSet else { return }
        settle()
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
