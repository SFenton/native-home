import Foundation

/// Drops fixes not worth sending, so a busy hour of significant changes doesn't flood Home Assistant.
///
/// Fixes arrive already graded by ``OneShotFix`` (nothing invalid, nothing older than ten minutes), so accuracy is
/// not judged here.
/// - Invalid fixes are always dropped.
/// - A fix older than the last one admitted is out of order and dropped.
/// - A fix older than ``maximumAge`` relative to the clock is a cached reading and dropped, unless the person asked
///   for it (``LocationTrigger/manual``).
/// - A fix within 10 m and 30 s of the last one sent is a duplicate and dropped, unless the trigger is manual or a
///   zone crossing (which is always news).
public struct LocationFixFilter: Sendable {
    /// The oldest a non-manual fix may be, in seconds: the one-shot grade's invalid age.
    public static let maximumAge: TimeInterval = OneShotFix.invalidAge
    /// Fixes closer together in time than this may be duplicates.
    public static let duplicateInterval: TimeInterval = 30
    /// Fixes closer together than this, within ``duplicateInterval``, are duplicates.
    public static let duplicateDistance: Double = 10

    /// The last fix let through.
    public private(set) var lastAdmitted: LocationFix?

    /// Creates a filter with no history.
    public init() {}

    /// Whether to send `fix`; a fix let through becomes the reference for the next duplicate check.
    /// - Parameters:
    ///   - fix: The reading.
    ///   - trigger: Why it was taken.
    ///   - now: The clock.
    public mutating func admit(_ fix: LocationFix, trigger: LocationTrigger, now: Date = .now) -> Bool {
        guard fix.isValid else { return false }
        if let last = lastAdmitted, fix.timestamp < last.timestamp { return false }
        if trigger != .manual, now.timeIntervalSince(fix.timestamp) > Self.maximumAge { return false }
        if !trigger.isZoneEvent, trigger != .manual, let last = lastAdmitted,
           abs(fix.timestamp.timeIntervalSince(last.timestamp)) < Self.duplicateInterval,
           fix.distance(to: last) < Self.duplicateDistance {
            return false
        }
        lastAdmitted = fix
        return true
    }

    /// Forgets the history (sign-out, or a new registration).
    public mutating func reset() {
        lastAdmitted = nil
    }
}
