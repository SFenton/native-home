import Foundation

/// Everything the briefing generator reads.
public struct WeatherDayBriefingInput: Sendable {
    public var aqi: Double?
    public var daily: [WeatherForecast]
    public var generatedAt: Date
    public var hourly: [WeatherForecast]
    public var precipitationUnit: String?
    public var sunrise: String?
    public var sunset: String?
    public var temperatureUnit: String?
    public var timeZone: TimeZone
    public var windSpeedUnit: String?

    public init(
        aqi: Double? = nil, daily: [WeatherForecast] = [], generatedAt: Date, hourly: [WeatherForecast] = [],
        precipitationUnit: String? = nil, sunrise: String? = nil, sunset: String? = nil, temperatureUnit: String? = nil,
        timeZone: TimeZone = .current, windSpeedUnit: String? = nil
    ) {
        self.aqi = aqi
        self.daily = daily
        self.generatedAt = generatedAt
        self.hourly = hourly
        self.precipitationUnit = precipitationUnit
        self.sunrise = sunrise
        self.sunset = sunset
        self.temperatureUnit = temperatureUnit
        self.timeZone = timeZone
        self.windSpeedUnit = windSpeedUnit
    }
}
