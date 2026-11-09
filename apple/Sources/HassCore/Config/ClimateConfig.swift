import Foundation

/// Entity ids, rooms and copy for the Climate page (web `ThermostatPage`,
/// `ha-sfenton-react-dash@9ac2a46:src/pages/DashboardViewPage.tsx:7397`). Spec: `.agents/pages/climate/spec.md`.
public enum ClimateConfig {
    /// Projects a value out of the loaded document's climate section.
    private static func read<T>(_ project: (HouseConfig.ClimateSection) -> T) -> T? {
        HouseConfigSource.active.read { project($0.climate) }
    }

    // Each value below is the server's document, else empty.

    // MARK: - Whole Home

    /// The whole-home virtual thermostat (`GLOBAL_THERMOSTAT_ENTITY_ID`).
    public static var globalThermostatEntityId: String { read { $0.globalThermostatEntityId } ?? "" }
    /// The thermostat the Whole Home dial shows while the house is effectively away.
    public static var ecoAwayThermostatEntityId: String { read { $0.ecoAwayThermostatEntityId } ?? "" }
    /// The physical thermostat (Thermostat Hub pill).
    public static var hubEntityId: String { read { $0.hubEntityId } ?? "" }
    /// Away Mode, the fallback when the effective home/away sensor is unknown.
    public static var awayModeEntityId: String { read { $0.awayModeEntityId } ?? "" }
    /// `Home`, `Away` or another effective mode.
    public static var homeAwayEntityId: String { read { $0.homeAwayEntityId } ?? "" }
    /// Why the effective mode is what it is.
    public static var homeAwayReasonEntityId: String { read { $0.homeAwayReasonEntityId } ?? "" }
    /// Vacation Mode (`VACATION_MODE_ENTITY_ID`, `portedDashboard.ts:402`).
    public static var vacationModeEntityId: String { Vacation.modeEntityId }
    /// Automatic Thermostat: Home Assistant's thermostat control.
    public static var integrationEntityId: String { read { $0.integrationEntityId } ?? "" }
    /// The aggregate contact sensor; the Open Contact Sensors section shows only while it is on.
    public static var contactSensorsEntityId: String { SecurityConfig.contactSensorsEntityId }

    // MARK: - Automation

    public static var ecoModeEntityId: String { read { $0.ecoModeEntityId } ?? "" }
    public static var ecoCriticalEntityId: String { read { $0.ecoCriticalEntityId } ?? "" }
    public static var ecoAwayEntityId: String { read { $0.ecoAwayEntityId } ?? "" }
    public static var predictiveComfortEntityId: String { read { $0.predictiveComfortEntityId } ?? "" }
    public static var predictiveAutoAdjustEntityId: String { read { $0.predictiveAutoAdjustEntityId } ?? "" }
    public static var predictiveHvacModeChangesEntityId: String { read { $0.predictiveHvacModeChangesEntityId } ?? "" }
    public static var predictiveAllowAwayEntityId: String { read { $0.predictiveAllowAwayEntityId } ?? "" }
    public static var predictiveSensorEntityId: String { read { $0.predictiveSensorEntityId } ?? "" }

    // MARK: - Tracking

    public static var trackSelectedEntityId: String { read { $0.trackSelectedEntityId } ?? "" }
    /// The critical-tracking option that enables per-room Critical Protection.
    public static var trackSelectCriticalOption: String { read { $0.trackSelectCriticalOption } ?? "" }

    // MARK: - Colors

    /// Heating tint `#cd5401` (`THERMOSTAT_HEAT_COLOR`).
    public static var heatColorHex: Int { read { $0.heatColorHex } ?? 0 }
    /// Cooling tint `#2c8e98` (`THERMOSTAT_COOL_COLOR`).
    public static var coolColorHex: Int { read { $0.coolColorHex } ?? 0 }

    // MARK: - Rooms

