import Foundation

/// A garage door's one morphing action (owner, 2026-10-26): the spec's id is `"door"` in every state, so the disc is
/// one view whose glyph and label change and the symbol transition survives.
///
/// | state | verb | symbol | call |
/// |---|---|---|---|
/// | `closed` | Open | `door.garage.closed` | `cover.open_cover` |
/// | `open` | Close | `door.garage.open` | `cover.close_cover` |
/// | `opening`, `closing`, Stop supported (`supported_features & 8`) | Stop | `stop.fill` | `cover.stop_cover` |
/// | `opening`, `closing`, no Stop | Reverse | `arrow.uturn.down` (opening) / `arrow.uturn.up` (closing) | the opposite command, ``GarageDoorController/command(for:)`` |
/// | any, while ``Hold`` is sending or stopping | unchanged | unchanged | unchanged, ``TileActionSpec/Phase/inFlight`` |
/// | missing, `unavailable`, `unknown`, or no command for the state | Open | `door.garage.closed` | none | ``TileActionSpec/Phase/unavailable`` |
///
/// Feedback is ``TileActionSpec/Feedback/tracked``; the optimistic moving state lives in ``GarageDoorController``,
/// so the spec carries no intents. Ours are Aladdin Connect with `supported_features` 3: they reverse.
public struct CoverActions: TileActionProviding {
    /// The controller's request hold, as the view reads it from ``GarageDoorController``.
    public enum Hold: Equatable, Sendable {
        /// No request in flight.
        case none
        /// A command was just sent ("Sending Open…"), or the controller's `.sending` phase.
        case sending
        /// A Stop was sent and the door has not reported yet.
        case stopping
    }

    /// The cover entity.
    public var entityId: String
    /// The controller's hold; any hold other than ``Hold/none`` makes the spec ``TileActionSpec/Phase/inFlight``.
    public var hold: Hold

    /// Creates the provider.
    public init(entityId: String, hold: Hold = .none) {
        self.entityId = entityId
        self.hold = hold
    }

    /// The action's id in every state.
    public static let actionId = "door"

    /// `supported_features` bit for Stop (`CoverEntityFeature.STOP`).
    public static let stopFeature = 8

    /// Whether the cover reports Stop support.
    public static func supportsStop(_ state: EntityState?) -> Bool {
        guard let features = state?.attributes["supported_features"]?.number else { return false }
        return Int(features) & stopFeature != 0
    }

    public func actions(for state: EntityState?) -> [TileActionSpec] {
        let value = state?.state
        guard !EntityState.isUnavailable(value), let command = GarageDoorController.command(for: value) else {
            return [TileActionSpec(id: Self.actionId, verb: "Open", symbol: "door.garage.closed", isOn: false,
                                   phase: .unavailable, feedback: .tracked)]
        }
        let moving = value == "opening" || value == "closing"
        let filled = Self.isFilled(value)
        let phase: TileActionSpec.Phase = hold == .none ? .ready : .inFlight
        let spec: TileActionSpec
        if moving, Self.supportsStop(state) {
            spec = TileActionSpec(id: Self.actionId, verb: "Stop", symbol: "stop.fill", isOn: filled, phase: phase,
                                  feedback: .tracked, call: ServiceCall("cover", "stop_cover", target: entityId))
        } else if moving {
            spec = TileActionSpec(id: Self.actionId, verb: "Reverse", symbol: value == "opening" ? "arrow.uturn.down" : "arrow.uturn.up",
                                  isOn: filled, phase: phase, feedback: .tracked,
                                  call: ServiceCall("cover", command.service, target: entityId))
        } else {
            spec = TileActionSpec(id: Self.actionId, verb: command.opens ? "Open" : "Close",
                                  symbol: command.opens ? "door.garage.closed" : "door.garage.open", isOn: filled, phase: phase,
                                  feedback: .tracked, call: ServiceCall("cover", command.service, target: entityId))
        }
        return [spec]
    }

    public var stateTextCandidates: [String] {
        ["Closed", "Open", "Opening", "Closing", "Sending Open…", "Sending Close…", "Stopping…", "Error", "Unavailable"]
    }

    /// Whether the tile draws filled: whenever the door is not closed (open or moving), never while unavailable. Today's
    /// `GarageDoorTile` face rule.
    public static func isFilled(_ state: String?) -> Bool {
        guard let state, !EntityState.isUnavailable(state) else { return false }
        return state != "closed"
    }
}
