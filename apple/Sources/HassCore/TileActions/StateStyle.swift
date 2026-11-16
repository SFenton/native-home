import Foundation
import HassTelemetry
import os

// MARK: - Style

/// A named state map, the look per state and the request settings: the one definition behind the door, lock, blind, alarm, robot,
/// detector, notice and switch tiles (`.agents/design/state-styles.md`). Values only, so the Studio can author one; tiles apply it by id.
///
/// ``resolve(_:entityId:)`` turns an entity state into the four layers of the look and the disc's action; ``spec(for:entityId:requestInFlight:)``
/// gives the action as the ``TileActionSpec`` the disc runs. The built-in styles are in `StateStyle+BuiltIn`.
public struct StateStyle: Equatable, Sendable, Identifiable {
    /// The id tiles apply it by: `garage-door`, `lock`, `alarm`.
    public var id: String
    /// The name the Studio lists.
    public var name: String
    /// The service domain the actions call: `cover`, `lock`, `alarm_control_panel`.
    public var domain: String
    /// The id of the disc's action in every state, so one disc keeps its identity and its glyph replaces itself.
    public var actionId: String
    /// The rules, tried in order. The last is the fallback: it matches every state.
    public private(set) var rules: [StateRule]
    /// The request phase, when the style authors one.
    public var request: StateRequest?
    /// The disc reports on or off (a door, a lock); an alarm's disc does not.
    public var togglesDisc: Bool
    /// An error state draws its disc glyph in the error ink (a jammed lock).
    public var drawsErrorDisc: Bool
    /// The words the text layer shows while the screen is redacted (`sh.state-style-fills@1`); nil shows the unknown state's own.
    public var hiddenWords: String?
    /// Whether the disc stays, dimmed, while the entity cannot be read. A lowered `door-tile` keeps the dimmed disc it always drew;
    /// never authored.
    public var keepsDiscWhenUnknown: Bool

    /// Creates a style. A map that names no `unavailable` or `unknown` state gets a rule for them: the unknown class with an untappable
    /// copy of the map's first action, so an unavailable entity never reads as resting or offers a tap. A map that does not end with a
    /// fallback gets one: a copy of its unknown rule.
    public init(id: String, name: String, domain: String, actionId: String, rules: [StateRule], request: StateRequest? = nil,
                togglesDisc: Bool = false, drawsErrorDisc: Bool = false, hiddenWords: String? = nil,
                keepsDiscWhenUnknown: Bool = false) {
        self.hiddenWords = hiddenWords
        self.keepsDiscWhenUnknown = keepsDiscWhenUnknown
        self.id = id
        self.name = name
        self.domain = domain
        self.actionId = actionId
        var rules = rules
        if !rules.contains(where: { $0.stateClass == .unknown && !$0.states.isEmpty }) {
            // An action only where the map has one: a display-only tile gains no disc.
            let action = rules.lazy.compactMap(\.action).first.map {
                StateAction(verb: $0.verb, symbol: $0.symbol, service: nil, isTappable: false)
            }
            let unknown = StateRule(["unavailable", "unknown"], .unknown, action: action)
            if rules.last?.states.isEmpty == true { rules.insert(unknown, at: rules.count - 1) } else { rules.append(unknown) }
        }
        if rules.last?.states.isEmpty == true {
            self.rules = rules
        } else {
            // The fallback takes the look and the action of the map's own unknown rule, so a state no rule names reads like `unknown`.
            var fallback = rules.first { $0.stateClass == .unknown } ?? StateRule([], .unknown)
            fallback.states = []
            self.rules = rules + [fallback]
        }
        self.request = request
        self.togglesDisc = togglesDisc
        self.drawsErrorDisc = drawsErrorDisc
    }

    /// A copy with `rules` in place of this style's, for the authored overrides that split a state off its rule.
    func replacingRules(_ rules: [StateRule]) -> StateStyle {
        StateStyle(id: id, name: name, domain: domain, actionId: actionId, rules: rules, request: request,
                   togglesDisc: togglesDisc, drawsErrorDisc: drawsErrorDisc, hiddenWords: hiddenWords,
                   keepsDiscWhenUnknown: keepsDiscWhenUnknown)
    }

    // MARK: Resolving

    /// The first rule that matches `state`; the fallback when none does.
    public func rule(for state: String?) -> StateRule {
        rules.first { $0.matches(state) } ?? rules[rules.count - 1]
    }

