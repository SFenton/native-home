import Foundation

// MARK: - Bathroom fans

/// One bathroom fan: a switch with an automation lock and an off timer, all driven through one script
/// (web `BathroomFanConfig`, `ha-sfenton-react-dash@9ac2a46:src/constants/bathroomFans.ts`).
public struct BathroomFanConfig: Hashable, Sendable, Identifiable, Codable {
    public var id: String
    /// The room, used in the sheet title ("Guest Bathroom Fan").
    public var roomTitle: String
    /// `input_boolean` on while the timer's auto-unlock is set.
    public var autoUnlockEntityId: String
    /// `input_datetime` holding when the timer ends.
    public var deadlineEntityId: String
    /// `input_boolean` on while the automation lock holds the fan.
    public var lockEntityId: String
    /// `input_boolean` on while a timer is pending.
    public var pendingEntityId: String
    /// The fan's switch.
    public var powerEntityId: String
    /// The `script.<name>` every command goes through.
    public var scriptService: String
    /// The `timer` entity the script runs (read-only here).
    public var timerEntityId: String

    /// Creates a fan.
    public init(id: String, roomTitle: String, autoUnlockEntityId: String, deadlineEntityId: String, lockEntityId: String,
                pendingEntityId: String, powerEntityId: String, scriptService: String, timerEntityId: String) {
        self.id = id
        self.roomTitle = roomTitle
        self.autoUnlockEntityId = autoUnlockEntityId
        self.deadlineEntityId = deadlineEntityId
        self.lockEntityId = lockEntityId
        self.pendingEntityId = pendingEntityId
        self.powerEntityId = powerEntityId
        self.scriptService = scriptService
        self.timerEntityId = timerEntityId
    }

    /// The four entities the controls show optimistically.
    public var optimisticEntityIds: [String] { [powerEntityId, lockEntityId, pendingEntityId, autoUnlockEntityId] }
}

public extension BathroomFanConfig {


    /// Every fan: the server's document.
    static var all: [BathroomFanConfig] { HouseConfigSource.active.read { $0.roomDevices.bathroomFans } ?? [] }

    /// The fan whose switch is `entityId` (web `bathroomFanForPowerEntity`).
    static func forPowerEntity(_ entityId: String) -> BathroomFanConfig? {
        all.first { $0.powerEntityId == entityId }
    }
}

// MARK: - Air purifiers

/// An air purifier, whose entities derive from its PM2.5 sensor unless the document names them
/// (web `derivedAirPurifierEntityIds`, `src/components/hass/airQualityState.ts`).
///
/// The document may carry the four derived ids (`aqiEntityId`, `autoModeEntityId`, `fanEntityId`, `modeEntityId`), each optional.
/// A missing fan id is empty (not configured: the power disc and speed control stay off) rather than a guess from the sensor's
/// name; the server document carries every field (`tools/house_config_patch.py` fills them).
public struct AirPurifierConfig: Hashable, Sendable, Identifiable, Codable {
    /// The room, used in the sheet title and accessibility labels.
    public var roomTitle: String
    /// e.g. `sensor.demo_purifier_pm2_5`.
    public var pm25EntityId: String

    private var aqi: String?
    private var autoMode: String?
    private var fan: String?
    private var mode: String?

    public var id: String { pm25EntityId }

    private enum CodingKeys: String, CodingKey {
        case roomTitle, pm25EntityId
        case aqi = "aqiEntityId", autoMode = "autoModeEntityId", fan = "fanEntityId", mode = "modeEntityId"
    }

    /// Creates a purifier from its PM2.5 sensor; each id left nil derives from the sensor's name.
    public init(roomTitle: String, pm25EntityId: String, aqiEntityId: String? = nil, autoModeEntityId: String? = nil,
                fanEntityId: String? = nil, modeEntityId: String? = nil) {
        self.roomTitle = roomTitle
        self.pm25EntityId = pm25EntityId
        self.aqi = aqiEntityId
        self.autoMode = autoModeEntityId
        self.fan = fanEntityId
        self.mode = modeEntityId
    }

    /// The shared prefix, e.g. `office_air_purifier`.
    var base: String {
        var base = pm25EntityId
        if base.hasPrefix("sensor.") { base.removeFirst("sensor.".count) }
        if base.hasSuffix("_pm2_5") { base.removeLast("_pm2_5".count) }
        return base
    }

    /// The document's id, else `sensor.<base>_air_quality_index`.
    public var aqiEntityId: String { aqi ?? "sensor.\(base)_air_quality_index" }
    /// The document's id, else `select.<base>_auto_mode`.
    public var autoModeEntityId: String { autoMode ?? "select.\(base)_auto_mode" }
    /// The document's id, else empty (not configured).
    public var fanEntityId: String { fan ?? "" }
    /// The document's id, else `select.<base>_fan_mode`.
    public var modeEntityId: String { mode ?? "select.\(base)_fan_mode" }
}

