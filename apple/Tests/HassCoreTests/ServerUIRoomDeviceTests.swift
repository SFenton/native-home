import Foundation
import HassTestSupport
import Testing
@testable import HassCore

// MARK: - Synthetic domain contracts

enum DeviceLaneFixture {
    static var humidifierInputs: [String: String] {
        var fields = ServerUIRoomDeviceDescriptor.domains("humidifier@1").mapValues { "\($0).synthetic_\($0)" }
        // Every helper is an explicit distinct target.
        for (field, domain) in ServerUIRoomDeviceDescriptor.domains("humidifier@1") { fields[field] = "\(domain).synthetic_\(field.lowercased())" }
        fields.merge(["id": "synthetic-humidifier", "title": "Synthetic Mist", "scheduleId": "synthetic_schedule",
                      "setLevelScriptService": "synthetic_set_level", "applyProfileScriptService": "synthetic_apply_profile"]) { _, next in next }
        return fields
    }
    static func humidifier() throws -> HumidifierConfig {
        try JSONDecoder().decode(HumidifierConfig.self, from: JSONEncoder().encode(humidifierInputs))
    }
    static var fan: BathroomFanConfig {
        .init(id: "synthetic-fan", roomTitle: "Synthetic Room", autoUnlockEntityId: "input_boolean.demo_auto",
              deadlineEntityId: "input_datetime.demo_deadline", lockEntityId: "input_boolean.demo_lock",
              pendingEntityId: "input_boolean.demo_pending", powerEntityId: "switch.demo_fan",
              scriptService: "synthetic_fan_command", timerEntityId: "timer.demo_fan")
    }
    static var labels: JSONValue {
        .object(["loading": "Reading", "unavailable": "Not available", "failed": "No response", "on": "Enabled", "off": "Disabled",
                 "action": "Output", "cancel": "Clear", "footnote": "Synthetic help", "sleep": "Sleeping",
                 "tankFault": "Replace tank", "waterFault": "Refill water", "invalidTarget": "Choose target", "highTarget": "Condensation risk"].mapValues(JSONValue.string))
    }
    static func atom(_ control: String, source: String = "source-device", options: [JSONValue] = [], extras: [String: JSONValue] = [:]) -> JSONValue {
        var props: [String: JSONValue] = ["control": .string(control), "family": .string("water"), "options": .array(options), "labels": labels]
        props.merge(extras) { _, next in next }
        return .object([
            "id": .string("synthetic-control"), "title": .string("Authored control"), "type": .string("room-device-control"),
            "layout": .object(["span": .number(1)]), "icon": .object(["type": .string("sf-symbol"), "name": .string("drop"),
                "rendering": .string("canonical"), "unavailable": .string("reject")]),
            "binding": .object(["sourceId": .string(source)]), "props": .object(props)
        ])
    }
    static func publication(atom: JSONValue, inputs: [String: String] = humidifierInputs,
                            model: String = "humidifier@1", inputValue: JSONValue? = nil) throws -> JSONValue {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ServerUICompositionFixture.json")
        guard case .object(var root) = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)),
              case .object(var document) = root["document"], case .array(var pages) = document["pages"],
              case .object(var page) = pages[0], case .array(var components) = page["components"],
              case .array(var sources) = document["dataSources"] else { throw FixtureFailure() }
        var atom = atom
        if case .object(var component) = atom, case .object(var props) = component["props"],
           props["control"] == .string("fan-room"), let modalId = document["modals"]?.array?.first?["id"] {
            props["modalId"] = modalId
            component["props"] = .object(props)
            atom = .object(component)
        }
        components.append(atom)
        page["components"] = .array(components); pages[0] = .object(page); document["pages"] = .array(pages)
        sources.append(.object(["id": .string("source-device"), "kind": .string("model"), "model": .string(model),
                                "inputs": inputValue ?? .object(inputs.mapValues(JSONValue.string))]))
        document["dataSources"] = .array(sources); root["document"] = .object(document)
        var capabilities = ServerUICompositionPublication.firstSliceCapabilities + ["sh.\(model)"]
        if atom["props"]?["control"] == .string("humidifier-scheduling") { capabilities.append("sh.humidifier-scheduling@1") }
        root["capabilities"] = .array(capabilities.sorted().map(JSONValue.string))
        return .object(root)
    }
    struct FixtureFailure: Error {}
}

