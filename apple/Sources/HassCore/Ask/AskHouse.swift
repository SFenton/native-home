import Foundation

// MARK: - Registry rows

/// One row of the entity registry, reduced to what the answerer reads (`config/entity_registry/list`).
public struct AskRegistryEntity: Codable, Sendable, Hashable {
    /// The entity id.
    public var entityId: String
    /// The device the entity belongs to.
    public var deviceId: String?
    /// The entity's own area, which wins over its device's.
    public var areaId: String?
    /// The integration that owns it.
    public var platform: String?
    /// The user's name for it (a rename).
    public var name: String?
    /// The integration's name for it.
    public var originalName: String?
    /// `diagnostic` or `config`; nil for an ordinary entity.
    public var entityCategory: String?
    /// Set when a user or integration hid it.
    public var hiddenBy: String?
    /// Set when it is disabled.
    public var disabledBy: String?
    /// Spoken aliases (`config/entity_registry/get_entries`); empty when not read.
    public var aliases: [String]
    /// Whether Assist exposes it (`options.conversation.should_expose`).
    public var exposed: Bool
    /// The registry's device class, when set.
    public var deviceClass: String?

    /// Creates a row.
    public init(
        entityId: String, deviceId: String? = nil, areaId: String? = nil, platform: String? = nil, name: String? = nil,
        originalName: String? = nil, entityCategory: String? = nil, hiddenBy: String? = nil, disabledBy: String? = nil,
        aliases: [String] = [], exposed: Bool = false, deviceClass: String? = nil
    ) {
        self.entityId = entityId
        self.deviceId = deviceId
        self.areaId = areaId
        self.platform = platform
        self.name = name
        self.originalName = originalName
        self.entityCategory = entityCategory
        self.hiddenBy = hiddenBy
        self.disabledBy = disabledBy
        self.aliases = aliases
        self.exposed = exposed
        self.deviceClass = deviceClass
    }
}

/// One device registry row (`config/device_registry/list`).
public struct AskDevice: Codable, Sendable, Hashable {
    /// The device id.
    public var id: String
    /// The device's area.
    public var areaId: String?
    /// The integration's name.
    public var name: String?
    /// The user's name for it.
    public var nameByUser: String?

    /// Creates a row.
    public init(id: String, areaId: String? = nil, name: String? = nil, nameByUser: String? = nil) {
        self.id = id
        self.areaId = areaId
        self.name = name
        self.nameByUser = nameByUser
    }
}

/// One area (`config/area_registry/list`).
public struct AskArea: Codable, Sendable, Hashable {
    /// The area id.
    public var id: String
    /// The area's name.
    public var name: String
    /// The floor it is on.
    public var floorId: String?
    /// Spoken aliases.
    public var aliases: [String]

    /// Creates an area.
    public init(id: String, name: String, floorId: String? = nil, aliases: [String] = []) {
        self.id = id
        self.name = name
        self.floorId = floorId
        self.aliases = aliases
    }
}

/// One floor (`config/floor_registry/list`).
public struct AskFloor: Codable, Sendable, Hashable {
    /// The floor id.
    public var id: String
    /// The floor's name.
    public var name: String
    /// Spoken aliases.
    public var aliases: [String]
    /// The floor's level (higher is further up), used for "upstairs" and "downstairs".
    public var level: Int?

    /// Creates a floor.
    public init(id: String, name: String, aliases: [String] = [], level: Int? = nil) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.level = level
    }
}

// MARK: - House document

