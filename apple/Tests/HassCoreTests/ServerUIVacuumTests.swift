import Foundation
import HassTestSupport
import Testing
@testable import HassCore

// MARK: - Configured vacuum contract

@Suite struct ServerUIVacuumTests {
    static func descriptor() throws -> ServerUIVacuumDescriptor {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ServerUIVacuumDescriptorFixture.json")
        return try JSONDecoder().decode(ServerUIVacuumDescriptor.self, from: Data(contentsOf: url))
    }

    private func publication(primitive: [String: Any], source: String = "source-robot",
                             edit: (inout [String: Any]) throws -> Void = { _ in }) throws -> ServerUICompositionPublication {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("ServerUICompositionFixture.json"))) as? [String: Any])
        var document = try #require(root["document"] as? [String: Any])
        var sources = try #require(document["dataSources"] as? [[String: Any]])
        let descriptor = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.descriptor()))
        sources.append(["id": "source-robot", "kind": "model", "model": "vacuum@1", "inputs": descriptor])
        document["dataSources"] = sources
        var pages = try #require(document["pages"] as? [[String: Any]])
        var nodes = try #require(pages[0]["components"] as? [[String: Any]])
        nodes.append(["id": "robot-control", "title": "Configured Robot", "type": "vacuum-control",
                      "layout": ["span": 1], "props": ["sourceId": source, "primitive": primitive]])
        pages[0]["components"] = nodes
        document["pages"] = pages
        root["document"] = document
        let kind = primitive["kind"] as? String
        let extra = kind == "auto-clean" ? ["sh.vacuum-auto-clean@1"] : kind == "map" ? ["sh.vacuum-map@1"] : kind == "area-editor" ? ["sh.vacuum-map@1", "sh.vacuum-area@1"]
            : kind == "report" || kind == "outcomes" ? ["sh.vacuum-outcomes@1"] : ["sh.vacuum-controls@1"]
        root["capabilities"] = (ServerUICompositionPublication.firstSliceCapabilities + ["sh.vacuum@1"] + extra).sorted()
        try edit(&root)
        return try ServerUICompositionPublication.decode(JSONSerialization.data(withJSONObject: root))
    }

    @Test func descriptorPreservesAuthoredTargetsTransformsAndReportNames() throws {
        let d = try Self.descriptor()
        #expect(ServerUIVacuumValidation.validate(d, at: "/inputs").isEmpty)
        #expect(d.configuration.mapRotationDegrees == 90)
        #expect(d.configuration.mapScale == 0.9)
        #expect(d.configuration.zones[0].segmentName == "Demo Segment")
        #expect(d.configuration.outcomeRoomNames["demo-room"] == "Demo Room")
        #expect(d.configuration.cleanScript == "script.demo_clean")
    }

    @Test func atomicVariantsCompileAndNegotiateExactCapabilities() throws {
        let variants: [[String: Any]] = [
            ["kind": "map", "overlay": "rooms", "height": 300, "runtimeHeight": 460, "label": "Map", "loadingText": "Reading map", "unavailableText": "Map unavailable", "locate": true],
            ["kind": "status", "metric": "battery"],
            ["kind": "notices"],
            ["kind": "settings", "rows": [["role": "passes", "title": "Repeats", "hint": "Select repeats"]]],
            ["kind": "choice", "selection": "rooms", "entityId": "input_boolean.demo_room"],
            ["kind": "choice", "selection": "autoClean", "entityId": "switch.demo_room_skip"],
            ["kind": "consumable", "entityId": "sensor.demo_brush"],
            ["kind": "outcomes"], ["kind": "area-editor", "height": 650,
                "onUse": ["type": "back"], "discardLabel": "Discard", "onDiscard": ["type": "back"]]
        ]
        for variant in variants {
            let p = try publication(primitive: variant)
            #expect(p.capabilities.contains("sh.vacuum@1"))
            #expect(p.document.pages[0].surface.components.last?.node.title == "Configured Robot")
        }
        let icon: [String: Any] = ["type": "sf-symbol", "name": "play", "rendering": "canonical", "unavailable": "reject"]
        let p = try publication(primitive: ["kind": "command", "command": "clean", "icon": icon])
        #expect(p.capabilities.contains("sh.vacuum-controls@1"))
        let destination: [String: Any] = ["type": "push", "pageId": "page-echo", "arguments": [:],
                                         "origin": "sender", "duplicate": "reuse-nearest"]
        let attachments: [[String: Any]] = [
            ["kind": "card", "icon": icon, "commands": ["start_pause", "dock"], "destination": destination],
            ["kind": "report", "destination": destination],
            ["kind": "target", "mode": "area", "icon": icon, "destination": destination],
            ["kind": "clear-area", "icon": icon]
        ]
        for variant in attachments {
            _ = try publication(primitive: variant)
        }
    }

    @Test func rejectsWrongSourceMembershipDuplicateRolesAndMissingCapability() throws {
        #expect(throws: ServerUICompositionError.self) {
            try publication(primitive: ["kind": "choice", "selection": "rooms", "entityId": "input_boolean.demo_other"])
        }
        #expect(throws: ServerUICompositionError.self) {
            try publication(primitive: ["kind": "status", "metric": "battery"], source: "source-power")
        }
        #expect(throws: ServerUICompositionError.self) {
            try publication(primitive: ["kind": "settings", "rows": [
                ["role": "passes", "title": "A", "hint": "A"], ["role": "passes", "title": "B", "hint": "B"]]])
        }
        #expect(throws: ServerUICompositionError.self) {
            try publication(primitive: ["kind": "status", "metric": "battery"]) {
                $0["capabilities"] = ServerUICompositionPublication.firstSliceCapabilities
            }
        }
        #expect(throws: ServerUICompositionError.self) {
            try publication(primitive: ["kind": "report", "destination": ["type": "back"]])
        }
    }

    @Test func automaticCleaningRequiresExplicitDescriptorAndMatchingDomain() throws {
        #expect(throws: ServerUICompositionError.self) { try publication(primitive: ["kind": "auto-clean"]) }
        func authored(_ entityId: String) throws -> ServerUICompositionPublication {
            try publication(primitive: ["kind": "auto-clean"]) { root in
                var document = try #require(root["document"] as? [String: Any])
                var sources = try #require(document["dataSources"] as? [[String: Any]])
                var inputs = try #require(sources[sources.count - 1]["inputs"] as? [String: Any])
                inputs["autoCleanControl"] = ["title": "Demo", "entityId": entityId, "kind": "pause"]
                sources[sources.count - 1]["inputs"] = inputs
                document["dataSources"] = sources
                root["document"] = document
            }
        }
        #expect(try authored("switch.demo_pause").capabilities.contains("sh.vacuum-auto-clean@1"))
        #expect(throws: ServerUICompositionError.self) { try authored("automation.demo_wrong") }
    }
}

// MARK: - Real command lifetime

@MainActor
private final class VacuumHeldCaller: HassServiceCalling {
    var started = false
    var continuation: CheckedContinuation<Void, Error>?
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        started = true
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
}

@MainActor
@Suite struct ServerUIVacuumLifetimeTests {
    @Test func liveAcknowledgementDoesNotReleaseAnUnfinishedCall() async throws {
        let d = try ServerUIVacuumTests.descriptor()
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: d.entityId, state: "docked")])
        let caller = VacuumHeldCaller()
        let c = VacuumController(vacuum: d.configuration, store: store, caller: caller, reconciliationEntities: [:])
        c.locate()
        #expect(c.hasPendingCommand)
        while !caller.started { await Task.yield() }
        c.liveDidChange()
        #expect(c.activeCallCount == 1)
        #expect(c.hasPendingCommand)
        caller.continuation?.resume()
        await c.waitForCalls()
        #expect(!c.hasPendingCommand)
    }
}
