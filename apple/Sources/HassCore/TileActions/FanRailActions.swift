import Foundation

/// The bathroom fan's two actions, in the rail's order: Lock, then Power. Every command goes through the fan's script
/// with a `command` field (``BathroomFanController``): `script.<name>` with `command: "power"` and `target_power`, or
/// `command: "lock"` and `locked`. Never a toggle.
///
/// | state | `lock` | `power` |
/// |---|---|---|
/// | lock on | Unlock, `lock.fill`, isOn | |
/// | lock off | Lock, `lock.open` | |
/// | power on | | Turn Off, `power`, isOn |
/// | power off | | Turn On, `power` |
/// | lock entity unavailable | `.unavailable` | unchanged |
/// | power entity unavailable | `.unavailable` | `.unavailable` |
///
/// Both are ``TileActionSpec/Feedback/optimistic`` with the same intents the controller commits, so the extra helpers
/// it clears (a pending timer, the auto-unlock flag) are inputs here. The set always holds both ids: an unavailable
/// lock dims in place instead of leaving (the old rail hid it).
public struct FanRailActions: TileActionProviding {
    /// The fan.
    public var config: BathroomFanConfig
    /// The lock helper's state (`input_boolean`, `on` while the automation lock holds the fan).
    public var lockState: EntityState?
    /// Whether the off timer is pending (`config.pendingEntityId` reads `on`).
    public var timerPending: Bool
    /// Whether auto-unlock is set (`config.autoUnlockEntityId` reads `on`).
    public var autoUnlock: Bool

    /// Creates the provider. `actions(for:)` takes the power switch's state.
    public init(config: BathroomFanConfig, lockState: EntityState?, timerPending: Bool = false, autoUnlock: Bool = false) {
        self.config = config
        self.lockState = lockState
        self.timerPending = timerPending
        self.autoUnlock = autoUnlock
    }

    public func actions(for state: EntityState?) -> [TileActionSpec] {
        let powerAvailable = !EntityState.isUnavailable(state?.state)
        let lockAvailable = powerAvailable && !EntityState.isUnavailable(lockState?.state)
        let powerOn = state?.state == "on"
        let locked = lockState?.state == "on"
        func script(_ data: [String: JSONValue]) -> ServiceCall { ServiceCall("script", config.scriptService, data: data) }
        func intent(_ id: String, _ on: Bool) -> OptimisticIntent { OptimisticIntent(id, value: on ? "on" : "off") }

        // Lock: locking during a timer turns auto-unlock on (`BathroomFanController.setLocked`).
        let setLocked = !locked
        var lockIntents = [intent(config.lockEntityId, setLocked)]
        if setLocked && timerPending { lockIntents.append(intent(config.autoUnlockEntityId, true)) }

        // Power: also clears the timer, lock and auto-unlock on the server (`setPower`).
        let setPower = !powerOn
        var powerIntents = [intent(config.powerEntityId, setPower)]
        if timerPending { powerIntents.append(intent(config.pendingEntityId, false)) }
        if locked { powerIntents.append(intent(config.lockEntityId, false)) }
        if autoUnlock { powerIntents.append(intent(config.autoUnlockEntityId, false)) }

        return [
            TileActionSpec(id: "lock", verb: locked ? "Unlock" : "Lock", symbol: locked ? "lock.fill" : "lock.open", isOn: locked,
                           phase: lockAvailable ? .ready : .unavailable, feedback: .optimistic,
                           call: script(["command": .string("lock"), "locked": .bool(setLocked)]), optimistic: lockIntents),
            TileActionSpec(id: "power", verb: powerOn ? "Turn Off" : "Turn On", symbol: "power", isOn: powerOn,
                           phase: powerAvailable ? .ready : .unavailable, feedback: .optimistic,
                           call: script(["command": .string("power"), "target_power": .string(setPower ? "on" : "off")]),
                           optimistic: powerIntents),
        ]
    }

    public var stateTextCandidates: [String] { ["On", "Off", "Off in 00:00:00", "Unavailable", "Didn't Respond"] }
}
