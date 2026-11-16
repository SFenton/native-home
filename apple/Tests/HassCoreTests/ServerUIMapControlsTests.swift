import Foundation
import HassTestSupport
import Testing
@testable import HassCore

// MARK: - Corner groups and orientation in a publication

/// `sh.surface-orientation@1` and `sh.surface-controls@1` decoded from a publication. The shared corpus pins every accept and reject case; these
/// pin what the app does with what it decodes.
@Suite struct ServerUIMapControlsTests {
    nonisolated(unsafe) private static let icon: [String: Any] = ["type": "sf-symbol", "name": "star", "rendering": "canonical", "unavailable": "fallback"]
    nonisolated(unsafe) private static let scope: [String: Any] = ["type": "sf-symbol", "name": "scope", "rendering": "canonical", "unavailable": "fallback"]
    nonisolated(unsafe) private static let toggle: [String: Any] = ["type": "call-service", "domain": "light", "service": "toggle",
                                                "target": ["entity_id": ["type": "literal", "value": "light.demo_kitchen"]]]
    nonisolated(unsafe) private static let push: [String: Any] = ["type": "push", "pageId": "page-echo", "arguments": [String: Any](),
                                              "origin": "sender", "duplicate": "reuse-nearest"]
    nonisolated(unsafe) private static let locateAction: [String: Any] = ["type": "map", "command": "locate"]
    nonisolated(unsafe) private static let hot: [String: Any] = ["type": "compare", "op": "eq", "left": ["type": "literal", "value": "a"],
                                              "right": ["type": "literal", "value": "a"]]

    private static func button(_ id: String, _ action: [String: Any] = toggle, label: Any? = nil, extra: [String: Any] = [:]) -> [String: Any] {
        var value: [String: Any] = ["id": id, "icon": icon, "label": label ?? id.capitalized, "action": action]
        for (key, item) in extra { value[key] = item }
        return value
    }
    private static func group(_ corner: String, _ axis: String, _ buttons: [[String: Any]]) -> [String: Any] {
        ["corner": corner, "axis": axis, "buttons": buttons]
    }
    nonisolated(unsafe) private static let locate = button("locate", locateAction, label: "Locate", extra: ["hint": "Asks the robot to play a sound.", "icon": scope])

