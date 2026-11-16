import FentonActivityModel
import Foundation
import Testing
@testable import HassCore

// MARK: - Authored system destination attachments

@Suite struct ServerUIExtensionRouteTests {
    private func bytes(capabilities: [String] = ["sh.native-extensions@1"], change: (inout [String: Any]) throws -> Void = { _ in }) throws -> Data {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ServerUICompositionFixture.json")
        var root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var document = try #require(root["document"] as? [String: Any])
        let page = try #require((document["pages"] as? [[String: Any]])?.first?["id"] as? String)
        let modal = try #require((document["modals"] as? [[String: Any]])?.first?["id"] as? String)
        let tab = try #require(((document["navigation"] as? [String: Any])?["tabs"] as? [[String: Any]])?.first?["id"] as? String)
        var targets: [String: Any] = [
            "type": "native-extensions@1", "watch": "stub@1",
            "routes": [["id": "authored-home", "path": "home", "pageId": page, "tabId": tab,
                        "title": "Home", "summary": "Your house", "icon": "house.fill",
                        "anchors": [["fragment": "details", "modalId": modal]]]],
            "cameras": [["entityId": "camera.demo_unit", "title": "Entry", "liveLabel": "Live", "unavailableLabel": "Stream unavailable"]],
        ]
        try change(&targets)
        document["extensions"] = targets
        root["document"] = document
        root["capabilities"] = (ServerUICompositionPublication.firstSliceCapabilities + capabilities).sorted()
        return try JSONSerialization.data(withJSONObject: root)
    }

    private func route(_ id: String, _ path: String, extra: [String: Any] = [:]) throws -> [String: Any] {
        var base: [String: Any] = ["id": id, "path": path, "pageId": "", "title": path, "summary": "Opens \(path)", "icon": "house.fill"]
        for (key, value) in extra { base[key] = value }
        return base
    }

    @Test func aPathResolvesToItsRouteWithItsTabAndAnchor() throws {
        let document = try ServerUICompositionPublication.decode(bytes()).document
        let target = try #require(document.target(for: RouteRequest(path: "home", anchor: "details")))
        #expect(target.pageId == document.pages.first?.surface.id)
        #expect(target.modalId == document.modals.first?.surface.id)
        #expect(target.tabId == document.extensions?.routes.first?.tabId)
        #expect(document.route(withID: "authored-home")?.path == "home")
        #expect(document.route(withID: "missing") == nil)
    }

    @Test func anUnknownAnchorOpensThePageAndDropsTheAnchor() throws {
        let document = try ServerUICompositionPublication.decode(bytes()).document
        let target = try #require(document.target(for: RouteRequest(path: "home", anchor: "missing")))
        #expect(target.pageId == document.pages.first?.surface.id)
        #expect(target.modalId == nil)
        #expect(document.target(for: RouteRequest(path: "home"))?.modalId == nil)
    }

    @Test func anUnknownPathResolvesToNothing() throws {
        let document = try ServerUICompositionPublication.decode(bytes()).document
        #expect(document.target(for: RouteRequest(path: "unknown")) == nil)
        #expect(document.target(for: RouteRequest(path: "unknown", anchor: "details")) == nil)
        #expect(document.target(for: RouteRequest(path: "Home")) == nil, "paths are exact")
    }

    @Test func noPathOpensTheInitialPage() throws {
        let document = try ServerUICompositionPublication.decode(bytes()).document
        let target = try #require(document.target(for: RouteRequest()))
        #expect(target == RouteTarget(pageId: document.navigation.initialPageId, tabId: nil, modalId: nil))
        #expect(document.target(for: RouteRequest(path: nil, anchor: "details"))?.modalId == nil, "no route, so no anchor")
    }

