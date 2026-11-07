import Foundation

// MARK: - Shared coding helpers

extension Duration {
    /// The duration in seconds, the form the document stores (whole seconds in use, so the round trip is exact).
    var houseSeconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    /// A duration from the document's seconds.
    init(houseSeconds seconds: Double) {
        self = .seconds(seconds)
    }
}

/// `SchedulePhase` keys a dictionary in `BedSideConfig`; this makes that dictionary encode as a keyed object
/// (`{"asleep": …, "bedtime": …}`) instead of an unordered alternating array.
extension SchedulePhase: CodingKeyRepresentable {}

// MARK: - Durations as seconds

extension OptimisticIntent {
    private enum Keys: String, CodingKey { case entityId, value, revertAfterSeconds, failsOnTimeout }

    /// Reads an intent; `revertAfterSeconds` is a number of seconds.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(
            try c.decode(String.self, forKey: .entityId), try c.decode(String.self, forKey: .value),
            revertAfter: Duration(houseSeconds: try c.decode(Double.self, forKey: .revertAfterSeconds)),
            failsOnTimeout: try c.decode(Bool.self, forKey: .failsOnTimeout)
        )
    }

    /// Writes an intent with `revertAfterSeconds` as a number of seconds.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(entityId, forKey: .entityId)
        try c.encode(value, forKey: .value)
        try c.encode(revertAfter.houseSeconds, forKey: .revertAfterSeconds)
        try c.encode(failsOnTimeout, forKey: .failsOnTimeout)
    }
}

extension MediaRemoteDevice {
    private enum Keys: String, CodingKey {
        case title, entityId, icon, action, activeHoldSeconds, activeHoldResetEntityIds, activeStates, semantics
        case stateEntityIds, stateLabels, stateResolver
    }

    /// Reads a device tile; `activeHoldSeconds` is a number of seconds.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(
            try c.decode(String.self, forKey: .title), entityId: try c.decode(String.self, forKey: .entityId),
            icon: try c.decode(String.self, forKey: .icon),
            action: try c.decodeIfPresent(MediaRemoteAction.self, forKey: .action),
            activeHold: try c.decodeIfPresent(Double.self, forKey: .activeHoldSeconds).map { Duration(houseSeconds: $0) },
            activeHoldResetEntityIds: try c.decode([String].self, forKey: .activeHoldResetEntityIds),
            activeStates: try c.decode([String].self, forKey: .activeStates),
            semantics: try c.decodeIfPresent(SemanticsRule.self, forKey: .semantics),
            stateEntityIds: try c.decodeIfPresent([String].self, forKey: .stateEntityIds),
            stateLabels: try c.decode([String: String].self, forKey: .stateLabels),
            stateResolver: try c.decodeIfPresent(MediaRemoteStateResolver.self, forKey: .stateResolver)
        )
    }

    /// Writes a device tile with `activeHoldSeconds` as a number of seconds.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(title, forKey: .title)
        try c.encode(entityId, forKey: .entityId)
        try c.encode(icon, forKey: .icon)
        try c.encodeIfPresent(action, forKey: .action)
        try c.encodeIfPresent(activeHold?.houseSeconds, forKey: .activeHoldSeconds)
        try c.encode(activeHoldResetEntityIds, forKey: .activeHoldResetEntityIds)
        try c.encode(activeStates, forKey: .activeStates)
        try c.encodeIfPresent(semantics, forKey: .semantics)
        try c.encodeIfPresent(stateEntityIds, forKey: .stateEntityIds)
        try c.encode(stateLabels, forKey: .stateLabels)
        try c.encodeIfPresent(stateResolver, forKey: .stateResolver)
    }
}

// MARK: - Enums with payloads as tagged objects

// Each writes `{"type": "<case>", …named payload…}` instead of the synthesized `{"case": {"_0": …}}`, so a person
// can read and edit the document. The discriminator names are part of schema 1.

extension SemanticsRule {
    private enum Keys: String, CodingKey { case type, states }

