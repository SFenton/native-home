import CoreGraphics
import Foundation

/// The timeline of a ticker pass (pattern: `.agents/patterns/ticker.md`), pure so it is unit-tested.
///
/// One pass is: hold at the start, travel to the end at ``MotionTokens/Ticker/speed``, hold at the end, return to the start.
/// ``MotionTokens/Ticker/passes`` passes play, then the label rests at the start. A label that fits its column has no plan to play.
public struct TickerPlan: Equatable, Sendable {
    /// The label's natural one-line width.
    public var textWidth: CGFloat
    /// The width the label has.
    public var columnWidth: CGFloat

    public init(textWidth: CGFloat, columnWidth: CGFloat) {
        self.textWidth = textWidth
        self.columnWidth = columnWidth
    }

    /// Whether the label is wider than its column. False until both widths are measured.
    public var overflows: Bool {
        textWidth > 0 && columnWidth > 0 && textWidth - columnWidth > MotionTokens.Ticker.overflowTolerance
    }

    /// How far the label travels, in points; 0 when it fits.
    public var travel: CGFloat { overflows ? textWidth - columnWidth : 0 }

    /// Seconds spent travelling in one pass.
    public var travelDuration: TimeInterval { TimeInterval(travel / MotionTokens.Ticker.speed) }

    /// Seconds in one pass: hold, travel, hold, return.
    public var passDuration: TimeInterval {
        overflows ? MotionTokens.Ticker.hold * 2 + travelDuration + MotionTokens.Ticker.returnDuration : 0
    }

    /// Seconds in all the passes.
    public var totalDuration: TimeInterval { passDuration * TimeInterval(MotionTokens.Ticker.passes) }

    /// The pass playing `elapsed` seconds in (0-based), or nil when the passes are done or nothing overflows.
    public func pass(at elapsed: TimeInterval) -> Int? {
        guard overflows, elapsed >= 0, elapsed < totalDuration else { return nil }
        return Int(elapsed / passDuration)
    }

    /// Whether all passes have played.
    public func isFinished(at elapsed: TimeInterval) -> Bool { overflows && elapsed >= totalDuration }

    /// How far the label has moved left of its start `elapsed` seconds in: 0 while holding at the start, ``travel`` while holding
    /// at the end, and 0 once the passes are done.
    public func offset(at elapsed: TimeInterval) -> CGFloat {
        guard let pass = pass(at: elapsed) else { return 0 }
        let t = elapsed - TimeInterval(pass) * passDuration
        let hold = MotionTokens.Ticker.hold
        if t < hold { return 0 }
        if t < hold + travelDuration { return CGFloat((t - hold) / travelDuration) * travel }
        if t < hold * 2 + travelDuration { return travel }
        let back = min(1, (t - hold * 2 - travelDuration) / MotionTokens.Ticker.returnDuration)
        return travel * CGFloat(1 - (1 - (1 - back) * (1 - back)))
    }
}