    /// The four layers and the action for `state`. A missing or unavailable entity is the unknown class whatever the map says, and
    /// every map has an unknown rule (see ``init(id:name:domain:actionId:rules:request:togglesDisc:drawsErrorDisc:)``). A state a
    /// built-in style does not list falls to its fallback and is reported once, so a state Home Assistant adds is noticed.
    public func resolve(_ state: EntityState?, entityId: String) -> StateResolution {
        let value = state?.state
        let rule = EntityState.isUnavailable(value) ? unknownRule : self.rule(for: value)
        if let value, !EntityState.isUnavailable(value), rule.states.isEmpty, Self.builtIn(id: id) == self {
            Self.reportUnlisted(value, style: id)
        }
        let supported = Self.features(state)
        var action: StateResolution.Action?
        if let authored = rule.action {
            var verb = authored.verb, symbol = authored.symbol, service = authored.service
            var offered = true
            if let bit = authored.requiresFeature, supported & bit == 0 {
                if let other = authored.otherwise { verb = other.verb; symbol = other.symbol; service = other.service } else { offered = false }
            }
            if offered {
                action = .init(verb: verb, symbol: symbol, call: service.map { ServiceCall(domain, $0, target: entityId) },
                               confirmation: authored.confirmation, isTappable: authored.isTappable)
            }
        }
        let indicator = rule.indicator ?? Self.defaultIndicator(rule.stateClass, hasAction: action?.isTappable == true)
        let authored = action?.symbol ?? rule.glyph
        return StateResolution(stateClass: rule.stateClass, isActive: rule.isActive, glyph: authored ?? "circle",
                               words: rule.words ?? Self.title(value), indicator: indicator, action: action, hasGlyph: authored != nil,
                               colour: rule.colour, fill: rule.fill, fillDark: rule.fillDark,
                               fillInk: rule.fillInk ?? .white, discGlyph: rule.discGlyph)
    }

    /// The disc's spec for `state`, or nil when the state has no action.
    /// - Parameter requestInFlight: A call was just sent and the state has not moved: the disc is in flight whatever the state says.
    public func spec(for state: EntityState?, entityId: String, requestInFlight: Bool = false) -> TileActionSpec? {
        let resolution = resolve(state, entityId: entityId)
        guard let action = resolution.action else { return nil }
        var phase: TileActionSpec.Phase = .ready
        if resolution.stateClass == .unknown { phase = .unavailable }
        else if !action.isTappable || requestInFlight { phase = .inFlight }
        return TileActionSpec(id: actionId, verb: action.verb, symbol: action.symbol, isOn: togglesDisc ? (discOn(for: state) ?? resolution.isActive) : nil,
                              phase: phase, feedback: .tracked, call: action.call,
                              isError: drawsErrorDisc && resolution.stateClass == .error, confirmation: action.confirmation)
    }

    /// The disc's own reading of the state, where the rule overrides the tile's.
    private func discOn(for state: EntityState?) -> Bool? {
        (EntityState.isUnavailable(state?.state) ? unknownRule : rule(for: state?.state)).discOn
    }

    // MARK: Defaults

    private static let reported = OSAllocatedUnfairLock(initialState: Set<String>())

    /// One telemetry event per style and state for the process: the fallback is hit on every render of the tile.
    private static func reportUnlisted(_ state: String, style: String) {
        let key = "\(style):\(state)"
        guard reported.withLock({ $0.insert(key).inserted }) else { return }
        Telemetry.event("statestyle.unlistedState", detail: key)
    }

    private var unknownRule: StateRule { rules.first { $0.stateClass == .unknown && !$0.states.isEmpty } ?? rules[rules.count - 1] }

    /// The class's default indicator: the arc for a transitional state whose tap does nothing, a pulse for a warning and a wiggle for
    /// an error. An in-progress state whose disc still takes a tap resolves to none, and so does a resting or unknown one.
    /// - Parameter hasAction: The state offers an action a tap runs now.
    public static func defaultIndicator(_ stateClass: StateClass, hasAction: Bool) -> StateIndicator {
        switch stateClass {
        case .inProgress: hasAction ? .none : .arcSpinner
        case .warning: .pulse
        case .error: .wiggle
        case .resting, .unknown: .none
        }
    }

    /// Home Assistant's state name as words: `armed_home` reads "Armed Home".
    public static func title(_ state: String?) -> String {
        guard let state, !state.isEmpty else { return "Unavailable" }
        return state.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private static func features(_ state: EntityState?) -> Int {
        state?.attributes["supported_features"]?.number.map { Int($0) } ?? 0
    }
}
