import Foundation
import HassTestSupport
import Testing
@testable import HassCore

private extension JSONValue {
    var dictionary: [String: JSONValue]? { if case .object(let value) = self { value } else { nil } }
}

// MARK: - Remote wire acceptance

@Suite struct ServerUIRemoteContractTests {
    typealias E = ServerUICompositionError

    func fixture() throws -> JSONValue {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ServerUIRemoteFixture.json")
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }

    func decode(_ value: JSONValue) throws -> ServerUICompositionPublication {
        try .decode(JSONEncoder().encode(value))
    }

    @Test func allAtomicVariantsHaveExactNarrowCapabilitiesAndAuthoredAppearance() throws {
        let publication = try decode(fixture())
        #expect(publication.document.pages[0].surface.components.count == 11)
        #expect(publication.capabilities.count == 19)
        guard case .remote(let remote) = publication.document.pages[0].surface.components[0],
              case .keys(_, let label, let keys) = remote.control else { Issue.record("Expected configured pad"); return }
        #expect(label == "Demo remote")
        #expect(keys.map(\.position) == [2, 1, 8, 4])
        #expect(keys.last?.icon == nil)
        #expect(keys[2].activeText == "Expanded")
        #expect(remote.sourceId == "source-demo")
        #expect(publication.capabilities.contains("sh.remote-card@1"))
        #expect(!publication.capabilities.contains("sh.tiles@1"))
        #expect(!publication.capabilities.contains("sh.power-toggle@1"))
    }

    @Test func rejectsExecutableDataInvalidSlotsRetargetingAndUnsupportedCapabilities() throws {
        let root = try fixture()
        var object = try #require(root.dictionary)
        var document = try #require(object["document"]?.dictionary)
        let originalPages = try #require(document["pages"]?.array)
        var page = try #require(originalPages[0].dictionary)
        let originalNodes = try #require(page["components"]?.array)
        func mutation(_ index: Int, _ field: String, _ replacement: JSONValue, _ code: E.Code, _ suffix: String) throws {
            var nodes = originalNodes
            var node = try #require(nodes[index].dictionary)
            var props = try #require(node["props"]?.dictionary)
            props[field] = replacement
            node["props"] = .object(props)
            nodes[index] = .object(node)
            page["components"] = .array(nodes)
            document["pages"] = .array([.object(page)])
            object["document"] = .object(document)
            #expect(throws: E(code, "/document/pages/0/components/\(index)/props/\(suffix)")) {
                try decode(.object(object))
            }
        }
        try mutation(0, "service", "remote.send_command", .unknownField, "service")
        var keys = try #require(originalNodes[0]["props"]?["keys"]?.array)
        var first = try #require(keys[0].dictionary)
        first["slot"] = "play"
        keys[0] = .object(first)
        try mutation(0, "keys", .array(keys), .invalidCombination, "keys/0/slot")
        first["slot"] = "power"
        first["position"] = .number(1)
        keys[0] = .object(first)
        try mutation(0, "keys", .array(keys), .invalidCombination, "keys/1/position")
        let choice: JSONValue = .object(["value": "game", "label": "Game"])
        try mutation(7, "options", .array([choice, choice]), .invalidCombination, "options/1/value")
        try mutation(7, "options", .array([]), .invalidCombination, "options")
        try mutation(10, "action", .object(["type": "back"]), .unknownVariant, "action/type")
        try mutation(5, "family", "power", .invalidCombination, "family")
        try mutation(5, "personalization",
                     .object(["residentId": "demo-resident", "ownTitle": "Your PC", "otherTitle": "Demo PC"]),
                     .invalidCombination, "personalization")
        var without = try #require(root.dictionary)
        without["capabilities"] = .array(try #require(root["capabilities"]?.array).filter { $0 != "sh.remote-app@1" })
        #expect(throws: E(.capabilityManifestMismatch, "/capabilities")) { try decode(.object(without)) }
    }

    @Test func remoteBindingsRejectOrdinaryEntitySources() throws {
        var root = try #require(fixture().dictionary)
        var document = try #require(root["document"]?.dictionary)
        document["dataSources"] = .array([.object([
            "id": "source-demo", "kind": "ha-entity", "entityId": .object(["type": "literal", "value": "media_player.demo_unit"])
        ])])
        root["document"] = .object(document)
        #expect(throws: E(.bindingType, "/document/pages/0/components/0/binding/sourceId")) { try decode(.object(root)) }
    }
}

