import Foundation
import HassTestSupport
import Testing
@testable import HassCore

// MARK: - Climate adapter reads, choices and status projections

/// The adapter's read side: editing holds, option filtering, every status projection and the tracking rows.
@MainActor @Suite
struct ServerUIClimateAdapterReadTests {
    private func source(_ json: String) throws -> ServerUIClimateSource {
        try JSONDecoder().decode(ServerUIClimateSource.self, from: Data(json.utf8))
    }

    private func status(_ projection: String, unit: String = "°C") throws -> ServerUIClimateControl.Status {
        try JSONDecoder().decode(ServerUIClimateControl.Status.self, from: Data("""
            {"projection":"\(projection)","unit":"\(unit)",
             "states":[{"state":"on","text":"Running"},{"state":"open","text":"Open"},{"state":"closed","text":"Shut"},
                       {"state":"heating","text":"Heating"},{"state":"pre_cool","text":"Pre-cooling"}],
             "fallbackText":"Other"}
            """.utf8))
    }

    private func props(_ kind: String, extra: String = "") throws -> ServerUIClimateControl.Properties {
        try JSONDecoder().decode(ServerUIClimateControl.Properties.self, from: Data("""
            {"kind":"\(kind)","sourceId":"source","icon":"thermometer","hint":"","loadingText":"Loading",
             "unavailableText":"Unavailable","errorText":"Try again"\(extra)}
            """.utf8))
    }

    private func adapter(_ json: String, _ states: [String: String], attributes: [String: [String: JSONValue]] = [:],
                         caller: (any HassServiceCalling)? = nil) throws -> (ServerUIClimateAdapter, EntityStore) {
        let store = makeStore(states, attributes: attributes)
        return (ServerUIClimateAdapter(configuration: try source(json), store: store, caller: caller), store)
    }

    @Test func aNativeEditHoldsPublicationUntilItEnds() throws {
        let (adapter, _) = try adapter(#"{"entityId":"climate.demo_zone","rangeCommitEntityIds":[]}"#, ["climate.demo_zone": "heat"],
                                       caller: RecordingCaller())
        #expect(!adapter.hasPendingIntent)
        adapter.setEditing(true, controlID: "dial")
        #expect(adapter.hasPendingIntent)
        adapter.setEditing(false, controlID: "dial")
        #expect(!adapter.hasPendingIntent)
        #expect(adapter.isEnabled)
    }

    @Test func aSourceWithoutACallerIsNeverEnabled() throws {
        let (adapter, _) = try adapter(#"{"entityId":"climate.demo_zone","rangeCommitEntityIds":[]}"#, ["climate.demo_zone": "heat"])
        #expect(!adapter.isEnabled)
        #expect(adapter.controller == nil)
        #expect(!adapter.hasPendingIntent)
    }

    @Test func selectedOptionsPreferTheOptimisticValueAndFallBackToTheEntity() async throws {
        let (adapter, _) = try adapter(#"{"entityId":"climate.demo_zone","rangeCommitEntityIds":[]}"#, ["climate.demo_zone": "heat"], attributes: [
            "climate.demo_zone": ["fan_mode": .string("auto"), "preset_mode": .string("eco"),
                                  "hvac_modes": .array([.string("off"), .string("heat")]),
                                  "fan_modes": .array([.string("auto"), .string("on")]),
                                  "preset_modes": .array([.string("eco")]), "options": .array([.string("one")])]
        ], caller: RecordingCaller())
        #expect(adapter.selected(.mode) == "heat")
        #expect(adapter.selected(.fan) == "auto")
        #expect(adapter.selected(.preset) == "eco")
        #expect(adapter.selected(.options) == "heat")
        await adapter.submit(.mode("climate.demo_zone", "off"), expectedTarget: adapter.target).value
        #expect(adapter.selected(.mode) == "off", "the pending value shows until Home Assistant answers")
    }

