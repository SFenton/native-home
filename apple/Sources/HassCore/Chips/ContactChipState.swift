import Foundation

/// What a Contact Sensors chip says about the house: one rule shared by Home's chip, every room rail and Security's chip
/// (`.agents/patterns/status-rail.md`, "Contact chip states").
///
/// The web draws the chip green or neutral from the sensors alone. Owner, 2026-10-16: "need to decide all closed, open
/// but we're home, open but we're away, open but security system is on." The web has no rule for those, so this is the
/// planner's decision (direction G, Status chips); precedence runs from the alarm down.
public enum ContactChipState: Equatable, Sendable {
    /// No sensor reading (the group entity is missing or unavailable).
    case unavailable
    /// Everything is shut.
    case allClosed
    /// Something is open, someone is home and the system is not armed: a warning, not an alert.
    case openHome
    /// Something is open and the whole household is away (not armed).
    case openAway
    /// Something is open while the security system is armed in any mode, or has triggered.
    case openArmed

    /// Whether an alarm panel state is an armed mode (or a triggered alarm), as opposed to disarmed, arming, pending or
    /// unknown.
    public static func isArmed(_ alarmState: String?) -> Bool {
        guard let alarmState else { return false }
        return alarmState.hasPrefix("armed_") || alarmState == "triggered"
    }

    /// The state for a chip.
    /// - Parameters:
    ///   - isOpen: Whether the chip's sensors report something open; `nil` when they report nothing.
    ///   - alarmState: The alarm panel's state.
    ///   - isAway: Whether the household is effectively away (``ClimateLogic/isEffectivelyAway(_:)``).
    public static func resolve(isOpen: Bool?, alarmState: String?, isAway: Bool) -> ContactChipState {
        guard let isOpen else { return .unavailable }
        guard isOpen else { return .allClosed }
        if isArmed(alarmState) { return .openArmed }
        return isAway ? .openAway : .openHome
    }

    /// The state read from the live entities.
    /// - Parameters:
    ///   - isOpen: See ``resolve(isOpen:alarmState:isAway:)``.
    ///   - read: Looks up an entity's current state; reads the alarm panel and the home/away entities.
    public static func current(isOpen: Bool?, read: EntityLookup) -> ContactChipState {
        resolve(isOpen: isOpen, alarmState: read(SecurityConfig.alarmEntityId)?.state, isAway: ClimateLogic.isEffectivelyAway(read))
    }

    /// Whether anything is open.
    public var isOpen: Bool {
        switch self {
        case .openHome, .openAway, .openArmed: true
        case .unavailable, .allClosed: false
        }
    }
}