// MARK: - Synthetic injected controller

@MainActor
enum ServerUIRemoteTestProvider {
    static func config() -> MediaRemoteConfig {
        func key(_ command: String) -> MediaRemoteButton {
            .init(command, icon: "", action: .service("remote", "send_command", target: "remote.demo_unit",
                                                     data: ["command": .string(command)]))
        }
        let hue = HueSyncConfig(powerEntityId: "switch.demo_hue_power", lightSyncEntityId: "switch.demo_hue_sync",
                                syncModeEntityId: "select.demo_mode", intensityEntityId: "select.demo_intensity",
                                brightnessEntityId: "number.demo_brightness", hdmiInputEntityId: "select.demo_input",
                                hdmiStatusEntityIds: ["sensor.demo_input"])
        return .init(id: "demo-provider", title: "Demo", roomTitle: "Demo", remoteTitle: "Demo",
                     mediaEntityId: "media_player.demo_unit", controlEntityId: "media_player.demo_unit",
                     power: key("POWER"), up: key("UP"), left: key("LEFT"), select: key("SELECT"), right: key("RIGHT"),
                     down: key("DOWN"), back: key("BACK"), home: key("HOME"),
                     keyboard: .init("Text", icon: "", action: .command(.textPrompt(targetEntityId: "media_player.demo_unit"))),
                     pause: key("PAUSE"), play: key("PLAY"), volumeTitle: "Demo speaker", volumeEntityId: "media_player.demo_speaker",
                     volumeDown: key("DOWN_VOLUME"), volumeMute: key("MUTE"), volumeUp: key("UP_VOLUME"),
                     apps: [.init("Demo app", action: .service("script", "demo_app"), stateEntityId: "media_player.demo_unit", activeStates: ["playing"])],
                     devices: [.init("Demo player", entityId: "media_player.demo_unit", icon: "", action: .service("remote", "send_command",
                                      target: "remote.demo_unit", data: ["command": "POWER"]), semantics: .toggleOnUnless(["off"]))],
                     lightSync: hue, optimisticEntityIds: [hue.powerEntityId, hue.lightSyncEntityId, hue.syncModeEntityId,
                                                           hue.intensityEntityId, hue.brightnessEntityId, hue.hdmiInputEntityId])
    }

    /// A house document whose remotes declare the synthetic config plus `scripts`, the only scripts a published remote may name.
    static func houseSource(scripts: [String] = ["demo_mute", "demo_unmute"]) -> HouseConfigSource {
        var house = DemoHouse.config
        var remote = config()
        remote.apps += scripts.map { .init($0, action: .service("script", $0)) }
        house.media.remotes = [remote]
        let source = HouseConfigSource()
        source.set(house)
        return source
    }

    static func store() -> EntityStore {
        let store = EntityStore()
        store.replaceAll([
            .init(entityId: "media_player.demo_unit", state: "playing"),
            .init(entityId: "media_player.demo_speaker", state: "on", attributes: ["volume_level": .number(0.2)]),
            .init(entityId: "switch.demo_hue_power", state: "on"), .init(entityId: "switch.demo_hue_sync", state: "on"),
            .init(entityId: "select.demo_mode", state: "video", attributes: ["options": ["video", "game"]]),
            .init(entityId: "select.demo_intensity", state: "low", attributes: ["options": ["low", "high"]]),
            .init(entityId: "number.demo_brightness", state: "50", attributes: ["min": .number(1), "max": .number(100), "step": .number(1)]),
            .init(entityId: "select.demo_input", state: "HDMI 1", attributes: ["options": ["HDMI 1"]]),
            .init(entityId: "sensor.demo_input", state: "connected")
        ])
        return store
    }
}

@MainActor
private final class RemoteSuspendingCaller: HassServiceCalling {
    private var completion: CheckedContinuation<Void, Error>?
    private var started: CheckedContinuation<Void, Never>?
    var command: String?
    var target: String?
    struct Failure: Error {}

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        command = data["command"] as? String
        target = data["entity_id"] as? String
        try await withCheckedThrowingContinuation {
            completion = $0
            started?.resume()
            started = nil
        }
    }

    func waitForStart() async {
        if completion != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(failing: Bool = false) {
        let continuation = completion
        completion = nil
        if failing { continuation?.resume(throwing: Failure()) } else { continuation?.resume() }
    }
}