    /// Reads `{"type": "toggleOnUnless" | "toggleOnWhen" | "selectedWhen", "states": […]}` or `{"type": "state"}`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "toggleOnUnless": self = .toggleOnUnless(try c.decode([String].self, forKey: .states))
        case "toggleOnWhen": self = .toggleOnWhen(try c.decode([String].self, forKey: .states))
        case "selectedWhen": self = .selectedWhen(try c.decode([String].self, forKey: .states))
        case "state": self = .state
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown rule")
        }
    }

    /// Writes the tagged form.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .toggleOnUnless(states):
            try c.encode("toggleOnUnless", forKey: .type)
            try c.encode(states, forKey: .states)
        case let .toggleOnWhen(states):
            try c.encode("toggleOnWhen", forKey: .type)
            try c.encode(states, forKey: .states)
        case let .selectedWhen(states):
            try c.encode("selectedWhen", forKey: .type)
            try c.encode(states, forKey: .states)
        case .state:
            try c.encode("state", forKey: .type)
        }
    }
}

extension MediaRemoteCommand {
    private enum Keys: String, CodingKey { case type, call, optimistic, targetEntityId }

    /// Reads `{"type": "service", "call": …, "optimistic": […]}` or `{"type": "textPrompt", "targetEntityId": …}`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "service":
            self = .service(try c.decode(ServiceCall.self, forKey: .call),
                            optimistic: try c.decode([OptimisticIntent].self, forKey: .optimistic))
        case "textPrompt": self = .textPrompt(targetEntityId: try c.decode(String.self, forKey: .targetEntityId))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown command")
        }
    }

    /// Writes the tagged form.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .service(call, optimistic):
            try c.encode("service", forKey: .type)
            try c.encode(call, forKey: .call)
            try c.encode(optimistic, forKey: .optimistic)
        case let .textPrompt(targetEntityId):
            try c.encode("textPrompt", forKey: .type)
            try c.encode(targetEntityId, forKey: .targetEntityId)
        }
    }
}

extension MediaRemoteAction {
    private enum Keys: String, CodingKey { case type, command, entityId, cases, otherwise }

    /// Reads `{"type": "command", "command": …}` or `{"type": "state", "entityId"?, "cases": […], "otherwise": …}`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "command": self = .command(try c.decode(MediaRemoteCommand.self, forKey: .command))
        case "state":
            self = .state(entityId: try c.decodeIfPresent(String.self, forKey: .entityId),
                          cases: try c.decode([StateCase].self, forKey: .cases),
                          otherwise: try c.decode(MediaRemoteCommand.self, forKey: .otherwise))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown action")
        }
    }

    /// Writes the tagged form.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .command(command):
            try c.encode("command", forKey: .type)
            try c.encode(command, forKey: .command)
        case let .state(entityId, cases, otherwise):
            try c.encode("state", forKey: .type)
            try c.encodeIfPresent(entityId, forKey: .entityId)
            try c.encode(cases, forKey: .cases)
            try c.encode(otherwise, forKey: .otherwise)
        }
    }
}

extension RoomCardAction {
    private enum Keys: String, CodingKey { case type, action }

    /// Reads `{"type": "flip"}` or `{"type": "remote", "action": …}`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "flip": self = .flip
        case "remote": self = .remote(try c.decode(MediaRemoteAction.self, forKey: .action))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown card action")
        }
    }

    /// Writes the tagged form.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .flip: try c.encode("flip", forKey: .type)
        case let .remote(action):
            try c.encode("remote", forKey: .type)
            try c.encode(action, forKey: .action)
        }
    }
}

extension RoomCardSemantics {
    private enum Keys: String, CodingKey { case type, rule }

    /// Reads `{"type": "modal" | "command"}` or `{"type": "rule", "rule": …}`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "modal": self = .modal
        case "command": self = .command
        case "rule": self = .rule(try c.decode(SemanticsRule.self, forKey: .rule))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown semantics")
        }
    }

    /// Writes the tagged form.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .modal: try c.encode("modal", forKey: .type)
        case .command: try c.encode("command", forKey: .type)
        case let .rule(rule):
            try c.encode("rule", forKey: .type)
            try c.encode(rule, forKey: .rule)
        }
    }
}

extension QuickLink.Action {
    private enum Keys: String, CodingKey { case type, detail, path }

    /// Reads `{"type": "detail", "detail": …}` or `{"type": "navigate", "path": …}`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "detail": self = .detail(try c.decode(QuickLink.Detail.self, forKey: .detail))
        case "navigate": self = .navigate(try c.decode(String.self, forKey: .path))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown quick link action")
        }
    }

    /// Writes the tagged form.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .detail(detail):
            try c.encode("detail", forKey: .type)
            try c.encode(detail, forKey: .detail)
        case let .navigate(path):
            try c.encode("navigate", forKey: .type)
            try c.encode(path, forKey: .path)
        }
    }
}
