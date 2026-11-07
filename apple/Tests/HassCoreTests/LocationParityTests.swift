import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// Alignment with the official Home Assistant app (`.agents/platforms/apple/location.md`, "Matching the official
/// app's location behavior"): graded one-shot fixes, small-zone circles, the entry fuzzer and the zone events.
@Suite("One-shot fix grading")
struct OneShotFixTests {
    let now = Date(timeIntervalSince1970: 1_000_100)

    func reading(accuracy: Double = 10, age: TimeInterval = 0, latitude: Double = 37.6, longitude: Double = -122.3) -> LocationFix {
        LocationFix(latitude: latitude, longitude: longitude, horizontalAccuracy: accuracy, timestamp: now.addingTimeInterval(-age))
    }

    @Test func gradesFollowTheOfficialThresholds() {
        #expect(OneShotFix.grade(reading(accuracy: 100, age: 30), now: now) == .perfect)
        #expect(OneShotFix.grade(reading(accuracy: 101, age: 5), now: now) == .meh)
        #expect(OneShotFix.grade(reading(accuracy: 10, age: 31), now: now) == .meh)
        #expect(OneShotFix.grade(reading(accuracy: 1500, age: 600), now: now) == .meh)
        #expect(OneShotFix.grade(reading(accuracy: 1501), now: now) == .invalid)
        #expect(OneShotFix.grade(reading(age: 601), now: now) == .invalid)
        #expect(OneShotFix.grade(reading(accuracy: -1), now: now) == .invalid)
        #expect(OneShotFix.grade(reading(latitude: 0), now: now) == .invalid, "Core Location sometimes reports 0,0")
        #expect(OneShotFix.grade(reading(longitude: 1e-12), now: now) == .invalid)
    }

    @Test func approximateLocationWidensTheThresholds() {
        #expect(OneShotFix.grade(reading(accuracy: 3000), now: now, reduced: true) == .perfect)
        #expect(OneShotFix.grade(reading(accuracy: 9000, age: 5), now: now, reduced: true) == .meh)
        #expect(OneShotFix.grade(reading(accuracy: 3000, age: 700), now: now, reduced: true) == .invalid)
    }

    @Test func aPerfectReadingAnswersAtOnce() {
        var selector = OneShotSelector()
        #expect(selector.verdict(outOfTime: false) == .wait)
        selector.add(reading(accuracy: 500, age: 40), now: now)
        #expect(selector.verdict(outOfTime: false) == .wait, "Meh waits for something better")
        let perfect = reading(accuracy: 20)
        selector.add(perfect, now: now)
        #expect(selector.verdict(outOfTime: false) == .done(perfect))
    }

    @Test func atTheTimeoutTheBestMehReadingAnswers() {
        var selector = OneShotSelector()
        let cached = reading(accuracy: 30, age: 200)
        selector.add(cached, now: now)
        #expect(selector.verdict(outOfTime: true) == .done(cached))
        // Close in time: the more accurate wins.
        let sharper = reading(accuracy: 20, age: 190)
        selector.add(sharper, now: now)
        #expect(selector.verdict(outOfTime: true) == .done(sharper))
        let blurrier = reading(accuracy: 90, age: 195)
        selector.add(blurrier, now: now)
        #expect(selector.verdict(outOfTime: true) == .done(sharper))
        // More than a minute newer: the newer wins even when less accurate.
        let newer = reading(accuracy: 400, age: 100)
        selector.add(newer, now: now)
        #expect(selector.verdict(outOfTime: true) == .done(newer))
        // And an older one never displaces it.
        selector.add(reading(accuracy: 5, age: 300), now: now)
        #expect(selector.verdict(outOfTime: true) == .done(newer))
    }

    @Test func theNewestPerfectReadingWins() {
        var selector = OneShotSelector()
        let older = reading(accuracy: 10, age: 20), newer = reading(accuracy: 90, age: 2)
        selector.add(older, now: now)
        selector.add(newer, now: now)
        #expect(selector.verdict(outOfTime: false) == .done(newer))
        selector.add(older, now: now)
        #expect(selector.verdict(outOfTime: false) == .done(newer))
    }

