import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// The controller with a recording caller and a manual clock: what each control sends, what it shows
/// meanwhile, and when optimistic values give way to Home Assistant.
@MainActor
@Suite(.demoHouse)
struct MediaRemoteControllerTests {
    typealias M = MediaRemotes.MusicRoom

    func controller(_ config: MediaRemoteConfig, _ states: [String: String], attributes: [String: [String: JSONValue]] = [:])
        -> (MediaRemoteController, EntityStore, RecordingCaller, ManualScheduler)
    {
        let store = makeStore(states, attributes: attributes)
        let caller = RecordingCaller()
        let scheduler = ManualScheduler()
        return (MediaRemoteController(config: config, store: store, caller: caller, scheduler: scheduler), store, caller, scheduler)
    }

    // MARK: Disabled and visibility rules

    @Test(arguments: ["off", "unavailable", "unknown"])
    func controlsDisableWhenTheControlEntityIsOff(state: String) {
        let (remote, _, _, _) = controller(MediaRemotes.all[0], ["media_player.demo_living_room_2": state])
        #expect(remote.controlsDisabled)
        #expect(remote.powerTitle == "Power On")
        #expect(remote.iconTone(for: remote.config.power) == .inactive)
    }

    @Test func controlsEnableWhenOn() {
        let (remote, _, _, _) = controller(MediaRemotes.all[0], ["media_player.demo_living_room_2": "playing"])
        #expect(!remote.controlsDisabled)
        #expect(remote.powerTitle == "Power Off")
        #expect(remote.iconTone(for: remote.config.power) == .active)
        #expect(remote.iconTone(for: remote.config.up) == nil)
        #expect(!remote.hidesKeyboard)
    }

    @Test func controlsDisableWhenTheEntityIsMissing() {
        let (remote, _, _, _) = controller(MediaRemotes.all[0], [:])
        #expect(remote.controlsDisabled)
        #expect(remote.iconTone(for: remote.config.power) == .active, "No state is not an inactive state")
    }

    @Test func appleTVStandbyIsGreenButStillEnabled() {
        let (remote, _, _, _) = controller(MediaRemotes.all[1], ["media_player.demo_bedroom_1_1": "standby"])
        #expect(remote.iconTone(for: remote.config.power) == .inactive)
        #expect(!remote.controlsDisabled, "Only off, unavailable and unknown disable the d-pad")
    }

    @Test func keyboardHidesOnlyWhenConfiguredAndOff() {
        var config = MediaRemotes.all[0]
        config.hideKeyboardWhenOff = true
        let (remote, store, _, _) = controller(config, ["media_player.demo_living_room_2": "off"])
        #expect(remote.hidesKeyboard)
        set(store, "media_player.demo_living_room_2", "on")
        #expect(!remote.hidesKeyboard)
    }

    @Test func volumeShowsOnlyWhileOnUnlessConfigured() {
        let (living, store, _, _) = controller(MediaRemotes.all[0], ["media_player.demo_media_player_3": "off"])
        #expect(!living.showsVolume)
        #expect(living.volumeDisabled)
        set(store, "media_player.demo_media_player_3", "playing")
        #expect(living.showsVolume)
        #expect(!living.volumeDisabled)

        let (theater, theaterStore, _, _) = controller(MediaRemotes.all[2], [:])
        #expect(!theater.showsVolume, "Missing entity hides even with showVolumeWhenOff")
        set(theaterStore, "media_player.demo_media_player_5", "off")
        #expect(theater.showsVolume)
        #expect(theater.volumeDisabled)
    }

    @Test func powerSemanticsFollowTheConfig() {
        let (music, store, _, _) = controller(MediaRemotes.sourceSelectRemote, [M.controlEntityId: "on"])
        #expect(music.semantics(for: music.config.power) == .toggle(isOn: true))
        set(store, M.controlEntityId, "off")
        #expect(music.semantics(for: music.config.power) == .toggle(isOn: false))
        #expect(music.semantics(for: music.config.up) == .command)
        let (living, _, _, _) = controller(MediaRemotes.all[0], [:])
        #expect(living.semantics(for: living.config.power) == .command)
    }

    // MARK: Service calls

