import HassCore
import HassDesign
import SwiftUI

// MARK: - Colors

extension SecurityConfig {
}

// MARK: - Garage door tile

/// A garage door tile driven by ``GarageDoorController`` (web `GarageDoorTile.tsx`): the garage room cards draw it.
/// The Security page's Doors section shows the same tile (``SecurityDoorTile``). An action tile, *text · disc*: one morphing
/// disc (id ``CoverActions/actionId``, stable across Open, Close and Reverse) from ``CoverActions``, the only place the door's
/// verb, glyph and phase are decided. The contact family, filled while the door is open or moving, and the red error face
/// after a failed command.
@MainActor
struct GarageDoorTile {
    /// The door's one action for the controller's shown state; its "Sending…" hold is the disc's in-flight arc.
    ///
    /// The controller only reverses (the opposite command), so the provider is fed the state without attributes: a Stop
    /// role would have no command to run. Ours are Aladdin Connect covers (`supported_features` 3), which reverse.
    static func specs(for controller: GarageDoorController) -> [TileActionSpec] {
        let state = EntityState(entityId: controller.entityId, state: controller.displayState)
        let hold: CoverActions.Hold = controller.phase == .sending ? .sending : .none
        return CoverActions(entityId: controller.entityId, hold: hold).actions(for: state)
    }

    /// "Sending Open…" / "Sending Close…" while sending, "Error" after a failure, else the shown state.
    static func subtitle(for controller: GarageDoorController) -> String {
        switch controller.phase {
        case .sending: controller.opens == true ? "Sending Open…" : "Sending Close…"
        case .error: "Error"
        case .idle, .pending:
            controller.liveState == "unavailable" ? "Unavailable" : SecurityConfig.stateText(controller.displayState)
        }
    }
}