@Suite struct ServerUIRoomDeviceContractTests {
    @Test(arguments: ServerUIRoomDeviceControl.Kind.allCases)
    func everyOwnedAtomHasAClosedModelAndCapabilityContract(_ kind: ServerUIRoomDeviceControl.Kind) throws {
        let inputs: JSONValue
        switch kind.model {
        case "air-purifier@1":
            inputs = .object(["roomTitle": "Synthetic Room", "pm25EntityId": "sensor.demo_pm25", "aqiEntityId": "sensor.demo_aqi",
                              "autoModeEntityId": "select.demo_auto", "fanEntityId": "fan.demo_purifier",
                              "modeEntityId": "select.demo_mode"].mapValues(JSONValue.string))
        case "bathroom-fan@1": inputs = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(DeviceLaneFixture.fan))
        case "grill@1":
            inputs = .object(["title": .string("Synthetic Grill"), "roomTitle": .string("Synthetic Room"),
                              "stateEntityId": .string("sensor.demo_grill"), "details": .array([
                                .object(["title": .string("Probe"), "entityId": .string("sensor.demo_probe"), "icon": .string("thermometer")])
                              ])])
        default: inputs = .object(DeviceLaneFixture.humidifierInputs.mapValues(JSONValue.string))
        }
        let values: [String]
        switch kind {
        case .purifierMode: values = ["Auto", "Manual"]
        case .purifierAuto: values = ["Quiet"]
        case .purifierSpeed: values = ["66"]
        case .fanTimer: values = ["10"]
        case .humidifierMode: values = ["Sleep", "Manual"]
        case .humidifierPresets: values = ["8"]
        case .humidifierWarm: values = ["3", "0"]
        default: values = []
        }
        let options: [JSONValue] = values.map {
            var value: [String: JSONValue] = ["value": .string($0), "label": .string("Authored \($0)")]
            if kind == .fanTimer { value["actionLabel"] = .string("Stop after ten minutes") }
            return .object(value)
        }
        var extras: [String: JSONValue] = [:]
        if kind == .fanTimer { extras["initialMinutes"] = .number(10) }
        if kind == .grillDetail { extras["detailEntityId"] = .string("sensor.demo_probe") }
        if kind == .humidifierInfo { extras["info"] = .string("water") }
        if kind == .fanRoom {
            let icon = JSONValue.object(["type": .string("sf-symbol"), "name": .string("power"), "rendering": .string("canonical"), "unavailable": .string("reject")])
            extras["fanRail"] = .object(["order": .array([.string("lock"), .string("power")]),
                                        "powerIcon": icon, "lockedIcon": icon, "unlockedIcon": icon, "powerOn": .string("Start"),
                                        "powerOff": .string("Stop"), "lock": .string("Hold"), "unlock": .string("Release"), "locked": .string("Held")])
        }
        let root = try DeviceLaneFixture.publication(atom: DeviceLaneFixture.atom(kind.rawValue, options: options, extras: extras),
                                                     model: kind.model, inputValue: inputs)
        let publication = try ServerUICompositionPublication.decode(JSONEncoder().encode(root))
        guard case .roomDeviceControl(let control)? = publication.document.pages[0].surface.components.last else {
            Issue.record("Missing domain atom"); return
        }
        #expect(control.control == kind)
        #expect(control.options.map(\.value) == values)
        #expect(publication.capabilities == (ServerUICompositionPublication.firstSliceCapabilities
            + ["sh.\(kind.model)"] + (kind == .humidifierScheduling ? ["sh.humidifier-scheduling@1"] : [])).sorted())
    }

    @Test func authoredOrderLabelsAndExactCapabilitiesSurviveCompilation() throws {
        let atom = DeviceLaneFixture.atom("humidifier-mode", options: [
            .object(["value": .string("Sleep"), "label": .string("Quiet hours")]),
            .object(["value": .string("Manual"), "label": .string("My output")])
        ])
        let root = try DeviceLaneFixture.publication(atom: atom)
        let publication = try ServerUICompositionPublication.decode(JSONEncoder().encode(root))
        guard case .roomDeviceControl(let control)? = publication.document.pages[0].surface.components.last else {
            Issue.record("Missing domain atom"); return
        }
        #expect(control.options.map(\.label) == ["Quiet hours", "My output"])
        #expect(control.labels.failed == "No response")
        #expect(publication.capabilities.contains("sh.humidifier@1"))
        #expect(!publication.capabilities.contains("sh.humidifier-scheduling@1"))
    }

    @Test func rejectsWrongDomainMissingExplicitTargetAndWrongSourceModel() throws {
        var inputs = DeviceLaneFixture.humidifierInputs
        inputs["modeEntityId"] = "switch.demo_mode"
        #expect(throws: ServerUICompositionError(.invalidCombination, "/document/dataSources/2/inputs/modeEntityId")) {
            try ServerUICompositionPublication.decode(JSONEncoder().encode(DeviceLaneFixture.publication(atom: DeviceLaneFixture.atom("humidifier-power"), inputs: inputs)))
        }
        inputs["modeEntityId"] = nil
        #expect(throws: ServerUICompositionError(.missingRequired, "/document/dataSources/2/inputs/modeEntityId")) {
            try ServerUICompositionPublication.decode(JSONEncoder().encode(DeviceLaneFixture.publication(atom: DeviceLaneFixture.atom("humidifier-power"), inputs: inputs)))
        }
        #expect(throws: ServerUICompositionError(.bindingType, "/document/pages/0/components/1/binding/sourceId")) {
            try ServerUICompositionPublication.decode(JSONEncoder().encode(DeviceLaneFixture.publication(atom: DeviceLaneFixture.atom("fan-power"))))
        }
    }

    @Test func rejectsDuplicateUnsupportedAndUnconfiguredChoices() throws {
        let option = JSONValue.object(["value": .string("Manual"), "label": .string("Manual")])
        let root = try DeviceLaneFixture.publication(atom: DeviceLaneFixture.atom("humidifier-mode", options: [option, option]))
        #expect(throws: ServerUICompositionError(.invalidCombination, "/document/pages/0/components/1/props/options/1/value")) {
            try ServerUICompositionPublication.decode(JSONEncoder().encode(root))
        }
        let empty = try DeviceLaneFixture.publication(atom: DeviceLaneFixture.atom("humidifier-mode"))
        #expect(throws: ServerUICompositionError(.invalidCombination, "/document/pages/0/components/1/props/options")) {
            try ServerUICompositionPublication.decode(JSONEncoder().encode(empty))
        }
    }
}

