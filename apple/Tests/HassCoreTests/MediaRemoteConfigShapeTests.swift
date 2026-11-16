import Foundation
import Testing
@testable import HassCore

// MARK: - Remote configuration values

/// The small value types of an authored remote: commands, device tiles, the console resolver and the sheet tabs.
struct MediaRemoteConfigShapeTests {
    @Test func aCommandNamesItsServiceOnlyWhenItCallsOne() {
        let call = MediaRemoteCommand.service(ServiceCall("remote", "send_command", target: "remote.demo_remote"))
        #expect(call.serviceName == "send_command")
        #expect(MediaRemoteCommand.service(ServiceCall("remote", "", target: "remote.demo_remote")).serviceName == nil)
        #expect(MediaRemoteCommand.textPrompt(targetEntityId: "text.demo_input").serviceName == nil)
    }

    @Test func aStateActionPicksItsBranchesAndTilesCompareByValue() {
        let on = MediaRemoteCommand.service(ServiceCall("switch", "turn_off", target: "switch.demo_a"))
        let off = MediaRemoteCommand.service(ServiceCall("switch", "turn_on", target: "switch.demo_a"))
        let branch = MediaRemoteAction.StateCase(["on", "playing"], on)
        #expect(branch.states == ["on", "playing"] && branch.command == on)
        let action = MediaRemoteAction.state(entityId: nil, cases: [branch], otherwise: off)
        let tile = MediaRemoteDevice("Console", entityId: "media_player.demo_console", icon: "gamecontroller", action: action,
                                     activeStates: ["on"], stateLabels: ["on": "Awake"])
        var copy = tile
        #expect(tile.id == "Console" && copy == tile)
        copy.title = "Other"
        #expect(copy != tile)
        #expect(tile != MediaRemoteDevice("Console", entityId: "media_player.demo_other", icon: "gamecontroller", action: action))
        #expect(MediaRemoteAction.service("switch", "turn_on", target: "switch.demo_a") == .command(off))
    }

    @Test func aConfiguredConsoleIsOnFromTheCloudOrTheLinkedTvPath() {
        let resolver = MediaRemoteStateResolver.configuredConsole(
            cloudEntityId: "sensor.demo_cloud", hdmiEntityId: "sensor.demo_hdmi", tvEntityId: "media_player.demo_tv",
            powerEntityId: "switch.demo_power", inputEntityId: "select.demo_input", activeStates: ["Playing"],
            inputSuffix: "Console", linkedState: "Linked")
        #expect(resolver.resolve(["sensor.demo_cloud": "Playing"]) == "on")
        #expect(resolver.resolve(["sensor.demo_cloud": "Idle", "sensor.demo_hdmi": "Linked", "media_player.demo_tv": "on",
                                  "switch.demo_power": "on", "select.demo_input": "HDMI 2 Console"]) == "on")
        #expect(resolver.resolve(["sensor.demo_cloud": "Idle"]) == "off")
        #expect(resolver.resolve(["sensor.demo_cloud": "unavailable"]) == "unavailable")
        #expect(MediaRemoteStateResolver.consoleState.resolve([:]) == "unavailable")
    }

    @Test func theHueSyncTabReadsEveryEntityItShows() {
        let sync = HueSyncConfig(powerEntityId: "switch.demo_a", lightSyncEntityId: "switch.demo_b", syncModeEntityId: "select.demo_c",
                                 intensityEntityId: "select.demo_d", brightnessEntityId: "number.demo_e",
                                 hdmiInputEntityId: "select.demo_f", hdmiStatusEntityIds: ["sensor.demo_g", "sensor.demo_h"])
        #expect(sync.entityIds == ["switch.demo_a", "switch.demo_b", "select.demo_c", "select.demo_d", "number.demo_e",
                                   "select.demo_f", "sensor.demo_g", "sensor.demo_h"])
    }

    @Test func everyTabHasItsOwnTitle() {
        #expect(MediaRemoteTab.allCases.map(\.title) == ["Remote", "Apps", "Devices", "Hue Sync"])
        #expect(Set(MediaRemoteTab.allCases.map(\.id)).count == 4)
    }
}
