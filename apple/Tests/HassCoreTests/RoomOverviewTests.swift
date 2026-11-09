@testable import HassCore
import HassTestSupport
import Testing

/// Home's room overview sheets (web `AtAGlancePage.tsx` `LightsSheet`, `ClimateSheet`, `OccupancySheet`,
/// `ContactSheet`, `AirQualitySheet`).
@Suite(.demoHouse)
struct RoomOverviewTests {
    private func states(_ values: [(String, String)], attributes: [String: [String: JSONValue]] = [:]) -> RoomOverview.Read {
        let map = Dictionary(uniqueKeysWithValues: values.map { ($0.0, EntityState(entityId: $0.0, state: $0.1, attributes: attributes[$0.0] ?? [:])) })
        return { map[$0] }
    }

    private func group(_ kind: RoomOverviewKind, _ room: String) -> RoomGroup {
        RoomOverview.groups(kind).first { $0.room == room }!
    }

    // MARK: Data

    @Test func groupsFollowTheWebLists() {
        #expect(RoomOverview.groups(.lights).count == 17)
        #expect(RoomOverview.groups(.lights).map(\.room).suffix(2) == ["Entryway", "Driveway"])
        #expect(RoomOverview.groups(.lights)[3].room == "Bedroom 1 Closet")
        #expect(RoomOverview.groups(.climate).count == 14)
        #expect(RoomOverview.groups(.occupancy).count == 15)
        #expect(RoomOverview.groups(.contacts).count == 11)
        #expect(RoomOverview.groups(.airQuality).isEmpty)
        #expect(RoomOverview.airQualityRooms.count == 6)
        // The closet light sits in two groups but counts once.
        #expect(RoomOverview.lightEntityIds.filter { $0 == "light.demo_bedroom_1_light_2" }.count == 1)
        #expect(RoomOverview.contactEntityIds.count == 12)
    }

    @Test func climateGroupsCarryTheirColorHelpers() {
        let living = group(.climate, "Living Room")
        #expect(living.colorEntityId == "input_text.demo_living_room_color_2")
        #expect(living.items.first?.colorEntityId == "input_text.demo_living_room_color_3")
        #expect(living.items.last?.colorEntityId == nil, "Vents have no color helper")
        #expect(group(.climate, "Bedroom 1").items[1].colorEntityId == "input_text.demo_bedroom_1_color_4")
    }

    @Test func aDeadSensorIsSpokenAsUnavailableNotAsClosedOrEmpty() throws {
        let office = group(.occupancy, "Office")
        let ids = office.items.map(\.entityId)
        let allOffline = states(ids.map { ($0, "unavailable") })
        #expect(RoomOverview.unavailableCount(office, read: allOffline) == ids.count)
        // Every sensor dead: the card shows and speaks one word, and stays navigable (the page names each sensor).
        #expect(RoomOverview.allUnavailable(office, read: allOffline))
        #expect(RoomOverview.cardSubtitle(.occupancy, office, read: allOffline) == "Unavailable")
        #expect(RoomOverview.spokenSubtitle(.occupancy, office, read: allOffline) == "Unavailable")
        let contacts = group(.contacts, "Office")
        let deadContacts = states(contacts.items.map { ($0.entityId, "unavailable") })
        #expect(RoomOverview.cardSubtitle(.contacts, contacts, read: deadContacts) == "Unavailable", "a dead contact sensor is not Closed")
        // Some dead: the state of the rest, and how many are not answering.
        if ids.count > 1 {
            let partial = states(ids.enumerated().map { ($1, $0 == 0 ? "unavailable" : "off") })
            #expect(!RoomOverview.allUnavailable(office, read: partial))
            #expect(RoomOverview.spokenSubtitle(.occupancy, office, read: partial) == "Not Occupied, 1 sensor unavailable")
        }
        let online = states(ids.map { ($0, "off") })
        #expect(RoomOverview.unavailableCount(office, read: online) == 0)
        #expect(RoomOverview.spokenSubtitle(.occupancy, office, read: online) == "Not Occupied")
        #expect(RoomOverview.unavailableCount(office, read: { _ in nil }) == 0, "a state not yet loaded is not called unavailable")
        #expect(!RoomOverview.allUnavailable(office, read: { _ in nil }))
    }

