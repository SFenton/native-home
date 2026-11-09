import Foundation
@testable import HassTelemetry
import Testing

/// Named intervals begun in one place and ended in another, once.
@Suite(.serialized)
struct TrackedIntervalsTests {
    @Test func theNamesAreTheOnesUITestsReadInTheTelemetryCategory() {
        #expect(Telemetry.subsystem == "com.sfenton.home" && Telemetry.category == "Performance")
        #expect(["\(Telemetry.Name.launch)", "\(Telemetry.Name.snapshotShown)", "\(Telemetry.Name.signIn)",
                 "\(Telemetry.Name.arrival)", "\(Telemetry.Name.reconnect)"] == ["Launch", "SnapshotShown", "SignIn", "Arrival", "Reconnect"])
    }

    /// Reads the interval's own clock and leaves the shared log alone.
    private func quiet() -> TrackedIntervals {
        TrackedIntervals { (ContinuousClock.now - $0.start).milliseconds }
    }

    @Test func anIntervalEndsOnceAndReportsItsLength() async throws {
        let intervals = quiet()
        #expect(intervals.end(Telemetry.Name.signIn) == nil, "ending an interval that never began does nothing")
        intervals.begin(Telemetry.Name.signIn)
        #expect(intervals.isOpen(Telemetry.Name.signIn))
        intervals.begin(Telemetry.Name.signIn) // already open: keeps the first start
        try await Task.sleep(for: .milliseconds(20))
        let ms = try #require(intervals.end(Telemetry.Name.signIn))
        #expect(ms >= 15)
        #expect(!intervals.isOpen(Telemetry.Name.signIn))
        #expect(intervals.end(Telemetry.Name.signIn) == nil, "a second end does nothing")
    }

    @Test func aCancelledIntervalClosesWithoutEndingIt() {
        let ended = Counter()
        let intervals = TrackedIntervals { _ in ended.bump(); return 0 }
        intervals.cancel(Telemetry.Name.reconnect) // not open: nothing happens
        intervals.begin(Telemetry.Name.reconnect)
        intervals.cancel(Telemetry.Name.reconnect)
        #expect(!intervals.isOpen(Telemetry.Name.reconnect))
        #expect(ended.value == 0, "a cancelled interval is never ended, so it is never recorded")
    }

    @Test func aFinishedIntervalIsEndedOnce() {
        let ended = Counter()
        let intervals = TrackedIntervals { _ in ended.bump(); return 7 }
        intervals.begin(Telemetry.Name.arrival)
        #expect(intervals.end(Telemetry.Name.arrival) == 7)
        #expect(intervals.end(Telemetry.Name.arrival) == nil)
        #expect(ended.value == 1)
    }

    private final class Counter: @unchecked Sendable {
        private(set) var value = 0
        func bump() { value += 1 }
    }

    @Test func theSharedFacadeBeginsEndsAndCancels() {
        // Begin and cancel only: ending records in the shared log, which `TelemetryTests` counts.
        Telemetry.cancelTracked(Telemetry.Name.launch)
        Telemetry.beginTracked(Telemetry.Name.launch)
        #expect(Telemetry.isTracked(Telemetry.Name.launch))
        Telemetry.cancelTracked(Telemetry.Name.launch)
        #expect(!Telemetry.isTracked(Telemetry.Name.launch))
    }
}
