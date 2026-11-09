import Foundation

/// Ignores the first state a newly added region reports, as the official app does (`ignoreNextState`): adding a
/// region evaluates it at once, and that answer describes where the phone already is, not a crossing. The
/// launch update reports the position.
///
/// Core Location's monitor only reports a condition added "assuming unsatisfied" when it is in fact satisfied,
/// so a flag that waited for the next event would swallow a real crossing much later. The state is therefore
/// ignored only when it arrives within ``window`` of the add.
public struct NewRegionGuard: Sendable {
    /// How long after an add the first state counts as the initial evaluation, in seconds.
    public static let window: TimeInterval = 10

    private var addedAt: [String: Date] = [:]

    /// Creates a guard with nothing added.
    public init() {}

    /// Records that `regionID` was just added.
    public mutating func added(_ regionID: String, at date: Date) {
        addedAt[regionID] = date
    }

    /// Whether a state reported for `regionID` at `date` is the initial evaluation of a region added moments ago.
    /// The first state after an add is consumed; later ones always pass.
    public mutating func isInitialState(_ regionID: String, at date: Date) -> Bool {
        guard let added = addedAt.removeValue(forKey: regionID) else { return false }
        return date.timeIntervalSince(added) <= Self.window
    }
}