/// What the answerer reads from the house document: the entity ids it names and its room groups.
///
/// Build it from a decoded ``HouseConfig`` with ``init(houseConfig:)``, or fill it by hand (the eval harness decodes a
/// stored document file into the same fields).
public struct AskHouseDocument: Sendable, Equatable {
    /// Every entity id the document names (`HouseConfig.referencedEntityIds`).
    public var referencedEntityIds: Set<String>
    /// A room's lights, keyed by room title.
    public var lightGroups: [RoomGroup]
    /// A room's temperature sensors.
    public var climateGroups: [RoomGroup]
    /// A room's occupancy sensors.
    public var occupancyGroups: [RoomGroup]
    /// A room's doors and windows.
    public var contactGroups: [RoomGroup]
    /// Vent ids per room title.
    public var ventEntityIds: [String: [String]]
    /// Every room title the document uses.
    public var roomTitles: [String]
    /// The titles the document gives an entity wherever one object pairs a title with exactly one entity id.
    public var entityTitles: [String: [String]]
    /// Titles with the role a key names ("Main Floor battery"), for matching only; never spoken.
    public var roleTitles: [String: [String]]
    /// The thermostat the document names as the house's main one, for a question about "the thermostat".
    public var primaryThermostatId: String?
    /// The weather entity the document names, for a question about the weather outside.
    public var primaryWeatherId: String?
    /// Entity lists the document keeps by kind where the kind has one list of its own: the garage doors, the locks, the alarm
    /// panel, the cameras. A house-wide question about that kind is answered from the list.
    public var deviceLists: [AskKind: [String]]
    /// The house-wide contact-sensor list (doors and windows), apart from the per-room groups.
    public var houseContactIds: [String]

    /// Creates a document view.
    public init(
        referencedEntityIds: Set<String> = [], lightGroups: [RoomGroup] = [], climateGroups: [RoomGroup] = [],
        occupancyGroups: [RoomGroup] = [], contactGroups: [RoomGroup] = [], ventEntityIds: [String: [String]] = [:],
        roomTitles: [String] = [], entityTitles: [String: [String]] = [:], roleTitles: [String: [String]] = [:], primaryThermostatId: String? = nil,
        primaryWeatherId: String? = nil, deviceLists: [AskKind: [String]] = [:], houseContactIds: [String] = []
    ) {
        self.deviceLists = deviceLists
        self.houseContactIds = houseContactIds
        self.primaryWeatherId = primaryWeatherId
        self.entityTitles = entityTitles
        self.roleTitles = roleTitles
        self.primaryThermostatId = primaryThermostatId
        self.referencedEntityIds = referencedEntityIds
        self.lightGroups = lightGroups
        self.climateGroups = climateGroups
        self.occupancyGroups = occupancyGroups
        self.contactGroups = contactGroups
        self.ventEntityIds = ventEntityIds
        self.roomTitles = roomTitles
    }

    /// Reads the answerer's view from a decoded house document. Costs one encode (`referencedEntityIds`); build once.
    public init(houseConfig: HouseConfig) {
        let rooms = houseConfig.rooms
        var titles: [String] = []
        for group in rooms.lightGroups + rooms.climateGroups + rooms.occupancyGroups + rooms.contactGroups where !titles.contains(group.room) {
            titles.append(group.room)
        }
        var vents: [String: [String]] = [:]
        for room in houseConfig.climate.rooms {
            vents[room.title] = room.ventEntityIds
            if !titles.contains(room.title) { titles.append(room.title) }
        }
        var entityTitles: [String: [String]] = [:]
        var roleTitles: [String: [String]] = [:]
        if let data = try? houseConfig.encoded(), let object = try? JSONSerialization.jsonObject(with: data) {
            Self.collectTitles(in: object, into: &entityTitles, roles: &roleTitles)
        }
        let hub = houseConfig.climate.hubEntityId
        func valid(_ ids: [String]) -> [String] {
            var seen = Set<String>()
            return ids.filter { HouseConfig.isEntityId($0) && seen.insert($0).inserted }
        }
        var lists: [AskKind: [String]] = [:]
        let security = houseConfig.security
        lists[.garage] = valid(security.garageDoors.sorted { $0.key < $1.key }.map(\.value))
        lists[.lock] = valid([security.entryLockEntityId, security.vehicleLockEntityId])
        lists[.alarm] = valid([security.alarmEntityId])
        lists[.camera] = valid(houseConfig.home.cameras.map(\.entityId))
        lists = lists.filter { !$0.value.isEmpty }
        self.init(
            referencedEntityIds: houseConfig.referencedEntityIds, lightGroups: rooms.lightGroups, climateGroups: rooms.climateGroups,
            occupancyGroups: rooms.occupancyGroups, contactGroups: rooms.contactGroups, ventEntityIds: vents, roomTitles: titles,
            entityTitles: entityTitles, roleTitles: roleTitles, primaryThermostatId: hub.isEmpty ? nil : hub,
            primaryWeatherId: houseConfig.home.weatherEntityId.isEmpty ? nil : houseConfig.home.weatherEntityId,
            deviceLists: lists, houseContactIds: valid(houseConfig.climate.contactSensors.map(\.entityId))
        )
    }

