import Foundation

/// The six-hour humidity and cloud-cover series.
/// Source: `ha-sfenton-react-dash@f5a7bf9:src/components/hass/WeatherHourlyMetricTiles.tsx:60`.
public enum WeatherHourlyMetrics {
    /// Hours each small chart shows.
    public static let hours = 6

    /// Points for the first six hours; values clamp to 0...100.
    public static func points(_ forecasts: [WeatherForecast]) -> [HourlyMetricPoint] {
        forecasts.prefix(hours).enumerated().map { index, forecast in
            HourlyMetricPoint(
                cloudCover: forecast.cloudCoverage.flatMap { $0.isFinite ? min(100, max(0, $0)) : nil },
                humidity: forecast.humidity.flatMap { $0.isFinite ? min(100, max(0, $0)) : nil },
                index: index, time: forecast.start
            )
        }
    }
}
