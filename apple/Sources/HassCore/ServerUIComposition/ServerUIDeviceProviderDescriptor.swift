import Foundation

// MARK: - Authored domain construction

/// Values needed to construct the canonical controllers. Permissions and transports are never authored.
public enum ServerUIDeviceProviderDescriptor: Equatable, Sendable {
    case remote(ServerUIRemoteDescriptor)
    case bedroom(ServerUIBedroomDescriptor)
    case lights(ServerUICustomLightsDescriptor)
    case sprinkler(ServerUISprinklerDescriptor)

    /// The document's model id for this provider, such as `media-remote-config@1`.
    public var model: String {
        switch self {
        case .remote: "media-remote-config@1"
        case .bedroom: "bedroom-config@1"
        case .lights: "custom-lights@1"
        case .sprinkler: "sprinkler-controller@1"
        }
    }

    static func decode(model: String, data: Data) throws -> Self {
        let decoder = JSONDecoder()
        switch model {
        case "media-remote-config@1": return try .remote(decoder.decode(ServerUIRemoteDescriptor.self, from: data))
        case "bedroom-config@1": return try .bedroom(decoder.decode(ServerUIBedroomDescriptor.self, from: ServerUIBedroomDescriptor.withoutRoleTargets(data)))
        case "custom-lights@1": return try .lights(decoder.decode(ServerUICustomLightsDescriptor.self, from: data))
        case "sprinkler-controller@1": return try .sprinkler(decoder.decode(ServerUISprinklerDescriptor.self, from: data))
        default: throw ServerUICompositionError(.unknownVariant, "/model")
        }
    }
}

/// Page cards share a remote's action session without appearing in its authored Devices tab.
public struct ServerUIRemoteDescriptor: Codable, Equatable, Sendable {
    /// A page card that reuses the remote's session.
    public struct Card: Codable, Equatable, Sendable {
        /// The key page nodes use to find this card; it replaces the card's visible title for controller lookup.
        public let key: String
        /// The card's device tile, whose commands are checked like a Devices-tab tile.
        public let configuration: MediaRemoteDevice
    }
    /// The remote's pad, apps and devices.
    public let configuration: MediaRemoteConfig
    /// Page cards that share this remote's session without joining its Devices tab.
    public let cards: [Card]
    private enum CodingKeys: String, CodingKey { case cards }
    /// Creates a descriptor from a remote and its page cards.
    public init(configuration: MediaRemoteConfig, cards: [Card]) {
        self.configuration = configuration
        self.cards = cards
    }
    /// Decodes the remote's configuration and its cards from one object.
    public init(from decoder: any Decoder) throws {
        configuration = try MediaRemoteConfig(from: decoder)
        cards = try decoder.container(keyedBy: CodingKeys.self).decode([Card].self, forKey: .cards)
    }
    /// Encodes the configuration and the cards into one object.
    public func encode(to encoder: any Encoder) throws {
        try configuration.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cards, forKey: .cards)
    }
    /// The configuration a controller is built from: the Devices tab plus the cards, each card titled by its key.
    public var controllerConfiguration: MediaRemoteConfig {
        var config = configuration
        config.devices += cards.map {
            var device = $0.configuration
            // Controller lookup identity is separate from the authored node's visible title.
            device.title = $0.key
            return device
        }
        return config
    }
}

// MARK: - Bedroom

/// One room owns both sides and wake provisioning.
///
/// A document never names the room's scripts or MQTT topic. Those are roles the house document owns
/// (`bedroom.hotFlashBrokerScript`, `bedroom.householdAwayScript`, `bedroom.scheduleSetTopic` and each bed's
/// `tonightScript` and `outsideScheduleScript`), so a decoded descriptor carries them empty and
/// ``controllerEnvironment`` and ``controllerConfiguration(of:)`` fill them from the house document when a controller is built.
public struct ServerUIBedroomDescriptor: Codable, Equatable, Sendable {
    /// One bed side and the provider id its alarms are published under.
    public struct Bed: Codable, Equatable, Sendable {
        /// The id the document's bedroom nodes bind to.
        public let providerId: String
        /// The side's entities. Its script fields are empty until resolved.
        public let configuration: BedSideConfig
    }
    /// The provider id of the wake-light alarms.
    public let wakeProviderId: String
    /// The room's beds.
    public let beds: [Bed]
    /// The shared entities. Its script and topic fields are empty until resolved.
    public let environment: BedSideEnvironment

