import Foundation
@testable import HassCore
import Testing

/// The frame-stall rule with a made-up clock (web `FRAME_STALL_MS`).
struct FrameStallDetectorTests {
    private let start = ContinuousClock.now

    private func at(_ seconds: Double) -> ContinuousClock.Instant { start.advanced(by: .seconds(seconds)) }

    /// `#expect` cannot call a mutating member, so readings go through here.
    private func stalled(_ detector: inout FrameStallDetector, _ frames: Int, _ seconds: Double) -> Bool {
        detector.observe(frames: frames, at: at(seconds))
    }

    @Test func advancingFramesNeverStall() {
        var detector = FrameStallDetector()
        for second in 0..<30 { #expect(!stalled(&detector, second * 15, Double(second))) }
    }

    @Test func aCountThatStaysPutStallsAfterEightSeconds() {
        var detector = FrameStallDetector()
        #expect(!stalled(&detector, 100, 0))
        for second in 1..<8 { #expect(!stalled(&detector, 100, Double(second)), "Second \(second)") }
        #expect(stalled(&detector, 100, 8))
    }

    @Test func framesResumingBeforeTheLimitClearTheClock() {
        var detector = FrameStallDetector()
        _ = detector.observe(frames: 10, at: at(0))
        #expect(!stalled(&detector, 10, 7))
        #expect(!stalled(&detector, 11, 8))
        #expect(!stalled(&detector, 11, 15), "Eight seconds are counted from the last advance")
        #expect(stalled(&detector, 11, 16))
    }

    @Test func resetStartsOver() {
        var detector = FrameStallDetector()
        _ = detector.observe(frames: 5, at: at(0))
        #expect(stalled(&detector, 5, 9))
        detector.reset()
        #expect(!stalled(&detector, 5, 10), "The first reading after a reset only sets the baseline")
        #expect(!stalled(&detector, 5, 17))
        #expect(stalled(&detector, 5, 18))
    }

    @Test func aCountThatGoesBackwardsIsProgress() {
        var detector = FrameStallDetector()
        _ = detector.observe(frames: 500, at: at(0))
        #expect(!stalled(&detector, 3, 9), "A restarted stream counts from zero")
    }

    @Test func aCustomLimitIsHonoured() {
        var detector = FrameStallDetector(stallAfter: .seconds(2))
        _ = detector.observe(frames: 1, at: at(0))
        #expect(!stalled(&detector, 1, 1))
        #expect(stalled(&detector, 1, 2))
    }
}
