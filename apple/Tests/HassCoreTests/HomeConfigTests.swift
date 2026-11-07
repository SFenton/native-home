@testable import HassCore
import HassTestSupport
import Testing

@Suite(.demoHouse)
struct HomeConfigTests {
    private func chip(_ sheet: HomeConfig.ChipSheet) -> HomeConfig.StatusChip {
        HomeConfig.statusChips.first { $0.sheet == sheet }!
    }

    /// Lights count each room light once (web `ROOM_LIGHT_ENTITY_IDS`), not the room groups.
    @Test func lightsSummaryCountsLightsOn() {
        let states: [String: EntityState] = [
            "light.demo_light_1": EntityState(entityId: "light.demo_light_1", state: "on"),
            "light.demo_kitchen_item_1": EntityState(entityId: "light.demo_kitchen_item_1", state: "on"),
            "light.demo_kitchen_light_1": EntityState(entityId: "light.demo_kitchen_light_1", state: "on"),
            "light.demo_kitchen_light_3": EntityState(entityId: "light.demo_kitchen_light_3", state: "on"),
            "light.demo_bedroom_1_light_2": EntityState(entityId: "light.demo_bedroom_1_light_2", state: "on"),
            "light.demo_gym_light_item_1": EntityState(entityId: "light.demo_gym_light_item_1", state: "off"),
        ]
        #expect(HomeConfig.summary(for: chip(.lights)) { states[$0] } == "3 On")
        #expect(HomeConfig.summary(for: chip(.lights)) { _ in nil } == "All Off")
    }

    /// Contact Sensors counts the rooms' sensors (web `ROOM_CONTACT_ENTITY_IDS`).
    @Test func contactsSummaryCountsOpenSensors() {
        let states: [String: EntityState] = [
            "binary_sensor.demo_front_door_contact_1": EntityState(entityId: "binary_sensor.demo_front_door_contact_1", state: "on"),
            "binary_sensor.demo_gym_contact_1": EntityState(entityId: "binary_sensor.demo_gym_contact_1", state: "off"),
        ]
        #expect(HomeConfig.summary(for: chip(.contacts)) { states[$0] } == "1 Open")
        #expect(HomeConfig.summary(for: chip(.contacts)) { _ in nil } == "All Closed")
    }

    @Test func occupancyReadsDetectedOrClear() {
        let id = chip(.occupancy).entityId
        #expect(HomeConfig.summary(for: chip(.occupancy)) { [id: EntityState(entityId: id, state: "on")][$0] } == "Detected")
        #expect(HomeConfig.summary(for: chip(.occupancy)) { [id: EntityState(entityId: id, state: "off")][$0] } == "Clear")
    }

    @Test func airQualityJoinsRanges() {
        // The summary reads the chip's own ranges, so the test keys on the chip and not on a literal id.
        let air = chip(.airQuality)
        let aqiId = air.entityId, pm25Id = air.detailEntityId ?? ""
        func read(_ id: String) -> EntityState? {
            if id == aqiId { return EntityState(entityId: id, state: "12 - 30") }
            if id == pm25Id { return EntityState(entityId: id, state: "1 - 4") }
            return nil
        }
        #expect(!pm25Id.isEmpty && aqiId != pm25Id)
        #expect(HomeConfig.summary(for: air) { read($0) } == "AQI 12 - 30 · PM2.5 1 - 4")
        #expect(HomeConfig.summary(for: chip(.airQuality)) { _ in nil } == "AQI Unavailable · PM2.5 Unavailable")
    }

    @Test func climateShowsItsText() {
        let id = chip(.climate).entityId
        #expect(HomeConfig.summary(for: chip(.climate)) { [id: EntityState(entityId: id, state: "68 - 72°F")][$0] } == "68 - 72°F")
    }

    /// Six chips in web order; every chip but Security opens a room overview.
    @Test func chipsMatchTheWebRail() {
        #expect(HomeConfig.statusChips.map(\.title) == ["Lights", "Security", "Climate", "Occupancy", "Contact Sensors", "Air Quality"])
        #expect(HomeConfig.ChipSheet.allCases.filter { $0.overview == nil } == [.security])
        #expect(chip(.airQuality).colorEntityId == "input_text.demo_color_2")
    }

    @Test func unavailableChip() {
        #expect(HomeConfig.summary(for: chip(.security)) { _ in nil } == "Unavailable")
    }

    @Test func securitySummaryIsReadable() {
        let id = chip(.security).entityId
        let states = [id: EntityState(entityId: id, state: "armed_away")]
        #expect(HomeConfig.summary(for: chip(.security)) { states[$0] } == "Armed Away")
    }
}
