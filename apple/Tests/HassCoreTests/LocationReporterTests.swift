import Foundation
@testable import HassCore
import HassTestSupport
import Testing

let zonesJSON = """
[{"entity_id":"zone.home","attributes":{"latitude":37.6,"longitude":-122.3,"radius":40,"friendly_name":"Home"}},
 {"entity_id":"zone.work","attributes":{"latitude":37.645,"longitude":-122.3,"radius":150,"friendly_name":"Work"}}]
"""

@MainActor
@Suite("Location reporter")
struct LocationReporterTests {
    let ticks = LocationTestClock()
    var clock: Date { ticks.date }
    let store = InMemoryZoneStore()
    let background = RecordingBackgroundTime()

    func reporter(_ platform: FakeLocationPlatform, _ transport: StubHTTPTransport, linksPresence: Bool = true) -> LocationReporter {
        LocationReporter(
            platform: platform,
            client: MobileAppWebhookClient(source: FixedMobileAppWebhookSource(mobileAppWebhook), transport: transport),
            linksPresence: linksPresence, batteryLevel: { 64 }, now: { [ticks] in ticks.date },
            zoneStore: store, backgroundTime: background
        )
    }

    /// The `data` of the `update_location` command at `index` among the recorded requests.
    func locationData(_ transport: StubHTTPTransport, _ index: Int) throws -> [String: Any] {
        let body = try sentBody(transport.requests[index])
        #expect(body["type"] as? String == "update_location")
        return try #require(body["data"] as? [String: Any])
    }

    @Test func permissionIsRequestedInTwoSteps() {
        let platform = FakeLocationPlatform(.notDetermined)
        let subject = reporter(platform, StubHTTPTransport([]))
        subject.requestPermission()
        platform.permission = LocationPermission(authorization: .whenInUse)
        let upgraded = reporter(platform, StubHTTPTransport([]))
        upgraded.requestPermission()
        for authorization in [LocationPermission.Authorization.always, .denied, .restricted] {
            platform.permission = LocationPermission(authorization: authorization)
            reporter(platform, StubHTTPTransport([])).requestPermission()
        }
        #expect(platform.calls == ["whenInUse", "always"])
    }

    @Test func startWithAlwaysMonitorsZonesAndSendsALaunchFix() async throws {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
        platform.fixes = [fixNorth(of: 0, accuracy: 8)]
        let transport = StubHTTPTransport([(200, zonesJSON), (200, "{}")])
        let subject = reporter(platform, transport)
        await subject.start()
        #expect(subject.isRunning)
        #expect(platform.calls == ["startSignificant", "open", "monitor 4"], "Home's three circles and Work")
        #expect(subject.monitoredRegions.map(\.id) == ["zone.home@000", "zone.home@120", "zone.home@240", "zone.work"])
        #expect(subject.monitoredRegions[0].radius == 100)
        let data = try locationData(transport, 1)
        #expect(data["battery"] as? Int == 64)
        #expect(data["location_name"] == nil)
        #expect(subject.lastTrigger == .launch)
        #expect(subject.lastReportDate == clock)
        #expect(subject.lastError == nil)

        await subject.start()
        #expect(transport.requests.count == 2, "Starting twice does nothing")
    }