    /// The words of a key such as `batteryEntityId`: "battery".
    static func role(of key: String) -> String {
        var base = key
        if let r = base.range(of: "EntityId", options: [.caseInsensitive, .backwards]) { base.removeSubrange(r) }
        var words = ""
        for ch in base {
            if ch.isUppercase, !words.isEmpty { words.append(" ") }
            words.append(Character(ch.lowercased()))
        }
        return words
    }

    /// Walks the encoded document: an object with a `title` (or `name`) and exactly one entity id gives that entity a spoken name.
    static func collectTitles(in node: Any, into found: inout [String: [String]], roles: inout [String: [String]]) {
        if let list = node as? [Any] {
            for item in list { collectTitles(in: item, into: &found, roles: &roles) }
        } else if let object = node as? [String: Any] {
            let title = ["title", "name", "label"].lazy.compactMap { object[$0] as? String }.first { !$0.isEmpty }
            let ids = object.compactMap { key, value -> String? in
                guard key.lowercased().hasSuffix("entityid"), let id = value as? String, HouseConfig.isEntityId(id) else { return nil }
                return id
            }
            if let title, ids.count == 1, !(found[ids[0]] ?? []).contains(title) { found[ids[0], default: []].append(title) }
            // An object with a title and several entity ids (a vacuum and its battery, error and status): the main id is the
            // title, the others are the title with the role the key names ("Main Floor battery").
            if let title, ids.count > 1 {
                for (key, value) in object {
                    guard key.lowercased().hasSuffix("entityid"), let id = value as? String, HouseConfig.isEntityId(id) else { continue }
                    if key == "entityId" { if !(found[id] ?? []).contains(title) { found[id, default: []].append(title) }; continue }
                    let name = title + " " + Self.role(of: key)
                    if !(roles[id] ?? []).contains(name) { roles[id, default: []].append(name) }
                }
            }
            for value in object.values { collectTitles(in: value, into: &found, roles: &roles) }
        }
    }
}

// MARK: - House inputs

/// Everything the answerer is built from, as values.
///
/// The app fills it from `EntityStore` (``states``), the registries over `HassConnection` and the house document; the eval
/// harness fills it from files. A nil ``registry`` selects the registry-free fallback.
public struct AskHouse: Sendable {
    /// The display name of the home, used in fixed sentences.
    public var name: String
    /// Every entity state.
    public var states: [EntityState]
    /// The entity registry, or nil when it has not been read.
    public var registry: [AskRegistryEntity]?
    /// The device registry.
    public var devices: [AskDevice]
    /// The areas.
    public var areas: [AskArea]
    /// The floors.
    public var floors: [AskFloor]
    /// The house document view.
    public var document: AskHouseDocument
    /// The moment answers are relative to.
    public var now: Date
    /// The home's time zone, for "today" and local clock times.
    public var timeZone: TimeZone

    /// Creates the inputs.
    public init(
        name: String = "Demo Home", states: [EntityState], registry: [AskRegistryEntity]? = nil, devices: [AskDevice] = [],
        areas: [AskArea] = [], floors: [AskFloor] = [], document: AskHouseDocument = AskHouseDocument(), now: Date = Date(),
        timeZone: TimeZone = .current
    ) {
        self.timeZone = timeZone
        self.name = name
        self.states = states
        self.registry = registry
        self.devices = devices
        self.areas = areas
        self.floors = floors
        self.document = document
        self.now = now
    }
}
