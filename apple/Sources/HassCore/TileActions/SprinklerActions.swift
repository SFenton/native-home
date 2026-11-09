import Foundation

/// A sprinkler controller card's one disc (audit item 30): **Stop Watering** while a zone waters; **dimmed in place** while idle,
/// so the set never changes shape (like Dock on a docked vacuum). Momentary: the press highlight and the tap haptic, then the disc
/// dims when the controller reports idle.
///
/// The provider reads the *watering valve*: pass the valve entity that is open or opening, or nil. The snapshot overload picks it
/// from a ``SprinklerSnapshot`` (and keeps the card unavailable when the controller is). The call is the controller's
/// (`bhyve.stop_watering`, ``SprinklersConfig/stopWatering(valve:)``); `SprinklerController.stopWatering()` runs the same call with
/// its own optimistic value, which the card should prefer.
///
/// | valve state | phase |
/// |---|---|
/// | `open`, `opening` | ready |
/// | anything else, nil | unavailable (idle: dims in place) |
public struct SprinklerActions: TileActionProviding {
    /// The action's id in every state.
    public static let actionId = "stop"

    /// The valve the disc stops when watering has not been observed (the controller's first zone), so the idle spec has a call.
    public var fallbackValveEntityId: String

    /// Creates the provider.
    public init(fallbackValveEntityId: String) {
        self.fallbackValveEntityId = fallbackValveEntityId
    }

    /// The provider for a configured controller.
    public init(_ controller: SprinklersConfig.Controller) {
        self.init(fallbackValveEntityId: controller.zones.first?.valveEntityId ?? "")
    }

    /// Whether a valve state means water is flowing.
    public static func isWatering(_ state: String?) -> Bool { state == "open" || state == "opening" }

    /// The disc for the watering valve `state` (the open valve's entity), or an idle disc when nil or not open.
    public func actions(for state: EntityState?) -> [TileActionSpec] {
        let watering = Self.isWatering(state?.state)
        let valve = watering ? (state?.entityId ?? fallbackValveEntityId) : fallbackValveEntityId
        return [TileActionSpec(
            id: Self.actionId, verb: "Stop Watering", symbol: "stop.fill", phase: watering ? .ready : .unavailable, feedback: .momentary,
            call: SprinklersConfig.stopWatering(valve: valve), label: "Stop Watering"
        )]
    }

    /// The disc for a controller snapshot: ready while watering (stopping the active valve), dimmed otherwise.
    public func actions(for snapshot: SprinklerSnapshot) -> [TileActionSpec] {
        actions(for: snapshot, shownValve: snapshot.activeValveEntityId)
    }

    /// The disc for a controller snapshot and the valve the card *shows* watering (optimistic: a tapped Stop shows none at once, a
    /// tapped zone shows its valve), so the disc dims the moment Stop is pressed, as `SprinklerController.isWatering` does.
    /// - Parameter shownValve: The valve shown open, or nil when none is.
    public func actions(for snapshot: SprinklerSnapshot, shownValve: String?) -> [TileActionSpec] {
        let valve = shownValve ?? fallbackValveEntityId
        let ready = shownValve != nil && snapshot.available
        return [TileActionSpec(
            id: Self.actionId, verb: "Stop Watering", symbol: "stop.fill", phase: ready ? .ready : .unavailable, feedback: .momentary,
            call: SprinklersConfig.stopWatering(valve: valve), label: "Stop Watering"
        )]
    }

    public var stateTextCandidates: [String] { ["Watering", "Fault", "Unavailable", "Didn't Respond"] }
}
