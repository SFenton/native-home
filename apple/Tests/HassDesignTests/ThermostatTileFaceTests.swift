@testable import HassDesign
import Testing

struct ThermostatTileFaceTests {
    @Test func heatingAndCoolingFillWhatTheModeSays() {
        for mode in ["heat", "cool", "heat_cool", "off", nil] {
            #expect(ThermostatTileFace.thermostat(action: "heating", mode: mode) == .init(family: .heating, isActive: true))
            #expect(ThermostatTileFace.thermostat(action: "cooling", mode: mode) == .init(family: .cooling, isActive: true))
        }
    }

    @Test func idleThermostatsKeepAFamilyGlyph() {
        // Heat mode draws the Heating glyph on the dark face; every other mode draws Cooling.
        #expect(ThermostatTileFace.thermostat(action: "idle", mode: "heat") == .init(family: .heating, isActive: false))
        #expect(ThermostatTileFace.thermostat(action: "off", mode: "heat") == .init(family: .heating, isActive: false))
        #expect(ThermostatTileFace.thermostat(action: "none", mode: "heat") == .init(family: .heating, isActive: false))
        #expect(ThermostatTileFace.thermostat(action: "idle", mode: "heat_cool") == .init(family: .cooling, isActive: false))
        #expect(ThermostatTileFace.thermostat(action: "idle", mode: "cool") == .init(family: .cooling, isActive: false))
        #expect(ThermostatTileFace.thermostat(action: "off", mode: "off") == .init(family: .cooling, isActive: false))
        #expect(ThermostatTileFace.thermostat(action: "idle", mode: nil) == .init(family: .cooling, isActive: false))
    }

    @Test func bedSidesFillWhileHeatingOrCooling() {
        #expect(ThermostatTileFace.bedSide(action: "heating", level: 3) == .init(family: .heating, isActive: true))
        #expect(ThermostatTileFace.bedSide(action: "cooling", level: -3) == .init(family: .cooling, isActive: true))
    }

    @Test func bedSidesThatAreOnFillWithTheirLevelsFamily() {
        // On near zero ("idle") still fills: Heating at or above zero, Cooling below.
        #expect(ThermostatTileFace.bedSide(action: "idle", level: 0) == .init(family: .heating, isActive: true))
        #expect(ThermostatTileFace.bedSide(action: "idle", level: -0.5) == .init(family: .cooling, isActive: true))
        #expect(ThermostatTileFace.bedSide(action: "idle", level: nil) == .init(family: .heating, isActive: true))
    }

    @Test func offBedSidesDrawTheirLevelsFamilyOnTheDarkFace() {
        #expect(ThermostatTileFace.bedSide(action: "off", level: 4) == .init(family: .heating, isActive: false))
        #expect(ThermostatTileFace.bedSide(action: "off", level: -4) == .init(family: .cooling, isActive: false))
        #expect(ThermostatTileFace.bedSide(action: "off", level: nil) == .init(family: .heating, isActive: false))
    }

    @Test func unavailableBedSidesStayNeutral() {
        #expect(ThermostatTileFace.bedSide(action: "heating", level: 5, isAvailable: false) == .init(family: .neutral, isActive: false))
        #expect(ThermostatTileFace.bedSide(action: "off", level: -5, isAvailable: false) == .init(family: .neutral, isActive: false))
    }
}
