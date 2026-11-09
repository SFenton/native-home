import Foundation
@testable import HassDesign
import Testing

/// ``TickerPlan``, ``TickerClock`` and the ticker's tokens (pattern: `.agents/patterns/ticker.md`).
struct TickerPlanTests {
    /// 300 pt of text in 200 pt of column: 100 pt of travel, 3.333 s at 30 pt/s.
    private let plan = TickerPlan(textWidth: 300, columnWidth: 200)

    @Test func tokensHaveTheirSpecifiedValues() {
        #expect(MotionTokens.Ticker.speed == 30)
        #expect(MotionTokens.Ticker.hold == 1.5)
        #expect(MotionTokens.Ticker.passes == 3)
        #expect(MotionTokens.Ticker.returnDuration == 0.3)
    }

    @Test func overflowComparesTheNaturalWidthWithTheColumn() {
        #expect(plan.overflows)
        #expect(!TickerPlan(textWidth: 200, columnWidth: 200).overflows)
        #expect(!TickerPlan(textWidth: 200.4, columnWidth: 200).overflows)
        #expect(TickerPlan(textWidth: 200.6, columnWidth: 200).overflows)
        #expect(!TickerPlan(textWidth: 150, columnWidth: 200).overflows)
    }

    @Test func nothingOverflowsBeforeBothWidthsAreMeasured() {
        #expect(!TickerPlan(textWidth: 0, columnWidth: 0).overflows)
        #expect(!TickerPlan(textWidth: 300, columnWidth: 0).overflows)
        #expect(!TickerPlan(textWidth: 0, columnWidth: 200).overflows)
    }

    @Test func aLabelThatFitsHasNothingToPlay() {
        let fits = TickerPlan(textWidth: 120, columnWidth: 200)
        #expect(fits.travel == 0)
        #expect(fits.passDuration == 0)
        #expect(fits.totalDuration == 0)
        #expect(fits.pass(at: 0) == nil)
        #expect(!fits.isFinished(at: 100))
        #expect(fits.offset(at: 5) == 0)
    }

    @Test func aPassIsHoldTravelHoldReturn() {
        #expect(plan.travel == 100)
        #expect(abs(plan.travelDuration - 100.0 / 30.0) < 1e-9)
        #expect(abs(plan.passDuration - (1.5 + 100.0 / 30.0 + 1.5 + 0.3)) < 1e-9)
        #expect(abs(plan.totalDuration - 3 * plan.passDuration) < 1e-9)
    }

    @Test func theOffsetHoldsTravelsHoldsAndReturns() {
        #expect(plan.offset(at: 0) == 0)
        #expect(plan.offset(at: 1.4) == 0)
        // Half way through the travel.
        #expect(abs(plan.offset(at: 1.5 + plan.travelDuration / 2) - 50) < 1e-6)
        // Constant speed: 30 pt per second.
        #expect(abs(plan.offset(at: 2.5) - 30) < 1e-6)
        #expect(abs(plan.offset(at: 1.5 + plan.travelDuration + 0.5) - 100) < 1e-6)
        let returning = 1.5 + plan.travelDuration + 1.5 + 0.15
        #expect(plan.offset(at: returning) > 0 && plan.offset(at: returning) < 100)
        #expect(abs(plan.offset(at: plan.passDuration) - 0) < 1e-6)
    }

    @Test func theOffsetNeverLeavesItsRange() {
        var t = 0.0
        while t < plan.totalDuration + 2 {
            let offset = plan.offset(at: t)
            #expect(offset >= 0 && offset <= plan.travel)
            t += 0.05
        }
    }

    @Test func threePassesPlayThenTheLabelRestsAtTheStart() {
        let pass = plan.passDuration
        #expect(plan.pass(at: 0) == 0)
        #expect(plan.pass(at: pass - 0.01) == 0)
        #expect(plan.pass(at: pass) == 1)
        #expect(plan.pass(at: 2 * pass + 1) == 2)
        #expect(plan.pass(at: 3 * pass) == nil)
        #expect(!plan.isFinished(at: 3 * pass - 0.01))
        #expect(plan.isFinished(at: 3 * pass))
        #expect(plan.offset(at: 3 * pass + 4) == 0)
        #expect(plan.pass(at: -1) == nil)
    }

    @Test func aWiderLabelTakesLongerButNeverFaster() {
        let wider = TickerPlan(textWidth: 400, columnWidth: 200)
        #expect(wider.passDuration > plan.passDuration)
        // Speed is the same: 30 pt/s in the middle of the travel.
        let t = 1.5 + 1.0
        #expect(abs(wider.offset(at: t + 1) - wider.offset(at: t) - 30) < 1e-6)
    }

    @Test func theClockKeepsItsTimeAcrossPauses() {
        var clock = TickerClock()
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        #expect(!clock.isRunning)
        #expect(clock.elapsed(at: start) == 0)
        clock.resume(at: start)
        #expect(clock.isRunning)
        #expect(clock.elapsed(at: start.addingTimeInterval(2)) == 2)
        clock.pause(at: start.addingTimeInterval(2))
        #expect(!clock.isRunning)
        #expect(clock.elapsed(at: start.addingTimeInterval(50)) == 2)
        clock.resume(at: start.addingTimeInterval(60))
        #expect(clock.elapsed(at: start.addingTimeInterval(61)) == 3)
        clock.restart()
        #expect(clock.elapsed(at: start.addingTimeInterval(100)) == 0)
        #expect(!clock.isRunning)
    }
}
