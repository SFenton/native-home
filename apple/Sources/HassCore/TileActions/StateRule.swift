import Foundation

/// One rule of a state map: the states it matches and the look and action they get. Rules are tried in order and the first match wins.
public struct StateRule: Equatable, Sendable {
    /// The Home Assistant states this rule matches; empty matches every state (the fallback rule).
    public var states: [String]
    /// The class.
    public var stateClass: StateClass
    /// Lit face (true) or unlit.
    public var isActive: Bool
    /// The face glyph for a state with no action; a state with an action shows the action's glyph.
    public var glyph: String?
    /// The state text; nil is Home Assistant's own name for the state, title-cased.
    public var words: String?
    /// Overrides the class's default indicator.
    public var indicator: StateIndicator?
    /// What the disc does; nil is a state with no action.
    public var action: StateAction?
    /// Overrides the face the class and ``isActive`` pick with a palette token.
    public var colour: StateColour?

    /// The face colour of this state as `red << 16 | green << 8 | blue`, which replaces the class face while the state shows
    /// (`sh.state-style-fills@1`); nil draws the class face.
    public var fill: UInt32?
    /// The face colour while the screen is dark, when the rule's fill is a light and dark pair (`sh.solid-appearance@1`); nil is ``fill``
    /// in both appearances.
    public var fillDark: UInt32?
    /// The icon colour of this state as `red << 16 | green << 8 | blue` (`sh.state-style-glyph-tint@1`), drawn where the tile's static
    /// `glyphTint` draws; nil leaves the tile's own tint, then the default ink.
    public var glyphTint: UInt32?
    /// The icon colour while the screen is dark, when the rule's tint is a light and dark pair; nil is ``glyphTint`` in both appearances.
    public var glyphTintDark: UInt32?
    /// The ink of the state line on ``fill`` (`sh.tile-ink@1`); nil is the document not naming one, which draws ``StateFillInk/white``.
    public var fillInk: StateFillInk?
    /// Whether the disc reads as on in this state, when that differs from the tile's own ``isActive``. Never authored: a lowered
    /// `door-tile` sets it where its tile was lit and its disc was not.
    public var discOn: Bool?
    /// The colour of the disc's glyph (`red << 16 | green << 8 | blue`) while the face is unlit, in the place of the face fill the state does
    /// not draw. Never authored: a lowered `door-tile` sets it from the state's authored colour, which is the face when the state is active
    /// and the glyph ink when it is not. nil leaves the disc's own ink.
    public var discGlyph: UInt32?

    /// Creates a rule.
    public init(_ states: [String], _ stateClass: StateClass, active: Bool = false, glyph: String? = nil, words: String? = nil,
                indicator: StateIndicator? = nil, action: StateAction? = nil, colour: StateColour? = nil,
                fill: UInt32? = nil, discOn: Bool? = nil, discGlyph: UInt32? = nil) {
        self.fill = fill
        self.discGlyph = discGlyph
        self.discOn = discOn
        self.states = states
        self.stateClass = stateClass
        self.isActive = active
        self.glyph = glyph
        self.words = words
        self.indicator = indicator
        self.action = action
        self.colour = colour
    }

    /// Whether the rule matches `state`.
    public func matches(_ state: String?) -> Bool { states.isEmpty || state.map(states.contains) == true }
}
