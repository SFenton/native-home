import Foundation

// MARK: - Injected domain descriptors

/// Explicit targets for the canonical room-device controllers. No house lookup or derived IDs.
public enum ServerUIRoomDeviceDescriptor: Equatable, Sendable {
    case purifier(AirPurifierConfig)
    case fan(BathroomFanConfig)
    case grill(GrillConfig)
    case humidifier(HumidifierConfig)

    /// Narrow wire model and capability identity.
    public var model: String {
        switch self {
        case .purifier: "air-purifier@1"
        case .fan: "bathroom-fan@1"
        case .grill: "grill@1"
        case .humidifier: "humidifier@1"
        }
    }

    /// The closed, domain-checked target fields accepted in `inputs`.
    static func domains(_ model: String) -> [String: String] {
        switch model {
        case "air-purifier@1":
            ["pm25EntityId": "sensor", "aqiEntityId": "sensor", "autoModeEntityId": "select",
             "fanEntityId": "fan", "modeEntityId": "select"]
        case "bathroom-fan@1":
            ["autoUnlockEntityId": "input_boolean", "deadlineEntityId": "input_datetime",
             "lockEntityId": "input_boolean", "pendingEntityId": "input_boolean", "powerEntityId": "switch",
             "timerEntityId": "timer"]
        case "grill@1": ["stateEntityId": "sensor"]
        case "humidifier@1":
            ["currentHumidityEntityId": "sensor", "currentTemperatureEntityId": "sensor", "displayEntityId": "switch",
             "humidifyingEntityId": "binary_sensor", "mistLevelEntityId": "number", "modeEntityId": "select",
             "powerEntityId": "switch", "scheduleEnabledEntityId": "input_boolean", "scheduleEntityId": "schedule",
             "tankRemovedEntityId": "binary_sensor", "targetHumidityEntityId": "number", "timerMinutesEntityId": "number",
             "timerRemainingEntityId": "sensor", "vacationModeEntityId": "input_boolean",
             "warmLevelEntityId": "number", "waterLowEntityId": "binary_sensor"]
        default: [:]
        }
    }
}

// MARK: - Atomic presentation contract

/// One native atom, never a sheet, tab, collection or feature controller.
public struct ServerUIRoomDeviceControl: Equatable, Sendable {
    public let node: ServerUICompositionDocument.Node
    public let sourceId: String
    public let icon: ServerUICompositionDocument.Symbol
    public let control: Kind
    public let family: Family
    public let options: [Option]
    public let labels: Labels
    public let detailEntityId: String?
    public let info: Info?
    public let initialMinutes: Int?
    public let modalId: String?
    public let fanRail: FanRail?
    /// Reuses Shell's existing presentation action, not a feature/page dispatcher.
    public var navigationAction: ServerUICompositionDocument.Action? {
        modalId.map { .present(modalId: $0, arguments: .init(), ifPresented: .reject) }
    }
    /// The authored family choices.
    public enum Family: String, Sendable { case neutral, air, security, cooking, water }

    /// Provider-owned command semantics; authored order, labels and icons remain values.
    public enum Kind: String, CaseIterable, Sendable {
        case purifierMode = "purifier-mode", purifierAuto = "purifier-auto", purifierSpeed = "purifier-speed"
        case fanPower = "fan-power", fanLock = "fan-lock", fanTimer = "fan-timer", fanRoom = "fan-room"
        case grillDetail = "grill-detail"
        case humidifierMode = "humidifier-mode", humidifierPresets = "humidifier-presets", humidifierWarm = "humidifier-warm"
        case humidifierMist = "humidifier-mist", humidifierTarget = "humidifier-target"
        case humidifierPower = "humidifier-power", humidifierDisplay = "humidifier-display"
        case humidifierTimer = "humidifier-timer", humidifierInfo = "humidifier-info"
        case humidifierScheduling = "humidifier-scheduling"

        public var model: String {
            switch self {
            case .purifierMode, .purifierAuto, .purifierSpeed: "air-purifier@1"
            case .fanPower, .fanLock, .fanTimer, .fanRoom: "bathroom-fan@1"
            case .grillDetail: "grill@1"
            default: "humidifier@1"
            }
        }

        public var hasOptions: Bool {
            switch self {
            case .purifierMode, .purifierAuto, .purifierSpeed, .fanTimer,
                 .humidifierMode, .humidifierPresets, .humidifierWarm: true
            default: false
            }
        }
    }

    /// The authored option.
    public struct Option: Equatable, Hashable, Sendable {
        public let value: String
        public let label: String
        /// A timer option's fully authored primary action title.
        public let actionLabel: String?

        /// Creates a option.
        public init(value: String, label: String, actionLabel: String? = nil) {
            self.value = value
            self.label = label
            self.actionLabel = actionLabel
        }
    }

    /// Authored appearance for the two canonical fan actions; targets and semantics remain provider-owned.
    public struct FanRail: Equatable, Sendable {
        public let order: [String]
        public let powerIcon: ServerUICompositionDocument.Symbol
        public let lockedIcon: ServerUICompositionDocument.Symbol
        public let unlockedIcon: ServerUICompositionDocument.Symbol
        public let powerOn: String
        public let powerOff: String
        public let lock: String
        public let unlock: String
        public let locked: String
    }

    /// Copy is explicit even in loading, failure and unavailable phases.
    public struct Labels: Equatable, Sendable {
        public let loading: String
        public let unavailable: String
        public let failed: String
        public let on: String
        public let off: String
        public let action: String
        public let cancel: String
        public let footnote: String
        public let sleep: String
        public let tankFault: String
        public let waterFault: String
        public let invalidTarget: String
        public let highTarget: String
    }

    /// The authored info choices.
    public enum Info: String, CaseIterable, Sendable {
        case output, water, tank, mode, display, warm, humidity, temperature, mist, timer
    }
}
