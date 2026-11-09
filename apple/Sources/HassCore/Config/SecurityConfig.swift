import Foundation

/// Entity configuration and state rules for the Security page, ported from the React dashboard.
///
/// Sources (`ha-sfenton-react-dash@9ac2a46`): `src/constants/securityPage.ts`, `src/constants/garageDoors.ts`,
/// `src/components/hass/SecurityDashboard.tsx`, `SecurityControls.tsx` and `securityState.ts`.
public enum SecurityConfig {
    // MARK: - Entities

    /// Projects a value out of the loaded document's Security section.
    private static func read<T>(_ project: (HouseConfig.SecuritySection) -> T) -> T? {
        HouseConfigSource.active.read { project($0.security) }
    }

    /// The household alarm panel (`SECURITY_ENTITY`, atAGlance.ts:757). Like every value here: the server's
    /// document, else empty.
    public static var alarmEntityId: String { read { $0.alarmEntityId } ?? "" }
    /// The front door smart lock.
    public static var frontDoorLockEntityId: String { read { $0.entryLockEntityId } ?? "" }
    /// Left garage door cover (`GARAGE_DOOR_ENTITY_IDS`).
    public static var leftGarageDoorEntityId: String { read { $0.garageDoors["left"] }.flatMap { $0 } ?? "" }
    /// Right garage door cover.
    public static var rightGarageDoorEntityId: String {
        read { $0.garageDoors["right"] }.flatMap { $0 } ?? ""
    }
    /// The car's door lock (the web's security vehicle tiles).
    public static var vehicleLockEntityId: String { read { $0.vehicleLockEntityId } ?? "" }
    /// Contact sensor group the Contact Sensors chip summarizes.
    public static var contactSensorsEntityId: String { read { $0.contactSensorsEntityId } ?? "" }


    /// The web hides the Vehicle section (a flag the web sets to false, SecurityDashboard.tsx:31); the native
    /// page follows it. The debug gallery shows the section so its tile stays tested.
    public static var showsVehicleSection: Bool { read { $0.showsVehicleSection } ?? false }

    // MARK: - Tiles

    /// How a tile behaves (web `SecurityTileTone` plus `SecurityTileAction`).
    public enum TileKind: String, Sendable, Codable {
        /// Opens the security system sheet.
        case alarm
        /// Locks or unlocks.
        case lock
        /// A garage door: open/close with the command state machine (``GarageDoorController``).
        case garageDoor
        /// The car's door lock.
        case vehicle
    }

    /// One Security tile.
    public struct Tile: Sendable, Identifiable, Hashable, Codable {
        public var title: String
        public var entityId: String
        /// Web MDI icon name.
        public var icon: String
        public var kind: TileKind
        public var id: String { entityId }
    }

    /// `SECURITY_CONTROL_TILES`, in web order: the server's document.
    public static var controlTiles: [Tile] { read { $0.controlTiles } ?? [] }

    /// The web's security vehicle tiles: the server's document.
    public static var vehicleTiles: [Tile] { read { $0.vehicleTiles } ?? [] }

    // MARK: - Tone

    /// A tile's color role (web `TileTone` as chosen by `tileTone`, SecurityDashboard.tsx:59).
    public enum Tone: String, Sendable {
        /// Closed, locked or disarmed (web `contact`, green).
        case secure
        /// Armed or moving (web `security`, blue).
        case active
        /// Open, unlocked or failed (web `danger`, red).
        case danger
        /// Unavailable.
        case neutral
    }

    /// The tone for a tile showing `state`.
    public static func tone(for kind: TileKind, state: String?) -> Tone {
        guard let state, !EntityState.isUnavailable(state) else { return .neutral }
        switch kind {
        case .garageDoor:
            switch state {
            case "closed": return .secure
            case "open", "opening": return .danger
            default: return .active
            }
        case .lock, .vehicle:
            switch state {
            case "locked": return .secure
            case "unlocked", "open", "jammed": return .danger
            default: return .active
            }
        case .alarm:
            return state == "disarmed" ? .secure : (state == "triggered" ? .danger : .active)
        }
    }

    // MARK: - Locks