    // MARK: Titles and sections

    @Test func lightsTitleCountsLightsOn() {
        #expect(RoomOverview.sheetTitle(.lights) { _ in nil } == "Lights (All Off)")
        let read = states([("light.demo_kitchen_light_1", "on"), ("light.demo_gym_light_item_1", "on")])
        #expect(RoomOverview.sheetTitle(.lights, read: read) == "Lights (2 On)")
        #expect(RoomOverview.sheetTitle(.climate, read: read) == "Climate")
        #expect(RoomOverview.sheetTitle(.occupancy, read: read) == "Occupancy")
        #expect(RoomOverview.sheetTitle(.contacts, read: read) == "Contact Sensors")
        #expect(RoomOverview.sheetTitle(.airQuality, read: read) == "Air Quality")
    }

    @Test func sheetNamesAndSubtitles() {
        let none: RoomOverview.Read = { _ in nil }
        #expect(RoomOverview.sheetName(.lights) == "Lights")
        #expect(RoomOverview.sheetName(.contacts) == "Contact Sensors")
        #expect(RoomOverview.sheetSubtitle(.lights, read: none) == "All Off")
        #expect(RoomOverview.sheetSubtitle(.occupancy, read: none) == "All Clear")
        #expect(RoomOverview.sheetSubtitle(.contacts, read: none) == "All Closed")
        #expect(RoomOverview.sheetSubtitle(.climate, read: none) == nil)
        #expect(RoomOverview.sheetSubtitle(.airQuality, read: none) == nil)

        let lights = states([("light.demo_kitchen_light_1", "on"), ("light.demo_gym_light_item_1", "on")])
        #expect(RoomOverview.sheetSubtitle(.lights, read: lights) == "2 of \(RoomOverview.lightEntityIds.count) On")

        let office = group(.occupancy, "Office")
        let occupied = states(office.items.prefix(1).map { ($0.entityId, "on") })
        #expect(RoomOverview.sheetSubtitle(.occupancy, read: occupied) == "1 Room Occupied")

        let open = states([(RoomOverview.contactEntityIds[0], "on"), (RoomOverview.contactEntityIds[1], "on")])
        #expect(RoomOverview.sheetSubtitle(.contacts, read: open) == "2 Open")
    }

    @Test func lightsSplitOnThenOff() {
        let read = states([("light.demo_kitchen_light_1", "on"), ("light.demo_media_room_1", "on")])
        let sections = RoomOverview.sections(.lights, read: read)
        #expect(sections.map(\.title) == ["Lights On", "Lights Off"])
        #expect(sections[0].groups.map(\.room) == ["Kitchen", "Media room"])
        #expect(sections[1].groups.count == 15)
        // Everything off drops the empty "Lights On" section.
        #expect(RoomOverview.sections(.lights) { _ in nil }.map(\.title) == ["Lights Off"])
    }

    @Test func occupancySplitsOccupiedThenClear() {
        let read = states([("binary_sensor.demo_gym_presence_1", "on")])
        let sections = RoomOverview.sections(.occupancy, read: read)
        #expect(sections.map(\.title) == ["Occupied", "Clear"])
        #expect(sections[0].groups.map(\.room) == ["Gym"])
    }

    @Test func climateAndContactsListEveryRoom() {
        #expect(RoomOverview.sections(.climate) { _ in nil }.map(\.title) == ["Rooms"])
        #expect(RoomOverview.sections(.contacts) { _ in nil }.first?.groups.count == 11)
        #expect(RoomOverview.sections(.airQuality) { _ in nil }.first?.groups.isEmpty == true)
    }

