import Foundation

/// When a route is offered to the person (Siri, Shortcuts, Spotlight): the viewer predicates of the publication's
/// `visibleWhen` grammar and their combinators, and nothing that reads entity state.
///
/// A route catalog is built without an `EntityStore`, so a route can only ask about the signed-in person
/// (`viewer`), never about a device. It is presentation, not access control: the publication is readable by any
/// signed-in user.
public indirect enum RouteVisibility: Codable, Equatable, Sendable {
    /// The signed-in user is an administrator and/or one of `userIds` (both must hold when both are given).
    case viewer(isAdmin: Bool?, userIds: [String]?)
    /// Every part holds.
    case all([RouteVisibility])
    /// At least one part holds.
    case any([RouteVisibility])
    /// The part does not hold.
    case not(RouteVisibility)

    /// What the catalog knows about the person.
    public struct Viewer: Equatable, Sendable {
        /// Home Assistant's user id, when known.
        public var userId: String?
        /// Whether the user is an administrator, when known.
        public var isAdmin: Bool?

        /// Creates a viewer.
        public init(userId: String? = nil, isAdmin: Bool? = nil) {
            self.userId = userId
            self.isAdmin = isAdmin
        }
    }

    // MARK: - Evaluation

    /// Whether the rule holds for `viewer`; nil while a fact it needs is not known.
    public func evaluate(_ viewer: Viewer) -> Bool? {
        switch self {
        case .viewer(let isAdmin, let userIds):
            var parts: [Bool?] = []
            if let isAdmin { parts.append(viewer.isAdmin.map { $0 == isAdmin }) }
            if let userIds { parts.append(viewer.userId.map { userIds.contains($0) }) }
            return Self.conjunction(parts)
        case .all(let items): return Self.conjunction(items.map { $0.evaluate(viewer) })
        case .any(let items):
            let parts = items.map { $0.evaluate(viewer) }
            if parts.contains(true) { return true }
            return parts.contains(nil) ? nil : false
        case .not(let item): return item.evaluate(viewer).map { !$0 }
        }
    }

    private static func conjunction(_ parts: [Bool?]) -> Bool? {
        if parts.contains(false) { return false }
        return parts.contains(nil) ? nil : true
    }

    // MARK: - Codable (the publication's JSON shape)

    private enum Keys: String, CodingKey { case type, isAdmin, userIds, of }

    /// Decodes the value from its wire form.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "viewer":
            self = .viewer(isAdmin: try container.decodeIfPresent(Bool.self, forKey: .isAdmin),
                           userIds: try container.decodeIfPresent([String].self, forKey: .userIds))
        case "all": self = .all(try container.decode([RouteVisibility].self, forKey: .of))
        case "any": self = .any(try container.decode([RouteVisibility].self, forKey: .of))
        case "not": self = .not(try container.decode(RouteVisibility.self, forKey: .of))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "unknown rule")
        }
    }

    /// Encodes the value to its wire form.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .viewer(let isAdmin, let userIds):
            try container.encode("viewer", forKey: .type)
            try container.encodeIfPresent(isAdmin, forKey: .isAdmin)
            try container.encodeIfPresent(userIds, forKey: .userIds)
        case .all(let items):
            try container.encode("all", forKey: .type)
            try container.encode(items, forKey: .of)
        case .any(let items):
            try container.encode("any", forKey: .type)
            try container.encode(items, forKey: .of)
        case .not(let item):
            try container.encode("not", forKey: .type)
            try container.encode(item, forKey: .of)
        }
    }

    // MARK: - Validation

    /// Checks the raw JSON of a route's `visibleWhen` before it is decoded: only the viewer grammar, bounded.
    static func validate(_ value: Any?, depth: Int = 0) throws {
        guard depth <= 4, let object = value as? [String: Any], let type = object["type"] as? String else {
            throw ExtensionJSON.Failure.invalid
        }
        switch type {
        case "viewer":
            try ExtensionJSON.keys(object, Set(["type"] + ["isAdmin", "userIds"].filter { object[$0] != nil }))
            guard object["isAdmin"] != nil || object["userIds"] != nil else { throw ExtensionJSON.Failure.invalid }
            if let flag = object["isAdmin"], !(flag is Bool) { throw ExtensionJSON.Failure.invalid }
            if let ids = object["userIds"] {
                guard let ids = ids as? [Any], !ids.isEmpty, ids.count <= 32 else { throw ExtensionJSON.Failure.invalid }
                for id in ids { try ExtensionJSON.text(id, maximum: 160) }
            }
        case "all", "any":
            try ExtensionJSON.keys(object, ["type", "of"])
            guard let items = object["of"] as? [Any], !items.isEmpty, items.count <= 8 else { throw ExtensionJSON.Failure.invalid }
            for item in items { try validate(item, depth: depth + 1) }
        case "not":
            try ExtensionJSON.keys(object, ["type", "of"])
            try validate(object["of"], depth: depth + 1)
        default:
            throw ExtensionJSON.Failure.invalid
        }
    }
}
