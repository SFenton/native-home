import Foundation

/// What evaluating authored logic costs the main thread (pattern: `.agents/patterns/telemetry.md`; budgets: `.agents/testing/apple/logic-evaluation.md`).
///
/// Authored logic (a node's `visibleWhen`, rules, badges and text expressions, a tab's badge and visibility) runs inside an observation that
/// re-runs when an entity it read changes. Every such run goes through ``measure(_:)``, so the counters say how many evaluations a live
/// update caused, not only how many boxes it wrote:
///
/// | Counter | Meaning |
/// |---|---|
/// | ``runsCounter`` | evaluations, the first run of an observation and each re-run |
/// | ``runMicrosecondsCounter`` | wall time those evaluations took, in microseconds |
/// | ``skippedEqualCounter`` | evaluations whose result equalled the one already shown, so no view was written |
///
/// A page nobody updates runs nothing, so these cost nothing while it idles; each evaluation adds two counter writes and one signpost.
///
/// The counters are process-wide. Code that needs the count of one renderer, scene or test (a hosted test that must see exactly the runs
/// its own scene made, with no stray observer from another scene in the number) gives that owner a ``Tally``: every evaluation and equal
/// result its observations make is added to it as well.
public enum LogicCost {
    // MARK: - A count for one owner

    /// The evaluations of one owner (a renderer's pages, tab bar and shared values), counted apart from the process-wide counters.
    ///
    /// It counts exactly what the counters count, while telemetry records, and only what was handed this tally: a run in another
    /// renderer, or in no renderer, is never in it. Written and read on the main actor only.
    public final class Tally: @unchecked Sendable {
        /// Evaluations, the first run of an observation and each re-run.
        public private(set) var runs = 0
        /// Their wall time in microseconds.
        public private(set) var runMicroseconds = 0
        /// Evaluations whose result equalled the one shown, so no view was written.
        public private(set) var skippedEqual = 0

        /// Creates an empty tally.
        public init() {}

        /// Counts one evaluation of `microseconds`.
        func addRun(microseconds: Int) {
            runs += 1
            runMicroseconds += microseconds
        }

        /// Counts one evaluation that changed nothing a view shows.
        func addSkippedEqual() { skippedEqual += 1 }
    }

    /// The tally of the evaluation in progress, so an equal result noted deep inside it (``skippedEqual(in:)``) reaches its owner.
    /// Touched on the main actor only, around ``measure(in:_:)``.
    nonisolated(unsafe) private static var activeTally: Tally?

    // MARK: - Counters

    /// The counter of evaluations.
    public static let runsCounter = "logic.runs"
    /// The counter of time spent evaluating, in microseconds.
    public static let runMicrosecondsCounter = "logic.runUs"
    /// The counter of evaluations that changed nothing a view shows.
    public static let skippedEqualCounter = "logic.skippedEqual"

    /// Runs one evaluation of authored logic: a signpost around it and, while telemetry records, one run and its duration on the counters.
    /// - Parameters:
    ///   - tally: The owner's tally, which counts the run too; `nil` leaves the evaluation to the process-wide counters, or to the
    ///     tally of the evaluation it runs inside.
    ///   - evaluation: The observation's closure.
    @MainActor
    public static func measure(in tally: Tally? = nil, _ evaluation: @MainActor () -> Void) {
        let outer = activeTally
        let owner = tally ?? outer
        activeTally = owner
        defer { activeTally = outer }
        let state = Telemetry.signposter.beginInterval(Telemetry.Name.logicRun)
        let start = DispatchTime.now().uptimeNanoseconds
        evaluation()
        let elapsed = DispatchTime.now().uptimeNanoseconds &- start
        Telemetry.signposter.endInterval(Telemetry.Name.logicRun, state)
        record(nanoseconds: elapsed, in: owner)
    }

    /// Counts one evaluation of `nanoseconds`; ``measure(in:_:)`` calls it, and a test can call it with a known duration.
    public static func record(nanoseconds: UInt64, in tally: Tally? = nil) {
        guard Telemetry.isEnabled else { return }
        Telemetry.count(runsCounter)
        Telemetry.count(runMicrosecondsCounter, by: Int(nanoseconds / 1000))
        tally?.addRun(microseconds: Int(nanoseconds / 1000))
    }

    /// Counts an evaluation whose result equalled the one already shown, so it wrote no view.
    /// - Parameter tally: The owner's tally; `nil` counts for the evaluation in progress, if it has one.
    public static func skippedEqual(in tally: Tally? = nil) {
        guard Telemetry.isEnabled else { return }
        Telemetry.count(skippedEqualCounter)
        (tally ?? activeTally)?.addSkippedEqual()
    }
}
