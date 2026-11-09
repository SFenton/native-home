import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// A made-up reading with every sensor the app reports. No real address, SSID or coordinates.
func sampleStatus(battery: Int = 80, ssid: String = "TestNet") -> DeviceStatus {
    DeviceStatus(
        battery: .init(level: battery, state: .charging),
        network: .init(connection: .wifi, ssid: ssid, bssid: "aa:bb:cc:dd:ee:ff"),
        appVersion: "1.0 (1)",
        audioOutputs: ["Speaker"],
        place: GeocodedPlace(locality: "Testville", country: "Nowhere", coordinate: [37.6, -122.3]),
        isFocused: false
    )
}

/// Every sensor of ``sampleStatus(battery:ssid:)``, by unique id.
let allSensorIDs: Set<String> = [
    "battery_level", "battery_state", "connectivity_connection_type", "connectivity_ssid", "connectivity_bssid",
    "location-permission", "last_update_trigger", "geocoded_location", "app-version",
    "iphone-audio-output", "focus",
]

/// A device source whose reading a test changes and whose calls it can hold.
final class ScriptedStatusSource: DeviceStatusSource, @unchecked Sendable {
    private let lock = NSLock()
    private var reading: DeviceStatus
    private var seen: [SensorContext] = []
    private let gate: AsyncGate?

    init(_ reading: DeviceStatus = sampleStatus(), gate: AsyncGate? = nil) {
        self.reading = reading
        self.gate = gate
    }

    var status: DeviceStatus {
        get { lock.withLock { reading } }
        set { lock.withLock { reading = newValue } }
    }

    var contexts: [SensorContext] { lock.withLock { seen } }

    func status(for context: SensorContext) async -> DeviceStatus {
        lock.withLock { seen.append(context) }
        if let gate { await gate.wait() }
        return status
    }
}

/// A webhook source whose id a test changes (a new registration).
final class SwitchableWebhookSource: MobileAppWebhookSource, @unchecked Sendable {
    private let lock = NSLock()
    private var id: String?

    init(_ id: String?) { self.id = id }

    func set(_ id: String?) { lock.withLock { self.id = id } }

    func currentWebhook() async -> MobileAppWebhook? {
        lock.withLock { id }.map { MobileAppWebhook(server: mobileAppServer, webhookID: $0) }
    }
}

func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "sensor-tests-\(UUID().uuidString)")! }

/// The unique ids in the entries of every `update_sensor_states` the transport saw, flattened in order.
func updatedIDs(_ transport: RoutingHTTPTransport) -> [String] {
    transport.bodies(of: "update_sensor_states").flatMap { ($0["data"] as? [[String: Any]] ?? []).compactMap { $0["unique_id"] as? String } }
}

/// The state of `id` in the last `update_sensor_states` that carried it.
func lastUpdatedState(_ id: String, _ transport: RoutingHTTPTransport) -> Any? {
    transport.bodies(of: "update_sensor_states").reversed().lazy
        .compactMap { ($0["data"] as? [[String: Any]])?.first { $0["unique_id"] as? String == id } }.first?["state"]
}

@Suite("Sensor reporter")
struct SensorReporterTests {
    let transport = RoutingHTTPTransport()
    let source = ScriptedStatusSource()
    let defaults = freshDefaults()

    func reporter(webhook: any MobileAppWebhookSource = FixedMobileAppWebhookSource(mobileAppWebhook),
                  version: String = "1", source: (any DeviceStatusSource)? = nil) -> SensorReporter {
        SensorReporter(client: MobileAppWebhookClient(source: webhook, transport: transport),
                       source: source ?? self.source, appVersion: version, memory: SensorRegistrationMemory(defaults))
    }

    func registeredIDs() -> [String] {
        transport.bodies(of: "register_sensor").compactMap { ($0["data"] as? [String: Any])?["unique_id"] as? String }
    }

    @Test func theFirstUpdateRegistersEverySensorWithItsStateAndSendsNoUpdate() async throws {
        let subject = reporter()
        let count = try await subject.update(SensorContext(trigger: .launch, permission: LocationPermission(authorization: .always)))
        #expect(Set(registeredIDs()) == allSensorIDs)
        #expect(count == allSensorIDs.count)
        #expect(transport.bodies(of: "update_sensor_states").isEmpty)
        let register = transport.bodies(of: "register_sensor").compactMap { $0["data"] as? [String: Any] }
        let trigger = try #require(register.first { $0["unique_id"] as? String == "last_update_trigger" })
        #expect(trigger["state"] as? String == "Launch")
        #expect(trigger["name"] as? String == "Last Update Trigger")
        let permission = try #require(register.first { $0["unique_id"] as? String == "location-permission" })
        #expect(permission["state"] as? String == "Authorized Always", "The context's permission fills the reading")
        let focus = try #require(register.first { $0["unique_id"] as? String == "focus" })
        #expect(focus["type"] as? String == "binary_sensor")
    }

    @Test func anUnchangedReadingSendsNothing() async throws {
        let subject = reporter()
        try await subject.update(SensorContext(trigger: .launch))
        let sent = transport.requests.count
        #expect(try await subject.update(SensorContext(trigger: .launch)) == 0)
        #expect(transport.requests.count == sent, "No request when nothing changed")
    }

