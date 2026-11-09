import Foundation
@testable import HassCore
import Testing

/// A fix `meters` due north of (37.6, -122.3), where one degree of latitude is about 111.2 km.
func fixNorth(of meters: Double, accuracy: Double = 10, at time: TimeInterval = 0) -> LocationFix {
    LocationFix(latitude: 37.6 + meters / 111_195, longitude: -122.3, horizontalAccuracy: accuracy,
                timestamp: Date(timeIntervalSince1970: 1_000_000 + time))
}

let homeZone = HAZone(entityID: "zone.home", latitude: 37.6, longitude: -122.3, radius: 40, friendlyName: "Home")

/// A zone `meters` north of home.
func zone(_ id: String, north meters: Double, radius: Double = 150, passive: Bool = false) -> HAZone {
    HAZone(entityID: "zone.\(id)", latitude: 37.6 + meters / 111_195, longitude: -122.3, radius: radius,
           isPassive: passive, friendlyName: id.capitalized)
}

@Suite("Location fix")
struct LocationFixTests {
    @Test func distanceMatchesTheMeasuredSpacing() {
        let home = fixNorth(of: 0)
        #expect(abs(home.distance(to: fixNorth(of: 1000)) - 1000) < 1)
        // The Bay Area to Sacramento is about 130 km.
        let sacramento = LocationFix(latitude: 38.5816, longitude: -121.4944, horizontalAccuracy: 5)
        #expect(abs(home.distance(to: sacramento) / 1000 - 130) < 3)
    }

    @Test func validity() {
        #expect(fixNorth(of: 0).isValid)
        #expect(!LocationFix(latitude: 0, longitude: 0, horizontalAccuracy: -1).isValid)
        #expect(!LocationFix(latitude: -91, longitude: 0, horizontalAccuracy: 1).isValid)
        #expect(!LocationFix(latitude: 0, longitude: -181, horizontalAccuracy: 1).isValid)
    }

    @Test func zoneDistanceIsFromTheEdge() {
        #expect(abs(homeZone.distanceOutside(fixNorth(of: 100)) - 60) < 1)
        #expect(homeZone.distanceOutside(fixNorth(of: 0)) < 0)
        #expect(homeZone.isHome && !zone("demo_work", north: 1).isHome)
    }
}

@Suite("Zone planner")
struct ZonePlannerTests {
    @Test func homeAlwaysPassiveNeverNearestFirst() {
        let zones = [zone("demo_far", north: 9000), zone("demo_gym", north: 500, passive: true), homeZone,
                     zone("demo_near", north: 2000), zone("demo_mid", north: 5000)]
        // Home is a small zone (three circles); the others are one region each.
        let plan = ZonePlanner(limit: 5).plan(zones, near: fixNorth(of: 3000))
        #expect(plan.map(\.zoneID) == ["zone.home", "zone.home", "zone.home", "zone.demo_near", "zone.demo_mid"])
    }

    @Test func homeIsKeptEvenWhenFarAway() {
        let zones = (1...25).map { zone("demo_z\($0)", north: Double($0) * 1000) } + [homeZone]
        let plan = ZonePlanner().plan(zones, near: fixNorth(of: 25_000))
        #expect(plan.count == ZonePlanner.regionLimit, "Home's three circles count toward the 20")
        #expect(plan.first?.zoneID == "zone.home")
        #expect(plan.dropFirst(3).first?.id == "zone.demo_z25")
        #expect(!plan.contains { $0.id == "zone.demo_z1" }, "The farthest zones are left out")
    }

    @Test func aZoneThatDoesNotFitWholeIsLeftOut() {
        // Home's three circles and 15 big zones leave room for 2: the small zone's three do not fit, so it is
        // dropped whole, and so is everything farther.
        let near = (1...15).map { zone("demo_n\($0)", north: Double($0) * 1000) }
        let zones = [homeZone] + near + [zone("demo_small", north: 50_000, radius: 30), zone("demo_far", north: 60_000)]
        let plan = ZonePlanner().plan(zones, near: fixNorth(of: 0))
        #expect(plan.count == 18)
        #expect(!plan.contains { $0.zoneID == "zone.demo_small" || $0.zoneID == "zone.demo_far" })
    }

