import Foundation

/// Which Home Assistant forecast a request asks for (`weather.get_forecasts` `type`).
public enum WeatherForecastKind: String, Codable, Sendable, CaseIterable {
    case daily
    case hourly

    /// How many entries the app keeps: seven days, or the next 24 hours (web `extractForecasts`).
    public var limit: Int { self == .daily ? 7 : 24 }
}
