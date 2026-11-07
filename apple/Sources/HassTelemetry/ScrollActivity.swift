import Foundation

/// When the user last scrolled anything, for work that should not interrupt a scroll (switching the websocket to the home
/// network address, `HassConnection`).
///
/// It lives in `HassTelemetry` because both `HassCore` (which asks) and `HassDesign`/`HassUI` (which report) import it. Reporting is
/// called per scroll frame, so ``noteScroll()`` only stores a timestamp: no SwiftUI state, no allocation. Pages that know their
/// scroll phase also call ``begin(page:)`` and ``end(page:)``, so a slow drag between frames still counts as scrolling.
@MainActor
public final class ScrollActivity {
    /// The one the app reports into.
    public static let shared = ScrollActivity()

    private let clock: () -> TimeInterval
    private var last: TimeInterval?
    private var activePages: Set<String> = []

    /// - Parameter clock: Seconds on a monotonic clock; tests pass their own.
    public init(clock: @escaping () -> TimeInterval = ScrollActivity.monotonicSeconds) {
        self.clock = clock
    }

    nonisolated private static let origin = ContinuousClock.now

    /// Seconds since this type was first used, on `ContinuousClock`. Not `ProcessInfo.systemUptime`, a required-reason
    /// API (`.agents/platforms/apple/testflight.md`, Required-reason APIs) that every bundle linking this module would
    /// then have to declare.
    nonisolated public static func monotonicSeconds() -> TimeInterval {
        let elapsed = ContinuousClock.now - origin
        return TimeInterval(elapsed.components.seconds) + TimeInterval(elapsed.components.attoseconds) * 1e-18
    }

    /// A scroll view moved this frame. Cheap: one timestamp.
    public func noteScroll() { last = clock() }

    /// A page's scroll started (finger down or momentum).
    public func begin(page: String) {
        activePages.insert(page)
        noteScroll()
    }

    /// A page's scroll came to rest or the page went away.
    public func end(page: String) {
        if activePages.remove(page) != nil { noteScroll() }
    }

    /// How long nothing has scrolled; zero while a page is mid-scroll, infinite if nothing ever scrolled.
    public var idleDuration: TimeInterval {
        if !activePages.isEmpty { return 0 }
        guard let last else { return .infinity }
        return max(0, clock() - last)
    }
}
