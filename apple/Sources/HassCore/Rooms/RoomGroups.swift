import Foundation

/// One entity in a room's lights, climate, occupancy or contact group (web `EntityButtonConfig`).
public struct RoomGroupItem: Hashable, Sendable, Identifiable, Codable {
    public var title: String
    public var entityId: String
    /// How many physical sensors one contact entity stands for (two street windows on one sensor).
    public var contactCount: Int
    /// The household member a nightstand belongs to.
    public var resident: HouseholdResident?
    /// A text helper holding this sensor's `rgba()` card color (climate sensors, web `EntityButtonConfig.colorEntityId`).
    public var colorEntityId: String?
    public var id: String { entityId + title }

    public init(_ title: String, _ entityId: String, contactCount: Int = 1, resident: HouseholdResident? = nil, color colorEntityId: String? = nil) {
        self.title = title
        self.entityId = entityId
        self.contactCount = contactCount
        self.resident = resident
        self.colorEntityId = colorEntityId
    }

    /// "Your Nightstand" for the owner, "Sam Nightstand" for anyone else signed in (web `LightsSheet`).
    public func title(for viewer: HouseholdResident?) -> String {
        guard let viewer, let resident else { return title }
        return resident == viewer ? "Your Nightstand" : "\(resident.name) Nightstand"
    }
}

/// A room's entity group, keyed by the room's title (web `LIGHT_GROUPS`, `CLIMATE_GROUPS`, `OCCUPANCY_GROUPS`,
/// `CONTACT_GROUPS`, `ha-sfenton-react-dash@9ac2a46:src/constants/atAGlance.ts:343-760`).
public struct RoomGroup: Hashable, Sendable, Codable {
    /// The room this group belongs to (the web title without its " Lights" / " Climate" suffix).
    public var room: String
    /// The group's own entity: a light group, or the climate range text.
    public var entityId: String?
    /// A text helper holding the room's `rgba()` climate color (web `EntityGroupConfig.colorEntityId`).
    public var colorEntityId: String?
    public var items: [RoomGroupItem]

    public init(_ room: String, entityId: String? = nil, colorEntityId: String? = nil, _ items: [RoomGroupItem]) {
        self.room = room
        self.entityId = entityId
        self.colorEntityId = colorEntityId
        self.items = items
    }
}

/// Per-room groups the generic room sheets list.
public enum RoomGroups {
    typealias I = RoomGroupItem

    /// The lights a room's Lights sheet shows (web `roomLightGroup`).
    public static func lights(room: String) -> RoomGroup? { allLights.first { $0.room == room } }
    /// The temperatures and vents a room's Climate sheet shows (web `roomClimateGroup`).
    public static func climate(room: String) -> RoomGroup? { allClimate.first { $0.room == room } }
    /// The presence sensors a room's Occupancy sheet shows (web `roomOccupancyGroup`).
    public static func occupancy(room: String) -> RoomGroup? { allOccupancy.first { $0.room == room } }
    /// The doors and windows a room's contact sheet shows (web `roomContactGroup`).
    public static func contacts(room: String) -> RoomGroup? { allContacts.first { $0.room == room } }

    /// Every room's contact group, for the house-wide door sheet a room without its own group opens (Back Deck, Garage).
    public static var allContacts: [RoomGroup] { HouseConfigSource.active.read { $0.rooms.contactGroups } ?? [] }

    /// Every room's lights in web order (`LIGHT_GROUPS`), as Home's Lights sheet lists them.
    public static var allLights: [RoomGroup] { HouseConfigSource.active.read { $0.rooms.lightGroups } ?? [] }
    /// Every room's temperatures and vents in web order (`CLIMATE_GROUPS`).
    public static var allClimate: [RoomGroup] { HouseConfigSource.active.read { $0.rooms.climateGroups } ?? [] }
    /// Every room's presence sensors in web order (`OCCUPANCY_GROUPS`).
    public static var allOccupancy: [RoomGroup] { HouseConfigSource.active.read { $0.rooms.occupancyGroups } ?? [] }




}
