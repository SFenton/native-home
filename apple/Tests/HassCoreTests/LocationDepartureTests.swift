import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// Leaving home, 2026-10-29: the departure never reached Home Assistant, or flipped straight back to Home.
@MainActor
@Suite("Location departures")
struct LocationDepartureTests {
    let ticks = LocationTestClock()
    var clock: Date { ticks.date }
    let store = InMemoryZoneStore()
    let background = RecordingBackgroundTime()

    func reporter(_ platform: FakeLocationPlatform, _ transport: StubHTTPTransport) -> LocationReporter {
        LocationReporter(
            platform: platform,
            client: MobileAppWebhookClient(source: FixedMobileAppWebhookSource(mobileAppWebhook), transport: transport),
            linksPresence: true, now: { [ticks] in ticks.date }, zoneStore: store, backgroundTime: background
        )
    }

    func data(_ transport: StubHTTPTransport, _ index: Int) throws -> [String: Any] {
        try #require(try sentBody(transport.requests[index])["data"] as? [String: Any])
    }

    func always() -> FakeLocationPlatform { FakeLocationPlatform(LocationPermission(authorization: .always)) }

    @Test func theMonitorOpensBeforeAnyNetworkCall() async {
        let platform = always()
        let transport = StubHTTPTransport([(500, ""), (200, "{}")])
        var requestsWhenOpened = -1
        platform.onOpenMonitor = { requestsWhenOpened = transport.requests.count }
        let subject = reporter(platform, transport)
        await subject.start()
        #expect(requestsWhenOpened == 0)
        #expect(platform.calls.prefix(2) == ["startSignificant", "open"])
    }

    @Test func aBackgroundRelaunchResolvesAnExitOfflineFromCachedZones() async throws {
        store.zones = HAZone.zones(json: Data(zonesJSON.utf8)) ?? []
        let platform = always()
        // The exit and the launch update race for fixes; both get the same kind of reading.
        platform.fixes = [fixNorth(of: 700, accuracy: 20), fixNorth(of: 700, accuracy: 20)]
        // Zones fail (off Wi-Fi), then everything else goes through.
        let transport = StubHTTPTransport([(503, "")] + Array(repeating: (200, "{}"), count: 8))
        let subject = reporter(platform, transport)
        // The exit arrives as soon as the monitor opens.
        platform.onOpenMonitor = { platform.onEvent?(.zone(.exited("zone.home"))) }
        await subject.start()
        await subject.awaitZoneWork()
        #expect(zoneOrder(subject.monitoredRegions) == ["zone.home", "zone.work"], "Planned from the cache")
        let exit = try updateLocations(transport).filter { $0["location_name"] as? String == "not_home" }
        #expect(exit.count == 1, "The exit resolved offline from the cached zones")
        #expect(try firedEvents(transport).map { $0["event_type"] as? String } == ["ios.zone_exited"])
    }

    @Test func aFailedRefreshKeepsCachedZonesAndASuccessfulOneSavesThem() async {
        store.zones = [HAZone(entityID: "zone.home", latitude: 1, longitude: 2, radius: 30, friendlyName: "Home")]
        let platform = always()
        let failing = reporter(platform, StubHTTPTransport([(503, ""), (503, "")]))
        await failing.start()
        #expect(store.zones.count == 1)
        #expect(zoneOrder(failing.monitoredRegions) == ["zone.home"])

        let other = InMemoryZoneStore()
        let saving = LocationReporter(
            platform: always(),
            client: MobileAppWebhookClient(source: FixedMobileAppWebhookSource(mobileAppWebhook), transport: StubHTTPTransport([(200, zonesJSON)])),
            now: { [ticks] in ticks.date }, zoneStore: other
        )
        await saving.start()
        #expect(other.zones.map(\.entityID) == ["zone.home", "zone.work"])
    }

    @Test func userDefaultsStoreRoundTrips() {
        let defaults = UserDefaults(suiteName: "zone-store-\(UUID().uuidString)")!
        let zones = UserDefaultsZoneStore(defaults: defaults)
        #expect(zones.load().isEmpty)
        let saved = [HAZone(entityID: "zone.home", latitude: 1.5, longitude: 2.5, radius: 33, isPassive: true, friendlyName: "H")]
        zones.save(saved)
        #expect(zones.load() == saved)
        defaults.set(Data("junk".utf8), forKey: "location.cachedZones")
        #expect(zones.load().isEmpty)
    }

    @Test func backgroundTimeIsHeldForEachEventAndReleasedOnSuccessAndFailure() async {
        store.zones = HAZone.zones(json: Data(zonesJSON.utf8)) ?? []
        let platform = always()
        platform.fixes = [fixNorth(of: 700), fixNorth(of: 900, at: 200), fixNorth(of: 3000, at: 200)]
        // Zones, launch, exit update, exit event, then the significant change's update fails.
        let transport = StubHTTPTransport([(200, zonesJSON), (200, "{}"), (200, "{}"), (200, "{}"), (500, "")])
        let subject = reporter(platform, transport)
        await subject.start()
        await subject.handle(.zone(.exited("zone.home")))
        #expect(background.begun == ["zone event"])
        #expect(background.held == 0)
        ticks.advance(200)
        await subject.handle(.significantChange(fixNorth(of: 3000, at: 200)))
        #expect(background.begun == ["zone event", "significant change"])
        #expect(background.held == 0, "Released after a failed send too")
        #expect(subject.lastError == .status(500))
    }