    /// A room with a virtual thermostat (`THERMOSTAT_ROOMS`, `portedDashboard.ts:671`).
    public struct Room: Identifiable, Hashable, Sendable, Codable {
        /// Display title, e.g. `Living Room`.
        public var title: String
        /// Vent covers in display order.
        public var ventEntityIds: [String]
        /// The room's "track only when occupied" switch as the document names it; nil means not configured (``occupiedOnlyEntityId``).
        public var occupiedOnlyOverride: String?

        private enum CodingKeys: String, CodingKey {
            case title, ventEntityIds
            case occupiedOnlyOverride = "occupiedOnlyEntityId"
        }

        /// `living_room` (web `thermostatRoomKey`).
        public var key: String { title.lowercased().replacingOccurrences(of: " ", with: "_") }
        public var id: String { key }

        public var climateEntityId: String { "climate.thermostat_contact_sensors_\(key)_virtual_thermostat" }
        public var temperatureEntityId: String { "sensor.thermostat_contact_sensors_\(key)_temperature" }
        public var occupancyEntityId: String { "sensor.thermostat_contact_sensors_\(key)_occupancy" }
        public var trackEntityId: String { "switch.thermostat_contact_sensors_track_\(key)" }
        public var forceCriticalEntityId: String { "switch.thermostat_contact_sensors_\(key)_force_track_when_critical" }
        /// The document's id, else empty: the switch is not configured and the room's toggle reads as unavailable. The app never
        /// guesses an id from a room's name; the server document carries the field (`tools/house_config_patch.py` fills it).
        public var occupiedOnlyEntityId: String { occupiedOnlyOverride ?? "" }

        /// `Living Room Vents` or `Study Vent`.
        public var ventSectionTitle: String { "\(title) \(ventEntityIds.count > 1 ? "Vents" : "Vent")" }

        /// `Vent 1`, `Vent 2` when the room has several, else `Vent`.
        public func ventTitle(at index: Int) -> String { ventEntityIds.count > 1 ? "Vent \(index + 1)" : "Vent" }

        /// Creates a room; a room with no explicit vents has the single `cover.<key>_vent_vent`.
        public init(_ title: String, vents: [String]? = nil, occupiedOnlyEntityId: String? = nil) {
            self.occupiedOnlyOverride = occupiedOnlyEntityId
            let key = title.lowercased().replacingOccurrences(of: " ", with: "_")
            self.title = title
            self.ventEntityIds = vents?.map { "cover.\(key)_\($0)_vent" } ?? ["cover.\(key)_vent_vent"]
        }
    }

    /// The eleven rooms in web order.
    public static var rooms: [Room] { read { $0.rooms } ?? [] }

    /// Every room's climate entity: the Whole Home dial's range fans out to these.
    public static var roomClimateEntityIds: [String] { rooms.map(\.climateEntityId) }

    /// The room with `key`, if any.
    public static func room(key: String) -> Room? { rooms.first { $0.key == key } }

    // MARK: - Contact sensors

    /// One contact sensor in the Open Contact Sensors section.
    public struct ContactSensor: Identifiable, Hashable, Sendable, Codable {
        public var entityId: String
        public var title: String
        public var id: String { entityId }

        /// A window icon when the title names a window, else a door (web `OpenContactSensorCard`).
        public var isWindow: Bool { title.lowercased().contains("window") }
    }

    /// `THERMOSTAT_CONTACT_SENSORS`: `CONTACT_GROUPS` (`atAGlance.ts:707`) with group-prefixed titles.
    public static var contactSensors: [ContactSensor] { read { $0.contactSensors } ?? [] }

    // MARK: - Copy

    /// Sheet title (`THERMOSTAT_MODAL_TITLE`).
    public static let sheetTitle = "Advanced Controls"

