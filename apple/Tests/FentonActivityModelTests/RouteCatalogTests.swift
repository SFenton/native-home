import Foundation
import Testing
@testable import FentonActivityModel

/// The route grammar the publication adds (aliases, keywords, siri, visibleWhen, linkPrefixes) and the account-scoped catalog
/// file Siri, Shortcuts and Spotlight read.
@Suite struct RouteCatalogTests {
    private let session = String(repeating: "a", count: 64)

    private func targets(routes: String, extra: String = "") -> Data {
        Data("""
        {"type":"native-extensions@1","watch":"stub@1","routes":[\(routes)],"cameras":[]\(extra)}
        """.utf8)
    }

    private func route(_ id: String, _ path: String, extra: String = "") -> String {
        """
        {"id":"\(id)","path":"\(path)","pageId":"page-\(id)","title":"\(path.capitalized)","summary":"Opens \(path)","icon":"house.fill"\(extra)}
        """
    }

    // MARK: - Grammar

    @Test func routeLinkFieldsDecodeAndRoundTrip() throws {
        let data = targets(routes: [
            route("home", "home", extra: #","aliases":["overview","house"],"keywords":["rooms"],"siri":true"#),
            route("settings", "settings", extra: #","visibleWhen":{"type":"viewer","isAdmin":true}"#),
        ].joined(separator: ","), extra: #","linkPrefixes":["my-dash"]"#)
        let value = try NativeExtensionPresentation.decode(data)
        #expect(value.routes[0].aliases == ["overview", "house"])
        #expect(value.routes[0].keywords == ["rooms"])
        #expect(value.routes[0].siri)
        #expect(value.routes[1].siri == false && value.routes[1].aliases.isEmpty)
        #expect(value.routes[1].visibleWhen == .viewer(isAdmin: true, userIds: nil))
        #expect(value.linkPrefixes == ["my-dash"])
        let again = try NativeExtensionPresentation.decode(JSONEncoder().encode(value))
        #expect(again == value)
        #expect(value.extensionCopy.linkPrefixes == nil && value.extensionCopy.routes.isEmpty)
    }

    @Test func aPlainRouteStillDecodesWithoutTheNewFields() throws {
        let value = try NativeExtensionPresentation.decode(targets(routes: route("kitchen", "kitchen")))
        #expect(value.routes[0].aliases.isEmpty && value.routes[0].keywords.isEmpty && !value.routes[0].siri)
        #expect(value.routes[0].visibleWhen == nil && value.linkPrefixes == nil)
    }

    @Test(arguments: [
        #","aliases":["Over View"]"#,
        #","aliases":["a1","a2","a3","a4","a5","a6","a7","a8","a9"]"#,
        #","aliases":["kitchen"]"#,
        #","keywords":["\#(String(repeating: "x", count: 41))"]"#,
        #","keywords":["a","b","c","d","e","f","g","h","i","j","k","l","m"]"#,
        #","siri":"yes""#,
        #","visibleWhen":{"type":"viewer-person","in":["home"]}"#,
        #","visibleWhen":{"type":"state","sourceId":"x","path":["state"],"in":["on"]}"#,
        #","visibleWhen":{"type":"viewer"}"#,
        #","visibleWhen":{"type":"all","of":[]}"#,
        #","unknown":true"#,
    ])
    func invalidRouteFieldsAreRejected(extra: String) {
        #expect(throws: (any Error).self) {
            try NativeExtensionPresentation.decode(targets(routes: route("home", "home", extra: extra)
                + "," + route("kitchen", "kitchen")))
        }
    }

    @Test func aPathOrAliasNamesOneRouteOnly() {
        #expect(throws: (any Error).self) {
            try NativeExtensionPresentation.decode(targets(routes: route("a", "home", extra: #","aliases":["x"]"#)
                + "," + route("b", "kitchen", extra: #","aliases":["x"]"#)))
        }
    }

    @Test(arguments: ["[]", #"["Bad Slug"]"#, #"["a","a"]"#, #"["a","b","c","d","e","f","g","h","i"]"#, #""text""#])
    func invalidLinkPrefixesAreRejected(list: String) {
        #expect(throws: (any Error).self) {
            try NativeExtensionPresentation.decode(targets(routes: route("a", "home"), extra: #","linkPrefixes":\#(list)"#))
        }
    }

    // MARK: - Visibility

    @Test func viewerRulesAnswerYesNoOrUnknown() {
        let admin = RouteVisibility.viewer(isAdmin: true, userIds: nil)
        #expect(admin.evaluate(.init(userId: "u", isAdmin: true)) == true)
        #expect(admin.evaluate(.init(userId: "u", isAdmin: false)) == false)
        #expect(admin.evaluate(.init(userId: "u", isAdmin: nil)) == nil)
        let named = RouteVisibility.viewer(isAdmin: nil, userIds: ["u1", "u2"])
        #expect(named.evaluate(.init(userId: "u2")) == true && named.evaluate(.init(userId: "u3")) == false)
        #expect(RouteVisibility.not(admin).evaluate(.init(isAdmin: false)) == true)
        #expect(RouteVisibility.not(admin).evaluate(.init()) == nil)
        #expect(RouteVisibility.all([admin, named]).evaluate(.init(userId: "u1", isAdmin: false)) == false)
        #expect(RouteVisibility.all([admin, named]).evaluate(.init(userId: "u1")) == nil)
        #expect(RouteVisibility.any([admin, named]).evaluate(.init(userId: "u1")) == true)
        #expect(RouteVisibility.any([admin, named]).evaluate(.init(userId: "u9")) == nil)
        #expect(RouteVisibility.any([admin, named]).evaluate(.init(userId: "u9", isAdmin: false)) == false)
    }

    // MARK: - Catalog

    private func entry(_ id: String, _ title: String, aliases: [String] = [], keywords: [String] = [], siri: Bool = false) -> RouteCatalogEntry {
        RouteCatalogEntry(id: id, path: id, title: title, summary: "Opens \(title)", icon: "house.fill",
                          aliases: aliases, keywords: keywords, siri: siri)
    }

    @Test func theCatalogOffersOnlyRoutesTheViewerMaySee() throws {
        let routes = try NativeExtensionPresentation.decode(targets(routes: [
            route("home", "home"),
            route("settings", "settings", extra: #","visibleWhen":{"type":"viewer","isAdmin":true}"#),
        ].joined(separator: ","))).routes
        let ids: (RouteVisibility.Viewer) -> [String] = {
            RouteCatalog(sessionID: session, revision: 1, routes: routes, viewer: $0).routes.map(\.id)
        }
        #expect(ids(.init(userId: "u", isAdmin: true)) == ["home", "settings"])
        #expect(ids(.init(userId: "u", isAdmin: false)) == ["home"])
        #expect(ids(.init()) == ["home"], "an unknown viewer is not offered a gated route")
    }

    @Test func queriesResolveByIdAndByNameAndSuggestOnlySiriRoutes() {
        let catalog = RouteCatalog(sessionID: session, revision: 1, routes: [
            entry("home", "Home", aliases: ["overview"], keywords: ["rooms"], siri: true),
            entry("climate", "Climate", aliases: ["thermostat"], keywords: ["Température"]),
            entry("security", "Security", keywords: ["cameras"], siri: true),
        ])
        #expect(catalog.entries(withIDs: ["security", "gone", "home"]).map(\.id) == ["security", "home"])
        #expect(catalog.suggested.map(\.id) == ["home", "security"])
        #expect(catalog.matching("climate").map(\.id) == ["climate"])
        #expect(catalog.matching("THERMOSTAT").map(\.id) == ["climate"], "an alias names its route")
        #expect(catalog.matching("temperature").map(\.id) == ["climate"], "accents and case do not matter")
        #expect(catalog.matching("cam").map(\.id) == ["security"])
        #expect(catalog.matching("  ").isEmpty && catalog.matching("zzz").isEmpty)
    }

    @Test func anExactNameOutranksAPartialMention() {
        let catalog = RouteCatalog(sessionID: session, revision: 1, routes: [
            entry("garden-lights", "Garden Lights"), entry("lights", "Lights"), entry("night", "Night", keywords: ["lights out"]),
        ])
        #expect(catalog.matching("lights").map(\.id) == ["lights", "garden-lights", "night"])
    }

    @Test func suggestionsAreCapped() {
        let routes = (0..<20).map { entry("route-\($0)", "Route \($0)", siri: true) }
        let catalog = RouteCatalog(sessionID: session, revision: 1, routes: routes)
        #expect(catalog.suggested.count == RouteCatalog.suggestionLimit)
        #expect(catalog.suggested.first?.id == "route-0")
        #expect(catalog.matching("route 19").map(\.id) == ["route-19"], "a route past the cap can still be named")
    }

    // MARK: - Store

    private func store(_ directory: URL) -> (ExtensionPresentationStore, RouteCatalogStore) {
        let base = ExtensionPresentationStore(directory: directory)
        return (base, RouteCatalogStore(base: base))
    }

    @Test func theStoreIsAccountScopedBoundedAndClearedAtSignOut() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("route-catalog-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let (base, routes) = store(directory)
        let other = String(repeating: "b", count: 64)
        let catalog = RouteCatalog(sessionID: session, revision: 3, routes: [entry("home", "Home", siri: true)])
        #expect(routes.read() == nil, "nothing before an account begins")
        #expect(throws: (any Error).self) { try routes.write(catalog) }
        try base.beginSession(session)
        try routes.write(catalog)
        #expect(routes.read() == catalog)
        #expect(throws: (any Error).self) { try routes.write(RouteCatalog(sessionID: other, revision: 1, routes: [])) }
        #expect(routes.read() == catalog, "a refused write leaves the last good catalog")
        try routes.write(RouteCatalog(sessionID: session, revision: 4, routes: [entry("home", "Home 2")]))
        #expect(routes.read()?.revision == 4, "an atomic replace")
        try base.beginSession(other)
        #expect(routes.read() == nil, "another account never reads the previous one's routes")
        try base.beginSession(session)
        #expect(routes.read()?.revision == 4)
        try base.endSession(session)
        #expect(routes.read() == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("routes.json").path), "sign-out removes the file")
    }

    @Test func clearRemovesTheFileButKeepsTheAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("route-catalog-clear-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let (base, routes) = store(directory)
        try base.beginSession(session)
        try routes.write(RouteCatalog(sessionID: session, revision: 1, routes: [entry("home", "Home")]))
        try routes.clear()
        #expect(routes.read() == nil)
        try routes.clear()
        try routes.write(RouteCatalog(sessionID: session, revision: 2, routes: []))
        #expect(routes.read()?.revision == 2)
    }

    @Test func aCorruptOrOversizedFileReadsAsNothing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("route-catalog-bad-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let (base, routes) = store(directory)
        try base.beginSession(session)
        let file = directory.appendingPathComponent("routes.json")
        try Data("not json".utf8).write(to: file)
        #expect(routes.read() == nil)
        try Data(repeating: 32, count: RouteCatalog.maximumBytes + 1).write(to: file)
        #expect(routes.read() == nil)
        let tooMany = (0...RouteCatalog.maximumRoutes).map { entry("r\($0)", "R\($0)") }
        #expect(throws: (any Error).self) {
            try RouteCatalog.decode(JSONEncoder().encode(RouteCatalog(sessionID: session, revision: 1, routes: tooMany)))
        }
        let foreign = Data(#"{"sessionID":"\#(session)","revision":1,"routes":[],"extra":1}"#.utf8)
        #expect(throws: (any Error).self) { try RouteCatalog.decode(foreign) }
    }
}
