import Foundation
import HassTestSupport
import Testing
@testable import HassCore

// MARK: - Authored domain construction

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ServerUIDeviceProvidersTests {
    func publication() throws -> ServerUICompositionPublication {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ServerUIDeviceProvidersFixture.json")
        return try .decode(Data(contentsOf: url))
    }

    func store() -> EntityStore {
        let store = EntityStore()
        var states: [String: String] = [
            "input_boolean.demo_manual": "on", "input_select.demo_mode": "Custom",
            "light.demo_a": "on", "light.demo_b": "on", "light.demo_group": "on",
            "sensor.demo_sprinkler": "auto", "select.demo_mode": "auto", "sensor.demo_battery": "80",
            "binary_sensor.demo_fault": "off", "binary_sensor.demo_hub": "on",
            "sensor.demo_next": "unknown", "switch.demo_rain": "off", "switch.demo_smart": "on",
            "valve.demo_zone": "closed", "switch.demo_program": "on"
        ]
        states["sensor.demo_history"] = "2026-11-13T10:00:00Z"
        store.replaceAll(states.map { id, state in
            let attributes: [String: JSONValue] = id.hasPrefix("light.")
                ? ["supported_color_modes": ["rgb"], "rgb_color": [.number(1), .number(2), .number(3)]]
                : id == "switch.demo_program" ? SprinklerFixture.program(station: 1, days: [1, 3], times: ["07:00"])
                : id == "valve.demo_zone" ? ["station": .number(1), "zone_name": "Demo zone"] : [:]
            return .init(entityId: id, state: state, attributes: attributes)
        })
        return store
    }

    @Test func constructsAndRetainsProvidersAndRejectsMissingTransportOrCrossStoreReuse() throws {
        let sources = try publication().document.dataSources
        let store = store(), caller = DeviceHeldCaller()
        let original = try ServerUIDeviceProviders(sources: sources, store: store, caller: caller)
        let retained = try ServerUIDeviceProviders(sources: sources, store: store, caller: caller, retaining: original)
        #expect(retained.lights["lights"] === original.lights["lights"])
        #expect(retained.sprinklers["sprinkler"] === original.sprinklers["sprinkler"])
        #expect(throws: ServerUIDeviceProviders.Failure.missingTransport("lights")) {
            try ServerUIDeviceProviders(sources: sources, store: store, caller: nil)
        }
        #expect(throws: ServerUIDeviceProviders.Failure.storeMismatch) {
            try ServerUIDeviceProviders(sources: sources, store: EntityStore(), caller: caller, retaining: original)
        }
        #expect(throws: ServerUIDeviceProviders.Failure.transportMismatch) {
            try ServerUIDeviceProviders(sources: sources, store: store, caller: DeviceHeldCaller(), retaining: original)
        }
        #expect(throws: ServerUIDeviceProviders.Failure.duplicateProvider("lights")) {
            try ServerUIDeviceProviders(sources: sources + [sources[0]], store: store, caller: caller)
        }
    }

    @Test func colorDebouncePinsOriginalTargetAndActualCallBeyondQueuedWork() async throws {
        let store = store(), caller = DeviceHeldCaller()
        let providers = try ServerUIDeviceProviders(sources: publication().document.dataSources, store: store, caller: caller)
        let lights = try #require(providers.lights["lights"])
        lights.setColor(.init(20, 30, 40), on: "light.demo_a")
        lights.setColor(.init(50, 60, 70), on: "light.demo_a")
        #expect(lights.protectsPublication)
        #expect(throws: ServerUIDeviceProviders.Failure.busy("lights")) {
            try ServerUIDeviceProviders(sources: [], store: store, caller: caller, retaining: providers)
        }
        await caller.waitForStart()
        #expect(caller.calls.count == 1)
        #expect(caller.calls[0].target == "light.demo_a")
        #expect(caller.calls[0].color == [50, 60, 70])
        #expect(lights.pendingCalls == 1)
        caller.finish()
        await caller.waitForFinish()
        // The continuation completes before the owning source releases its pending count; await that release.
        await lights.waitForCalls()
        #expect(lights.pendingCalls == 0)
        #expect(!lights.protectsPublication)
    }

    @Test func staleGroupConfirmationCannotUseChangedColorOrUnavailableMember() async throws {
        let store = store(), caller = DeviceHeldCaller()
        let providers = try ServerUIDeviceProviders(sources: publication().document.dataSources, store: store, caller: caller)
        let lights = try #require(providers.lights["lights"])
        let ticket = try #require(lights.confirmation(.applyColor("light.demo_a", .init(1, 2, 3))))
        store.apply([.init(entityId: "light.demo_a", state: "on", attributes: ["rgb_color": [.number(9), .number(8), .number(7)]])])
        #expect(!(await lights.confirm(ticket)))
        #expect(caller.calls.isEmpty)
        #expect(lights.error != nil)
        store.apply([.init(entityId: "light.demo_a", state: "unavailable")])
        #expect(!(await lights.copyColor(from: "light.demo_b", to: "light.demo_a")))
        #expect(caller.calls.isEmpty)
    }

    @Test func explicitVacuumAutoCleanPauseInvertsStateAndOwnsUnfinishedTransport() async {
        let store = EntityStore(), caller = DeviceHeldCaller(), scheduler = ManualScheduler()
        let control = Vacuums.AutoCleanControl(title: "Demo", entityId: "switch.demo_pause", icon: "mdi:robot-vacuum", kind: .pause)
        store.replaceAll([.init(entityId: control.entityId, state: "on")])
        let model = VacuumAutoCleanController(store: store, caller: caller, controls: [control], scheduler: scheduler)
        #expect(!model.display(control).isEnabled)
        model.toggle(control)
        #expect(model.display(control).isEnabled)
        await caller.waitForStart()
        #expect(caller.calls[0].target == control.entityId)
        scheduler.fireAll()
        #expect(model.hasPendingIntent)
        caller.finish(failing: true)
        await model.waitForCalls()
        #expect(!model.hasPendingIntent)
        #expect(model.display(control).isFailed)
    }

    @Test func scheduleOwnsStableRowsRejectsMalformedTimeAndPreservesDraftDuringSave() async throws {
        let store = store(), caller = DeviceHeldCaller()
        let providers = try ServerUIDeviceProviders(sources: publication().document.dataSources, store: store, caller: caller)
        let sprinkler = try #require(providers.sprinklers["sprinkler"])
        let draft = try #require(sprinkler.draft(0))
        let rowID = try #require(draft.value.times.first?.id)
        draft.update { $0.times[0].value = "08:00:30" }
        #expect(!draft.canSave)
        draft.update { $0.times[0].value = "08:00" }
        #expect(draft.canSave)
        draft.reload()
        #expect(draft.value.times[0].value == "08:00")
        #expect(draft.error != nil)
        let save = Task { await draft.save() }
        await caller.waitForStart()
        #expect(draft.busy && providers.protectsPublication)
        draft.update { $0.budget = 150 }
        #expect(draft.value.budget == 100)
        #expect(draft.value.times[0].id == rowID)
        caller.finish(failing: true)
        #expect(!(await save.value))
        #expect(draft.dirty && draft.error != nil)
        draft.discard()
        #expect(draft.value.times[0].value == "07:00")
        #expect(draft.value.times[0].id == rowID)
    }

    @Test func configuredRemoteKeepsPageCardKeysSeparateAndKeyboardPinsPublication() throws {
        try HouseConfigSource.$scoped.withValue(ServerUIRemoteTestProvider.houseSource()) { try remoteBody() }
    }

    private func remoteBody() throws {
        let config = ServerUIRemoteTestProvider.config()
        let card = ServerUIRemoteDescriptor.Card(key: "page-player", configuration: config.devices[0])
        let descriptor = ServerUIRemoteDescriptor(configuration: config, cards: [card])
        let decoded = try ServerUIDeviceProviderDescriptor.decode(model: "media-remote-config@1", data: JSONEncoder().encode(descriptor))
        #expect(ServerUIDeviceProviderValidation.validate(decoded, at: "").isEmpty)
        let source = ServerUICompositionDocument.Source.deviceProvider(id: "remote", descriptor: decoded)
        let store = ServerUIRemoteTestProvider.store(), caller = DeviceHeldCaller()
        let providers = try ServerUIDeviceProviders(sources: [source], store: store, caller: caller)
        let remote = try #require(providers.remotes["remote"])
        #expect(remote.controller.config.devices.map(\.title) == ["Demo player", "page-player"])
        try remote.press(.keyboard)
        remote.keyboardText = "draft"
        #expect(throws: ServerUIDeviceProviders.Failure.busy("remote")) {
            try ServerUIDeviceProviders(sources: [], store: store, caller: caller, retaining: providers)
        }
        #expect(try ServerUIDeviceProviders(sources: [source], store: store, caller: caller, retaining: providers).remotes["remote"] === remote)
    }

    @Test func pageCardResolverRequiresEveryObservedStateTarget() {
        let config = ServerUIRemoteTestProvider.config()
        var card = config.devices[0]
        card.stateResolver = .configuredConsole(cloudEntityId: "sensor.demo_cloud", hdmiEntityId: "sensor.demo_hdmi",
            tvEntityId: "media_player.demo_tv", powerEntityId: "switch.demo_console", inputEntityId: "sensor.demo_input",
            activeStates: ["on"], inputSuffix: "Console", linkedState: "linked")
        let descriptor = ServerUIRemoteDescriptor(configuration: config, cards: [.init(key: "console-card", configuration: card)])
        #expect(ServerUIDeviceProviderValidation.validate(.remote(descriptor), at: "/inputs").contains {
            $0.pointer == "/inputs/cards/0/configuration/stateEntityIds"
        })
    }

    @Test(.demoHouse) func alarmEditorIsRetainedByVisitAndReadOnlyRowsReflectLiveSource() throws {
        let b = DemoHouse.config.bedroom
        let descriptor = ServerUIBedroomDescriptor(wakeProviderId: "demo-wake", beds: b.beds.map {
            .init(providerId: "demo-" + $0.side.rawValue, configuration: $0)
        }, environment: .init(scheduleEntityId: b.scheduleEntityId, scheduleSetTopic: b.scheduleSetTopic,
            hotFlashBrokerScript: b.hotFlashBrokerScript, householdAwayEntityId: b.householdAwayEntityId,
            householdAwayScript: b.householdAwayScript, wakeLight: b.wakeLight))
        let store = bedroomStore(bedEntities()), caller = ResponseCaller()
        let session = ServerUIBedroomSession(descriptor: descriptor, store: store, caller: caller, canEdit: true)
        let rows = try #require(session.alarms["demo-left"])
        #expect(rows.rows(day: .monday).count == 1)
        let draft = try session.editor(providerId: "demo-left", route: .addBed(.monday), visitId: "visit")
        #expect(try session.editor(providerId: "demo-left", route: .addBed(.monday), visitId: "visit") === draft)
        #expect(!draft.blocksExit)
        #expect(throws: ServerUIBedroomSession.Failure.editorBusy) { try session.release(draft) }
        store.apply([.init(entityId: b.scheduleEntityId, state: "ok", attributes: ["left": .object([:]), "right": .object([:])])])
        #expect(rows.rows(day: .monday).isEmpty)
        #expect(session.protectsPublication)
        session.retire(draft)
        #expect(draft.completed)
        #expect(session.editors.isEmpty)
        let wake = try session.editor(providerId: "demo-wake", route: .addWake, visitId: "wake-visit")
        guard case .wake(let alarm) = wake.value else { Issue.record("Missing wake draft"); return }
        #expect(alarm.kind == .weekly && alarm.weekdays == Weekday.workdays && alarm.date == nil)
        #expect(wake.protectsPublication && !wake.blocksExit)
        session.retire(wake)
        #expect(wake.completed && !session.protectsPublication)
        #expect(session.editors.isEmpty)
    }

    @Test(.demoHouse) func wakeAlarmSaveDoesNotClaimSuccessWhenBedProvisioningFails() async {
        let caller = DeviceProvisioningFailure()
        let room = BedroomDevices(store: bedroomStore(bedEntities()), caller: caller)
        var alarm = WakeLight.Alarm.new(id: "new-alarm", now: .now, defaults: .standard)
        alarm.kind = .weekly
        alarm.weekdays = [.monday]
        alarm.localTime = "08:17"
        #expect(!(await room.saveWakeAlarm(alarm, isNew: true, addToBeds: [.left])))
        #expect(caller.bedCalls == 1)
        #expect(room.bed(.left).commandError != nil)
    }

    @Test func bedroomConstructsWithoutHouseGlobalLookupsAndRequiresExplicitResponder() throws {
        let b = DemoHouse.config.bedroom
        let descriptor = ServerUIBedroomDescriptor(wakeProviderId: "demo-wake", beds: b.beds.map {
            .init(providerId: "demo-" + $0.side.rawValue, configuration: $0)
        }, environment: .init(scheduleEntityId: b.scheduleEntityId, scheduleSetTopic: b.scheduleSetTopic,
            hotFlashBrokerScript: b.hotFlashBrokerScript, householdAwayEntityId: b.householdAwayEntityId,
            householdAwayScript: b.householdAwayScript, wakeLight: b.wakeLight))
        #expect(ServerUIDeviceProviderValidation.validate(.bedroom(descriptor), at: "").isEmpty)
        let source = ServerUICompositionDocument.Source.deviceProvider(id: "bedroom", descriptor: .bedroom(descriptor))
        let providers = try ServerUIDeviceProviders(sources: [source], store: EntityStore(), caller: nil,
            responder: DeviceHeldCaller(), canEditBedroom: false)
        let room = try #require(providers.bedrooms["bedroom"])
        #expect(room.devices.beds.count == 2)
        #expect(room.collections["demo-left.day.monday"] != nil)
        #expect(!room.devices.wakeLight.canEdit)
        #expect(throws: ServerUIDeviceProviders.Failure.missingTransport("bedroom")) {
            try ServerUIDeviceProviders(sources: [source], store: EntityStore(), caller: nil)
        }
    }

    @Test func suppliedPrivateRecipeHasExactNativeCapabilityClosure() throws {
        guard let path = ProcessInfo.processInfo.environment["SDUI_DEVICE_RECIPE"] else { return }
        let value = try ServerUICompositionPublication.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        #expect(value.document.pages.count > 16)
        #expect(value.document.dataSources.count > 100)
    }
}