    /// Section descriptions (`THERMOSTAT_SECTION_DESCRIPTIONS`, `DashboardViewPage.tsx:2977`).
    public enum Copy {
        public static let ecoMode = "Eco Mode reduces heating and cooling in inactive rooms. Use the options above to choose critical-temperature protection and what happens when everyone is away."
        public static let forceCritical = "Choose unselected rooms that should still be monitored for unsafe temperatures."
        public static let integration = "Turn Home Assistant's automatic thermostat control on or off."
        public static let predictiveComfort = "Predictive Comfort uses forecast and indoor conditions to recommend earlier changes. Open it to review the recommendation and choose which automatic changes are allowed."
        public static let trackOnlyWhenOccupied = "Choose rooms that should stop contributing demand while empty and rejoin when occupied."
        public static let trackSelected = "Track only the rooms that should participate in normal automatic heating and cooling."
        public static let selectedRoomsOpener = "Choose the rooms used for normal automatic heating and cooling when selected-room tracking is on."
        public static let integrationOffWarning = "Automatic Thermostat is off. Open Advanced Configuration to turn Home Assistant's thermostat control back on."
        public static let noReason = "Home Assistant has not provided an effective-mode reason."
        public static let predictiveAutoAdjust = "Allow Predictive Comfort to adjust the thermostat target before the house leaves the comfort range."
        public static let predictiveHvacModeChanges = "Allow Predictive Comfort to switch between heating and cooling when the recommendation requires it."
        public static let predictiveAllowAway = "Allow predictive thermostat changes while everyone is away. Leave this off to act only while someone is home."
        public static let selectedRoomsDisabled = "Enable Track Selected Rooms before choosing participating rooms."
        public static let criticalDisabled = "Set Eco Mode Critical Tracking to Track Select Critical before choosing protected unselected rooms."
        public static let enableTrackSelectedFirst = "Enable Track Selected Rooms first"
    }

    // MARK: - Sheet tabs