    @Test func smallZonesAreWatchedWithThreeCirclesThatEachContainTheZone() {
        let plan = ZonePlanner().plan([homeZone, zone("demo_big", north: 1000, radius: 300)], near: nil)
        #expect(plan.map(\.id) == ["zone.home@000", "zone.home@120", "zone.home@240", "zone.demo_big"])
        #expect(plan.allSatisfy { $0.radius == 100 || $0.id == "zone.demo_big" })
        #expect(plan.last == PlannedRegion(id: "zone.demo_big", latitude: 37.6 + 1000 / 111_195, longitude: -122.3, radius: 300))
        // Centers sit (100 - 40) m from the zone's center at 0, 120 and 240 degrees.
        let circles = Array(plan.prefix(3))
        for (circle, bearing) in zip(circles, [0.0, 120, 240]) {
            let center = LocationFix(latitude: 37.6, longitude: -122.3, horizontalAccuracy: 1)
            #expect(abs(center.distance(toLatitude: circle.latitude, longitude: circle.longitude) - 60) < 0.01)
            let north = circle.latitude - 37.6, east = (circle.longitude + 122.3) * cos(37.6 * .pi / 180)
            let measured = atan2(east, north) * 180 / .pi
            let gap = abs(measured - bearing).truncatingRemainder(dividingBy: 360)
            #expect(min(gap, 360 - gap) < 0.5)
            #expect(circle.zoneID == "zone.home")
        }
        // Leaving any circle is leaving the zone: each contains the whole 40 m zone.
        for circle in circles {
            let edge = homeZone.offset(meters: 40, bearing: 77)
            let probe = LocationFix(latitude: edge.latitude, longitude: edge.longitude, horizontalAccuracy: 0)
            #expect(probe.distance(toLatitude: circle.latitude, longitude: circle.longitude) <= circle.radius)
        }
    }

    @Test func regionIdsNameTheirZone() {
        #expect(PlannedRegion.zoneID(of: "zone.home@120") == "zone.home")
        #expect(PlannedRegion.zoneID(of: "zone.work") == "zone.work")
        #expect(PlannedRegion.subRegionID(of: "zone.home@240") == "240")
        #expect(PlannedRegion.subRegionID(of: "zone.work") == nil)
        #expect(ZoneEvent.exited("zone.home@120").zoneID == "zone.home")
        #expect(ZoneEvent.exited("zone.home@120").isSubRegion)
        #expect(!ZoneEvent.entered("zone.home").isSubRegion)
    }

    @Test func withoutAFixHomeAssistantsOrderIsKept() {
        let zones = [zone("demo_b", north: 9000), zone("demo_a", north: 10), zone("demo_c", north: 5)]
        #expect(ZonePlanner(limit: 2).plan(zones, near: nil).map(\.id) == ["zone.demo_b", "zone.demo_a"])
        #expect(ZonePlanner(limit: 2).plan(zones, near: LocationFix(latitude: 0, longitude: 0, horizontalAccuracy: -1))
            .map(\.id) == ["zone.demo_b", "zone.demo_a"], "An invalid fix is no fix")
    }

    @Test func equalDistancesKeepTheirOrder() {
        let zones = [zone("demo_first", north: 1000), zone("demo_second", north: 1000)]
        #expect(ZonePlanner().plan(zones, near: fixNorth(of: 0)).map(\.id) == ["zone.demo_first", "zone.demo_second"])
    }

    @Test func zeroLimitPlansNothing() {
        #expect(ZonePlanner(limit: 0).plan([homeZone], near: nil).isEmpty)
        #expect(ZonePlanner(limit: 2).plan([homeZone], near: nil).isEmpty, "Three circles do not fit in two")
        #expect(ZonePlanner(limit: 3).plan([homeZone, zone("demo_x", north: 1)], near: nil).map(\.zoneID) == Array(repeating: "zone.home", count: 3))
    }
}

@Suite("Zone event resolver")
struct ZoneEventResolverTests {
    let resolver = ZoneEventResolver(zones: [homeZone, zone("demo_work", north: 5000), zone("demo_mall", north: 300, radius: 50, passive: true)])

    @Test func enteringWithoutAFixNamesTheZone() {
        #expect(resolver.locationName(for: .entered("zone.home"), fix: nil) == "home")
        #expect(resolver.locationName(for: .entered("zone.home@120"), fix: nil) == "home")
        #expect(resolver.locationName(for: .entered("zone.demo_work"), fix: nil) == "Demo_Work")
        #expect(resolver.locationName(for: .entered("zone.demo_mall"), fix: nil) == nil, "Passive zones never name a state")
        #expect(resolver.locationName(for: .entered("zone.demo_unknown"), fix: nil) == nil)
    }

    @Test func exitingSaysNotHomeOnlyWhenClearOfEveryZone() {
        #expect(resolver.locationName(for: .exited("zone.home"), fix: fixNorth(of: 1000, accuracy: 20)) == "not_home")
        // 60 m outside home's edge with a 65 m circle: iOS said it left, the position is outside every zone.
        #expect(resolver.locationName(for: .exited("zone.home"), fix: fixNorth(of: 100, accuracy: 65)) == "not_home")
        #expect(resolver.locationName(for: .exited("zone.home"), fix: fixNorth(of: 30, accuracy: 5)) == nil, "Still inside home")
        // Inside work.
        #expect(resolver.locationName(for: .exited("zone.home"), fix: fixNorth(of: 5050)) == nil)
        // Inside the passive mall only: still not_home.
        #expect(resolver.locationName(for: .exited("zone.home"), fix: fixNorth(of: 300, accuracy: 5)) == "not_home")
        #expect(resolver.locationName(for: .exited("zone.home"), fix: nil) == nil)
        #expect(resolver.locationName(for: .exited("zone.home"), fix: LocationFix(latitude: 0, longitude: 0, horizontalAccuracy: -1)) == nil)
    }

