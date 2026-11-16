import Foundation

/// What the household Settings tiles (Admin, Auto-Reset, Special Device Modes, Guest Controls, Car) show and run as action
/// tiles (rollout lane S, audit items 18 to 25; pattern: `.agents/patterns/action-tiles.md`). Pure rules: the views feed them the
/// shown state (``HouseholdSettingsController`` owns the optimistic value and the failure face) and run the spec.
public enum HouseholdTileActions {
    // MARK: - Mapping

    /// The provider kind of a control the document declares, by the control's own kind and never by a house-configuration list: a
    /// switch is a ``TileActionKind/power`` disc, power recovery a momentary command, a reading or a presence row shows state only
    /// (a presence row opens its own page, which is a destination, not an action).
    public static func kind(of target: HouseholdSettingsTarget.Kind) -> TileActionKind {
        switch target {
        case .toggle: .power
        case .powerRecovery: .momentaryCommand
        case .presence, .readOnly: .none
        }
    }

    /// A control's class from its kind: a switch acts, a reading reads (no tile here opens anything).
    public static func classification(of target: HouseholdSettingsTarget.Kind) -> TileClassification {
        .classify(hasDestination: false, actions: kind(of: target).restingActionCount)
    }

    /// The provider kind of a configured Settings tile that is not a switch: the vehicle's Doors a ``TileActionKind/lock``, a
    /// reading shows state only. A switch is named by its control kind (``kind(of:)-(HouseholdSettingsTarget.Kind)``).
    public static func kind(of tile: HouseholdSettingsConfig.Tile) -> TileActionKind {
        tile.entityId == SecurityConfig.vehicleLockEntityId ? .lock : .none
    }

    /// A non-switch Settings tile's class: no tile here opens anything, so it acts or it reads.
    public static func classification(of tile: HouseholdSettingsConfig.Tile) -> TileClassification {
        .classify(hasDestination: false, actions: kind(of: tile).restingActionCount)
    }

    /// Admin's power recovery: one momentary command.
    public static var powerRecoveryClassification: TileClassification {
        .classify(hasDestination: false, actions: TileActionKind.momentaryCommand.restingActionCount)
    }

    // MARK: - Power switches

    /// The switch's one action for what the tile shows: Turn Off while on, Turn On while off, dimmed while unavailable.
    /// Explicit `turn_on` / `turn_off` (``PowerToggleActions``), optimistic. The disc draws the action glyph, never the authored
    /// icon: `power` for every switch, except Front Door Auto-Lock (`isAutoLock`, a house_config role), which draws the lock it
    /// controls: `lock.fill` while on, `lock.open` while off or unavailable.
    public static func specs(entityId: String, isAutoLock: Bool = false, isOn: Bool, isUnavailable: Bool) -> [TileActionSpec] {
        let symbol = isAutoLock ? (isOn && !isUnavailable ? "lock.fill" : "lock.open") : "power"
        let provider = PowerToggleActions.entity(entityId, symbol: symbol)
        let shown = isUnavailable ? "unavailable" : (isOn ? "on" : "off")
        return provider.actions(for: EntityState(entityId: entityId, state: shown))
    }

    /// The state texts a switch tile can show, so the tile reserves room for the longest.
    public static var stateTextCandidates: [String] { PowerToggleActions.entity("input_boolean.demo_switch").stateTextCandidates }

    // MARK: - Guest Controls

    /// A guest-stay tile's state line: the Home page's words ("Guests staying" / "No guests").
    public static func guestStateText(isOn: Bool, isUnavailable: Bool, isFailed: Bool) -> String {
        if isUnavailable { return "Unavailable" }
        if isFailed { return "Didn't Respond" }
        return isOn ? "Guests staying" : "No guests"
    }

    // MARK: - Car Doors

    /// The vehicle's door lock: the lock disc (Unlock, Lock), the same provider as the Security page's Car tile.
    public static var doors: StateStyleActions { StateStyleActions(.lock, entityId: SecurityConfig.vehicleLockEntityId) }
}