    /// The shared command targets with the house document's scripts and schedule topic filled in by role.
    public var controllerEnvironment: BedSideEnvironment {
        .init(scheduleEntityId: environment.scheduleEntityId, scheduleSetTopic: MasterBedroom.scheduleSetTopic,
              hotFlashBrokerScript: MasterBedroom.hotFlashBrokerScript, householdAwayEntityId: environment.householdAwayEntityId,
              householdAwayScript: MasterBedroom.householdAwayScript, wakeLight: environment.wakeLight)
    }

    /// `bed`'s configuration with the house document's per-side scripts filled in by side.
    public func controllerConfiguration(of bed: Bed) -> BedSideConfig {
        var configuration = bed.configuration
        let role = MasterBedroom.bed(configuration.side)
        configuration.tonightScript = role.tonightScript
        configuration.outsideScheduleScript = role.outsideScheduleScript
        return configuration
    }

    /// Blanks the script and topic fields a document might carry, so no authored value can reach a controller.
    static func withoutRoleTargets(_ data: Data) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServerUICompositionError(.invalidValue, "/inputs")
        }
        if var environment = root["environment"] as? [String: Any] {
            for key in ["scheduleSetTopic", "hotFlashBrokerScript", "householdAwayScript"] { environment[key] = "" }
            root["environment"] = environment
        }
        if let beds = root["beds"] as? [[String: Any]] {
            root["beds"] = beds.map { bed -> [String: Any] in
                var bed = bed
                if var configuration = bed["configuration"] as? [String: Any] {
                    for key in ["tonightScript", "outsideScheduleScript"] { configuration[key] = "" }
                    bed["configuration"] = configuration
                }
                return bed
            }
        }
        return try JSONSerialization.data(withJSONObject: root)
    }
}

/// A custom-light group, its mode palette and reset policy; no house-global lookup.
public struct ServerUICustomLightsDescriptor: Codable, Equatable, Sendable {
    /// The colors a lighting mode shows in its swatch.
    public struct Palette: Codable, Equatable, Sendable {
        /// The mode the palette belongs to.
        public let mode: String
        /// The mode's swatch colors.
        public let colors: [CustomLightsConfig.RGB]
    }
    /// The control section's title.
    public let sectionTitle: String
    /// The manual-control switch's title.
    public let manualTitle: String
    /// The mode selector's title.
    public let modeTitle: String
    /// The switch that turns manual control on.
    public let manualEntityId: String
    /// The selector that chooses the lighting mode.
    public let modeEntityId: String
    /// The light group that group-wide changes address.
    public let groupEntityId: String
    /// The mode in which individual lights may be edited.
    public let customMode: String
    /// The modes offered when the selector reports no options.
    public let fallbackModes: [String]
    /// The swatch colors of each mode.
    public let palettes: [Palette]
    /// The group's lights.
    public let lights: [CustomLightsConfig.Light]
    /// The color temperature a reset applies.
    public let resetKelvin: Int
    /// The brightness a reset applies.
    public let resetBrightness: Int
    /// The transition, in seconds, a reset applies.
    public let resetTransition: Int

    /// The validated settings, or an error when modes repeat or an entity is malformed.
    public func settings() throws -> CustomLightsSettings {
        guard Set(palettes.map(\.mode)).count == palettes.count else {
            throw CustomLightsSettings.ValidationError.invalidModes
        }
        return try CustomLightsSettings(sectionTitle: sectionTitle, manualTitle: manualTitle, modeTitle: modeTitle,
            manualEntityId: manualEntityId, modeEntityId: modeEntityId, groupEntityId: groupEntityId,
            customMode: customMode, fallbackModes: fallbackModes,
            modeSwatches: Dictionary(palettes.map { ($0.mode, $0.colors) }, uniquingKeysWith: { first, _ in first }),
            lights: lights, resetKelvin: resetKelvin, resetBrightness: resetBrightness, resetTransition: resetTransition)
    }
}

/// The default clock and battery threshold are explicit rather than inherited from another house.
public struct ServerUISprinklerDescriptor: Codable, Equatable, Sendable {
    /// The controller's entities and zones.
    public let controller: SprinklersConfig.Controller
    /// The battery level at or below which the controller reports low battery.
    public let lowBatteryPercent: Double
    /// The `HH:mm` a new start time row begins at.
    public let defaultStartTime: String
}