    /// The lock service that flips what the tile shows (web `lockServiceForState`): unlocked or unlocking locks,
    /// anything else unlocks. Explicit services, never `toggle`.
    public static func lockService(for state: String?) -> String {
        state == "unlocked" || state == "unlocking" || state == "open" ? "lock" : "unlock"
    }

    /// The `lock.lock` / `lock.unlock` call for a lock tile.
    public static func lockCall(entityId: String, state: String?) -> ServiceCall {
        ServiceCall("lock", lockService(for: state), target: entityId)
    }

    // MARK: - Alarm modes

    /// One alarm mode button (`SECURITY_MODES`, SecurityControls.tsx:15).
    public struct AlarmMode: Sendable, Identifiable, Hashable {
        public var title: String
        /// `alarm_control_panel` service.
        public var service: String
        /// The panel state this mode sets.
        public var state: String
        public var icon: String
        public var id: String { state }
        /// Disarming opens the house, so it asks first (HIG: Alerts, confirming actions with serious consequences).
        public var needsConfirmation: Bool { state == "disarmed" }
        /// The mode button's label: the action for Disarm ("Disarm"), the mode's name otherwise (mockup n3).
        public var buttonTitle: String { needsConfirmation ? "Disarm" : title }

        /// The service call that selects this mode.
        public var call: ServiceCall { ServiceCall("alarm_control_panel", service, target: SecurityConfig.alarmEntityId) }
    }

    /// Modes in web order.
    public static let alarmModes: [AlarmMode] = [
        .init(title: "Home", service: "alarm_arm_home", state: "armed_home", icon: "mdi:shield-home"),
        .init(title: "Away", service: "alarm_arm_away", state: "armed_away", icon: "mdi:shield"),
        .init(title: "Night", service: "alarm_arm_night", state: "armed_night", icon: "mdi:shield-moon"),
        .init(title: "Disarmed", service: "alarm_disarm", state: "disarmed", icon: "mdi:shield-off"),
    ]

    /// The mode that disarms.
    public static var disarmMode: AlarmMode { alarmModes.first(where: \.needsConfirmation)! }

    /// The mode buttons in the alarm card's order (direction G mockup n3): Disarm first, then Home, Away and Night.
    public static var modeButtons: [AlarmMode] { [disarmMode] + alarmModes.filter { !$0.needsConfirmation } }

    /// The alarm card's title: the mode as a fact ("Armed Home"), or "Alarm Triggered".
    public static func panelTitle(_ state: String?) -> String {
        state == "triggered" ? "Alarm Triggered" : stateText(state)
    }

    /// When the panel entered its state: "Since 9:30 PM" today, "Since Oct 14" before today, or nil when Home
    /// Assistant gave no time (a snapshot or fixture) or the time is in the future.
    public static func sinceText(_ changed: Date, now: Date = .now, calendar: Calendar = .current) -> String? {
        guard changed != .distantPast, changed <= now.addingTimeInterval(60) else { return nil }
        let when = calendar.isDate(changed, inSameDayAs: now)
            ? changed.formatted(date: .omitted, time: .shortened)
            : changed.formatted(.dateTime.month(.abbreviated).day())
        return "Since \(when)"
    }

    /// Alarm state colors as 0...255 RGB (`SECURITY_STATE_META`, securityState.ts:7).
    public static func alarmColor(for state: String?) -> (red: Int, green: Int, blue: Int) {
        switch state {
        case "armed_away", "triggered": (229, 57, 53)
        case "armed_home": (30, 136, 229)
        case "armed_night": (142, 36, 170)
        case "disarmed": (67, 160, 71)
        default: (84, 110, 122)
        }
    }

    /// The alarm icon for a panel state (`alarmIcon`, SecurityDashboard.tsx:49).
    public static func alarmIcon(for state: String?) -> String {
        switch state {
        case "disarmed": "mdi:shield-off"
        case "armed_home": "mdi:shield-home"
        case "armed_night": "mdi:shield-moon"
        case "armed_away": "mdi:shield"
        case "triggered": "mdi:shield-alert"
        default: "mdi:shield-outline"
        }
    }

    // MARK: - Text

    /// Title-cased state (`titleCaseState`): `armed_home` → `Armed Home`; missing → `Unknown`.
    public static func stateText(_ state: String?) -> String { StateText.titleCase(state) }
}
