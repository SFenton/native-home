import Foundation

/// Decides when the day's briefing is written. Home Assistant stays the source: the briefing is frozen once per
/// local day, at or after 00:01, and never rewritten that day; the first one ever is written at once.
/// Source: `ha-sfenton-react-dash@f5a7bf9:src/components/hass/useWeatherDayBriefing.ts:106`.
public enum WeatherBriefingPlanner {
    /// The earliest minute of the day a new briefing is written.
    public static let generationMinute = 1

    /// Whether a new briefing should be generated now.
    public static func shouldGenerate(
        current: WeatherDayBriefing?, now: Date, timeZone: TimeZone, hourly: [WeatherForecast], daily: [WeatherForecast]
    ) -> Bool {
        let dateKey = WeatherDates.dateKey(now, in: timeZone)
        if let current, current.dateKey == dateKey { return false }
        if current != nil {
            let parts = WeatherDates.parts(now, in: timeZone)
            if parts.hour * 60 + parts.minute < generationMinute { return false }
        }
        return covers(hourly, dateKey: dateKey, timeZone: timeZone) || covers(daily, dateKey: dateKey, timeZone: timeZone)
    }

    private static func covers(_ forecasts: [WeatherForecast], dateKey: String, timeZone: TimeZone) -> Bool {
        forecasts.contains { forecast in
            guard let start = forecast.start else { return false }
            return WeatherDates.dateKey(start, in: timeZone) == dateKey
        }
    }
}