    @Test func aStaleSignificantChangeIsNotReported() async {
        let platform = always()
        let transport = StubHTTPTransport([(200, zonesJSON)])
        let subject = reporter(platform, transport)
        await subject.start()
        // The cached "309 m" reading, ten minutes old.
        await subject.handle(.significantChange(fixNorth(of: 309, accuracy: 29, at: -600)))
        #expect(transport.requests.count == 1)
        #expect(background.held == 0)
        // Even three minutes and a second is too old.
        await subject.handle(.significantChange(fixNorth(of: 309, accuracy: 29, at: -181)))
        #expect(transport.requests.count == 1)
    }

    @Test func fixesAreRequestedWithATriggerSpecificTimeout() async {
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 700, at: 1), fixNorth(of: 700, at: 100)]
        let subject = reporter(platform, StubHTTPTransport(okReplies(10)))
        await subject.start()
        await subject.handle(.zone(.exited("zone.home")))
        ticks.advance(100)
        await subject.handle(.significantChange(fixNorth(of: 700, at: 100)))
        #expect(platform.timeouts == [30, 20, 10], "Launch 30 s, region crossing 20 s, significant change 10 s")
    }

    @Test func theWaitIsCappedByTheBackgroundTimeLeft() async {
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 700, at: 1)]
        let subject = reporter(platform, StubHTTPTransport(okReplies(10)))
        await subject.start()
        background.remaining = 12
        await subject.handle(.zone(.exited("zone.home")))
        #expect(platform.timeouts == [30, 7], "min(20, 12 - 5)")
        #expect(OneShotFix.timeout(for: .launch, backgroundRemaining: 3) == 1, "Never under a second")
        #expect(OneShotFix.timeout(for: .pushNotification) == 10)
        #expect(OneShotFix.timeout(for: .backgroundFetch) == 10)
        #expect(OneShotFix.timeout(for: .manual) == 30)
    }

    @Test func anExitWithNoFixSendsNotHomeAtTheCenterWithTheRegionRadius() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0)]
        let transport = StubHTTPTransport(okReplies(4))
        let subject = reporter(platform, transport)
        await subject.start()
        await subject.handle(.zone(.exited("zone.home")))
        let sent = try updateLocations(transport)[1]
        #expect(sent["gps"] as? [Double] == [37.6, -122.3])
        #expect(sent["gps_accuracy"] as? Int == 100, "The 100 m circle, not the 40 m zone")
        #expect(sent["location_name"] as? String == "not_home")
        #expect(subject.lastTrigger == .regionExited)
    }

    @Test func anExitWithNoFixIsSkippedWhileAnotherZoneIsSatisfied() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0)]
        platform.satisfied = ["zone.work"]
        let transport = StubHTTPTransport(okReplies(6))
        let subject = reporter(platform, transport)
        await subject.start()
        await subject.handle(.zone(.exited("zone.home")))
        #expect(try updateLocations(transport).count == 1, "Only the launch update")
        #expect(try firedEvents(transport).count == 1, "The crossing is still fired")
        platform.satisfied = ["zone.home@120", "zone.home"]
        await subject.handle(.zone(.exited("zone.home@000")))
        #expect(try updateLocations(transport).count == 2, "The exited zone's own circles do not veto")
    }

    @Test func anEntryOutsideTheRealZoneSendsTheFixWithoutAName() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 382, accuracy: 10, at: 1)]
        let transport = StubHTTPTransport(okReplies(4))
        let subject = reporter(platform, transport)
        await subject.start()
        await subject.handle(.zone(.entered("zone.home")))
        let sent = try updateLocations(transport)[1]
        #expect(sent["location_name"] == nil)
        #expect(sent["gps_accuracy"] as? Int == 10, "382 m out is not widened")
    }

    @Test func twoEventsSharingOneFixNeverContradict() async throws {
        // 2026-10-21: an exit at 382 m said not_home, then the same coordinates said home.
        let platform = always()
        let shared = fixNorth(of: 382, accuracy: 10, at: 1)
        platform.fixes = [fixNorth(of: 0), shared, shared]
        let transport = StubHTTPTransport(okReplies(8))
        let subject = reporter(platform, transport)
        await subject.start()
        await subject.handle(.zone(.exited("zone.home")))
        await subject.handle(.zone(.entered("zone.home")))
        let updates = try updateLocations(transport)
        #expect(updates.count == 3)
        #expect(updates[1]["location_name"] as? String == "not_home")
        #expect(updates[2]["location_name"] == nil, "An entry carries no name: Home Assistant places the fix")
    }

    @Test func aCoarseSignificantChangeFixIsReportedUnderTheGradedRules() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 1500, accuracy: 1400, at: 100)]
        let transport = StubHTTPTransport(okReplies(4))
        let subject = reporter(platform, transport)
        await subject.start()
        ticks.advance(100)
        await subject.handle(.significantChange(fixNorth(of: 1500, accuracy: 1400, at: 99)))
        #expect(try updateLocations(transport).count == 2)
        #expect(subject.lastTrigger == .significantLocationChange)
    }

    @Test func anOutOfOrderSignificantChangeIsDropped() async {
        let platform = always()
        platform.fixes = [fixNorth(of: 0, at: 50)]
        let transport = StubHTTPTransport(okReplies(4))
        let subject = reporter(platform, transport)
        await subject.start()
        ticks.advance(100)
        await subject.handle(.significantChange(fixNorth(of: 3000, at: 10)))
        #expect(transport.requests.count == 2, "Zones and launch only: the reading predates the last one sent")
    }

    @Test func noBackgroundTimeHoldsNothing() {
        let release = NoBackgroundTime().begin("x")
        release()
        #expect(NoBackgroundTime().remaining == .infinity)
    }
}
