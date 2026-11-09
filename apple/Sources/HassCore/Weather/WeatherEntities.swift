import Foundation

/// The entities the weather card and sheet read.
///
/// Each id is the document's value (`home.weatherEntityId`, `home.airQualityEntityId`, `home.sunEntityId`), else empty. Source: `ha-sfenton-react-dash@f5a7bf9:src/constants/atAGlance.ts:766`.
public enum WeatherEntities {
    /// The weather entity: current conditions and the forecast source.
    public static var weather: String { HomeConfig.weatherEntityId }
    /// The air-quality sensor (US AQI): `home.airQualityEntityId`.
    public static var airQuality: String { HouseConfigSource.active.read { $0.home.airQualityEntityId }.flatMap { $0 } ?? "" }
    /// The sun entity: next sunrise and sunset, and whether it is night. `home.sunEntityId`.
    public static var sun: String { HouseConfigSource.active.read { $0.home.sunEntityId }.flatMap { $0 } ?? "" }
}
