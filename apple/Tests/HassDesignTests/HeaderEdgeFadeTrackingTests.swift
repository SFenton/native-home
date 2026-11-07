import CoreGraphics
@testable import HassDesign
import Testing

struct HeaderEdgeFadeTrackingTests {
    @Test func theTrackedOffsetIsWholePointsFromTheRestingTop() {
        // Large title page at rest: offset -103 under a 103 pt inset is zero.
        #expect(HeaderEdgeFade.trackedOffset(contentOffset: -103, topInset: 103) == 0)
        #expect(HeaderEdgeFade.trackedOffset(contentOffset: -83.4, topInset: 103) == 20)
        #expect(HeaderEdgeFade.trackedOffset(contentOffset: -82.6, topInset: 103) == 20)
    }

    @Test func itIsClampedSoOnlyChangesThatMoveTheMaskAreReported() {
        // Pulled down past the top: -1, never lower.
        #expect(HeaderEdgeFade.trackedOffset(contentOffset: -240, topInset: 103) == -1)
        // Scrolled a long way: one past the ramp, however far.
        #expect(HeaderEdgeFade.trackedOffset(contentOffset: 5000, topInset: 103) == HeaderEdgeFade.rampHeight + 1)
        #expect(HeaderEdgeFade.trackedOffset(contentOffset: 900, topInset: 103) == HeaderEdgeFade.trackedOffset(contentOffset: 4000, topInset: 103))
        #expect(HeaderEdgeFade.trackedOffset(contentOffset: -63, topInset: 103, rampHeight: 10) == 11)
    }
}
