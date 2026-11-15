import Foundation

// MARK: - Closed target projection

/// Target-safe copy and route attachment. No entities' state, credentials, URLs, assets or service calls.
public struct NativeExtensionPresentation: Codable, Equatable, Sendable {
    public let type: String
    public let watch: String
    public let routes: [Route]
    public let cameras: [Camera]
    /// The first path segments that mark a link as one of the dashboard's (`/<slug>/home?path=kitchen`). Nil while the
    /// publication authors none: the app then reads the three slugs the integration has always sent.
    public let linkPrefixes: [String]?

    /// One authored route: a plain path that push links, Live Activity links, Spotlight and Siri open.
    public struct Route: Codable, Equatable, Sendable {
        public let id: String
        public let path: String
        public let pageId: String
        public let title: String
        public let summary: String
        public let icon: String
        public let tabId: String?
        public let anchors: [Anchor]?
        /// Other paths that open this route (links older automations still send); unique across all routes and paths.
        public let aliases: [String]
        /// Words that find this route in Spotlight and Siri besides its title.
        public let keywords: [String]
        /// Whether Siri and Shortcuts suggest this route by name; every route can still be named in a phrase.
        public let siri: Bool
        /// When the route is offered to the person; nil means always. Viewer predicates only.
        public let visibleWhen: RouteVisibility?

        private enum Keys: String, CodingKey {
            case id, path, pageId, title, summary, icon, tabId, anchors, aliases, keywords, siri, visibleWhen
        }

        /// Decodes the value from its wire form.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            id = try c.decode(String.self, forKey: .id)
            path = try c.decode(String.self, forKey: .path)
            pageId = try c.decode(String.self, forKey: .pageId)
            title = try c.decode(String.self, forKey: .title)
            summary = try c.decode(String.self, forKey: .summary)
            icon = try c.decode(String.self, forKey: .icon)
            tabId = try c.decodeIfPresent(String.self, forKey: .tabId)
            anchors = try c.decodeIfPresent([Anchor].self, forKey: .anchors)
            aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
            keywords = try c.decodeIfPresent([String].self, forKey: .keywords) ?? []
            siri = try c.decodeIfPresent(Bool.self, forKey: .siri) ?? false
            visibleWhen = try c.decodeIfPresent(RouteVisibility.self, forKey: .visibleWhen)
        }

        /// Encodes the value to its wire form.
        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(id, forKey: .id)
            try c.encode(path, forKey: .path)
            try c.encode(pageId, forKey: .pageId)
            try c.encode(title, forKey: .title)
            try c.encode(summary, forKey: .summary)
            try c.encode(icon, forKey: .icon)
            try c.encodeIfPresent(tabId, forKey: .tabId)
            try c.encodeIfPresent(anchors, forKey: .anchors)
            if !aliases.isEmpty { try c.encode(aliases, forKey: .aliases) }
            if !keywords.isEmpty { try c.encode(keywords, forKey: .keywords) }
            if siri { try c.encode(true, forKey: .siri) }
            try c.encodeIfPresent(visibleWhen, forKey: .visibleWhen)
        }
    }
    /// The authored anchor.
    public struct Anchor: Codable, Equatable, Sendable {
        public let fragment: String
        public let modalId: String
    }
    /// The authored camera.
    public struct Camera: Codable, Equatable, Sendable {
        public let entityId: String
        public let title: String
        public let liveLabel: String
        public let unavailableLabel: String
    }

    /// Spotlight/navigation stays in the app. Extensions receive only their presentation needs.
    public var extensionCopy: Self {
        .init(type: type, watch: watch, routes: [], cameras: cameras, linkPrefixes: nil)
    }

    /// Validates unknown fields before Codable can discard them. Core also applies page-reference validation.
    public static func decode(_ data: Data) throws -> Self {
        let json = try ExtensionJSON.object(data, maximum: 32_768)
        try ExtensionJSON.keys(json, json["linkPrefixes"] == nil ? ["type", "watch", "routes", "cameras"]
                                                                  : ["type", "watch", "routes", "cameras", "linkPrefixes"])
        guard json["type"] as? String == "native-extensions@1", json["watch"] as? String == "stub@1",
              let routes = json["routes"] as? [[String: Any]], routes.count <= 64,
              let cameras = json["cameras"] as? [[String: Any]], cameras.count <= 32 else { throw ExtensionJSON.Failure.invalid }
        for route in routes {
            var keys: Set<String> = ["id", "path", "pageId", "title", "summary", "icon"]
            if route["tabId"] != nil { keys.insert("tabId"); try ExtensionJSON.identifier(route["tabId"]) }
            if route["aliases"] != nil { keys.insert("aliases"); try pathList(route["aliases"], maximum: 8) }
            if let words = route["keywords"] {
                keys.insert("keywords")
                guard let words = words as? [Any], words.count <= 12 else { throw ExtensionJSON.Failure.invalid }
                for word in words { try ExtensionJSON.text(word, maximum: 40) }
            }
            if let siri = route["siri"] { keys.insert("siri"); guard siri is Bool else { throw ExtensionJSON.Failure.invalid } }
            if let rule = route["visibleWhen"] { keys.insert("visibleWhen"); try RouteVisibility.validate(rule) }
            if let anchors = route["anchors"] {
                keys.insert("anchors")
                guard let entries = anchors as? [[String: Any]], entries.count <= 32 else { throw ExtensionJSON.Failure.invalid }
                for entry in entries {
                    try ExtensionJSON.keys(entry, ["fragment", "modalId"])
                    try ExtensionJSON.identifier(entry["fragment"])
                    try ExtensionJSON.identifier(entry["modalId"])
                }
                guard Set(entries.compactMap { $0["fragment"] as? String }).count == entries.count else { throw ExtensionJSON.Failure.invalid }
            }
            try ExtensionJSON.keys(route, keys)
            for key in ["id", "pageId"] { try ExtensionJSON.identifier(route[key]) }
            try ExtensionJSON.text(route["path"], maximum: 80, pattern: "^[a-z][a-z0-9-]{0,79}$")
            try ExtensionJSON.text(route["icon"], maximum: 80, pattern: "^[a-z0-9][a-z0-9.-]{0,79}$")
            try ExtensionJSON.text(route["title"], maximum: 80)
            try ExtensionJSON.text(route["summary"], maximum: 240)
        }
        for camera in cameras {
            try ExtensionJSON.keys(camera, ["entityId", "title", "liveLabel", "unavailableLabel"])
            try ExtensionJSON.text(camera["entityId"], maximum: 160, pattern: "^camera\\.[a-z0-9_]+$")
            try ExtensionJSON.text(camera["title"], maximum: 80)
            try ExtensionJSON.text(camera["liveLabel"], maximum: 40)
            try ExtensionJSON.text(camera["unavailableLabel"], maximum: 80)
        }
        if let prefixes = json["linkPrefixes"] { try pathList(prefixes, maximum: 8, minimum: 1) }
        let value = try JSONDecoder().decode(Self.self, from: data)
        // A path or alias names one route only, so a link can never be ambiguous.
        let names = value.routes.flatMap { [$0.path] + $0.aliases }
        guard Set(names).count == names.count,
              Set(value.linkPrefixes ?? []).count == (value.linkPrefixes ?? []).count else { throw ExtensionJSON.Failure.invalid }
        guard Set(value.routes.map(\.id)).count == routes.count, Set(value.routes.map(\.path)).count == routes.count,
              Set(value.cameras.map(\.entityId)).count == cameras.count else { throw ExtensionJSON.Failure.invalid }
        return value
    }
}