    @Test func choicesKeepOnlyWhatTheEntityOffersInAuthoredOrder() throws {
        let (adapter, _) = try adapter(#"{"entityId":"climate.demo_zone","rangeCommitEntityIds":[]}"#, ["climate.demo_zone": "heat"], attributes: [
            "climate.demo_zone": ["hvac_modes": .array([.string("off"), .string("heat")]),
                                  "fan_modes": .array([.string("on")]), "preset_modes": .array([.string("eco")]),
                                  "options": .array([.string("b")])]
        ])
        func choice(_ value: String) -> String { #"{"value":"\#(value)","label":"\#(value)","icon":"x","detail":""}"# }
        let authored = try JSONDecoder().decode([ServerUIClimateControl.Choice].self, from: Data("[\(["heat", "cool", "off", "on", "eco", "a", "b"].map(choice).joined(separator: ","))]".utf8))
        #expect(adapter.choices(authored, kind: .mode).map(\.value) == ["heat", "off"])
        #expect(adapter.choices(authored, kind: .fan).map(\.value) == ["on"])
        #expect(adapter.choices(authored, kind: .preset).map(\.value) == ["eco"])
        #expect(adapter.choices(authored, kind: .options).map(\.value) == ["b"])
        let withChoices = try props("mode", extra: #","choices":[\#(choice("cool")),\#(choice("heat"))]"#)
        #expect(adapter.choices(withChoices).map(\.value) == ["heat"])
        #expect(adapter.choices(try props("mode")).isEmpty)
    }

    @Test func linkRowsFollowTheirProjection() throws {
        let tracking = #"""
            {"entityId":"switch.demo_tracking","rangeCommitEntityIds":[],
             "tracking":{"policyEntityId":"select.demo_policy","criticalOption":"Critical","rooms":[
               {"selectedEntityId":"switch.demo_selected","criticalEntityId":"switch.demo_critical","occupiedOnlyEntityId":"switch.demo_occupied"}]}}
            """#
        let (adapter, store) = try adapter(tracking, ["switch.demo_tracking": "on", "select.demo_policy": "Critical",
                                                      "switch.demo_selected": "on", "switch.demo_critical": "off", "switch.demo_occupied": "off"])
        func link(_ projection: String) throws -> ServerUIClimateControl.Properties {
            try props("link", extra: #","status":{"projection":"\#(projection)","unit":"°F","states":[],"fallbackText":"Unknown"}"#)
        }
        #expect(adapter.navigationEnabled(try link("trackingSelected")))
        #expect(adapter.navigationEnabled(try link("trackingOccupiedOnly")))
        #expect(adapter.navigationEnabled(try link("trackingCritical")) == (adapter.trackingSummary?.isEnabled(.criticalProtection) == true))
        #expect(adapter.navigationEnabled(try link("state")), "a plain projection is enabled while it has a reading")
        #expect(!adapter.navigationEnabled(try props("link")), "a link with no status never opens")
        #expect(adapter.navigationEnabled(try props("room-tile")))
        set(store, "switch.demo_tracking", "unavailable")
        #expect(!adapter.navigationEnabled(try link("state")))
    }

    @Test func aSelectEntityWithoutOptionsDisablesItsLink() throws {
        let (adapter, store) = try adapter(#"{"entityId":"select.demo_mode","rangeCommitEntityIds":[]}"#, ["select.demo_mode": "Home"],
                                           attributes: ["select.demo_mode": ["options": .array([.string("Home"), .string("Away")])]])
        let link = try props("link", extra: #","status":{"projection":"state","unit":"°C","states":[],"fallbackText":"None"}"#)
        #expect(adapter.navigationEnabled(link))
        store.apply([EntityState(entityId: "select.demo_mode", state: "Home", attributes: ["options": .array([])])])
        #expect(!adapter.navigationEnabled(link))
    }

    @Test func stateActionVentAndTemperatureProjectionsUseAuthoredLabels() throws {
        let (adapter, store) = try adapter(#"{"entityId":"cover.demo_vent","rangeCommitEntityIds":[]}"#, ["cover.demo_vent": "closed"])
        #expect(adapter.status(try status("state")) == "Shut")
        set(store, "cover.demo_vent", "mystery")
        #expect(adapter.status(try status("state")) == "Other")
        #expect(adapter.status(try status("occupancy")) == "Other")
        set(store, "cover.demo_vent", "unavailable")
        #expect(adapter.status(try status("state")) == nil)

        set(store, "cover.demo_vent", "closed")
        #expect(adapter.status(try status("vent")) == "Shut")
        store.apply([EntityState(entityId: "cover.demo_vent", state: "open", attributes: ["current_position": .number(60)])])
        #expect(adapter.status(try status("vent")) == "Open · 60%")

        let (thermostat, climateStore) = try self.adapter(#"{"entityId":"climate.demo_zone","rangeCommitEntityIds":[],"actionEntityId":"sensor.demo_action"}"#,
                                                          ["climate.demo_zone": "heat", "sensor.demo_action": "heating"],
                                                          attributes: ["climate.demo_zone": ["current_temperature": .number(21.5),
                                                                                            "temperature_unit": .string("°C")]])
        #expect(thermostat.status(try status("temperature")) == ClimateLogic.temperature(21.5, unit: "°C"))
        #expect(thermostat.status(try status("temperature", unit: "°F")) == nil, "a unit mismatch is not shown")
        #expect(thermostat.status(try status("action")) != nil)
        climateStore.apply([EntityState(entityId: "climate.demo_zone", state: "heat", attributes: [:])])
        #expect(thermostat.status(try status("temperature")) == nil)
    }

    @Test func aSensorEntityReadsItsOwnStateAsTheTemperature() throws {
        let (adapter, _) = try adapter(#"{"entityId":"sensor.demo_temperature","rangeCommitEntityIds":[]}"#, ["sensor.demo_temperature": "18.5"],
                                       attributes: ["sensor.demo_temperature": ["unit_of_measurement": .string("°C")]])
        #expect(adapter.status(try status("temperature")) == ClimateLogic.temperature(18.5, unit: "°C"))
    }

    @Test func predictionTextProjectionsReadTheSensorAndKeepAuthoredStateLabels() throws {
        let (adapter, store) = try adapter(#"{"entityId":"switch.demo_predictive","rangeCommitEntityIds":[],"sensorEntityId":"sensor.demo_prediction"}"#,
                                           ["switch.demo_predictive": "on"])
        store.apply([EntityState(entityId: "sensor.demo_prediction", state: "pre_cool", attributes: [
            "reason": .string("warming_trend"), "weather_entity": .string("weather.demo_home"), "adjustment_status": .string("heating"),
            "temperature_unit": .string("°C"), "indoor_temperature": .number(21), "predicted_temperature": .number(23),
            "comfort_low": .number(19), "comfort_high": .number(24), "forecast_low": .number(16), "forecast_high": .number(29)
        ])])
        #expect(adapter.status(try status("recommendation")) == "Pre-cooling")
        #expect(adapter.status(try status("adjustment")) == "Heating")
        #expect(adapter.status(try status("reason")) == "warming_trend")
        #expect(adapter.status(try status("weather")) == "weather.demo_home")
        #expect(adapter.status(try status("indoor")) == ClimateLogic.temperature(21, unit: "°C"))
        #expect(adapter.status(try status("predicted")) == ClimateLogic.temperature(23, unit: "°C"))
        #expect(adapter.status(try status("comfortLow")) == ClimateLogic.temperature(19, unit: "°C"))
        #expect(adapter.status(try status("comfortHigh")) == ClimateLogic.temperature(24, unit: "°C"))
        #expect(adapter.status(try status("forecastLow")) == ClimateLogic.temperature(16, unit: "°C"))
        #expect(adapter.status(try status("forecastHigh")) == ClimateLogic.temperature(29, unit: "°C"))
        set(store, "switch.demo_predictive", "unavailable")
        #expect(adapter.status(try status("indoor")) == nil)
    }

    @Test func predictiveShowsTheRecommendationOnlyWhenOnAndOneExists() throws {
        let (adapter, store) = try adapter(#"{"entityId":"switch.demo_predictive","rangeCommitEntityIds":[],"sensorEntityId":"sensor.demo_missing"}"#,
                                           ["switch.demo_predictive": "on"])
        #expect(adapter.status(try status("predictive")) == nil, "on with no recommendation and no sensor shows nothing")
        store.apply([EntityState(entityId: "switch.demo_predictive", state: "on", attributes: ["current_recommendation": .string("pre_cool")])])
        #expect(adapter.status(try status("predictive")) == "Running · Pre-Cool")
        set(store, "switch.demo_predictive", "off")
        #expect(adapter.status(try status("predictive")) == "Other")
    }

    @Test func trackingProjectionsAndFieldsReadTheRoomSwitches() throws {
        let json = #"""
            {"entityId":"switch.demo_tracking","rangeCommitEntityIds":[],
             "tracking":{"policyEntityId":"select.demo_policy","criticalOption":"Critical","rooms":[
               {"selectedEntityId":"switch.demo_a","criticalEntityId":"switch.demo_a_critical","occupiedOnlyEntityId":"switch.demo_a_occupied"},
               {"selectedEntityId":"switch.demo_b","criticalEntityId":"switch.demo_b_critical","occupiedOnlyEntityId":"switch.demo_b_occupied"}]}}
            """#
        let (adapter, store) = try adapter(json, ["switch.demo_tracking": "on", "select.demo_policy": "Critical",
                                                  "switch.demo_a": "on", "switch.demo_a_critical": "off", "switch.demo_a_occupied": "on",
                                                  "switch.demo_b": "off", "switch.demo_b_critical": "on", "switch.demo_b_occupied": "off"])
        let summary = try #require(adapter.trackingSummary)
        #expect(adapter.status(try status("trackingSelected")) == summary.subtitle(.selectedRooms))
        #expect(adapter.status(try status("trackingCritical")) == summary.subtitle(.criticalProtection))
        #expect(adapter.status(try status("trackingOccupiedOnly")) == summary.subtitle(.occupiedOnly))
        #expect(adapter.trackingValue("occupiedOnlyCount") == .number(Double(summary.occupiedOnlyCount)))
        #expect(adapter.trackingValue("totalRooms") == .number(2))
        #expect(adapter.trackingValue("selectedEnabled") == .bool(summary.selectedEnabled))
        #expect(adapter.trackingValue("unknownField") == nil)
        set(store, "select.demo_policy", "unavailable")
        #expect(adapter.trackingSummary == nil)
        #expect(adapter.status(try status("trackingSelected")) == nil)
        #expect(adapter.trackingValue("selectedCount") == nil)
    }

    @Test func aSourceWithoutHomeAwayHasNoNotice() throws {
        let (adapter, _) = try adapter(#"{"entityId":"climate.demo_zone","rangeCommitEntityIds":[]}"#, ["climate.demo_zone": "heat"])
        let copy = try JSONDecoder().decode(ServerUIClimateControl.Notice.self, from: Data("""
            {"useEffectiveMode":false,"isWarning":false,"awayText":"a","vacationText":"v","unknownText":"u",
             "unavailableModeText":"n","reasonFallback":"r","separator":" / "}
            """.utf8))
        #expect(adapter.notice(copy) == nil)
        #expect(adapter.trackingSummary == nil)
        #expect(adapter.trackingValue("selectedCount") == nil)
    }

    @Test func aCommandCannotNameATargetOutsideTheSource() async throws {
        let caller = RecordingCaller()
        let (adapter, _) = try adapter(#"{"entityId":"climate.demo_zone","rangeCommitEntityIds":["climate.demo_one","climate.demo_two"]}"#,
                                       ["climate.demo_zone": "heat_cool", "climate.demo_one": "heat_cool", "climate.demo_two": "heat_cool"],
                                       caller: caller)
        var rejected = 0
        // A fan-out naming the wrong ids, then single-target intents aimed elsewhere, each count as one failure and call nothing.
        await adapter.submit(.temperature(["climate.demo_one"], ["target_temp_low": 19, "target_temp_high": 24], unit: "°C"),
                             expectedTarget: adapter.target, failed: { rejected += 1 }).value
        await adapter.submit(.select("climate.demo_other", "x"), expectedTarget: adapter.target, failed: { rejected += 1 }).value
        await adapter.submit(.fan("climate.demo_other", "on"), expectedTarget: adapter.target, failed: { rejected += 1 }).value
        await adapter.submit(.preset("climate.demo_other", "eco"), expectedTarget: adapter.target, failed: { rejected += 1 }).value
        #expect(rejected == 4 && adapter.failureCount == 4)
        #expect(caller.calls.isEmpty)
    }
}