    /// A publication built from a shared corpus case that already holds a vacuum source and a map (so its manifest is right), with the map's
    /// `controls`, `locate` flag and the source's orientation replaced, and the manifest given what the new content needs.
    private func publication(controls: [[String: Any]]?, locate flag: Bool = false, orientation: [String: Any]? = nil,
                             capabilities: [String]? = nil, areaCleaning: Bool = true, needs extra: [String] = []) throws -> ServerUICompositionPublication {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ContractCorpus/accept")
        var root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("surface-controls-locate-explicit.json"))) as? [String: Any])
        var document = try #require(root["document"] as? [String: Any])
        var sources = try #require(document["dataSources"] as? [[String: Any]])
        let robot = try #require(sources.firstIndex { $0["id"] as? String == "robot-src" })
        var inputs = try #require(sources[robot]["inputs"] as? [String: Any])
        if let orientation { inputs["orientation"] = orientation }
        if !areaCleaning { inputs["areaCleaning"] = nil }
        sources[robot]["inputs"] = inputs
        document["dataSources"] = sources
        var pages = try #require(document["pages"] as? [[String: Any]])
        var nodes = try #require(pages[2]["components"] as? [[String: Any]])
        var props = try #require(nodes[0]["props"] as? [String: Any])
        var primitive = try #require(props["primitive"] as? [String: Any])
        primitive["locate"] = flag
        primitive["controls"] = controls
        props["primitive"] = primitive
        nodes[0]["props"] = props
        pages[2]["components"] = nodes
        document["pages"] = pages
        root["document"] = document
        var needs = Set(try #require(root["capabilities"] as? [String]))
        needs.remove("sh.surface-controls@1")
        if controls != nil { needs.insert("sh.surface-controls@1") }
        if orientation != nil { needs.insert("sh.surface-orientation@1") }
        let commands = (controls ?? []).flatMap { $0["buttons"] as? [[String: Any]] ?? [] }
            .contains { ($0["action"] as? [String: Any])?["type"] as? String == "source-command" }
        if commands { needs.insert("sh.vacuum-controls@1") }
        // A service call with a literal target reads an operand.
        let serialized = String(decoding: try JSONSerialization.data(withJSONObject: controls ?? []), as: UTF8.self)
        if serialized.contains("\"call-service\"") { needs.formUnion(["sh.call-service@1", "sh.operands@1"]) }
        needs.formUnion(extra)
        root["capabilities"] = capabilities ?? needs.sorted()
        return try ServerUICompositionPublication.decode(JSONSerialization.data(withJSONObject: root))
    }

    /// The manifest of the base case without the two new ids.
    private func baseCapabilities() throws -> [String] {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ContractCorpus/accept")
        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("surface-controls-locate-explicit.json"))) as? [String: Any])
        return try #require(root["capabilities"] as? [String]).filter { $0 != "sh.surface-controls@1" }
    }

    /// The first issue a publication is refused with, as `code pointer-from-the-primitive`, or nil when it is accepted.
    private func refusal(controls: [[String: Any]]?, locate: Bool = false, areaCleaning: Bool = true) -> String? {
        do { _ = try publication(controls: controls, locate: locate, areaCleaning: areaCleaning); return nil } catch let error as ServerUICompositionError {
            return error.code.rawValue + " " + (error.pointer.components(separatedBy: "/primitive").last ?? error.pointer)
        } catch { return "other \(error)" }
    }

    private func map(_ publication: ServerUICompositionPublication) throws -> (locate: Bool, controls: [ServerUIMapControlGroup]?) {
        let component = try #require(publication.document.pages[2].surface.components.last)
        guard case .vacuum(let control) = component, case .map(_, _, _, _, _, _, let locate, let controls) = control.primitive else {
            Issue.record("not a map")
            return (false, nil)
        }
        return (locate, controls)
    }

    @Test func aMapWithNoControlsDecodesToNilAndNeedsNeitherId() throws {
        let p = try publication(controls: nil, locate: true)
        let (locate, controls) = try map(p)
        #expect(locate && controls == nil)
        #expect(!p.capabilities.contains("sh.surface-controls@1") && !p.capabilities.contains("sh.surface-orientation@1"))
        #expect(ServerUIMapControls.effective(locate: locate, controls: controls).map(\.corner) == [.topLeading])
    }

    @Test func authoredGroupsKeepTheirCornersAxesAndOrder() throws {
        let p = try publication(controls: [
            Self.group("top-trailing", "row", [Self.locate, Self.button("lights"), Self.button("plan", Self.push)]),
            Self.group("bottom-leading", "column", [Self.button("dock", ["type": "source-command", "command": "dock"]),
                                                     Self.button("pause", ["type": "source-command", "command": "pause"])]),
        ], locate: true)
        let groups = try #require(try map(p).controls)
        #expect(groups.map(\.corner) == [.topTrailing, .bottomLeading])
        #expect(groups.map(\.axis) == [.row, .column])
        #expect(groups[0].buttons.map(\.id) == ["locate", "lights", "plan"])
        #expect(groups[0].buttons[0].action == .locate && groups[0].buttons[0].identifier == "vacuum.locate")
        #expect(groups[0].buttons[0].hint == "Asks the robot to play a sound.")
        #expect(groups[0].buttons[1].identifier == "map.control.lights")
        if case .perform(.callService) = groups[0].buttons[1].action {} else { Issue.record("expected a service call") }
        if case .perform(.push) = groups[0].buttons[2].action {} else { Issue.record("expected navigation") }
        #expect(groups[1].buttons.map(\.action) == [.sourceCommand(.dock), .sourceCommand(.pause)])
        #expect(p.capabilities.contains("sh.surface-controls@1") && p.capabilities.contains("sh.vacuum-controls@1"))
        #expect(ServerUIMapControls.hasLocate(groups))
    }

    @Test func theIdsAreNeededWhenUsed() throws {
        let controls = [Self.group("top-trailing", "row", [Self.button("lights")])]
        let all = (try baseCapabilities() + ["sh.call-service@1", "sh.operands@1"]).sorted()
        _ = try publication(controls: controls)
        do {
            _ = try publication(controls: controls, capabilities: all)
            Issue.record("controls without its id must be refused")
        } catch let error as ServerUICompositionError {
            #expect(error.code.rawValue == "capability_manifest_mismatch")
        }
        do {
            _ = try publication(controls: nil, locate: true, orientation: ["flipHorizontal": true, "flipVertical": false], capabilities: all)
            Issue.record("an orientation without its id must be refused")
        } catch let error as ServerUICompositionError {
            #expect(error.code.rawValue == "capability_manifest_mismatch")
        }
        let flipped = try publication(controls: nil, locate: true, orientation: ["flipHorizontal": false, "flipVertical": false])
        #expect(flipped.capabilities.contains("sh.surface-orientation@1"), "an orientation with both flips off is still authored")
    }

    @Test func theOrientationReachesTheVacuumDescriptor() throws {
        let p = try publication(controls: nil, locate: true, orientation: ["flipHorizontal": true, "flipVertical": true])
        let descriptors = p.document.dataSources.compactMap { source -> ServerUIVacuumDescriptor? in
            if case .vacuum(_, let descriptor) = source { descriptor } else { nil }
        }
        let descriptor = try #require(descriptors.first)
        #expect(descriptor.orientation == MapOrientation(flipHorizontal: true, flipVertical: true))
        #expect(descriptor.configuration.mapOrientation?.flips == true)
    }

    @Test func theLocateFlagMustStateWhetherALocateButtonIsAuthored() throws {
        let withLocate = [Self.group("top-leading", "column", [Self.locate])]
        _ = try publication(controls: withLocate, locate: true)
        #expect(refusal(controls: withLocate, locate: false) == "invalid_combination /locate")
        #expect(refusal(controls: [Self.group("top-leading", "row", [Self.button("a")])], locate: true) == "invalid_combination /locate")
        let twice = [Self.group("top-leading", "row", [Self.locate, Self.button("again", Self.locateAction)])]
        #expect(refusal(controls: twice, locate: true) == "invalid_combination /controls/0/buttons/1/action")
    }

    @Test func aGroupAnIdAndACommandHaveTheirLimits() throws {
        let sameCorner = [Self.group("top-leading", "row", [Self.button("a")]), Self.group("top-leading", "column", [Self.button("b")])]
        #expect(refusal(controls: sameCorner) == "duplicate_id /controls/1/corner")
        let sameId = [Self.group("top-leading", "row", [Self.button("a")]), Self.group("top-trailing", "row", [Self.button("a")])]
        #expect(refusal(controls: sameId) == "duplicate_id /controls/1/buttons/0/id")
        let unknown = [Self.group("top-leading", "row", [Self.button("a", ["type": "source-command", "command": "selfDestruct"])])]
        #expect(refusal(controls: unknown) == "invalid_combination /controls/0/buttons/0/action/command")
        #expect(refusal(controls: [Self.group("top-leading", "row", (0..<9).map { Self.button("b\($0)") })]) == "limit_exceeded /controls/0/buttons")
        #expect(refusal(controls: [Self.group("top-leading", "row", [])]) == "limit_exceeded /controls/0/buttons")
        let five = ["top-leading", "top-trailing", "bottom-leading", "bottom-trailing", "top-leading"].enumerated()
            .map { Self.group($0.element, "row", [Self.button("b\($0.offset)")]) }
        #expect(refusal(controls: five) == "limit_exceeded /controls")
        #expect(refusal(controls: [Self.group("top-leading", "row", (0..<8).map { Self.button("b\($0)") })]) == nil)
    }

    @Test func cleanAreaNeedsTheVacuumsAreaCleaningScript() throws {
        let clean = [Self.group("top-leading", "row", [Self.button("a", ["type": "source-command", "command": "cleanArea"])])]
        #expect(refusal(controls: clean) == nil)
        #expect(refusal(controls: clean, areaCleaning: false) == "invalid_combination /controls/0/buttons/0/action/command")
    }

    @Test func aMapActionAndASourceCommandTakeNoStateRulesOfTheirOwn() throws {
        let command = [Self.group("top-leading", "row", [Self.button("a", ["type": "source-command", "command": "dock"], extra: ["visibleWhen": Self.hot])])]
        #expect(refusal(controls: command) == "invalid_combination /controls/0/buttons/0/visibleWhen")
        let locate = Self.button("locate", Self.locateAction, label: "Locate", extra: ["enabledWhen": ["condition": Self.hot, "whenUnknown": "disabled"]])
        #expect(refusal(controls: [Self.group("top-leading", "row", [locate])], locate: true) == "invalid_combination /controls/0/buttons/0/enabledWhen")
    }

    @Test func aServiceButtonMayBeShownAndEnabledByAConditionAndFollowARule() throws {
        let label: [String: Any] = ["type": "expr", "value": ["type": "choose", "cases": [["when": Self.hot, "then": ["type": "literal", "value": "Cool Down"]]],
                                                              "otherwise": ["type": "literal", "value": "Warm Up"]]]
        let ruled = Self.button("lights", label: label, extra: [
            "visibleWhen": Self.hot, "whenUnknown": "hide", "enabledWhen": ["condition": Self.hot, "whenUnknown": "disabled"],
            "icon": ["type": "conditional", "cases": [["when": Self.hot, "then": Self.icon]], "otherwise": Self.icon],
        ])
        let p = try publication(controls: [Self.group("bottom-trailing", "row", [ruled])],
                                needs: ["sh.conditions@1", "sh.rules@1", "sh.tile-disc-rules@1", "sh.visible-when@1", "sh.enabled-when@1"])
        let groups = try #require(try map(p).controls)
        let button = try #require(groups.first?.buttons.first)
        #expect(button.look.visibility != nil && button.look.enabledWhen != nil && button.look.iconRule != nil && button.look.labelValue != nil)
        #expect(p.capabilities.contains("sh.tile-disc-rules@1") && p.capabilities.contains("sh.enabled-when@1"))
    }
}
