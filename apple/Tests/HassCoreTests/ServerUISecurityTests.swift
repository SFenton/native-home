import Foundation
import Testing
@testable import HassCore

// MARK: - Configured security contract

@Suite struct ServerUISecurityTests {
    private typealias E = ServerUICompositionError

    private func fixture() throws -> JSONValue {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var root = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: directory.appendingPathComponent("ServerUICompositionFixture.json")))
        let nodes = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: directory.appendingPathComponent("ServerUISecurityNodes.json")))
        let sources = try #require(root["document"]?["dataSources"]?.array) + #require(nodes["sources"]?.array)
        let components = try #require(root["document"]?["pages"]?.array?[0]["components"]?.array) + #require(nodes["components"]?.array)
        root = try replacing(root, ["document", "dataSources"], .array(sources))
        root = try replacing(root, ["document", "pages", "0", "components"], .array(components))
        return try replacing(root, ["capabilities"], .array((ServerUICompositionPublication.firstSliceCapabilities
            + ["sh.alarm-mode@1", "sh.alarm-panel@1", "sh.security-door@1"]).sorted().map(JSONValue.string)))
    }

    private func replacing(_ root: JSONValue, _ path: [String], _ value: JSONValue?) throws -> JSONValue {
        let key = try #require(path.first)
        switch root {
        case .object(var object):
            object[key] = path.count == 1 ? value : try replacing(#require(object[key]), Array(path.dropFirst()), value)
            return .object(object)
        case .array(var array):
            let index = try #require(Int(key))
            if path.count == 1 {
                if let value { array[index] = value } else { array.remove(at: index) }
            } else { array[index] = try replacing(array[index], Array(path.dropFirst()), value) }
            return .array(array)
        default: throw E(.invalidValue, "")
        }
    }

    private func decode(_ value: JSONValue) throws -> ServerUICompositionPublication {
        try .decode(JSONEncoder().encode(value))
    }

    @Test func compilesTypedOrderedModesAndDomainSpecificDoorSources() throws {
        let publication = try decode(fixture())
        let components = publication.document.pages[0].surface.components
        guard case .alarmPanel(let panel) = components[1], case .stateTile(let lock) = components[2],
              case .stateTile(let garage) = components[3] else { Issue.record("Missing security primitives"); return }
        #expect(panel.modes.map(\.state) == ["disarmed", "armed_home", "armed_away", "armed_night"])
        #expect(panel.confirmation.spec.confirmVerb == "Disarm")
        #expect(panel.confirmation.cancelLabel == "Cancel")
        // A `door-tile` lowers to a `state-tile` over the built-in lock or garage-door style, carried by a saved style of its own.
        #expect(lock.binding.builtIn == "lock" && garage.binding.builtIn == "garage-door")
        #expect(lock.binding.entityId == "lock.demo_unit" && garage.binding.entityId == "cover.demo_unit")
        #expect(lock.binding.styleId == "demo-lock-control.door" && garage.binding.styleId == "demo-garage-control.door")
        #expect(publication.document.stateStyles?.style(id: "demo-garage-control.door") != nil)
        #expect(publication.capabilities.contains("sh.alarm-panel@1"))
        #expect(ServerUICompositionPublication.firstSliceCapabilities.count == 14)
    }

    @Test func compilesModalLocalAlarmAndIndependentStandaloneSheetWithExactCapabilities() throws {
        var root = try fixture()
        var pages = try #require(root["document"]?["pages"]?.array)
        var panel = try #require(pages[0]["components"]?.array?[1])
        panel = try replacing(panel, ["id"], .string("demo-local-panel"))
        var local = pages[2]
        local = try replacing(local, ["id"], .string("demo-local-alarm"))
        local = try replacing(local, ["toolbar"], .object(["type": .string("replace"), "groups": .array([])]))
        local = try replacing(local, ["components"], .array([panel]))
        pages.append(local)
        root = try replacing(root, ["document", "pages"], .array(pages))
        var modals = try #require(root["document"]?["modals"]?.array)
        var link = try #require(modals[0]["components"]?.array?[1])
        link = try replacing(link, ["action", "pageId"], .string("demo-local-alarm"))
        modals[0] = try replacing(modals[0], ["components"], .array([link]))
        var sheet = modals[0]
        sheet = try replacing(sheet, ["id"], .string("demo-standalone-alarm"))
        panel = try replacing(panel, ["id"], .string("demo-sheet-panel"))
        sheet = try replacing(sheet, ["components"], .array([panel]))
        sheet = try replacing(sheet, ["presentation", "height"], .object([
            "type": .string("fitted"), "follows": .string("top-page"), "firstOpen": .string("canonical@1")
        ]))
        modals.append(sheet)
        root = try replacing(root, ["document", "modals"], .array(modals))
        let capabilities = (ServerUICompositionPublication.firstSliceCapabilities
            + ["sh.alarm-mode@1", "sh.alarm-panel@1", "sh.security-door@1", "sh.sheet-fit@1"]).sorted()
        root = try replacing(root, ["capabilities"], .array(capabilities.map(JSONValue.string)))
        let publication = try decode(root)
        #expect(publication.capabilities == capabilities)
        #expect(publication.document.pages.last?.surface.id == "demo-local-alarm")
        #expect(publication.document.modals.last?.surface.id == "demo-standalone-alarm")
        #expect(root["document"]?["modals"]?.array?[0]["components"]?.array?[0]["action"]?["origin"]?.string == "sender")
    }

    @Test func rejectsUnsafeTargetsAmbiguousModesAndUnnegotiatedCapabilities() throws {
        let root = try fixture()
        let panel = ["document", "pages", "0", "components", "1", "props"]
        let cases: [([String], JSONValue?, E.Code)] = [
            (["document", "dataSources", "2", "inputs", "entityId", "value"], JSONValue.string("switch.demo_unit"), E.Code.invalidCombination),
            (["document", "dataSources", "3", "inputs", "entityId", "value"], .string("cover.demo_unit"), .invalidCombination),
            (panel + ["sourceId"], .string("demo-lock"), .bindingType),
            (panel + ["modes", "1", "state"], .string("disarmed"), .invalidCombination),
            (panel + ["modes", "0", "service"], .string("alarm_disarm"), .unknownField),
            (panel + ["confirmation"], nil, .missingRequired),
            (panel + ["confirmation", "cancelLabel"], .string("Ignore"), .unknownVariant),
            (["capabilities"], .array(ServerUICompositionPublication.firstSliceCapabilities.map(JSONValue.string)), .capabilityManifestMismatch)
        ]
        for (path, value, code) in cases {
            #expect(throws: E(code, "/" + path.joined(separator: "/"))) { try decode(replacing(root, path, value)) }
        }
        let wrongDoor = try replacing(root, ["document", "pages", "0", "components", "3", "props", "sourceId"], .string("demo-lock"))
        #expect(throws: E(.bindingType, "/document/pages/0/components/3/props/sourceId")) { try decode(wrongDoor) }
    }

    @Test(arguments: ["disarmed", "armed_home", "armed_away", "armed_night", "arming", "disarming", "pending", "triggered"])
    func commandsUseInjectedTargetAndDisarmAlwaysConfirms(live: String) throws {
        for (mode, service) in ServerUISecurity.modeServices {
            let confirmation = TileActionSpec.Confirmation(title: "Stand down?", message: "Synthetic question", confirmVerb: "Stand down")
            let spec = try #require(ServerUISecurity.alarmMode(entityID: "alarm_control_panel.demo_item",
                live: EntityState(entityId: "alarm_control_panel.demo_item", state: live), selected: mode, confirmation: confirmation))
            #expect(spec.call == ServiceCall("alarm_control_panel", service, target: "alarm_control_panel.demo_item"))
            #expect(spec.confirmation == (mode == "disarmed" ? confirmation : nil))
            #expect(spec.optimistic == [OptimisticIntent("alarm_control_panel.demo_item", value: mode)])
        }
        #expect(ServerUISecurity.alarmMode(entityID: "alarm_control_panel.demo_item", live: nil, selected: "bad",
                                          confirmation: StateStyle.alarmDisarmConfirmation) == nil)
    }
}
