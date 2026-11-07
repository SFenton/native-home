import Foundation

/// What the household Settings tiles (Admin, Auto-Reset, Special Device Modes, Guest Controls, Mach-E) show and run as action
/// tiles (rollout lane S, audit items 18 to 25; pattern: `.agents/patterns/action-tiles.md`). Pure rules: the views feed them the
/// shown state (``HouseholdSettingsController`` owns the optimistic value and the failure face) and run the spec.
public enum HouseholdTileActions {
    // MARK: - Mapping

    /// The provider kind of a configured Settings tile: a switch is a ``TileActionKind/power`` disc, the vehicle's Doors a
    /// ``TileActionKind/lock``, a reading shows state only.
    public static func kind(of tile: HouseholdSettingsConfig.Tile) -> TileActionKind {
        if tile.entityId == SecurityConfig.vehicleLockEntityId { return .lock }
        if HouseholdSettingsConfig.toggleEntityIds.contains(tile.entityId) { return .power }
        return .none
    }

    /// A Settings tile's class: no tile here opens anything, so it acts or it reads.
    public static func classification(of tile: HouseholdSettingsConfig.Tile) -> TileClassification {
        .classify(hasDestination: false, actions: kind(of: tile).restingActionCount)
    }

    /// Admin's power recovery: one momentary command.
    public static var powerRecoveryClassification: TileClassification {
        .classify(hasDestination: false, actions: TileActionKind.momentaryCommand.restingActionCount)
    }

    // MARK: - Power switches

    /// The entity whose disc draws a lock (Front Door Auto-Lock enabled = `lock.fill`, disabled = `lock.open`).
    public static var autoLockEntityId: String {
        HouseholdSettingsConfig.Admin.securityTiles.first?.entityId ?? ""
    }

    /// The disc's glyph for a switch: the power glyph, except Front Door Auto-Lock, which draws the lock it controls (the mockup,
    /// item 18). Unavailable draws the open lock, like an off switch.
    public static func symbol(for tile: HouseholdSettingsConfig.Tile, isOn: Bool) -> String {
        guard tile.entityId == autoLockEntityId else { return PowerToggleActions.entity(tile.entityId).symbol }
        return isOn ? "lock.fill" : "lock.open"
    }

    /// The switch's one action for what the tile shows: Turn Off while on, Turn On while off, dimmed while unavailable.
    /// Explicit `turn_on` / `turn_off` (``PowerToggleActions``), optimistic.
    public static func specs(for tile: HouseholdSettingsConfig.Tile, isOn: Bool, isUnavailable: Bool) -> [TileActionSpec] {
        let provider = PowerToggleActions.entity(tile.entityId, symbol: symbol(for: tile, isOn: isOn && !isUnavailable))
        let shown = isUnavailable ? "unavailable" : (isOn ? "on" : "off")
        return provider.actions(for: EntityState(entityId: tile.entityId, state: shown))
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

    // MARK: - Mach-E Doors

    /// The vehicle's door lock: the lock disc (Unlock, Lock), the same provider as the Security page's Mach-E tile.
    public static var doors: LockActions { LockActions(entityId: SecurityConfig.vehicleLockEntityId) }
}
