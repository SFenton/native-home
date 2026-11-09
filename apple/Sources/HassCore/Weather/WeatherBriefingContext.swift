import Foundation

/// The inputs from entities that the day briefing reads besides the forecasts.
public struct WeatherBriefingContext: Equatable, Sendable {
    public var aqi: Double?
    public var precipitationUnit: String?
    public var sunrise: String?
    public var sunset: String?
    public var temperatureUnit: String?
    public var windSpeedUnit: String?

    public init(aqi: Double? = nil, precipitationUnit: String? = nil, sunrise: String? = nil, sunset: String? = nil, temperatureUnit: String? = nil, windSpeedUnit: String? = nil) {
        self.aqi = aqi
        self.precipitationUnit = precipitationUnit
        self.sunrise = sunrise
        self.sunset = sunset
        self.temperatureUnit = temperatureUnit
        self.windSpeedUnit = windSpeedUnit
    }

    /// Builds the context from the weather, air-quality and sun entities.
    public init(current: WeatherCurrent, aqiState: String?, sun: WeatherSunInput?) {
        self.init(
            aqi: aqiState.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) },
            precipitationUnit: current.precipitationUnit, sunrise: sun?.nextRising, sunset: sun?.nextSetting,
            temperatureUnit: current.temperatureUnit, windSpeedUnit: current.windSpeedUnit
        )
    }
}
