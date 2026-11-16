import Foundation

// MARK: - Built-in styles

extension StateStyle {
    /// The Stop feature bit of a cover (`CoverEntityFeature.STOP`).
    public static let coverStopFeature = 8

    /// A garage door: open and closed rest; opening and closing keep the disc as Stop, or Reverse where Stop is not supported.
    /// Timings and words are the web's (`constants/garageDoors.ts`).
    public static let garageDoor = StateStyle(
        id: "garage-door", name: "Garage door", domain: "cover", actionId: "door",
        rules: [
            StateRule(["closed"], .resting, action: StateAction(verb: "Open", symbol: "door.garage.closed", service: "open_cover")),
            StateRule(["open"], .resting, active: true, action: StateAction(verb: "Close", symbol: "door.garage.open", service: "close_cover")),
            StateRule(["opening"], .inProgress, active: true, action: StateAction(
                verb: "Stop", symbol: "stop.fill", service: "stop_cover", requiresFeature: coverStopFeature,
                otherwise: .init(verb: "Reverse", symbol: "arrow.uturn.down", service: "close_cover"))),
            StateRule(["closing"], .inProgress, active: true, action: StateAction(
                verb: "Stop", symbol: "stop.fill", service: "stop_cover", requiresFeature: coverStopFeature,
                otherwise: .init(verb: "Reverse", symbol: "arrow.uturn.up", service: "open_cover"))),
            StateRule(["unavailable", "unknown"], .unknown, glyph: "door.garage.closed",
                      action: StateAction(verb: "Open", symbol: "door.garage.closed", service: nil, isTappable: false)),
        ],
        request: StateRequest(lockout: .seconds(2), ackTimeout: .seconds(10), settleTimeout: .seconds(45), errorHold: .seconds(8),
                              pendingWords: ["open_cover": "Sending Open…", "close_cover": "Sending Close…", "stop_cover": "Stopping…"],
                              pendingStates: ["open_cover": "opening", "close_cover": "closing"]),
        togglesDisc: true)

    /// A lock: locked and unlocked rest; moving states (locking, unlocking, opening) ignore taps; `open` warns; `jammed` is an error and a tap locks.
    public static let lock = StateStyle(
        id: "lock", name: "Lock", domain: "lock", actionId: "lock",
        rules: [
            StateRule(["locked"], .resting, action: StateAction(verb: "Unlock", symbol: "lock.fill", service: "unlock")),
            StateRule(["unlocked"], .resting, active: true, action: StateAction(verb: "Lock", symbol: "lock.open", service: "lock")),
            StateRule(["open"], .warning, active: true, action: StateAction(verb: "Lock", symbol: "lock.open", service: "lock")),
            StateRule(["locking"], .inProgress, action: StateAction(verb: "Unlock", symbol: "lock.fill", service: "unlock", isTappable: false)),
            StateRule(["unlocking", "opening"], .inProgress, active: true, action: StateAction(verb: "Lock", symbol: "lock.open", service: "lock", isTappable: false)),
            StateRule(["jammed"], .error, active: true, action: StateAction(verb: "Lock", symbol: "lock.trianglebadge.exclamationmark", service: "lock")),
            StateRule(["unavailable", "unknown"], .unknown, glyph: "lock.fill",
                      action: StateAction(verb: "Unlock", symbol: "lock.fill", service: "unlock", isTappable: false)),
        ],
        request: StateRequest(lockout: .seconds(0), ackTimeout: .seconds(10), settleTimeout: .seconds(2), errorHold: .seconds(4),
                              onTimeout: .revert, pendingStates: ["lock": "locking", "unlock": "unlocking"], errorWords: "Didn't Respond"),
        togglesDisc: true, drawsErrorDisc: true)

    /// A blind: open and closed rest; opening and closing keep the disc as Stop where the cover supports it, else the arc stands in.
    public static let blind = StateStyle(
        id: "blind", name: "Blind", domain: "cover", actionId: "blind",
        rules: [
            StateRule(["closed"], .resting, glyph: "blinds.horizontal.closed",
                      action: StateAction(verb: "Open", symbol: "blinds.horizontal.closed", service: "open_cover")),
            StateRule(["open"], .resting, active: true, glyph: "blinds.horizontal.open",
                      action: StateAction(verb: "Close", symbol: "blinds.horizontal.open", service: "close_cover")),
            StateRule(["opening", "closing"], .inProgress, active: true, glyph: "blinds.horizontal.open", action: StateAction(
                verb: "Stop", symbol: "stop.fill", service: "stop_cover", requiresFeature: coverStopFeature, otherwise: nil)),
            StateRule(["unavailable", "unknown"], .unknown, glyph: "blinds.horizontal.closed"),
        ],
        request: StateRequest(lockout: .seconds(2), ackTimeout: .seconds(10), settleTimeout: .seconds(45), errorHold: .seconds(4),
                              errorWords: "Didn't Respond"),
        togglesDisc: true)

