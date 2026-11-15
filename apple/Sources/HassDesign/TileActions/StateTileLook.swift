import Foundation

// MARK: - Look

/// The four resolved layers of a state-styled tile as values: **icon**, **colour**, **indicator** and **text**
/// (`.agents/design/state-styled-tile.md`, Layers). HassDesign does not depend on HassCore, so the style's resolution is mapped onto this in
/// HassUI. On every change each layer's value is compared with the one on screen (``changes(to:)``); an unchanged layer is not touched.
public struct StateTileLook: Equatable, Sendable {
    /// The class of the state: what it means, not how it is drawn.
    public enum Class: String, Equatable, Sendable {
        /// Settled.
        case resting
        /// Transitional: it ends without another tap.
        case inProgress
        /// Needs attention, nothing has failed.
        case warning
        /// Failed, jammed, triggered, detected.
        case error
        /// Unavailable or unknown: a dimmed disc, taps ignored, never an arc.
        case unknown
    }

    /// The indicator layer. Closed list.
    public enum Indicator: String, Equatable, Sendable {
        /// Nothing plays.
        case none
        /// The arc stands in the disc's place while a tap does nothing.
        case arc
        /// A pulse while the state holds.
        case pulse
        /// A breathe while the state holds.
        case breathe
        /// One bounce on arrival.
        case bounce
        /// One wiggle on arrival.
        case wiggle

        /// Whether the indicator is a symbol effect on the glyph, as opposed to the arc view or nothing.
        public var isSymbolEffect: Bool { self != .none && self != .arc }
        /// Whether the effect plays once, on arrival.
        public var playsOnce: Bool { self == .bounce || self == .wiggle }
    }

    /// The colour layer: the face and ink are palette tokens picked by the class and whether the face is lit. It is only the face; what
    /// the state means is ``StateTileLook/stateClass``.
    public struct Colour: Equatable, Sendable {
        /// The class the face is drawn for: the warning and error faces are dense with their own ink.
        public var stateClass: Class
        /// Lit face or unlit.
        public var isActive: Bool

        /// Creates the colour layer.
        public init(_ stateClass: Class, active: Bool) {
            self.stateClass = stateClass
            self.isActive = active
        }
    }

    /// The icon layer: an SF Symbol name.
    public var icon: String
    /// The class of the state: what it means. Every reader of the class (the spoken value, the announcement, the error haptic, the flap
    /// guard, the warning replay, the disc and the taps) reads this, never ``colour``, so a colour token changes only the face.
    public var stateClass: Class
    /// The colour layer: the face only.
    public var colour: Colour
    /// The indicator layer. It is ``Indicator/none`` or an effect, never ``Indicator/arc``, when the state has an action.
    public var indicator: Indicator
    /// The text layer: the state's words.
    public var text: String
    /// Whether the state has an action, so its disc takes a tap.
    public var hasAction: Bool

    /// Creates a look. An arc is dropped for a state that has an action: its disc stays and its words carry the progress.
    /// - Parameter stateClass: The meaning of the state; absent, the class the face is drawn for.
    public init(icon: String, colour: Colour, stateClass: Class? = nil, indicator: Indicator = .none, text: String, hasAction: Bool) {
        self.icon = icon
        self.stateClass = stateClass ?? colour.stateClass
        self.colour = colour
        self.indicator = hasAction && indicator == .arc ? .none : indicator
        self.text = text
        self.hasAction = hasAction
    }

    /// Whether the arc stands in the disc's place: the disc's fill and glyph are at zero opacity, it draws no press state and ignores taps.
    public var showsArc: Bool { indicator == .arc }

    /// The disc's opacity: zero while the arc stands in, a dimmed 0.5 for the unknown class, else 1.
    public var discOpacity: Double {
        if showsArc { 0 } else if stateClass == .unknown { 0.5 } else { 1 }
    }

    /// Whether a tap on the disc or the body does something now. False while the arc shows and for the unknown class.
    public var acceptsTaps: Bool { !showsArc && stateClass != .unknown }
}
