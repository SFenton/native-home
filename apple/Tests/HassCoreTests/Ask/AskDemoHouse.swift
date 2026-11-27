import Foundation
@testable import HassCore

/// A small invented home the Ask tests share: three rooms, a handful of devices, one person away. No real names.
///
/// Everything in ``states`` is configured (the house document references it) except the entities in ``unconfigured``, which
/// exist in Home Assistant only: a question about one is answered "not set up".
enum AskDemoHouse {
    /// 2030-01-15 12:00:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_894_708_800)
    static let utc = TimeZone(identifier: "UTC")!

    static func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

    static func state(
        _ id: String, _ value: String, _ attributes: [String: JSONValue] = [:], name: String? = nil, deviceClass: String? = nil,
        changed: TimeInterval = 7_200
    ) -> EntityState {
        var attrs = attributes
        if let name { attrs["friendly_name"] = .string(name) }
        if let deviceClass { attrs["device_class"] = .string(deviceClass) }
        return EntityState(entityId: id, state: value, attributes: attrs, lastChanged: ago(changed))
    }

    static var states: [EntityState] {
        [
            state("light.demo_kitchen_light", "on", name: "Demo Kitchen Light", changed: 600),
            state("light.demo_kitchen_counter", "off", name: "Demo Counter Strip"),
            state("light.demo_office_light", "on", name: "Demo Office Light", changed: 1_500),
            state("light.demo_lamp", "off", name: "Demo Living Room Lamp"),
            state("light.demo_broken_bulb", "unavailable", name: "Demo Spare Bulb"),
            state("lock.demo_front_door", "locked", name: "Demo Front Door Lock", changed: 86_400),
            state("lock.demo_back_door", "unlocked", name: "Demo Back Door Lock", changed: 3_600),
            state("cover.demo_garage_door", "closed", name: "Demo Garage Door", deviceClass: "garage"),
            state("binary_sensor.demo_office_window", "on", name: "Demo Office Window", deviceClass: "window"),
            state("binary_sensor.demo_kitchen_window", "off", name: "Demo Kitchen Window", deviceClass: "window"),
            state("sensor.demo_kitchen_temperature", "68.5", ["unit_of_measurement": .string("°F")], name: "Demo Kitchen Temperature", deviceClass: "temperature"),
            state("sensor.demo_office_temperature", "72", ["unit_of_measurement": .string("°F")], name: "Demo Office Temperature", deviceClass: "temperature"),
            state("sensor.demo_office_humidity", "41", ["unit_of_measurement": .string("%")], name: "Demo Office Humidity", deviceClass: "humidity"),
            state("person.demo_alex", "home", name: "Demo Alex"),
            state("person.demo_sam", "not_home", name: "Demo Sam", changed: 5_400),
            state("media_player.demo_tv", "playing", ["media_title": .string("Demo Show")], name: "Demo Living Room TV"),
            state("camera.demo_driveway", "recording", name: "Demo Driveway Camera"),
            state("automation.demo_porch_schedule", "on", ["last_triggered": .string("2030-01-15T10:00:00+00:00")], name: "Demo Porch Schedule"),
            state("fan.demo_kitchen_fan", "off", name: "Demo Fan"),
            state("fan.demo_office_fan", "on", name: "Demo Fan"),
            state("weather.demo_weather", "sunny", ["temperature": .number(55), "temperature_unit": .string("°F")], name: "Demo Weather"),
            state("light.demo_porch_light", "on", name: "Demo Porch Light"),
            state("sensor.demo_attic_humidity", "55", ["unit_of_measurement": .string("%")], name: "Demo Attic Humidity", deviceClass: "humidity"),
            state("media_player.demo_bedroom_tv", "playing", name: "Demo Bedroom TV"),
        ]
    }

    /// Entities that exist but that the configuration does not name.
    static let unconfigured: Set<String> = ["light.demo_porch_light", "sensor.demo_attic_humidity", "media_player.demo_bedroom_tv"]

    /// The house document: it references every demo entity but the unconfigured ones.
    static func document(_ states: [EntityState]? = nil) -> AskHouseDocument {
        AskHouseDocument(referencedEntityIds: Set((states ?? Self.states).map(\.entityId)).subtracting(unconfigured))
    }

