import Foundation

/// One forecast kind's data and loading state, as the card and sheet read it.
///
/// While a refresh runs, ``forecasts`` keeps the last good data, so neither screen ever blanks.
public struct WeatherForecastFeed: Equatable, Sendable {
    /// Where the feed is in its life (web `WEATHER_FORECAST_PHASE`).
    public enum Phase: String, Codable, Sendable {
        case idle, loading, ready, empty, error
    }

    /// The message of the latest failure, cleared by the next success.
    public var error: String?
    public var forecasts: [WeatherForecast]
    /// A request is in flight.
    public var refreshing: Bool
    public var phase: Phase
    /// When ``forecasts`` last arrived or was restored from disk.
    public var updatedAt: Date?

    /// An empty feed.
    public init(
        error: String? = nil, forecasts: [WeatherForecast] = [], refreshing: Bool = false, phase: Phase = .idle, updatedAt: Date? = nil
    ) {
        self.error = error
        self.forecasts = forecasts
        self.refreshing = refreshing
        self.phase = phase
        self.updatedAt = updatedAt
    }

    /// Idle and loading both mean a forecast is still expected, including while Home Assistant reconnects.
    public var isPending: Bool { phase == .idle || phase == .loading }

    /// Draw placeholders: there is nothing to show yet and something is on its way.
    public var showsPlaceholders: Bool { forecasts.isEmpty && (refreshing || isPending) }
}
