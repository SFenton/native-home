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
public enum LogicCost {
    /// The counter of evaluations.
    public static let runsCounter = "logic.runs"
    /// The counter of time spent evaluating, in microseconds.
    public static let runMicrosecondsCounter = "logic.runUs"
    /// The counter of evaluations that changed nothing a view shows.
    public static let skippedEqualCounter = "logic.skippedEqual"

    /// Runs one evaluation of authored logic: a signpost around it and, while telemetry records, one run and its duration on the counters.
    /// - Parameter evaluation: The observation's closure.
    @MainActor
    public static func measure(_ evaluation: @MainActor () -> Void) {
        let state = Telemetry.signposter.beginInterval(Telemetry.Name.logicRun)
        let start = DispatchTime.now().uptimeNanoseconds
        evaluation()
        let elapsed = DispatchTime.now().uptimeNanoseconds &- start
        Telemetry.signposter.endInterval(Telemetry.Name.logicRun, state)
        record(nanoseconds: elapsed)
    }

    /// Counts one evaluation of `nanoseconds`; ``measure(_:)`` calls it, and a test can call it with a known duration.
    public static func record(nanoseconds: UInt64) {
        Telemetry.count(runsCounter)
        Telemetry.count(runMicrosecondsCounter, by: Int(nanoseconds / 1000))
    }

    /// Counts an evaluation whose result equalled the one already shown, so it wrote no view.
    public static func skippedEqual() {
        Telemetry.count(skippedEqualCounter)
    }
}
