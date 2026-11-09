import Foundation

/// Widens the accuracy of the fix sent with a region entry when iOS says "inside" and the fix says "just outside",
/// as the official app does (`ZoneManagerAccuracyFuzzer`). The coordinate is never moved.
///
/// Home Assistant places a tracker in a zone when the fix's accuracy circle reaches it, so a fix that iOS's region
/// monitoring and Home Assistant's zone test disagree about by a few meters would otherwise leave the person away.
public enum ZoneEntryFuzzer {
    /// The farthest outside the region (meters, past the accuracy) a fix may be and still be widened to reach it.
    /// Beyond this the region event is the likelier mistake (cell positioning reports "inside" for every region
    /// within about a kilometer), so the fix is sent unchanged.
    public static let maximumDistance: Double = 100

    /// The fix to send for entering `region` of `zone`.
    /// - Parameters:
    ///   - fix: The fresh reading.
    ///   - region: The circle iOS reported the entry for.
    ///   - zone: The zone it belongs to.
    ///   - zoneRegions: Every circle that watches the zone (``ZonePlanner/regions(for:)``).
    public static func fuzz(_ fix: LocationFix, entering region: PlannedRegion, of zone: HAZone,
                            zoneRegions: [PlannedRegion]) -> LocationFix {
        var fuzzed = fix
        // The region says inside, the fix says outside it: reach the region, if it is close.
        let toRegion = region.distanceWithAccuracy(fix)
        if toRegion > 0, toRegion <= maximumDistance { fuzzed.horizontalAccuracy += toRegion + 1 }
        // Inside the overlap of all of a small zone's circles but not the zone: reach the zone.
        let toZone = fuzzed.distance(toLatitude: zone.latitude, longitude: zone.longitude) - zone.radius - fuzzed.horizontalAccuracy
        if toZone > 0, zoneRegions.allSatisfy({ $0.distanceWithAccuracy(fuzzed) <= 0 }) { fuzzed.horizontalAccuracy += toZone + 1 }
        return fuzzed
    }
}
