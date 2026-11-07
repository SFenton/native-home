import Foundation

/// The `sun.sun` entity's fields the sheet reads.
public struct WeatherSunInput: Equatable, Sendable {
    public var state: String?
    public var nextRising: String?
    public var nextSetting: String?

    public init(state: String?, nextRising: String?, nextSetting: String?) {
        self.state = state
        self.nextRising = nextRising
        self.nextSetting = nextSetting
    }

    /// Reads a `sun.sun` entity; `nil` when the entity is missing.
    public init?(entity: EntityState?) {
        guard let entity else { return nil }
        self.init(state: entity.state, nextRising: entity.attributes["next_rising"]?.string, nextSetting: entity.attributes["next_setting"]?.string)
    }

    /// `below_horizon` means night.
    public var isNight: Bool { state == "below_horizon" }
}
