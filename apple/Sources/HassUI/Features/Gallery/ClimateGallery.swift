#if DEBUG
import HassCore
import HassDesign
import SwiftUI

/// Gallery page for Climate: the real page on fixture state with a recording service caller, so journeys tap
/// toggles without touching the house. `FENTON_GALLERY_CLIMATE_SCENARIO=away` loads the away fixture;
/// `FENTON_GALLERY_CLIMATE_OPEN=<tab>` or `=<route>` (`room:living_room`, `predictive`, `eco-critical`,
/// `selected-rooms`…) opens the sheet at launch.
struct ClimateGallery {
    /// A tab name or a route token.
    static func request(token: String) -> ClimateSheetRequest? {
        if let tab = ClimateConfig.Tab(rawValue: token) { return ClimateSheetRequest(tab: tab) }
        return ClimateRoute(token: token).map { ClimateSheetRequest(tab: $0.tab, route: $0) }
    }
}

/// Synthetic Climate states for the gallery and hosted tests, shaped like the live house (not a copy of it).
enum ClimateFixtures {
    enum Scenario: String {
        /// Someone is home, an office window is open, Predictive Comfort and selected-room tracking are on.
        case home
        /// Everyone is away on vacation, Automatic Thermostat is off, nothing is open.
        case away
    }

    @MainActor static func store(scenario: Scenario = .home) -> EntityStore {
        let store = EntityStore()
        store.replaceAll(states(scenario), freshness: .live)
        return store
    }

    static func states(_ scenario: Scenario) -> [EntityState] {
        typealias C = ClimateConfig
        let away = scenario == .away
        func entity(_ id: String, _ state: String, _ attributes: [String: JSONValue] = [:]) -> EntityState {
            EntityState(entityId: id, state: state, attributes: attributes)
        }
        func strings(_ values: [String]) -> JSONValue { .array(values.map(JSONValue.string)) }
        func range(_ low: Double, _ high: Double, current: Double, action: String, extra: [String: JSONValue] = [:]) -> [String: JSONValue] {
            ["min_temp": .number(45), "max_temp": .number(95), "target_temp_step": .number(0.5),
             "current_temperature": .number(current), "target_temp_low": .number(low), "target_temp_high": .number(high),
             "hvac_action": .string(action)].merging(extra) { _, new in new }
        }
        var states: [EntityState] = [
            entity(C.globalThermostatEntityId, "heat_cool", range(71, 74, current: 72, action: away ? "idle" : "heating")),
            entity(C.ecoAwayThermostatEntityId, "heat_cool", range(62, 78, current: 72, action: "idle")),
            entity(C.hubEntityId, away ? "off" : "heat", [
                "hvac_modes": strings(["off", "heat", "cool", "heat_cool"]), "fan_modes": strings(["auto", "on"]),
                "fan_mode": .string("auto"), "current_temperature": .number(73), "temperature": .number(72),
                "hvac_action": .string(away ? "idle" : "heating"),
            ]),
            entity(C.homeAwayEntityId, away ? "Away" : "Home"),
            entity(C.homeAwayReasonEntityId, away ? "Everyone is away." : "A resident is home, so TCS is using home behavior."),
            entity(C.awayModeEntityId, away ? "on" : "off"),
            entity(C.vacationModeEntityId, away ? "on" : "off"),
            entity(C.integrationEntityId, away ? "off" : "on"),
            entity(C.contactSensorsEntityId, away ? "off" : "on"),
            entity(C.ecoModeEntityId, "on"),
            entity(C.ecoCriticalEntityId, "Track Select Critical", ["options": strings(["Do Not Track Critical", "Track Select Critical", "Track All Critical"])]),
            entity(C.ecoAwayEntityId, "Keep Eco Active", ["options": strings(["Disable Eco When Away", "Use Eco Away Targets", "Keep Eco Active"])]),
            entity(C.predictiveComfortEntityId, away ? "off" : "on", ["current_recommendation": .string("pre_cool")]),
            entity(C.predictiveAutoAdjustEntityId, "on"),
            entity(C.predictiveHvacModeChangesEntityId, "on"),
            entity(C.predictiveAllowAwayEntityId, "off"),
            entity(C.predictiveSensorEntityId, "pre_cool", [
                "reason": .string("Predicted indoor temperature rises above comfort band"),
                "comfort_low": .number(71), "comfort_high": .number(74), "indoor_temperature": .number(72.4),
                "predicted_temperature": .number(75.1), "forecast_high": .number(88), "forecast_low": .number(64),
                "weather_entity": .string("weather.demo_weather_1"),
                "active_activity_entities": strings(["binary_sensor.demo_pc_power"]), "adjustment_status": .string("applied"),
            ]),
            entity(C.trackSelectedEntityId, away ? "off" : "on"),
        ]
        for sensor in C.contactSensors {
            states.append(entity(sensor.entityId, !away && sensor.title == "Office Window" ? "on" : "off"))
        }
        let temperatures = [70.9, 76.1, 72.3, 73.3, 69.9, 71.4, 68.8, 71.6, 75.4, 71.7, 72.1]
        let tracked: Set<String> = ["living_room", "office", "master_bedroom"]
        for (index, room) in C.rooms.enumerated() {
            let occupied = !away && index < 3
            states.append(entity(room.climateEntityId, "heat_cool", range(71, 74, current: temperatures[index].rounded(), action: "idle",
                                                                          extra: ["away_mode_active": .bool(away)])))
            states.append(entity(room.temperatureEntityId, String(temperatures[index]), ["unit_of_measurement": .string("°F")]))
            states.append(entity(room.occupancyEntityId, occupied ? (index == 0 ? "occupied" : "active") : "inactive"))
            states.append(entity(room.trackEntityId, tracked.contains(room.key) ? "on" : "off"))
            states.append(entity(room.forceCriticalEntityId, room.key == "guest_room" ? "on" : "off"))
            states.append(entity(room.occupiedOnlyEntityId, ["master_bathroom", "guest_bathroom"].contains(room.key) ? "on" : "off"))
            for (ventIndex, vent) in room.ventEntityIds.enumerated() {
                let closed = room.key == "office" || (room.key == "dining_room" && ventIndex == 0)
                // Open vents report a position (the second living-room vent is half open), so the tiles show it.
                states.append(entity(vent, closed ? "closed" : "open",
                                     ["current_position": .number(closed ? 0 : (room.key == "living_room" && ventIndex == 1 ? 50 : 100))]))
            }
        }
        return states
    }
}
#endif
