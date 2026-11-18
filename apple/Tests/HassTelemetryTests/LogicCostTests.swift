import Foundation
@testable import HassTelemetry
import Testing

/// The `logic.*` counters (``LogicCost``): every evaluation is counted and timed while telemetry records, and nothing is counted while it does not.
@MainActor
struct LogicCostTests {
    private func delta(_ counter: String, during work: () -> Void) -> Int {
        let before = Telemetry.log.counters[counter] ?? 0
        work()
        return (Telemetry.log.counters[counter] ?? 0) - before
    }

    @Test func everyEvaluationIsCountedOnceAndTimed() {
        let wasEnabled = Telemetry.isEnabled
        defer { Telemetry.isEnabled = wasEnabled }
        Telemetry.isEnabled = true
        var ran = 0
        let runs = delta(LogicCost.runsCounter) {
            for _ in 0..<3 { LogicCost.measure { ran += 1 } }
        }
        #expect(ran == 3, "the evaluation itself runs exactly once per call")
        #expect(runs == 3, "one count per evaluation")
    }

    @Test func theDurationIsTheEvaluationsOwnTimeInMicroseconds() {
        let wasEnabled = Telemetry.isEnabled
        defer { Telemetry.isEnabled = wasEnabled }
        Telemetry.isEnabled = true
        #expect(delta(LogicCost.runMicrosecondsCounter) { LogicCost.record(nanoseconds: 2_500_000) } == 2500)
        #expect(delta(LogicCost.runMicrosecondsCounter) { LogicCost.record(nanoseconds: 999) } == 0, "under a microsecond rounds down, not up")
        let slow = delta(LogicCost.runMicrosecondsCounter) { LogicCost.measure { Thread.sleep(forTimeInterval: 0.02) } }
        #expect(slow >= 19_000, "a 20 ms evaluation reads about 20,000 microseconds")
    }

    @Test func anEqualResultIsCountedApartFromTheRun() {
        let wasEnabled = Telemetry.isEnabled
        defer { Telemetry.isEnabled = wasEnabled }
        Telemetry.isEnabled = true
        #expect(delta(LogicCost.skippedEqualCounter) { LogicCost.skippedEqual(); LogicCost.skippedEqual() } == 2)
        #expect(delta(LogicCost.runsCounter) { LogicCost.skippedEqual() } == 0, "skipping is not a run")
    }

    @Test func nothingIsCountedWhileTelemetryIsOff() {
        let wasEnabled = Telemetry.isEnabled
        defer { Telemetry.isEnabled = wasEnabled }
        Telemetry.isEnabled = false
        var ran = 0
        #expect(delta(LogicCost.runsCounter) { LogicCost.measure { ran += 1 }; LogicCost.skippedEqual() } == 0)
        #expect(delta(LogicCost.skippedEqualCounter) { LogicCost.skippedEqual() } == 0)
        #expect(ran == 1, "the evaluation still runs when nothing records it")
    }

    @Test func theCounterNamesAreTheOnesTheScrollCostLineReads() {
        #expect(LogicCost.runsCounter == "logic.runs")
        #expect(LogicCost.runMicrosecondsCounter == "logic.runUs")
        #expect(LogicCost.skippedEqualCounter == "logic.skippedEqual")
    }
}