// MARK: - Network-isolated acknowledged transport

@MainActor
private final class DeviceProvisioningFailure: HassServiceResponding {
    var bedCalls = 0
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        bedCalls += 1
        throw ResponseCaller.Failure()
    }
    func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        .object(["outcome": "accepted"])
    }
}

@MainActor
private final class DeviceHeldCaller: HassServiceResponding {
    struct Call { let target: String?; let color: [Int]? }
    struct Rejected: Error {}
    var calls: [Call] = []
    private var completion: CheckedContinuation<Void, any Error>?
    private var started: CheckedContinuation<Void, Never>?
    private var finished: CheckedContinuation<Void, Never>?
    private var didFinish = false

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        calls.append(.init(target: data["entity_id"] as? String, color: (data["rgb_color"] as? [any Sendable])?.compactMap { $0 as? Int }))
        defer { didFinish = true; finished?.resume(); finished = nil }
        try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            started?.resume(); started = nil
        }
    }
    func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        try await callService(domain, service, data: data)
        return .object([:])
    }
    func waitForStart() async {
        if completion != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func waitForFinish() async {
        if didFinish { return }
        await withCheckedContinuation { finished = $0 }
    }
    func finish(failing: Bool = false) {
        if failing { completion?.resume(throwing: Rejected()) } else { completion?.resume() }
        completion = nil
    }
}