    @Test func invalidReadingsNeverAnswer() {
        var selector = OneShotSelector()
        #expect(selector.verdict(outOfTime: true) == .fail, "Nothing arrived")
        selector.add(reading(age: 900), now: now)
        selector.add(reading(accuracy: 2000), now: now)
        #expect(selector.verdict(outOfTime: false) == .wait)
        #expect(selector.verdict(outOfTime: true) == .fail)
        selector.reduced = true
        selector.add(reading(accuracy: 2000), now: now)
        #expect(selector.verdict(outOfTime: false) == .done(reading(accuracy: 2000)))
    }
}

@Suite("Not-before bound and new regions")
struct NotBeforeTests {
    let now = Date(timeIntervalSince1970: 1_000_100)

    @Test func readingsBeforeTheBoundAreNeverConsidered() {
        var selector = OneShotSelector(notBefore: now.addingTimeInterval(-10))
        // Cached from before the crossing: perfect on paper, but too old to count.
        selector.add(LocationFix(latitude: 37.6, longitude: -122.3, horizontalAccuracy: 5, timestamp: now.addingTimeInterval(-20)), now: now)
        #expect(selector.verdict(outOfTime: false) == .wait)
        #expect(selector.verdict(outOfTime: true) == .fail)
        let after = LocationFix(latitude: 37.6, longitude: -122.3, horizontalAccuracy: 200, timestamp: now.addingTimeInterval(-5))
        selector.add(after, now: now)
        #expect(selector.verdict(outOfTime: true) == .done(after))
    }

    @Test func theFirstStateOfANewRegionIsIgnoredOnceAndOnlyBriefly() {
        var guardian = NewRegionGuard()
        let neverAdded = guardian.isInitialState("zone.home@000", at: now)
        guardian.added("zone.home@000", at: now)
        let first = guardian.isInitialState("zone.home@000", at: now.addingTimeInterval(2))
        let second = guardian.isInitialState("zone.home@000", at: now.addingTimeInterval(3))
        guardian.added("zone.work", at: now)
        let late = guardian.isInitialState("zone.work", at: now.addingTimeInterval(3600))
        let after = guardian.isInitialState("zone.work", at: now.addingTimeInterval(3601))
        #expect(!neverAdded, "Never added: a real crossing")
        #expect(first)
        #expect(!second, "Only the first state")
        #expect(!late, "A crossing hours later is real")
        #expect(!after)
    }
}

@Suite("Zone entry fuzzer")
struct ZoneEntryFuzzerTests {
    let zone = HAZone(entityID: "zone.home", latitude: 37.6, longitude: -122.3, radius: 33, friendlyName: "Home")
    var regions: [PlannedRegion] { ZonePlanner().regions(for: zone) }

    @Test func aFixJustOutsideTheRegionIsWidenedByTheShortfall() {
        // The @000 circle is centered 67 m north: this fix is 130 m past its center, 30 m past its edge, 10 m accuracy.
        let fix = fixNorth(of: 67 + 130, accuracy: 10)
        let fuzzed = ZoneEntryFuzzer.fuzz(fix, entering: regions[0], of: zone, zoneRegions: regions)
        #expect(abs(fuzzed.horizontalAccuracy - (10 + 20 + 1)) < 0.1, "10 m accuracy, 20 m short of the edge, plus 1")
        #expect(fuzzed.latitude == fix.latitude && fuzzed.longitude == fix.longitude, "The coordinate is never moved")
    }

    @Test func aFixFarOutsideTheRegionIsLeftAlone() {
        let fix = fixNorth(of: 67 + 400, accuracy: 10)
        #expect(ZoneEntryFuzzer.fuzz(fix, entering: regions[0], of: zone, zoneRegions: regions) == fix)
    }

    @Test func aFixInsideTheRegionButOutsideTheOverlapIsLeftAlone() {
        // Inside @000, but not inside the other two circles: no overlap, no widening.
        let fix = fixNorth(of: 67 + 60, accuracy: 5)
        #expect(ZoneEntryFuzzer.fuzz(fix, entering: regions[0], of: zone, zoneRegions: regions) == fix)
    }

