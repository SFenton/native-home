import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// Batch b of the house-config flip: the rooms facades (`RoomGroups`, `RoomsConfig`, `RoomNavigation`, `RoomOverview`,
/// `QuickLinks`) read the loaded document and answer empty values without one. Each test scopes its own source.
@MainActor
struct HouseConfigRoomsFacadeTests {
    /// The demo house with every flipped rooms value changed.
    private static func changedHouse() -> HouseConfig {
        var config = DemoHouse.config
        config.rooms.lightGroups = [RoomGroup("Demo Room", entityId: "light.demo_demo", [RoomGroupItem("Lamp", "light.demo_lamp")])]
        config.rooms.climateGroups = [RoomGroup("Demo Room", entityId: "input_text.demo_range", [RoomGroupItem("Probe", "sensor.demo_t")])]
        config.rooms.occupancyGroups = [RoomGroup("Demo Room", [RoomGroupItem("Presence", "binary_sensor.demo_presence")])]
        config.rooms.contactGroups = [RoomGroup("Demo Room", [RoomGroupItem("Door", "binary_sensor.demo_door")])]
        config.rooms.airQualityRooms = [AirQualityRoom(title: "Demo", aqiEntityId: "sensor.demo_aqi", colorEntityId: "input_text.demo_aqi_color", pm25EntityId: "sensor.demo_pm")]
        config.rooms.pages = Array(config.rooms.pages.prefix(2))
        config.rooms.shared.wakeLightPage = HouseConfig.WakeLightPage(sheet: "demo-sheet", title: "Demo Alarms", sectionTitle: "Demo Section")
        config.rooms.shared.dishwasherProgramEntityId = "select.demo_dishwasher"
        config.rooms.grid.accessIncrementScript = "script.demo_access"
        config.rooms.grid.items = Array(config.rooms.grid.items.prefix(3))
        config.rooms.quickLinks = Array(config.rooms.quickLinks.prefix(2))
        return config
    }

    @Test func withoutADocumentEveryFlippedValueIsEmpty() {
        HouseConfigSource.$scoped.withValue(HouseConfigSource()) {
            #expect(RoomGroups.allLights.isEmpty)
            #expect(RoomGroups.allClimate.isEmpty)
            #expect(RoomGroups.allOccupancy.isEmpty)
            #expect(RoomGroups.allContacts.isEmpty)
            #expect(RoomGroups.lights(room: "Gym") == nil)
            #expect(RoomOverview.airQualityRooms.isEmpty)
            #expect(RoomOverview.lightEntityIds.isEmpty)
            #expect(RoomsConfig.pages.isEmpty)
            #expect(RoomsConfig.page(id: "gym") == nil)
            #expect(RoomsConfig.WakeLight.title.isEmpty)
            #expect(RoomsConfig.dishwasherProgramEntityId.isEmpty)
            #expect(RoomNavigation.items.isEmpty)
            #expect(RoomNavigation.accessIncrementScript.isEmpty)
            #expect(QuickLinks.items.isEmpty)
        }
    }

    @Test func theDemoHouseProvidesTheRooms() {
        HouseConfigSource.$scoped.withValue(DemoHouse.source) {
            #expect(RoomGroups.lights(room: "Gym")?.entityId == "light.demo_gym_light_item_1")
            #expect(RoomOverview.lightEntityIds.contains("light.demo_gym_light_item_1"))
            #expect(RoomsConfig.page(id: "gym")?.id == "gym")
            #expect(RoomsConfig.dishwasherProgramEntityId == "select.demo_program_1")
            #expect(!RoomNavigation.items.isEmpty && !QuickLinks.items.isEmpty)
        }
    }

    @Test func aLoadedDocumentProvidesEveryFlippedValue() {
        let source = HouseConfigSource()
        source.set(Self.changedHouse())
        HouseConfigSource.$scoped.withValue(source) {
            #expect(RoomGroups.allLights.map(\.room) == ["Demo Room"])
            #expect(RoomGroups.lights(room: "Demo Room")?.entityId == "light.demo_demo")
            #expect(RoomGroups.lights(room: "Gym") == nil)
            #expect(RoomGroups.climate(room: "Demo Room")?.items.first?.entityId == "sensor.demo_t")
            #expect(RoomGroups.occupancy(room: "Demo Room")?.items.first?.entityId == "binary_sensor.demo_presence")
            #expect(RoomGroups.contacts(room: "Demo Room")?.items.first?.entityId == "binary_sensor.demo_door")
            #expect(RoomOverview.groups(.lights).map(\.room) == ["Demo Room"])
            #expect(RoomOverview.lightEntityIds == ["light.demo_lamp"])
            #expect(RoomOverview.contactEntityIds == ["binary_sensor.demo_door"])
            #expect(RoomOverview.airQualityRooms.map(\.pm25EntityId) == ["sensor.demo_pm"])
            #expect(RoomsConfig.pages.count == 2)
            #expect(RoomsConfig.page(id: "gym") == nil)
            #expect(RoomsConfig.page(id: "living-room") != nil)
            #expect(RoomsConfig.WakeLight.sheet == "demo-sheet")
            #expect(RoomsConfig.WakeLight.title == "Demo Alarms")
            #expect(RoomsConfig.WakeLight.sectionTitle == "Demo Section")
            #expect(RoomsConfig.dishwasherProgramEntityId == "select.demo_dishwasher")
            #expect(RoomNavigation.accessIncrementScript == "script.demo_access")
            #expect(RoomNavigation.items.count == 3)
            #expect(RoomNavigation.item(for: RoomNavigation.items.first?.path ?? "") != nil)
            #expect(RoomNavigation.ranked { _ in nil }.count == 3)
            #expect(QuickLinks.items.count == 2)
            #expect(QuickLinks.visible { _ in nil }.count == 2)
        }
    }

    @Test func emptyServerListsAreServedAsEmptyWithoutCrashing() {
        var config = DemoHouse.config
        config.rooms.lightGroups = []
        config.rooms.contactGroups = []
        config.rooms.pages = []
        config.rooms.grid.items = []
        config.rooms.quickLinks = []
        let source = HouseConfigSource()
        source.set(config)
        HouseConfigSource.$scoped.withValue(source) {
            #expect(RoomOverview.lightEntityIds.isEmpty)
            #expect(RoomOverview.contactEntityIds.isEmpty)
            #expect(RoomsConfig.page(id: "gym") == nil)
            #expect(RoomNavigation.ranked { _ in nil }.isEmpty)
            #expect(QuickLinks.visible { _ in nil }.isEmpty)
        }
    }
}
