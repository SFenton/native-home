import Foundation

/// What a state of a binding means to the person, in one of five classes (`.agents/design/state-styled-tile.md`, Classes).
///
/// ``active`` is separate: it only picks the lit or the unlit face, so open and closed are both ``resting``.
public enum StateClass: String, Equatable, Sendable, CaseIterable {
    /// Settled. Includes active work: cleaning, playing, heating.
    case resting
    /// Transitional: it ends without another tap.
    case inProgress = "in-progress"
    /// Needs attention, nothing has failed.
    case warning
    /// Failed, jammed, triggered, detected.
    case error
    /// `unavailable`, `unknown`, or no rule matched: the face dims and taps are ignored, and never an arc.
    case unknown
}
