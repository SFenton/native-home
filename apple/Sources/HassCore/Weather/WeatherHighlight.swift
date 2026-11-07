import Foundation

/// A highlight tile of the weather sheet (everything under "Highlights" except the chart tiles).
public struct WeatherHighlight: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case aqi, feels, uv, wind, sun, visibility, pressure
    }

    /// Wind tile details.
    public struct Wind: Equatable, Sendable {
        public var bearingDegrees: Double?
        public var destinationDegrees: Double?
        public var directionLabel: String
        public var directionValue: String
        public var gustIsForecast: Bool
        public var gustLabel: String
        public var gustValue: String
        public var showVector: Bool
        public var speedLabel: String
        public var speedValue: String
    }

    public var kind: Kind
    public var id: String { kind.rawValue }
    /// Spoken name for the whole tile, when it differs from "title value".
    public var accessibilityLabel: String
    public var available: Bool
    /// Web MDI icon name.
    public var icon: String
    /// 0...100 marker position on the tile's gauge.
    public var percent: Double?
    public var rotation: Double?
    /// Category text, e.g. `Moderate`.
    public var status: String?
    public var title: String
    public var value: String
    public var wind: Wind?
    /// A mild tone key for the AQI tile (the level name), `unavailable` otherwise.
    public var tone: String?
}
