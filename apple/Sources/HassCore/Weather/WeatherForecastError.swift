import Foundation

/// Why a forecast response could not be used.
public struct WeatherForecastError: Error, Equatable, LocalizedError, Sendable {
    /// The user-facing message (`forecast.dailyError` / `forecast.hourlyError`).
    public var message: String
    public var errorDescription: String? { message }

    /// The malformed-response error for a forecast kind.
    public static func malformed(_ kind: WeatherForecastKind) -> WeatherForecastError {
        WeatherForecastError(message: WeatherCopy.forecastFailure(kind))
    }

    /// The websocket dropped or was not ready; the store retries quietly instead of showing an error.
    public static let connectionLost = WeatherForecastError(message: "Connection lost")
}
