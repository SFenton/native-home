import Foundation
import HassTestSupport
import Testing
@testable import HassCore

// MARK: - Configured climate contracts and commands

@MainActor @Suite
struct ServerUIClimateTests {
    @Test func roomTileUsesSeparateCanonicalReadingsAndReportsMissingOccupancy() throws {
        let config = try source("""
            {"entityId":"climate.demo_room","rangeCommitEntityIds":[],
             "sensorEntityId":"sensor.demo_temperature","occupancyEntityId":"sensor.demo_occupancy"}
            """)
        let store = makeStore(["climate.demo_room": "heat", "sensor.demo_temperature": "19", "sensor.demo_occupancy": "not_occupied"],
                              attributes: ["sensor.demo_temperature": ["unit_of_measurement": .string("°C")]])
        let adapter = ServerUIClimateAdapter(configuration: config, store: store, caller: nil)
        #expect(adapter.roomSubtitle == "19.0°C\nNot Occupied")
        set(store, "sensor.demo_occupancy", "unavailable")
        #expect(adapter.roomSubtitle == nil)
    }

    private func source(_ json: String = """
        {"entityId":"climate.demo_zone","rangeCommitEntityIds":["climate.demo_one","climate.demo_two"],
         "actionEntityId":"climate.demo_zone","sensorEntityId":"sensor.demo_prediction",
         "effectiveAway":{"ecoEntityId":"climate.demo_eco","modeEntityId":"sensor.demo_mode","fallbackEntityId":"binary_sensor.demo_away"}}
        """) throws -> ServerUIClimateSource {
        try JSONDecoder().decode(ServerUIClimateSource.self, from: Data(json.utf8))
    }

    @Test func arbitraryTargetsRetainRangeFanoutAndAwaySelection() async throws {
        let store = makeStore([
            "climate.demo_zone": "heat_cool", "climate.demo_one": "heat_cool", "climate.demo_two": "heat_cool",
            "climate.demo_eco": "heat_cool", "sensor.demo_mode": "Home", "binary_sensor.demo_away": "off"
        ])
        let caller = RecordingCaller()
        let adapter = ServerUIClimateAdapter(configuration: try source(), store: store, caller: caller)
        #expect(adapter.target == "climate.demo_zone")
        let task = adapter.submit(.temperature(["climate.demo_one", "climate.demo_two"], ["target_temp_low": 19, "target_temp_high": 24], unit: "°C"),
                                  expectedTarget: adapter.target)
        #expect(adapter.hasPendingIntent)
        await task.value
        #expect(caller.calls.count == 1)
        #expect(caller.calls[0].service == "set_temperature")
        #expect(caller.raw[0]["entity_id"] as? [String] == ["climate.demo_one", "climate.demo_two"])
        set(store, "sensor.demo_mode", "Away")
        #expect(adapter.target == "climate.demo_eco")
        await adapter.submit(.temperature(["climate.demo_eco"], ["target_temp_low": 16, "target_temp_high": 28], unit: "°C"),
                             expectedTarget: adapter.target).value
        #expect(caller.calls.count == 2)
        #expect(caller.calls.last?.data["entity_id"] == "climate.demo_eco")
        await adapter.submit(.temperature(["climate.demo_one", "climate.demo_two"], ["target_temp_low": 19, "target_temp_high": 24], unit: "°C"),
                             expectedTarget: "climate.demo_zone").value
        #expect(caller.calls.count == 2)
        #expect(adapter.failureCount == 1)
    }

