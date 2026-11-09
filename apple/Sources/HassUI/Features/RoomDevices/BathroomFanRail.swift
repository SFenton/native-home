import HassCore
import HassDesign

extension BathroomFanController {
    /// Lock and Power from ``FanRailActions`` (the provider owns verbs, glyphs and what dims), fed the shown state. An unavailable
    /// switch dims its disc in place instead of leaving. The fan sheet draws one disc each as action tiles.
    var railSpecs: [TileActionSpec] {
        func shown(_ id: String) -> EntityState? { commands.entity(id)?.showing(commands.displayed(id)) }
        return FanRailActions(config: config, lockState: shown(config.lockEntityId), timerPending: timerPending, autoUnlock: autoUnlock)
            .actions(for: shown(config.powerEntityId))
    }

    /// Runs the disc `id` of ``railSpecs`` through the fan script's explicit target state (never a toggle).
    func runRail(_ id: TileActionItem.ID) {
        switch id {
        case "lock": setLocked(!locked)
        case "power": setPower(!powerOn)
        default: break
        }
    }
}
