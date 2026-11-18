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

    // MARK: A tally counts one owner

    @Test func aTallyCountsOnlyTheEvaluationsItWasHanded() {
        let wasEnabled = Telemetry.isEnabled
        defer { Telemetry.isEnabled = wasEnabled }
        Telemetry.isEnabled = true
        let mine = LogicCost.Tally(), theirs = LogicCost.Tally()
        let processWide = delta(LogicCost.runsCounter) {
            for _ in 0..<3 { LogicCost.measure(in: mine) {} }
            LogicCost.measure(in: theirs) {}
            LogicCost.measure {}
        }
        #expect(mine.runs == 3)
        #expect(theirs.runs == 1, "another owner's run is never in mine")
        #expect(processWide == 5, "the process-wide counter still counts every run, tallied or not")
    }

    @Test func aTallyAddsUpTheTimeOfItsRuns() {
        let wasEnabled = Telemetry.isEnabled
        defer { Telemetry.isEnabled = wasEnabled }
        Telemetry.isEnabled = true
        let tally = LogicCost.Tally()
        LogicCost.record(nanoseconds: 2_500_000, in: tally)
        LogicCost.record(nanoseconds: 1_000_000, in: tally)
        #expect(tally.runs == 2)
        #expect(tally.runMicroseconds == 3500)
    }

    @Test func anEqualResultReachesTheTallyOfTheRunItIsNotedIn() {
        let wasEnabled = Telemetry.isEnabled
        defer { Telemetry.isEnabled = wasEnabled }
        Telemetry.isEnabled = true
        let inside = LogicCost.Tally(), outside = LogicCost.Tally()
        LogicCost.measure(in: inside) { LogicCost.skippedEqual() }
        LogicCost.skippedEqual()
        LogicCost.skippedEqual(in: outside)
        #expect(inside.skippedEqual == 1, "noted inside the run, it goes to the run's owner without being told whose it is")
        #expect(outside.skippedEqual == 1, "named explicitly, it goes where it is told")
        #expect(inside.runs == 1 && outside.runs == 0)
    }

    @Test func aRunInsideARunKeepsTheOuterOwner() {
        let wasEnabled = Telemetry.isEnabled
        defer { Telemetry.isEnabled = wasEnabled }
        Telemetry.isEnabled = true
        let owner = LogicCost.Tally()
        LogicCost.measure(in: owner) { LogicCost.measure {} }
        #expect(owner.runs == 2, "an evaluation nested in an owner's evaluation is the owner's")
        LogicCost.skippedEqual()
        #expect(owner.skippedEqual == 0, "and the owner is released when its run ends")
    }

    @Test func aTallyCountsNothingWhileTelemetryIsOff() {
        let wasEnabled = Telemetry.isEnabled
        defer { Telemetry.isEnabled = wasEnabled }
        Telemetry.isEnabled = false
        let tally = LogicCost.Tally()
        LogicCost.measure(in: tally) { LogicCost.skippedEqual() }
        #expect(tally.runs == 0 && tally.skippedEqual == 0)
    }
}
