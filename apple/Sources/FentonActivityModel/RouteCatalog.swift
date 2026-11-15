import Foundation

// MARK: - The route catalog

/// One route as Siri, Shortcuts and Spotlight need it: names, words and the path to open. No page ids, anchors or
/// predicates, so a query never needs the publication.
public struct RouteCatalogEntry: Codable, Equatable, Sendable, Identifiable {
    /// The route's stable id (not its path, which an author may rename).
    public let id: String
    /// The path a ``RouteRequest`` opens.
    public let path: String
    /// What the person says and reads.
    public let title: String
    /// The second line of a Spotlight result.
    public let summary: String
    /// The route's icon as authored: an SF Symbol name.
    public let icon: String
    /// Other paths that open the route.
    public let aliases: [String]
    /// Extra words that find the route.
    public let keywords: [String]
    /// Whether Siri and Shortcuts suggest the route by name.
    public let siri: Bool

    /// Creates an entry.
    public init(id: String, path: String, title: String, summary: String, icon: String, aliases: [String] = [],
                keywords: [String] = [], siri: Bool = false) {
        self.id = id
        self.path = path
        self.title = title
        self.summary = summary
        self.icon = icon
        self.aliases = aliases
        self.keywords = keywords
        self.siri = siri
    }
}

/// The routes the signed-in person is offered, as one small file (``RouteCatalogStore``).
///
/// Built when a publication is accepted and again when the viewer becomes known. A route whose `visibleWhen` does not hold
/// for the viewer, or cannot be answered yet, is left out: the catalog is what Siri and Spotlight list.
public struct RouteCatalog: Codable, Equatable, Sendable {
    /// The most routes a publication may author and the catalog may hold.
    public static let maximumRoutes = 64
    /// The largest catalog file, in bytes.
    public static let maximumBytes = 65_536

    /// The account the catalog belongs to (the extension store's session id).
    public let sessionID: String
    /// The accepted publication's revision.
    public let revision: Int
    /// The offered routes, in authored order.
    public let routes: [RouteCatalogEntry]

    /// Creates a catalog of entries as they are.
    public init(sessionID: String, revision: Int, routes: [RouteCatalogEntry]) {
        self.sessionID = sessionID
        self.revision = revision
        self.routes = routes
    }

    /// The catalog of the routes `viewer` is offered.
    /// - Parameters:
    ///   - sessionID: The account's session id.
    ///   - revision: The publication's revision.
    ///   - routes: The authored routes.
    ///   - viewer: What is known about the signed-in person.
    public init(sessionID: String, revision: Int, routes: [NativeExtensionPresentation.Route], viewer: RouteVisibility.Viewer) {
        self.init(sessionID: sessionID, revision: revision, routes: routes.filter {
            // No rule: always offered. A rule that cannot be decided yet (nil) hides the route until the viewer is known.
            guard let rule = $0.visibleWhen else { return true }
            return rule.evaluate(viewer) == true
        }.map {
            RouteCatalogEntry(id: $0.id, path: $0.path, title: $0.title, summary: $0.summary, icon: $0.icon,
                              aliases: $0.aliases, keywords: $0.keywords, siri: $0.siri)
        })
    }

    /// The most routes Siri and Shortcuts are offered by name at once. Spotlight lists one row per shortcut per suggested
    /// route, so the fan-out stays small; every route can still be named in a phrase (``matching(_:)``).
    public static let suggestionLimit = 10

    /// The entries Siri and Shortcuts suggest by name: `siri` routes, in authored order, up to ``suggestionLimit``.
    public var suggested: [RouteCatalogEntry] { Array(routes.filter(\.siri).prefix(Self.suggestionLimit)) }

    /// The routes with these ids, in the order asked. An id the catalog no longer lists (a deleted or hidden route) is left out.
    public func entries(withIDs ids: [String]) -> [RouteCatalogEntry] {
        ids.compactMap { id in routes.first { $0.id == id } }
    }