    @Test func detailTitlesMatchWebGroupTitles() {
        #expect(RoomOverview.detailTitle(.lights, group(.lights, "Living Room")) == "Living Room Lights")
        #expect(RoomOverview.detailTitle(.lights, group(.lights, "Bedroom 1 Closet")) == "Bedroom 1 Closet Light")
        #expect(RoomOverview.detailTitle(.climate, group(.climate, "Office")) == "Office Climate")
        #expect(RoomOverview.detailTitle(.occupancy, group(.occupancy, "Hallway")) == "Hallway Occupancy")
        #expect(RoomOverview.detailTitle(.contacts, group(.contacts, "Entryway")) == "Entryway Contact Sensors")
        #expect(RoomOverview.detailTitle(.airQuality, group(.contacts, "Entryway")) == "Entryway")
    }

    // MARK: Subtitles

    @Test func lightSubtitles() {
        let living = group(.lights, "Living Room")
        let gym = group(.lights, "Gym")
        #expect(RoomOverview.lightSubtitle(living, read: states([("light.demo_living_room_light_1", "on"), ("light.demo_living_room_light_3", "on")])) == "2 On")
        #expect(RoomOverview.lightSubtitle(gym, read: states([("light.demo_gym_light_item_1", "on")])) == "On")
        #expect(RoomOverview.lightSubtitle(gym) { _ in nil } == "Off")
        #expect(RoomOverview.lightSubtitle(living, read: states([("light.demo_living_room_item_1", "unavailable")])) == "Unavailable")
        #expect(RoomOverview.isActive(.lights, living, read: states([("light.demo_living_room_item_1", "on")])))
        #expect(!RoomOverview.isActive(.lights, living) { _ in nil })
        #expect(RoomOverview.cardSubtitle(.lights, gym, read: states([("light.demo_gym_light_item_1", "on")])) == "On")
    }

    @Test func occupancySubtitles() {
        let living = group(.occupancy, "Living Room")
        let read = states([("binary_sensor.demo_living_room_presence_2", "on")])
        #expect(RoomOverview.cardSubtitle(.occupancy, living, read: read) == "Occupied")
        #expect(RoomOverview.cardSubtitle(.occupancy, living) { _ in nil } == "Not Occupied")
        #expect(RoomOverview.detailSubtitle(.occupancy, living, read: read) == "1 sensor occupied")
        #expect(RoomOverview.detailSubtitle(.occupancy, living) { _ in nil } == "0 sensors occupied")
    }

    @Test func contactSubtitles() {
        let office = group(.contacts, "Office")
        let read = states([("binary_sensor.demo_office_contact_1", "on")])
        #expect(RoomOverview.cardSubtitle(.contacts, office, read: read) == "1 Window Open")
        #expect(RoomOverview.detailSubtitle(.contacts, office) { _ in nil } == "All Windows Closed")
        #expect(RoomOverview.isActive(.contacts, office, read: read))
        #expect(RoomOverview.isWindowGroup(office))
        #expect(!RoomOverview.isWindowGroup(group(.contacts, "Entryway")))
        #expect(RoomOverview.contactCountSummary(0) == "All Closed")
        #expect(RoomOverview.openContactCount(read: read) == 1)
    }