    static let registry: [AskRegistryEntity] = [
        AskRegistryEntity(entityId: "light.demo_kitchen_light", areaId: "kitchen", exposed: true),
        AskRegistryEntity(entityId: "light.demo_kitchen_counter", areaId: "living_room", exposed: true),
        AskRegistryEntity(entityId: "light.demo_office_light", areaId: "office", exposed: true),
        AskRegistryEntity(entityId: "light.demo_lamp", areaId: "living_room", exposed: true),
        AskRegistryEntity(entityId: "light.demo_broken_bulb", areaId: "living_room", exposed: true),
        AskRegistryEntity(entityId: "lock.demo_front_door", exposed: true),
        AskRegistryEntity(entityId: "lock.demo_back_door", exposed: true),
        AskRegistryEntity(entityId: "cover.demo_garage_door", exposed: true),
        AskRegistryEntity(entityId: "binary_sensor.demo_office_window", areaId: "office", deviceClass: "window"),
        AskRegistryEntity(entityId: "binary_sensor.demo_kitchen_window", areaId: "kitchen", deviceClass: "window"),
        AskRegistryEntity(entityId: "sensor.demo_kitchen_temperature", areaId: "kitchen", deviceClass: "temperature"),
        AskRegistryEntity(entityId: "sensor.demo_office_temperature", areaId: "office", deviceClass: "temperature"),
        AskRegistryEntity(entityId: "sensor.demo_office_humidity", areaId: "office", deviceClass: "humidity"),
        AskRegistryEntity(entityId: "person.demo_alex"),
        AskRegistryEntity(entityId: "person.demo_sam"),
        AskRegistryEntity(entityId: "media_player.demo_tv", areaId: "living_room"),
        AskRegistryEntity(entityId: "camera.demo_driveway"),
        AskRegistryEntity(entityId: "automation.demo_porch_schedule", exposed: true),
        AskRegistryEntity(entityId: "fan.demo_kitchen_fan", areaId: "kitchen"),
        AskRegistryEntity(entityId: "fan.demo_office_fan", areaId: "office"),
        AskRegistryEntity(entityId: "weather.demo_weather"),
        AskRegistryEntity(entityId: "light.demo_porch_light", exposed: true),
        AskRegistryEntity(entityId: "sensor.demo_attic_humidity", deviceClass: "humidity"),
        AskRegistryEntity(entityId: "media_player.demo_bedroom_tv"),
    ]

    static let areas = [
        AskArea(id: "kitchen", name: "Kitchen", floorId: "main"),
        AskArea(id: "office", name: "Office", floorId: "main"),
        AskArea(id: "living_room", name: "Living Room", floorId: "main"),
    ]

    static let floors = [AskFloor(id: "main", name: "Main Floor", level: 0)]

    static func house(registry withRegistry: Bool = true, states: [EntityState]? = nil) -> AskHouse {
        AskHouse(
            name: "Demo Home", states: states ?? Self.states, registry: withRegistry ? registry : nil, areas: areas, floors: floors,
            document: document(states), now: now, timeZone: utc
        )
    }

    static func index(registry withRegistry: Bool = true, configuration: AskConfiguration = AskConfiguration(), states: [EntityState]? = nil) -> AskableIndex {
        AskableIndex(house: house(registry: withRegistry, states: states), configuration: configuration)
    }
}

/// A data source over fixed rows, for the duration, cause and last-time tests.
struct AskStubSource: AskDataSource {
    var logbookRows: [String: [AskLogbookRow]] = [:]
    var historyPoints: [String: [AskHistoryPoint]] = [:]
    var failsHistory = false

    func logbook(entityId: String, from: Date, to: Date) async throws -> [AskLogbookRow] {
        (logbookRows[entityId] ?? []).filter { $0.when >= from && $0.when <= to }
    }

    func history(entityId: String, from: Date, to: Date) async throws -> [AskHistoryPoint] {
        if failsHistory { throw AskNoDataSource.Unavailable() }
        return historyPoints[entityId] ?? []
    }
}
