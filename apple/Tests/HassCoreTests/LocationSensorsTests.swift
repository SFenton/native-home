import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// Sensors with every location update (location parity PR C), and the #203 review fix for a request that was waiting
/// for its fix when an exit fell back to the zone's center.
@MainActor
@Suite("Location sensors")
struct LocationSensorsTests {
    let ticks = LocationTestClock()
    let store = InMemoryZoneStore()
    let background = RecordingBackgroundTime()
    let transport = RoutingHTTPTransport([
        "get_zones": [(200, zonesJSON)],
    ])
    let source = ScriptedStatusSource()
    let defaults = freshDefaults()

    func reporter(_ platform: FakeLocationPlatform, source: (any DeviceStatusSource)? = nil) -> LocationReporter {
        let client = MobileAppWebhookClient(source: FixedMobileAppWebhookSource(mobileAppWebhook), transport: transport)
        return LocationReporter(
            platform: platform, client: client, linksPresence: true, now: { [ticks] in ticks.date }, zoneStore: store,
            backgroundTime: background,
            sensors: SensorReporter(client: client, source: source ?? self.source, appVersion: "1", memory: SensorRegistrationMemory(defaults))
        )
    }

    func always() -> FakeLocationPlatform { FakeLocationPlatform(LocationPermission(authorization: .always)) }

    func registeredIDs() -> [String] {
        transport.bodies(of: "register_sensor").compactMap { ($0["data"] as? [String: Any])?["unique_id"] as? String }
    }

