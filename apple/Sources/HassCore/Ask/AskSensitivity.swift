import Foundation

// MARK: - Sensitivity

/// How private an entity's answer is.
///
/// The class decides what an answer may reveal on a locked phone. The App Intent that calls the answerer owns the policy
/// (one authentication policy per intent); this type only labels.
public enum AskSensitivity: String, Codable, Sendable, Comparable {
    /// Everyday: fine on a locked phone.
    case everyday
    /// Reveals who is home or where. The caller's `allowing` value decides whether a locked phone may hear it.
    case home
    /// Security state (locks, alarm, cameras, doors and windows, vehicle): after unlock only.
    case security

    private var rank: Int {
        switch self {
        case .everyday: 0
        case .home: 1
        case .security: 2
        }
    }

    public static func < (lhs: AskSensitivity, rhs: AskSensitivity) -> Bool { lhs.rank < rhs.rank }
}

/// The rules that label an entity, as data (generic defaults; platform names for one house come from configuration).
public struct AskSensitivityRules: Codable, Sendable, Equatable {
    /// Domains that are security state.
    public var securityDomains: Set<String>
    /// Device classes of a `binary_sensor` (or cover) that are security state.
    public var securityDeviceClasses: Set<String>
    /// Device classes that reveal presence.
    public var homeDeviceClasses: Set<String>
    /// Domains that reveal presence.
    public var homeDomains: Set<String>
    /// Platforms whose every entity is security state (a vehicle integration, for example). House specific.
    public var securityPlatforms: Set<String>
    /// Words in a name that reveal presence (`bed`, `presence`, `away`).
    public var homeNameWords: Set<String>
    /// Attribute names that never enter an annotator line (a cause note); the entity lines write a fixed set of attributes.
    public var neverAttributes: Set<String>

    /// The defaults.
    public init(
        securityDomains: Set<String> = ["lock", "alarm_control_panel", "camera", "siren"],
        securityDeviceClasses: Set<String> = [
            "door", "window", "garage_door", "garage", "opening", "tamper", "smoke", "carbon_monoxide", "gas", "vibration",
        ],
        homeDeviceClasses: Set<String> = ["occupancy", "motion", "presence"],
        homeDomains: Set<String> = ["person", "vacuum"],
        securityPlatforms: Set<String> = [],
        homeNameWords: Set<String> = ["bed", "presence", "away"],
        neverAttributes: Set<String> = [
            "latitude", "longitude", "gps_accuracy", "device_trackers", "user_id", "access_token", "entity_picture", "source",
        ]
    ) {
        self.securityDomains = securityDomains
        self.securityDeviceClasses = securityDeviceClasses
        self.homeDeviceClasses = homeDeviceClasses
        self.homeDomains = homeDomains
        self.securityPlatforms = securityPlatforms
        self.homeNameWords = homeNameWords
        self.neverAttributes = neverAttributes
    }

    /// Decodes with every missing key falling back to its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AskSensitivityRules()
        securityDomains = try c.decodeIfPresent(Set<String>.self, forKey: .securityDomains) ?? d.securityDomains
        securityDeviceClasses = try c.decodeIfPresent(Set<String>.self, forKey: .securityDeviceClasses) ?? d.securityDeviceClasses
        homeDeviceClasses = try c.decodeIfPresent(Set<String>.self, forKey: .homeDeviceClasses) ?? d.homeDeviceClasses
        homeDomains = try c.decodeIfPresent(Set<String>.self, forKey: .homeDomains) ?? d.homeDomains
        securityPlatforms = try c.decodeIfPresent(Set<String>.self, forKey: .securityPlatforms) ?? d.securityPlatforms
        homeNameWords = try c.decodeIfPresent(Set<String>.self, forKey: .homeNameWords) ?? d.homeNameWords
        neverAttributes = try c.decodeIfPresent(Set<String>.self, forKey: .neverAttributes) ?? d.neverAttributes
    }

    /// The class of one entity.
    /// - Parameters:
    ///   - domain: The entity's domain.
    ///   - deviceClass: Its device class, when it has one.
    ///   - platform: Its integration platform, when known.
    ///   - nameWords: The lower-case words of its name.
    public func classify(domain: String, deviceClass: String?, platform: String?, nameWords: Set<String>) -> AskSensitivity {
        if securityDomains.contains(domain) { return .security }
        if let platform, securityPlatforms.contains(platform) { return .security }
        if let deviceClass {
            if (domain == "binary_sensor" || domain == "cover"), securityDeviceClasses.contains(deviceClass) { return .security }
            if domain == "binary_sensor", homeDeviceClasses.contains(deviceClass) { return .home }
        }
        if homeDomains.contains(domain) { return .home }
        if ["sensor", "binary_sensor", "input_boolean", "switch"].contains(domain), !nameWords.isDisjoint(with: homeNameWords) { return .home }
        return .everyday
    }
}
