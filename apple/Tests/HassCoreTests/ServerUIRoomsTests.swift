import Foundation
import Testing
@testable import HassCore

// MARK: - Configured room contract and intents

@Suite struct ServerUIRoomsTests {
    private typealias P = ServerUICompositionPublication
    private typealias D = ServerUICompositionDocument

    private func json(_ name: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent(name)))
    }

    private func fixture() throws -> JSONValue {
        guard case .object(var root) = try json("ServerUICompositionFixture.json"),
              case .object(var document) = root["document"],
              case .array(var pages) = document["pages"], case .object(var page) = pages[0],
              case .array(let originalSources) = document["dataSources"],
              case .array(let originalNodes) = page["components"] else { throw FixtureError() }
        let rooms = try json("ServerUIRoomsFixture.json")
        document["dataSources"] = .array(originalSources + (try #require(rooms["sources"]?.array)))
        page["components"] = .array(originalNodes + (try #require(rooms["components"]?.array)))
        pages[0] = .object(page)
        document["pages"] = .array(pages)
        root["document"] = .object(document)
        root["capabilities"] = .array((P.firstSliceCapabilities + [
            "sh.room-navigation@1", "sh.room-card@1", "sh.room-chip@1", "sh.room-section@1", "sh.room-visibility@1"
        ]).sorted().map(JSONValue.string))
        return .object(root)
    }

    private struct FixtureError: Error {}
    private func decode(_ value: JSONValue) throws -> P { try P.decode(JSONEncoder().encode(value)) }
    private func changing(_ value: JSONValue, path: String, to replacement: JSONValue?) throws -> JSONValue {
        let segments = path.split(separator: "/").map(String.init)
        func replace(_ value: JSONValue, _ depth: Int) throws -> JSONValue {
            switch value {
            case .object(var object):
                let key = segments[depth]
                if depth == segments.count - 1 { object[key] = replacement }
                else { object[key] = try replace(#require(object[key]), depth + 1) }
                return .object(object)
            case .array(var array):
                let index = try #require(Int(segments[depth]))
                if depth == segments.count - 1 {
                    if let replacement { array[index] = replacement } else { array.remove(at: index) }
                } else { array[index] = try replace(array[index], depth + 1) }
                return .array(array)
            default: throw FixtureError()
            }
        }
        return try replace(value, 0)
    }
    private func navigation() throws -> D.RoomNavigation {
        let source = try #require(decode(fixture()).document.dataSources.first { $0.id == "source-room-navigation" })
        guard case .roomNavigation(_, let configuration) = source else { throw FixtureError() }
        return configuration
    }

    @Test func closedRoomPlanPreservesAuthoredCompositionAndExactCapabilities() throws {
        let publication = try decode(fixture())
        #expect(publication.capabilities.contains("sh.room-visibility@1"))
        guard case .roomSection(let section) = publication.document.pages[0].surface.components[1],
              case .roomCard(let card) = section.children[0],
              case .roomChip(let chip) = section.children[1] else { throw FixtureError() }
        #expect(section.layout == .leadRow)
        #expect(card.power?.sourceId == "source-room-power")
        #expect(card.action == .push(.init(pageId: "page-echo", arguments: .init(), origin: .sender, duplicate: .reuseNearest)))
        #expect(card.stateLabels.map(\.label) == ["Running", "Stopped"])
        #expect(chip.power == nil)
        let rooms = try navigation()
        #expect(rooms.items.map(\.visitKey) == ["demo-a", "demo-b"])
        #expect(rooms.items[0].action == .dismissThenPush(.init(pageId: "page-echo", arguments: .init(), origin: .sender, duplicate: .reuseNearest)))
    }

    @Test func stableRankingUsesCanonicalCounterParsingAndFreezesWhileVisible() throws {
        let configuration = try navigation()
        #expect(ServerUIRooms.ranked(configuration) { $0.hasSuffix("_b") ? "3.0" : "2" }.map(\.id) == ["room-b", "room-a"])
        for invalid in [nil, "", "unknown", "unavailable", "-1", "0.5", "nan", "9007199254740992"] as [String?] {
            #expect(ServerUIRooms.ranked(configuration) { _ in invalid }.map(\.id) == ["room-a", "room-b"])
        }
        var order = ServerUIRooms.ServerUIRoomOrder()
        #expect(order.items(configuration) { $0.hasSuffix("_b") ? "9" : "0" }.map(\.id) == ["room-b", "room-a"])
        #expect(order.items(configuration) { $0.hasSuffix("_a") ? "100" : "0" }.map(\.id) == ["room-b", "room-a"])
        var reopened = ServerUIRooms.ServerUIRoomOrder()
        #expect(reopened.items(configuration) { _ in nil }.map(\.id) == ["room-a", "room-b"])
    }

    @Test func roomChipFitsStatusRailButArbitraryCardsDoNot() throws {
        let root = try fixture()
        let components = try #require(root["document"]?["pages"]?.array?.first?["components"]?.array)
        let chip = try #require(components[1]["children"]?.array?[1])
        let rail: JSONValue = .object(["id": "room-rail", "title": "Room overview", "type": "status-rail",
            "layout": .object(["span": .number(1)]), "props": .object([:]), "children": .array([chip])])
        var value = try changing(root, path: "/document/pages/0/components/1/children/1", to: rail)
        let capabilities = try #require(value["capabilities"]?.array) + [.string("sh.status-rail@1")]
        value = try changing(value, path: "/capabilities", to: .array(capabilities.sorted { ($0.string ?? "") < ($1.string ?? "") }))
        _ = try decode(value)
        value = try changing(value, path: "/document/pages/0/components/1/children/1/children/0/type", to: "room-card")
        #expect(throws: ServerUICompositionError.self) { try decode(value) }
    }

    @Test func alternateDisplayDoesNotRetargetCommandsAndContactToneUsesEffectiveAwayPrecedence() throws {
        let value = try decode(fixture())
        guard case .roomSection(let section) = value.document.pages[0].surface.components[1],
              case .roomCard(var card) = section.children[0] else { throw FixtureError() }
        let command = card.power
        card.alternate = .init(when: .init(sourceId: "gate", states: ["running"]), sourceId: "alternate", showState: true, subtitleSourceIds: [])
        #expect(ServerUIRooms.display(card) { .init(entityId: $0, state: "running") }.sourceId == "alternate")
        #expect(ServerUIRooms.display(card) { .init(entityId: $0, state: "unavailable") }.sourceId == card.sourceId)
        #expect(card.power == command)
        let sources = D.RoomChipSources(aqiSourceId: nil, colorSourceId: nil, alarmSourceId: nil,
            homeAwaySourceId: "mode", awaySourceIds: ["fallback"], pluralContacts: true)
        for (state, expected) in [("Home", false), ("Away", true), ("unknown", true), ("unavailable", true)] {
            #expect(ServerUIRooms.isAway(sources) { .init(entityId: $0, state: $0 == "mode" ? state : "on") } == expected)
        }
    }

    @Test func visitIntentPinsConfiguredTargetAndKeyWithoutHouseLookup() throws {
        let configuration = try navigation(), call = try #require(ServerUIRooms.visitCall(configuration.items[0], configuration: configuration))
        #expect(call == ServiceCall("script", "turn_on", target: "script.demo_visit",
                                   data: ["variables": .object(["room": .string("demo-a")])]))
    }

    @Test func roomPresentationRetainsUnavailableDisabledAndMappedStateBehavior() throws {
        let publication = try decode(fixture())
        guard case .roomSection(let section) = publication.document.pages[0].surface.components[1],
              case .roomCard(let definition) = section.children[0] else { throw FixtureError() }
        let card = ServerUIRooms.card(definition, entityId: "switch.demo_room")
        let state = EntityState(entityId: card.entityId, state: "on")
        let display = RoomCardDisplay.resolve(card, entity: state, subtitle: RoomFormat.cardState(card, state))
        #expect(display.subtitle == "Running")
        #expect(display.isEnabled)
        #expect(display.semantics == .modal)
        #expect(!RoomCardDisplay.resolve(card, entity: nil, subtitle: nil).isEnabled)
        let disabled = RoomCardDisplay.resolve(card, entity: EntityState(entityId: card.entityId, state: "locked"), subtitle: nil)
        #expect(disabled.isOff)
        #expect(!disabled.isEnabled)
    }

    @Test func invalidRoomReferencesTargetsAndAmbiguousLabelsCannotCompile() throws {
        typealias E = ServerUICompositionError
        let card = "/document/pages/0/components/1/children/0"
        let cases: [(String, JSONValue?, E.Code)] = [
            ("/document/dataSources/4/visitScriptEntityId/value", .string("switch.demo_wrong"), .invalidCombination),
            ("/document/dataSources/4/items/0/counterEntityId", nil, .invalidCombination),
            ("/document/dataSources/4/items/0/visitKey", nil, .invalidCombination),
            (card + "/binding/sourceId", .string("source-room-navigation"), .bindingType),
            (card + "/props/visibility/sourceId", .string("source-power"), .bindingType),
            (card + "/props/stateLabels/1/state", .string("on"), .invalidCombination),
            (card + "/props/expression", .string("return true"), .unknownField),
            ("/capabilities", .array(P.firstSliceCapabilities.map(JSONValue.string)), .capabilityManifestMismatch),
        ]
        for (path, replacement, code) in cases {
            let value = try changing(fixture(), path: path, to: replacement)
            #expect(throws: E(code, path)) { try decode(value) }
        }
    }

    @Test func appLaunchRemainsAnExplicitSiblingCapabilityGap() throws {
        let path = "/document/pages/0/components/1/children/0"
        let value = try changing(fixture(), path: path + "/type", to: .string("room-app-launch"))
        #expect(throws: ServerUICompositionError(.unsupportedCapability, path + "/type", capability: "sh.room-app-launch@1")) {
            try decode(value)
        }
    }
}

// MARK: - Recording-only command lifetime

@MainActor
private final class RoomVisitFixtureCaller: HassServiceCalling {
    var calls: [ServiceCall] = []
    var continuation: CheckedContinuation<Void, Error>?
    var started: CheckedContinuation<Void, Never>?
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        calls.append(ServiceCall(domain, service, data: data.mapValues { JSONValue(any: $0) }))
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started?.resume(); started = nil
        }
    }
    func waitForStart() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }
}

@Suite @MainActor struct ServerUIRoomVisitLifetimeTests {
    @Test func visitRemainsPendingThroughNetworkLifetimeAndReportsFailure() async {
        struct Failure: Error {}
        let caller = RoomVisitFixtureCaller(), visits = ServerUIRoomVisits(caller: caller)
        var errors = 0
        let call = ServiceCall("script", "turn_on", target: "script.demo_visit", data: ["variables": .object(["room": .string("demo-a")])])
        visits.record(call) { _ in errors += 1 }
        #expect(visits.pendingCount == 1)
        await caller.waitForStart()
        #expect(caller.calls.count == 1)
        #expect(caller.calls.first?.serviceData == call.serviceData)
        #expect(visits.pendingCount == 1)
        caller.continuation?.resume(throwing: Failure())
        caller.continuation = nil
        await visits.waitForCalls()
        #expect(visits.pendingCount == 0)
        #expect(errors == 1)
    }
}
