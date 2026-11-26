import CryptoKit
import Foundation
import Testing
@testable import HassCore

// MARK: - Frozen synthetic contract conformance

/// Publication copied from the frozen contract's first-native-slice, with no private inputs.
/// `#filePath` keeps the fixture independent of build/research and Package.swift resources.
@Suite struct ServerUICompositionTests {
    private typealias P = ServerUICompositionPublication
    private typealias D = ServerUICompositionDocument
    private typealias E = ServerUICompositionError

    private let grid = "/document/pages/0/components/0"
    private let power = "/document/pages/0/components/0/children/0"
    private let text = "/document/pages/2/components/0/props/value"
    private let presentation = "/document/modals/0/presentation"

    private func fixture() throws -> JSONValue {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ServerUICompositionFixture.json")
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    private func bytes(_ value: JSONValue) throws -> Data { try JSONEncoder().encode(value) }
    private func decode(_ value: JSONValue) throws -> P { try P.decode(bytes(value)) }

    /// Minimal JSON-pointer replacement/removal for independent synthetic mutations.
    private func changing(_ root: JSONValue, _ pointer: String, _ replacement: JSONValue?) throws -> JSONValue {
        let parts = pointer.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map {
            $0.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
        }
        func replace(_ value: JSONValue, _ depth: Int) throws -> JSONValue {
            let part = parts[depth]
            switch value {
            case .object(var object):
                if depth == parts.count - 1 { object[part] = replacement }
                else { object[part] = try replace(#require(object[part]), depth + 1) }
                return .object(object)
            case .array(var array):
                let index = try #require(Int(part))
                if depth == parts.count - 1 {
                    if let replacement { array[index] = replacement } else { array.remove(at: index) }
                } else { array[index] = try replace(array[index], depth + 1) }
                return .array(array)
            default: throw E(.invalidValue, pointer)
            }
        }
        return try replace(root, 0)
    }
    private func expect(_ root: JSONValue, _ code: E.Code, _ pointer: String, capability: String? = nil,
                        sourceLocation: SourceLocation = #_sourceLocation) throws {
        #expect(throws: E(code, pointer, capability: capability), sourceLocation: sourceLocation) { try decode(root) }
    }
    private func mutation(_ pointer: String, _ replacement: JSONValue?, _ code: E.Code,
                          at expected: String? = nil, capability: String? = nil,
                          sourceLocation: SourceLocation = #_sourceLocation) throws {
        try expect(changing(fixture(), pointer, replacement), code, expected ?? pointer,
                   capability: capability, sourceLocation: sourceLocation)
    }
    private func value(_ json: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)) }
    private func manifest(_ root: JSONValue) throws -> JSONValue {
        let assets = try #require(root["document"]?["assets"])
        let digest = SHA256.hash(data: Data(ServerUICompositionJSON.canonical(assets).utf8))
            .map { String(format: "%02x", $0) }.joined()
        return try changing(root, "/assetManifestSha256", .string(digest))
    }

    @Test func groupedSheetRevealRequiresAnExplicitCapability() throws {
        #expect(try decode(fixture()).document.modals.first?.presentation.groupedReveal == false)
        let url = ServerUIContractCorpusTests.directory.appendingPathComponent("reject/pending-sheet-reveal-grouped.json")
        let root = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        #expect(try decode(root).document.modals.first?.presentation.groupedReveal == true)
        let capabilities = try #require(root["capabilities"]?.array).filter { $0.string != "sh.sheet-reveal@1" }
        try expect(changing(root, "/capabilities", .array(capabilities)), .capabilityManifestMismatch, "/capabilities")
    }

    @Test(arguments: ["fitted", "adaptive", "fullscreen"])
    func groupedRevealRejectsLayoutsOtherThanNonadaptiveFullHeightSheets(_ layout: String) throws {
        let url = ServerUIContractCorpusTests.directory.appendingPathComponent("reject/sheet-reveal-\(layout).json")
        let root = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        try expect(root, .invalidCombination, "\(presentation)/reveal")
    }

    @Test func supportingTextStylesRequireTheirCapabilityWithoutChangingOriginalStyles() throws {
        for style in ["subheadline", "footnote", "section-title"] {
            var root = try changing(fixture(), "/document/pages/2/components/0/props/style", .string(style))
            try expect(root, .capabilityManifestMismatch, "/capabilities")
            let capability = style == "section-title" ? "sh.section-title@1" : "sh.supporting-text-styles@1"
            let capabilities = (P.firstSliceCapabilities + [capability]).sorted().map(JSONValue.string)
            root = try changing(root, "/capabilities", .array(capabilities))
            #expect(try decode(root).capabilities.contains(capability))
        }
        #expect(try decode(fixture()).capabilities == P.firstSliceCapabilities)
    }

    @Test func climateAtomicVariantsCompileWithExactCapabilitiesAndRejectInvalidBindings() throws {
        var root = try fixture()
        var sources = try #require(root["document"]?["dataSources"]?.array)
        var nodes = try #require(root["document"]?["pages"]?.array?[0]["components"]?.array)
        for (index, kind) in ServerUIClimateControl.Kind.allCases.enumerated() {
            let domain = kind == .toggle || kind == .check || kind == .explicitSwitch ? "switch" : kind == .options ? "select" : "climate"
            let homeAway = kind == .notice ? #","homeAway":{"modeEntityId":"sensor.demo_mode","reasonEntityId":"sensor.demo_reason","fallbackEntityId":"binary_sensor.demo_away","vacationEntityId":"input_boolean.demo_vacation"}"#
                : kind == .roomTile ? #","sensorEntityId":"sensor.demo_temperature","occupancyEntityId":"sensor.demo_occupancy""# : ""
            sources.append(try value("""
                {"id":"source-climate-\(index)","kind":"model","model":"climate@1",
                 "inputs":{"entityId":"\(domain).demo_zone","rangeCommitEntityIds":[]\(homeAway)}}
                """))
            var props = try value("""
                {"kind":"\(kind.rawValue)","sourceId":"source-climate-\(index)","icon":"thermometer","hint":"",
                 "loadingText":"Reading","unavailableText":"No climate data","errorText":"Try again"}
                """)
            switch kind {
            case .dial:
                props = try changing(props, "/dial", value(#"{"minimum":5,"maximum":35,"step":0.5,"unit":"°C","size":"modal"}"#))
            case .mode, .fan, .preset, .options:
                props = try changing(props, "/choices", value(#"[{"value":"eco","label":"Economy","icon":"leaf","detail":"Save energy"}]"#))
            case .status, .link:
                props = try changing(props, "/status", value(#"{"projection":"indoor","unit":"°C","states":[],"fallbackText":"No forecast"}"#))
            case .hub:
                props = try changing(props, "/hub", value(#"{"modeLabel":"Mode","fanLabel":"Fan","modes":[{"value":"heat","label":"Heat","icon":"flame","detail":""}],"fans":[]}"#))
            case .notice:
                props = try changing(props, "/notice", value(#"{"useEffectiveMode":true,"isWarning":false,"awayText":"Away active","vacationText":"Vacation active","unknownText":"Unknown mode","unavailableModeText":"No mode","reasonFallback":"No reason","separator":" / "}"#))
            default: break
            }

            var fields: [String: JSONValue] = ["id": .string("control-\(index)"), "title": .string("Authored Zone"),
                                  "type": .string("climate-control"), "layout": .object(["span": .number(1)]), "props": props]
            if [.link, .roomTile].contains(kind) {
                fields["action"] = .object(["type": .string("push"), "pageId": try #require(root["document"]?["pages"]?.array?[0]["id"]),
                                            "arguments": .object([:]), "origin": .string("sender"), "duplicate": .string("reuse-nearest")])
            }
            nodes.append(.object(fields))
        }
        root = try changing(root, "/document/dataSources", .array(sources))
        root = try changing(root, "/document/pages/0/components", .array(nodes))
        let capabilities = Set(P.firstSliceCapabilities + ["sh.climate-source@1"] + ServerUIClimateControl.Kind.allCases.map(\.capability)).sorted()
        root = try changing(root, "/capabilities", .array(capabilities.map(JSONValue.string)))
        #expect(try decode(root).document.pages[0].surface.components.count == ServerUIClimateControl.Kind.allCases.count + 1)
        try expect(changing(root, "/capabilities", .array(P.firstSliceCapabilities.map(JSONValue.string))),
                   .capabilityManifestMismatch, "/capabilities")
        try expect(changing(root, "/document/pages/0/components/1/props/dial/maximum", .number(4)),
                   .invalidCombination, "/document/pages/0/components/1/props/dial")
        try expect(changing(root, "/document/pages/0/components/1/props/sourceId", .string("source-power")),
                   .bindingType, "/document/pages/0/components/1/props/sourceId")
        try expect(changing(root, "/document/pages/0/components/1/props/expression", .string("run()")),
                   .unknownField, "/document/pages/0/components/1/props/expression")
    }

    @Test func sharedFixtureCompilesToTypedPlan() throws {
        let publication = try decode(fixture())
        #expect(publication.capabilities == P.firstSliceCapabilities)
        #expect(publication.document.navigation.tabs.map(\.id) == ["tab-alpha", "tab-beta"])
        #expect(publication.document.pages.map(\.id) == ["page-orbit", "page-lattice", "page-echo"])
        let first = try #require(publication.document.pages.first)
        guard case .grid(let grid) = first.surface.components[0],
              case .actionTile(let tile) = grid.children[0],
              case .navigationTile(let navigation) = grid.children[1] else {
            Issue.record("Expected typed grid and tile variants"); return
        }
        #expect(grid.spacing.points == 12)
        #expect(first.surface.layout.spacing.points == 24)
        #expect(first.surface.layout.padding.leading.points == 16)
        #expect(tile.binding.sourceId == tile.action.sourceId)
        #expect(tile.action.confirmation == .policy)
        #expect(navigation.action == .push(.init(pageId: "page-echo", arguments: .init(), origin: .sender, duplicate: .reuseNearest)))
        #expect(publication.document.modals[0].presentation.close.visibility == .rootOnly)
    }

    @Test @MainActor func configuredSpeakerArgumentRequiresItsCapabilityAndPreservesClosedBounds() throws {
        try HouseConfigSource.$scoped.withValue(ServerUIRemoteTestProvider.houseSource()) {
            try speakerArgumentBody()
        }
    }

    @MainActor private func speakerArgumentBody() throws {
        var root = try fixture()
        let descriptor = ServerUIRemoteDescriptor(configuration: ServerUIRemoteTestProvider.config(), cards: [])
        var inputs = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(descriptor))
        inputs = try changing(inputs, "/devices/0/icon", .string("mdi:speaker"))
        inputs = try changing(inputs, "/volumeMute/action", value("""
            {"type":"state","entityId":"media_player.demo_volume","cases":[
              {"states":["playing"],"command":{"type":"service","call":{"domain":"script","service":"demo_mute",
                "data":{"speakerdevice":["media_player.demo_volume"]}},"optimistic":[]}}
            ],"otherwise":{"type":"service","call":{"domain":"script","service":"demo_unmute",
                "data":{}},"optimistic":[]}}
            """))
        var sources = try #require(root["document"]?["dataSources"]?.array)
        let index = sources.count
        sources.append(.object(["id": "configured-remote", "kind": "model", "model": "media-remote-config@1", "inputs": inputs]))
        root = try changing(root, "/document/dataSources", .array(sources))
        let legacy = (P.firstSliceCapabilities + ["sh.media-remote-config@1"]).sorted()
        let capabilities = (legacy + ["sh.remote-speaker-targets@1"]).sorted()
        root = try changing(root, "/capabilities", .array(capabilities.map(JSONValue.string)))
        #expect(try decode(root).capabilities == capabilities)
        try expect(changing(root, "/capabilities", .array(legacy.map(JSONValue.string))),
                   .capabilityManifestMismatch, "/capabilities")
        let data = "/document/dataSources/\(index)/inputs/volumeMute/action/cases/0/command/call/data"
        for invalid: JSONValue in [.string("media_player.demo_volume"),
                                   .array(Array(repeating: .string("media_player.demo_volume"), count: 17))] {
            #expect(throws: E.self) { try decode(changing(root, data + "/speakerdevice", invalid)) }
        }
        try expect(changing(root, data + "/password", .string("not-accepted")), .unknownField, data + "/password")
        let oldArgument = try changing(root, data, value(#"{"sonosdevice":["media_player.demo_volume"]}"#))
        #expect(try decode(changing(oldArgument, "/capabilities", .array(legacy.map(JSONValue.string)))).capabilities == legacy)
    }

        @Test func sprinklerSourceRequiresExplicitConfigurationAndProjectsCanonicalState() throws {
            var root = try fixture()
            var sources = try #require(root["document"]?["dataSources"]?.array)
            sources.append(try value("""
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
                """))
            root = try changing(root, "/document/dataSources", .array(sources))
            root = try changing(root, text, value("""
                {"type":"read","from":{"type":"source","sourceId":"source-irrigation","path":["status"]},
                 "as":"string","missing":"unavailable"}
                """))
            try expect(root, .capabilityManifestMismatch, "/capabilities")
            root = try changing(root, "/capabilities", .array((P.firstSliceCapabilities + ["sh.sprinkler-state@1"]).sorted().map(JSONValue.string)))
            let publication = try decode(root)
            guard case .some(.sprinklerState(_, let config)) = publication.document.dataSources.last else {
                Issue.record("Expected sprinkler state"); return
            }
            let states = [
                "sensor.test_state": EntityState(entityId: "sensor.test_state", state: "auto"),
                "select.test_mode": EntityState(entityId: "select.test_mode", state: "auto"),
                "sensor.test_battery": EntityState(entityId: "sensor.test_battery", state: "23"),
                "binary_sensor.test_fault": EntityState(entityId: "binary_sensor.test_fault", state: "on"),
                "valve.test_zone": EntityState(entityId: "valve.test_zone", state: "open")
            ]
            func projection(_ field: String) -> JSONValue? {
                ServerUISprinklerState.value(field, configuration: config) { states[$0] }
            }
            #expect(projection("status") == .string("fault"))
            #expect(projection("batteryLow") == .bool(true))
            #expect(projection("batteryPercent") == .number(23))
            #expect(projection("hubConnected") == nil)
            #expect(ServerUISprinklerState.value("status", configuration: config) { _ in nil } == .string("unavailable"))
            let source = "/document/dataSources/2/inputs"
            try expect(changing(root, source + "/zones/0/valveEntityId/value", .string("switch.test_zone")),
                       .invalidCombination, source + "/zones/0/valveEntityId/value")
            try expect(changing(root, text + "/from/path", .array([.string("batteryLow")])),
                       .bindingType, text + "/as")
            try expect(changing(root, text + "/from/path", .array([.string("bogus")])),
                       .invalidReference, text + "/from/path")
        }

        @Test func activityPresentationRequiresNegotiatedDeliveryCapability() throws {
            let activity = try value("""
                [{"id":"activity-demo","jobId":"fan.demo_unit","type":"activity-presentation@1","title":"Cleaning","glyph":"fan",
                  "tint":"air","source":"activity-engine@1","privacy":"system-sensitive@1",
                  "updates":"engine@1","intents":"engine-safe@1"}]
                """)
            try expect(changing(fixture(), "/document/liveActivities", activity), .capabilityManifestMismatch, "/capabilities")
            let invalid = try value("""
                [{"id":"activity-demo","jobId":"fan.demo_unit","type":"activity-presentation@1","title":"Cleaning","glyph":"fan",
                  "tint":"air","source":"activity-engine@1","privacy":"public",
                  "updates":"engine@1","intents":"engine-safe@1"}]
                """)
            try expect(changing(fixture(), "/document/liveActivities", invalid), .unknownVariant,
                       "/document/liveActivities/0/privacy")
        }

    @Test func settingsLinkNegotiatesNavigationAndRejectsMisleadingPresentation() throws {
        let link = try value("""
            {"id":"settings-demo","type":"settings-link","title":"Sample setting",
             "layout":{"span":1},"icon":{"type":"sf-symbol","name":"gearshape","rendering":"canonical","unavailable":"reject"},
             "props":{"subtitle":"Open details","hint":"Opens details","showsChevron":true},
             "action":{"type":"push","pageId":"page-echo","arguments":{},"origin":"sender","duplicate":"reuse-nearest"}}
            """)
        var root = try changing(fixture(), "/document/pages/2/components/0", link)
        let caps = P.firstSliceCapabilities + ["sh.settings-link@1"]
        root = try changing(root, "/capabilities", .array(caps.sorted().map(JSONValue.string)))
        guard case .settingsLink(let row) = try decode(root).document.pages[2].surface.components[0] else {
            Issue.record("Expected a settings link"); return
        }
        #expect(row.subtitle == "Open details")
        #expect(row.hint == "Opens details")
        #expect(row.showsChevron)
        try expect(changing(root, "/document/pages/2/components/0/props/showsChevron", .bool(false)),
                   .invalidCombination, "/document/pages/2/components/0/props/showsChevron")
        try expect(changing(root, "/document/pages/2/components/0/action/pageId", .string("missing")),
                   .invalidReference, "/document/pages/2/components/0/action/pageId")
        try expect(changing(root, "/capabilities", .array(caps.filter { $0 != "sh.settings-link@1" }.sorted().map(JSONValue.string))),
                   .capabilityManifestMismatch, "/capabilities")
        let gridLink = try changing(link, "/id", .string("settings-grid"))
        let gridChild = try changing(root, "/document/pages/0/components/0/children/1", gridLink)
        try expect(gridChild, .invalidCombination, "/document/pages/0/components/0/children/1")
    }

    private func profileFixture() throws -> JSONValue {
        var root = try fixture()
        var sources = try #require(root["document"]?["dataSources"]?.array)
        sources.append(try value(#"{"id":"private-account","kind":"model","model":"profile-account@1"}"#))
        root = try changing(root, "/document/dataSources", .array(sources))
        let header = try value("""
            {"id":"account-card","title":"Account","type":"account-header","layout":{"span":1},
             "binding":{"sourceId":"private-account","projection":"profile-account@1"},
             "props":{"fallbackName":"Signed In","loadingText":"Loading account","unavailableText":"Account unavailable"}}
            """)
        var nodes = try #require(root["document"]?["pages"]?.array?[2]["components"]?.array)
        nodes.append(header)
        root = try changing(root, "/document/pages/2/components", .array(nodes))
        return try changing(root, "/capabilities",
                            .array((P.firstSliceCapabilities + ["sh.profile-account@1"]).sorted().map(JSONValue.string)))
    }

    @Test func profileAccountCompilesWithoutPublishingPersonalSnapshots() throws {
        let root = try profileFixture()
        let plan = try decode(root).document
        guard case .profileAccount(let id) = plan.dataSources.last,
              case .accountHeader(let header) = plan.pages[2].surface.components.last else {
            Issue.record("Expected private account source and header"); return
        }
        #expect(id == "private-account")
        #expect(header.sourceId == id)
        #expect(header.fallbackName == "Signed In")
        try expect(changing(root, "/capabilities", .array(P.firstSliceCapabilities.map(JSONValue.string))),
                   .capabilityManifestMismatch, "/capabilities")
        try expect(changing(root, "/document/dataSources/2/token", .string("not-a-token")),
                   .unknownField, "/document/dataSources/2/token")
        try expect(changing(root, "/document/dataSources/2/name", .string("Synthetic")),
                   .unknownField, "/document/dataSources/2/name")
        try expect(changing(root, "/document/pages/2/components/1/binding/sourceId", .string("source-power")),
                   .bindingType, "/document/pages/2/components/1/binding/sourceId")
        try expect(changing(root, "/document/pages/2/components/1/binding/sourceId", .string("missing")),
                   .invalidReference, "/document/pages/2/components/1/binding/sourceId")
        try expect(changing(root, "/document/pages/2/components/0/props/value/from/sourceId", .string("private-account")),
                   .invalidReference, "/document/pages/2/components/0/props/value/from/path")
    }

    private func liveFixture() throws -> JSONValue {
        var root = try fixture()
        var sources = try #require(root["document"]?["dataSources"]?.array)
        sources += try #require(value("""
            [{"id":"source-panel","kind":"model","model":"alarm-mode@1",
              "inputs":{"entityId":{"type":"literal","value":"alarm_control_panel.demo_panel"}}},
             {"id":"source-stock","kind":"model","model":"inventory-summary@1",
              "inputs":{"totalEntityId":{"type":"literal","value":"sensor.demo_total"},
                        "expiringEntityId":{"type":"literal","value":"sensor.demo_expiry"},
                        "spaceEntityIds":[{"type":"literal","value":"sensor.demo_space"}]},
              "labels":{"singular":"Unit","plural":"Units","expiringSuffix":"Due","separator":" / ",
                        "loadingText":"Reading stock","unavailableText":"Stock unavailable"}}]
            """).array)
        root = try changing(root, "/document/dataSources", .array(sources))
        let props = grid + "/children/1/props"
        root = try changing(root, props + "/selected", .string("none"))
        root = try changing(root, props + "/subtitle", value(#"{"type":"literal","value":""}"#))
        root = try changing(root, props + "/alarm", value("""
            {"sourceId":"source-panel","projection":"alarm-navigation@1",
             "states":[{"state":"disarmed","appearance":{"icon":{"type":"sf-symbol","name":"shield.slash",
               "rendering":"canonical","unavailable":"reject"},"fill":{"type":"solid-rgb","red":67,"green":160,"blue":71},"text":"At rest"}}],
             "fallback":{"icon":{"type":"sf-symbol","name":"shield","rendering":"canonical","unavailable":"reject"},
               "fill":{"type":"solid-rgb","red":84,"green":110,"blue":122},"text":"Panel"},
             "loadingText":"Reading panel","unavailableText":"Panel unavailable","errorText":"No response","hiddenText":"Private"}
            """))
        root = try changing(root, text, value("""
            {"type":"read","from":{"type":"source","sourceId":"source-stock","path":["stateText"]},"as":"string","missing":"unavailable"}
            """))
        return try changing(root, "/capabilities", .array((P.firstSliceCapabilities
            + ["sh.alarm-mode@1", "sh.inventory-summary@1", "sh.tile-presentation@1"]).sorted().map(JSONValue.string)))
    }

    @Test func todoCountsHaveClosedShapeAndExactCapability() throws {
        var root = try fixture()
        var sources = try #require(root["document"]?["dataSources"]?.array)
        sources.append(try value("""
            {"id":"source-chores","kind":"model","model":"todo-counts@1",
             "inputs":{"lists":[{"entityId":{"type":"literal","value":"todo.demo_unit"},"overdue":true}]},
             "labels":{"openSuffix":"open","overdueSuffix":"late","separator":" / ","zeroText":"All clear",
                       "loadingText":"Loading","unavailableText":"Unavailable"}}
            """))
        root = try changing(root, "/document/dataSources", .array(sources))
        root = try changing(root, text, value("""
            {"type":"read","from":{"type":"source","sourceId":"source-chores","path":["stateText"]},"as":"string","missing":"unavailable"}
            """))
        try expect(root, .capabilityManifestMismatch, "/capabilities")
        root = try changing(root, "/capabilities", .array((P.firstSliceCapabilities + ["sh.todo-counts@1"]).sorted().map(JSONValue.string)))
        guard case .some(.todoCounts(_, let config)) = try decode(root).document.dataSources.last else {
            Issue.record("Expected configured counts"); return
        }
        #expect(config.lists.first?.entityId == "todo.demo_unit")
        let list = "/document/dataSources/2/inputs/lists"
        try expect(changing(root, list + "/0/entityId/value", .string("sensor.demo_unit")), .invalidCombination, list + "/0/entityId/value")
        let entry = try #require(root["document"]?["dataSources"]?.array?[2]["inputs"]?["lists"]?.array?.first)
        try expect(changing(root, list, .array([entry, entry])), .invalidCombination, list + "/1/entityId/value")
        try expect(changing(root, text + "/from/path", .array([.string("count")])), .invalidReference, text + "/from/path")
    }

    @Test func configuredAlarmAndInventoryCompileWithoutFeatureIdentityDispatch() throws {
        let publication = try decode(liveFixture())
        guard case .alarmMode(_, let target) = publication.document.dataSources[2],
              case .inventorySummary(_, let summary) = publication.document.dataSources[3],
              case .grid(let grid) = publication.document.pages[0].surface.components[0],
              case .navigationTile(let tile) = grid.children[1] else { Issue.record("Expected live adapters"); return }
        #expect(target == "alarm_control_panel.demo_panel")
        #expect(summary.spaceEntityIds == ["sensor.demo_space"])
        #expect(summary.singular == "Unit")
        #expect(tile.alarm?.sourceId == "source-panel")
        #expect(tile.alarm?.states.first?.appearance.text == "At rest")
        #expect(tile.action == .push(.init(pageId: "page-echo", arguments: .init(), origin: .sender, duplicate: .reuseNearest)))
        try expect(changing(liveFixture(), "/capabilities", .array(P.firstSliceCapabilities.map(JSONValue.string))),
                   .capabilityManifestMismatch, "/capabilities")
    }

    @Test func inventoryListSourceHasAnIndependentClosedCapability() throws {
        var root = try fixture()
        var sources = try #require(root["document"]?["dataSources"]?.array)
        sources.append(try value(#"{"id":"source-items","kind":"model","model":"inventory-list@1","inputs":{"space":"fridge"}}"#))
        root = try changing(root, "/document/dataSources", .array(sources))
        try expect(root, .capabilityManifestMismatch, "/capabilities")
        root = try changing(root, "/capabilities", .array((P.firstSliceCapabilities + ["sh.inventory-list@1"])
            .sorted().map(JSONValue.string)))
        let last = try #require(decode(root).document.dataSources.last)
        guard case .inventoryList(let id, let space) = last else {
            Issue.record("Expected inventory list source"); return
        }
        #expect(id == "source-items")
        #expect(space == .fridge)
        try expect(changing(root, "/document/dataSources/2/inputs/space", .string("other")),
                   .unknownVariant, "/document/dataSources/2/inputs/space")
        let read = try value(#"{"type":"read","from":{"type":"source","sourceId":"source-items","path":["stateText"]},"as":"string","missing":"unavailable"}"#)
        try expect(changing(root, text, read), .invalidReference, text + "/from/path")
    }

    @Test func householdAwayStatusUsesExplicitSensorAndExactCapability() throws {
        var root = try fixture()
        var sources = try #require(root["document"]?["dataSources"]?.array)
        sources.append(try value("""
            {"id":"source-away","kind":"model","model":"household-away-status@1",
             "inputs":{"entityId":{"type":"literal","value":"sensor.example_away"}}}
            """))
        root = try changing(root, "/document/dataSources", .array(sources))
        root = try changing(root, text, value("""
            {"type":"read","from":{"type":"source","sourceId":"source-away","path":["mode"]},"as":"string","missing":"unavailable"}
            """))
        try expect(root, .capabilityManifestMismatch, "/capabilities")
        root = try changing(root, "/capabilities", .array((P.firstSliceCapabilities + ["sh.household-away-status@1"]).sorted().map(JSONValue.string)))
        let last = try #require(decode(root).document.dataSources.last)
        guard case .householdAwayStatus(_, let id) = last else {
            Issue.record("Expected away status source"); return
        }
        #expect(id == "sensor.example_away")
        try expect(changing(root, "/document/dataSources/2/inputs/entityId/value", .string("switch.example")),
                   .invalidCombination, "/document/dataSources/2/inputs/entityId/value")
        try expect(changing(root, text + "/from/path", .array([.string("traveler")])), .invalidReference, text + "/from/path")
        try expect(changing(root, text + "/as", .string("boolean")), .bindingType, text + "/as")
    }

    @Test func liveAdaptersRejectWrongTypesTargetsUnknownFieldsAndAmbiguousAppearances() throws {
        let root = try liveFixture(), alarm = grid + "/children/1/props/alarm"
        for (path, replacement, code) in [
            ("/document/dataSources/2/inputs/entityId/value", JSONValue.string("switch.demo_panel"), E.Code.invalidCombination),
            ("/document/dataSources/3/inputs/totalEntityId/value", .string("sensor.demo_total\n"), .invalidValue),
            ("/document/dataSources/3/inputs/spaceEntityIds", .array([]), .limitExceeded),
            ("/document/dataSources/3/labels/singular", .string(" "), .invalidValue),
            ("/document/dataSources/3/labels/expression", .string("return 12"), .unknownField),
            (alarm + "/sourceId", .string("source-power"), .bindingType),
            (alarm + "/sourceId", .string("source-missing"), .invalidReference),
            (alarm + "/fallback/fill/red", .number(256), .limitExceeded),
            (alarm + "/states/0/state", .string("any"), .unknownVariant),
            (grid + "/children/1/props/selected", .string("navigation-path"), .invalidCombination),
            (grid + "/children/1/props/subtitle", .object(["type": .string("literal"), "value": .string("Frozen")]), .invalidCombination),
            (power + "/action/sourceId", .string("source-panel"), .invalidCombination),
            (text + "/from/path", .array([.string("isOn")]), .invalidReference),
            (text + "/as", .string("entity-id"), .bindingType)
        ] {
            try expect(changing(root, path, replacement), code, path)
        }
        try expect(changing(root, "/document/dataSources/3/labels/unavailableText", nil), .missingRequired,
                   "/document/dataSources/3/labels/unavailableText")
        try expect(changing(root, grid + "/children/1/props/presentation", value("""
            {"layout":"anchored-bottom","titleLines":2,"fill":{"type":"solid-rgb","red":1,"green":2,"blue":3}}
            """)), .invalidCombination, grid + "/children/1/props/presentation/fill")
        let state = try #require(root["document"]?["pages"]?.array?[0]["components"]?.array?[0]["children"]?.array?[1]["props"]?["alarm"]?["states"]?.array?.first)
        try expect(changing(root, alarm + "/states", .array([state, state])), .invalidCombination, alarm + "/states/1/state")
        let readTarget = try value("""
            {"type":"read","from":{"type":"source","sourceId":"source-entity","path":["attributes","target"]},"as":"entity-id","missing":"unavailable"}
            """)
        #expect(throws: E.self) { try decode(changing(root, "/document/dataSources/2/inputs/entityId", readTarget)) }
    }

    @Test func authoredTilePresentationIsTypedAndRequiresExactCapability() throws {
        let tile = grid + "/children/1/props"
        var root = try changing(fixture(), tile + "/presentation", value("""
            {"layout":"anchored-bottom","titleLines":2,
             "fill":{"type":"solid-rgb","red":42,"green":128,"blue":255},
             "bodyHint":"Opens the sample page"}
            """))
        root = try changing(root, tile + "/selected", .string("none"))
        try expect(root, .capabilityManifestMismatch, "/capabilities")
        var capabilities = try #require(root["capabilities"]?.array)
        capabilities.insert(.string("sh.tile-presentation@1"), at: capabilities.count - 1)
        root = try changing(root, "/capabilities", .array(capabilities))
        let document = try decode(root).document
        guard case .grid(let grid) = document.pages[0].surface.components[0],
              case .navigationTile(let tile) = grid.children[1] else {
            Issue.record("Expected navigation tile"); return
        }
        #expect(tile.selected == .none)
        #expect(tile.presentation?.layout == .anchoredBottom)
        #expect(tile.presentation?.titleLines == 2)
        #expect(tile.presentation?.fill == .solidRGB(red: 42, green: 128, blue: 255))
        #expect(tile.presentation?.bodyHint == "Opens the sample page")
    }

    @Test func tilePresentationRejectsInvalidOrIncompatibleInputs() throws {
        let props = grid + "/children/1/props"
        let presentation = props + "/presentation"
        var root = try changing(fixture(), presentation, value("""
            {"layout":"standard","titleLines":1,"fill":{"type":"solid-rgb","red":0,"green":0,"blue":0}}
            """))
        var capabilities = try #require(root["capabilities"]?.array)
        capabilities.insert(.string("sh.tile-presentation@1"), at: capabilities.count - 1)
        root = try changing(root, "/capabilities", .array(capabilities))
        try expect(changing(root, presentation + "/fill/red", .number(256)), .limitExceeded, presentation + "/fill/red")
        try expect(changing(root, presentation + "/fill/blue", .number(1.5)), .invalidValue, presentation + "/fill/blue")
        try expect(changing(root, presentation + "/titleLines", .number(3)), .limitExceeded, presentation + "/titleLines")
        try expect(changing(root, presentation + "/layout", .string("custom")), .unknownVariant, presentation + "/layout")
        try expect(changing(root, presentation + "/bodyHint", .string(" ")), .invalidValue, presentation + "/bodyHint")
        try expect(changing(root, props + "/family", .string("lights")), .invalidCombination, props + "/family")
        try expect(changing(root, presentation + "/extra", .bool(true)), .unknownField, presentation + "/extra")
        let standard = try changing(root, presentation + "/fill", value(#"{"type":"standard"}"#))
        _ = try decode(changing(standard, props + "/family", .string("lights")))
    }

    @Test func selectionOnlyRequiresCapabilityAndUnusedCapabilityRejects() throws {
        let fixture = try fixture()
        var capabilities = try #require(fixture["capabilities"]?.array)
        capabilities.insert(.string("sh.tile-presentation@1"), at: capabilities.count - 1)
        let declared = try changing(fixture, "/capabilities", .array(capabilities))
        try expect(declared, .capabilityManifestMismatch, "/capabilities")
        let selected = try changing(fixture, grid + "/children/1/props/selected", .string("none"))
        try expect(selected, .capabilityManifestMismatch, "/capabilities")
        _ = try decode(changing(selected, "/capabilities", .array(capabilities)))
    }

    @Test func contractPositiveMutationsRemainArbitraryAndExplicit() throws {
        var root = try fixture()
        let pointers = [
            "/document/navigation/chrome/groups/0/items/1/action/pageId",
            grid + "/children/1/action/pageId", "/document/pages/1/components/1/action/pageId",
            "/document/pages/2/id", "/document/modals/0/components/1/action/pageId",
            "/document/modals/0/components/2/action/destination/pageId"
        ]
        for pointer in pointers { root = try changing(root, pointer, .string("page-fractal")) }
        root = try changing(root, "/document/navigation/initialTabId", .string("tab-iris"))
        root = try changing(root, "/document/navigation/tabs/0/id", .string("tab-iris"))
        root = try changing(root, "/document/modals/0/id", .string("modal-opal"))
        root = try changing(root, "/document/navigation/chrome/groups/1/items/0/action/modalId", .string("modal-opal"))
        let renamed = try decode(root)
        #expect(renamed.document.navigation.initialTabId == "tab-iris")
        #expect(renamed.document.pages[2].id == "page-fractal")
        #expect(renamed.document.modals[0].id == "modal-opal")
        let tabs = try #require(root["document"]?["navigation"]?["tabs"]?.array)
        root = try changing(root, "/document/navigation/tabs", .array(tabs.reversed()))
        root = try changing(root, "/revision", .number(2))
        #expect(try decode(root).document.navigation.tabs.first?.id == "tab-beta")
        root = try changing(root, power + "/action/confirmation", value("""
            {"type":"additional","style":"alert","title":"Change Sample Output?",
             "message":"Send the selected power command to the sample output.",
             "confirmLabel":"Change","cancelLabel":"Cancel","destructive":false}
            """))
        #expect(try decode(root).revision == 2)
    }

    @Test func sharedRejectionMutations() throws {
        try mutation("/document/navigation/chrome/groups/0/vertical", nil, .missingRequired)
        try mutation(grid + "/type", .string("nativeFeature"), .unknownVariant)
        try mutation(grid + "/props/css", .string("display:grid"), .unknownField)
        try mutation(presentation + "/width", nil, .missingRequired)
        try mutation(grid + "/props/shortRow", nil, .missingRequired)
        try mutation(grid + "/children/1/action/pageId", .string("page-missing"), .invalidReference)
        try mutation(text + "/as", .string("number"), .bindingType)
        try mutation(power + "/action/sourceId", .string("source-entity"), .invalidCombination)
        try mutation(power + "/action/confirmation", value(#"{"type":"none"}"#), .unknownVariant, at: power + "/action/confirmation/type")
        try mutation(grid + "/props/maxColumns", .number(5), .limitExceeded)
        try mutation(presentation + "/height", value("""
            {"type":"fitted","follows":"top-page","firstOpen":"premeasure"}
            """), .unknownVariant, at: presentation + "/height/firstOpen")
    }

    @Test func canonicalFittingAndScaledGridRequireTheirExactCapabilities() throws {
        var root = try changing(fixture(), presentation + "/height", value("""
            {"type":"fitted","follows":"top-page","firstOpen":"canonical@1"}
            """))
        root = try changing(root, grid + "/props/minimum", .string("tile-dynamic-type@1"))
        try expect(root, .capabilityManifestMismatch, "/capabilities")
        let capabilities = P.firstSliceCapabilities + ["sh.grid-dynamic-type@1", "sh.sheet-fit@1"]
        root = try changing(root, "/capabilities", .array(capabilities.sorted().map(JSONValue.string)))
        let document = try decode(root).document
        #expect(document.modals[0].presentation.height == .fitted(follows: .topPage, firstOpen: .canonicalV1))
        guard case .grid(let grid) = document.pages[0].surface.components[0] else {
            Issue.record("Expected configured grid"); return
        }
        #expect(grid.minimum == .tileDynamicType)
        let rootFit = try changing(root, presentation + "/height/follows", .string("root"))
        #expect(try decode(rootFit).document.modals[0].presentation.height == .fitted(follows: .root, firstOpen: .canonicalV1))
        try expect(changing(root, presentation + "/height/firstOpen", nil), .missingRequired, presentation + "/height/firstOpen")
    }

    @Test func pureCompilerDoesNotClaimSymbolsOrAssetBytes() throws {
        let root = try changing(fixture(), "/document/navigation/tabs/0/icon/name", .string("demo.symbol.that.does.not.exist"))
        #expect(try decode(root).document.navigation.tabs[0].icon.name == "demo.symbol.that.does.not.exist")
        // The shared corpus's symbol_unavailable and downloaded asset-corruption cases belong
        // to UIKit preparation/staging. Decode performs no symbol lookup or asset requests.
    }

    /// The symbol's `unavailable` field says what a device gap does. `fallback` is the contract word; `reject` is the legacy alias
    /// the live published revision still carries. Both mean the same: the fallback symbol is drawn and nothing rejects.
    @Test func symbolUnavailableAcceptsFallbackAndTheLegacyRejectAlias() throws {
        let path = "/document/navigation/tabs/0/icon/unavailable"
        let fallback = try decode(changing(fixture(), path, .string("fallback"))).document.navigation.tabs[0].icon
        #expect(fallback.unavailable == .fallback)
        let legacy = try decode(changing(fixture(), path, .string("reject"))).document.navigation.tabs[0].icon
        #expect(legacy.unavailable == .reject)
        // Neither value changes what Core reports: the authored name, with no device state read.
        #expect(fallback.name == legacy.name)
        try expect(changing(fixture(), path, .string("hide")), .unknownVariant, path)
    }

    @Test func allFirstSlicePolicyAlternativesCompile() throws {
        var root = try fixture()
        let edits: [(String, JSONValue)] = [
            ("/document/theme/background/blur", try value(#"{"type":"preference","key":"backdrop-blur","initialPercent":100}"#)),
            ("/document/theme/background/scrim", try value(#"{"type":"gradient","stops":[{"location":0,"opacity":0},{"location":1,"opacity":0.9}],"increasedContrastBoost":0.1}"#)),
            ("/document/navigation/initialTabId", .null),
            ("/document/navigation/chrome/groups/0/horizontal", .string("shared@1")),
            ("/document/navigation/chrome/groups/0/vertical", .string("separate@1")),
            ("/document/navigation/chrome/groups/0/items/1/priority", .string("low")),
            ("/document/navigation/chrome/groups/0/items/1/rail", .string("horizontal-only")),
            ("/document/pages/0/layout/spacing", try value(#"{"type":"points","value":64}"#)),
            ("/document/pages/0/layout/maxWidth", try value(#"{"type":"points","value":1600}"#)),
            (grid + "/props/shortRow", .string("leading")), (grid + "/props/fold", .string("container")),
            (grid + "/props/equalRowHeights", .bool(true)), (power + "/layout/span", .number(4)),
            (power + "/props/family", .string("neutral")),
            ("/document/dataSources/1/inputs/entityId/value", .string("input_boolean.demo_unit")),
            (presentation + "/width", .string("page")), (presentation + "/appearance", .string("dark")),
            (presentation + "/close/visibility", .string("all-depths")),
            (presentation + "/close/rail", .string("automatic")),
            ("/document/pages/1/components/0/props/style", .string("caption1")),
            ("/document/pages/1/components/1/props/subtitle/value", .string(""))
        ]
        for (pointer, replacement) in edits { root = try changing(root, pointer, replacement) }
        #expect(try decode(root).document.navigation.initialTabId == nil)
        for style in ["alert", "dialog"] {
            root = try changing(root, power + "/action/confirmation", value("""
                {"type":"additional","style":"\(style)","title":"Change?",
                 "confirmLabel":"Change","cancelLabel":"Cancel","destructive":true}
                """))
            #expect(try decode(root).document.modals[0].presentation.height == .full)
        }
    }

    @Test func everyNavigationIntentAndReadVariantIsTyped() throws {
        let chrome = "/document/navigation/chrome/groups/0/items/1/action"
        let actions = [
            #"{"type":"select-tab","tabId":"tab-beta"}"#, #"{"type":"back"}"#,
            #"{"type":"dismiss","scope":"current-modal"}"#,
            #"{"type":"present","modalId":"modal-swatch","arguments":{},"ifPresented":"reject"}"#,
            #"{"type":"dismiss-then-push","destination":{"type":"push","pageId":"page-orbit","arguments":{},"origin":"sender","duplicate":"reuse-nearest"}}"#
        ]
        for action in actions { _ = try decode(changing(fixture(), chrome, value(action))) }
        for path in [["state"], ["attributes", "friendly_name"]] {
            _ = try decode(changing(fixture(), text + "/from/path", .array(path.map(JSONValue.string))))
        }
        var root = try changing(fixture(), text + "/from/sourceId", .string("source-power"))
        for field in ["stateText", "phase"] {
            _ = try decode(changing(root, text + "/from/path", .array([.string(field)])))
        }
        root = try changing(root, text + "/from/path", .array([.string("isOn")]))
        try expect(root, .bindingType, text + "/as")
        root = try changing(fixture(), "/document/dataSources/1/inputs/entityId", value("""
            {"type":"read","from":{"type":"source","sourceId":"source-entity","path":["attributes","target"]},"as":"entity-id","missing":"unavailable"}
            """))
        _ = try decode(root)
    }

    @Test func exactClosureIncludesUnreachableDefinitionsAndNoExtras() throws {
        let root = try fixture()
        var capabilities = try #require(root["capabilities"]?.array)
        capabilities.append(.string("sh.unknown@1"))
        try expect(changing(root, "/capabilities", .array(capabilities)), .unsupportedCapability,
                   "/capabilities/14", capability: "sh.unknown@1")
        capabilities.removeLast()
        capabilities.remove(at: 6)
        try expect(changing(root, "/capabilities", .array(capabilities)), .capabilityManifestMismatch, "/capabilities")
        capabilities = try #require(root["capabilities"]?.array)
        capabilities.swapAt(0, 1)
        try expect(changing(root, "/capabilities", .array(capabilities)), .capabilityManifestMismatch, "/capabilities")
        capabilities = try #require(root["capabilities"]?.array)
        capabilities.append(capabilities[0])
        try expect(changing(root, "/capabilities", .array(capabilities)), .capabilityManifestMismatch, "/capabilities")

        var solid = try changing(root, "/document/theme/background", value(#"{"type":"solid","token":"shell-base@1"}"#))
        solid = try changing(solid, "/document/assets", .array([]))
        capabilities = try #require(solid["capabilities"]?.array).filter { $0 != .string("sh.assets.publisher@1") }
        solid = try changing(solid, "/capabilities", .array(capabilities))
        _ = try decode(manifest(solid))
        try expect(manifest(changing(solid, "/document/pages/2/components/0/props/value/from/sourceId", .string("absent"))),
                   .invalidReference, text + "/from/sourceId")
    }

    @Test func knownFollowOnsRejectWithoutFallbackEvenWithoutManifestEntries() throws {
        let cases: [(String, String, String, String?)] = [
            (grid + "/type", #""modal-tab-bar""#, grid + "/type", "sh.modal-tab-bar@1"),
            (grid + "/type", #""content-image""#, grid + "/type", "sh.content-image@1"),
            (grid + "/type", #""section-sides""#, grid + "/type", "sh.section-sides@1"),
            (grid + "/type", #""content-panes""#, grid + "/type", "sh.content-panes@1"),
            (presentation + "/type", #""fullscreen""#, presentation + "/type", "sh.fullscreen@1"),
            (presentation + "/close/type", #""form-actions""#, presentation + "/close/type", "sh.forms@1"),
            (presentation + "/close/guard/type", #""draft""#, presentation + "/close/guard/type", "sh.forms@1"),
            ("/document/navigation/chrome/groups/0/items/1/badge/type", #""count""#, "/document/navigation/chrome/groups/0/items/1/badge/type", "sh.profile-count@1"),
            ("/document/assets/0/source/type", #""public-https""#, "/document/assets/0/source/type", "sh.public-assets@1"),
            ("/document/variables", #"{"local":{"initial":false}}"#, "/document/variables", "sh.local-state@1"),
            ("/document/pages/0/parameters", #"{"arg":{"type":"required"}}"#, "/document/pages/0/parameters", "sh.route-arguments@1"),
            (text + "/from/type", #""parameter""#, text + "/from/type", "sh.route-arguments@1"),
            (text + "/from/type", #""variable""#, text + "/from/type", "sh.local-state@1")
        ]
        for (pointer, replacement, expected, capability) in cases {
            try mutation(pointer, value(replacement), .unsupportedCapability, at: expected, capability: capability)
        }
        try mutation("/document/pages/0/navigation/type", .string("navigation-columns"),
                     .missingRequired, at: "/document/pages/0/navigation/placeholder")
    }

    @Test func unsafeBindingsSourcesAndActionsReject() throws {
        for segment in ["__proto__", "prototype", "constructor", "*", "x.y", "0", "x[0]", "fn()", "name\n"] {
            try mutation(text + "/from/path", .array([.string("attributes"), .string(segment)]),
                         .invalidReference, at: text + "/from/path/1")
        }
        try mutation(text + "/from/path", .array([.string("state"), .string("extra")]), .invalidReference, at: text + "/from/path")
        try mutation(text + "/from/sourceId", .string("missing"), .invalidReference)
        try mutation("/document/dataSources/1/inputs/entityId/value", .string("light.demo_unit"), .invalidCombination)
        try mutation("/document/dataSources/1/inputs/entityId/value", .string("switch.demo_bad/path"), .invalidValue)
        try mutation(grid + "/children/1/action", value(#"{"type":"back"}"#), .invalidCombination, at: grid + "/children/1/action/type")
        // A power tile takes the power action only (an object, as in the Studio), so a foreign action reports the field it lacks first.
        try mutation(power + "/action", value(#"{"type":"service","service":"toggle"}"#), .missingRequired, at: power + "/action/confirmation")
        try mutation("/document/navigation/initialPageId", .string("page-echo"), .invalidCombination, at: "/document/navigation/initialTabId")
        try mutation("/document/modals/0/toolbar", value(#"{"type":"inherit"}"#), .invalidCombination)
        try mutation("/document/pages/0/components/0/layout/span", .number(2), .invalidCombination)
        try mutation("/document/modals/0/id", .string("page-echo"), .duplicateID)
    }

    @Test func sourceDependencyCyclesAndKnownOutputTypesReject() throws {
        var root = try changing(fixture(), "/document/dataSources/0/entityId", value("""
            {"type":"read","from":{"type":"source","sourceId":"source-entity","path":["attributes","target"]},"as":"entity-id","missing":"unavailable"}
            """))
        try expect(root, .invalidCombination, "/document/dataSources/0/entityId/from/sourceId")
        root = try changing(root, "/document/dataSources/0/entityId/from/sourceId", .string("source-power"))
        root = try changing(root, "/document/dataSources/0/entityId/from/path", .array([.string("stateText")]))
        try expect(root, .bindingType, "/document/dataSources/0/entityId/as")
        root = try changing(fixture(), "/document/dataSources/1/inputs/entityId", value("""
            {"type":"read","from":{"type":"source","sourceId":"source-entity","path":["state"]},"as":"entity-id","missing":"unavailable"}
            """))
        try expect(root, .bindingType, "/document/dataSources/1/inputs/entityId/as")
        root = try changing(fixture(), "/document/dataSources", value("""
            [{"id":"source-entity","kind":"ha-entity","entityId":{"type":"read",
              "from":{"type":"source","sourceId":"source-power","path":["attributes","target"]},"as":"entity-id","missing":"unavailable"}},
             {"id":"source-power","kind":"ha-entity","entityId":{"type":"read",
              "from":{"type":"source","sourceId":"source-entity","path":["attributes","target"]},"as":"entity-id","missing":"unavailable"}}]
            """))
        try expect(root, .invalidCombination, "/document/dataSources/0/entityId/from/sourceId")
    }

    @Test func duplicateKeysAreDetectedBeforeDictionaryDecode() throws {
        let examples: [(String, String)] = [
            (#"{"document":{},"document":{}}"#, "/document"),
            (#"{"document":{},"\u0064ocument":{}}"#, "/document"),
            (#"{"x":{"a/b~c":0,"a\/b\u007ec":1}}"#, "/x/a~1b~0c"),
            (#"{"x":[{"id":"a","id":"b"}]}"#, "/x/0/id"),
            (#"{"x":{"name":1,"\u006eame":2}}"#, "/x/name")
        ]
        for (json, pointer) in examples {
            #expect(throws: E(.duplicateKey, pointer)) { try P.decode(Data(json.utf8)) }
        }
        for json in [#"{"x":"\ud800"}"#, #"{"x":"\udc00"}"#, #"{"x":01}"#, #"{"x":1e309}"#, #"{"x":true,}"#, #"[]null"#] {
            #expect(throws: E.self) { try P.decode(Data(json.utf8)) }
        }
        #expect(throws: E.self) { try P.decode(Data([123, 34, 120, 34, 58, 34, 255, 34, 125])) }
    }

    @Test func strictShapeHasNoDefaultsAndSchemaWinsShapeErrors() throws {
        for pointer in ["/document/navigation/initialTabId", "/document/navigation/policy/reselect",
                        "/document/pages/0/layout/padding", "/document/pages/0/toolbar",
                        power + "/action/confirmation", "/document/assets/0/sha256"] {
            try mutation(pointer, nil, .missingRequired)
        }
        for pointer in ["/document/theme/background/extra", "/document/pages/0/subtitle",
                        "/document/pages/0/layout/rows", power + "/props/target", "/extra"] {
            try mutation(pointer, .string("private-sentinel"), .unknownField)
        }
        var root = try changing(fixture(), "/document/schemaVersion", .string("2.1"))
        root = try changing(root, "/extra", .bool(true))
        try expect(root, .unsupportedSchema, "/document/schemaVersion")
        try mutation("/envelopeVersion", .string("1.0"), .unsupportedSchema)
        try mutation("/document/theme/appearance", .string("light"), .unknownVariant)
        try mutation("/document/navigation/initialTabId", .bool(false), .invalidValue)
        try mutation("/document/dataSources/0/id", .string("constructor"), .invalidValue)
        try mutation("/document/dataSources/0/id", .string("source\n"), .invalidValue)
        #expect(throws: E(.invalidValue, "/constructor")) { try P.decode(Data(#"{"constructor":1}"#.utf8)) }
        root = try changing(fixture(), "/z", .bool(true))
        root = try changing(root, "/a", .bool(true))
        try expect(root, .unknownField, "/a")
        #expect(throws: E(.duplicateKey, "/a")) {
            try P.decode(Data(#"{"z":0,"z":1,"a":0,"a":1}"#.utf8))
        }
    }

    @Test func manifestJCSAndDescriptorSecurity() throws {
        var root = try fixture()
        try mutation("/assetManifestSha256", .string(String(repeating: "0", count: 64)), .assetIntegrity)
        let sha = try #require(root["document"]?["assets"]?.array?[0]["sha256"]?.string)
        for path in ["/api/assets/\(sha).png?x=1", "/api/assets/\(sha).png#x",
                     "/api/assets/%2e%2e/\(sha).png", "//api/assets/\(sha).png",
                     "/api/assets/\(sha).jpg", "https://example.invalid/x.png"] {
            try mutation("/document/assets/0/source/path", .string(path), .invalidValue)
        }
        root = try changing(root, "/document/assets/0/pixelWidth", .number(8_192))
        root = try changing(root, "/document/assets/0/pixelHeight", .number(8_192))
        try expect(root, .limitExceeded, "/document/assets/0/pixelWidth")
        try mutation("/document/assets/0/role", .string("content-image"), .invalidCombination, at: "/document/theme/background/assetId")
        root = try changing(fixture(), "/document/theme/background", value(#"{"type":"solid","token":"shell-base@1"}"#))
        try expect(root, .invalidReference, "/document/assets/0")
        // JCS control escaping, literal slash/Unicode, UTF-16 ordering, integers and -0.
        let jcs = try value(#"{"z":"\u0000\b\t\n\f\r\"\\/é","a":-0,"n":1e-7,"m":0.000001,"i":79.0}"#)
        #expect(ServerUICompositionJSON.canonical(jcs) == #"{"a":0,"i":79,"m":0.000001,"n":1e-7,"z":"\u0000\b\t\n\f\r\"\\/é"}"#)
        #expect(try decode(fixture()).assetManifestSha256 == "9aee7dd449988eba3f8b622b2769ef5d507d6755df521319701602d06c0db245")
    }

    @Test func numericTextAndTimestampEdges() throws {
        for (pointer, number) in [(grid + "/props/maxColumns", 1.5), ("/revision", 1.5)] {
            try mutation(pointer, .number(number), .invalidValue)
        }
        try mutation("/revision", .number(0), .limitExceeded)
        try mutation("/revision", .number(9_007_199_254_740_992), .limitExceeded)
        _ = try decode(changing(fixture(), "/revision", .number(9_007_199_254_740_991)))
        try mutation("/document/name", .string("   \n"), .invalidValue)
        _ = try decode(changing(fixture(), "/document/name", .string(String(repeating: "🟦", count: 120))))
        try mutation("/document/name", .string(String(repeating: "🟦", count: 121)), .limitExceeded)
        for timestamp in ["2026-02-30T00:00:00Z", "2026-11-13T16:00:00+00:00", "2026-11-13", "0000-01-01T00:00:00Z"] {
            try mutation("/updatedAt", .string(timestamp), .invalidValue)
        }
        try mutation("/updatedAt", .string("2026-11-13T16:02:00Z"), .invalidValue)
        var root = try changing(fixture(), "/updatedAt", .string("2026-11-13T16:01:00.000000000000000002Z"))
        root = try changing(root, "/publishedAt", .string("2026-11-13T16:01:00.000000000000000001Z"))
        try expect(root, .invalidValue, "/updatedAt")
    }

    @Test func independentJSONAndDocumentSizeCeilings() throws {
        #expect(throws: E(.limitExceeded, "")) {
            try P.decode(Data(repeating: 32, count: 2_162_689))
        }
        var parser = try ServerUICompositionJSON(Data(("[" + Array(repeating: "0", count: 1_000).joined(separator: ",") + "]").utf8))
        #expect(try parser.parse().array?.count == 1_000)
        #expect(throws: E(.limitExceeded, "")) {
            var parser = try ServerUICompositionJSON(Data(("[" + Array(repeating: "0", count: 1_001).joined(separator: ",") + "]").utf8))
            _ = try parser.parse()
        }
        let atDepth = String(repeating: "[", count: 40) + "0" + String(repeating: "]", count: 40)
        var depthParser = try ServerUICompositionJSON(Data(atDepth.utf8))
        _ = try depthParser.parse()
        #expect(throws: E.self) {
            var parser = try ServerUICompositionJSON(Data(("[" + atDepth + "]").utf8)); _ = try parser.parse()
        }
        let largeArray = "[" + Array(repeating: "0", count: 1_000).joined(separator: ",") + "]"
        #expect(throws: E.self) {
            var parser = try ServerUICompositionJSON(Data(("[" + Array(repeating: largeArray, count: 100).joined(separator: ",") + "]").utf8))
            _ = try parser.parse()
        }
        var root = try fixture()
        var textNode = try #require(root["document"]?["pages"]?.array?[1]["components"]?.array?[0])
        textNode = try changing(textNode, "/props/value/value", .string(""))
        var nodes: [JSONValue] = []
        for index in 0..<140 { nodes.append(try changing(textNode, "/id", .string("size-\(index)"))) }
        root = try changing(root, "/document/pages/1/components", .array(Array(nodes.prefix(70))))
        root = try changing(root, "/document/pages/2/components", .array(Array(nodes.suffix(70))))
        let remaining = 2_097_152 - (try #require(root["document"]).flatCanonicalSize)
        try #require((1..<16_384).contains(remaining / nodes.count))
        for index in nodes.indices {
            let size = remaining / nodes.count + (index < remaining % nodes.count ? 1 : 0)
            nodes[index] = try changing(nodes[index], "/props/value/value", .string(String(repeating: "x", count: size)))
        }
        root = try changing(root, "/document/pages/1/components", .array(Array(nodes.prefix(70))))
        root = try changing(root, "/document/pages/2/components", .array(Array(nodes.suffix(70))))
        #expect(try #require(root["document"]).flatCanonicalSize == 2_097_152)
        _ = try decode(root)
        let first = try #require(nodes[0]["props"]?["value"]?["value"]?.string)
        root = try changing(root, "/document/pages/1/components/0/props/value/value", .string(first + "x"))
        try expect(root, .limitExceeded, "/document")
        let minimal = try fixture()
        let canonical = ServerUICompositionJSON.canonical(minimal)
        // Raw whitespace counts against the response cap, but not document/envelope accounting.
        let padded = Data((canonical + String(repeating: " ", count: 2_162_688 - canonical.utf8.count)).utf8)
        _ = try P.decode(padded)
        let overhead = try changing(minimal, "/padding", .string(String(repeating: "x", count: 65_536)))
        try expect(overhead, .limitExceeded, "")
    }

    @Test func chromeCountsIncludeOnlyRenderedItemsAndReservedHostControls() throws {
        var root = try fixture()
        let button = try #require(root["document"]?["navigation"]?["chrome"]?["groups"]?.array?[0]["items"]?.array?[1])
        let menu = try #require(root["document"]?["navigation"]?["chrome"]?["groups"]?.array?[0]["items"]?.array?[0])
        var buttons: [JSONValue] = []
        for index in 0..<11 { buttons.append(try changing(button, "/id", .string("root-button-\(index)"))) }
        root = try changing(root, "/document/navigation/chrome/groups/0/items", .array([menu] + buttons))
        root = try changing(root, "/document/navigation/chrome/groups/1/items", .array([]))
        // Twelve items on a shell root is legal; root-only items vanish on pushed pages.
        _ = try decode(root)
        root = try changing(root, "/document/navigation/chrome/groups/1/items", .array([
            try changing(button, "/id", .string("extra-button"))
        ]))
        try expect(root, .limitExceeded, "/document/pages/0/toolbar")

        root = try fixture()
        var alwaysButtons: [JSONValue] = []
        for index in 0..<12 {
            var item = try changing(button, "/id", .string("modal-button-\(index)"))
            item = try changing(item, "/visibility", .string("always"))
            alwaysButtons.append(item)
        }
        var group = try #require(root["document"]?["navigation"]?["chrome"]?["groups"]?.array?[0])
        group = try changing(group, "/id", .string("modal-group"))
        group = try changing(group, "/items", .array(alwaysButtons))
        root = try changing(root, "/document/modals/0/toolbar", .object(["type": .string("replace"), "groups": .array([group])]))
        try expect(root, .limitExceeded, "/document/modals/0/toolbar")
        alwaysButtons.removeLast()
        group = try changing(group, "/items", .array(alwaysButtons))
        root = try changing(root, "/document/modals/0/toolbar/groups", .array([group]))
        // Eleven + root Close is legal; root-only Close is absent beside pushed Back.
        _ = try decode(root)
        root = try changing(root, presentation + "/close/visibility", .string("all-depths"))
        try expect(root, .limitExceeded, "/document/pages/2/toolbar")
        try mutation("/document/navigation/chrome/groups/0/items/0", nil, .invalidCombination, at: "/document/pages/0/toolbar")
    }

    @Test func reusingOwnRootDoesNotInventAHostBackButton() throws {
        var root = try fixture()
        root = try changing(root, "/document/navigation/initialTabId", .null)
        root = try changing(root, "/document/navigation/tabs", .array([]))
        var button = try #require(root["document"]?["navigation"]?["chrome"]?["groups"]?.array?[0]["items"]?.array?[1])
        button = try changing(button, "/visibility", .string("always"))
        button = try changing(button, "/action/pageId", .string("page-orbit"))
        let menu = try #require(root["document"]?["navigation"]?["chrome"]?["groups"]?.array?[0]["items"]?.array?[0])
        var items = [menu]
        for index in 0..<11 { items.append(try changing(button, "/id", .string("root-only-route-\(index)"))) }
        root = try changing(root, "/document/navigation/chrome/groups/0/items", .array(items))
        root = try changing(root, "/document/navigation/chrome/groups/1/items", .array([]))
        root = try changing(root, grid + "/children/1/action/pageId", .string("page-orbit"))
        _ = try decode(root)
    }

    @Test func catalogComponentAndTabBounds() throws {
        var root = try fixture()
        let originalPages = try #require(root["document"]?["pages"]?.array)
        var pages = originalPages
        let emptyPage = try changing(originalPages[2], "/components", .array([]))
        for index in 0..<252 { pages.append(try changing(emptyPage, "/id", .string("page-extra-\(index)"))) }
        root = try changing(root, "/document/pages", .array(pages))
        _ = try decode(root) // 255 pages + one modal.
        pages.append(try changing(emptyPage, "/id", .string("page-too-many")))
        root = try changing(root, "/document/pages", .array(pages))
        _ = try decode(root) // 256 pages remain valid with the separate modal catalog.
        pages.append(try changing(emptyPage, "/id", .string("page-over-page-limit")))
        try expect(changing(root, "/document/pages", .array(pages)), .limitExceeded, "/document/pages")

        var modals = try #require(root["document"]?["modals"]?.array)
        let emptyModal = try changing(modals[0], "/components", .array([]))
        while modals.count < 256 {
            modals.append(try changing(emptyModal, "/id", .string("modal-extra-\(modals.count)")))
        }
        root = try changing(root, "/document/modals", .array(modals))
        _ = try decode(root)
        modals.append(try changing(emptyModal, "/id", .string("modal-over-limit")))
        try expect(changing(root, "/document/modals", .array(modals)), .limitExceeded, "/document/modals")

        root = try fixture()
        var tabs = try #require(root["document"]?["navigation"]?["tabs"]?.array)
        let tab = tabs[0]
        for index in 0..<3 { tabs.append(try changing(tab, "/id", .string("tab-extra-\(index)"))) }
        root = try changing(root, "/document/navigation/tabs", .array(tabs))
        _ = try decode(root)
        tabs.append(try changing(tab, "/id", .string("tab-six")))
        try expect(changing(root, "/document/navigation/tabs", .array(tabs)), .unsupportedCapability,
                   "/document/navigation/tabs", capability: "sh.extended-tabs@1")

        root = try fixture()
        let leaf = try #require(root["document"]?["pages"]?.array?[1]["components"]?.array?[0])
        var nodes: [JSONValue] = []
        for index in 0..<100 { nodes.append(try changing(leaf, "/id", .string("bounded-node-\(index)"))) }
        root = try changing(root, "/document/pages/2/components", .array(nodes))
        _ = try decode(root)
        nodes.append(try changing(leaf, "/id", .string("bounded-node-101")))
        try expect(changing(root, "/document/pages/2/components", .array(nodes)), .limitExceeded, "/document/pages/2/components")
        nodes.removeLast()
        nodes[99] = try changing(nodes[99], "/id", .string("bounded-node-0"))
        try expect(changing(root, "/document/pages/2/components", .array(nodes)), .duplicateID, atNodeZero)
    }

    private var atNodeZero: String { "/document/pages/2/components/0/id" }

    @Test func componentDepthAndRawObjectValueLimits() throws {
        let root = try fixture()
        var nested = try #require(root["document"]?["pages"]?.array?[1]["components"]?.array?[0])
        nested = try changing(nested, "/id", .string("depth-leaf"))
        let container = try #require(root["document"]?["pages"]?.array?[0]["components"]?.array?[0])
        for index in 0..<11 {
            var next = try changing(container, "/id", .string("depth-\(index)"))
            next = try changing(next, "/children", .array([nested]))
            nested = next
        }
        _ = try decode(changing(root, "/document/pages/2/components", .array([nested])))
        var outer = try changing(container, "/id", .string("depth-12"))
        outer = try changing(outer, "/children", .array([nested]))
        #expect(throws: E.self) { try decode(changing(root, "/document/pages/2/components", .array([outer]))) }

        let object = (0..<1_000).map { "\"key-\($0)\":0" }.joined(separator: ",")
        var parser = try ServerUICompositionJSON(Data(("{\(object)}").utf8))
        _ = try parser.parse()
        #expect(throws: E(.limitExceeded, "")) {
            var parser = try ServerUICompositionJSON(Data(("{\(object),\"key-1000\":0}").utf8)); _ = try parser.parse()
        }
        let full = "[" + Array(repeating: "0", count: 1_000).joined(separator: ",") + "]"
        let tail = "[" + Array(repeating: "0", count: 899).joined(separator: ",") + "]"
        let prefix = "[" + Array(repeating: full, count: 99).joined(separator: ",") + ","
        var exact = try ServerUICompositionJSON(Data((prefix + tail + "]").utf8))
        _ = try exact.parse() // Exactly 100,000 values; the independent byte and depth limits still apply.
        #expect(throws: E.self) {
            var over = try ServerUICompositionJSON(Data((prefix + tail.dropLast() + ",0]]").utf8)); _ = try over.parse()
        }
    }
}

private extension JSONValue {
    var flatCanonicalSize: Int { ServerUICompositionJSON.canonical(self).utf8.count }
}
