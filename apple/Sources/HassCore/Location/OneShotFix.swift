import Foundation

/// How good a one-shot reading is, graded as the official Home Assistant app grades it
/// (`home-assistant/iOS` `PotentialLocation`, `.agents/platforms/apple/location.md`).
public enum FixGrade: Sendable, Equatable {
    /// Unusable: no real coordinate, older than ``OneShotFix/invalidAge``, or less accurate than the threshold.
    case invalid
    /// Usable if nothing better arrives before the timeout.
    case meh
    /// Accurate (within ``OneShotFix/perfectAccuracy``) and recent (within ``OneShotFix/perfectAge``): returned at once.
    case perfect
}

/// The rules for one-shot fixes: grading, choosing among readings, and how long each trigger may wait.
///
/// Core Location hands out cached readings, and a cached "309 m" reading re-sent for two hours was one of the
/// things wrong with the departures of 2026-10-29. A one-shot request starts updates at the best accuracy and also
/// considers the cached reading, then grades everything: a perfect reading answers at once, an invalid one is never
/// used, and at the timeout the best of the rest is taken.
public enum OneShotFix {
    /// A reading this accurate (meters) and this recent counts as perfect.
    public static let perfectAccuracy: Double = 100
    /// A reading this recent (seconds) and accurate counts as perfect.
    public static let perfectAge: TimeInterval = 30
    /// A reading older than this (seconds) is invalid.
    public static let invalidAge: TimeInterval = 600
    /// A reading less accurate than this (meters) is invalid (Precise Location on).
    public static let invalidAccuracy: Double = 1500
    /// With Approximate Location the perfect accuracy is this instead, and accuracy never makes a reading invalid.
    public static let reducedPerfectAccuracy: Double = 3000
    /// Among meh readings, one this much newer (seconds) than another wins whatever its accuracy.
    public static let preferNewerBy: TimeInterval = 60
    /// A significant-change reading older than this (seconds) is a cached one and the change is ignored.
    public static let significantChangeMaxAge: TimeInterval = 180
    /// A significant change within this long (seconds) of a successful update is ignored.
    public static let significantChangeCooldown: TimeInterval = 30
    /// Seconds kept in reserve when the wait is capped by the background time left.
    public static let backgroundReserve: TimeInterval = 5

    /// Grades `fix` as of `now`.
    /// - Parameters:
    ///   - fix: The reading.
    ///   - now: The clock.
    ///   - reduced: Whether Approximate Location is on (wider thresholds).
    public static func grade(_ fix: LocationFix, now: Date, reduced: Bool = false) -> FixGrade {
        guard fix.isValid, !isNearZero(fix.latitude), !isNearZero(fix.longitude) else { return .invalid }
        let age = now.timeIntervalSince(fix.timestamp)
        if fix.horizontalAccuracy <= (reduced ? reducedPerfectAccuracy : perfectAccuracy), age <= perfectAge {
            return .perfect
        }
        if (!reduced && fix.horizontalAccuracy > invalidAccuracy) || age > invalidAge { return .invalid }
        return .meh
    }

    /// A zero (or denormal) coordinate is what Core Location sometimes reports instead of a position.
    private static func isNearZero(_ value: Double) -> Bool { abs(value) <= 0.000_000_001 }

    /// The longest any wait sleeps (seconds), however much background time is reported.
    public static let longestWait: TimeInterval = 60

    /// How long a wait may last given the background time left: `max(remaining - 5, 1)`, never more than `maximum`.
    /// Safe for any input: infinity, `DBL_MAX` (what iOS reports with no limit), NaN and negative values all give a
    /// finite number of seconds that `Duration` can hold.
    public static func waitLimit(backgroundRemaining: TimeInterval, maximum: TimeInterval = longestWait) -> TimeInterval {
        let ceiling = min(max(maximum, 1), longestWait)
        guard !backgroundRemaining.isNaN else { return ceiling }
        return min(ceiling, max(backgroundRemaining - backgroundReserve, 1))
    }

    /// How long to wait for a fix caused by `trigger`, in seconds: a region crossing 20, significant change, push
    /// and background fetch 10, launch and manual 30.
    /// - Parameters:
    ///   - trigger: Why the fix is wanted.
    ///   - backgroundRemaining: The background time left; the wait never exceeds `max(remaining - 5, 1)`.
    public static func timeout(for trigger: LocationTrigger, backgroundRemaining: TimeInterval = .infinity) -> TimeInterval {
        let base: TimeInterval = switch trigger {
        case .regionEntered, .regionExited: 20
        case .significantLocationChange, .backgroundFetch, .pushNotification: 10
        case .launch, .manual: 30
        }
        return waitLimit(backgroundRemaining: backgroundRemaining, maximum: base)
    }
}

/// The readings one request has seen, and what to do with them.
public struct OneShotSelector: Sendable {
    /// What the request should do next.
    public enum Verdict: Equatable, Sendable {
        /// Answer with this reading.
        case done(LocationFix)
        /// Keep waiting.
        case wait
        /// Nothing usable and out of time.
        case fail
    }

    private struct Candidate: Sendable {
        let fix: LocationFix
        let grade: FixGrade
    }

    private var candidates: [Candidate] = []
    /// Whether Approximate Location is on; set once known, as it is read off the main thread.
    public var reduced: Bool
    /// Readings taken before this are never considered, however accurate: for a region exit, a cached reading
    /// from before the crossing would still say the phone is inside the zone.
    public let notBefore: Date?

    /// Creates a selector.
    /// - Parameters:
    ///   - reduced: Whether Approximate Location is on.
    ///   - notBefore: The earliest acceptable reading time, if any.
    public init(reduced: Bool = false, notBefore: Date? = nil) {
        self.reduced = reduced
        self.notBefore = notBefore
    }

    /// Considers a reading (the cached one, or a delivered one), graded as of `now`; one taken before
    /// ``notBefore`` is ignored.
    public mutating func add(_ fix: LocationFix, now: Date) {
        if let notBefore, fix.timestamp < notBefore { return }
        candidates.append(Candidate(fix: fix, grade: OneShotFix.grade(fix, now: now, reduced: reduced)))
    }

    /// The answer so far. A perfect reading ends the wait; at the timeout the best meh reading does; an invalid
    /// one never does.
    /// - Parameter outOfTime: Whether the timeout has passed (or Core Location gave up).
    public func verdict(outOfTime: Bool) -> Verdict {
        var best: Candidate?
        for next in candidates where best.map({ Self.isBetter(next, than: $0) }) ?? true { best = next }
        guard let best else { return outOfTime ? .fail : .wait }
        switch best.grade {
        case .perfect: return .done(best.fix)
        case .meh: return outOfTime ? .done(best.fix) : .wait
        case .invalid: return outOfTime ? .fail : .wait
        }
    }

    private static func isBetter(_ lhs: Candidate, than rhs: Candidate) -> Bool {
        func rank(_ grade: FixGrade) -> Int { grade == .perfect ? 2 : grade == .meh ? 1 : 0 }
        if rank(lhs.grade) != rank(rhs.grade) { return rank(lhs.grade) > rank(rhs.grade) }
        switch lhs.grade {
        case .perfect: return lhs.fix.timestamp > rhs.fix.timestamp
        case .invalid: return false
        case .meh:
            let gap = lhs.fix.timestamp.timeIntervalSince(rhs.fix.timestamp)
            if abs(gap) > OneShotFix.preferNewerBy { return gap > 0 }
            return lhs.fix.horizontalAccuracy < rhs.fix.horizontalAccuracy
        }
    }
}
