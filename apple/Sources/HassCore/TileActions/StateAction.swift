import Foundation

/// What the disc does in one state of a ``StateStyle``: its words, its glyph and the service it runs. A data value, so the Studio can
/// author it; the call is `domain.service` on the bound entity, the domain coming from the style.
public struct StateAction: Equatable, Sendable {
    /// The same action when the entity lacks the feature in ``requiresFeature``: Reverse where Stop is not supported.
    public struct Alternative: Equatable, Sendable {
        /// The VoiceOver verb.
        public var verb: String
        /// The disc glyph.
        public var symbol: String
        /// The service, or nil for none.
        public var service: String?

        /// Creates an alternative.
        public init(verb: String, symbol: String, service: String?) {
            self.verb = verb
            self.symbol = symbol
            self.service = service
        }
    }

    /// The VoiceOver verb: "Open", "Stop", "Disarm".
    public var verb: String
    /// The disc glyph.
    public var symbol: String
    /// The service on the style's domain, or nil when the state has none to send.
    public var service: String?
    /// Asked before the call runs.
    public var confirmation: TileActionSpec.Confirmation?
    /// A `supported_features` bit the entity must report for this action (Stop is 8).
    public var requiresFeature: Int?
    /// Used when ``requiresFeature`` is missing; nil makes the state offer no action, so its arc shows.
    public var otherwise: Alternative?
    /// Whether a tap runs the action now. False keeps the verb and call (VoiceOver and the request) but the tap is ignored, as a
    /// moving lock's is.
    public var isTappable: Bool

    /// Creates an action.
    public init(verb: String, symbol: String, service: String?, confirmation: TileActionSpec.Confirmation? = nil,
                requiresFeature: Int? = nil, otherwise: Alternative? = nil, isTappable: Bool = true) {
        self.verb = verb
        self.symbol = symbol
        self.service = service
        self.confirmation = confirmation
        self.requiresFeature = requiresFeature
        self.otherwise = otherwise
        self.isTappable = isTappable
    }
}