    @Test func climateSubtitlesPreferTheRangeHelper() {
        let office = group(.climate, "Office")
        #expect(RoomOverview.cardSubtitle(.climate, office, read: states([("input_text.demo_office_1", "70.06 - 72.49°F")])) == "70.0 - 72.4°F")
        let sensors = states([
            ("sensor.demo_office_temperature_1", "71.27"), ("sensor.demo_office_temperature_2", "69.9"),
        ], attributes: [
            "sensor.demo_office_temperature_1": ["unit_of_measurement": .string("°F")],
            "sensor.demo_office_temperature_2": ["unit_of_measurement": .string("°F")],
        ])
        #expect(RoomOverview.climateSubtitle(office, read: sensors) == "69.9°F - 71.2°F")
        let one = states([("sensor.demo_office_temperature_1", "71.0")])
        #expect(RoomOverview.climateSubtitle(office, read: one) == "71.0")
        #expect(RoomOverview.climateSubtitle(office) { _ in nil } == "4 sensors")
        var single = office
        single.items = [office.items[0]]
        #expect(RoomOverview.climateSubtitle(single) { _ in nil } == "1 sensor")
        #expect(RoomOverview.normalizedRange("unknown") == nil)
        #expect(RoomOverview.normalizedRange(nil) == nil)
        #expect(RoomOverview.normalizedRange("-3.25 to 4") == "-3.2 to 4.0")
    }

    @Test func climateTextAndColors() {
        let sensor = EntityState(entityId: "sensor.demo_x", state: "71.29", attributes: ["unit_of_measurement": .string("°F")])
        #expect(RoomOverview.climateText(sensor) == "71.2°F")
        #expect(RoomOverview.climateText(EntityState(entityId: "sensor.demo_x", state: "unavailable")) == "Unavailable")
        #expect(RoomOverview.climateText(EntityState(entityId: "cover.demo_vent", state: "open")) == "Open")
        let half = EntityState(entityId: "cover.demo_vent", state: "open", attributes: ["current_position": .number(50)])
        #expect(RoomOverview.climateText(half) == "Open · 50%", "One vent rule with Advanced Controls")
        #expect(RoomOverview.climateText(half) == ClimateLogic.ventSubtitle(half))
        #expect(RoomOverview.climateText(EntityState(entityId: "cover.demo_vent", state: "closed")) == "Closed")
        #expect(RoomOverview.climateText(nil) == "Unavailable")
        let fallback = RoomColor(1, 2, 3)
        #expect(RoomOverview.climateColor(EntityState(entityId: "cover.demo_v", state: "open"), colorEntity: nil, fallback: fallback) == RoomColor(30, 136, 229))
        #expect(RoomOverview.climateColor(EntityState(entityId: "cover.demo_v", state: "closed"), colorEntity: nil, fallback: fallback) == RoomColor(128, 128, 128))
        let helper = EntityState(entityId: "input_text.demo_c", state: "rgba(10, 20, 30, 0.5)")
        #expect(RoomOverview.climateColor(sensor, colorEntity: helper, fallback: fallback) == RoomColor(10, 20, 30))
        #expect(RoomOverview.climateColor(EntityState(entityId: "sensor.demo_x", state: "50"), colorEntity: nil, fallback: fallback) == RoomColor(0, 110, 255))
        #expect(RoomOverview.climateColor(nil, colorEntity: nil, fallback: fallback) == fallback)
    }

    @Test func temperatureGradientInterpolates() {
        #expect(RoomOverview.colorFromTemperature(nil) == nil)
        #expect(RoomOverview.colorFromTemperature(20) == RoomColor(0, 110, 255))
        #expect(RoomOverview.colorFromTemperature(99) == RoomColor(255, 0, 0))
        #expect(RoomOverview.colorFromTemperature(71) == RoomColor(128, 208, 60))
    }

    @Test func cssColorsParse() {
        #expect(RoomOverview.colorFromRgba("rgb(1, 2, 3)") == RoomColor(1, 2, 3))
        #expect(RoomOverview.colorFromRgba("blue") == nil)
        #expect(RoomOverview.colorFromRgba(nil) == nil)
        #expect(RoomOverview.colorFromCss("#ff8000") == RoomColor(255, 128, 0))
        #expect(RoomOverview.colorFromCss("RGBA(4, 5, 6, 1)") == RoomColor(4, 5, 6))
        #expect(RoomOverview.colorFromCss("#ff80") == nil)
        #expect(RoomOverview.colorFromCss(nil) == nil)
    }

