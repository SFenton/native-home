import Foundation

/// A Home Assistant zone, as `get_zones` returns it.
public struct HAZone: Equatable, Sendable, Identifiable, Codable {
    /// `zone.home`, `zone.work`.
    public var entityID: String
    /// Center latitude.
    public var latitude: Double
    /// Center longitude.
    public var longitude: Double
    /// Radius in meters.
    public var radius: Double
    /// A passive zone never sets anyone's state; it is not monitored.
    public var isPassive: Bool
    /// The zone's name, which Home Assistant uses as a tracker's state inside it.
    public var friendlyName: String

    public var id: String { entityID }

    /// The entity id of the home zone.
    public static let homeID = "zone.home"

    /// Creates a zone.
    public init(entityID: String, latitude: Double, longitude: Double, radius: Double, isPassive: Bool = false,
                friendlyName: String) {
        self.entityID = entityID
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.isPassive = isPassive
        self.friendlyName = friendlyName
    }

    /// Whether this is the home zone.
    public var isHome: Bool { entityID == Self.homeID }

    /// Meters from the zone's edge to `fix` (negative inside the zone).
    public func distanceOutside(_ fix: LocationFix) -> Double {
        fix.distance(toLatitude: latitude, longitude: longitude) - radius
    }

    /// Reads one zone state object: `{"entity_id": "zone.home", "attributes": {"latitude": …, "longitude": …,
    /// "radius": …, "passive": false, "friendly_name": "Home"}}`.
    /// - Returns: nil for anything that is not a zone with a center and radius.
    public init?(state: [String: Any]) {
        guard let entityID = state["entity_id"] as? String, entityID.hasPrefix("zone."),
              let attributes = state["attributes"] as? [String: Any],
              let latitude = (attributes["latitude"] as? NSNumber)?.doubleValue,
              let longitude = (attributes["longitude"] as? NSNumber)?.doubleValue,
              let radius = (attributes["radius"] as? NSNumber)?.doubleValue
        else { return nil }
        self.init(
            entityID: entityID, latitude: latitude, longitude: longitude, radius: radius,
            isPassive: attributes["passive"] as? Bool ?? false,
            friendlyName: attributes["friendly_name"] as? String ?? String(entityID.dropFirst("zone.".count))
        )
    }

    /// Reads the `get_zones` response, skipping entries that are not zones.
    /// - Returns: nil when the body is not a JSON array.
    public static func zones(json data: Data) -> [HAZone]? {
        guard let states = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return nil }
        return states.compactMap { ($0 as? [String: Any]).flatMap(HAZone.init(state:)) }
    }
}
