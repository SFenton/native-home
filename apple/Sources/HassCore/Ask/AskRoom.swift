import Foundation

// MARK: - Room

/// A place a question can name: an area, a house-document room title, or both when they match.
public struct AskRoom: Sendable, Hashable {
    /// Lower-case normalised title; the room's identity.
    public let key: String
    /// The title as shown.
    public var title: String
    /// The areas that make up the room (usually one; none for a document-only title).
    public var areaIds: [String]
    /// The floor id, when known.
    public var floorId: String?
    /// Every phrase that names the room, stemmed word runs (title, area aliases, nicknames).
    public var phrases: [[String]]
    /// Whether the room comes from a house-document title with no area of the same name.
    public var documentOnly: Bool

    /// Creates a room.
    public init(key: String, title: String, areaIds: [String] = [], floorId: String? = nil, phrases: [[String]] = [], documentOnly: Bool = false) {
        self.key = key
        self.title = title
        self.areaIds = areaIds
        self.floorId = floorId
        self.phrases = phrases
        self.documentOnly = documentOnly
    }
}

/// A floor, with the phrases that name it.
public struct AskFloorInfo: Sendable, Hashable {
    /// The floor id.
    public let id: String
    /// The floor's name.
    public var name: String
    /// Phrases that name the floor ("main floor", "upstairs").
    public var phrases: [[String]]
    /// The floor's level, when known.
    public var level: Int?

    /// Creates a floor.
    public init(id: String, name: String, phrases: [[String]], level: Int? = nil) {
        self.id = id
        self.name = name
        self.phrases = phrases
        self.level = level
    }
}

/// Where a question's scope sits.
public enum AskScope: Sendable, Hashable {
    /// The whole house.
    case house
    /// One floor.
    case floor(String)
    /// One room, by key.
    case room(String)
}
