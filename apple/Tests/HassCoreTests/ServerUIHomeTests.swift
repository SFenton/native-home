import Foundation
import Testing
import HassTestSupport
@testable import HassCore

// MARK: - Home wire conformance and projections

struct ServerUIHomeTests {
    typealias D = ServerUICompositionDocument

    static func fixture() throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ServerUIHomeFixture.json"))
    }

    private func configuration(_ projection: D.HomeStatus.Projection, ids: [String] = ["light.demo_a", "light.demo_b"],
                               format: D.HomeStatus.Format = .summary) -> D.HomeStatus {
        .init(projection: projection, format: format, entityIds: ids, rangeEntityId: nil, secondaryEntityId: nil,
              alarmEntityId: "alarm_control_panel.demo_panel", awayEntityIds: ["input_boolean.demo_away"],
              labels: .init(idle: "Idle", active: "Detected", countSuffix: " Active", loading: "Reading",
                            unavailable: "Unavailable", empty: "No members", hidden: "Hidden"))
    }

    @Test func wireCompilesWithExactClosureAndTypedAdapters() throws {
        let publication = try ServerUICompositionPublication.decode(Self.fixture())
        guard case .statusRail(let rail) = publication.document.pages[0].surface.components[0],
              case .statusChip(let chip) = rail.children[0],
              case .homeWeather(_, let weather) = publication.document.dataSources[1],
              case .weatherPanel(let hourly) = publication.document.modals[1].surface.components[0] else {
            Issue.record("Expected configured primitives"); return
        }
        #expect(chip.sourceId == "fixture-status")
        #expect(chip.states.first?.appearance.glyph == .solidRGB(red: 255, green: 255, blue: 255))
        #expect(weather.weatherEntityId == "weather.demo_forecast")
        #expect(hourly.modes == [.wind, .condition, .precipitation])
        #expect(hourly.compactHours == 5)
        #expect(publication.capabilities.contains("sh.home-status@1"))
        var root = try #require(JSONSerialization.jsonObject(with: Self.fixture()) as? [String: Any])
        root["capabilities"] = publication.capabilities.filter { $0 != "sh.home-status@1" }
        #expect(throws: ServerUICompositionError(.capabilityManifestMismatch, "/capabilities")) {
            try ServerUICompositionPublication.decode(JSONSerialization.data(withJSONObject: root))
        }
    }

    @Test func homeWireRejectsIncompatibleBindingsAmbiguousModesAndUnknownFields() throws {
        typealias E = ServerUICompositionError
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Self.fixture())
        func replacing(_ value: JSONValue, path: ArraySlice<String>, with replacement: JSONValue) throws -> JSONValue {
            guard let head = path.first else { return replacement }
            switch value {
            case .object(var object):
                object[head] = try replacing(object[head] ?? .null, path: path.dropFirst(), with: replacement)
                return .object(object)
            case .array(var array):
                let index = try #require(Int(head))
                array[index] = try replacing(array[index], path: path.dropFirst(), with: replacement)
                return .array(array)
            default: throw E(.invalidValue, "")
            }
        }
        for (path, replacement, code) in [
            ("/document/pages/0/components/1/props/sourceId", JSONValue.string("fixture-status"), E.Code.bindingType),
            ("/document/dataSources/1/inputs/weatherEntityId/value", .string("switch.demo_other"), .invalidCombination),
            ("/document/dataSources/2/inputs/entityId/value", .string("script.demo_other"), .invalidCombination),
            ("/document/pages/0/components/1/props/initialMode", .string("other"), .unknownVariant),
            ("/document/pages/0/components/1/props/modes", .array([.string("condition"), .string("condition")]), .invalidCombination),
            ("/document/modals/0/components/0/children/0/props/fallback/glyph", .object([
                "type": .string("solid-rgb"), "red": .number(255), "green": .number(255), "blue": .number(255)
            ]), .invalidCombination),
            ("/document/modals/1/components/2/props/highlights", .array([.string("wind"), .string("wind")]), .invalidCombination),
            ("/document/pages/0/components/0/props/pageId", .string("home"), .unknownField)
        ] {
            let candidate = try replacing(fixture, path: path.split(separator: "/").map(String.init)[...], with: replacement)
            #expect(throws: E(code, path)) {
                try ServerUICompositionPublication.decode(JSONEncoder().encode(candidate))
            }
        }
    }

    @Test func explicitPhysicalContactMetadataAndHelperColoursUseCanonicalFormatting() {
        var contact = configuration(.contacts, ids: ["binary_sensor.demo_window_named_sensor"], format: .room)
        contact.members = [.init(entityId: contact.entityIds[0], title: "Window-labelled door", contactCount: 2, contactKind: .door)]
        let result = ServerUIHomeStatus.project(contact) { EntityState(entityId: $0, state: "off") }
        #expect(result.text == "All Doors Closed")
        #expect(result.spoken == result.text)

        for projection in [D.HomeStatus.Projection.climate, .airQuality] {
            var config = configuration(projection, ids: ["sensor.demo_measurement"])
            config.colorEntityId = "input_text.demo_colour"
            let read: (String) -> EntityState? = {
                EntityState(entityId: $0, state: $0 == "input_text.demo_colour" ? "rgba(25, 84, 130, 0.6)" : "70°F - 74°F")
            }
            #expect(ServerUIHomeStatus.project(config, read: read).color?.rgb == 0x195482)
            #expect(ServerUIHomeStatus.project(config, redacted: true, read: read).color == nil)
            #expect(ServerUIHomeStatus.project(config, pending: true, read: read).color == nil)
        }
    }

    @Test func detailItemProjectionsReuseCanonicalContactOccupancyAndVentCopy() {
        let contact = configuration(.contacts, ids: ["binary_sensor.demo_window"], format: .item)
        let closed = ServerUIHomeStatus.project(contact) { EntityState(entityId: $0, state: "off") }
        #expect(closed.text == "Closed" && closed.spoken == "Closed")
        let occupied = ServerUIHomeStatus.project(configuration(.occupancy, ids: ["binary_sensor.demo_presence"], format: .item)) {
            EntityState(entityId: $0, state: "on")
        }
        #expect(occupied.text == "Detected" && occupied.active)
        let vent = ServerUIHomeStatus.project(configuration(.climate, ids: ["cover.demo_vent"], format: .item)) {
            EntityState(entityId: $0, state: "open", attributes: ["current_position": .number(65)])
        }
        #expect(vent.text == "Open · 65%" && vent.active && vent.color == nil)
    }

    @Test func missingAndPartialSensorsNeverClaimAnAllClearHouse() {
        let c = configuration(.lights)
        #expect(ServerUIHomeStatus.project(c) { _ in nil }.unavailable)
        let partial = ServerUIHomeStatus.project(c) { id in id == "light.demo_a" ? EntityState(entityId: id, state: "off") : nil }
        #expect(partial.unavailable)
        let active = ServerUIHomeStatus.project(c) { id in id == "light.demo_a" ? EntityState(entityId: id, state: "on") : nil }
        #expect(active.text == "1 Active")
        #expect(active.spoken == "1 Active, 1 Unavailable")
        #expect(ServerUIHomeStatus.project(configuration(.lights, ids: [])) { _ in nil }.state == "empty")
        #expect(ServerUIHomeStatus.project(c, pending: true) { _ in nil }.text == "Reading")
        #expect(ServerUIHomeStatus.project(c, pending: true, redacted: true) { _ in nil }.text == "Hidden")
    }

    @Test(arguments: [
        ("disarmed", "off", "open-home"), ("disarmed", "on", "open-away"),
        ("armed_home", "on", "open-armed"), ("triggered", "off", "open-armed")
    ])
    func contactsUseInjectedContextAndArmedPrecedence(_ alarm: String, _ away: String, _ expected: String) {
        let value = ServerUIHomeStatus.project(configuration(.contacts, ids: ["binary_sensor.demo_door"])) { id in
            EntityState(entityId: id, state: id.hasPrefix("alarm_") ? alarm : id.hasPrefix("input_boolean.") ? away : "on")
        }
        #expect(value.state == expected)
        #expect(value.active)
    }

    @Test func roomFormattingAndClimateUseOnlyTheirExplicitMembership() {
        let room = configuration(.lights, ids: ["light.demo_a"], format: .room)
        #expect(ServerUIHomeStatus.project(room) { EntityState(entityId: $0, state: "on") }.text == "On")
        let climate = configuration(.climate, ids: ["sensor.demo_a", "sensor.demo_b"], format: .room)
        let value = ServerUIHomeStatus.project(climate) {
            EntityState(entityId: $0, state: $0 == "sensor.demo_a" ? "70.27" : "75.96",
                        attributes: ["unit_of_measurement": .string("°F")])
        }
        #expect(value.text == "70.2°F - 75.9°F")
        #expect(!value.active)
        #expect(ServerUIHomeStatus.project(configuration(.climate, ids: ["input_text.demo_range"])) {
            EntityState(entityId: $0, state: "70°F - 76°F")
        }.text == "70°F - 76°F")
        #expect(ServerUIHomeStatus.project(configuration(.airQuality, ids: ["input_text.demo_aqi"])) {
            EntityState(entityId: $0, state: "12 - 20")
        }.text == "AQI 12 - 20 · PM2.5 Unavailable")
        #expect(RoomOverview.airQualityChipSummary(aqi: nil, pm25: EntityState(entityId: "sensor.demo_pm25", state: "3.1"))
                == "AQI Unavailable · PM2.5 3.1")
    }
}