    @Test func dpadSendsRemoteCommands() async {
        let (remote, _, caller, _) = controller(MediaRemotes.all[2], ["media_player.demo_media_room_1": "on"])
        for button in remote.config.directionalButtons { remote.press(button) }
        remote.press(remote.config.back)
        await remote.waitForCalls()
        #expect(caller.calls.map { $0.data["command"] } == ["DPAD_UP", "DPAD_LEFT", "DPAD_CENTER", "DPAD_RIGHT", "DPAD_DOWN", "BACK"])
        #expect(caller.calls.allSatisfy { $0.domain == "remote" && $0.service == "demo_send_command" && $0.data["entity_id"] == "remote.demo_remote_1" })
    }

    @Test func keyboardOpensThePromptAndSendsEscapedText() async {
        let (remote, _, caller, _) = controller(MediaRemotes.all[0], ["media_player.demo_living_room_2": "on"])
        let target = remote.press(remote.config.keyboard!)
        #expect(target == "media_player.demo_living_room_2")
        await remote.waitForCalls()
        #expect(caller.calls.isEmpty, "Opening the prompt calls nothing")
        remote.sendText("   ", to: "media_player.demo_living_room_2")
        remote.sendText("it's", to: "media_player.demo_living_room_2")
        await remote.waitForCalls()
        #expect(caller.calls == [.init(domain: "androidtv", service: "adb_command",
                                       data: ["entity_id": "media_player.demo_living_room_2", "command": #"input text 'it'\''s'"#])])
    }

    @Test func muteAndAppsSendScriptData() async throws {
        let (remote, _, caller, _) = controller(MediaRemotes.all[2], [:])
        remote.press(remote.config.volumeMute)
        remote.tap(remote.config.apps[2])
        await remote.waitForCalls()
        #expect(caller.calls[0] == .init(domain: "media_player", service: "demo_volume_mute", data: ["entity_id": "media_player.demo_media_player_5", "is_volume_muted": "true"]))
        #expect(caller.raw[0]["is_volume_muted"] as? Bool == true)
        #expect(caller.calls[1].service == "demo_launch_app_on_media_player")
        #expect(caller.calls[1].data["app_id"] == "com.streamc.demo")
        #expect(caller.raw[1]["turn_on_projector"] as? Bool == true)
        let (living, _, livingCaller, _) = controller(MediaRemotes.all[0], [:])
        living.press(living.config.volumeMute)
        await living.waitForCalls()
        #expect(livingCaller.raw[0]["speakerdevice"] as? [String] == ["media_player.demo_media_player_3"])
    }

    @Test func theaterPCPressesTheRightButton() async {
        let (remote, store, caller, _) = controller(MediaRemotes.all[2], ["input_boolean.demo_power_1": "off"])
        let pc = remote.config.devices[3]
        remote.tap(pc)
        set(store, "input_boolean.demo_power_1", "on")
        remote.tap(pc)
        await remote.waitForCalls()
        #expect(caller.calls.map { $0.data["entity_id"] } == ["input_button.demo_input_button_6", "input_button.demo_input_button_5"])
        #expect(remote.display(pc).semantics == .command)
    }

    @Test func readOnlyDeviceDoesNothing() async {
        let (remote, _, caller, _) = controller(MediaRemotes.sourceSelectRemote, [M.volumeEntityId: "on"])
        let beam = remote.config.devices[4]
        remote.tap(beam)
        await remote.waitForCalls()
        #expect(caller.calls.isEmpty)
        let display = remote.display(beam)
        #expect(display.semantics == .state)
        #expect(!display.isDisabled)
        #expect(display.subtitle == "On")
    }

    // MARK: Volume

    @Test func volumeIsOptimisticUntilConfirmedOrReverted() async {
        let (remote, store, caller, scheduler) = controller(MediaRemotes.all[0], ["media_player.demo_media_player_3": "playing"],
                                                            attributes: ["media_player.demo_media_player_3": ["volume_level": .number(0.2)]])
        #expect(remote.volumePercent == 20)
        remote.setVolume(percent: 45)
        #expect(remote.volumePercent == 45)
        await remote.waitForCalls()
        #expect(caller.calls.last == .init(domain: "media_player", service: "volume_set", data: ["entity_id": "media_player.demo_media_player_3", "volume_level": "0.45"]))
        #expect(scheduler.pending.first?.delay == .milliseconds(2500))
        // An unrelated echo keeps the optimistic value; the confirming one clears it.
        set(store, "media_player.demo_media_player_3", "playing", ["volume_level": .number(0.3)])
        remote.liveDidChange()
        #expect(remote.volumePercent == 45)
        set(store, "media_player.demo_media_player_3", "playing", ["volume_level": .number(0.45)])
        remote.liveDidChange()
        #expect(remote.volumeOverlay.pending.isEmpty)
        #expect(remote.volumePercent == 45)
        // A value the speaker never reaches reverts after 2.5 s.
        remote.setVolume(percent: 120)
        #expect(remote.volumePercent == 100)
        scheduler.fireAll()
        #expect(remote.volumePercent == 45)
        remote.setVolume(percent: 45)
        #expect(remote.volumeOverlay.pending.isEmpty, "Setting the live value shows no override")
    }

    // MARK: Music Room optimistic intents

    @Test func powerTogglesTheTVWithOptimisticState() async {
        let (remote, store, caller, scheduler) = controller(MediaRemotes.sourceSelectRemote, [M.controlEntityId: "off", M.activeMediaSourceEntityId: "Off"])
        remote.press(remote.config.power)
        #expect(remote.displayedState(M.controlEntityId) == "on")
        #expect(remote.displayedState(M.activeMediaSourceEntityId) == "TV")
        #expect(remote.displayedState(M.hueSyncLightSyncEntityId) == "off")
        #expect(!remote.controlsDisabled, "The optimistic on enables the d-pad at once")
        #expect(remote.powerTitle == "Power Off")
        await remote.waitForCalls()
        #expect(caller.calls.last?.service == "demo_studio_tv")
        // The source sensor clears on any live change; the TV clears on confirmation.
        set(store, M.activeMediaSourceEntityId, "Off")
        remote.liveDidChange()
        #expect(remote.displayedState(M.activeMediaSourceEntityId) == "TV", "Same live value: not a change")
        set(store, M.activeMediaSourceEntityId, "Game Console")
        remote.liveDidChange()
        #expect(remote.displayedState(M.activeMediaSourceEntityId) == "Game Console")
        #expect(remote.displayedState(M.controlEntityId) == "on")
        set(store, M.controlEntityId, "on")
        remote.liveDidChange()
        #expect(remote.overlay.pending[M.controlEntityId] == nil)
        // Now on: the same button resolves to demo_studio_tv_off.
        remote.press(remote.config.power)
        await remote.waitForCalls()
        #expect(caller.calls.last?.service == "demo_studio_tv_off")
        #expect(scheduler.pending.contains { $0.delay == .seconds(180) })
        scheduler.fireAll()
        #expect(remote.overlay.pending.isEmpty, "Reverted to live after the revert time")
    }

    @Test func failedCallsUndoTheirOptimisticState() async {
        let (remote, _, caller, _) = controller(MediaRemotes.sourceSelectRemote, [M.controlEntityId: "off"])
        caller.failNext = true
        remote.press(remote.config.power)
        #expect(remote.displayedState(M.controlEntityId) == "on")
        await remote.waitForCalls()
        #expect(remote.displayedState(M.controlEntityId) == "off")
    }

    @Test func sourceTogglesDependOnTheActiveSource() async {
        let (remote, store, caller, _) = controller(MediaRemotes.sourceSelectRemote, [M.activeMediaSourceEntityId: "TV"])
        let server = remote.config.devices[2]
        #expect(remote.display(server).subtitle == "Off")
        #expect(remote.display(server).semantics == .selection(isSelected: false))
        remote.tap(server)
        #expect(remote.display(server).subtitle == "On")
        #expect(remote.display(server).isActive)
        set(store, M.activeMediaSourceEntityId, "Server")
        remote.liveDidChange()
        remote.tap(server)
        await remote.waitForCalls()
        #expect(caller.calls.map(\.service) == ["demo_studio_server", "demo_studio_tv_off"])
        let pc = remote.config.devices[3]
        remote.tap(pc)
        await remote.waitForCalls()
        #expect(caller.calls.last?.service == "demo_studio_windows_pc")
        let (fortnite, _, fortniteCaller, _) = controller(MediaRemotes.sourceSelectRemote, [M.activeMediaSourceEntityId: "Game"])
        fortnite.run(M.xboxSourceToggle)
        await fortnite.waitForCalls()
        #expect(fortniteCaller.calls.last?.service == "demo_studio_tv_off")
    }

    @Test func fortniteAppIsSelectedWhileItIsTheSource() {
        let (remote, store, _, _) = controller(MediaRemotes.sourceSelectRemote, [M.activeMediaSourceEntityId: "TV"])
        let app = remote.config.apps[0]
        #expect(remote.display(app) == .init(isActive: false, isUnavailable: false, semantics: .selection(isSelected: false)))
        remote.tap(app)
        #expect(remote.display(app).isActive)
        set(store, M.activeMediaSourceEntityId, "unavailable")
        #expect(remote.display(app).isUnavailable)
        let (living, _, _, _) = controller(MediaRemotes.all[0], [:])
        #expect(living.display(living.config.apps[0]) == .init(isActive: false, isUnavailable: false, semantics: .command))
    }

    // MARK: Xbox tile

    @Test func xboxTileResolvesAndHoldsActive() async {
        let (remote, store, caller, scheduler) = controller(MediaRemotes.sourceSelectRemote, [
            M.xboxEntityId: "on", M.controlEntityId: "on", M.hueSyncPowerEntityId: "on", M.hueSyncHdmiInputEntityId: "HDMI 2",
        ])
        let xbox = remote.config.devices[1]
        #expect(remote.display(xbox).state == "on")
        #expect(remote.display(xbox).semantics == .toggle(isOn: true))
        // The cloud state drops: the tile holds "on" for 45 s.
        set(store, M.xboxEntityId, "off")
        remote.liveDidChange()
        #expect(remote.display(xbox).state == "on")
        #expect(scheduler.pending.contains { $0.delay == .seconds(45) })
        // Tapping while held decides on the shown state: turn it off.
        remote.tap(xbox)
        await remote.waitForCalls()
        #expect(caller.calls.last?.service == "demo_studio_console_off")
        #expect(remote.display(xbox).state == "off", "The optimistic off wins over the hold")
        scheduler.fireAll()
        #expect(remote.display(xbox).state == "off")
        remote.tap(xbox)
        await remote.waitForCalls()
        #expect(caller.calls.last?.service == "demo_studio_console")
    }

    @Test func xboxHoldEndsWhenARelatedEntityChanges() {
        let (remote, store, _, scheduler) = controller(MediaRemotes.sourceSelectRemote, [
            M.xboxEntityId: "playing", M.controlEntityId: "on", M.hueSyncPowerEntityId: "on",
        ])
        let xbox = remote.config.devices[1]
        set(store, M.xboxEntityId, "off")
        remote.liveDidChange()
        #expect(remote.display(xbox).state == "on")
        set(store, M.hueSyncPowerEntityId, "off")
        remote.liveDidChange()
        #expect(remote.display(xbox).state == "off")
        #expect(scheduler.pending.isEmpty)
        // The hold also expires on its own.
        set(store, M.xboxEntityId, "on")
        remote.liveDidChange()
        set(store, M.xboxEntityId, "off")
        remote.liveDidChange()
        #expect(remote.display(xbox).state == "on")
        scheduler.fireAll()
        #expect(remote.display(xbox).state == "off")
    }

    @Test func unavailableDevicesAreDisabled() {
        let (remote, _, _, _) = controller(MediaRemotes.all[2], ["media_player.demo_media_player_2": "unavailable"])
        let display = remote.display(remote.config.devices[0])
        #expect(display.isUnavailable)
        #expect(display.isDisabled)
        #expect(!display.isActive)
        #expect(display.subtitle == "Unavailable")
        #expect(remote.display(remote.config.devices[1]).subtitle == "Unavailable", "Missing entity")
    }

    // MARK: Hue Sync

    func hueStates() -> [String: String] {
        [M.hueSyncPowerEntityId: "on", M.hueSyncLightSyncEntityId: "off", M.hueSyncModeEntityId: "video",
         M.hueSyncIntensityEntityId: "moderate", M.hueSyncBrightnessEntityId: "50", M.hueSyncHdmiInputEntityId: "HDMI 1",
         M.hueSyncHdmiStatusEntityIds[0]: "linked", M.hueSyncHdmiStatusEntityIds[1]: "connected",
         M.hueSyncHdmiStatusEntityIds[2]: "plugged", M.hueSyncHdmiStatusEntityIds[3]: "unplugged"]
    }

    func hueAttributes() -> [String: [String: JSONValue]] {
        [M.hueSyncModeEntityId: ["options": ["video", "music", "game"]],
         M.hueSyncIntensityEntityId: ["options": ["subtle", "moderate", "high", "intense"]],
         M.hueSyncBrightnessEntityId: ["min": .number(0), "max": .number(200), "step": .number(5)],
         M.hueSyncHdmiInputEntityId: ["options": ["HDMI 1", "HDMI 2", "HDMI 3", "HDMI 4"]]]
    }

    @Test func hueTogglesProjectOntoEachOther() async {
        let (remote, _, caller, scheduler) = controller(MediaRemotes.sourceSelectRemote, hueStates(), attributes: hueAttributes())
        let hue = remote.config.lightSync!
        #expect(remote.hueToggle(hue.powerEntityId) == .init(isOn: true, isUnavailable: false, subtitle: "On"))
        remote.toggleHue(hue.lightSyncEntityId, onProjections: [hue.powerEntityId])
        #expect(remote.hueToggle(hue.lightSyncEntityId).isOn)
        #expect(remote.isHueSyncing(hue))
        remote.toggleHue(hue.powerEntityId, offProjections: [hue.lightSyncEntityId])
        #expect(!remote.hueToggle(hue.powerEntityId).isOn)
        #expect(!remote.hueToggle(hue.lightSyncEntityId).isOn)
        await remote.waitForCalls()
        #expect(caller.calls.map(\.service) == ["turn_on", "turn_off"])
        #expect(caller.calls.map { $0.data["entity_id"] } == [hue.lightSyncEntityId, hue.powerEntityId])
        #expect(scheduler.pending.allSatisfy { $0.delay == .seconds(8) })
        #expect(remote.hueToggle("switch.demo_missing") == .init(isOn: false, isUnavailable: true, subtitle: "Unavailable"))
    }

    @Test func hueSelectsSkipTheShownValueAndUnavailableSelects() async {
        let (remote, store, caller, _) = controller(MediaRemotes.sourceSelectRemote, hueStates(), attributes: hueAttributes())
        let hue = remote.config.lightSync!
        remote.selectHue(hue.intensityEntityId, option: "moderate")
        remote.selectHue(hue.intensityEntityId, option: "high")
        #expect(remote.hueSelect(hue.intensityEntityId).selected == "high")
        await remote.waitForCalls()
        #expect(caller.calls == [.init(domain: "select", service: "select_option", data: ["entity_id": hue.intensityEntityId, "option": "high"])])
        set(store, hue.intensityEntityId, "unavailable")
        #expect(remote.hueSelect(hue.intensityEntityId).isUnavailable)
        remote.selectHue(hue.intensityEntityId, option: "subtle")
        await remote.waitForCalls()
        #expect(caller.calls.count == 1)
    }

    @Test func syncModeStartsSyncingAndResetsIntensity() async {
        let (remote, _, caller, _) = controller(MediaRemotes.sourceSelectRemote, hueStates(), attributes: hueAttributes())
        let hue = remote.config.lightSync!
        remote.selectHue(hue.intensityEntityId, option: "high")
        // Not syncing: re-choosing the current mode is allowed and starts syncing.
        remote.selectSyncMode(hue, mode: "video")
        #expect(remote.hueSelect(hue.intensityEntityId).selected == "moderate", "Optimistic intensity dropped")
        #expect(remote.isHueSyncing(hue))
        // Syncing now: the same mode again does nothing.
        remote.selectSyncMode(hue, mode: "video")
        remote.selectSyncMode(hue, mode: "game")
        await remote.waitForCalls()
        let options = caller.calls.compactMap { $0.data["option"] }
        #expect(options == ["high", "video", "game"])
    }

    @Test func brightnessClampsAndCommitsChanges() async {
        let (remote, store, caller, _) = controller(MediaRemotes.sourceSelectRemote, hueStates(), attributes: hueAttributes())
        let hue = remote.config.lightSync!
        let display = remote.hueBrightness(hue.brightnessEntityId)
        #expect(display.value == 50)
        #expect(display.range == 0...200)
        #expect(display.step == 5)
        remote.setHueBrightness(hue.brightnessEntityId, value: 50)
        remote.setHueBrightness(hue.brightnessEntityId, value: 120)
        #expect(remote.hueBrightness(hue.brightnessEntityId).value == 120)
        await remote.waitForCalls()
        #expect(caller.calls == [.init(domain: "number", service: "set_value", data: ["entity_id": hue.brightnessEntityId, "value": "120"])])
        set(store, hue.brightnessEntityId, "999")
        remote.liveDidChange()
        #expect(remote.hueBrightness(hue.brightnessEntityId).value == 120, "Still waiting for 120")
        set(store, hue.brightnessEntityId, "unavailable", [:])
        let unavailable = remote.hueBrightness(hue.brightnessEntityId)
        #expect(unavailable.isUnavailable)
        #expect(unavailable.unavailableText == "Unavailable")
        #expect(unavailable.range == 1...100)
    }

    @Test func hdmiInputsShowStatusAndSelection() {
        let (remote, store, _, _) = controller(MediaRemotes.sourceSelectRemote, hueStates(), attributes: hueAttributes())
        let hue = remote.config.lightSync!
        let inputs = remote.hdmiInputs(hue)
        #expect(inputs.map(\.subtitle) == ["Selected • Linked", "Connected", "Plugged", "Unplugged"])
        #expect(inputs.map(\.isSelected) == [true, false, false, false])
        #expect(inputs.map(\.isDisabled) == [false, false, false, true])
        // Without options the tab falls back to HDMI 1–4, all disabled.
        set(store, hue.hdmiInputEntityId, "HDMI 1", [:])
        let fallback = remote.hdmiInputs(hue)
        #expect(fallback.map(\.option) == ["HDMI 1", "HDMI 2", "HDMI 3", "HDMI 4"])
        #expect(fallback.allSatisfy { $0.isDisabled })
        // More options than status sensors reuse the last sensor.
        set(store, hue.hdmiInputEntityId, "HDMI 5", ["options": ["HDMI 1", "HDMI 2", "HDMI 3", "HDMI 4", "HDMI 5"]])
        #expect(remote.hdmiInputs(hue).last?.statusEntityId == M.hueSyncHdmiStatusEntityIds[3])
    }

    // MARK: Live observation

    @Test func liveChangesReachTheOverlayWithoutManualSync() async throws {
        let (remote, store, _, _) = controller(MediaRemotes.sourceSelectRemote, [M.controlEntityId: "off"])
        remote.press(remote.config.power)
        #expect(remote.overlay.pending[M.controlEntityId] == "on")
        set(store, M.controlEntityId, "on")
        for _ in 0..<20 where remote.overlay.pending[M.controlEntityId] != nil { await Task.yield() }
        #expect(remote.overlay.pending[M.controlEntityId] == nil)
        #expect(remote.observedEntityIds.contains(M.xboxEntityId))
    }
}

/// The overlay and hold primitives on their own.
@MainActor
@Suite(.demoHouse)
struct OptimisticOverlayTests {
    @Test func untrackedKeysTakeNoValues() {
        let overlay = OptimisticOverlay(rules: ["a": .confirmation], scheduler: ManualScheduler())
        #expect(overlay.commit("b", value: "on", live: "off", revertAfter: .seconds(1)) == nil)
        #expect(overlay.displayed("b", live: "off") == "off")
        overlay.reset("b")
        overlay.liveChanged("b", to: "on")
        #expect(overlay.pending.isEmpty)
    }

