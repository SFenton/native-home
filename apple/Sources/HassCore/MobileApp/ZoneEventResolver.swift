import Foundation

/// A monitored region boundary crossing, by region id (``PlannedRegion/id``): a zone's entity id, or
/// `<entity id>@<degrees>` for one of a small zone's circles.
public enum ZoneEvent: Equatable, Sendable {
    case entered(String)
    case exited(String)

    /// The region the crossing happened at.
    public var regionID: String {
        switch self {
        case .entered(let id), .exited(let id): id
        }
    }

    /// The zone's entity id.
    public var zoneID: String { PlannedRegion.zoneID(of: regionID) }

    /// Whether the crossing was of one circle of a small zone rather than of the zone's own region.
    public var isSubRegion: Bool { PlannedRegion.subRegionID(of: regionID) != nil }

    /// The trigger the update is reported with.
    public var trigger: LocationTrigger {
        switch self {
        case .entered: .regionEntered
        case .exited: .regionExited
        }
    }

    /// The Home Assistant event fired with the crossing, as the official app fires it (`ios.zone_entered`,
    /// `ios.zone_exited`).
    public var eventType: String {
        switch self {
        case .entered: "ios.zone_entered"
        case .exited: "ios.zone_exited"
        }
    }
}

/// Decides the `location_name` sent with a zone event, so GPS wobble at a boundary cannot flip a person back.
///
/// iOS's report is the news; the fix only checks it.
/// - Enter with a fix: no name. The official app sends none either: Home Assistant places the fix in whichever
///   zone contains it, and ``ZoneEntryFuzzer`` widens the accuracy circle when iOS's region and the fix disagree
///   slightly. An entry reported 382 m out is simply not at home.
/// - Enter without a fix: the zone's name (`home` for the home zone); the caller sends the zone's center.
/// - Exit with a fix: `not_home` unless the fix's position lies inside some non-passive zone, then no name. iOS
///   already said the phone left the region, so an accuracy circle that still touches a zone must not veto it.
///   (A departure from the official app, which sends no name; it left the person "home" for hours.)
/// - Exit without a fix: no name here; ``LocationReporter`` sends the exited zone's center instead.
public struct ZoneEventResolver: Sendable {
    /// Every zone from `get_zones`.
    public var zones: [HAZone]

    /// Creates a resolver over `zones`.
    public init(zones: [HAZone]) {
        self.zones = zones
    }

    /// The `location_name` for `event`, or nil to let Home Assistant decide.
    /// - Parameters:
    ///   - event: The crossing.
    ///   - fix: The fresh position taken for it, if any.
    public func locationName(for event: ZoneEvent, fix: LocationFix?) -> String? {
        let fix = fix.flatMap { $0.isValid ? $0 : nil }
        switch event {
        case .entered:
            guard fix == nil, let zone = zones.first(where: { $0.entityID == event.zoneID }), !zone.isPassive else { return nil }
            return zone.isHome ? "home" : zone.friendlyName
        case .exited:
            guard let fix else { return nil }
            let inside = zones.contains { !$0.isPassive && $0.distanceOutside(fix) <= 0 }
            return inside ? nil : "not_home"
        }
    }
}
