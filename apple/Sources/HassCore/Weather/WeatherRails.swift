import Foundation

/// Rail geometry for the Today row and the seven-day rows.
/// Source: `ha-sfenton-react-dash@f5a7bf9:src/components/hass/WeatherSummary.tsx:457`.
public enum WeatherRails {
    /// A day's low-to-high span positioned inside the week's overall span; day 0 carries the current-temperature marker.
    public static func week(forecast: WeatherForecast, all forecasts: [WeatherForecast], currentTemperature: Double?, index: Int) -> WeatherRailRange? {
        let ranges = forecasts.compactMap { item -> (low: Double, high: Double)? in
            guard let low = item.templow, let high = item.temperature, high >= low else { return nil }
            return (low, high)
        }
        guard let low = forecast.templow, let high = forecast.temperature, high >= low, !ranges.isEmpty else { return nil }
        let minLow = ranges.map(\.low).min() ?? low
        let maxHigh = ranges.map(\.high).max() ?? high
        let spread = maxHigh - minLow
        let current = index == 0 ? currentTemperature : nil
        if spread == 0 {
            return WeatherRailRange(markerPercent: current.map { $0 < low ? 0 : $0 > high ? 100 : 50 }, rangeSizePercent: 0, rangeStartPercent: 50)
        }
        return WeatherRailRange(
            markerPercent: current.map { WeatherPresentation.clampPercent(($0 - minLow) / spread * 100) },
            rangeSizePercent: WeatherPresentation.clampPercent((high - low) / spread * 100),
            rangeStartPercent: WeatherPresentation.clampPercent((low - minLow) / spread * 100)
        )
    }

    /// Today's rail spans the whole track; the marker is the current temperature between low and high.
    public static func hero(forecast: WeatherForecast, currentTemperature: Double?) -> WeatherRailRange? {
        guard let low = forecast.templow, let high = forecast.temperature, high >= low else { return nil }
        let spread = high - low
        if spread == 0 {
            return WeatherRailRange(markerPercent: currentTemperature.map { $0 < low ? 0 : $0 > high ? 100 : 50 }, rangeSizePercent: 0, rangeStartPercent: 50)
        }
        return WeatherRailRange(
            markerPercent: currentTemperature.map { WeatherPresentation.clampPercent(($0 - low) / spread * 100) },
            rangeSizePercent: 100, rangeStartPercent: 0
        )
    }
}