// MARK: - Interaction and command lifetimes

@MainActor
@Suite struct ServerUIRemoteSessionTests {
    @Test func validatedHueAndVolumeIntentsPreserveProjectionsAndRejectStaleOptions() async throws {
        let caller = RecordingCaller(), store = ServerUIRemoteTestProvider.store()
        let controller = MediaRemoteController(config: ServerUIRemoteTestProvider.config(), store: store, caller: caller, scheduler: ManualScheduler())
        let session = ServerUIRemoteSession(controller: controller)
        try session.toggleHue(.power)
        #expect(controller.displayedState("switch.demo_hue_power") == "off")
        #expect(controller.displayedState("switch.demo_hue_sync") == "off")
        try session.toggleHue(.lightSync)
        #expect(controller.displayedState("switch.demo_hue_power") == "on")
        #expect(controller.displayedState("switch.demo_hue_sync") == "on")
        try session.chooseHue(.intensity, value: "high", allowed: ["low", "high"])
        #expect(controller.displayedState("select.demo_intensity") == "high")
        try session.chooseHue(.mode, value: "game", allowed: ["game", "video"])
        #expect(controller.displayedState("select.demo_intensity") == "low")
        #expect(controller.displayedState("select.demo_mode") == "game")
        #expect(throws: ServerUIRemoteSession.InteractionError.unavailable) {
            try session.chooseHue(.mode, value: "music", allowed: ["music"])
        }
        #expect(throws: ServerUIRemoteSession.InteractionError.unavailable) { try session.setHueBrightness(.infinity) }
        try session.setHueBrightness(72)
        try session.setVolume(percent: 45)
        #expect(controller.volumePercent == 45)
        store.apply([.init(entityId: "sensor.demo_input", state: "unplugged")])
        #expect(throws: ServerUIRemoteSession.InteractionError.unavailable) { try session.selectHueInput("HDMI 1") }
        await controller.waitForCalls()
        #expect(caller.names == ["switch.turn_off", "switch.turn_on", "select.select_option", "select.select_option", "number.set_value", "media_player.volume_set"])
        #expect(caller.raw[4]["value"] as? Int == 72)
    }

    @Test func commandWithoutOptimisticWritesStillPinsActualLifetimeAndRevalidatesOffState() async throws {
        let store = ServerUIRemoteTestProvider.store(), caller = RemoteSuspendingCaller()
        let controller = MediaRemoteController(config: ServerUIRemoteTestProvider.config(), store: store, caller: caller)
        let session = ServerUIRemoteSession(controller: controller)
        try session.press(.up)
        #expect(session.hasInteraction)
        await caller.waitForStart()
        #expect(caller.command == "UP")
        #expect(controller.pendingCallCount == 1)
        caller.finish(failing: true)
        await controller.waitForCalls()
        #expect(!session.hasInteraction)
        #expect(controller.lastCommandFailed)
        store.apply([.init(entityId: "media_player.demo_unit", state: "off")])
        #expect(throws: ServerUIRemoteSession.InteractionError.unavailable) { try session.press(.up) }
        #expect(session.isEnabled(.power))
    }

    @Test func keyboardPinsEscapedTextAndTargetAndRetainsDraftOnRejection() async throws {
        let caller = RemoteSuspendingCaller()
        let controller = MediaRemoteController(config: ServerUIRemoteTestProvider.config(), store: ServerUIRemoteTestProvider.store(), caller: caller)
        let session = ServerUIRemoteSession(controller: controller)
        try session.press(.keyboard)
        session.keyboardText = "it's a test"
        let send = Task { @MainActor in try await session.submitKeyboard() }
        await caller.waitForStart()
        #expect(session.keyboardSending)
        #expect(caller.target == "media_player.demo_unit")
        #expect(caller.command == MediaRemoteState.textInputCommand("it's a test"))
        #expect(throws: ServerUIRemoteSession.InteractionError.busy) { try session.cancelKeyboard() }
        await #expect(throws: ServerUIRemoteSession.InteractionError.busy) { try await session.submitKeyboard() }
        caller.finish(failing: true)
        await #expect(throws: RemoteSuspendingCaller.Failure.self) { try await send.value }
        #expect(session.keyboardText == "it's a test")
        #expect(session.keyboardTarget == "media_player.demo_unit")
        #expect(session.keyboardFailed)
        #expect(session.hasInteraction)
        try session.cancelKeyboard()
        #expect(!session.hasInteraction)
    }

    @Test func acknowledgedKeyboardSuccessClearsDraftButBlankTextSendsNothing() async throws {
        let caller = RecordingCaller()
        let session = ServerUIRemoteSession(controller: .init(config: ServerUIRemoteTestProvider.config(),
                                                               store: ServerUIRemoteTestProvider.store(), caller: caller))
        try session.press(.keyboard)
        session.keyboardText = "  "
        await #expect(throws: ServerUIRemoteSession.InteractionError.blankText) { try await session.submitKeyboard() }
        #expect(caller.calls.isEmpty)
        session.keyboardText = "hello"
        try await session.submitKeyboard()
        #expect(session.keyboardTarget == nil)
        #expect(session.keyboardText.isEmpty)
        #expect(!session.hasInteraction)
        #expect(caller.names == ["androidtv.adb_command"])
    }

    @Test func stateDependentCardActionsUseAuthoredOrderAndRevalidateBeforeSending() async throws {
        let publication = try ServerUIRemoteContractTests().decode(ServerUIRemoteContractTests().fixture())
        guard case .remote(let card) = publication.document.pages[0].surface.components[10],
              case .card(_, _, _, _, _, _, let appearances, _, _, _) = card.control else { Issue.record("Expected card"); return }
        let store = ServerUIRemoteTestProvider.store(), caller = RecordingCaller(), clock = ManualScheduler()
        let controller = MediaRemoteController(config: ServerUIRemoteTestProvider.config(), store: store, caller: caller, scheduler: clock)
        let session = ServerUIRemoteSession(controller: controller)
        let actions = session.cardActions(appearances)
        #expect(actions.map(\.id) == ["previous", "play_pause", "next"])
        let pause = try #require(actions.first { $0.id == "play_pause" })
        #expect(pause.verb == "Pause")
        try session.performCard(pause, appearances: appearances)
        #expect(session.cardActions(appearances).first { $0.id == "play_pause" }?.verb == "Play")
        #expect(throws: ServerUIRemoteSession.InteractionError.unavailable) { try session.performCard(pause, appearances: appearances) }
        await controller.waitForCalls()
        #expect(caller.calls.first?.data["command"] == "PAUSE")
        store.apply([.init(entityId: "media_player.demo_unit", state: "off")])
        controller.liveDidChange()
        #expect(session.cardActions(appearances).map(\.id) == ["power"])
    }

    @Test func cardPowerRunsTheRevalidatedProviderCallNotASecondResolutionOnTheControlEntity() async throws {
        let publication = try ServerUIRemoteContractTests().decode(ServerUIRemoteContractTests().fixture())
        guard case .remote(let card) = publication.document.pages[0].surface.components[10],
              case .card(_, _, _, _, _, _, let appearances, _, _, _) = card.control else { Issue.record("Expected card"); return }
        var config = ServerUIRemoteTestProvider.config()
        config.controlEntityId = "remote.demo_control"
        config.power.action = .state(entityId: nil, cases: [.init(["off"], .service(ServiceCall("remote", "turn_on", target: "remote.demo_unit")))],
                                     otherwise: .service(ServiceCall("remote", "turn_off", target: "remote.demo_unit")))
        let store = ServerUIRemoteTestProvider.store(), caller = RecordingCaller()
        store.apply([.init(entityId: "media_player.demo_unit", state: "off"), .init(entityId: "remote.demo_control", state: "on")])
        let session = ServerUIRemoteSession(controller: .init(config: config, store: store, caller: caller))
        let spec = try #require(session.cardActions(appearances).first)
        try session.performCard(spec, appearances: appearances)
        await session.controller.waitForCalls()
        #expect(caller.names == ["remote.turn_on"])
    }
}
