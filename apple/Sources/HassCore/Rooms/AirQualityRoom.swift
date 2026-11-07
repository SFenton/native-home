import Foundation

/// One room in the Air Quality sheet (web `AirQualityRoomConfig`, `atAGlance.ts:178`).
public struct AirQualityRoom: Hashable, Sendable, Identifiable, Codable {
    public var title: String
    public var aqiEntityId: String
    /// A text helper holding the room's AQI color (`rgb()`, `rgba()` or `#rrggbb`).
    public var colorEntityId: String
    public var pm25EntityId: String
    public var id: String { title }
}