public extension AirPurifierConfig {
    /// The purifiers on the web room pages (`src/constants/roomPages.ts`): the server's document.
    static var all: [AirPurifierConfig] { HouseConfigSource.active.read { $0.roomDevices.airPurifiers } ?? [] }

    /// The purifier a room page names by its PM2.5 sensor.
    static func forPM25Entity(_ entityId: String) -> AirPurifierConfig? {
        all.first { $0.pm25EntityId == entityId }
    }
}

// MARK: - Humidifiers

/// A humidifier's operating mode; raw values are the `select` options Home Assistant uses.
public enum HumidifierMode: String, CaseIterable, Hashable, Sendable {
    case manual = "Manual"
    case targetHumidity = "Target Humidity"
    case sleep = "Sleep"

    /// What the app calls the mode (web `HUMIDIFIER_MODES` labels).
    public var title: String {
        switch self {
        case .manual: "Manual"
        case .targetHumidity: "Auto Humidity"
        case .sleep: "Sleep"
        }
    }

    /// Web MDI icon.
    public var icon: String {
        switch self {
        case .manual: "mdi:water"
        case .targetHumidity: "mdi:fan-auto"
        case .sleep: "mdi:weather-night"
        }
    }
}

/// A humidifier and its scheduling helpers (web `HumidifierConfig`, `src/constants/humidifiers.ts`).
public struct HumidifierConfig: Hashable, Sendable, Identifiable, Codable {
    public var id: String
    public var title: String
    public var applyProfileScriptService: String
    public var currentHumidityEntityId: String
    public var currentTemperatureEntityId: String
    public var displayEntityId: String
    public var humidifyingEntityId: String
    public var mistLevelEntityId: String
    public var modeEntityId: String
    public var powerEntityId: String
    public var scheduleEnabledEntityId: String
    public var scheduleEntityId: String
    /// The `schedule` helper's id for `schedule/list` and `schedule/update`.
    public var scheduleId: String
    public var setLevelScriptService: String
    public var tankRemovedEntityId: String
    public var targetHumidityEntityId: String
    public var timerMinutesEntityId: String
    public var timerRemainingEntityId: String
    public var vacationModeEntityId: String
    public var warmLevelEntityId: String
    public var waterLowEntityId: String

    /// Entities whose values the controls show optimistically.
    public var optimisticEntityIds: [String] {
        [powerEntityId, modeEntityId, mistLevelEntityId, targetHumidityEntityId, warmLevelEntityId, timerMinutesEntityId,
         displayEntityId, scheduleEnabledEntityId]
    }

    /// A mist preset (web `HUMIDIFIER_MIST_PRESETS`).
    public struct Preset: Hashable, Sendable, Identifiable {
        public var title: String
        public var icon: String
        public var value: Int
        public var id: Int { value }
    }

    /// Low 2, Medium 5, High 8, Max 9.
    public static let mistPresets: [Preset] = [
        .init(title: "Low", icon: "mdi:fan-speed-1", value: 2),
        .init(title: "Medium", icon: "mdi:fan-speed-2", value: 5),
        .init(title: "High", icon: "mdi:fan-speed-3", value: 8),
        .init(title: "Max", icon: "mdi:fan", value: 9),
    ]

    /// Off 0 to High 3 (web `HUMIDIFIER_WARM_LEVELS`).
    public static let warmLevels: [Preset] = [
        .init(title: "Off", icon: "mdi:power", value: 0),
        .init(title: "Low", icon: "mdi:fire", value: 1),
        .init(title: "Medium", icon: "mdi:fire", value: 2),
        .init(title: "High", icon: "mdi:fire", value: 3),
    ]
}

public extension HumidifierConfig {
    /// Every humidifier: the server's document.
    static var all: [HumidifierConfig] { HouseConfigSource.active.read { $0.roomDevices.humidifiers } ?? [] }

    /// The humidifier whose power switch is `entityId` (web `humidifierForPowerEntity`).
    static func forPowerEntity(_ entityId: String) -> HumidifierConfig? {
        all.first { $0.powerEntityId == entityId }
    }
}

// MARK: - Grill

/// The Traeger grill sheet (web `GrillModalContent.tsx`).
public struct GrillConfig: Hashable, Sendable, Codable {
    /// One detail card.
    public struct Detail: Hashable, Sendable, Identifiable, Codable {
        public var title: String
        public var entityId: String
        public var icon: String
        public var id: String { entityId }
        /// Switches can be tapped; sensors only show their value.
        public var isSwitch: Bool { entityId.hasPrefix("switch.") }
    }

    public var title: String
    /// The room, shown before the title in the sheet ("Back Deck: Patio Grill").
    public var roomTitle: String
    public var stateEntityId: String
    public var details: [Detail]

    /// Patio Grill (`GRILL_DETAILS`): the server's first grill.
    public static var bearGrills: GrillConfig { HouseConfigSource.active.read { $0.roomDevices.grills.first }.flatMap { $0 } ?? GrillConfig(title: "", roomTitle: "", stateEntityId: "", details: []) }
}