    @Test func staleGenerationsDoNotResetNewerCommits() {
        let scheduler = ManualScheduler()
        let overlay = OptimisticOverlay(rules: ["a": .confirmation], scheduler: scheduler)
        let first = overlay.commit("a", value: "on", live: "off", revertAfter: .seconds(1))
        overlay.commit("a", value: "dim", live: "off", revertAfter: .seconds(1))
        overlay.reset("a", generation: first)
        #expect(overlay.displayed("a", live: "off") == "dim")
        #expect(overlay.hasOverride("a", live: "off"))
        #expect(!overlay.hasOverride("a", live: "dim"))
        // The first commit's timer was cancelled; only the second's can revert.
        #expect(scheduler.pending.count == 1)
        overlay.reset("a")
        #expect(overlay.pending.isEmpty)
        #expect(!overlay.hasOverride("a", live: "off"))
    }

    @Test func liveChangeRuleClearsOnAnyChange() {
        let overlay = OptimisticOverlay(rules: ["a": .liveChange], scheduler: ManualScheduler())
        overlay.liveChanged("a", to: "x")
        overlay.commit("a", value: "y", live: "x", revertAfter: .seconds(1))
        overlay.liveChanged("a", to: "x")
        #expect(overlay.pending["a"] == "y", "No change, no clear")
        overlay.liveChanged("a", to: "z")
        #expect(overlay.pending.isEmpty)
    }

