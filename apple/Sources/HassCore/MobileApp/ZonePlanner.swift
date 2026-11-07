import Foundation

/// A circular region the phone asks iOS to watch for one zone.
///
/// A zone smaller than 100 m is watched with three of these (see ``ZonePlanner``); their ids are
/// `<zone entity id>@<degrees>`, so ``zoneID`` is the zone they belong to.
public struct PlannedRegion: Equatable, Sendable, Identifiable {
    /// The monitor's condition identifier: the zone's entity id, plus `@<degrees>` for a small zone's sub-region.
    public var id: String
    /// Center latitude.
    public var latitude: Double
    /// Center longitude.
    public var longitude: Double
    /// Radius in meters.
    public var radius: Double

    /// Creates a region.
    public init(id: String, latitude: Double, longitude: Double, radius: Double) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
    }

    /// The entity id of the zone this region watches: ``id`` without any `@<degrees>` suffix.
    public var zoneID: String { Self.zoneID(of: id) }

    /// The suffix after `@` for a small zone's sub-region (`"120"`), nil for a zone's own region.
    public var subRegionID: String? { Self.subRegionID(of: id) }

    /// The zone entity id in a region id.
    public static func zoneID(of regionID: String) -> String {
        regionID.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? regionID
    }

    /// The sub-region suffix in a region id, if any.
    public static func subRegionID(of regionID: String) -> String? {
        let parts = regionID.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.count == 2 ? String(parts[1]) : nil
    }

    /// Meters from the region's edge to `fix`, less the fix's accuracy: at most zero when the fix's circle touches
    /// the region (the official app's "contains with accuracy").
    public func distanceWithAccuracy(_ fix: LocationFix) -> Double {
        fix.distance(toLatitude: latitude, longitude: longitude) - radius - fix.horizontalAccuracy
    }
}

/// Picks the regions to watch: iOS monitors at most 20 regions per app, so watch the nearest zones.
///
/// Rules (matching the official app): the home zone is always watched; passive zones never are (they cannot set
/// anyone's state); the rest are the nearest to the last fix; and a zone under 100 m, which iOS reports false
/// entries for, is watched with three 100 m circles whose centers sit `100 - radius` meters from the zone's center
/// at 0°, 120° and 240°. Each circle contains the whole zone, so leaving any one of them means leaving the zone.
/// Every region counts toward the 20; whole zones are dropped, farthest first.
public struct ZonePlanner: Sendable {
    /// The most regions iOS monitors for one app.
    public static let regionLimit = 20
    /// The smallest radius iOS reports crossings for reliably.
    public static let minimumRadius: Double = 100
    /// How many circles watch a zone under ``minimumRadius``.
    public static let subRegionCount = 3

    /// How many regions to plan.
    public var limit: Int

    /// Creates a planner.
    public init(limit: Int = ZonePlanner.regionLimit) {
        self.limit = limit
    }

    /// The regions that watch one zone: itself, or three circles when it is under 100 m.
    public func regions(for zone: HAZone) -> [PlannedRegion] {
        guard zone.radius < Self.minimumRadius else {
            return [PlannedRegion(id: zone.entityID, latitude: zone.latitude, longitude: zone.longitude, radius: zone.radius)]
        }
        let offset = Self.minimumRadius - zone.radius
        return (0..<Self.subRegionCount).map { index in
            let degrees = Double(index) * 360 / Double(Self.subRegionCount)
            let center = zone.offset(meters: offset, bearing: degrees)
            return PlannedRegion(id: "\(zone.entityID)@\(String(format: "%03.0f", degrees))", latitude: center.latitude,
                                 longitude: center.longitude, radius: Self.minimumRadius)
        }
    }

    /// The regions to monitor.
    /// - Parameters:
    ///   - zones: Every zone from `get_zones`.
    ///   - fix: The last known position; without one, zones keep Home Assistant's order.
    public func plan(_ zones: [HAZone], near fix: LocationFix?) -> [PlannedRegion] {
        guard limit > 0 else { return [] }
        let home = zones.first(where: \.isHome)
        var others = zones.filter { !$0.isHome && !$0.isPassive }
        if let fix, fix.isValid {
            // Stable for equal distances, so a replan with the same inputs never reshuffles conditions.
            others = others.enumerated().sorted { lhs, rhs in
                let left = lhs.element.distanceOutside(fix), right = rhs.element.distanceOutside(fix)
                return left == right ? lhs.offset < rhs.offset : left < right
            }.map(\.element)
        }
        var planned: [PlannedRegion] = []
        for zone in (home.map { [$0] } ?? []) + others {
            let regions = regions(for: zone)
            // Whole zones only: a zone with some of its circles missing could report an entry but never the exit.
            guard planned.count + regions.count <= limit else { break }
            planned += regions
        }
        return planned
    }
}

extension HAZone {
    /// The point `meters` from the zone's center along `bearing` degrees clockwise from north (great circle on the
    /// mean Earth radius, like the distances in ``LocationFix``).
    func offset(meters: Double, bearing degrees: Double) -> (latitude: Double, longitude: Double) {
        let angular = meters / LocationFix.earthRadius, bearing = degrees * .pi / 180
        let φ1 = latitude * .pi / 180, λ1 = longitude * .pi / 180
        let φ2 = asin(sin(φ1) * cos(angular) + cos(φ1) * sin(angular) * cos(bearing))
        let λ2 = λ1 + atan2(sin(bearing) * sin(angular) * cos(φ1), cos(angular) - sin(φ1) * sin(φ2))
        return (φ2 * 180 / .pi, λ2 * 180 / .pi)
    }
}