    // MARK: Colors and details

    @Test func cardColorsUseRoomColors() {
        let read: RoomOverview.Read = { _ in nil }
        #expect(RoomOverview.cardColor(.lights, group(.lights, "Gym"), read: read) == RoomOverview.lightOnColor)
        #expect(RoomOverview.cardColor(.occupancy, group(.occupancy, "Gym"), read: read) == RoomColor(213, 117, 26))
        #expect(RoomOverview.cardColor(.contacts, group(.contacts, "Garage"), read: read) == RoomColor(223, 12, 12))
        #expect(RoomOverview.cardColor(.climate, group(.climate, "Gym"), read: read) == RoomColor(213, 117, 26))
        let tinted = states([("input_text.demo_gym_color_1", "rgb(9, 8, 7)")])
        #expect(RoomOverview.cardColor(.climate, group(.climate, "Gym"), read: tinted) == RoomColor(9, 8, 7))
        let noRoom = RoomGroup("Nowhere", [])
        #expect(RoomOverview.cardColor(.occupancy, noRoom, read: read) == RoomColor(46, 180, 120))
        #expect(RoomOverview.cardColor(.contacts, noRoom, read: read) == RoomColor(220, 92, 68))
        #expect(RoomOverview.cardColor(.climate, noRoom, read: read) == RoomColor(25, 84, 130))
        #expect(RoomOverview.cardColor(.airQuality, noRoom, read: read) == RoomColor(0, 150, 136))
        #expect(RoomOverview.roomIcon("Gym") == "mdi:dumbbell")
    }

    @Test func detailSectionsHeadTheirTiles() {
        #expect(RoomOverview.detailSections(.lights, group(.lights, "Gym")).map(\.title) == ["Light"])
        #expect(RoomOverview.detailSections(.lights, group(.lights, "Kitchen")).map(\.title) == ["Lights"])
        #expect(RoomOverview.detailSections(.climate, group(.climate, "Living Room")).map(\.title) == ["Temperature Sensors", "Vents"])
        #expect(RoomOverview.detailSections(.climate, group(.climate, "Gym")).map(\.title) == ["Temperature Sensors", "Vent"])
        #expect(RoomOverview.detailSections(.climate, group(.climate, "Entryway")).map(\.title) == ["Temperature Sensor"])
        #expect(RoomOverview.detailSections(.occupancy, group(.occupancy, "Gym")).map(\.title) == ["Occupancy Sensor"])
        #expect(RoomOverview.detailSections(.occupancy, group(.occupancy, "Office"), showsHeadings: false).map(\.title) == [nil])
        #expect(RoomOverview.detailSections(.contacts, group(.contacts, "Office")).map(\.title) == ["Contact Sensors"])
        #expect(RoomOverview.detailSections(.contacts, group(.contacts, "Office"), showsHeadings: false).first?.title == nil)
        #expect(RoomOverview.detailSections(.airQuality, group(.contacts, "Office")).isEmpty)
    }

    @Test func multiLightRoomsShowTheirGroupLight() {
        #expect(RoomOverview.groupLightEntityId(group(.lights, "Kitchen")) == "light.demo_kitchen_item_1")
        #expect(RoomOverview.groupLightEntityId(group(.lights, "Gym")) == nil)
        #expect(RoomOverview.groupLightEntityId(RoomGroup("X", entityId: "switch.demo_x", [RoomGroupItem("a", "switch.demo_a"), RoomGroupItem("b", "switch.demo_b")])) == nil)
    }

    @Test func airQualityColorsAndSummary() {
        let room = RoomOverview.airQualityRooms[0]
        #expect(RoomOverview.airQualityColor(room, read: states([(room.colorEntityId, "#00ff00")])) == RoomColor(0, 255, 0))
        #expect(RoomOverview.airQualityColor(room) { _ in nil } == RoomColor(0, 150, 136))
    }
}