    @Test func enteringWithAFixSendsNoName() {
        // The official app sends none: Home Assistant places the fix, and the fuzzer widens its accuracy.
        for meters in [5.0, 100, 130, 382] {
            #expect(resolver.locationName(for: .entered("zone.home"), fix: fixNorth(of: meters, accuracy: 10)) == nil)
        }
        #expect(resolver.locationName(for: .entered("zone.home"), fix: LocationFix(latitude: 0, longitude: 0, horizontalAccuracy: -1)) == "home", "Invalid is no fix")
    }

    @Test func eventsCarryTheirTriggerAndHomeAssistantEventName() {
        #expect(ZoneEvent.entered("zone.home").trigger == .regionEntered)
        #expect(ZoneEvent.exited("zone.home").trigger == .regionExited)
        #expect(ZoneEvent.entered("zone.home").eventType == "ios.zone_entered")
        #expect(ZoneEvent.exited("zone.home@000").eventType == "ios.zone_exited")
    }
}

/// Holds a filter so `#expect` can call its mutating `admit` through a reference.
final class FilterBox {
    var filter = LocationFixFilter()
    var lastAdmitted: LocationFix? { filter.lastAdmitted }
    func admit(_ fix: LocationFix, trigger: LocationTrigger, now: Date? = nil) -> Bool {
        filter.admit(fix, trigger: trigger, now: now ?? fix.timestamp)
    }
    func reset() { filter.reset() }
}

@Suite("Location fix filter")
struct LocationFixFilterTests {
    @Test func accuracyIsJudgedByTheGradeNotTheFilter() {
        let filter = FilterBox()
        #expect(filter.admit(fixNorth(of: 0, accuracy: 900), trigger: .significantLocationChange))
        #expect(filter.admit(fixNorth(of: 0, accuracy: 1400, at: 100), trigger: .launch))
    }

    @Test func duplicatesWithin30SecondsAnd10MetersAreDropped() {
        let filter = FilterBox()
        #expect(filter.admit(fixNorth(of: 0), trigger: .launch))
        #expect(!filter.admit(fixNorth(of: 5, at: 10), trigger: .significantLocationChange))
        #expect(!filter.admit(fixNorth(of: 5, at: 10), trigger: .pushNotification))
        #expect(filter.admit(fixNorth(of: 5, at: 10), trigger: .manual), "Asked for: always sent")
        #expect(filter.admit(fixNorth(of: 30, at: 15), trigger: .significantLocationChange), "Moved")
        #expect(filter.admit(fixNorth(of: 30, at: 50), trigger: .backgroundFetch), "Later")
    }

    @Test func outOfOrderAndStaleFixesAreDropped() {
        let filter = FilterBox()
        #expect(filter.admit(fixNorth(of: 0, at: 100), trigger: .launch))
        #expect(!filter.admit(fixNorth(of: 500, at: 90), trigger: .significantLocationChange), "older than the last admitted")
        #expect(!filter.admit(fixNorth(of: 500, at: 90), trigger: .regionExited), "also for zone events")
        #expect(filter.admit(fixNorth(of: 500, at: 150), trigger: .significantLocationChange))
        let stale = fixNorth(of: 900, at: 160)
        #expect(!filter.admit(stale, trigger: .significantLocationChange, now: stale.timestamp.addingTimeInterval(601)))
        #expect(!filter.admit(stale, trigger: .regionExited, now: stale.timestamp.addingTimeInterval(601)))
        #expect(filter.admit(stale, trigger: .significantLocationChange, now: stale.timestamp.addingTimeInterval(599)), "A meh reading may be minutes old")
        #expect(filter.admit(fixNorth(of: 900, at: 170), trigger: .manual, now: Date(timeIntervalSince1970: 2_000_000)), "Asked for: always sent")
    }

    @Test func invalidFixesNeverPass() {
        let filter = FilterBox()
        #expect(!filter.admit(LocationFix(latitude: 0, longitude: 0, horizontalAccuracy: -1), trigger: .regionEntered))
    }

    @Test func resetForgetsTheLastFix() {
        let filter = FilterBox()
        #expect(filter.admit(fixNorth(of: 0), trigger: .launch))
        filter.reset()
        #expect(filter.admit(fixNorth(of: 0, at: 1), trigger: .launch))
    }

    @Test func triggersUseTheOfficialAppsStrings() {
        #expect(LocationTrigger.allCases.map(\.rawValue) == [
            "Launch", "Geographic Region Entered", "Geographic Region Exited", "Significant Location Change",
            "Background Fetch", "Push Notification", "Manual",
        ])
        #expect(LocationTrigger.allCases.filter(\.isZoneEvent) == [.regionEntered, .regionExited])
    }
}
