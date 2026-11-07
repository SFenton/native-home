import Foundation

/// One reading of everything the device sensors report, gathered by a platform source and turned into sensors by
/// ``MobileAppSensorProvider``s. Nil means "not available here" (no Wi-Fi entitlement, no geocode yet); that
/// provider then reports nothing rather than a made-up state.
public struct DeviceStatus: Equatable, Sendable {
    /// Battery level and charging state.
    public var battery: Battery?
    /// The current network path.
    public var network: Network?
    /// Location permission.
    public var locationPermission: LocationPermission?
    /// The app's marketing version (`0.1.0`).
    public var appVersion: String?
    /// Audio output port names ("Built-in Speaker", "Bluetooth A2DP").
    public var audioOutputs: [String]?
    /// What sent the last location update.
    public var lastUpdateTrigger: LocationTrigger?
    /// Reverse-geocoded address for the last fix.
    public var place: GeocodedPlace?
    /// Whether a Focus is on.
    public var isFocused: Bool?

    /// Creates a reading.
    public init(battery: Battery? = nil, network: Network? = nil, locationPermission: LocationPermission? = nil,
                appVersion: String? = nil, audioOutputs: [String]? = nil,
                lastUpdateTrigger: LocationTrigger? = nil, place: GeocodedPlace? = nil, isFocused: Bool? = nil) {
        self.battery = battery
        self.network = network
        self.locationPermission = locationPermission
        self.appVersion = appVersion
        self.audioOutputs = audioOutputs
        self.lastUpdateTrigger = lastUpdateTrigger
        self.place = place
        self.isFocused = isFocused
    }

    /// Battery level and charging state.
    public struct Battery: Equatable, Sendable {
        /// Charging state, with the official app's wording.
        public enum State: String, Sendable {
            case charging = "Charging"
            case full = "Full"
            case notCharging = "Not Charging"
            case unknown = "Unknown"
        }

        /// 0–100.
        public var level: Int
        /// Charging state.
        public var state: State
        /// Low Power Mode.
        public var isLowPowerMode: Bool

        /// Creates a battery reading; the level is clamped to 0–100.
        public init(level: Int, state: State, isLowPowerMode: Bool = false) {
            self.level = min(max(level, 0), 100)
            self.state = state
            self.isLowPowerMode = isLowPowerMode
        }
    }

    /// The current network path.
    public struct Network: Equatable, Sendable {
        /// The connection type, with the official app's wording.
        public enum Connection: String, Sendable {
            case wifi = "Wi-Fi"
            case cellular = "Cellular"
            case ethernet = "Ethernet"
            case none = "No Connection"
            case unknown = "Unknown"

            /// The official app's icon for this type.
            public var icon: String {
                switch self {
                case .wifi: "mdi:wifi"
                case .cellular: "mdi:signal"
                case .ethernet: "mdi:ethernet"
                case .none: "mdi:sim-off"
                case .unknown: "mdi:help-circle"
                }
            }
        }

        /// The connection type.
        public var connection: Connection
        /// The Wi-Fi network name, when the app may read it.
        public var ssid: String?
        /// The access point's MAC address, when the app may read it.
        public var bssid: String?
        /// Whether the app may read SSID and BSSID at all (the Access Wi-Fi Information entitlement plus location
        /// permission); when false the SSID and BSSID sensors are not reported.
        public var canReadWiFi: Bool

        /// Creates a network reading.
        public init(connection: Connection, ssid: String? = nil, bssid: String? = nil, canReadWiFi: Bool = true) {
            self.connection = connection
            self.ssid = ssid
            self.bssid = bssid
            self.canReadWiFi = canReadWiFi
        }
    }
}

/// A reverse-geocoded address (the fields of `CLPlacemark` the official app reports).
public struct GeocodedPlace: Equatable, Sendable {
    public var name: String?
    public var subThoroughfare: String?
    public var thoroughfare: String?
    public var subLocality: String?
    public var locality: String?
    public var subAdministrativeArea: String?
    public var administrativeArea: String?
    public var postalCode: String?
    public var country: String?
    public var isoCountryCode: String?
    public var timeZone: String?
    public var inlandWater: String?
    public var ocean: String?
    public var areasOfInterest: [String]
    /// The fix that was geocoded, `[latitude, longitude]`.
    public var coordinate: [Double]?
    /// Names of the zones the fix is inside, smallest first.
    public var zones: [String]

    /// Creates a place.
    public init(name: String? = nil, subThoroughfare: String? = nil, thoroughfare: String? = nil,
                subLocality: String? = nil, locality: String? = nil, subAdministrativeArea: String? = nil,
                administrativeArea: String? = nil, postalCode: String? = nil, country: String? = nil,
                isoCountryCode: String? = nil, timeZone: String? = nil, inlandWater: String? = nil,
                ocean: String? = nil, areasOfInterest: [String] = [], coordinate: [Double]? = nil, zones: [String] = []) {
        self.name = name
        self.subThoroughfare = subThoroughfare
        self.thoroughfare = thoroughfare
        self.subLocality = subLocality
        self.locality = locality
        self.subAdministrativeArea = subAdministrativeArea
        self.administrativeArea = administrativeArea
        self.postalCode = postalCode
        self.country = country
        self.isoCountryCode = isoCountryCode
        self.timeZone = timeZone
        self.inlandWater = inlandWater
        self.ocean = ocean
        self.areasOfInterest = areasOfInterest
        self.coordinate = coordinate
        self.zones = zones
    }

    /// A mailing-address style string: street, then city, region and postal code, then country.
    /// - Returns: nil when no address field is known.
    public var mailingAddress: String? {
        let street = [subThoroughfare, thoroughfare].compactMap { $0 }.joined(separator: " ")
        let cityLine = [locality, [administrativeArea, postalCode].compactMap { $0 }.joined(separator: " ")]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        let lines = [street, cityLine, country ?? ""].filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
