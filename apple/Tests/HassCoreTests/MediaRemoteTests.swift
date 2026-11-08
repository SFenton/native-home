import Foundation
@testable import HassCore
import HassTestSupport
import Testing

// MARK: - Test doubles

// `RecordingCaller` and `ManualScheduler` live in `Tests/HassTestSupport`.

@MainActor
func makeStore(_ states: [String: String], attributes: [String: [String: JSONValue]] = [:]) -> EntityStore {
    let store = EntityStore()
    store.replaceAll(states.map { EntityState(entityId: $0.key, state: $0.value, attributes: attributes[$0.key] ?? [:]) })
    return store
}

func set(_ store: EntityStore, _ id: String, _ state: String, _ attributes: [String: JSONValue]? = nil) {
    MainActor.assumeIsolated {
        var entity = store.value(id) ?? EntityState(entityId: id, state: state)
        entity.state = state
        if let attributes { entity.attributes = attributes }
        store.apply([entity])
    }
}

// MARK: - Logic

@Suite(.demoHouse)
struct MediaRemoteStateTests {
    @Test func unavailableAndOff() {
        #expect(EntityState.isUnavailable(nil))
        #expect(EntityState.isUnavailable("unknown"))
        #expect(EntityState.isUnavailable("unavailable"))
        #expect(!EntityState.isUnavailable("off"))
        #expect(MediaRemoteState.isOff("off"))
        #expect(MediaRemoteState.isOff(nil))
        #expect(!MediaRemoteState.isOff("standby"))
    }

    @Test func titleCaseAndFormat() {
        #expect(StateText.titleCase("armed_away") == "Armed Away")
        #expect(StateText.titleCase("linked") == "Linked")
        #expect(StateText.titleCase(nil) == "Unknown")
        #expect(StateText.titleCase("") == "Unknown")
        #expect(MediaRemoteState.format(nil) == "Unavailable")
        #expect(MediaRemoteState.format("unavailable") == "Unavailable")
        #expect(MediaRemoteState.format("unknown") == "Unknown")
        #expect(MediaRemoteState.format("playing") == "Playing")
    }

    /// `input text '<value>'` with each `'` written as `'\''` (web `textInputCommand`).
    @Test func textPromptEscapesQuotes() {
        #expect(MediaRemoteState.textInputCommand("hello") == "input text 'hello'")
        #expect(MediaRemoteState.textInputCommand("it's") == #"input text 'it'\''s'"#)
        #expect(MediaRemoteState.textInputCommand("''") == #"input text ''\'''\'''"#)
        #expect(MediaRemoteState.textInputCommand("a b") == "input text 'a b'")
    }

    @Test func activeStates() {
        #expect(MediaRemoteState.isActive("playing", activeStates: []))
        #expect(!MediaRemoteState.isActive("off", activeStates: []))
        #expect(MediaRemoteState.isActive("Server", activeStates: ["Server"]))
        #expect(!MediaRemoteState.isActive("TV", activeStates: ["Server"]))
    }

    @Test func syncModesOrderAndIcons() {
        #expect(MediaRemoteState.orderedSyncModes(["video", "passthrough", "game", "Music"]) == ["Music", "video", "game", "passthrough"])
        #expect(MediaRemoteState.orderedSyncModes(["b", "a"]) == ["b", "a"])
        #expect(MediaRemoteState.syncModeIcon("GAME") == "mdi:gamepad-variant")
        #expect(MediaRemoteState.syncModeIcon("music") == "mdi:music")
        #expect(MediaRemoteState.syncModeIcon("video") == "mdi:movie-open")
        #expect(MediaRemoteState.syncModeIcon("passthrough") == "mdi:lightbulb-multiple")
    }

    @Test func numbersPrintLikeJavaScript() {
        #expect(MediaRemoteState.numberString(50) == "50")
        #expect(MediaRemoteState.numberString(12.5) == "12.5")
    }