    @Test func revertTimerOfAReplacedCommitDoesNothing() {
        let scheduler = ManualScheduler()
        let overlay = OptimisticOverlay(rules: ["a": .confirmation], scheduler: scheduler)
        overlay.commit("a", value: "on", live: "off", revertAfter: .seconds(1))
        let stale = scheduler.items[0]
        overlay.commit("a", value: "dim", live: "off", revertAfter: .seconds(1))
        stale.work()
        #expect(overlay.pending["a"] == "dim")
    }

    @Test func holdsWithoutADurationNeverHold() {
        let holds = ActiveHoldTracker(scheduler: ManualScheduler())
        holds.update("x", liveActive: true, hasOverride: false, hold: nil, resetKey: "")
        holds.update("x", liveActive: false, hasOverride: false, hold: nil, resetKey: "")
        #expect(holds.held("x", displayed: "off", activeStates: ["on"], hasOverride: false, hold: nil) == "off")
        #expect(holds.held("y", displayed: "off", activeStates: ["on"], hasOverride: false, hold: .seconds(1)) == "off")
    }

    @Test func holdTimerRestartsOnlyWhenItsInputsChange() {
        let scheduler = ManualScheduler()
        let holds = ActiveHoldTracker(scheduler: scheduler)
        holds.update("x", liveActive: true, hasOverride: false, hold: .seconds(45), resetKey: "k")
        holds.update("x", liveActive: false, hasOverride: false, hold: .seconds(45), resetKey: "k")
        #expect(scheduler.pending.count == 1)
        holds.update("x", liveActive: false, hasOverride: false, hold: .seconds(45), resetKey: "k")
        #expect(scheduler.pending.count == 1, "Same inputs keep the timer")
        #expect(holds.held("x", displayed: "off", activeStates: [], hasOverride: false, hold: .seconds(45)) == "off",
                "No active states: shows the displayed state")
        // An override ends the hold.
        holds.update("x", liveActive: false, hasOverride: true, hold: .seconds(45), resetKey: "k")
        #expect(scheduler.pending.isEmpty)
        #expect(holds.held("x", displayed: "off", activeStates: ["on"], hasOverride: false, hold: .seconds(45)) == "off")
    }
}

/// The production scheduler really runs and cancels work.
@MainActor
@Suite(.demoHouse)
struct TaskRevertSchedulerTests {
    @Test func runsAndCancels() async throws {
        let scheduler = TaskRevertScheduler()
        var ran = 0
        _ = scheduler.schedule(after: .milliseconds(10)) { ran += 1 }
        let cancelled = scheduler.schedule(after: .milliseconds(10)) { ran += 10 }
        cancelled.cancel()
        // Waits for the work rather than a fixed time: other suites can hold the main actor past any deadline.
        for _ in 0..<500 where ran == 0 { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(50)) // The cancelled work was due at the same moment.
        #expect(ran == 1)
    }
}