extension NativeExtensionPresentation {
    /// A list of plain paths (`^[a-z][a-z0-9-]{0,79}$`), at most `maximum` long.
    private static func pathList(_ value: Any?, maximum: Int, minimum: Int = 0) throws {
        guard let items = value as? [Any], items.count >= minimum, items.count <= maximum else { throw ExtensionJSON.Failure.invalid }
        for item in items { try ExtensionJSON.text(item, maximum: 80, pattern: "^[a-z][a-z0-9-]{0,79}$") }
    }
}

// MARK: - Dependency-free extension validation

enum ExtensionJSON {
    enum Failure: Error { case invalid, unavailable }
    static func keys(_ object: [String: Any], _ expected: Set<String>) throws {
        guard Set(object.keys) == expected else { throw Failure.invalid }
    }
    static func text(_ value: Any?, maximum: Int, pattern: String? = nil) throws {
        guard let value = value as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.utf16.count <= maximum, !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              pattern.map({ value.range(of: $0, options: .regularExpression) == value.startIndex..<value.endIndex }) ?? true else {
            throw Failure.invalid
        }
    }
    static func identifier(_ value: Any?) throws {
        try text(value, maximum: 80, pattern: "^[A-Za-z0-9][A-Za-z0-9_.-]{0,79}$")
        guard let value = value as? String, !["__proto__", "prototype", "constructor"].contains(value) else { throw Failure.invalid }
    }
    static func object(_ data: Data, maximum: Int) throws -> [String: Any] {
        guard data.count <= maximum else { throw Failure.invalid }
        // The small scanner keeps duplicate keys from being collapsed by Foundation.
        var scanner = KeyScanner(bytes: Array(data))
        try scanner.value(depth: 0)
        scanner.whitespace()
        guard scanner.index == data.count,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.invalid }
        return object
    }
    private struct KeyScanner {
        let bytes: [UInt8]
        var index = 0
        mutating func whitespace() { while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
        mutating func take(_ byte: UInt8) -> Bool {
            whitespace()
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }
        mutating func string() throws -> String {
            whitespace()
            let start = index
            guard take(34) else { throw Failure.invalid }
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if byte == 92 {
                    guard index < bytes.count else { throw Failure.invalid }
                    index += 1
                } else if byte == 34 {
                    guard let text = try JSONSerialization.jsonObject(with: Data(bytes[start..<index]), options: .fragmentsAllowed) as? String
                    else { throw Failure.invalid }
                    return text
                }
            }
            throw Failure.invalid
        }
        mutating func value(depth: Int) throws {
            guard depth <= 8 else { throw Failure.invalid }
            whitespace()
            guard index < bytes.count else { throw Failure.invalid }
            if take(123) {
                var keys: Set<String> = []
                if take(125) { return }
                repeat {
                    guard keys.insert(try string()).inserted, take(58) else { throw Failure.invalid }
                    try value(depth: depth + 1)
                    if take(125) { return }
                } while take(44)
                throw Failure.invalid
            } else if take(91) {
                if take(93) { return }
                repeat {
                    try value(depth: depth + 1)
                    if take(93) { return }
                } while take(44)
                throw Failure.invalid
            } else if bytes[index] == 34 {
                _ = try string()
            } else {
                let start = index
                while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
                guard index > start else { throw Failure.invalid }
            }
        }
    }
}
