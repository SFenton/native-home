import Foundation

/// One hour of the humidity and cloud-cover tiles.
public struct HourlyMetricPoint: Equatable, Sendable {
    public var cloudCover: Double?
    public var humidity: Double?
    public var index: Int
    public var time: Date?
}
