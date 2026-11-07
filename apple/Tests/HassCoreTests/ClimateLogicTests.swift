import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// Climate page rules against the web `ThermostatPage` (`ha-sfenton-react-dash@9ac2a46:src/pages/DashboardViewPage.tsx`).
@Suite(.demoHouse)
struct ClimateLogicTests {
    typealias C = ClimateConfig

    func lookup(_ states: [String: String], attributes: [String: [String: JSONValue]] = [:]) -> EntityLookup {
        { id in states[id].map { EntityState(entityId: id, state: $0, attributes: attributes[id] ?? [:]) } }
    }

    // MARK: Config

    @Test func roomsMatchTheWebList() {
        // The demo rooms: compared with each other, not with the house's literals.
        #expect(C.rooms.count == 11)
        let living = C.rooms[0]
        #expect(C.room(key: living.key)?.climateEntityId == living.climateEntityId)
        #expect(living.ventEntityIds.count == 2)
        #expect(living.ventTitle(at: 1) == "Vent 2")
        #expect(living.ventSectionTitle.hasSuffix("Vents"))
        #expect(Set([living.temperatureEntityId, living.occupancyEntityId, living.trackEntityId,
                     living.forceCriticalEntityId, living.occupiedOnlyEntityId]).count == 5)
        let single = C.rooms.first { $0.ventEntityIds.count == 1 }
        #expect(single?.ventSectionTitle.hasSuffix("Vent") == true)
        #expect(single?.ventTitle(at: 0) == "Vent")
        #expect(C.room(key: "attic") == nil)
        #expect(C.roomClimateEntityIds.count == 11)
        #expect(C.toggleEntityIds.count == 7 + 33)
    }

    @Test func tabsAndPagesCarryTheWebCopy() {
        #expect(C.Tab.allCases.map(\.title) == ["Rooms", "Automation", "Tracking"])
        #expect(C.Tab.allCases.map(\.entryTitle) == ["Room Thermostats", "Advanced Configuration", "Room Tracking"])
        #expect(C.Tab.allCases.map(\.icon) == ["mdi:home-thermometer", "mdi:cog", "mdi:motion-sensor"])
        #expect(C.Tab.rooms.description.hasPrefix("View each room's temperature and occupancy"))
        #expect(C.Tab.automation.description == "Manage Automatic Thermostat, Eco Mode, and Predictive Comfort settings.")
        #expect(C.Tab.tracking.description.hasPrefix("Choose which rooms participate"))
        #expect(C.EcoOption.critical.entityId == C.ecoCriticalEntityId)
        #expect(C.EcoOption.away.entityId == C.ecoAwayEntityId)
        #expect(C.EcoOption.allCases.map(\.title) == ["Eco Mode Critical Tracking", "Eco Behavior When Away"])
        #expect(C.EcoOption.allCases.map(\.icon) == ["mdi:thermometer-alert", "mdi:leaf-circle"])
        #expect(C.EcoOption.critical.openerDescription.contains("unsafe temperatures"))
        #expect(C.EcoOption.away.openerDescription.contains("everyone leaves"))
        #expect(C.EcoOption.critical.pageDescription.contains("not participating"))
        #expect(C.EcoOption.away.pageDescription == "Choose what Eco Mode should do when everyone is away.")
        #expect(C.EcoOption.away.unavailableMessage == "Eco Behavior When Away is unavailable until Home Assistant supplies supported options.")
        let room = C.rooms[0]
        #expect(C.TrackingPage.allCases.map(\.title) == ["Selected Rooms", "Critical Protection", "Occupied Only"])
        #expect(C.TrackingPage.allCases.map(\.icon) == ["mdi:home-check", "mdi:thermometer-alert", "mdi:motion-sensor"])
        #expect(C.TrackingPage.allCases.map { $0.entityId(for: room) } == [room.trackEntityId, room.forceCriticalEntityId, room.occupiedOnlyEntityId])
        #expect(C.TrackingPage.allCases.map(\.openerDescription) == [C.Copy.selectedRoomsOpener, C.Copy.forceCritical, C.Copy.trackOnlyWhenOccupied])
        #expect(C.TrackingPage.allCases.map(\.pageDescription) == [C.Copy.trackSelected, C.Copy.forceCritical, C.Copy.trackOnlyWhenOccupied])
        #expect(C.contactSensors.count == 12)
        #expect(C.contactSensors.filter(\.isWindow).count == 6)
    }

    // MARK: Formatting

    @Test func formatting() {
        #expect(StateText.titleCase("heat_cool") == "Heat Cool")
        #expect(StateText.titleCase(nil) == "Unknown")
        #expect(StateText.titleCase("") == "Unknown")
        #expect(ClimateLogic.compactState(nil) == "Unavailable")
        #expect(ClimateLogic.compactState(EntityState(entityId: "switch.demo_x", state: "unavailable")) == "Unavailable")
        #expect(ClimateLogic.compactState(EntityState(entityId: "switch.demo_x", state: "on"), state: "off") == "Off")
        #expect(ClimateLogic.compactState(EntityState(entityId: "binary_sensor.contact_test_demo", state: "on")) == "Open")
        #expect(ClimateLogic.compactState(EntityState(entityId: "binary_sensor.contact_test_x", state: "off")) == "Closed")
        #expect(ClimateLogic.compactState(EntityState(entityId: "binary_sensor.demo_motion", state: "on")) == "Active")
        #expect(ClimateLogic.compactState(EntityState(entityId: "binary_sensor.demo_motion", state: "off")) == "Clear")
        #expect(ClimateLogic.compactState(EntityState(entityId: "light.demo_x", state: "on")) == "On")
        #expect(ClimateLogic.compactState(EntityState(entityId: "light.demo_x", state: "off")) == "Off")
        #expect(ClimateLogic.compactState(EntityState(entityId: "sensor.demo_x", state: "Home")) == "Home")
        #expect(ClimateLogic.compactState(EntityState(entityId: "input_text.demo_x", state: "raw_text")) == "raw_text")
        #expect(ClimateLogic.compactState(EntityState(entityId: "climate.demo_x", state: "heat_cool")) == "Heat Cool")
        #expect(ClimateLogic.selectOption("") == "Unknown")
        #expect(ClimateLogic.selectOption("Keep Eco Active") == "Keep Eco Active")
        #expect(ClimateLogic.selectOption("fan_only") == "Fan Only")
        #expect(ClimateLogic.predictiveState(.string("pre_cool")) == "Pre-Cool")
        #expect(ClimateLogic.predictiveState(.string("Pre Cool")) == "Pre-Cool")
        #expect(ClimateLogic.predictiveState(.string("rate_limited")) == "Rate Limited")
        #expect(ClimateLogic.predictiveState(nil) == "Unknown")
        #expect(ClimateLogic.predictiveState(.number(3)) == "Unknown")
        #expect(ClimateLogic.number(.number(2.5)) == 2.5)
        #expect(ClimateLogic.number(.number(.infinity)) == nil)
        #expect(ClimateLogic.number(.string(" ")) == nil)
        #expect(ClimateLogic.number(.string("70.9")) == 70.9)
        #expect(ClimateLogic.number(.string("abc")) == nil)
        #expect(ClimateLogic.number(.bool(true)) == nil)
        #expect(ClimateLogic.temperature(72) == "72.0°F")
        #expect(ClimateLogic.temperature(nil, unit: "°C") == "--°C")
        #expect(ClimateLogic.unit(of: EntityState(entityId: "climate.demo_x", state: "off", attributes: ["temperature_unit": .string("°C")])) == "°C")
        #expect(ClimateLogic.unit(of: EntityState(entityId: "sensor.demo_x", state: "1", attributes: ["unit_of_measurement": .string("K")])) == "K")
        #expect(ClimateLogic.unit(of: nil) == "°F")
        #expect(ClimateLogic.sentence(" ") == "")
        #expect(ClimateLogic.sentence("Done!") == "Done!")
        #expect(ClimateLogic.entityLabel("binary_sensor.demo_office_pc_power") == "Demo Office PC Power")
        #expect(ClimateLogic.entityLabel("plain_name") == "Plain Name")
        #expect(ClimateLogic.entityLabel(nil) == "Unknown")
    }

    // MARK: Effective away

    @Test func effectiveAwayFollowsTheHomeAwaySensorThenTheAwayModeFallback() {
        #expect(!ClimateLogic.isEffectivelyAway(lookup([C.homeAwayEntityId: "Home", C.awayModeEntityId: "on"])))
        #expect(ClimateLogic.isEffectivelyAway(lookup([C.homeAwayEntityId: "Away", C.awayModeEntityId: "off"])))
        #expect(ClimateLogic.isEffectivelyAway(lookup([C.homeAwayEntityId: "unknown", C.awayModeEntityId: "on"])))
        #expect(ClimateLogic.isEffectivelyAway(lookup([C.homeAwayEntityId: "unavailable", C.awayModeEntityId: "on"])))
        #expect(ClimateLogic.isEffectivelyAway(lookup([C.awayModeEntityId: "on"])), "A missing sensor reads Unavailable")
        #expect(!ClimateLogic.isEffectivelyAway(lookup([C.homeAwayEntityId: "unknown", C.awayModeEntityId: "off"])))
        #expect(ClimateLogic.wholeHomeDialEntityId(lookup([C.homeAwayEntityId: "Away"])) == C.ecoAwayThermostatEntityId)
        #expect(ClimateLogic.wholeHomeDialEntityId(lookup([C.homeAwayEntityId: "Home"])) == C.globalThermostatEntityId)
    }

    @Test func hvacActionFallsBackToStateThenIdle() {
        #expect(ClimateLogic.hvacAction(EntityState(entityId: "climate.demo_x", state: "heat", attributes: ["hvac_action": .string("heating")])) == "heating")
        #expect(ClimateLogic.hvacAction(EntityState(entityId: "climate.demo_x", state: "cool")) == "cool")
        #expect(ClimateLogic.hvacAction(nil) == "idle")
    }

    @Test func awayNoticeCopy() {
        let reason = "A resident is home."
        let home = lookup([C.homeAwayEntityId: "Home", C.homeAwayReasonEntityId: reason, C.awayModeEntityId: "off"])
        #expect(ClimateLogic.awayNotice(climateEntityId: C.globalThermostatEntityId, useEffectiveMode: true, home) == nil)
        let away = lookup([C.homeAwayEntityId: "Away", C.awayModeEntityId: "off"])
        #expect(ClimateLogic.awayNotice(climateEntityId: C.globalThermostatEntityId, useEffectiveMode: true, away)
            == "Away Mode Active. The room may be cooler or warmer than your heat/cool targets to save energy while away.")
        let vacation = lookup([C.homeAwayEntityId: "Away", C.vacationModeEntityId: "on"])
        #expect(ClimateLogic.awayNotice(climateEntityId: C.globalThermostatEntityId, useEffectiveMode: true, vacation)?.hasPrefix("Vacation Mode Active.") == true)
        // Unknown and not away: the mode and the fallback reason.
        let unknown = lookup([C.homeAwayEntityId: "unknown", C.homeAwayReasonEntityId: "unavailable", C.awayModeEntityId: "off"])
        #expect(ClimateLogic.awayNotice(climateEntityId: C.globalThermostatEntityId, useEffectiveMode: true, unknown)
            == "Unknown Mode. Home Assistant has not provided an effective-mode reason.")
        let blankReason = lookup([C.homeAwayEntityId: "unavailable", C.homeAwayReasonEntityId: "  "])
        #expect(ClimateLogic.homeAwayStatus(blankReason) == .init(state: "Unavailable", reason: C.Copy.noReason))
        #expect(ClimateLogic.homeAwayStatus(home).reason == reason)
        // A room reads its own away_mode_active first, then the global sensor.
        let room = C.rooms[0].climateEntityId
        let roomAway = lookup([C.homeAwayEntityId: "Home", C.awayModeEntityId: "off", room: "heat_cool"],
                              attributes: [room: ["away_mode_active": .bool(true)]])
        #expect(ClimateLogic.awayNotice(climateEntityId: room, useEffectiveMode: false, roomAway)?.hasPrefix("Away Mode Active.") == true)
        let globalAway = lookup([C.homeAwayEntityId: "Home", C.awayModeEntityId: "on"])
        #expect(ClimateLogic.roomAwayMode(climateEntityId: room, globalAway))
        #expect(ClimateLogic.awayNotice(climateEntityId: room, useEffectiveMode: false, globalAway) != nil)
        #expect(ClimateLogic.awayNotice(climateEntityId: room, useEffectiveMode: false, home) == nil)
    }

    @Test func integrationWarningOnlyWhenExplicitlyOff() {
        #expect(ClimateLogic.showsIntegrationWarning(lookup([C.integrationEntityId: "off"])))
        #expect(!ClimateLogic.showsIntegrationWarning(lookup([C.integrationEntityId: "on"])))
        #expect(!ClimateLogic.showsIntegrationWarning(lookup([:])))
    }

    // MARK: Contacts and rooms

    @Test func openContactsShowOnlyWhileTheAggregateIsOpen() {
        let window = "binary_sensor.demo_office_contact_2"
        let door = "binary_sensor.demo_front_door_contact_1"
        #expect(ClimateLogic.openContactSensors(lookup([C.contactSensorsEntityId: "off", window: "on"])).isEmpty)
        let open = ClimateLogic.openContactSensors(lookup([C.contactSensorsEntityId: "on", window: "on", door: "open"]))
        #expect(open.map(\.title) == ["Front Door", "Office Window"])
        #expect(open.map(\.isWindow) == [false, true])
        #expect(ClimateLogic.contactState(EntityState(entityId: window, state: "on")) == "Open")
        #expect(ClimateLogic.contactState(EntityState(entityId: window, state: "closed")) == "Closed")
        #expect(ClimateLogic.contactState(EntityState(entityId: window, state: "unknown")) == "Unknown")
        #expect(ClimateLogic.contactState(EntityState(entityId: window, state: "unavailable")) == "Unavailable")
        #expect(ClimateLogic.contactState(EntityState(entityId: window, state: "tilted")) == "Tilted")
        #expect(ClimateLogic.contactState(nil) == "Unavailable")
    }

    @Test func roomSubtitleAndOccupancy() {
        let room = C.rooms[0]
        let states = lookup([room.temperatureEntityId: "70.94", room.occupancyEntityId: "occupied"],
                            attributes: [room.temperatureEntityId: ["unit_of_measurement": .string("°F")]])
        #expect(ClimateLogic.roomSubtitle(room, states) == "70.9°F · Occupied")
        #expect(ClimateLogic.roomSubtitle(room, lookup([:])) == "--°F · Unknown")
        #expect(ClimateLogic.roomTemperature(room, states) == "70.9°F")
        #expect(ClimateLogic.roomOccupancy(room, states) == "Occupied")
        #expect(ClimateLogic.isOccupied(EntityState(entityId: "sensor.demo_x", state: "active")))
        #expect(ClimateLogic.isOccupied(EntityState(entityId: "sensor.demo_x", state: "on")))
        #expect(!ClimateLogic.isOccupied(EntityState(entityId: "sensor.demo_x", state: "inactive")))
        #expect(!ClimateLogic.isOccupied(nil))
        #expect(ClimateLogic.ventState(EntityState(entityId: "cover.demo_x", state: "open")) == "Open")
    }

    @Test func ventTilesShowTheirOpenPosition() {
        func vent(_ state: String, position: Double? = nil) -> EntityState {
            EntityState(entityId: "cover.demo_x", state: state, attributes: position.map { ["current_position": .number($0)] } ?? [:])
        }
        #expect(ClimateLogic.ventSubtitle(vent("open", position: 60)) == "Open · 60%")
        #expect(ClimateLogic.ventSubtitle(vent("open", position: 100)) == "Open · 100%")
        #expect(ClimateLogic.ventSubtitle(vent("opening", position: 12.4)) == "Opening · 12%")
        #expect(ClimateLogic.ventSubtitle(vent("open")) == "Open", "No reported position, no percentage")
        #expect(ClimateLogic.ventSubtitle(vent("closed", position: 0)) == "Closed")
        #expect(ClimateLogic.ventSubtitle(vent("unavailable")) == "Unavailable")
        #expect(ClimateLogic.ventSubtitle(nil) == "Unavailable")
        #expect(ClimateLogic.isVentOpen(vent("open")) && ClimateLogic.isVentOpen(vent("opening")))
        #expect(!ClimateLogic.isVentOpen(vent("closed")) && !ClimateLogic.isVentOpen(vent("closing")))
        #expect(!ClimateLogic.isVentOpen(nil))
    }

    // MARK: Tracking summary

    @Test func criticalSubtitleAgreesWithOneRoom() {
        var states: [String: String] = [C.trackSelectedEntityId: "on", C.ecoCriticalEntityId: "Track Select Critical"]
        states[C.rooms[5].forceCriticalEntityId] = "on"
        #expect(ClimateLogic.trackingSummary(lookup(states)).criticalSubtitle == "1 room forced")
    }

    @Test func trackingSummaryCounts() {
        var states: [String: String] = [C.trackSelectedEntityId: "on", C.ecoCriticalEntityId: "Track Select Critical"]
        for room in C.rooms.prefix(3) { states[room.trackEntityId] = "on" }
        // A tracked room forced critical doesn't count; untracked ones do.
        states[C.rooms[0].forceCriticalEntityId] = "on"
        states[C.rooms[5].forceCriticalEntityId] = "on"
        states[C.rooms[6].forceCriticalEntityId] = "on"
        states[C.rooms[3].occupiedOnlyEntityId] = "on"
        let summary = ClimateLogic.trackingSummary(lookup(states))
        #expect(summary.selectedCount == 3)
        #expect(summary.criticalCount == 2)
        #expect(summary.occupiedOnlyCount == 1)
        #expect(summary.selectedEnabled && summary.criticalEnabled)
        #expect(summary.selectedSubtitle == "3 of 11 selected")
        #expect(summary.criticalSubtitle == "2 rooms forced")
        #expect(summary.occupiedOnlySubtitle == "1 of 11 occupied only")
        #expect(C.TrackingPage.allCases.map(summary.isEnabled) == [true, true, true])
        #expect(C.TrackingPage.allCases.map(summary.subtitle) == ["3 of 11 selected", "2 rooms forced", "1 of 11 occupied only"])
        // Critical Protection lists only untracked rooms.
        let rooms = ClimateLogic.rooms(for: .criticalProtection) { states[$0] }
        #expect(rooms.count == 8 && !rooms.contains(C.rooms[0]))
        #expect(ClimateLogic.rooms(for: .selectedRooms) { states[$0] }.count == 11)
    }

    @Test func trackingSummaryEnablement() {
        let policyOther = ClimateLogic.trackingSummary(lookup([C.trackSelectedEntityId: "on", C.ecoCriticalEntityId: "Track All Critical"]))
        #expect(policyOther.selectedEnabled && !policyOther.criticalEnabled)
        #expect(policyOther.criticalSubtitle == "Track All Critical")
        let off = ClimateLogic.trackingSummary(lookup([C.trackSelectedEntityId: "off"]))
        #expect(!off.selectedEnabled && !off.criticalEnabled)
        #expect(off.selectedSubtitle == "Enable Track Selected Rooms first")
        #expect(off.criticalSubtitle == "Enable Track Selected Rooms first")
        #expect(off.criticalPolicy == "Unavailable")
        #expect(C.TrackingPage.allCases.map(off.isEnabled) == [false, false, true])
        // An optimistic state wins over the live one.
        let optimistic = ClimateLogic.trackingSummary(lookup([C.trackSelectedEntityId: "off"])) { $0 == C.trackSelectedEntityId ? "on" : nil }
        #expect(optimistic.selectedEnabled)
    }

    // MARK: Options

    @Test func optionPresentation() {
        let select = EntityState(entityId: C.ecoAwayEntityId, state: "Keep Eco Active", attributes: [
            "options": .array([.string("Disable Eco When Away"), .string("Use Eco Away Targets"), .string("Keep Eco Active"), .string("custom_mode")]),
        ])
        let options = ClimateLogic.selectOptions(select)
        #expect(options.map(\.label) == ["Disable Eco When Away", "Use Eco Away Targets", "Keep Eco Active", "Custom Mode"])
        #expect(options[0].description == "Turn Eco Mode off while everyone is away.")
        #expect(options[0].icon == "mdi:home-export-outline")
        #expect(options[1].description == "Use the wider away temperature range while everyone is away.")
        #expect(options[2].description == "Keep normal Eco Mode behavior active while everyone is away.")
        #expect(options[3].description == nil && options[3].icon == nil)
        #expect(ClimateLogic.selectOptions(nil).isEmpty)
        let critical = ClimateLogic.selectOptions(EntityState(entityId: C.ecoCriticalEntityId, state: "x", attributes: [
            "options": .array([.string("Do Not Track Critical"), .string("Track Select Critical"), .string("Track All Critical")]),
        ]))
        #expect(critical.map(\.description) == [
            "Do not add temperature-only protection for unselected rooms.",
            "Protect only the unselected rooms chosen in Critical Protection.",
            "Protect every room from unsafe temperatures, even when it is not selected.",
        ])
        #expect(critical.map(\.icon) == ["mdi:thermometer-off", "mdi:thermometer-check", "mdi:thermometer-alert"])
    }

    @Test func hubModeAndFanOptions() {
        let hub = EntityState(entityId: C.hubEntityId, state: "off", attributes: [
            "hvac_modes": .array([.string("off"), .string("heat_cool"), .string("fan_only")]),
            "fan_modes": .array([.string("auto"), .number(2), .number(2.5), .bool(true), .null]),
        ])
        let modes = ClimateLogic.hvacModeOptions(hub)
        #expect(modes.map(\.label) == ["Off", "Heat/Cool", "Fan Only"])
        #expect(modes.map(\.icon) == ["mdi:power", "mdi:sun-snowflake-variant", "mdi:fan"])
        #expect(ClimateLogic.fanModeOptions(hub).map(\.value) == ["auto", "2", "2.5", "true"])
        #expect(ClimateLogic.fanModeOptions(EntityState(entityId: C.hubEntityId, state: "off")).isEmpty)
    }

    // MARK: Predictive Comfort

    @Test func predictiveSubtitleAndRecommendation() {
        let on = lookup([C.predictiveComfortEntityId: "on"], attributes: [C.predictiveComfortEntityId: ["current_recommendation": .string("pre_cool")]])
        #expect(ClimateLogic.predictiveSubtitle(on, shownState: "on") == "On · Pre-Cool")
        #expect(ClimateLogic.predictiveSubtitle(on, shownState: "off") == "Off")
        let sensorOnly = lookup([C.predictiveComfortEntityId: "on", C.predictiveSensorEntityId: "idle"])
        #expect(ClimateLogic.predictiveSubtitle(sensorOnly, shownState: "on") == "On · Idle")
        #expect(ClimateLogic.predictiveSubtitle(lookup([:]), shownState: nil) == "Unavailable")
        #expect(ClimateLogic.predictiveRecommendation(lookup([:])) == nil)
    }

    @Test func predictiveMetrics() {
        let sensor = EntityState(entityId: C.predictiveSensorEntityId, state: "idle", attributes: [
            "indoor_temperature": .number(71.6), "predicted_temperature": .number(70.8), "comfort_low": .number(71),
            "comfort_high": .number(74), "forecast_low": .number(46), "forecast_high": .number(59),
            "weather_entity": .string("weather.demo_weather_1"), "adjustment_status": .string("rate_limited"),
        ])
        #expect(ClimateLogic.predictiveMetrics(sensor).map(\.value) == [
            "71.6°F", "70.8°F", "71.0°F - 74.0°F", "46.0°F - 59.0°F", "weather.demo_weather_1", "Rate Limited",
        ])
        #expect(ClimateLogic.predictiveMetrics(sensor).map(\.label) == ["Indoor", "Predicted", "Comfort Band", "Forecast", "Weather", "Adjustment"])
        #expect(ClimateLogic.predictiveMetrics(nil).map(\.value) == ["--°F", "--°F", "--°F - --°F", "Unknown", "Unknown", "Unknown"])
        let numericWeather = EntityState(entityId: "sensor.demo_x", state: "1", attributes: ["weather_entity": .number(3), "forecast_high": .number(80)])
        #expect(ClimateLogic.predictiveMetrics(numericWeather)[4].value == "3")
        #expect(ClimateLogic.predictiveMetrics(numericWeather)[3].value == "--°F - 80.0°F")
        let nullWeather = EntityState(entityId: "sensor.demo_x", state: "1", attributes: ["weather_entity": .null])
        #expect(ClimateLogic.predictiveMetrics(nullWeather)[4].value == "Unknown")
    }

    @Test func predictiveReasonBulletsCopyTheWeb() {
        let sensor = EntityState(entityId: C.predictiveSensorEntityId, state: "pre_cool", attributes: [
            "reason": .string("Predicted indoor temperature rises above comfort band"),
            "predicted_temperature": .number(75.1), "comfort_low": .number(71), "comfort_high": .number(74),
            "forecast_low": .number(64), "forecast_high": .number(88),
            "active_activity_entities": .array([.string("binary_sensor.demo_office_pc_power")]),
            "adjustment_status": .string("applied"),
        ])
        #expect(ClimateLogic.predictiveReasonBullets(sensor) == [
            "Predicted indoor temperature rises above comfort band.",
            "Predicted indoor temperature is 75.1°F, above your 71.0°F - 74.0°F comfort band.",
            "Today's forecast range is 64.0°F - 88.0°F, which Predictive Comfort uses to estimate where the house is heading.",
            "Demo Office PC Power is active, so the model is accounting for extra heat from configured devices.",
            "Predictive Comfort has already applied the safe thermostat change.",
        ])
    }

    @Test func predictiveReasonBulletVariants() {
        func bullets(_ attributes: [String: JSONValue]) -> [String] {
            ClimateLogic.predictiveReasonBullets(EntityState(entityId: "sensor.demo_x", state: "idle", attributes: attributes))
        }
        let band: [String: JSONValue] = ["comfort_low": .number(71), "comfort_high": .number(74)]
        #expect(bullets(band.merging(["predicted_temperature": .number(69)]) { $1 })[0].contains("below your 71.0°F - 74.0°F"))
        #expect(bullets(band.merging(["predicted_temperature": .number(72)]) { $1 })[0].contains("inside your"))
        #expect(bullets(["indoor_temperature": .number(70)])[0]
            == "Current indoor temperature is 70.0°F, so the forecast is being compared against where the house is starting from.")
        #expect(bullets(["forecast_high": .number(80)])[0].hasPrefix("Today's forecast range is 80.0°F,"))
        let two = bullets(["active_activity_entities": .array([.string("switch.demo_a"), .string("switch.demo_b")])])
        #expect(two[0] == "Demo A, Demo B are active, so the model is accounting for extra heat from configured devices.")
        #expect(bullets([:]) == ["No configured heat-load devices are active right now."])
        #expect(bullets(["reason": .string("  ")]) == ["No configured heat-load devices are active right now."])
        #expect(ClimateLogic.predictiveReasonBullets(nil) == ["No configured heat-load devices are active right now."])
        let statuses = [
            "auto_adjust_disabled": "Auto setpoint adjustments are off, so this is only a recommendation.",
            "hvac_mode_changes_disabled": "HVAC mode changes are off, so Predictive Comfort will not switch between heat and cool automatically.",
            "skipped_away_mode": "Away Mode is active and away adjustments are off, so Predictive Comfort will not change the thermostat.",
            "rate_limited": "Thermostat changes are paused briefly to avoid rapid repeated adjustments.",
        ]
        for (status, line) in statuses {
            #expect(bullets(["adjustment_status": .string(status)]).last == line)
        }
        #expect(bullets(["adjustment_status": .string("other")]).count == 1)
    }
}