    @Test func configuredModesValidateCurrentOptionsAndKeepOptimisticKeysIndependent() async throws {
        let store = makeStore(["climate.demo_zone": "off"], attributes: ["climate.demo_zone": [
            "hvac_modes": .array([.string("off"), .string("heat")]),
            "fan_modes": .array([.string("auto"), .string("on")]), "fan_mode": .string("auto"),
            "preset_modes": .array([.string("eco")])
        ]])
        let caller = RecordingCaller(), scheduler = ManualScheduler()
        let climate = ClimateController(store: store, caller: caller, scheduler: scheduler, configuredEntityIds: ["climate.demo_zone"])
        try await climate.execute(.mode("climate.demo_zone", "heat"))
        try await climate.execute(.fan("climate.demo_zone", "on"))
        try await climate.execute(.preset("climate.demo_zone", "eco"))
        #expect(climate.shown("climate.demo_zone#hvac_mode") == "heat")
        #expect(climate.shown("climate.demo_zone#fan_mode") == "on")
        #expect(caller.calls.map(\.service) == ["set_hvac_mode", "set_fan_mode", "set_preset_mode"])
        await #expect(throws: ClimateConfiguredError.unsupportedOption) {
            try await climate.execute(.mode("climate.demo_zone", "cool"))
        }
        await #expect(throws: ClimateConfiguredError.unavailable) {
            try await climate.execute(.mode("climate.demo_other", "heat"))
        }
        scheduler.fireAll()
        #expect(climate.shown("climate.demo_zone#hvac_mode") == "off")
        #expect(climate.pendingCommandCount == 0)
    }

    @Test func trackingGatesRevalidateAndUnavailableNeverCalls() async throws {
        let config = try source("""
            {"entityId":"switch.demo_critical","rangeCommitEntityIds":[],
             "trackingGate":{"selectedEntityId":"switch.demo_enabled","criticalEntityId":"select.demo_policy",
              "criticalOption":"Track Select Critical","trackedEntityId":"switch.demo_tracked"}}
            """)
        let store = makeStore(["switch.demo_critical": "off", "switch.demo_enabled": "on",
                               "select.demo_policy": "Track Select Critical", "switch.demo_tracked": "off"])
        let caller = RecordingCaller()
        let adapter = ServerUIClimateAdapter(configuration: config, store: store, caller: caller)
        #expect(adapter.isEnabled)
        set(store, "switch.demo_tracked", "on")
        await adapter.submit(.toggle(adapter.target), expectedTarget: adapter.target).value
        #expect(caller.calls.isEmpty && adapter.failureCount == 1)
        set(store, "switch.demo_tracked", "off")
        set(store, "switch.demo_critical", "unavailable")
        #expect(!adapter.isEnabled)
    }

    @Test func explicitSwitchFailureRollsBackAndCommandCannotEscapeSource() async throws {
        let config = try source(#"{"entityId":"switch.demo_predictive","rangeCommitEntityIds":[]}"#)
        let store = makeStore(["switch.demo_predictive": "off", "switch.demo_other": "off"])
        let caller = RecordingCaller()
        let adapter = ServerUIClimateAdapter(configuration: config, store: store, caller: caller)
        caller.failNext = true
        await adapter.submit(.setSwitch(adapter.target, true), expectedTarget: adapter.target).value
        #expect(adapter.shown(adapter.target) == "off")
        #expect(adapter.failureCount == 1)
        #expect(caller.calls.first?.service == "turn_on")
        await adapter.submit(.toggle("switch.demo_other"), expectedTarget: adapter.target).value
        #expect(caller.calls.count == 1 && adapter.failureCount == 2)
    }

    @Test func semanticValidationRejectsInvalidFanoutDomainsAndBounds() throws {
        let bad = try source(#"{"entityId":"switch.demo_zone","rangeCommitEntityIds":["light.demo_one","light.demo_one"]}"#)
        #expect(ServerUIClimateValidation.source(bad, at: "/inputs").contains { $0.pointer == "/inputs/rangeCommitEntityIds" })
        let props = try JSONDecoder().decode(ServerUIClimateControl.Properties.self, from: Data("""
            {"kind":"dial","sourceId":"source-zone","icon":"thermometer","hint":"","loadingText":"Reading",
             "unavailableText":"No thermostat","errorText":"Try again",
             "dial":{"minimum":30,"maximum":10,"step":1,"unit":"°C","size":"compact"}}
            """.utf8))
        let control = ServerUIClimateControl(node: .init(id: "dial-zone", title: "Test Zone", span: 1), props: props)
        #expect(ServerUIClimateValidation.control(control, source: try source(), at: "/props").contains { $0.pointer == "/props/dial" })
    }

    @Test func pendingLifetimeOutlivesOptimisticTimeoutAndFailureIsExplicit() async throws {
        let caller = SuspendedClimateCaller()
        let scheduler = ManualScheduler()
        let store = makeStore(["switch.demo_control": "off"])
        let adapter = ServerUIClimateAdapter(configuration: try source(#"{"entityId":"switch.demo_control","rangeCommitEntityIds":[]}"#),
                                             store: store, caller: caller, scheduler: scheduler)
        let task = adapter.submit(.toggle(adapter.target), expectedTarget: adapter.target)
        for _ in 0..<20 where caller.continuation == nil { await Task.yield() }
        #expect(caller.continuation != nil)
        scheduler.fireAll()
        #expect(adapter.controller?.overlay.pending.isEmpty == true)
        #expect(adapter.hasPendingIntent, "A timeout is not completion of a service call")
        caller.continuation?.resume(throwing: ClimateConfiguredError.unavailable)
        await task.value
        #expect(!adapter.hasPendingIntent && adapter.failureCount == 1)
    }

    @Test func injectedAwayNoticeUsesCanonicalVisibilityAndAuthoredCopy() throws {
        let config = try source("""
            {"entityId":"climate.demo_room","rangeCommitEntityIds":[],
             "homeAway":{"modeEntityId":"sensor.demo_mode","reasonEntityId":"sensor.demo_reason",
                         "fallbackEntityId":"binary_sensor.demo_away","vacationEntityId":"input_boolean.demo_vacation"}}
            """)
        let store = makeStore(["climate.demo_room": "heat_cool", "sensor.demo_mode": "Home", "sensor.demo_reason": "Nobody home",
                               "binary_sensor.demo_away": "off", "input_boolean.demo_vacation": "off"])
        let adapter = ServerUIClimateAdapter(configuration: config, store: store, caller: nil)
        let copy = try JSONDecoder().decode(ServerUIClimateControl.Notice.self, from: Data("""
            {"useEffectiveMode":true,"isWarning":false,"awayText":"Zone away","vacationText":"Zone vacation",
             "unknownText":"Unknown mode","unavailableModeText":"No mode","reasonFallback":"No reason","separator":" / "}
            """.utf8))
        #expect(adapter.notice(copy) == nil)
        set(store, "sensor.demo_mode", "unknown")
        #expect(adapter.notice(copy) == "Unknown mode / Nobody home")
        set(store, "binary_sensor.demo_away", "on")
        #expect(adapter.notice(copy) == "Zone away")
        set(store, "input_boolean.demo_vacation", "on")
        #expect(adapter.notice(copy) == "Zone vacation")
    }

    @Test func trackingCountsExcludeSelectedCriticalAndNeverInventMissingValues() throws {
        let config = try source("""
            {"entityId":"switch.demo_tracking","rangeCommitEntityIds":[],
             "tracking":{"policyEntityId":"select.demo_policy","criticalOption":"Critical","rooms":[
               {"selectedEntityId":"switch.demo_selected","criticalEntityId":"switch.demo_critical","occupiedOnlyEntityId":"switch.demo_occupied"}]}}
            """)
        let store = makeStore(["switch.demo_tracking": "on", "select.demo_policy": "Critical",
                               "switch.demo_selected": "on", "switch.demo_critical": "on", "switch.demo_occupied": "off"])
        let adapter = ServerUIClimateAdapter(configuration: config, store: store, caller: nil)
        let props = try JSONDecoder().decode(ServerUIClimateControl.Properties.self, from: Data("""
            {"kind":"link","sourceId":"tracking","icon":"checkmark","hint":"","loadingText":"Loading",
             "unavailableText":"Unavailable","errorText":"Try again",
             "status":{"projection":"trackingCritical","unit":"°F","states":[],"fallbackText":"Unknown"}}
            """.utf8))
        #expect(adapter.navigationEnabled(props))
        set(store, "select.demo_policy", "Do Not Track")
        #expect(!adapter.navigationEnabled(props))
        set(store, "select.demo_policy", "Critical")
        #expect(adapter.trackingValue("selectedCount") == .number(1))
        #expect(adapter.trackingValue("criticalCount") == .number(0))
        #expect(adapter.trackingValue("criticalEnabled") == .bool(true))
        set(store, "switch.demo_selected", "off")
        #expect(adapter.trackingValue("criticalCount") == .number(1))
        set(store, "switch.demo_occupied", "unavailable")
        #expect(adapter.trackingSummary == nil)
    }

    @Test func predictiveMissingSensorAndMismatchedUnitsRemainUnavailable() throws {
        let store = makeStore(["switch.demo_predictive": "on"])
        let adapter = ServerUIClimateAdapter(configuration: try source("""
            {"entityId":"switch.demo_predictive","rangeCommitEntityIds":[],"sensorEntityId":"sensor.demo_prediction"}
            """), store: store, caller: nil)
        func status(_ projection: String) throws -> ServerUIClimateControl.Status {
            try JSONDecoder().decode(ServerUIClimateControl.Status.self, from: Data("""
                {"projection":"\(projection)","unit":"°C","states":[{"state":"on","text":"Running"}],"fallbackText":"Other"}
                """.utf8))
        }
        #expect(adapter.status(try status("recommendation")) == nil)
        store.apply([EntityState(entityId: "sensor.demo_prediction", state: "pre_cool", attributes: [
            "indoor_temperature": .number(75), "unit_of_measurement": .string("°F")
        ])])
        #expect(adapter.status(try status("indoor")) == nil)
    }

    @Test func temperatureFanoutRejectsMixedUnitsBeforeAnyServiceCall() async throws {
        let caller = RecordingCaller()
        let store = makeStore(["climate.demo_one": "heat", "climate.demo_two": "heat"],
                              attributes: ["climate.demo_one": ["temperature_unit": .string("°C")],
                                           "climate.demo_two": ["temperature_unit": .string("°F")]])
        let controller = ClimateController(store: store, caller: caller, configuredEntityIds: ["climate.demo_one", "climate.demo_two"])
        await #expect(throws: ClimateConfiguredError.invalidIntent) {
            try await controller.execute(.temperature(["climate.demo_one", "climate.demo_two"],
                                                      ["target_temp_low": 19, "target_temp_high": 24], unit: "°C"))
        }
        #expect(caller.calls.isEmpty)
    }

    @Test func combinedPredictionReadingsAndExplanationRespectUnitsAndMissingBounds() throws {
        let store = makeStore(["switch.demo_predictive": "on"])
        let adapter = ServerUIClimateAdapter(configuration: try source("""
            {"entityId":"switch.demo_predictive","rangeCommitEntityIds":[],"sensorEntityId":"sensor.demo_prediction"}
            """), store: store, caller: nil)
        func status(_ projection: String, unit: String = "°C") throws -> ServerUIClimateControl.Status {
            try JSONDecoder().decode(ServerUIClimateControl.Status.self, from: Data("""
                {"projection":"\(projection)","unit":"\(unit)","states":[{"state":"on","text":"On"},{"state":"off","text":"Off"}],"fallbackText":"Unknown"}
                """.utf8))
        }
        var attributes: [String: JSONValue] = [
            "temperature_unit": .string("°C"), "comfort_low": .number(19), "comfort_high": .number(24),
            "forecast_low": .number(16), "forecast_high": .number(29), "reason": .string("warming_trend")
        ]
        func update() {
            store.apply([EntityState(entityId: "sensor.demo_prediction", state: "pre_cool", attributes: attributes)])
        }
        update()
        #expect(adapter.status(try status("comfortBand")) == "19.0°C - 24.0°C")
        #expect(adapter.status(try status("forecastRange")) == "16.0°C - 29.0°C")
        #expect(adapter.status(try status("predictive")) == "On · Pre-Cool")
        let sensor = try #require(store.entity("sensor.demo_prediction").state)
        #expect(adapter.status(try status("explanation")) == ClimateLogic.predictiveReasonBullets(sensor, unit: "°C").joined(separator: "\n\n"))
        for projection in ["comfortBand", "forecastRange", "explanation"] {
            #expect(adapter.status(try status(projection, unit: "°F")) == nil)
        }
        attributes.removeValue(forKey: "forecast_high")
        update()
        #expect(adapter.status(try status("forecastRange")) == nil)
        set(store, "switch.demo_predictive", "off")
        #expect(adapter.status(try status("predictive")) == "Off")
    }
}

@MainActor private final class SuspendedClimateCaller: HassServiceCalling {
    var continuation: CheckedContinuation<Void, any Error>?
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
}