// MARK: - Actual command lifetime

@MainActor
struct ServerUIHomeLightTests {
    @Test func roomDiscSharesMemberOptimismAndKeepsItsRealLifetime() async throws {
        let caller = HomeHeldCaller(), scheduler = ManualScheduler()
        let live: [String: EntityState] = [
            "light.demo_group": EntityState(entityId: "light.demo_group", state: "off"),
            "light.demo_one": EntityState(entityId: "light.demo_one", state: "on"),
            "light.demo_two": EntityState(entityId: "light.demo_two", state: "off")
        ]
        let actions = OptimisticActions(rules: Dictionary(uniqueKeysWithValues: live.keys.map { ($0, .liveChange) }),
            caller: caller, scheduler: scheduler) { live[$0]?.state }
        let group = ServerUIHomeLightSource(entityId: "light.demo_group", memberEntityIds: ["light.demo_one", "light.demo_two"],
            caller: caller, actions: actions, readMember: { live[$0] }) { live["light.demo_group"] }
        let member = ServerUIHomeLightSource(entityId: "light.demo_one", caller: caller, actions: actions) { live["light.demo_one"] }
        let spec = group.roomPower(title: "Demo Room")
        #expect(spec.isOn == true, "A member can be on before the aggregate catches up.")
        let task = try group.performRoomPower(title: "Demo Room", expected: spec)
        #expect(member.shown?.state == "off")
        #expect(group.roomPower(title: "Demo Room").isOn == false)
        #expect(throws: ServerUIHomeLightSource.Failure.unavailable) {
            try group.performRoomPower(title: "Demo Room", expected: spec)
        }
        await caller.waitUntilStarted()
        #expect(caller.service == "turn_off" && caller.target == "light.demo_group")
        scheduler.fireAll()
        #expect(group.hasPendingIntent && group.inFlight == 1)
        caller.finish(failing: true)
        await task.value
        #expect(group.isFailed && member.shown?.state == "on")
        #expect(!group.hasPendingIntent)
    }

    @Test func actualServicePinsTheSourceAfterItsOptimismExpires() async throws {
        let caller = HomeHeldCaller()
        let scheduler = ManualScheduler()
        let model = ServerUIHomeLightSource(entityId: "light.demo_a", caller: caller, scheduler: scheduler) {
            EntityState(entityId: "light.demo_a", state: "off")
        }
        let task = try model.perform(LightControl.power("light.demo_a", on: true))
        await caller.waitUntilStarted()
        scheduler.fireAll()
        #expect(model.actions.isPending("light.demo_a") == false)
        #expect(model.inFlight == 1)
        #expect(model.hasPendingIntent)
        caller.finish()
        await task.value
        #expect(model.inFlight == 0)
        #expect(!model.hasPendingIntent)
        #expect(caller.service == "turn_on")
        #expect(caller.target == "light.demo_a")
    }

    @Test func lightRevalidatesTargetsServicesAndDimmingAndShowsFailure() async throws {
        let caller = RecordingCaller()
        let model = ServerUIHomeLightSource(entityId: "switch.demo_a", caller: caller) {
            EntityState(entityId: "switch.demo_a", state: "off")
        }
        #expect(throws: ServerUIHomeLightSource.Failure.invalidCommand) { try model.perform(LightControl.power("switch.demo_other", on: true)) }
        #expect(throws: ServerUIHomeLightSource.Failure.invalidCommand) { try model.perform(LightControl.brightness("switch.demo_a", percent: 30)) }
        #expect(caller.calls.isEmpty)
        caller.failNext = true
        await (try model.perform(LightControl.power("switch.demo_a", on: true))).value
        #expect(model.isFailed)
        #expect(model.shown?.state == "off")
    }

    @Test func aRejectionAfterOptimismExpiresStillShowsNativeFailure() async throws {
        let caller = HomeHeldCaller()
        let scheduler = ManualScheduler()
        let model = ServerUIHomeLightSource(entityId: "light.demo_a", caller: caller, scheduler: scheduler) {
            EntityState(entityId: "light.demo_a", state: "off")
        }
        let task = try model.perform(LightControl.power("light.demo_a", on: true))
        await caller.waitUntilStarted()
        scheduler.fireAll()
        caller.finish(failing: true)
        await task.value
        #expect(model.isFailed)
        #expect(model.shown?.state == "off")
        #expect(!model.hasPendingIntent)
    }
}

@MainActor
private final class HomeHeldCaller: HassServiceCalling {
    var continuation: CheckedContinuation<Void, Error>?
    var service: String?
    var target: String?
    private var started: CheckedContinuation<Void, Never>?
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        self.service = service
        target = data["entity_id"] as? String
        try await withCheckedThrowingContinuation {
            continuation = $0
            started?.resume()
            started = nil
        }
    }
    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    struct Failure: Error {}
    func finish(failing: Bool = false) {
        if failing { continuation?.resume(throwing: Failure()) } else { continuation?.resume() }
        continuation = nil
    }
}