    @Test func insideEveryCircleButOutsideTheZoneReachesTheZone() {
        // 50 m north of the center: inside all three circles (with accuracy), 12 m short of the 33 m zone's edge.
        let fix = fixNorth(of: 50, accuracy: 5)
        let fuzzed = ZoneEntryFuzzer.fuzz(fix, entering: regions[0], of: zone, zoneRegions: regions)
        #expect(abs(fuzzed.horizontalAccuracy - (5 + 12 + 1)) < 0.1)
    }

    @Test func aFixInsideTheZoneIsLeftAlone() {
        let fix = fixNorth(of: 5, accuracy: 5)
        #expect(ZoneEntryFuzzer.fuzz(fix, entering: regions[0], of: zone, zoneRegions: regions) == fix)
    }

    @Test func aBigZoneIsItsOwnRegion() {
        let big = HAZone(entityID: "zone.work", latitude: 37.6, longitude: -122.3, radius: 150, friendlyName: "Work")
        let only = ZonePlanner().regions(for: big)
        #expect(only.map(\.id) == ["zone.work"])
        let fix = fixNorth(of: 190, accuracy: 10)
        let fuzzed = ZoneEntryFuzzer.fuzz(fix, entering: only[0], of: big, zoneRegions: only)
        #expect(abs(fuzzed.horizontalAccuracy - (10 + 30 + 1)) < 0.1)
    }
}

@MainActor
@Suite("Official zone events")
struct OfficialZoneEventTests {
    let ticks = LocationTestClock()
    let store = InMemoryZoneStore()
    let info = ["sourceDevicePermanentID": "vendor-1", "sourceDeviceName": "Test Phone", "sourceDeviceID": "vendor-1"]

    func reporter(_ platform: FakeLocationPlatform, _ transport: StubHTTPTransport) -> LocationReporter {
        LocationReporter(
            platform: platform,
            client: MobileAppWebhookClient(source: FixedMobileAppWebhookSource(mobileAppWebhook), transport: transport),
            linksPresence: true, now: { [ticks] in ticks.date }, zoneStore: store, deviceInfo: { [info] in info }
        )
    }

    func always() -> FakeLocationPlatform { FakeLocationPlatform(LocationPermission(authorization: .always)) }