    @Test func onlyWhatChangedIsSent() async throws {
        let subject = reporter()
        try await subject.update(SensorContext(trigger: .launch))
        source.status = sampleStatus(battery: 79)
        let count = try await subject.update(SensorContext(trigger: .launch))
        #expect(Set(updatedIDs(transport)) == ["battery_level", "battery_state"], "Both carry the level")
        #expect(count == 2)
        #expect(lastUpdatedState("battery_level", transport) as? Int == 79)
    }

    @Test func theLastUpdateTriggerShowsTheRealTriggerOnEveryUpdate() async throws {
        let subject = reporter()
        try await subject.update(SensorContext(trigger: .launch))
        for trigger in LocationTrigger.allCases.dropFirst() {
            try await subject.update(SensorContext(trigger: trigger))
            #expect(lastUpdatedState("last_update_trigger", transport) as? String == trigger.rawValue)
        }
        #expect(LocationTrigger.allCases.map(\.rawValue) == [
            "Launch", "Geographic Region Entered", "Geographic Region Exited", "Significant Location Change",
            "Background Fetch", "Push Notification", "Manual",
        ])
        #expect(Set(updatedIDs(transport)) == ["last_update_trigger"], "Nothing else changed")
    }

    @Test func aSensorHomeAssistantDoesNotKnowIsRegisteredThenNotRepeated() async throws {
        let subject = reporter()
        try await subject.update(SensorContext(trigger: .launch))
        let registered = registeredIDs().count
        transport.script("update_sensor_states", [(200, #"{"battery_level":{"success":false,"error":{"code":"not_registered"}},"battery_state":{"success":true}}"#)])
        source.status = sampleStatus(battery: 70)
        try await subject.update(SensorContext(trigger: .launch))
        #expect(Array(registeredIDs().dropFirst(registered)) == ["battery_level"], "Registered again, with its state")
        // Nothing left to send.
        let requests = transport.requests.count
        #expect(try await subject.update(SensorContext(trigger: .launch)) == 0)
        #expect(transport.requests.count == requests)
    }

    @Test func aFailedSensorIsSentAgainAtTheNextUpdate() async throws {
        let subject = reporter()
        try await subject.update(SensorContext(trigger: .launch))
        transport.script("update_sensor_states", [(200, #"{"battery_level":{"success":false,"error":{"code":"invalid_format"}},"battery_state":{"success":true}}"#)])
        source.status = sampleStatus(battery: 70)
        try await subject.update(SensorContext(trigger: .launch))
        #expect(try await subject.update(SensorContext(trigger: .launch)) == 1)
        #expect(updatedIDs(transport).suffix(1) == ["battery_level"])
    }

    @Test func aDisabledSensorIsLeftAloneUntilTheNextLaunch() async throws {
        let subject = reporter()
        try await subject.update(SensorContext(trigger: .launch))
        transport.script("update_sensor_states", [(200, #"{"battery_level":{"success":true,"is_disabled":true},"battery_state":{"success":true}}"#)])
        source.status = sampleStatus(battery: 70)
        try await subject.update(SensorContext(trigger: .manual))
        source.status = sampleStatus(battery: 60)
        try await subject.update(SensorContext(trigger: .manual))
        #expect(!updatedIDs(transport).suffix(2).contains("battery_level"), "Only battery_state, as the disabled one is skipped")
        try await subject.update(SensorContext(trigger: .launch))
        #expect(updatedIDs(transport).suffix(2).contains("battery_level"), "A Launch update asks again")
    }

    @Test func aFailedRequestIsNotRememberedAsSent() async throws {
        let subject = reporter()
        try await subject.update(SensorContext(trigger: .launch))
        source.status = sampleStatus(battery: 50)
        transport.script("update_sensor_states", [(500, "")])
        await #expect(throws: MobileAppWebhookError.status(500)) { try await subject.update(SensorContext(trigger: .manual)) }
        #expect(try await subject.update(SensorContext(trigger: .manual)) > 0, "The next update carries it again")
    }

    @Test func aFailedRegistrationIsAttemptedAgain() async throws {
        let subject = reporter()
        transport.script("register_sensor", [(200, "{}"), (500, "")])
        await #expect(throws: MobileAppWebhookError.status(500)) { try await subject.update(SensorContext(trigger: .launch)) }
        let first = registeredIDs().count
        try await subject.update(SensorContext(trigger: .launch))
        #expect(registeredIDs().count - first == allSensorIDs.count, "Every sensor, from the start")
    }

    @Test func aGoneRegistrationRegistersAgainOnTheNewWebhook() async throws {
        let webhook = SwitchableWebhookSource("old-hook")
        let subject = reporter(webhook: webhook)
        try await subject.update(SensorContext(trigger: .launch))
        source.status = sampleStatus(battery: 50)
        transport.script("update_sensor_states", [(410, "")])
        await #expect(throws: MobileAppWebhookError.registrationGone) { try await subject.update(SensorContext(trigger: .manual)) }
        webhook.set("new-hook")
        let before = registeredIDs().count
        try await subject.update(SensorContext(trigger: .launch))
        #expect(registeredIDs().count - before == allSensorIDs.count)
        let last = try #require(transport.requests.last)
        #expect(last.url?.path == "/api/webhook/new-hook")
    }

    @Test func aNewRegistrationOnAnotherWebhookRegistersAgain() async throws {
        let webhook = SwitchableWebhookSource("hook-a")
        let subject = reporter(webhook: webhook)
        try await subject.update(SensorContext(trigger: .launch))
        webhook.set("hook-b")
        try await subject.update(SensorContext(trigger: .launch))
        #expect(registeredIDs().count == allSensorIDs.count * 2)
    }

    @Test func aGoneRegistrationWithTheSameWebhookIdAlsoStartsOver() async throws {
        let subject = reporter()
        try await subject.update(SensorContext(trigger: .launch))
        transport.script("update_sensor_states", [(410, "")])
        source.status = sampleStatus(battery: 50)
        await #expect(throws: MobileAppWebhookError.registrationGone) { try await subject.update(SensorContext(trigger: .manual)) }
        try await subject.update(SensorContext(trigger: .launch))
        #expect(registeredIDs().count == allSensorIDs.count * 2)
    }

    @Test func aNewAppVersionRegistersAgain() async throws {
        try await reporter(version: "1").update(SensorContext(trigger: .launch))
        try await reporter(version: "2").update(SensorContext(trigger: .launch))
        #expect(registeredIDs().count == allSensorIDs.count * 2)
        // The same version in a later launch does not.
        try await reporter(version: "2").update(SensorContext(trigger: .launch))
        #expect(registeredIDs().count == allSensorIDs.count * 2)
    }

    @Test func noWebhookMeansNothingToSendTo() async {
        let subject = reporter(webhook: FixedMobileAppWebhookSource(nil))
        await #expect(throws: MobileAppWebhookError.notRegistered) { try await subject.update(SensorContext(trigger: .launch)) }
        #expect(transport.requests.isEmpty)
    }

    @Test func theGeocodedLocationListsTheNonPassiveZonesTheFixIsIn() async throws {
        let fix = fixNorth(of: 0)
        let zones = [homeZone, zone("park", north: 10, radius: 500), zone("quiet", north: 0, radius: 500, passive: true),
                     zone("far", north: 5000)]
        let subject = reporter()
        try await subject.update(SensorContext(trigger: .launch, fix: fix, zones: zones))
        let geocoded = try #require(transport.bodies(of: "register_sensor").compactMap { $0["data"] as? [String: Any] }
            .first { $0["unique_id"] as? String == "geocoded_location" })
        let attributes = try #require(geocoded["attributes"] as? [String: Any])
        #expect(attributes["Zones"] as? [String] == ["Home", "Park"], "Smallest first; passive and distant zones left out")
        #expect(geocoded["state"] as? String == "Testville\nNowhere")
        #expect(SensorContext(trigger: .launch, zones: zones).zoneNames.isEmpty, "No fix, no zones")
    }

    @MainActor @Test func updatesRunOneAtATimeInTheOrderAsked() async throws {
        let gate = AsyncGate()
        let held = ScriptedStatusSource(gate: gate)
        let subject = reporter(source: held)
        let first = Task { try await subject.update(SensorContext(trigger: .launch)) }
        await gate.untilEntered()
        let second = Task { try await subject.update(SensorContext(trigger: .manual)) }
        gate.open()
        #expect(try await first.value == allSensorIDs.count)
        #expect(try await second.value == 1, "It saw the first's registration: only the changed trigger is sent")
        #expect(registeredIDs().count == allSensorIDs.count)
        #expect(updatedIDs(transport) == ["last_update_trigger"])
    }

    @MainActor @Test func concurrentUpdatesArriveInTheOrderAsked() async throws {
        let gate = AsyncGate()
        let held = ScriptedStatusSource(gate: gate)
        let subject = reporter(source: held)
        let first = Task { try await subject.update(SensorContext(trigger: .launch)) }
        await gate.untilEntered()
        let asked: [LocationTrigger] = [.manual, .pushNotification, .backgroundFetch, .significantLocationChange,
                                        .regionExited, .regionEntered, .manual, .launch]
        let rest = asked.map { trigger in Task { try await subject.update(SensorContext(trigger: trigger)) } }
        gate.open()
        _ = try await first.value
        for task in rest { _ = try await task.value }
        #expect(held.contexts.map(\.trigger) == [.launch] + asked)
        #expect(lastUpdatedState("last_update_trigger", transport) as? String == "Launch", "The last one asked is the last one sent")
    }

    @Test func aSensorsOnlyContextCarriesNoFixToGeocode() async throws {
        try await reporter().update(SensorContext(trigger: .backgroundFetch))
        #expect(source.contexts.last?.fix == nil)
        #expect(source.contexts.last?.trigger == .backgroundFetch)
    }

    @Test func theFixedSourceAnswersItsReading() async {
        let status = await FixedDeviceStatusSource(sampleStatus()).status(for: SensorContext(trigger: .launch))
        #expect(status == sampleStatus())
    }
}
