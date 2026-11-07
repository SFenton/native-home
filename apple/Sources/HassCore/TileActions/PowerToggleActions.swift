import Foundation

/// A power toggle's one action: a PC, a towel rack, a guest-stay toggle or a remote's Power. Explicit `turn_on` /
/// `turn_off` (or the device's own on/off command), never `toggle`.
///
/// | state | verb | symbol | isOn | phase |
/// |---|---|---|---|---|
/// | on | Turn Off | ``symbol`` (default `power`) | true | ready (inFlight for a PC whose status says "Turning…") |
/// | off | Turn On | ``symbol`` | false | ready |
/// | missing, `unavailable`, `unknown` | Turn On | ``symbol`` | false | unavailable |
public struct PowerToggleActions: TileActionProviding {
    /// How the entity's state says it is on.
    public enum OnRule: Equatable, Sendable {
        /// On when the state is `on`.
        case state
        /// On unless the state is one of these (a remote: `off`, `standby`, `unavailable` ...).
        case unless(Set<String>)
    }

    /// The entity whose state is the power state.
    public var entityId: String
    /// The disc's SF Symbol.
    public var symbol: String
    /// Optimistic for towel racks and guest toggles; tracked for a PC and a remote.
    public var feedback: TileActionSpec.Feedback
    /// What the call sets: ``OnRule``.
    public var onRule: OnRule
    /// The call that turns it on.
    public var turnOn: ServiceCall?
    /// The call that turns it off.
    public var turnOff: ServiceCall?
    /// Values shown after turning it on.
    public var optimisticOn: [OptimisticIntent]
    /// Values shown after turning it off.
    public var optimisticOff: [OptimisticIntent]
    /// The device's own status text (a PC's `input_text.<prefix>_power_state`); a "Turning…" status makes the spec in flight.
    public var statusText: String?

    /// Creates a provider from its parts; prefer the factories.
    public init(entityId: String, symbol: String = "power", feedback: TileActionSpec.Feedback, onRule: OnRule = .state,
                turnOn: ServiceCall?, turnOff: ServiceCall?, optimisticOn: [OptimisticIntent] = [],
                optimisticOff: [OptimisticIntent] = [], statusText: String? = nil) {
        self.entityId = entityId
        self.symbol = symbol
        self.feedback = feedback
        self.onRule = onRule
        self.turnOn = turnOn
        self.turnOff = turnOff
        self.optimisticOn = optimisticOn
        self.optimisticOff = optimisticOff
        self.statusText = statusText
    }

    /// The action's id in every state.
    public static let actionId = "power"

    // MARK: - Factories

    /// A switch-like entity (towel rack, guest-stay toggle): explicit `turn_on` / `turn_off` through
    /// ``LightControl/power(_:on:)`` and an optimistic value, like the room flip card.
    public static func entity(_ entityId: String, symbol: String = "power") -> PowerToggleActions {
        func call(_ on: Bool) -> ServiceCall {
            let command = LightControl.power(entityId, on: on)
            return ServiceCall(command.domain, command.service, target: entityId)
        }
        return PowerToggleActions(
            entityId: entityId, symbol: symbol, feedback: .optimistic, turnOn: call(true), turnOff: call(false),
            optimisticOn: [OptimisticIntent(entityId, value: "on")], optimisticOff: [OptimisticIntent(entityId, value: "off")]
        )
    }

    /// A PC (`input_boolean.<prefix>_power`): presses `input_button.<prefix>_on` / `_off`, tracked through the PC's own
    /// status text ("Turning On…").
    public static func pc(prefix: String, symbol: String = "power", statusText: String? = nil) -> PowerToggleActions {
        PowerToggleActions(
            entityId: "input_boolean.\(prefix)_power", symbol: symbol, feedback: .tracked,
            turnOn: ServiceCall("input_button", "press", target: "input_button.\(prefix)_on"),
            turnOff: ServiceCall("input_button", "press", target: "input_button.\(prefix)_off"), statusText: statusText
        )
    }

    /// A media remote's Power button on its control entity, with the button's own command and off states. Optimistic
    /// when the command declares values, else tracked.
    public static func remote(_ config: MediaRemoteConfig, symbol: String = "power") -> PowerToggleActions {
        let off = Set(config.power.iconColorRule?.inactiveStates ?? MediaRemotes.deviceOffStates)
        func command(state: String) -> (ServiceCall?, [OptimisticIntent]) {
            guard case let .service(call, intents) = config.power.action.resolve(entityId: config.controlEntityId, stateOverride: state, displayedState: { _ in state })
            else { return (nil, []) }
            return (call, intents)
        }
        let turnOn = command(state: "off")
        let turnOff = command(state: "on")
        let optimistic = !turnOn.1.isEmpty || !turnOff.1.isEmpty
        return PowerToggleActions(
            entityId: config.controlEntityId, symbol: symbol, feedback: optimistic ? .optimistic : .tracked, onRule: .unless(off),
            turnOn: turnOn.0, turnOff: turnOff.0, optimisticOn: turnOn.1, optimisticOff: turnOff.1
        )
    }

    // MARK: - Provider

    /// Whether `state` reads on under ``onRule``.
    public func isOn(_ state: String?) -> Bool {
        guard let state, !EntityState.isUnavailable(state) else { return false }
        switch onRule {
        case .state: return state == "on"
        case let .unless(off): return !off.contains(state)
        }
    }

    public func actions(for state: EntityState?) -> [TileActionSpec] {
        let on = isOn(state?.state)
        let unavailable = EntityState.isUnavailable(state?.state)
        let turning = statusText.map { $0.hasPrefix("Turning") } ?? false
        let phase: TileActionSpec.Phase = unavailable ? .unavailable : (feedback == .tracked && turning ? .inFlight : .ready)
        return [TileActionSpec(
            id: Self.actionId, verb: on ? "Turn Off" : "Turn On", symbol: symbol, isOn: on, phase: phase, feedback: feedback,
            call: on ? turnOff : turnOn, optimistic: feedback == .optimistic ? (on ? optimisticOff : optimisticOn) : []
        )]
    }

    public var stateTextCandidates: [String] { ["On", "Off", "Turning On…", "Turning Off…", "Unavailable", "Didn't Respond"] }
}
