import Foundation

/// The frozen "Today" briefing: a headline, an icon and a few narrative sentences.
public struct WeatherDayBriefing: Codable, Hashable, Sendable {
    public var condition: String?
    /// Local calendar day, `2026-01-15`.
    public var dateKey: String
    public var generatedAt: Date
    public var hazard: WeatherHazard?
    public var headline: WeatherBriefingRef?
    /// Literal headline for a provider condition the copy deck lacks.
    public var headlineText: String?
    /// Web MDI icon name.
    public var icon: String
    public var sentences: [WeatherBriefingRef]
    public var severity: WeatherBriefingSeverity
    public var version: Int
}