    /// The sheet's tabs (`THERMOSTAT_MODAL_TABS`, `surfaceSemantics.ts:174`).
    public enum Tab: String, CaseIterable, Identifiable, Sendable {
        case rooms, automation, tracking
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .rooms: "Rooms"
            case .automation: "Automation"
            case .tracking: "Tracking"
            }
        }

        /// MDI icon name.
        public var icon: String {
            switch self {
            case .rooms: "mdi:home-thermometer"
            case .automation: "mdi:cog"
            case .tracking: "mdi:motion-sensor"
            }
        }

        public var description: String {
            switch self {
            case .rooms: "View each room's temperature and occupancy, then open a room to adjust its target and check vent position."
            case .automation: "Manage Automatic Thermostat, Eco Mode, and Predictive Comfort settings."
            case .tracking: "Choose which rooms participate in normal comfort, critical protection, or occupancy-only tracking."
            }
        }

        /// The page entry that opens this tab (`ThermostatPageEntries`).
        public var entryTitle: String {
            switch self {
            case .rooms: "Room Thermostats"
            case .automation: "Advanced Configuration"
            case .tracking: "Room Tracking"
            }
        }
    }

    // MARK: - Eco options

    /// One of the two Eco Mode select pages (web `ThermostatOptionDetailPage`).
    public enum EcoOption: String, CaseIterable, Identifiable, Sendable {
        case critical = "eco-critical"
        case away = "eco-away"
        public var id: String { rawValue }

        public var entityId: String { self == .critical ? ClimateConfig.ecoCriticalEntityId : ClimateConfig.ecoAwayEntityId }
        public var title: String { self == .critical ? "Eco Mode Critical Tracking" : "Eco Behavior When Away" }
        public var icon: String { self == .critical ? "mdi:thermometer-alert" : "mdi:leaf-circle" }

        /// The opener's description in the Automation tab.
        public var openerDescription: String {
            self == .critical
                ? "Choose how Eco Mode protects rooms from unsafe temperatures."
                : "Choose whether Eco Mode turns off, uses away targets, or stays active when everyone leaves."
        }

        /// The detail page's description.
        public var pageDescription: String {
            self == .critical
                ? "Choose how Eco Mode protects rooms that are not participating in normal heating and cooling."
                : "Choose what Eco Mode should do when everyone is away."
        }

        /// Shown instead of options when the select has none.
        public var unavailableMessage: String { "\(title) is unavailable until Home Assistant supplies supported options." }
    }

    /// Description and icon for a select option (`THERMOSTAT_OPTION_PRESENTATION`).
    public struct OptionPresentation: Hashable, Sendable {
        public var description: String
        public var icon: String
    }

    public static let optionPresentations: [String: OptionPresentation] = [
        "Disable Eco When Away": .init(description: "Turn Eco Mode off while everyone is away.", icon: "mdi:home-export-outline"),
        "Do Not Track Critical": .init(description: "Do not add temperature-only protection for unselected rooms.", icon: "mdi:thermometer-off"),
        "Keep Eco Active": .init(description: "Keep normal Eco Mode behavior active while everyone is away.", icon: "mdi:leaf"),
        "Track All Critical": .init(description: "Protect every room from unsafe temperatures, even when it is not selected.", icon: "mdi:thermometer-alert"),
        "Track Select Critical": .init(description: "Protect only the unselected rooms chosen in Critical Protection.", icon: "mdi:thermometer-check"),
        "Use Eco Away Targets": .init(description: "Use the wider away temperature range while everyone is away.", icon: "mdi:home-thermometer"),
    ]

    // MARK: - Tracking pages

    /// One of the three room-rule pages in the Tracking tab (web `ThermostatTrackingDetailPage`).
    public enum TrackingPage: String, CaseIterable, Identifiable, Sendable {
        case selectedRooms = "selected-rooms"
        case criticalProtection = "critical-protection"
        case occupiedOnly = "occupied-only"
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .selectedRooms: "Selected Rooms"
            case .criticalProtection: "Critical Protection"
            case .occupiedOnly: "Occupied Only"
            }
        }

        public var icon: String {
            switch self {
            case .selectedRooms: "mdi:home-check"
            case .criticalProtection: "mdi:thermometer-alert"
            case .occupiedOnly: "mdi:motion-sensor"
            }
        }

        /// The opener's description (and the page's, which the web shares).
        public var openerDescription: String {
            switch self {
            case .selectedRooms: Copy.selectedRoomsOpener
            case .criticalProtection: Copy.forceCritical
            case .occupiedOnly: Copy.trackOnlyWhenOccupied
            }
        }

        public var pageDescription: String {
            switch self {
            case .selectedRooms: Copy.trackSelected
            case .criticalProtection: Copy.forceCritical
            case .occupiedOnly: Copy.trackOnlyWhenOccupied
            }
        }

        /// The room switch this page toggles.
        public func entityId(for room: Room) -> String {
            switch self {
            case .selectedRooms: room.trackEntityId
            case .criticalProtection: room.forceCriticalEntityId
            case .occupiedOnly: room.occupiedOnlyEntityId
            }
        }
    }

    // MARK: - HVAC modes

    /// HVAC mode icons (`HVAC_MODE_ICONS`).
    public static let hvacModeIcons: [String: String] = [
        "auto": "mdi:autorenew", "cool": "mdi:snowflake", "dry": "mdi:water-percent", "fan_only": "mdi:fan",
        "heat": "mdi:fire", "heat_cool": "mdi:sun-snowflake-variant", "off": "mdi:power",
    ]

    /// HVAC mode labels that title-casing gets wrong (`HVAC_MODE_LABELS`).
    public static let hvacModeLabels: [String: String] = ["heat_cool": "Heat/Cool"]

    /// Every toggle on the page and in the sheet: these take optimistic values.
    public static var toggleEntityIds: [String] {
        [integrationEntityId, ecoModeEntityId, predictiveComfortEntityId, predictiveAutoAdjustEntityId,
         predictiveHvacModeChangesEntityId, predictiveAllowAwayEntityId, trackSelectedEntityId]
            + rooms.flatMap { [$0.trackEntityId, $0.forceCriticalEntityId, $0.occupiedOnlyEntityId] }
    }
}