// MARK: - Command and draft lifetimes

@MainActor
private final class DeviceHeldCaller: HassServiceCalling {
    private var continuation: CheckedContinuation<Void, Error>?
    private var started: CheckedContinuation<Void, Never>?
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        try await withCheckedThrowingContinuation {
            continuation = $0; started?.resume(); started = nil
        }
    }
    func waitForStart() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish() { continuation?.resume(); continuation = nil }
}

@MainActor @Suite
struct ServerUIRoomDeviceSourceTests {
    private func humidifierStore(_ config: HumidifierConfig, tank: String = "off") -> EntityStore {
        makeStore([
            config.powerEntityId: "on", config.modeEntityId: "Manual", config.mistLevelEntityId: "5", config.targetHumidityEntityId: "50",
            config.warmLevelEntityId: "0", config.timerMinutesEntityId: "0", config.displayEntityId: "on",
            config.tankRemovedEntityId: tank, config.waterLowEntityId: "off", config.scheduleEnabledEntityId: "off",
            config.scheduleEntityId: "off", config.vacationModeEntityId: "off"
        ])
    }

    @Test func timerUsesTheFanScriptAndMandatoryAutoUnlock() async throws {
        let fan = DeviceLaneFixture.fan, caller = RecordingCaller(), scheduler = ManualScheduler()
        let store = makeStore([fan.powerEntityId: "off", fan.lockEntityId: "on", fan.pendingEntityId: "off", fan.autoUnlockEntityId: "off"])
        let source = ServerUIRoomDeviceSource(descriptor: .fan(fan), store: store, caller: caller, scheduler: scheduler)
        try source.perform(.fanTimer, intent: .startTimer(10))
        guard case .fan(let model) = source.controller else { Issue.record("Wrong controller"); return }
        #expect(model.powerOn && model.timerPending)
        await source.commands.waitForCalls()
        #expect(caller.calls == [.init(domain: "script", service: fan.scriptService,
                                      data: ["command": "timer_start", "minutes": "10", "auto_unlock": "true"])])
        scheduler.fireAll()
        #expect(!model.powerOn && !model.timerPending)
        #expect(throws: ServerUIRoomDeviceSource.Failure.invalidIntent) { try source.perform(.fanTimer, intent: .startTimer(11)) }
    }

    @Test func transportRemainsPinnedAfterOptimisticExpiry() async throws {
        let fan = DeviceLaneFixture.fan, caller = DeviceHeldCaller(), scheduler = ManualScheduler()
        let source = ServerUIRoomDeviceSource(descriptor: .fan(fan),
            store: makeStore([fan.powerEntityId: "off", fan.lockEntityId: "off", fan.pendingEntityId: "off"]), caller: caller, scheduler: scheduler)
        try source.perform(.fanPower, intent: .setOn(true))
        await caller.waitForStart()
        scheduler.fireAll()
        #expect(source.commands.overlay.pending.isEmpty)
        #expect(source.hasPendingIntent)
        #expect(throws: ServerUIRoomDeviceSource.Failure.busy) { try source.perform(.fanPower, intent: .setOn(true)) }
        caller.finish()
        await source.commands.waitForCalls()
        #expect(!source.hasPendingIntent)
    }

    @Test func faultAndMissingCapabilitiesRejectCommandsAndFailuresRollBack() async throws {
        let config = try DeviceLaneFixture.humidifier(), caller = RecordingCaller()
        let faulted = ServerUIRoomDeviceSource(descriptor: .humidifier(config), store: humidifierStore(config, tank: "on"), caller: caller)
        #expect(throws: ServerUIRoomDeviceSource.Failure.unavailable) { try faulted.perform(.humidifierMist, intent: .number(8)) }
        #expect(caller.calls.isEmpty)
        let source = ServerUIRoomDeviceSource(descriptor: .humidifier(config), store: humidifierStore(config), caller: caller, scheduler: ManualScheduler())
        caller.failNext = true
        try source.perform(.humidifierWarm, intent: .choose("3"))
        await source.commands.waitForCalls()
        guard case .humidifier(let model) = source.controller else { Issue.record("Wrong controller"); return }
        #expect(model.warmLevel == 0)
        #expect(source.commands.isFailed(config.warmLevelEntityId))
        #expect(throws: ServerUIRoomDeviceSource.Failure.invalidIntent) { try source.perform(.humidifierMist, intent: .number(.infinity)) }
    }

    @Test func infoRequiresItsIndividualSensorsAndModesRevalidateLiveOptions() throws {
        let config = try DeviceLaneFixture.humidifier(), store = humidifierStore(config), caller = RecordingCaller()
        let source = ServerUIRoomDeviceSource(descriptor: .humidifier(config), store: store, caller: caller)
        #expect(source.infoItem(.water)?.value == "OK")
        #expect(source.infoItem(.timer) == nil)
        #expect(source.infoItem(.temperature) == nil)
        store.replaceAll([
            EntityState(entityId: config.powerEntityId, state: "on"),
            EntityState(entityId: config.timerRemainingEntityId, state: "not-a-number"),
            EntityState(entityId: config.modeEntityId, state: "Manual", attributes: ["options": .array([.string("Manual")])])
        ])
        #expect(source.infoItem(.water) == nil)
        #expect(source.infoItem(.timer) == nil)
        #expect(throws: ServerUIRoomDeviceSource.Failure.unavailable) {
            try source.perform(.humidifierMode, intent: .choose("Sleep"))
        }
        #expect(caller.calls.isEmpty)
    }

    @Test func purifierAndGrillKeepTheirDistinctNativeCommandsAndReadOnlySensors() async throws {
        let caller = RecordingCaller(), scheduler = ManualScheduler()
        let config = AirPurifierConfig(roomTitle: "Synthetic Room", pm25EntityId: "sensor.demo_pm25",
            aqiEntityId: "sensor.demo_aqi", autoModeEntityId: "select.demo_auto",
            fanEntityId: "fan.demo_purifier", modeEntityId: "select.demo_mode")
        let purifier = ServerUIRoomDeviceSource(descriptor: .purifier(config), store: makeStore([
            config.modeEntityId: "Manual", config.autoModeEntityId: "Default", config.fanEntityId: "on"
        ]), caller: caller, scheduler: scheduler)
        try purifier.perform(.purifierSpeed, intent: .choose("66"))
        await purifier.commands.waitForCalls()
        #expect(caller.calls.last == .init(domain: "fan", service: "set_percentage",
                                           data: ["entity_id": config.fanEntityId, "percentage": "66"]))
        scheduler.fireAll()
        #expect(throws: ServerUIRoomDeviceSource.Failure.invalidIntent) { try purifier.perform(.purifierAuto, intent: .choose("Quiet")) }
        let grill = try JSONDecoder().decode(GrillConfig.self, from: Data("""
            {"title":"Synthetic Grill","roomTitle":"Synthetic Room","stateEntityId":"sensor.demo_grill",
             "details":[{"title":"Probe","entityId":"sensor.demo_probe","icon":"thermometer"},
                        {"title":"Warm","entityId":"switch.demo_warm","icon":"flame"}]}
            """.utf8))
        let source = ServerUIRoomDeviceSource(descriptor: .grill(grill), store: makeStore([
            grill.stateEntityId: "cooking", "sensor.demo_probe": "165", "switch.demo_warm": "off"
        ]), caller: caller, scheduler: scheduler)
        #expect(throws: ServerUIRoomDeviceSource.Failure.invalidIntent) {
            try source.perform(.grillDetail, intent: .setOn(true), detailEntityId: "sensor.demo_probe")
        }
        try source.perform(.grillDetail, intent: .setOn(true), detailEntityId: "switch.demo_warm")
        await source.commands.waitForCalls()
        #expect(caller.calls.last == .init(domain: "switch", service: "turn_on", data: ["entity_id": "switch.demo_warm"]))
    }

    @Test func draftsPreserveFailuresAndDeletionRevalidatesTheExactRule() async throws {
        let config = try DeviceLaneFixture.humidifier(), scheduler = ManualScheduler()
        let storage = MemoryScheduleStore([HassSchedule(id: config.scheduleId, name: "Synthetic")])
        let source = ServerUIRoomDeviceSource(descriptor: .humidifier(config), store: humidifierStore(config), caller: RecordingCaller(), storage: storage, scheduler: scheduler)
        try await source.loadSchedules()
        let rule = HumidifierScheduleRule.new(id: "synthetic-night", mode: .manual)
        let draft = ServerUIHumidifierActivityDraft(source: source, rule: rule, isNew: true)
        draft.value.label = "My activity"
        storage.failUpdate = true
        #expect(await !draft.save())
        #expect(draft.isDirty && source.schedules?.rules.isEmpty == true)
        storage.failUpdate = false
        #expect(await draft.save())
        await source.schedules?.waitForCalls()
        scheduler.fireAll()
        let ticket = try source.deletion(for: rule.id)
        var edited = ticket.rule; edited.label = "Changed elsewhere"
        #expect(await source.schedules?.save(edited) == true)
        await #expect(throws: ServerUIRoomDeviceSource.Failure.staleConfirmation) { try await source.delete(ticket) }
        storage.admin = false
        try await source.loadSchedules()
        #expect(throws: ServerUIRoomDeviceSource.Failure.notAdministrator) { try source.deletion(for: rule.id) }
    }
}