    @Test func everyLocationUpdateRegistersThenUpdatesTheSensorsWithItsTrigger() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 500, at: 60)]
        let subject = reporter(platform)
        await subject.start()
        await subject.awaitSensors()
        #expect(Set(registeredIDs()) == allSensorIDs, "Registered with the first update")
        #expect(transport.bodies(of: "update_location").count == 1)
        #expect(source.contexts.map(\.trigger) == [.launch])

        ticks.advance(60)
        #expect(await subject.report(.manual))
        await subject.awaitSensors()
        #expect(transport.bodies(of: "update_location").count == 2)
        // The trigger changed, and so did the zones the geocoded location lists (the fix left Home).
        #expect(Set(updatedIDs(transport)) == ["last_update_trigger", "geocoded_location"])
        #expect(lastUpdatedState("last_update_trigger", transport) as? String == "Manual")
    }

    @Test func theSensorsGeocodeTheSameFixTheLocationCarries() async throws {
        let platform = always()
        let fix = fixNorth(of: 12)
        platform.fixes = [fix]
        let subject = reporter(platform)
        await subject.start()
        await subject.awaitSensors()
        let context = try #require(source.contexts.first)
        #expect(context.fix == fix)
        #expect(context.permission == LocationPermission(authorization: .always))
        #expect(context.zones.map(\.entityID) == ["zone.home", "zone.work"], "The zones from get_zones")
        let sent = try #require(transport.bodies(of: "update_location").first?["data"] as? [String: Any])
        #expect(sent["gps"] as? [Double] == [fix.latitude, fix.longitude])
    }

    @Test func theSensorsRunBesideTheLocationNotBehindIt() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0)]
        let locationGate = AsyncGate(), sensorGate = AsyncGate()
        transport.hold("update_location", at: locationGate)
        let subject = reporter(platform, source: ScriptedStatusSource(gate: sensorGate))
        await subject.start(reportLaunch: false)
        let report = Task { await subject.report(.launch) }
        // Both are in flight at the same moment: the location send is held, and the sensors are already reading the
        // device. Neither waited for the other.
        await locationGate.untilEntered()
        await sensorGate.untilEntered()
        #expect(transport.bodies(of: "register_sensor").isEmpty)
        locationGate.open()
        sensorGate.open()
        #expect(await report.value)
        await subject.awaitSensors()
        #expect(Set(registeredIDs()) == allSensorIDs)
    }

    @Test func backgroundTimeCoversTheSensorsToo() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 500, at: 60)]
        let gate = AsyncGate()
        let subject = reporter(platform, source: ScriptedStatusSource(gate: gate))
        await subject.start(reportLaunch: false)
        ticks.advance(60)
        let update = Task { await subject.requestUpdate(.pushNotification, inBackground: true) }
        await gate.untilEntered()
        #expect(background.held == 1, "Still held while the sensors are read")
        gate.open()
        #expect(await update.value)
        #expect(background.held == 0)
    }

    @Test func aFilteredDuplicateSendsNoSensors() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 2, at: 5)]
        let subject = reporter(platform)
        await subject.start()
        await subject.awaitSensors()
        let sent = transport.requests.count
        ticks.advance(5)
        #expect(!(await subject.report(.pushNotification)), "Within 10 m and 30 s: the filter refuses it")
        #expect(transport.requests.count == sent)
        #expect(source.contexts.count == 1)
    }

    @Test func aFailedLocationSendStillSendsTheSensors() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0)]
        transport.script("update_location", [(500, "")])
        let subject = reporter(platform)
        await subject.start()
        await subject.awaitSensors()
        #expect(subject.lastError == .status(500))
        #expect(Set(registeredIDs()) == allSensorIDs)
    }

    @Test func aFailedSensorUpdateDoesNotFailTheLocation() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0)]
        transport.script("register_sensor", [(500, "")])
        let subject = reporter(platform)
        await subject.start()
        await subject.awaitSensors()
        #expect(subject.lastError == nil)
        #expect(subject.lastReportDate != nil)
        #expect(subject.isRunning)
    }

    @Test func aGoneRegistrationSeenBySensorsStopsReporting() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0)]
        transport.script("register_sensor", [(410, "")])
        let subject = reporter(platform)
        await subject.start()
        await subject.awaitSensors()
        #expect(subject.lastError == .registrationGone)
        #expect(!subject.isRunning)
    }

    @Test func aMadeUpExitFixIsNotGeocoded() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0)]
        let subject = reporter(platform)
        await subject.start()
        await subject.awaitSensors()
        ticks.advance(100)
        await subject.handle(.zone(.exited("zone.home")))
        #expect(subject.lastTrigger == .regionExited)
        #expect(source.contexts.last?.trigger == .regionExited)
        #expect(source.contexts.last?.fix == nil, "The zone's center is not where the phone is")
        #expect(lastUpdatedState("last_update_trigger", transport) as? String == "Geographic Region Exited")
    }

    @Test func theLastUpdateTriggerFollowsEveryKindOfUpdate() async throws {
        let platform = always()
        let subject = reporter(platform)
        platform.fixes = [fixNorth(of: 0)]
        await subject.start()
        await subject.awaitSensors()
        var meters = 0.0
        /// A fix 500 m on from the last, taken a minute later.
        func next() -> LocationFix {
            ticks.advance(60)
            meters += 500
            return fixNorth(of: meters, at: ticks.date.timeIntervalSince1970 - 1_000_000)
        }
        func lastTrigger() -> String? { lastUpdatedState("last_update_trigger", transport) as? String }

        platform.fixes = [next()]
        #expect(await subject.report(.manual))
        await subject.awaitSensors()
        #expect(lastTrigger() == "Manual")
        platform.fixes = [next()]
        #expect(await subject.requestUpdate(.pushNotification, inBackground: true))
        #expect(lastTrigger() == "Push Notification")
        platform.fixes = [next()]
        #expect(await subject.requestUpdate(.backgroundFetch, inBackground: true))
        #expect(lastTrigger() == "Background Fetch")
        platform.fixes = [next()]
        await subject.handle(.significantChange(fixNorth(of: meters, at: ticks.date.timeIntervalSince1970 - 1_000_000)))
        #expect(lastTrigger() == "Significant Location Change")
        platform.fixes = [next()]
        await subject.handle(.zone(.exited("zone.home")))
        #expect(lastTrigger() == "Geographic Region Exited")
        platform.fixes = [next()]
        await subject.handle(.zone(.entered("zone.work")))
        #expect(lastTrigger() == "Geographic Region Entered")
        #expect(source.contexts.map(\.trigger) == [.launch, .manual, .pushNotification, .backgroundFetch,
                                                  .significantLocationChange, .regionExited, .regionEntered])
    }

    // MARK: Sensors never hold up the location work

    @Test func slowSensorsDoNotDelayTheZoneEventOrTheNextOne() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0)]
        let sensorGate = AsyncGate(), fireGate = AsyncGate()
        transport.hold("fire_event", at: fireGate)
        let subject = reporter(platform, source: ScriptedStatusSource(gate: sensorGate))
        await subject.start(reportLaunch: false)

        let first = Task { await subject.handle(.zone(.entered("zone.home"))) }
        // The sensors are stuck reading the device, and the zone event has still gone out.
        await sensorGate.untilEntered()
        await fireGate.untilEntered()
        #expect(transport.bodies(of: "update_location").count == 1)
        fireGate.open()

        // The next zone event starts its own work while the first one's sensors are still stuck.
        let nextFix = AsyncGate()
        platform.fixes = [fixNorth(of: 700, at: 1)]
        platform.gate = nextFix
        platform.gatedRequests = 1
        let second = Task { await subject.handle(.zone(.exited("zone.work"))) }
        await nextFix.untilEntered()
        #expect(transport.bodies(of: "register_sensor").isEmpty, "Still not through the first event's sensors")
        nextFix.open()
        sensorGate.open()
        await first.value
        await second.value
        #expect(Set(registeredIDs()) == allSensorIDs)
        #expect(background.held == 0)
    }

    @Test func theHoldGivesUpOnSlowSensorsWithinTheBackgroundTimeLeft() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 500, at: 60)]
        let gate = AsyncGate()
        let subject = reporter(platform, source: ScriptedStatusSource(gate: gate))
        await subject.start(reportLaunch: false)
        ticks.advance(60)
        background.remaining = 6 // 5 s are kept back: wait 1 s at most
        #expect(await subject.requestUpdate(.pushNotification, inBackground: true), "Returns without the sensors")
        #expect(background.held == 0)
        #expect(transport.bodies(of: "register_sensor").isEmpty)
        // They carry on once let go.
        background.remaining = .infinity
        gate.open()
        await subject.awaitSensors()
        #expect(Set(registeredIDs()) == allSensorIDs)
    }

    // MARK: Huge background time (iOS reports DBL_MAX in the foreground)

    @Test(arguments: [Double.greatestFiniteMagnitude, 1e300, .infinity, .nan])
    func aHugeBackgroundTimeNeverTrapsAndIsClamped(remaining: Double) async throws {
        #expect(OneShotFix.waitLimit(backgroundRemaining: remaining) == 60)
        #expect(OneShotFix.timeout(for: .launch, backgroundRemaining: remaining) == 30)
        #expect(OneShotFix.timeout(for: .pushNotification, backgroundRemaining: remaining) == 10)
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 500, at: 60)]
        let subject = reporter(platform)
        await subject.start(reportLaunch: false)
        ticks.advance(60)
        background.remaining = remaining
        // The wait for the sensors arms a (clamped) timer; it must not trap, and finishes with the sensors.
        #expect(await subject.requestUpdate(.pushNotification, inBackground: true))
        await subject.awaitSensors()
        #expect(Set(registeredIDs()) == allSensorIDs)
        #expect(platform.timeouts.last == 10)
    }

    @Test func waitLimitsAreClampedAndFloored() {
        #expect(OneShotFix.waitLimit(backgroundRemaining: 6) == 1)
        #expect(OneShotFix.waitLimit(backgroundRemaining: 3) == 1)
        #expect(OneShotFix.waitLimit(backgroundRemaining: -40) == 1)
        #expect(OneShotFix.waitLimit(backgroundRemaining: 20) == 15)
        #expect(OneShotFix.waitLimit(backgroundRemaining: 1000) == 60)
        #expect(OneShotFix.waitLimit(backgroundRemaining: 1000, maximum: 10) == 10)
        #expect(OneShotFix.waitLimit(backgroundRemaining: 1000, maximum: 5000) == 60, "Never above the longest wait")
        #expect(OneShotFix.waitLimit(backgroundRemaining: 1000, maximum: 0) == 1)
    }

    // MARK: Stopping

    @Test func stoppingCancelsRunningAndQueuedSensorUpdates() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 500, at: 60)]
        let gate = AsyncGate()
        let subject = reporter(platform, source: ScriptedStatusSource(gate: gate))
        await subject.start(reportLaunch: false)
        #expect(await subject.report(.launch))
        await gate.untilEntered()
        ticks.advance(60)
        #expect(await subject.report(.manual), "A second update queues behind the first one's sensors")
        await subject.stop()
        gate.open()
        await subject.awaitSensors()
        // Neither sent anything: the device read came back after stopping.
        #expect(transport.bodies(of: "register_sensor").isEmpty)
        #expect(transport.bodies(of: "update_sensor_states").isEmpty)
        #expect(!subject.isRunning)
    }

    // MARK: Sensors alone

    @Test func aSensorsOnlyUpdateNeedsNoLocationAndHoldsBackgroundTime() async throws {
        let subject = reporter(FakeLocationPlatform(LocationPermission(authorization: .denied)))
        #expect(!subject.isRunning)
        #expect(await subject.updateSensorsOnly(.backgroundFetch))
        #expect(transport.bodies(of: "update_location").isEmpty)
        #expect(Set(registeredIDs()) == allSensorIDs)
        let trigger = try #require(transport.bodies(of: "register_sensor").compactMap { $0["data"] as? [String: Any] }
            .first { $0["unique_id"] as? String == "last_update_trigger" })
        #expect(trigger["state"] as? String == "Background Fetch")
        #expect(background.begun == ["Background Fetch sensors"])
        #expect(background.held == 0)
        #expect(source.contexts.last?.fix == nil)
    }

    @Test func aSensorsOnlyUpdateOfAGoneRegistrationIsReported() async throws {
        transport.script("register_sensor", [(410, "")])
        let subject = reporter(FakeLocationPlatform(LocationPermission(authorization: .always)))
        await subject.start(reportLaunch: false)
        #expect(!(await subject.updateSensorsOnly(.backgroundFetch)))
        #expect(subject.lastError == .registrationGone)
    }

    @Test func withoutSensorsConfiguredASensorsOnlyUpdateDoesNothing() async {
        let client = MobileAppWebhookClient(source: FixedMobileAppWebhookSource(mobileAppWebhook), transport: transport)
        let subject = LocationReporter(platform: always(), client: client, zoneStore: store)
        #expect(!(await subject.updateSensorsOnly(.backgroundFetch)))
        #expect(transport.requests.isEmpty)
    }

    // MARK: A request waiting for its fix when an exit falls back (#203 review)

    @Test func aLaunchReportInFlightWhenAnExitFallsBackCannotSendAFixFromBeforeTheExit() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0)]
        let subject = reporter(platform)
        await subject.start()
        await subject.awaitSensors()
        let sent = transport.bodies(of: "update_location").count

        // A launch report is waiting for its fix...
        let gate = AsyncGate()
        platform.gate = gate
        platform.gatedRequests = 1
        platform.fixes = []
        let launch = Task { await subject.report(.launch) }
        await gate.untilEntered()
        // ...when the phone leaves and no reading arrives, so the zone's center is sent as not_home.
        ticks.advance(100)
        await subject.handle(.zone(.exited("zone.home")))
        #expect(transport.bodies(of: "update_location").count == sent + 1)
        #expect(subject.lastTrigger == .regionExited)

        // The waiting request now gets the cached reading from before the crossing (at home).
        platform.fixes = [fixNorth(of: 3, at: 50)]
        gate.open()
        #expect(!(await launch.value), "Older than the exit: it must not put the person back home")
        #expect(transport.bodies(of: "update_location").count == sent + 1)
        #expect(subject.lastTrigger == .regionExited)
    }
}
