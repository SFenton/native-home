import Foundation

/// Remembers the last successful `get_zones` result, so a background relaunch (a zone event while the phone is
/// leaving Wi-Fi) can resolve the crossing offline. Zones are names and circles, not secrets.
@MainActor
public protocol ZoneStore: AnyObject {
    /// The zones saved last, or none.
    func load() -> [HAZone]
    /// Replaces the saved zones.
    func save(_ zones: [HAZone])
}

/// ``ZoneStore`` over `UserDefaults`.
@MainActor
public final class UserDefaultsZoneStore: ZoneStore {
    private let defaults: UserDefaults
    private let key: String

    /// Creates a store.
    public init(defaults: UserDefaults = .standard, key: String = "location.cachedZones") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> [HAZone] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([HAZone].self, from: data)) ?? []
    }

    public func save(_ zones: [HAZone]) {
        defaults.set(try? JSONEncoder().encode(zones), forKey: key)
    }
}

/// ``ZoneStore`` in memory, for tests and previews.
@MainActor
public final class InMemoryZoneStore: ZoneStore {
    public var zones: [HAZone]

    public init(_ zones: [HAZone] = []) { self.zones = zones }

    public func load() -> [HAZone] { zones }
    public func save(_ zones: [HAZone]) { self.zones = zones }
}
