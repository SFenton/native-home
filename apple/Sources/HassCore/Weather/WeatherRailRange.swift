import Foundation

/// A temperature range drawn as a rail: where the span starts, how long it is and where "now" sits (all 0...100).
public struct WeatherRailRange: Equatable, Sendable {
    public var markerPercent: Double?
    public var rangeSizePercent: Double?
    public var rangeStartPercent: Double?

    public init(markerPercent: Double? = nil, rangeSizePercent: Double? = nil, rangeStartPercent: Double? = nil) {
        self.markerPercent = markerPercent
        self.rangeSizePercent = rangeSizePercent
        self.rangeStartPercent = rangeStartPercent
    }
}
