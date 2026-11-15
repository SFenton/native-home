import Foundation

/// The closed list of indicators a state may play (`.agents/design/state-styled-tile.md`, Indicators). Nothing else is authorable:
/// no rotate, variable colour, draw or keyframes.
public enum StateIndicator: String, Equatable, Sendable, CaseIterable {
    /// Nothing plays.
    case none
    /// The arc stands in the disc's place while the state holds. Offered only for a state with no action.
    case arcSpinner = "arc-spinner"
    /// A pulse while the state holds.
    case pulse
    /// A breathe while the state holds; a pulse on iOS 17.
    case breathe
    /// One bounce on arrival.
    case bounce
    /// One wiggle on arrival; a bounce on iOS 17.
    case wiggle

    /// Whether the indicator plays once, on arrival, and never repeats.
    public var playsOnce: Bool { self == .bounce || self == .wiggle }
}