    @Test func jsonValuesBecomeSerializableFoundationValues() throws {
        let data: [String: JSONValue] = [
            "a": .string("x"), "b": .number(2), "c": .number(0.25), "d": .bool(true),
            "e": .array([.string("media_player.demo_media_player_3")]), "f": .object(["g": .number(1)]), "h": .null,
        ]
        let foundation = data.mapValues(\.foundationValue)
        #expect(foundation["b"] as? Int == 2)
        #expect(foundation["c"] as? Double == 0.25)
        #expect(foundation["d"] as? Bool == true)
        #expect(JSONSerialization.isValidJSONObject(foundation as [String: Any]))
    }
}

@Suite(.demoHouse)
struct SemanticsRuleTests {
    @Test func rules() {
        #expect(SemanticsRule.toggleOnUnless(["off"]).semantics(for: "on") == .toggle(isOn: true))
        #expect(SemanticsRule.toggleOnUnless(["off"]).semantics(for: "off") == .toggle(isOn: false))
        #expect(SemanticsRule.toggleOnUnless(["off"]).semantics(for: nil) == .toggle(isOn: false))
        #expect(SemanticsRule.toggleOnWhen(["on", "playing"]).semantics(for: "playing") == .toggle(isOn: true))
        #expect(SemanticsRule.toggleOnWhen(["on"]).semantics(for: nil) == .toggle(isOn: false))
        #expect(SemanticsRule.selectedWhen(["Server"]).semantics(for: "Server") == .selection(isSelected: true))
        #expect(SemanticsRule.selectedWhen(["Server"]).semantics(for: nil) == .selection(isSelected: false))
        #expect(SemanticsRule.state.semantics(for: "on") == .state)
    }
}

// MARK: - Action resolution

@Suite(.demoHouse)
struct ActionResolutionTests {
    let tvOn = MediaRemoteCommand.service(ServiceCall("script", "on"))
    let tvOff = MediaRemoteCommand.service(ServiceCall("script", "off"))

    @Test func stateActionPicksTheMatchingCase() {
        let action = MediaRemoteAction.state(entityId: "media_player.demo_tv", cases: [.init(["off", "unavailable"], tvOn)], otherwise: tvOff)
        #expect(action.resolve { _ in "off" } == tvOn)
        #expect(action.resolve { _ in "unavailable" } == tvOn)
        #expect(action.resolve { _ in "on" } == tvOff)
        #expect(action.resolve { _ in nil } == tvOff, "No state takes the default")
    }

    @Test func stateActionFallsBackToTheControlsEntityAndOverride() {
        let action = MediaRemotes.pcPowerAction(on: "input_button.demo_on", off: "input_button.demo_off")
        let pressOff = MediaRemoteCommand.service(ServiceCall("input_button", "press", target: "input_button.demo_off"))
        let pressOn = MediaRemoteCommand.service(ServiceCall("input_button", "press", target: "input_button.demo_on"))
        #expect(action.resolve(entityId: "input_boolean.demo_pc") { $0 == "input_boolean.demo_pc" ? "on" : nil } == pressOff)
        #expect(action.resolve(entityId: "input_boolean.demo_pc") { _ in "off" } == pressOn)
        #expect(action.resolve { _ in "on" } == pressOn, "No entity at all takes the default")
        #expect(action.resolve(entityId: "input_boolean.demo_pc", stateOverride: "on") { _ in "off" } == pressOff)
    }

    @Test func commandActionsResolveToThemselves() {
        #expect(MediaRemoteAction.command(tvOn).resolve { _ in nil } == tvOn)
    }

    @Test func iconColorRuleIsRedUnlessEveryEntityIsInactive() {
        let rule = IconColorRule(entityIds: ["a", "b"], inactiveStates: ["off"], inactiveStatesByEntity: ["b": ["standby"]])
        #expect(rule.tone { ["a": "off", "b": "standby"][$0] } == .inactive)
        #expect(rule.tone { ["a": "off", "b": "off"][$0] } == .active)
        #expect(rule.tone { ["a": "on", "b": "standby"][$0] } == .active)
        #expect(rule.tone { ["a": "off"][$0] } == .active, "A missing state counts as active")
    }
}