    /// The alarm: Arm Home while disarmed, Disarm (asked first) while armed. Disarm stays tappable through arming, pending and
    /// triggered; only disarming ignores taps. `pending` warns and `triggered` is an error.
    public static let alarm = StateStyle(
        id: "alarm", name: "Alarm", domain: "alarm_control_panel", actionId: "alarm",
        rules: [
            StateRule(["disarmed"], .resting, action: armHome),
            StateRule(["armed_home", "armed_away", "armed_night", "armed_vacation", "armed_custom_bypass"], .resting, active: true, action: disarm),
            StateRule(["arming"], .inProgress, active: true, action: disarm),
            StateRule(["pending"], .warning, active: true, action: disarm),
            StateRule(["disarming"], .inProgress, action: StateAction(verb: "Arm Home", symbol: "shield.lefthalf.filled",
                                                                       service: "alarm_arm_home", isTappable: false)),
            StateRule(["triggered"], .error, active: true, action: disarm),
            StateRule(["unavailable", "unknown"], .unknown, glyph: "shield.lefthalf.filled",
                      action: StateAction(verb: "Arm Home", symbol: "shield.lefthalf.filled", service: "alarm_arm_home", isTappable: false)),
        ],
        request: nil)

    /// The question asked before the alarm disarms (the same words as the Security sheet's alert).
    public static let alarmDisarmConfirmation = TileActionSpec.Confirmation(
        title: "Disarm the Security System?", message: "Doors and motion stop triggering the alarm.", confirmVerb: "Disarm")

    private static let armHome = StateAction(verb: "Arm Home", symbol: "shield.lefthalf.filled", service: "alarm_arm_home")
    private static let disarm = StateAction(verb: "Disarm", symbol: "shield.slash", service: "alarm_disarm",
                                            confirmation: alarmDisarmConfirmation)

    /// A robot: docked and idle rest; cleaning and mowing rest lit and breathe; paused warns; returning is in progress; error fails.
    public static let robot = StateStyle(
        id: "robot", name: "Robot", domain: "vacuum", actionId: "robot",
        rules: [
            StateRule(["docked", "idle"], .resting),
            StateRule(["cleaning", "mowing"], .resting, active: true, indicator: .breathe),
            StateRule(["paused"], .warning),
            StateRule(["returning"], .inProgress),
            StateRule(["error"], .error),
            StateRule(["unavailable", "unknown"], .unknown),
        ])

    /// A detector (smoke, gas, carbon monoxide, moisture, problem, tamper, safety): off rests, on is an error.
    public static let detector = StateStyle(
        id: "detector", name: "Detector", domain: "binary_sensor", actionId: "detector",
        rules: [StateRule(["off"], .resting), StateRule(["on"], .error), StateRule(["unavailable", "unknown"], .unknown)])

    /// A notice (battery, heat, cold, update, connectivity): off rests, on warns.
    public static let notice = StateStyle(
        id: "notice", name: "Notice", domain: "binary_sensor", actionId: "notice",
        rules: [StateRule(["off"], .resting), StateRule(["on"], .warning), StateRule(["unavailable", "unknown"], .unknown)])

    /// A switch: off rests unlit, on rests lit.
    public static let `switch` = StateStyle(
        id: "switch", name: "Switch", domain: "switch", actionId: "switch",
        rules: [StateRule(["off"], .resting), StateRule(["on"], .resting, active: true), StateRule(["unavailable", "unknown"], .unknown)])

    /// Every built-in style, in the library's order.
    public static let builtIn: [StateStyle] = [garageDoor, lock, blind, alarm, robot, detector, notice, `switch`]

    /// The built-in style with `id`.
    public static func builtIn(id: String) -> StateStyle? { builtIn.first { $0.id == id } }
}
