import Foundation

/// A copy key plus the values to fill it with; rendered to text by ``WeatherBriefingRenderer``.
public struct WeatherBriefingRef: Codable, Hashable, Sendable {
    public var key: String
    public var values: [String: WeatherBriefingValue]

    public init(_ key: String, _ values: [String: WeatherBriefingValue] = [:]) {
        self.key = key
        self.values = values
    }
}