    /// The routes a spoken or typed phrase names: by title, alias or keyword, ignoring case and accents. Exact matches
    /// come first, then titles that begin with the phrase, then any other mention.
    public func matching(_ text: String) -> [RouteCatalogEntry] {
        let needle = Self.fold(text)
        guard !needle.isEmpty else { return [] }
        func rank(_ entry: RouteCatalogEntry) -> Int? {
            let title = Self.fold(entry.title)
            let words = entry.aliases.map { Self.fold($0.replacingOccurrences(of: "-", with: " ")) } + entry.keywords.map(Self.fold)
            if title == needle || words.contains(needle) { return 0 }
            if title.hasPrefix(needle) { return 1 }
            if title.contains(needle) || words.contains(where: { $0.contains(needle) }) { return 2 }
            return nil
        }
        return routes.compactMap { entry in rank(entry).map { (entry, $0) } }
            .enumerated().sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }.map(\.element.0)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reads and validates catalog bytes; throws for anything outside the closed shape.
    public static func decode(_ data: Data) throws -> Self {
        let object = try ExtensionJSON.object(data, maximum: maximumBytes)
        try ExtensionJSON.keys(object, ["sessionID", "revision", "routes"])
        try ExtensionJSON.text(object["sessionID"], maximum: 64, pattern: "^[a-f0-9]{64}$")
        guard let routes = object["routes"] as? [[String: Any]], routes.count <= maximumRoutes else { throw ExtensionJSON.Failure.invalid }
        for route in routes {
            try ExtensionJSON.keys(route, ["id", "path", "title", "summary", "icon", "aliases", "keywords", "siri"])
            try ExtensionJSON.identifier(route["id"])
            try ExtensionJSON.text(route["path"], maximum: 80, pattern: "^[a-z][a-z0-9-]{0,79}$")
            try ExtensionJSON.text(route["title"], maximum: 80)
            try ExtensionJSON.text(route["summary"], maximum: 240)
            try ExtensionJSON.text(route["icon"], maximum: 80, pattern: "^[a-z0-9][a-z0-9.-]{0,79}$")
            guard let aliases = route["aliases"] as? [Any], aliases.count <= 8,
                  let keywords = route["keywords"] as? [Any], keywords.count <= 12, route["siri"] is Bool else {
                throw ExtensionJSON.Failure.invalid
            }
            for alias in aliases { try ExtensionJSON.text(alias, maximum: 80, pattern: "^[a-z][a-z0-9-]{0,79}$") }
            for word in keywords { try ExtensionJSON.text(word, maximum: 40) }
        }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.revision > 0, Set(value.routes.map(\.id)).count == value.routes.count else { throw ExtensionJSON.Failure.invalid }
        return value
    }
}

// MARK: - Store

/// The route catalog file in the app group, beside ``ExtensionPresentationStore`` and fenced by the same account marker.
///
/// Siri, Shortcuts and Spotlight read only this bounded file. It never starts a connection and never decodes the
/// publication, so a query that runs in a headless launch stays cheap. Writes are atomic; sign-out removes the file
/// together with the account marker.
public struct RouteCatalogStore: Sendable {
    private let base: ExtensionPresentationStore

    /// Creates a store over the extension store's directory.
    public init(base: ExtensionPresentationStore) { self.base = base }

    /// A store in the app group; nil where the group is unavailable.
    public static var shared: Self? { ExtensionPresentationStore.shared.map(Self.init(base:)) }

    /// Replaces the catalog. Throws when `catalog` belongs to another account than the active one.
    public func write(_ catalog: RouteCatalog) throws {
        guard try base.activeSession() == catalog.sessionID else { throw ExtensionJSON.Failure.unavailable }
        let bytes = try JSONEncoder().encode(catalog)
        _ = try RouteCatalog.decode(bytes)
        try base.atomicWrite(bytes, to: base.routesURL)
    }

    /// The active account's catalog, or nil when there is none, the account changed, or the file is not valid.
    public func read() -> RouteCatalog? {
        guard let session = try? base.activeSession(), FileManager.default.fileExists(atPath: base.routesURL.path),
              let bytes = try? base.boundedRead(base.routesURL, maximum: RouteCatalog.maximumBytes),
              let catalog = try? RouteCatalog.decode(bytes), catalog.sessionID == session else { return nil }
        return catalog
    }

    /// Removes the file (the account marker stays).
    public func clear() throws {
        if FileManager.default.fileExists(atPath: base.routesURL.path) { try FileManager.default.removeItem(at: base.routesURL) }
    }
}
