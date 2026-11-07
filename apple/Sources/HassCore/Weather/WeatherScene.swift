import Foundation

/// The atmosphere behind the weather sheet (web `WeatherScene`).
public enum WeatherScene: String, Sendable, CaseIterable {
    case sunny, night, clouds, fog, rain, storm, snow, wind, exceptional, neutral

    /// Maps a condition to its scene; `isNight` turns a sunny sky into the night scene (`weatherSceneForCondition`).
    public init(condition: String?, isNight: Bool = false) {
        switch condition {
        case "clear-night": self = .night
        case "sunny": self = isNight ? .night : .sunny
        case "partlycloudy", "cloudy": self = .clouds
        case "fog": self = .fog
        case "rainy", "pouring": self = .rain
        case "lightning", "lightning-rainy", "hail": self = .storm
        case "snowy", "snowy-rainy": self = .snow
        case "windy", "windy-variant": self = .wind
        case "exceptional": self = .exceptional
        default: self = .neutral
        }
    }
}
