import HassCore
import Observation
import XCTest
@testable import HassUI

@MainActor
@Observable
private final class SyntheticAccountProvider: UKServerUIAccountProvider {
    var account: UKServerUIAccountValue = .loading
}

// MARK: - Typed reads and power policy

@MainActor
final class ServerUIRendererBindingsTests: XCTestCase {
    func testConfiguredTodoCountsFollowEntityBoxesAndShowUnavailable() throws {
        var fixture = try ServerUIRendererFixture.json()
        var sources = try XCTUnwrap(fixture["document"]?["dataSources"]?.array)
        sources.append(.object([
            "id": .string("chores-counts"), "kind": .string("model"), "model": .string("todo-counts@1"),
            "inputs": .object(["lists": .array([
                .object(["entityId": .object(["type": .string("literal"), "value": .string("todo.demo_late")]), "overdue": .bool(true)]),
                .object(["entityId": .object(["type": .string("literal"), "value": .string("todo.demo_other")]), "overdue": .bool(false)]),
            ])]),
            "labels": .object(["openSuffix": .string("open"), "overdueSuffix": .string("late"), "separator": .string(" / "),
                               "zeroText": .string("Clear"), "loadingText": .string("Loading"), "unavailableText": .string("Unavailable")]),
        ]))
        fixture = try ServerUIRendererFixture.changing(fixture, path: "/document/dataSources", to: .array(sources))
        fixture = try ServerUIRendererFixture.changing(fixture, path: "/capabilities",
            to: .array((ServerUICompositionPublication.firstSliceCapabilities + ["sh.todo-counts@1"]).sorted().map(JSONValue.string)))
        fixture = try ServerUIRendererFixture.changing(fixture, path: "/document/pages/2/components/0/props/value",
            to: .object(["type": .string("read"), "from": .object(["type": .string("source"), "sourceId": .string("chores-counts"),
                        "path": .array([.string("stateText")])]), "as": .string("string"), "missing": .string("unavailable")]))
        let publication = try ServerUIRendererFixture.publication(fixture)
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "todo.demo_late", state: "2"), EntityState(entityId: "todo.demo_other", state: "1")])
        let bindings = UKServerUIBindings(sources: publication.document.dataSources, context: UKContext(store: store))
        guard case .text(let text) = publication.document.pages[2].surface.components[0] else { return XCTFail("Fixture read") }
        XCTAssertEqual(bindings.string(text.value).value, "3 open / 2 late")
        store.apply([EntityState(entityId: "todo.demo_late", state: "unavailable")])
        XCTAssertEqual(bindings.string(text.value).value, "Unavailable")
        store.apply([EntityState(entityId: "todo.demo_late", state: "0"), EntityState(entityId: "todo.demo_other", state: "0")])
        XCTAssertEqual(bindings.string(text.value).value, "Clear")
    }

    func testConfiguredSprinklerReadsUpdateWithoutCallsAndLeaveMissingBatteryUnavailable() throws {
        var fixture = try ServerUIRendererFixture.json()
        var sources = try XCTUnwrap(fixture["document"]?["dataSources"]?.array)
        let source = try JSONDecoder().decode(JSONValue.self, from: Data("""
            {"id":"source-irrigation","kind":"model","model":"sprinkler-state@1","inputs":{
              "title":"Test controller","lowBatteryPercent":25,
              "stateEntityId":{"type":"literal","value":"sensor.test_state"},
              "modeEntityId":{"type":"literal","value":"select.test_mode"},
              "batteryEntityId":{"type":"literal","value":"sensor.test_battery"},
              "faultEntityId":{"type":"literal","value":"binary_sensor.test_fault"},
              "nextWateringEntityId":{"type":"literal","value":"sensor.test_next"},
              "hubConnectedEntityId":{"type":"literal","value":"binary_sensor.test_hub"},
              "rainDelayEntityId":{"type":"literal","value":"switch.test_rain"},
              "smartWateringEntityId":{"type":"literal","value":"switch.test_smart"},
              "zones":[{"valveEntityId":{"type":"literal","value":"valve.test_zone"},
                        "programEntityId":{"type":"literal","value":"switch.test_program"},
                        "historyEntityId":{"type":"literal","value":"sensor.test_history"}}]}}
            """.utf8))
        sources.append(source)
        fixture = try ServerUIRendererFixture.changing(fixture, path: "/document/dataSources", to: .array(sources))
        let value = try JSONDecoder().decode(JSONValue.self, from: Data("""
            {"type":"read","from":{"type":"source","sourceId":"source-irrigation","path":["status"]},
             "as":"string","missing":"unavailable"}
            """.utf8))
        fixture = try ServerUIRendererFixture.changing(fixture, path: "/document/pages/2/components/0/props/value", to: value)
        fixture = try ServerUIRendererFixture.changing(fixture, path: "/capabilities",
            to: .array((ServerUICompositionPublication.firstSliceCapabilities + ["sh.sprinkler-state@1"]).sorted().map(JSONValue.string)))
        let publication = try ServerUIRendererFixture.publication(fixture)
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "sensor.test_state", state: "auto"),
                          EntityState(entityId: "valve.test_zone", state: "closed")])
        let caller = HostedCaller()
        let bindings = UKServerUIBindings(sources: publication.document.dataSources, context: UKContext(store: store, caller: caller))
        guard case .text(let text) = publication.document.pages[2].surface.components[0],
              case .read(let status, _, _) = text.value,
              case .some(.sprinklerState(_, let configuration)) = publication.document.dataSources.last else {
            return XCTFail("Expected configured sprinkler read")
        }
        XCTAssertEqual(bindings.read(status).value, .string("ready"))
        XCTAssertNil(ServerUISprinklerState.value("batteryPercent", configuration: configuration) { store.entity($0).state })
        store.apply([EntityState(entityId: "valve.test_zone", state: "open")])
        XCTAssertEqual(bindings.read(status).value, .string("watering"))
        XCTAssertTrue(caller.calls.isEmpty)
    }

    func testConfiguredAwayStatusReadsOnlyTheRequestedSensorAndPreservesUnavailable() throws {
        var root = try ServerUIRendererFixture.json()
        var sources = try XCTUnwrap(root["document"]?["dataSources"]?.array)
        sources.append(.object([
            "id": .string("source-away"), "kind": .string("model"), "model": .string("household-away-status@1"),
            "inputs": .object(["entityId": .object(["type": .string("literal"), "value": .string("sensor.example_away")])]),
        ]))
        root = try ServerUIRendererFixture.changing(root, path: "/document/dataSources", to: .array(sources))
        let caps = ServerUICompositionPublication.firstSliceCapabilities + ["sh.household-away-status@1"]
        root = try ServerUIRendererFixture.changing(root, path: "/capabilities", to: .array(caps.sorted().map(JSONValue.string)))
        root = try ServerUIRendererFixture.changing(root, path: "/document/pages/2/components/0/props/value", to: .object([
            "type": .string("read"), "from": .object(["type": .string("source"), "sourceId": .string("source-away"),
                                                       "path": .array([.string("mode")])]),
            "as": .string("string"), "missing": .string("unavailable"),
        ]))
        let publication = try ServerUIRendererFixture.publication(root)
        guard case .text(let text) = publication.document.pages[2].surface.components[0] else { return XCTFail("Expected text") }
        let store = EntityStore()
        let bindings = UKServerUIBindings(sources: publication.document.dataSources, context: UKContext(store: store))
        guard case .unavailable = bindings.string(text.value) else { return XCTFail("Missing sensor must be unavailable") }
        store.apply([EntityState(entityId: "sensor.example_away", state: "scheduled", attributes: [
            "contract_version": .number(1), "mode": .string("solo_trip"), "command_available": .bool(true),
        ])])
        XCTAssertEqual(bindings.string(text.value).value, "solo_trip")
        store.apply([EntityState(entityId: "sensor.example_away", state: "unavailable")])
        guard case .unavailable = bindings.string(text.value) else { return XCTFail("Unavailable sensor must not report idle") }
    }
    func testAccountHeaderRequiresPrivateProviderAndUpdatesInPlace() throws {
        func json(_ text: String) throws -> JSONValue {
            try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        }
        var fixture = try ServerUIRendererFixture.json()
        var sources = try XCTUnwrap(fixture["document"]?["dataSources"]?.array)
        sources.append(try json(#"{"id":"private-account","kind":"model","model":"profile-account@1"}"#))
        fixture = try ServerUIRendererFixture.changing(fixture, path: "/document/dataSources", to: .array(sources))
        var nodes = try XCTUnwrap(fixture["document"]?["pages"]?.array?[0]["components"]?.array)
        nodes.append(try json("""
            {"id":"account-card","title":"Account","type":"account-header","layout":{"span":1},
             "binding":{"sourceId":"private-account","projection":"profile-account@1"},
             "props":{"fallbackName":"Signed In","loadingText":"Loading account","unavailableText":"Account unavailable"}}
            """))
        fixture = try ServerUIRendererFixture.changing(fixture, path: "/document/pages/0/components", to: .array(nodes))
        let capabilities = (ServerUICompositionPublication.firstSliceCapabilities + ["sh.profile-account@1"]).sorted()
        fixture = try ServerUIRendererFixture.changing(fixture, path: "/capabilities", to: .array(capabilities.map(JSONValue.string)))
        let publication = try ServerUIRendererFixture.publication(fixture)
        XCTAssertThrowsError(try UKServerUIRenderer.preflight(publication)) {
            XCTAssertEqual(($0 as? UKServerUIRendererError)?.code, .unavailableSource)
        }
        let provider = SyntheticAccountProvider()
        let host = try UKServerUIRenderer(publication: publication, context: UKContext(store: EntityStore()),
                                          backdrop: ServerUIRendererFixture.backdrop(), accountProvider: provider)
        let window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: 390, height: 844)))
        defer { window.isHidden = true }
        HostedPage.wait(0.1)
        let page = try ServerUIRendererFixture.root(host)
        let header = try XCTUnwrap(page.nodes["account-card"]?.view)
        XCTAssertGreaterThan(header.bounds.height, 0)
        XCTAssertGreaterThan(header.sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)).height, 0)
        XCTAssertEqual(header.accessibilityLabel, "Loading account")
        provider.account = .ready(name: "Sample Person", server: "Sample Server", avatar: nil)
        HostedPage.wait(0.1)
        XCTAssertTrue(page.nodes["account-card"]?.view === header)
        XCTAssertEqual(header.accessibilityLabel, "Sample Person, Sample Server")
        provider.account = .ready(name: nil, server: "Sample Server", avatar: nil)
        HostedPage.wait(0.1)
        XCTAssertEqual(header.accessibilityLabel, "Signed In, Sample Server")
        provider.account = .unavailable
        HostedPage.wait(0.1)
        XCTAssertEqual(header.accessibilityLabel, "Account unavailable")
    }

    func testPowerUsesExplicitOnOffAndRetainsItsActionModelForRepeatedOptimisticTaps() async throws {
        let publication = try ServerUIRendererFixture.publication()
        let caller = HostedCaller()
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "switch.demo_lamp", state: "off")])
        let bindings = UKServerUIBindings(sources: publication.document.dataSources, context: UKContext(store: store, caller: caller))
        let power = try XCTUnwrap(bindings.powers["source-power"])
        let first = power.projection(entityID: "switch.demo_lamp", symbol: "power")
        try power.perform(entityID: "switch.demo_lamp", spec: first.spec)
        let actions = try XCTUnwrap(power.actions["switch.demo_lamp"])
        XCTAssertEqual(power.projection(entityID: "switch.demo_lamp", symbol: "power").spec.phase, .inFlight)
        await actions.waitForCalls()
        let completed = await FeatureHost.settleAsync(until: {
            power.projection(entityID: "switch.demo_lamp", symbol: "power").spec.phase == .ready
        })
        XCTAssertTrue(completed)
        let optimistic = power.projection(entityID: "switch.demo_lamp", symbol: "power")
        XCTAssertEqual(optimistic.text, "On")
        XCTAssertEqual(optimistic.spec.phase, .ready, "Optimistic feedback does not invent an in-flight lockout.")
        try power.perform(entityID: "switch.demo_lamp", spec: optimistic.spec)
        await actions.waitForCalls()
        XCTAssertEqual(caller.calls, ["switch.turn_on", "switch.turn_off"])
        XCTAssertEqual(caller.data.count, 2)
        XCTAssertTrue(caller.data.allSatisfy { Set($0.keys) == ["entity_id"] && $0["entity_id"] as? String == "switch.demo_lamp" })
        XCTAssertTrue(power.actions["switch.demo_lamp"] === actions)
    }

    func testRejectedPowerRollsBackUsingCanonicalFailureFeedback() async throws {
        let caller = HostedCaller()
        caller.fails = true
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "input_boolean.demo_flag", state: "off")])
        let power = UKServerUIPowerSource(context: UKContext(store: store, caller: caller))
        let projection = power.projection(entityID: "input_boolean.demo_flag", symbol: "power")
        try power.perform(entityID: "input_boolean.demo_flag", spec: projection.spec)
        let actions = try XCTUnwrap(power.actions["input_boolean.demo_flag"])
        await actions.waitForCalls()
        let failed = power.projection(entityID: "input_boolean.demo_flag", symbol: "power")
        XCTAssertEqual(caller.calls, ["input_boolean.turn_on"])
        XCTAssertEqual(failed.text, "Didn't Respond")
        XCTAssertTrue(failed.failed)
        XCTAssertFalse(failed.spec.isOn == true)
    }

    func testRuntimeEntityDomainAssertionBlocksReadDerivedTargetsOutsidePowerProfile() throws {
        var fixture = try ServerUIRendererFixture.json()
        let read: JSONValue = .object([
            "type": .string("read"),
            "from": .object(["type": .string("source"), "sourceId": .string("source-entity"),
                              "path": .array([.string("attributes"), .string("target")])]),
            "as": .string("entity-id"), "missing": .string("unavailable"),
        ])
        fixture = try ServerUIRendererFixture.changing(fixture, path: "/document/dataSources/1/inputs/entityId", to: read)
        let publication = try ServerUIRendererFixture.publication(fixture)
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "switch.demo_lamp", state: "on", attributes: ["target": .string("light.demo_other")])])
        let caller = HostedCaller()
        let bindings = UKServerUIBindings(sources: publication.document.dataSources, context: UKContext(store: store, caller: caller))
        guard case .unavailable = bindings.entityID(for: "source-power") else { return XCTFail("Power domain assertion must reject light") }
        let power = try XCTUnwrap(bindings.powers["source-power"])
        let invalid = power.projection(entityID: "light.demo_other", symbol: "power")
        XCTAssertThrowsError(try power.perform(entityID: "light.demo_other", spec: invalid.spec))
        XCTAssertTrue(power.actions.isEmpty)
        XCTAssertTrue(caller.calls.isEmpty)

        store.apply([EntityState(entityId: "switch.demo_lamp", state: "on", attributes: ["target": .string("input_boolean.demo_flag")])])
        XCTAssertEqual(bindings.entityID(for: "source-power").value, "input_boolean.demo_flag")
        store.apply([EntityState(entityId: "switch.demo_lamp", state: "on", attributes: ["target": .string("switch.demo_other\n")])])
        guard case .unavailable = bindings.entityID(for: "source-power") else { return XCTFail("Entity grammar must match the complete value") }
        XCTAssertTrue(caller.calls.isEmpty)
    }

    func testUnavailableReadsDoNotBecomeSuccessfulStateTextAndPendingSourcesCannotRebind() throws {
        let publication = try ServerUIRendererFixture.publication()
        let store = EntityStore()
        let caller = HostedCaller()
        store.replaceAll([EntityState(entityId: "switch.demo_lamp", state: "unknown")])
        let bindings = UKServerUIBindings(sources: publication.document.dataSources, context: UKContext(store: store, caller: caller))
        guard case .text(let text) = publication.document.pages[2].surface.components[0] else { return XCTFail("Fixture read") }
        guard case .unavailable = bindings.string(text.value) else { return XCTFail("Unknown is unavailable runtime data") }
        store.apply([EntityState(entityId: "switch.demo_lamp", state: "off")])
        XCTAssertEqual(bindings.string(text.value).value, "off")
        let power = try XCTUnwrap(bindings.powers["source-power"])
        try power.perform(entityID: "switch.demo_lamp", spec: power.projection(entityID: "switch.demo_lamp", symbol: "power").spec)
        let next = try ServerUIRendererFixture.changing(ServerUIRendererFixture.json(),
                                                       path: "/document/dataSources/1/inputs/entityId/value", to: .string("switch.demo_other"))
        let replacement = try ServerUIRendererFixture.publication(next)
        XCTAssertThrowsError(try bindings.validateReplacement(replacement.document.dataSources)) {
            XCTAssertEqual(($0 as? UKServerUIRendererError)?.code, .interactionBlocked)
        }
        XCTAssertEqual(bindings.entityID(for: "source-power").value, "switch.demo_lamp")
    }
}
