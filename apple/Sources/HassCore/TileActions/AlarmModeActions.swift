import Foundation

/// The Quick Links Security System disc (audit item 17, owner 2026-10-27): **Arm Home** while the panel is disarmed, **Disarm**
/// while it is armed. Disarm is confirmed with today's alert ("Disarm the Security System?"); arming is not.
///
/// Services and wording come from ``SecurityConfig`` (`alarm_control_panel.alarm_arm_home`, `alarm_disarm`); the panel takes no
/// code here, as the Security sheet's mode buttons send none.
///
/// | state | verb | symbol | phase |
/// |---|---|---|---|
/// | `disarmed` | Arm Home | `shield.lefthalf.filled` | ready |
/// | `armed_home`, `armed_away`, `armed_night`, `armed_vacation`, `armed_custom_bypass`, `triggered` | Disarm (confirmed) | `shield.slash` | ready |
/// | `arming`, `pending` | Disarm (confirmed) | `shield.slash` | ready: the exit and entry delays are when Disarm matters most |
/// | `disarming` | Arm Home | `shield.lefthalf.filled` | inFlight |
/// | missing, `unavailable`, `unknown` | Arm Home | `shield.lefthalf.filled` | unavailable |
///
/// Feedback is ``TileActionSpec/Feedback/tracked``: only `disarming` holds the disc in flight. `arming` and `pending` keep Disarm
/// tappable, because `pending` is the entry delay before the alarm triggers.
public struct AlarmModeActions: TileActionProviding {
    /// The action's id in every state, so Arm Home morphs into Disarm.
    public static let actionId = "alarm"

    /// The alarm panel.
    public var entityId: String

    /// Creates the provider; the default is the house's panel.
    public init(entityId: String = SecurityConfig.alarmEntityId) {
        self.entityId = entityId
    }

    /// The question asked before disarming (the same words as the Security sheet's alert).
    public static let disarmConfirmation = TileActionSpec.Confirmation(
        title: "Disarm the Security System?", message: "Doors and motion stop triggering the alarm.", confirmVerb: "Disarm"
    )

    /// States in which the panel is armed or arming, so the disc offers Disarm.
    static let armedStates: Set<String> = ["armed_home", "armed_away", "armed_night", "armed_vacation", "armed_custom_bypass", "triggered", "arming", "pending"]

    public func actions(for state: EntityState?) -> [TileActionSpec] {
        let value = state?.state
        let unavailable = EntityState.isUnavailable(value)
        let disarms = !unavailable && Self.armedStates.contains(value ?? "")
        let moving = value == "disarming"
        let mode = disarms ? SecurityConfig.disarmMode : SecurityConfig.alarmModes[0]
        let phase: TileActionSpec.Phase = unavailable ? .unavailable : (moving ? .inFlight : .ready)
        return [TileActionSpec(
            id: Self.actionId, verb: disarms ? "Disarm" : "Arm Home", symbol: disarms ? "shield.slash" : "shield.lefthalf.filled",
            phase: phase, feedback: .tracked, call: ServiceCall("alarm_control_panel", mode.service, target: entityId),
            confirmation: disarms ? Self.disarmConfirmation : nil
        )]
    }

    public var stateTextCandidates: [String] {
        ["Disarmed", "Armed Home", "Armed Away", "Armed Night", "Armed Vacation", "Arming", "Pending", "Disarming", "Triggered", "Unavailable"]
    }
}
