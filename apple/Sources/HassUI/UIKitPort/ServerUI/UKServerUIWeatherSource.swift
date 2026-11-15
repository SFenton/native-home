#if os(iOS)
import HassCore
import Observation
import UIKit

// MARK: - Injected forecast adapter

/// Shares the canonical forecast store/connection across composed panels, with balanced visible consumers.
@MainActor
@Observable
final class UKServerUIWeatherSource {
    let configuration: ServerUICompositionDocument.HomeWeather
    let driver: UKWeatherForecastDriver
    var selectedMode: WeatherHourlyMode?
    @ObservationIgnored private let context: UKContext
    @ObservationIgnored private let hasCaller: Bool
    @ObservationIgnored private let reader: ServerUIWeatherReader?
    @ObservationIgnored private var consumers: Set<ObjectIdentifier> = []

    init(configuration: ServerUICompositionDocument.HomeWeather, context: UKContext,
         forecasts: WeatherForecastStore? = nil, caller: (any WeatherForecastCalling)? = nil,
         reader: ServerUIWeatherReader? = nil) {
        self.configuration = configuration
        self.context = context
        self.reader = reader
        hasCaller = reader != nil || caller != nil || context.connection != nil
        let adapter: (any WeatherForecastCalling)?
        let connected: (@MainActor () -> Bool)?
        if let reader {
            adapter = ForecastCaller(reader: reader, entityId: configuration.weatherEntityId)
            connected = { reader.isConnected }
        } else {
            adapter = caller
            connected = nil
        }
        let inputs = UKWeatherForecastDriver.Inputs(weather: configuration.weatherEntityId,
            sun: configuration.sunEntityId, airQuality: configuration.airQualityEntityId)
        driver = UKWeatherForecastDriver(context: context, store: forecasts, caller: adapter,
                                         inputs: inputs, connected: connected)
    }

    var current: WeatherCurrent { WeatherCurrent(entity: context.store.entity(configuration.weatherEntityId).state) }
    var sun: WeatherSunInput? { WeatherSunInput(entity: configuration.sunEntityId.flatMap { context.store.entity($0).state }) }
    var airQuality: EntityState? { configuration.airQualityEntityId.flatMap { context.store.entity($0).state } }
    var hourly: WeatherForecastFeed { available(driver.forecasts.hourly) }
    var daily: WeatherForecastFeed { available(driver.forecasts.daily) }
    var briefing: WeatherDayBriefing? { driver.forecasts.briefing }
    var offline: Bool {
        if let reader { return !reader.isConnected }
        guard let connection = context.connection else { return false }
        if case .connected = connection.status { return false }
        return true
    }

    /// The canonical store still speaks its existing service protocol; this bridge accepts only its exact forecast request.
    private final class ForecastCaller: WeatherForecastCalling {
        let reader: ServerUIWeatherReader
        let entityId: String

        init(reader: ServerUIWeatherReader, entityId: String) {
            self.reader = reader
            self.entityId = entityId
        }

        func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
            guard domain == "weather", service == "get_forecasts", Set(data.keys) == ["entity_id", "type"],
                  data["entity_id"] as? String == entityId,
                  let raw = data["type"] as? String, let kind = WeatherForecastKind(rawValue: raw) else {
                throw ServerUIWeatherReader.Failure.unapprovedEntity
            }
            return try await reader.forecast(entityId: entityId, kind: kind)
        }
    }

    func isStale(_ feed: WeatherForecastFeed, now: Date = Date()) -> Bool {
        !feed.forecasts.isEmpty && (offline || feed.updatedAt.map { now.timeIntervalSince($0) >= WeatherForecastStore.timeToLive } == true)
    }

    private func available(_ feed: WeatherForecastFeed) -> WeatherForecastFeed {
        guard !hasCaller, feed.forecasts.isEmpty, feed.isPending else { return feed }
        return WeatherForecastFeed(error: "unavailable_source", phase: .error)
    }

    func setVisible(_ view: UIView, _ visible: Bool) {
        let wasEmpty = consumers.isEmpty
        if visible { consumers.insert(ObjectIdentifier(view)) } else { consumers.remove(ObjectIdentifier(view)) }
        if wasEmpty, !consumers.isEmpty { driver.activate() }
        else if !wasEmpty, consumers.isEmpty { driver.deactivate() }
    }
}
#endif
