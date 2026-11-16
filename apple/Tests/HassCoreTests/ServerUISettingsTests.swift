import Foundation
import Testing
@testable import HassCore

// MARK: - Closed settings composition

@Suite struct ServerUISettingsContractTests {
    private typealias P = ServerUICompositionPublication
    private typealias E = ServerUICompositionError

    private func publication(kind: String = "background-blur", domain: String = "preferences",
                             item: String = "", destination: JSONValue? = nil,
                             capabilities: [String] = [],
                             edit: (inout [String: JSONValue]) -> Void = { _ in }) throws -> P {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ServerUICompositionFixture.json")
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        var document = root["document"] as! [String: Any]
        var pages = document["pages"] as! [[String: Any]]
        let symbol: JSONValue = .object(["type": .string("sf-symbol"), "name": .string("gearshape"),
                                        "rendering": .string("canonical"), "unavailable": .string("reject")])
        var props: [String: JSONValue] = ["sourceId": .string("settings-source"), "kind": .string(kind),
                                          "item": .string(item), "subtitle": .string("")]
        props["destination"] = destination
        var node: [String: JSONValue] = ["id": .string("settings-control"), "title": .string("Settings"),
            "type": .string("settings-control"), "layout": .object(["span": .number(1)]),
            "icon": symbol, "props": .object(props)]
        edit(&node)
        pages[2]["components"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([JSONValue.object(node)]))
        document["pages"] = pages
        var sources = document["dataSources"] as! [[String: Any]]
        sources.append(["id": "settings-source", "kind": "model", "model": "settings-provider@1",
                        "inputs": ["providerId": "isolated-settings", "domain": domain]])
        document["dataSources"] = sources
        root["document"] = document
        root["capabilities"] = (P.firstSliceCapabilities + ["sh.settings-controls@1"] + capabilities).sorted()
        return try P.decode(JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]))
    }

    @Test func compilesTypedDomainAndRejectsCrossDomainSubstitution() throws {
        let plan = try publication()
        guard case .settingsControl(let control) = plan.document.pages[2].surface.components[0] else {
            Issue.record("Expected a domain control"); return
        }
        #expect(control.kind == .blur)
        #expect(control.kind.domain == .preferences)
        #expect(throws: E(.bindingType, "/document/pages/2/components/0/props/sourceId")) {
            try publication(domain: "feedback")
        }
    }

    @Test func rejectsUnknownFieldsAndMissingImmutableTargetKeys() throws {
        #expect(throws: E.self) { try publication { $0["controller"] = .string("settings") } }
        #expect(throws: E(.invalidCombination, "/document/pages/2/components/0/props/item")) {
            try publication(kind: "vacation-check", domain: "away")
        }
        #expect(throws: E(.invalidCombination, "/document/pages/2/components/0/props/item")) {
            try publication(item: "unexpected-target")
        }
        #expect(throws: E(.invalidCombination, "/document/pages/2/components/0/props/item")) {
            try publication(kind: "performance-action", domain: "performance", item: "run-service")
        }
    }

    @Test func requiresNavigationAttachmentAndTraversesIt() throws {
        #expect(throws: E(.invalidCombination, "/document/pages/2/components/0/props/destination")) {
            try publication(kind: "presence-room", domain: "household", item: "sample-room")
        }
        let destination = JSONValue.object(["type": .string("push"), "pageId": .string("missing-page"),
            "arguments": .object([:]), "origin": .string("sender"), "duplicate": .string("reuse-nearest")])
        #expect(throws: E(.invalidReference, "/document/pages/2/components/0/props/destination/pageId")) {
            try publication(kind: "presence-room", domain: "household", item: "sample-room", destination: destination)
        }
    }

    @Test func moduleListsAcceptSettingsRowsButNotTiles() throws {
        let wrap: (inout [String: JSONValue]) -> Void = { node in
            let child = JSONValue.object(node)
            node = ["id": .string("settings-list"), "title": .string("Preferences"), "type": .string("section"),
                    "layout": .object(["span": .number(1)]),
                    "props": .object(["header": .string("Preferences"), "footer": .string(""),
                        "style": .string("module-list"), "density": .string("thin"), "hasGlyphs": .bool(false),
                        "spacing": .object(["type": .string("token"), "name": .string("m")])]),
                    "children": .array([child])]
        }
        let capabilities = ["sh.section@1", "sh.module-settings-rows@1"]
        let result = try publication(capabilities: capabilities, edit: wrap)
        #expect(result.capabilities.contains("sh.module-settings-rows@1"))
        #expect(throws: E(.invalidCombination, "/document/pages/2/components/0/children/0/type")) {
            try publication(kind: "household-toggle", domain: "household", item: "sample-switch",
                            capabilities: capabilities, edit: wrap)
        }
    }

    @Test func pinnedFormsAcceptNativeSubmitButNotTextFields() throws {
        let wrap: (inout [String: JSONValue]) -> Void = { node in
            let child = JSONValue.object(node)
            node = ["id": .string("submit-bar"), "title": .string("Submit"), "type": .string("pinned-actions"),
                    "layout": .object(["span": .number(1)]),
                    "props": .object(["style": .string("form"), "searchPrompt": .string("Search"), "items": .array([])]),
                    "children": .array([child])]
        }
        let capabilities = ["sh.pinned-actions@1", "sh.pinned-form-actions@1"]
        let result = try publication(kind: "feedback-submit", domain: "feedback", capabilities: capabilities, edit: wrap)
        #expect(result.capabilities.contains("sh.pinned-form-actions@1"))
        #expect(throws: E(.invalidCombination, "/document/pages/2/components/0/children/0/type")) {
            try publication(kind: "feedback-field", domain: "feedback", item: "description",
                            capabilities: capabilities, edit: wrap)
        }
    }
}
