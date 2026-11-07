import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// Batch c of the house-config flip: `ClimateConfig`, `CustomLightsConfig`, the room device configs and
/// `MasterBedroom` read the loaded document and answer empty values without one. Each test scopes its own source.
struct HouseConfigFlipCTests {
    /// The demo house with one value of every flipped kind changed.
    private static func changedHouse() -> HouseConfig {
        var config = DemoHouse.config
        config.climate.globalThermostatEntityId = "climate.demo_global"
        config.climate.hubEntityId = "climate.demo_hub"
        config.climate.trackSelectCriticalOption = "Demo Option"
        config.climate.heatColorHex = 0x112233
        config.climate.rooms = [ClimateConfig.Room("Demo Room")]
        config.climate.contactSensors = [.init(entityId: "binary_sensor.demo_demo", title: "Demo Door")]
        config.customLights.manualControlEntityId = "input_boolean.demo_manual"
        config.customLights.sectionTitle = "Demo Yard"
        config.customLights.fallbackModes = ["Demo Mode"]
        config.customLights.lights = [.init(entityId: "light.demo_demo", title: "Demo Light")]
        config.roomDevices.bathroomFans = [DemoHouse.config.roomDevices.bathroomFans[0]]
        config.roomDevices.airPurifiers = [.init(roomTitle: "Demo", pm25EntityId: "sensor.demo_air_purifier_pm2_5")]
        config.roomDevices.grills = [GrillConfig(title: "Demo Grill", roomTitle: "Demo Deck", stateEntityId: "sensor.demo_grill", details: [])]
        config.bedroom.scheduleEntityId = "sensor.demo_schedule"
        config.bedroom.householdAwayScript = "demo_away"
        config.bedroom.beds = Array(config.bedroom.beds.reversed())
        return config
    }

    private static func scoped(_ house: HouseConfig?, _ body: () -> Void) {
        let source = HouseConfigSource()
        source.set(house)
        HouseConfigSource.$scoped.withValue(source, operation: body)
    }

    @Test func withoutADocumentTheFacadesAreEmpty() {
        Self.scoped(nil) {
            #expect(ClimateConfig.globalThermostatEntityId.isEmpty)
            #expect(ClimateConfig.heatColorHex == 0)
            #expect(ClimateConfig.rooms.isEmpty)
            #expect(ClimateConfig.contactSensors.isEmpty)
            #expect(ClimateConfig.contactSensorsEntityId.isEmpty)
            #expect(CustomLightsConfig.frontYardTitle.isEmpty)
            #expect(CustomLightsConfig.lights.isEmpty)
            #expect(BathroomFanConfig.all.isEmpty)
            #expect(AirPurifierConfig.all.isEmpty)
            #expect(HumidifierConfig.all.isEmpty)
            #expect(GrillConfig.bearGrills.title.isEmpty && GrillConfig.bearGrills.details.isEmpty)
            #expect(MasterBedroom.scheduleEntityId.isEmpty)
            #expect(MasterBedroom.wakeLight == .unconfigured)
            #expect(MasterBedroom.beds.isEmpty)
            #expect(MasterBedroom.bed(.right) == .unconfigured(.right))
        }
    }

    @Test func aLoadedDocumentProvidesEveryFlippedValue() {
        let house = Self.changedHouse()
        Self.scoped(house) {
            #expect(ClimateConfig.globalThermostatEntityId == "climate.demo_global")
            #expect(ClimateConfig.hubEntityId == "climate.demo_hub")
            #expect(ClimateController.hubModeKey == "climate.demo_hub#hvac_mode")
            #expect(ClimateConfig.trackSelectCriticalOption == "Demo Option")
            #expect(ClimateConfig.heatColorHex == 0x112233)
            #expect(ClimateConfig.rooms == house.climate.rooms)
            #expect(ClimateConfig.roomClimateEntityIds == ["climate.thermostat_contact_sensors_demo_room_virtual_thermostat"])
            #expect(ClimateConfig.contactSensors == house.climate.contactSensors)
            #expect(CustomLightsConfig.manualControlEntityId == "input_boolean.demo_manual")
            #expect(CustomLightsConfig.frontYardTitle == "Demo Yard")
            #expect(CustomLightsConfig.modes(nil) == ["Demo Mode"])
            #expect(CustomLightsConfig.lights == house.customLights.lights)
            #expect(BathroomFanConfig.all == house.roomDevices.bathroomFans)
            #expect(AirPurifierConfig.all == house.roomDevices.airPurifiers)
            #expect(GrillConfig.bearGrills.title == "Demo Grill")
            #expect(MasterBedroom.scheduleEntityId == "sensor.demo_schedule")
            #expect(MasterBedroom.householdAwayScript == "demo_away")
            #expect(MasterBedroom.beds == house.bedroom.beds)
            #expect(MasterBedroom.bed(.left).side == .left)
            #expect(MasterBedroom.bed(id: house.bedroom.beds[0].id) == house.bedroom.beds[0])
        }
    }

    @Test func aDocumentWithEmptyListsKeepsTheScreensWorking() {
        var house = DemoHouse.config
        let removedBedId = house.bedroom.beds[0].id
        house.bedroom.beds = []
        house.roomDevices.grills = []
        house.customLights.lights = []
        house.customLights.fallbackModes = []
        Self.scoped(house) {
            #expect(MasterBedroom.beds.isEmpty)
            #expect(MasterBedroom.bed(.left) == .unconfigured(.left))
            #expect(MasterBedroom.bed(id: removedBedId) == nil)
            #expect(GrillConfig.bearGrills.title.isEmpty)
            #expect(CustomLightsConfig.lights.isEmpty)
            #expect(CustomLightsConfig.modes(nil).isEmpty)
        }
    }

    @Test func theSecurityContactSensorReadsThroughItsFacade() {
        var house = DemoHouse.config
        house.security.contactSensorsEntityId = "binary_sensor.demo_contacts"
        Self.scoped(house) {
            #expect(ClimateConfig.contactSensorsEntityId == "binary_sensor.demo_contacts")
        }
    }
}
