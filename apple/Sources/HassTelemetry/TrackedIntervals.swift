import Foundation
import os

/// Intervals begun in one place and ended in another (``Telemetry/Name/launch``, ``Telemetry/Name/signIn``,
/// ``Telemetry/Name/arrival``, ``Telemetry/Name/snapshotShown``, ``Telemetry/Name/reconnect``): the app delegate and the first
/// frame, the Sign In button and the end of the arrival animation. They go through ``Telemetry/begin(_:page:_:)`` and
/// ``Telemetry/end(_:value:detail:)``, so they are signposts in `com.sfenton.home` / `Performance` for `XCTOSSignpostMetric`
/// and records in the in-app log; this only remembers which are open, by name. Beginning one that is open, or ending one that
/// is not, does nothing.
final class TrackedIntervals: Sendable {
    private let open = OSAllocatedUnfairLock<[String: Telemetry.Interval]>(initialState: [:])
    private let finish: @Sendable (Telemetry.Interval) -> Double

    /// - Parameter finish: Ends an interval and returns its length; the app's is ``Telemetry/end(_:value:detail:)``, which
    ///   records in the shared in-app log (tests pass one that does not, so they never disturb other suites' counts).
    init(finish: @escaping @Sendable (Telemetry.Interval) -> Double = { Telemetry.end($0) }) {
        self.finish = finish
    }

    func begin(_ name: StaticString) {
        open.withLock { open in
            let key = "\(name)"
            guard open[key] == nil else { return }
            open[key] = Telemetry.begin(name)
        }
    }

    @discardableResult
    func end(_ name: StaticString) -> Double? {
        guard let interval = open.withLock({ $0.removeValue(forKey: "\(name)") }) else { return nil }
        return finish(interval)
    }

    /// Closes the signpost without a log record: what it timed was abandoned.
    func cancel(_ name: StaticString) {
        guard let interval = open.withLock({ $0.removeValue(forKey: "\(name)") }) else { return }
        Telemetry.signposter.endInterval(interval.name, interval.state, "cancelled")
    }

    func isOpen(_ name: StaticString) -> Bool { open.withLock { $0["\(name)"] != nil } }
}

public extension Telemetry {
    private static let tracked = TrackedIntervals()

    /// Starts a named interval that another place ends. Does nothing when it is already open.
    static func beginTracked(_ name: StaticString) { tracked.begin(name) }

    /// Ends a named interval and records it.
    /// - Returns: Its length in milliseconds, or nil when it was not open.
    @discardableResult
    static func endTracked(_ name: StaticString) -> Double? { tracked.end(name) }

    /// Ends a named interval without recording it (a reconnect cut short by going to the background).
    static func cancelTracked(_ name: StaticString) { tracked.cancel(name) }

    /// Whether the named interval has begun and not yet ended.
    static func isTracked(_ name: StaticString) -> Bool { tracked.isOpen(name) }
}
