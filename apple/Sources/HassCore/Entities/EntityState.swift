import Foundation

/// One Home Assistant entity's state, independent of HAKit so it can be cached and tested.
public struct EntityState: Codable, Hashable, Sendable, Identifiable {
    /// e.g. `light.kitchen`.
    public var entityId: String
    /// Raw state string, e.g. `on`, `23.5`, `armed_away`.
    public var state: String
    /// Entity attributes.
    public var attributes: [String: JSONValue]
    /// Last time ``state`` changed.
    public var lastChanged: Date

    public var id: String { entityId }

    /// Creates an entity state.
    public init(entityId: String, state: String, attributes: [String: JSONValue] = [:], lastChanged: Date = .distantPast) {
        self.entityId = entityId
        self.state = state
        self.attributes = attributes
        self.lastChanged = lastChanged
    }

    // MARK: - Derived

    /// The entity's domain, e.g. `light`.
    public var domain: String { String(entityId.prefix { $0 != "." }) }

    /// `friendly_name`, falling back to the object id.
    public var friendlyName: String {
        attributes["friendly_name"]?.string ?? String(entityId.drop { $0 != "." }.dropFirst())
    }

    /// `unavailable` or `unknown`.
    public var isUnavailable: Bool { Self.isUnavailable(state) }

    /// Missing, `unavailable` or `unknown`: the one availability rule every feature shares (web `isUnavailable`).
    public static func isUnavailable(_ state: String?) -> Bool {
        guard let state else { return true }
        return state == "unavailable" || state == "unknown"
    }

    /// Active in the web dashboard's sense (`entityState.ts` `isActiveState`).
    public var isActive: Bool {
        ["on", "open", "opening", "unlocked", "playing", "home", "cleaning", "heat", "cool", "heat_cool"].contains(state)
    }

    /// A number parsed from ``state``, if it is numeric.
    public var numericState: Double? { Double(state) }
}
