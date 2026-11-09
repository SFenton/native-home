import Foundation
import Testing
@testable import HassTelemetry

@MainActor
struct MainThreadCostMeterTests {
    @Test func reportCountsLongTurnsAndPercentiles() {
        let turns = [1.0, 2.0, 5.0, 9.0, 17.0].map { MainThreadCostMeter.Turn(cpuMs: $0) }
        let report = MainThreadCostMeter.report(
            seconds: 8, process: ProcessCPU.Snapshot(instructions: 2_500_000_000, cpuSeconds: 0.75), mainSeconds: 0.5, turns: turns)
        #expect(report.turns == 5)
        #expect(report.turnsOver4 == 3)
        #expect(report.turnsOver8 == 2)
        #expect(report.turnsOver16 == 1)
        #expect(report.worstTurnMs == 17)
        #expect(report.p95TurnMs == 17)
        #expect(report.megaInstructions == 2500)
        #expect(report.summary.contains("minstr=2500.00"))
        #expect(report.summary.contains("over8=2"))
    }

    @Test func emptyRunReportsZeros() {
        let report = MainThreadCostMeter.report(seconds: 1, process: .zero, mainSeconds: 0, turns: [])
        #expect(report.turns == 0)
        #expect(report.worstTurnMs == 0)
        #expect(report.p95TurnMs == 0)
    }

    @Test func processCountersGrowWithWork() {
        let before = ProcessCPU.snapshot()
        let threadBefore = ProcessCPU.currentThreadSeconds()
        var total = 0.0
        for index in 0..<3_000_000 { total += Double(index).squareRoot() }
        #expect(total > 0)
        let after = ProcessCPU.snapshot()
        #expect(after.cpuSeconds >= before.cpuSeconds)
        #expect(ProcessCPU.currentThreadSeconds() > threadBefore)
    }

    @Test func meterSeesATurnThatComputes() async {
        let meter = MainThreadCostMeter()
        meter.begin()
        // Two run-loop turns: sleep so the loop goes back to waiting, then compute in a later turn.
        try? await Task.sleep(for: .milliseconds(20))
        var total = 0.0
        for index in 0..<2_000_000 { total += Double(index).squareRoot() }
        try? await Task.sleep(for: .milliseconds(20))
        let report = meter.finish()
        #expect(total > 0)
        #expect(report.turns >= 1)
        #expect(report.seconds > 0.03)
    }
}
