import Foundation
import Testing
@testable import HassCore

// MARK: - Complete domain composition conformance

struct ServerUIHomeDomainsTests {
    static func fixture() throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("ServerUIHomeDomainsFixture.json"))
    }

    @Test func completeSyntheticDomainRecipesCompileWithoutControllerRouting() throws {
        let publication = try ServerUICompositionPublication.decode(Self.fixture())
        #expect(publication.document.pages.contains { $0.surface.id == "page-home" })
        #expect(publication.document.pages.contains { $0.surface.id == "hc-predictive-detail" })
        #expect(publication.document.modals.contains { $0.surface.id == "hc-climate-sheet" })
        #expect(publication.capabilities.contains("sh.camera-viewer@1"))
        #expect(publication.capabilities.contains("sh.room-visibility@1"))
        #expect(publication.capabilities.contains("sh.climate-link@1"))
        #expect(publication.capabilities.contains("sh.climate-room-tile@1"))
    }

    @Test func roomPowerCannotAttachToDifferentMembership() throws {
        var root = try #require(JSONSerialization.jsonObject(with: Self.fixture()) as? [String: Any])
        var document = try #require(root["document"] as? [String: Any])
        var sources = try #require(document["dataSources"] as? [[String: Any]])
        let index = try #require(sources.firstIndex { ($0["inputs"] as? [String: Any])?["memberEntityIds"] != nil })
        var inputs = try #require(sources[index]["inputs"] as? [String: Any])
        inputs["memberEntityIds"] = [["type": "literal", "value": "light.demo_wrong_room"]]
        sources[index]["inputs"] = inputs
        document["dataSources"] = sources
        root["document"] = document
        do {
            _ = try ServerUICompositionPublication.decode(JSONSerialization.data(withJSONObject: root))
            Issue.record("A different room's members must not be commanded by this disc.")
        } catch let error as ServerUICompositionError {
            #expect(error.code == .invalidCombination && error.pointer.hasSuffix("/powerSourceId"))
        }
    }

    @Test func occupancyDetailUsesSensorCountRatherThanRoomSummary() throws {
        let publication = try ServerUICompositionPublication.decode(Self.fixture())
        let configuration = try #require(publication.document.dataSources.compactMap { source -> ServerUICompositionDocument.HomeStatus? in
            if case .homeStatus(_, let config) = source, config.projection == .occupancy, config.format == .detail { return config }
            return nil
        }.first)
        let value = ServerUIHomeStatus.project(configuration) { EntityState(entityId: $0, state: $0 == configuration.entityIds.first ? "on" : "off") }
        #expect(value.text == "1 sensor occupied")
    }

    @Test func scopedOverviewSubtitleCountsRoomsAndUniqueMembersNotGlobalHouseConfiguration() {
        let groups = [RoomGroup("One", [RoomGroupItem("A", "sensor.demo_a"), RoomGroupItem("B", "sensor.demo_b")]),
                      RoomGroup("Two", [RoomGroupItem("A", "sensor.demo_a")])]
        let read: RoomOverview.Read = { EntityState(entityId: $0, state: "on") }
        #expect(RoomOverview.sheetSubtitle(.occupancy, groups: groups, read: read) == "2 Rooms Occupied")
        #expect(RoomOverview.sheetSubtitle(.lights, groups: groups, read: read) == "2 of 2 On")
        #expect(RoomOverview.sheetSubtitle(.contacts, groups: groups, read: read) == "2 Open")
    }

    @Test func guestCopyFollowsOptimismWithoutHidingFailureOrUnavailable() throws {
        let publication = try ServerUICompositionPublication.decode(Self.fixture())
        func tiles(_ components: [ServerUICompositionDocument.Component]) -> [ServerUICompositionDocument.ActionTile] {
            components.flatMap {
                if case .actionTile(let tile) = $0 { return [tile] }
                return tiles($0.childComponents)
            }
        }
        let tile = try #require(tiles(publication.document.pages.flatMap(\.surface.components)).first { $0.powerLabels != nil })
        let provider = PowerToggleActions.entity("input_boolean.demo_guests")
        for state in ["on", "off", "unavailable"] {
            let spec = try #require(provider.actions(for: EntityState(entityId: "input_boolean.demo_guests", state: state)).first)
            let expected = state == "on" ? "Guests staying" : state == "off" ? "No guests" : "Unavailable"
            #expect(tile.powerText(spec: spec, failed: false, fallback: "Unavailable") == expected)
            #expect(tile.powerText(spec: spec, failed: true, fallback: "Didn't Respond") == "Didn't Respond")
        }
    }

    @MainActor @Test func occupiedOnlyRecipeDoesNotRequireSelectedRoomTracking() throws {
        let publication = try ServerUICompositionPublication.decode(Self.fixture())
        let config = try #require(publication.document.dataSources.compactMap { source -> ServerUIClimateSource? in
            if case .climate(let id, let config) = source, id.hasPrefix("hc-track-occupied-") { return config }
            return nil
        }.first)
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: config.entityId, state: "off")])
        let adapter = ServerUIClimateAdapter(configuration: config, store: store, caller: RecordingCaller())
        #expect(adapter.isEnabled, "Occupied Only is independent of selected-room tracking.")
    }

    @Test func expandedSourceInventoryStillHasAnExactBound() throws {
        var root = try #require(JSONSerialization.jsonObject(with: Self.fixture()) as? [String: Any])
        var document = try #require(root["document"] as? [String: Any])
        var sources = try #require(document["dataSources"] as? [[String: Any]])
        while sources.count < 1_000 {
            sources.append(["id": "extra-source-\(sources.count)", "kind": "ha-entity",
                            "entityId": ["type": "literal", "value": "sensor.demo_extra_\(sources.count)"]])
        }
        document["dataSources"] = sources
        root["document"] = document
        _ = try ServerUICompositionPublication.decode(JSONSerialization.data(withJSONObject: root))
        sources.append(["id": "one-too-many", "kind": "ha-entity",
                        "entityId": ["type": "literal", "value": "sensor.demo_overflow"]])
        document["dataSources"] = sources
        root["document"] = document
        #expect(throws: ServerUICompositionError(.limitExceeded, "/document/dataSources")) {
            try ServerUICompositionPublication.decode(JSONSerialization.data(withJSONObject: root))
        }
    }

    @Test func authoredContactMetadataMustMatchMembershipAndVisibilityRequiresAReadableModel() throws {
        let original = try #require(JSONSerialization.jsonObject(with: Self.fixture()) as? [String: Any])
        for invalidVisibility in [false, true] {
            var root = original
            var document = try #require(root["document"] as? [String: Any])
            var sources = try #require(document["dataSources"] as? [[String: Any]])
            if invalidVisibility {
                let index = try #require(sources.firstIndex { $0["id"] as? String == "hc-guests-status" })
                sources[index] = ["id": "hc-guests-status", "kind": "model", "model": "power-toggle@1",
                                  "inputs": ["entityId": ["type": "literal", "value": "switch.demo_guest"]]]
            } else {
                let index = try #require(sources.firstIndex {
                    ($0["inputs"] as? [String: Any])?["members"] != nil
                })
                var inputs = try #require(sources[index]["inputs"] as? [String: Any])
                var members = try #require(inputs["members"] as? [[String: Any]])
                members[0]["entityId"] = ["type": "literal", "value": "binary_sensor.demo_not_a_member"]
                inputs["members"] = members
                sources[index]["inputs"] = inputs
            }
            document["dataSources"] = sources
            root["document"] = document
            do {
                _ = try ServerUICompositionPublication.decode(JSONSerialization.data(withJSONObject: root))
                Issue.record("Invalid metadata or visibility source accepted")
            } catch let error as ServerUICompositionError {
                #expect(error.code == (invalidVisibility ? .bindingType : .invalidCombination))
            }
        }
    }

    @Test func privateProductionRecipeCompilesWhenExplicitlySupplied() throws {
        guard let path = ProcessInfo.processInfo.environment["SDUI_HOME_PUBLICATION"] else { return }
        let publication = try ServerUICompositionPublication.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        #expect(publication.document.dataSources.count > 100)
        #expect(publication.document.pages.contains { $0.surface.id == "page-climate" })
    }

    @Test func singleMemberFormattingRejectsAmbiguousMultipleTargets() throws {
        var root = try #require(JSONSerialization.jsonObject(with: Self.fixture()) as? [String: Any])
        var document = try #require(root["document"] as? [String: Any])
        var sources = try #require(document["dataSources"] as? [[String: Any]])
        let index = try #require(sources.firstIndex { ($0["inputs"] as? [String: Any])?["format"] as? String == "item" })
        var inputs = try #require(sources[index]["inputs"] as? [String: Any])
        var ids = try #require(inputs["entityIds"] as? [[String: String]])
        ids.append(["type": "literal", "value": "sensor.demo_unexpected_second_member"])
        inputs["entityIds"] = ids
        sources[index]["inputs"] = inputs
        document["dataSources"] = sources
        root["document"] = document
        #expect(throws: ServerUICompositionError(.invalidCombination, "/document/dataSources/\(index)/inputs/entityIds")) {
            try ServerUICompositionPublication.decode(JSONSerialization.data(withJSONObject: root))
        }
    }
}
