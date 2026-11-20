import Foundation

// MARK: - Entry

/// One entity as the resolver sees it: its names, room, class, sensitivity and current state.
public struct AskEntry: Sendable {
    /// The entity id.
    public let id: String
    /// The domain part of the id.
    public let domain: String
    /// The device class (state attribute, else registry), if any.
    public let deviceClass: String?
    /// The integration platform, when the registry is present.
    public let platform: String?
    /// The device the registry puts it on, when known. Two entities on one device that report one door count once.
    public let deviceId: String?
    /// The current state.
    public var state: EntityState
    /// The name to speak: the house document's title when the friendly name does not carry it, else the friendly name.
    public let displayName: String
    /// The name without its leading room, for lines that add "(Room)".
    public let shortName: String
    /// Every spoken name variant, as stemmed word bags.
    public let nameVariants: [Set<String>]
    /// The entity's own names, normalised but not stemmed (friendly, registry, alias, overlay), not a document title that may
    /// be a bare kind word ("Lights"). A plural word that is one entity's exact name is matched against these only.
    public let ownNames: [String]
    /// The words of the entity's room.
    public let roomWords: Set<String>
    /// The room's key, when the entity has one.
    public let roomKey: String?
    /// Where the room came from.
    public let roomSource: RoomSource
    /// The floor id, when known.
    public let floorId: String?
    /// What the entity is.
    public let kind: AskKind
    /// Whether the configuration admits it as a subject: configured, and not a helper, hidden or disabled entity.
    public let askable: Bool
    /// Whether Assist exposes it.
    public let exposed: Bool
    /// Whether the house document names it.
    public let documentReferenced: Bool
    /// How private its answer is.
    public let sensitivity: AskSensitivity
    /// Whether it is a group entity (its attributes list members).
    public let isGroup: Bool
    /// The members of a group entity.
    public let members: [String]
    /// The group entities that list this one.
    public var parentGroups: [String]
    /// Whether it is a light of the aggregate kind that must not count (a group, or a colour channel).
    public let excludedFromAggregates: Bool

    /// Where an entity's room came from.
    public enum RoomSource: String, Sendable { case area, deviceArea, document, namePrefix, none }

    /// A leaf: not a group.
    public var isLeaf: Bool { !isGroup }

    /// The moment a timestamp sensor reports ("last cleaned"), when its state is one.
    public var stampedAt: Date? {
        guard domain == "sensor", deviceClass == "timestamp" || state.state.contains("T") else { return nil }
        return AskDurationResolver.parse(state.state)
    }

    /// Whether the entity reports no usable state.
    public var isUnavailable: Bool { state.state == "unavailable" || state.state == "unknown" }

    /// Creates an entry.
    init(
        id: String, deviceClass: String?, platform: String?, deviceId: String? = nil, state: EntityState, displayName: String, shortName: String,
        nameVariants: [Set<String>], ownNames: [String] = [], roomWords: Set<String>, roomKey: String?, roomSource: RoomSource, floorId: String?,
        kind: AskKind, askable: Bool, exposed: Bool, documentReferenced: Bool, sensitivity: AskSensitivity, isGroup: Bool,
        members: [String], excludedFromAggregates: Bool
    ) {
        self.id = id
        self.domain = String(id.prefix { $0 != "." })
        self.deviceClass = deviceClass
        self.platform = platform
        self.deviceId = deviceId
        self.state = state
        self.displayName = displayName
        self.shortName = shortName
        self.nameVariants = nameVariants
        self.ownNames = ownNames
        self.roomWords = roomWords
        self.roomKey = roomKey
        self.roomSource = roomSource
        self.floorId = floorId
        self.kind = kind
        self.askable = askable
        self.exposed = exposed
        self.documentReferenced = documentReferenced
        self.sensitivity = sensitivity
        self.isGroup = isGroup
        self.members = members
        self.parentGroups = []
        self.excludedFromAggregates = excludedFromAggregates
    }
}
