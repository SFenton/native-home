import Foundation

/// What a ``StateStyle`` makes of one entity state: the four layers of the look and the disc's action
/// (`.agents/design/state-styled-tile.md`, Layers).
public struct StateResolution: Equatable, Sendable {
    /// The disc as it resolved for this state.
    public struct Action: Equatable, Sendable {
        /// The VoiceOver verb.
        public var verb: String
        /// The disc glyph.
        public var symbol: String
        /// The call a tap runs; nil when the state has none.
        public var call: ServiceCall?
        /// Asked before the call runs.
        public var confirmation: TileActionSpec.Confirmation?
        /// Whether a tap runs the call now.
        public var isTappable: Bool
    }

    /// The class of the state.
    public var stateClass: StateClass
    /// Lit face or unlit.
    public var isActive: Bool
    /// The icon layer: the disc's glyph (the action's, or the rule's when the state has none).
    public var glyph: String
    /// The text layer.
    public var words: String
    /// The indicator layer. A state whose tap does something resolves to ``StateIndicator/none``: its disc stays, so no arc.
    public var indicator: StateIndicator
    /// The disc's action, if the state has one.
    public var action: Action?
    /// Whether the state's rule or action gave a glyph. False means ``glyph`` is a placeholder and the tile keeps its own icon.
    public var hasGlyph: Bool = false
    /// The colour layer's palette token when the rule names one; nil is the face the class and ``isActive`` pick.
    public var colour: StateColour? = nil
    /// The face fill of the state's rule (`red << 16 | green << 8 | blue`); nil is the face the class picks.
    public var fill: UInt32? = nil
    /// The face fill while the screen is dark, when the rule's fill is a light and dark pair; nil is ``fill`` in both.
    public var fillDark: UInt32? = nil
}