    @Test func aliasesOpenTheirRouteAndThePathWinsOverAnAlias() throws {
        let data = try bytes(capabilities: ["sh.native-extensions@1", "sh.route-links@1"]) { targets in
            let page = (targets["routes"] as? [[String: Any]])?.first?["pageId"] as? String ?? ""
            var home = try route("authored-home", "home", extra: ["pageId": page, "aliases": ["overview", "house"]])
            home["pageId"] = page
            var climate = try route("climate", "climate", extra: ["pageId": page, "aliases": ["thermostat"]])
            climate["pageId"] = page
            targets["routes"] = [home, climate]
        }
        let document = try ServerUICompositionPublication.decode(data).document
        #expect(document.route(matching: "overview")?.id == "authored-home")
        #expect(document.route(matching: "house")?.id == "authored-home")
        #expect(document.route(matching: "thermostat")?.id == "climate")
        #expect(document.route(matching: "climate")?.id == "climate")
        #expect(document.route(matching: "settings") == nil)
        #expect(document.target(for: RouteRequest(path: "thermostat"))?.pageId == document.pages.first?.surface.id)
    }

    @Test(arguments: ["pageId", "tabId", "modalId"])
    func attachmentsMustExistInTheAcceptedCatalog(field: String) throws {
        let data = try bytes { targets in
            var routes = try #require(targets["routes"] as? [[String: Any]])
            if field == "modalId" { routes[0]["anchors"] = [["fragment": "details", "modalId": "missing"]] }
            else { routes[0][field] = "missing" }
            targets["routes"] = routes
        }
        #expect(throws: ServerUICompositionError.self) { try ServerUICompositionPublication.decode(data) }
    }

    @Test func routeLinkFieldsNeedTheirCapability() throws {
        let withAlias: (inout [String: Any]) throws -> Void = { targets in
            var routes = try #require(targets["routes"] as? [[String: Any]])
            routes[0]["aliases"] = ["overview"]
            targets["routes"] = routes
        }
        #expect(throws: ServerUICompositionError.self) { try ServerUICompositionPublication.decode(bytes(change: withAlias)) }
        _ = try ServerUICompositionPublication.decode(bytes(capabilities: ["sh.native-extensions@1", "sh.route-links@1"], change: withAlias))
        let withPrefixes: (inout [String: Any]) throws -> Void = { $0["linkPrefixes"] = ["my-dash"] }
        #expect(throws: ServerUICompositionError.self) { try ServerUICompositionPublication.decode(bytes(change: withPrefixes)) }
        let accepted = try ServerUICompositionPublication.decode(
            bytes(capabilities: ["sh.native-extensions@1", "sh.route-links@1"], change: withPrefixes))
        #expect(accepted.document.extensions?.linkPrefixes == ["my-dash"])
    }

    @Test func aRouteMayOnlyAskAboutTheViewer() throws {
        let capabilities = ["sh.native-extensions@1", "sh.visible-when@1"]
        func publication(_ rule: [String: Any]) throws -> Data {
            try bytes(capabilities: capabilities) { targets in
                var routes = try #require(targets["routes"] as? [[String: Any]])
                routes[0]["visibleWhen"] = rule
                targets["routes"] = routes
            }
        }
        let admin = ["type": "viewer", "isAdmin": true] as [String: Any]
        let document = try ServerUICompositionPublication.decode(publication(["type": "all", "of": [admin, ["type": "not", "of": admin]]])).document
        #expect(document.extensions?.routes.first?.visibleWhen != nil)
        for rule in [["type": "viewer-person", "in": ["home"]] as [String: Any],
                     ["type": "any", "of": [admin, ["type": "viewer-person", "in": ["home"]]]],
                     ["type": "state", "sourceId": "demo", "path": ["state"], "in": ["on"]]] {
            let error = #expect(throws: ServerUICompositionError.self) { try ServerUICompositionPublication.decode(publication(rule)) }
            if let error, rule["type"] as? String != "state" { #expect(error.code == .invalidCombination, "\(rule)") }
        }
    }
}