    @Test func whileUsingOnlySendsFixesWithoutBackgroundMonitoring() async throws {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .whenInUse))
        platform.fixes = [fixNorth(of: 0)]
        let transport = StubHTTPTransport([(200, zonesJSON), (200, "{}")])
        let subject = reporter(platform, transport)
        await subject.start()
        #expect(platform.calls.isEmpty)
        #expect(subject.monitoredRegions.isEmpty)
        #expect(transport.requests.count == 2)
    }

    @Test func unauthorizedDevicesNeverStart() async {
        let transport = StubHTTPTransport([])
        let denied = reporter(FakeLocationPlatform(LocationPermission(authorization: .denied)), transport)
        await denied.start()
        #expect(!denied.isRunning)
        #expect(transport.requests.isEmpty)
        #expect(await denied.report(.manual) == false)
    }

    @Test func anIPadReportsToItsOwnTrackerButIsNeverLinkedToAPerson() async {
        // Owner, 2026-10-27: every iOS device opts in to location; only a phone follows the signed-in person.
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
        platform.fixes = [LocationFix(latitude: 37.6, longitude: -122.3, horizontalAccuracy: 8, timestamp: clock)]
        let transport = StubHTTPTransport([(200, zonesJSON), (200, "{}")])
        let iPad = reporter(platform, transport, linksPresence: false)
        await iPad.start()
        #expect(iPad.isRunning, "an iPad reports")
        #expect(iPad.lastReportDate != nil)
        #expect(!iPad.linksPresence)
        #expect(!LocationReporter.linksPresence(isPad: true))
        #expect(LocationReporter.linksPresence(isPad: false))
        #expect(!LocationReporter.deviceLinksPresence, "The macOS test host is not a phone")
    }

    @Test func zoneEntryAndExitSendTheZoneResult() async throws {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
        platform.fixes = [fixNorth(of: 5000), fixNorth(of: 10, accuracy: 15), fixNorth(of: 2000, accuracy: 30)]
        let transport = StubHTTPTransport(okReplies(8))
        let subject = reporter(platform, transport)
        await subject.start()

        await subject.handle(.zone(.entered("zone.home")))
        let updates = try updateLocations(transport)
        #expect(updates[1]["location_name"] == nil, "An entry with a fix carries no name, as in the official app")
        #expect(updates[1]["gps_accuracy"] as? Int == 15)
        #expect(subject.lastTrigger == .regionEntered)

        await subject.handle(.zone(.exited("zone.home")))
        #expect(try updateLocations(transport)[2]["location_name"] as? String == "not_home")
        #expect(subject.lastTrigger == .regionExited)
    }

    @Test func zoneEntryWithoutAFixReportsTheZoneCenter() async throws {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
        platform.fixes = [fixNorth(of: 3000)]
        let transport = StubHTTPTransport(okReplies(6))
        let subject = reporter(platform, transport)
        await subject.start()
        await subject.handle(.zone(.entered("zone.work")))
        let data = try updateLocations(transport)[1]
        #expect(data["gps"] as? [Double] == [37.645, -122.3])
        #expect(data["gps_accuracy"] as? Int == 150)
        #expect(data["location_name"] as? String == "Work")

        // A region no zone owns is ignored: nothing sent, nothing fired.
        let before = transport.requests.count
        await subject.handle(.zone(.entered("zone.demo_unknown")))
        await subject.handle(.zone(.exited("zone.demo_unknown@120")))
        #expect(transport.requests.count == before)
    }

    @Test func significantChangesTakeTheirOwnFixAndReplanZones() async throws {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 4000, at: 100)]
        let transport = StubHTTPTransport(okReplies(6))
        let subject = reporter(platform, transport)
        await subject.start()
        ticks.advance(5)
        await subject.handle(.significantChange(fixNorth(of: 3, at: 5)))
        #expect(transport.requests.count == 2, "An update succeeded under 30 s ago")
        ticks.advance(95)
        // The reading says 120 m; the fix taken for it says 4 km, and that is what is sent.
        await subject.handle(.significantChange(fixNorth(of: 120, at: 99)))
        let updates = try updateLocations(transport)
        #expect(updates.count == 2)
        let gps = try #require(updates[1]["gps"] as? [Double])
        #expect(abs(gps[0] - (37.6 + 4000 / 111_195)) < 1e-6)
        #expect(subject.lastTrigger == .significantLocationChange)
        #expect(zoneOrder(subject.monitoredRegions) == ["zone.home", "zone.work"])
    }

    @Test func aSignificantChangeWithNoFixOfItsOwnFallsBackToItsReadingUnlessInvalid() async throws {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
        platform.fixes = [fixNorth(of: 0)]
        let transport = StubHTTPTransport(okReplies(6))
        let subject = reporter(platform, transport)
        await subject.start()
        ticks.advance(100)
        await subject.handle(.significantChange(fixNorth(of: 2000, accuracy: 1600, at: 99)))
        #expect(try updateLocations(transport).count == 1, "Over 1500 m grades invalid")
        await subject.handle(.significantChange(fixNorth(of: 2000, accuracy: 50, at: 99)))
        #expect(try updateLocations(transport).count == 2)
    }

    @Test func aRelaunchPlansZonesFromCoreLocationsCachedPosition() async {
        let zones = (1...25).map { "{\"entity_id\":\"zone.demo_z\($0)\",\"attributes\":{\"latitude\":\(37.6 + Double($0) * 0.009),\"longitude\":-122.3,\"radius\":150,\"friendly_name\":\"Z\($0)\"}}" }
        store.zones = HAZone.zones(json: Data("[\(zones.joined(separator: ","))]".utf8)) ?? []
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
        platform.lastKnown = fixNorth(of: 25 * 1000)
        let subject = reporter(platform, StubHTTPTransport([(503, "")]))
        await subject.start()
        let ids = subject.monitoredRegions.map(\.id)
        #expect(ids.count == 20)
        #expect(ids.contains("zone.demo_z25"), "Near the cached position")
        #expect(!ids.contains("zone.demo_z1"))
    }

    @Test func eventsWhileStoppedAreIgnored() async {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
        let transport = StubHTTPTransport([])
        let subject = reporter(platform, transport)
        await subject.handle(.significantChange(fixNorth(of: 0)))
        await subject.handle(.zone(.entered("zone.home")))
        await subject.refreshZones()
        await subject.stop()
        await subject.handle(.permissionChanged(LocationPermission(authorization: .denied)))
        #expect(subject.permission.authorization == .denied)
        #expect(transport.requests.isEmpty)
        #expect(platform.calls.isEmpty)
    }

    @Test func permissionChangesFollowThePlatform() async {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .whenInUse))
        platform.fixes = [fixNorth(of: 0)]
        let transport = StubHTTPTransport([(200, zonesJSON), (200, "{}")])
        let subject = reporter(platform, transport)
        await subject.start()

        await subject.handle(.permissionChanged(LocationPermission(authorization: .always)))
        #expect(platform.calls == ["startSignificant", "monitor 4"])

        await subject.handle(.permissionChanged(LocationPermission(authorization: .always)))
        #expect(platform.calls.count == 2, "No change, nothing to do")

        await subject.handle(.permissionChanged(LocationPermission(authorization: .always, isPrecise: false)))
        #expect(platform.calls == ["startSignificant", "monitor 4", "stopSignificant", "stopMonitoring"])
        #expect(subject.monitoredRegions.isEmpty)

        await subject.handle(.permissionChanged(LocationPermission(authorization: .denied)))
        #expect(!subject.isRunning)
        #expect(platform.calls.suffix(2) == ["stopSignificant", "stopMonitoring"])
    }

    @Test func aGoneRegistrationStopsReporting() async {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
        platform.fixes = [fixNorth(of: 0)]
        let transport = StubHTTPTransport([(200, zonesJSON), (410, "")])
        let subject = reporter(platform, transport)
        await subject.start()
        #expect(subject.lastError == .registrationGone)
        #expect(!subject.isRunning)
        #expect(subject.lastTrigger == nil)
    }

    @Test func zoneFailuresAreRecordedAndAFailedSendCanBeRetried() async throws {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 0)]
        let transport = StubHTTPTransport([(500, ""), (503, ""), (200, "{}")])
        let subject = reporter(platform, transport)
        await subject.start()
        #expect(subject.isRunning, "A server error keeps reporting on")
        #expect(subject.lastError == .status(503))
        #expect(subject.monitoredRegions.isEmpty)
        #expect(await subject.report(.manual))
        #expect(subject.lastError == nil)
        #expect(await subject.report(.manual) == false, "No fix")
    }

    @Test func cancellationIsNotAnError() async {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
        let transport = StubHTTPTransport([])
        transport.error = CancellationError()
        let subject = reporter(platform, transport)
        await subject.start()
        #expect(subject.lastError == nil)
        #expect(subject.isRunning)
    }

    @Test func platformEventsReachTheReporter() async {
        let platform = FakeLocationPlatform(.notDetermined)
        let subject = reporter(platform, StubHTTPTransport([]))
        platform.onEvent?(.permissionChanged(LocationPermission(authorization: .whenInUse)))
        await subject.awaitZoneWork()
        #expect(subject.permission.authorization == .whenInUse)
    }

    @Test func unregisteredStopsToo() async {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
        let subject = LocationReporter(
            platform: platform, client: MobileAppWebhookClient(source: FixedMobileAppWebhookSource(nil), transport: StubHTTPTransport([])),
            linksPresence: true
        )
        await subject.start()
        #expect(subject.lastError == .notRegistered)
        #expect(!subject.isRunning)
    }
}