// MARK: - Configs

@Suite(.demoHouse)
struct MediaRemoteConfigTests {
    private func remote(_ id: String) throws -> MediaRemoteConfig {
        try #require(MediaRemotes.config(id: id))
    }

    @Test func everyRemoteIsReachable() {
        #expect(MediaRemotes.all.map(\.id) == ["living-room-streamer", "bedroom-1-streamer-tv", "media-room-streamer", "studio-remote"])
        #expect(MediaRemotes.config(id: "#media-room-streamer")?.title == "Media room STREAMER")
        #expect(MediaRemotes.config(id: "nope") == nil)
        #expect(MediaRemotes.config(forMediaPlayer: "media_player.demo_media_player_2")?.id == "media-room-streamer")
        #expect(MediaRemotes.config(forMediaPlayer: "media_player.demo_living_room_1")?.id == "living-room-streamer")
        #expect(MediaRemotes.config(forMediaPlayer: "media_player.demo_nope") == nil)
    }

    @Test func tabsOnlyWithContent() throws {
        #expect(try remote("living-room-streamer").tabs == [.controls, .apps])
        #expect(try remote("bedroom-1-streamer-tv").tabs == [.controls, .apps])
        #expect(try remote("media-room-streamer").tabs == [.controls, .apps, .devices])
        #expect(try remote("studio-remote").tabs == [.controls, .apps, .devices, .hueSync])
        #expect(MediaRemoteTab.allCases.map(\.title) == ["Remote", "Apps", "Devices", "Hue Sync"])
    }

    /// Service calls match the demo document verbatim.
    @Test func livingRoomRemoteCalls() throws {
        let config = try remote("living-room-streamer")
        let target = "remote.demo_living_room_1"
        #expect(config.up.action == .service("remote", "demo_send_command", target: target, data: ["command": "DPAD_UP"]))
        #expect(config.select.action == .service("remote", "demo_send_command", target: target, data: ["command": "DPAD_CENTER"]))
        #expect(!config.select.hasIcon, "The streamer's select is blank")
        #expect(config.back.iconRotationDegrees == 90)
        #expect(config.power.action == .service("remote", "demo_send_command", target: target, data: ["command": "POWER"]))
        #expect(config.power.iconColorRule?.inactiveStates == ["off", "unavailable", "unknown"])
        #expect(config.keyboard?.action == .command(.textPrompt(targetEntityId: "media_player.demo_living_room_2")))
        #expect(config.volumeMute.action == .service("script", "demo_toggle_speaker_mute", data: ["speakerdevice": .array(["media_player.demo_media_player_3"])]))
        #expect(config.volumeUp.action == .service("media_player", "demo_volume_up", target: "media_player.demo_media_player_3"))
        #expect(config.apps.map(\.title) == ["Streaming A", "Streaming B", "Streaming C", "Streaming D", "Streaming E", "Streaming F"])
        #expect(config.apps[0].action == .service("script", "demo_launch_app_on_media_player", data: [
            "entity": "media_player.demo_living_room_1", "remote_entity": .string(target), "app_id": "com.streamapp.player",
        ]))
        #expect(!config.showVolumeWhenOff)
    }

    @Test func streamerTVCalls() throws {
        let config = try remote("bedroom-1-streamer-tv")
        let target = "remote.demo_bedroom_1_1"
        #expect(config.up.action == .service("remote", "demo_send_command", target: target, data: ["command": "up"]),
                "Presses skip the single-mode script so fast presses aren't dropped")
        #expect(config.select.action == .service("remote", "demo_send_command", target: target, data: ["command": "select"]))
        #expect(config.keyboard == nil)
        #expect(config.power.action == .service("script", "demo_streamer_tv_power_on_off"))
        #expect(config.volumeEntityId == "media_player.demo_media_player_4")
        #expect(config.apps.first?.action == .service("script", "demo_launch_app_on_streamer_tv", data: [
            "entity": "media_player.demo_bedroom_1_1", "app_name": "Streaming A", "remote_entity": .string(target),
        ]))
    }

    @Test func mediaRoomCalls() throws {
        let config = try remote("media-room-streamer")
        #expect(config.power.action == .service("script", "demo_room_power_toggle"))
        #expect(config.volumeMute.action == .service("media_player", "demo_volume_mute", target: "media_player.demo_media_player_5", data: ["is_volume_muted": true]))
        #expect(config.showVolumeWhenOff)
        #expect(config.apps[0].action == .service("script", "demo_launch_app_on_media_player", data: [
            "entity": "media_player.demo_media_room_1", "remote_entity": "remote.demo_remote_1",
            "app_id": "com.streamapp.player", "turn_on_projector": true,
        ]))
        #expect(config.devices.map(\.title) == ["Projector", "Receiver", "Media room STREAMER", "Media Room Computer"])
        #expect(config.devices[0].action == .service("media_player", "demo_toggle", target: "media_player.demo_media_player_2"))
    }

    @Test func studioRemoteMatchesTheDocument() throws {
        let config = try remote("studio-remote")
        #expect(config.power.semantics == .toggleOnUnless(["off", "unavailable", "unknown"]))
        #expect(config.appSectionTitle == "Quick App Launch")
        #expect(config.volumeTitle == "Soundbar Volume")
        #expect(config.showVolumeWhenOff)
        #expect(config.devices.map(\.title) == ["TV", "Game Console", "Server", "Computer", "Soundbar"])
        #expect(config.devices[1].activeHold == .seconds(45))
        #expect(config.lightSync != nil)
    }
}

