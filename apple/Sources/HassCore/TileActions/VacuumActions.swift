import Foundation

/// A robot vacuum's two actions: start / pause (optimistic) and dock (momentary). Both ids are always present, so the
/// set never changes shape; an action that does not apply (dock while docked) dims in place.
///
/// Services and optimistic values match ``VacuumController/run(_:pixelSize:)`` (`vacuum.start` shows `cleaning`,
/// `vacuum.pause` shows `paused`, `vacuum.return_to_base`).
///
/// | state | `start_pause` | `dock` |
/// |---|---|---|
/// | `cleaning` | Pause, `pause.fill` | Dock, `house.fill` |
/// | `returning` | Pause | unavailable (already heading home) |
/// | `paused` | Resume, `play.fill` | Dock |
/// | `idle` | Start | Dock |
/// | `docked` | Start | unavailable (already home) |
/// | `error` | unavailable | Dock |
/// | missing, `unavailable`, `unknown`, other | unavailable | unavailable |
public struct VacuumActions: TileActionProviding {
    /// The vacuum entity.
    public var entityId: String

    /// Creates the provider.
    public init(entityId: String) {
        self.entityId = entityId
    }

    public func actions(for state: EntityState?) -> [TileActionSpec] {
        let value = state?.state ?? "unavailable"
        let known: Set<String> = ["cleaning", "returning", "paused", "idle", "docked", "error"]
        let usable = known.contains(value)
        let pausing = value == "cleaning" || value == "returning"
        let startPause: TileActionSpec
        if pausing {
            startPause = TileActionSpec(id: "start_pause", verb: "Pause", symbol: "pause.fill", phase: .ready, feedback: .optimistic,
                                        call: ServiceCall("vacuum", "pause", target: entityId),
                                        optimistic: [OptimisticIntent(entityId, value: "paused")])
        } else {
            startPause = TileActionSpec(id: "start_pause", verb: value == "paused" ? "Resume" : "Start", symbol: "play.fill",
                                        phase: ["paused", "idle", "docked"].contains(value) ? .ready : .unavailable,
                                        feedback: .optimistic, call: ServiceCall("vacuum", "start", target: entityId),
                                        optimistic: [OptimisticIntent(entityId, value: "cleaning")])
        }
        let canDock = usable && ["cleaning", "paused", "idle", "error"].contains(value)
        let dock = TileActionSpec(id: "dock", verb: "Dock", symbol: "house.fill", phase: canDock ? .ready : .unavailable,
                                  feedback: .momentary, call: ServiceCall("vacuum", "return_to_base", target: entityId))
        return [startPause, dock]
    }

    public var stateTextCandidates: [String] { ["Cleaning", "Paused", "Docked", "Returning", "Error", "Idle", "Unavailable"] }
}
