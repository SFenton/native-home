import Foundation

/// Something that can call `weather.get_forecasts` and read the data it returns.
///
/// ``HassConnection`` is the app's implementation; tests pass a fake. Mirrors the `callServiceForResponse`
/// path the inventory feature uses, so the weather store opens no second connection.
@MainActor
public protocol WeatherForecastCalling: AnyObject {
    /// Calls `domain.service` with `return_response: true`.
    /// - Returns: The service's `response` object.
    func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue
}