// MARK: - Music Room Xbox resolver

@Suite(.demoHouse)
struct MusicRoomXboxResolverTests {
    typealias M = MediaRemotes.MusicRoom

    func states(cloud: String? = nil, hdmi: String? = nil, tv: String? = nil, power: String? = nil, input: String? = nil) -> [String: String] {
        var states: [String: String] = [:]
        states[M.xboxEntityId] = cloud
        states[M.xboxHdmiStatusEntityId] = hdmi
        states[M.controlEntityId] = tv
        states[M.hueSyncPowerEntityId] = power
        states[M.hueSyncHdmiInputEntityId] = input
        return states
    }

    @Test(arguments: ["on", "playing", "paused"])
    func cloudActiveIsOn(cloud: String) {
        #expect(M.xboxState(states(cloud: cloud)) == "on")
    }

    @Test func linkedOnTheActivePathIsOn() {
        #expect(M.xboxState(states(cloud: "off", hdmi: "linked", tv: "on", power: "on", input: "HDMI 1")) == "on")
    }

    @Test func anyBrokenLinkIsOff() {
        #expect(M.xboxState(states(cloud: "off", hdmi: "plugged", tv: "on", power: "on", input: "HDMI 1")) == "off")
        #expect(M.xboxState(states(cloud: "off", hdmi: "linked", tv: "off", power: "on", input: "HDMI 1")) == "off")
        #expect(M.xboxState(states(cloud: "off", hdmi: "linked", tv: "unknown", power: "on", input: "HDMI 1")) == "off")
        #expect(M.xboxState(states(cloud: "off", hdmi: "linked", tv: "on", power: "off", input: "HDMI 1")) == "off")
        #expect(M.xboxState(states(cloud: "off", hdmi: "linked", tv: "on", power: "on", input: "HDMI 2")) == "off")
        #expect(M.xboxState(states(hdmi: "linked", tv: "on", power: "on")) == "off", "No input")
    }

    @Test func nothingKnownIsUnavailable() {
        #expect(M.xboxState(states()) == "unavailable")
        #expect(M.xboxState(states(cloud: "unavailable", hdmi: "unknown")) == "unavailable")
        #expect(MediaRemoteStateResolver.consoleState.resolve(states(cloud: "playing")) == "on")
    }
}