    @Test func eachCrossingFiresTheOfficialEventAndStripsTheCircleSuffix() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 700, at: 1)]
        let transport = StubHTTPTransport(okReplies(6))
        let subject = reporter(platform, transport)
        await subject.start()
        await subject.handle(.zone(.exited("zone.home@120")))
        let fired = try firedEvents(transport)
        #expect(fired.count == 1)
        #expect(fired[0]["event_type"] as? String == "ios.zone_exited")
        let eventData = try #require(fired[0]["event_data"] as? [String: String])
        #expect(eventData["zone"] == "zone.home", "Not zone.home@120")
        #expect(eventData["multi_region_zone_id"] == "120")
        #expect(eventData["sourceDeviceName"] == "Test Phone")
        #expect(eventData["sourceDeviceID"] == "vendor-1")
        #expect(eventData["sourceDevicePermanentID"] == "vendor-1")

        await subject.handle(.zone(.entered("zone.work")))
        let work = try #require(try firedEvents(transport)[1]["event_data"] as? [String: String])
        #expect(try firedEvents(transport)[1]["event_type"] as? String == "ios.zone_entered")
        #expect(work["zone"] == "zone.work")
        #expect(work["multi_region_zone_id"] == nil, "A zone watched whole has no circle id")
    }

    @Test func anEntryFixIsWidenedByTheShortfallAndSentWithoutAName() async throws {
        let platform = always()
        // The @000 circle of the 40 m home zone is centered 60 m north: 190 m north is 130 m from it, 20 m past
        // its edge once the 10 m accuracy is taken off.
        platform.fixes = [fixNorth(of: 5000), fixNorth(of: 190, accuracy: 10, at: 1)]
        let transport = StubHTTPTransport(okReplies(6))
        let subject = reporter(platform, transport)
        await subject.start()
        await subject.handle(.zone(.entered("zone.home@000")))
        let sent = try updateLocations(transport)[1]
        #expect(sent["gps_accuracy"] as? Int == 31)
        #expect(sent["location_name"] == nil)
    }

    @Test func aSecondCircleExitWithinFiveMinutesIsTheSameDeparture() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 400, at: 1), fixNorth(of: 420, at: 400)]
        let transport = StubHTTPTransport(okReplies(12))
        let subject = reporter(platform, transport)
        await subject.start()
        await subject.handle(.zone(.exited("zone.home@000")))
        #expect(try updateLocations(transport).count == 2)
        ticks.advance(60)
        await subject.handle(.zone(.exited("zone.home@120")))
        #expect(try updateLocations(transport).count == 2, "Repeat exit of the same zone from another circle")
        #expect(try firedEvents(transport).count == 2, "The crossing is still fired")
        #expect(platform.timeouts.count == 2, "No fix was even taken for it")
        ticks.advance(300)
        await subject.handle(.zone(.exited("zone.home@240")))
        #expect(try updateLocations(transport).count == 3, "Five minutes on, it counts again")
    }

    @Test func anEntryRearmsTheExit() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 400, at: 1), fixNorth(of: 5, at: 2), fixNorth(of: 400, at: 3)]
        let transport = StubHTTPTransport(okReplies(12))
        let subject = reporter(platform, transport)
        await subject.start()
        await subject.handle(.zone(.exited("zone.home@000")))
        await subject.handle(.zone(.entered("zone.home@000")))
        await subject.handle(.zone(.exited("zone.home@120")))
        #expect(try updateLocations(transport).count == 4)
    }

    @Test func anExitStillInsideTheZoneDoesNotSuppressTheNext() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 10, at: 1), fixNorth(of: 400, at: 2)]
        let transport = StubHTTPTransport(okReplies(12))
        let subject = reporter(platform, transport)
        await subject.start()
        await subject.handle(.zone(.exited("zone.home@000")))
        await subject.handle(.zone(.exited("zone.home@120")))
        #expect(try updateLocations(transport).count == 3, "The first fix was still inside the zone")
    }

    @Test func aFailedSendDoesNotArmTheExitWindow() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 400, at: 1), fixNorth(of: 410, at: 2)]
        let transport = StubHTTPTransport([(200, zonesJSON), (200, "{}"), (500, ""), (200, "{}"), (200, "{}"), (200, "{}")])
        let subject = reporter(platform, transport)
        await subject.start()
        await subject.handle(.zone(.exited("zone.home@000")))
        await subject.handle(.zone(.exited("zone.home@120")))
        #expect(try updateLocations(transport).count == 3)
    }

    @Test func theMadeUpFixOfAnExitWithNoReadingNeverBecomesTheOrderReference() async throws {
        ticks.advance(100)
        let platform = always()
        platform.fixes = [fixNorth(of: 0, at: 50)]
        let transport = StubHTTPTransport(okReplies(8))
        let subject = reporter(platform, transport)
        await subject.start()
        ticks.advance(60)
        await subject.handle(.zone(.exited("zone.home@000")))
        #expect(try updateLocations(transport).count == 2)
        // A reading taken before the crossing (the made-up fix is stamped with the clock, 160) is refused now:
        // it could be a cached one from before the exit.
        platform.fixes = [fixNorth(of: 800, at: 100 + 30)]
        #expect(!(await subject.report(.manual)))
        #expect(try updateLocations(transport).count == 2)
        // One taken after it is in order: the made-up fix never became the order reference.
        platform.fixes = [fixNorth(of: 800, at: 100 + 70)]
        #expect(await subject.report(.manual))
        #expect(try updateLocations(transport).count == 3)
    }

    @Test func aGoneRegistrationOnTheEventStopsReporting() async {
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 400, at: 1)]
        let transport = StubHTTPTransport([(200, zonesJSON), (200, "{}"), (200, "{}"), (410, "")])
        let subject = reporter(platform, transport)
        await subject.start()
        await subject.handle(.zone(.exited("zone.home")))
        #expect(subject.lastError == .registrationGone)
        #expect(!subject.isRunning)
    }

    @Test func aFailedEventIsNotAnError() async {
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 400, at: 1)]
        let transport = StubHTTPTransport([(200, zonesJSON), (200, "{}"), (200, "{}"), (500, "")])
        let subject = reporter(platform, transport)
        await subject.start()
        await subject.handle(.zone(.exited("zone.home")))
        #expect(subject.lastError == nil)
        #expect(subject.isRunning)
    }

    @Test func twoCirclesCrossedTogetherSendOneDeparture() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 400, at: 1), fixNorth(of: 410, at: 2)]
        let transport = StubHTTPTransport(okReplies(10))
        let subject = reporter(platform, transport)
        await subject.start()
        async let first: Void = subject.handle(.zone(.exited("zone.home@120")))
        async let second: Void = subject.handle(.zone(.exited("zone.home@240")))
        _ = await (first, second)
        let updates = try updateLocations(transport)
        #expect(updates.count == 2, "The launch update and one departure")
        #expect(updates[1]["location_name"] as? String == "not_home")
        #expect(try firedEvents(transport).count == 2, "Both crossings are still fired")
        #expect(platform.timeouts.count == 2, "The second took no fix")
    }

    @Test func anExitIsNotAnsweredByAReadingFromBeforeTheCrossing() async throws {
        ticks.advance(100)
        let platform = always()
        platform.fixes = [fixNorth(of: 0, at: 95)]
        let transport = StubHTTPTransport(okReplies(8))
        let subject = reporter(platform, transport)
        await subject.start()
        // A cached reading from 20 s before the crossing, inside the zone.
        platform.fixes = [fixNorth(of: 5, accuracy: 5, at: 80)]
        await subject.handle(.zone(.exited("zone.home@000")))
        #expect(platform.notBefores.last == ticks.date, "The bound is the crossing's receipt time")
        let sent = try updateLocations(transport)[1]
        #expect(sent["location_name"] as? String == "not_home")
        #expect(sent["gps"] as? [Double] == [37.6, -122.3], "The zone center fallback, not the old reading")
        #expect(sent["gps_accuracy"] as? Int == 100)
    }

    @Test func anExitTheFilterRefusesFallsBackToTheZoneCenter() async throws {
        let platform = always()
        // The launch fix is stamped in the future, so the exit's real fix looks out of order and is refused.
        platform.fixes = [fixNorth(of: 0, at: 200), fixNorth(of: 400, at: 150)]
        let transport = StubHTTPTransport(okReplies(8))
        let subject = reporter(platform, transport)
        await subject.start()
        await subject.handle(.zone(.exited("zone.home@000")))
        let updates = try updateLocations(transport)
        #expect(updates.count == 2)
        #expect(updates[1]["location_name"] as? String == "not_home")
        #expect(updates[1]["gps"] as? [Double] == [37.6, -122.3])
    }

    @Test func aFailedExitSendDoesNotRetryWithTheFallback() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 400, at: 1)]
        let transport = StubHTTPTransport([(200, zonesJSON), (200, "{}"), (500, ""), (200, "{}")])
        let subject = reporter(platform, transport)
        await subject.start()
        await subject.handle(.zone(.exited("zone.home@000")))
        #expect(try updateLocations(transport).count == 2)
    }

    @Test func zoneWorkQueuedWhenReportingStopsSendsNothing() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 400, at: 1)]
        let transport = StubHTTPTransport(okReplies(10))
        let subject = reporter(platform, transport)
        await subject.start()
        let before = transport.requests.count
        let gate = AsyncGate()
        platform.gate = gate
        // The first exit is waiting for its fix; the second is queued behind it.
        platform.onEvent?(.zone(.exited("zone.home@000")))
        platform.onEvent?(.zone(.exited("zone.work")))
        await gate.untilEntered()
        await subject.stop()
        gate.open()
        await subject.awaitZoneWork()
        #expect(transport.requests.count == before, "No update and no event after stopping")
        #expect(!subject.isRunning)
    }
}
