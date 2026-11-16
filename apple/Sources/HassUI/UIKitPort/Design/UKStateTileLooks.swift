#if os(iOS)
import HassCore
import HassDesign

/// Maps what a ``StateStyle`` resolved, and where the request stands, onto the four layers a tile draws (``StateTileLook``).
///
/// The style classes the state; the request decides the rest: a call in flight makes the tile in-progress from the same frame, a failed
/// request is an error, and an entity that cannot be reached, a screenshot or a first load is the unknown class, which keeps a dimmed disc
/// and never an arc.
enum UKStateTileLooks {
    /// Where the request stands, which the style cannot know.
    struct Request {
        /// The disc takes no tap now (the call is in flight, or the lockout has not ended).
        var isInFlight = false
        /// The request failed.
        var failed = false
        /// The entity is unavailable, or its values have not arrived, or the screen is redacted: the unknown class.
        var isUnknown = false
    }

    /// The look for `resolution`.
    /// - Parameters:
    ///   - resolution: What the style made of the live state.
    ///   - request: Where the request stands.
    ///   - icon: The icon layer: the glyph the tile's document gives the state.
    ///   - text: The text layer: the state's words, or the pending or error words.
    ///   - isActive: Whether the face is lit.
    ///   - hasDisc: Whether the tile draws an action disc at all; a tile with no disc shows the arc in its glyph's place.
    static func look(_ resolution: StateResolution, request: Request, icon: String, text: String, isActive: Bool, hasDisc: Bool = true) -> StateTileLook {
        let look = classLook(resolution, request: request, icon: icon, text: text, isActive: isActive, hasDisc: hasDisc)
        // A token is cosmetic: it sets the lit or unlit face of a resting or in-progress look and nothing else. Unknown, a failed request,
        // warning and error keep the face of their class, and the class is never changed.
        guard let token = resolution.colour, look.stateClass == .resting || look.stateClass == .inProgress else { return look }
        var coloured = look
        coloured.colour = .init(look.stateClass, active: token == .lit)
        return coloured
    }

    private static func classLook(_ resolution: StateResolution, request: Request, icon: String, text: String, isActive: Bool, hasDisc: Bool) -> StateTileLook {
        let stateClass: StateClass = request.isUnknown ? .unknown : request.failed ? .error : request.isInFlight ? .inProgress : resolution.stateClass
        let takesTap = hasDisc && !request.isInFlight && !request.isUnknown && (resolution.action?.isTappable ?? false)
        var indicator = stateClass == resolution.stateClass && !request.isInFlight ? resolution.indicator
            : StateStyle.defaultIndicator(stateClass, hasAction: takesTap)
        if stateClass == .inProgress, !takesTap { indicator = .arcSpinner }
        if stateClass == .inProgress, takesTap, indicator == .arcSpinner { indicator = .none }
        return StateTileLook(icon: icon, colour: .init(map(stateClass), active: isActive), stateClass: map(stateClass), indicator: map(indicator), text: text, hasAction: takesTap)
    }

    /// ``StateClass`` as the design layer's class.
    static func map(_ stateClass: StateClass) -> StateTileLook.Class {
        switch stateClass {
        case .resting: .resting
        case .inProgress: .inProgress
        case .warning: .warning
        case .error: .error
        case .unknown: .unknown
        }
    }

    /// ``StateIndicator`` as the design layer's indicator.
    static func map(_ indicator: StateIndicator) -> StateTileLook.Indicator {
        switch indicator {
        case .none: .none
        case .arcSpinner: .arc
        case .pulse: .pulse
        case .breathe: .breathe
        case .bounce: .bounce
        case .wiggle: .wiggle
        }
    }
}
#endif
