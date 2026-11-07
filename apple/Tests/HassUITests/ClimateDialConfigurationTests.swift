import Foundation
import HassCore
import HassDesign
@testable import HassUI
import Testing

/// How the Climate dial reads a `climate` entity, the way the web's `ThermostatDial` does.
struct ClimateDialConfigurationTests {
    private func climate(_ state: String = "heat", _ attributes: [String: JSONValue] = [:]) -> EntityState {
        EntityState(entityId: "climate.demo_living_room", state: state, attributes: attributes)
    }

    @Test func aHeatCoolThermostatGetsTwoHandles() {
        let dial = ThermostatDialConfiguration(entity: climate("heat_cool", [
            "target_temp_low": .number(66), "target_temp_high": .number(72), "current_temperature": .number(68.5),
            "min_temp": .number(50), "max_temp": .number(90), "target_temp_step": .number(1), "hvac_action": .string("cooling"),
            "temperature_unit": .string("°C"),
        ]), title: "Living Room")
        #expect(dial.targets == .range(low: 66, high: 72))
        #expect(dial.title == "Living Room")
        #expect(dial.min == 50 && dial.max == 90 && dial.step == 1)
        #expect(dial.current == 68.5)
        #expect(dial.action == "cooling" && dial.unit == "°C")
        #expect(!dial.isUnavailable && !dial.isOff)
    }

    @Test func aSingleSetpointGetsOneHandleAndTheWebsDefaults() {
        let dial = ThermostatDialConfiguration(entity: climate("heat", ["temperature": .number(70)]), title: "Hall")
        #expect(dial.targets == .single(70))
        #expect(dial.min == 45 && dial.max == 95 && dial.step == 0.5, "the web's defaults")
        #expect(dial.unit == "°F")
        #expect(dial.action == "heat", "the state stands in for a missing hvac_action")
        #expect(dial.current == nil)
    }

    @Test func halfARangeIsNotARangeAndTheUnitFallsBackToTheEntitysOwn() {
        let dial = ThermostatDialConfiguration(entity: climate("cool", [
            "target_temp_low": .number(66), "temperature": .number(71), "unit_of_measurement": .string("°C"),
        ]), title: "Den")
        #expect(dial.targets == .single(71), "a range needs both ends")
        #expect(dial.unit == "°C")
        let none = ThermostatDialConfiguration(entity: climate("cool"), title: "Den")
        #expect(none.targets == nil)
    }

    @Test func anOffThermostatIsOffAndAnUnknownOneIsUnavailable() {
        let off = ThermostatDialConfiguration(entity: climate("off", ["temperature": .number(70)]), title: "Hall")
        #expect(off.isOff && !off.isUnavailable)
        let unavailable = ThermostatDialConfiguration(entity: climate("unavailable"), title: "Hall")
        #expect(unavailable.isUnavailable)
        let missing = ThermostatDialConfiguration(entity: nil, title: "Hall")
        #expect(missing.isUnavailable && !missing.isOff)
        #expect(missing.action == "idle")
        #expect(missing.targets == nil)
    }

    @Test func aRejectedSetpointNamesWhatFailedAndTheServiceDataTargetsOneOrManyEntities() {
        #expect(ThermostatTargets.single(68).failureMessage == "Couldn't set 68°. Check the connection.")
        #expect(ThermostatTargets.single(68.5).failureMessage == "Couldn't set 68.5°. Check the connection.")
        #expect(ThermostatTargets.range(low: 66, high: 72.5).failureMessage == "Couldn't set 66° to 72.5°. Check the connection.")
        let one = ThermostatTargets.single(70).setTemperatureData(entityIds: ["climate.demo_a"])
        #expect(one["entity_id"] as? String == "climate.demo_a" && one["temperature"] as? Double == 70)
        let many = ThermostatTargets.range(low: 66, high: 72).setTemperatureData(entityIds: ["climate.demo_a", "climate.demo_b"])
        #expect(many["entity_id"] as? [String] == ["climate.demo_a", "climate.demo_b"])
        #expect(many["target_temp_low"] as? Double == 66 && many["target_temp_high"] as? Double == 72)
    }
}
