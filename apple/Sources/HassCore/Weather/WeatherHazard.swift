import Foundation

/// A weather hazard the Today headline can lead with.
public enum WeatherHazard: String, Codable, Sendable, CaseIterable {
    case damagingWind, denseFog, extremeCold, extremeHeat, freeze, hail, heat, heavyRain, heavySnow
    case highUv, ice, poorAir, severeStorms, snow, wind

    /// The hazard's headline copy key.
    public var headlineKey: String { "briefing.hazard.\(rawValue)" }

    var baseSeverity: WeatherBriefingSeverity {
        switch self {
        case .damagingWind, .extremeCold, .extremeHeat, .heavySnow, .ice, .severeStorms: .alert
        case .denseFog, .hail, .heavyRain, .poorAir, .snow: .caution
        case .freeze, .heat, .highUv, .wind: .notable
        }
    }

    /// Web MDI icon name.
    public var icon: String {
        switch self {
        case .damagingWind, .wind: "mdi:weather-windy"
        case .denseFog: "mdi:weather-fog"
        case .extremeCold: "mdi:snowflake-alert"
        case .extremeHeat: "mdi:thermometer-alert"
        case .freeze: "mdi:snowflake"
        case .hail: "mdi:weather-hail"
        case .heat: "mdi:thermometer-high"
        case .heavyRain: "mdi:weather-pouring"
        case .heavySnow: "mdi:weather-snowy-heavy"
        case .highUv: "mdi:weather-sunny-alert"
        case .ice: "mdi:car-traction-control"
        case .poorAir: "mdi:air-filter"
        case .severeStorms: "mdi:weather-lightning"
        case .snow: "mdi:weather-snowy"
        }
    }

    /// Severity first, then meteorological priority inside a band (lowest index first).
    static let priority: [WeatherHazard] = [
        .severeStorms, .ice, .heavySnow, .damagingWind, .extremeCold, .extremeHeat, .hail, .heavyRain,
        .snow, .poorAir, .denseFog, .wind, .heat, .freeze, .highUv,
    ]
}
