#if DEBUG
import HassCore
import HassDesign
import Observation
import SwiftUI

/// Records service calls and echoes the few that change fixture state, after a short delay like Home Assistant.
@MainActor
@Observable
final class GalleryServiceRecorder: HassServiceCalling {
    private(set) var lastCall = "None"
    @ObservationIgnored private let store: EntityStore

    init(store: EntityStore) { self.store = store }

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        lastCall = Self.describe(domain, service, data)
        try? await Task.sleep(for: .milliseconds(400))
        echo(domain, service, data)
    }

    /// The source a Music Room source script selects, by the service names the house document gives its commands.
    static func musicRoomSource(forScript service: String) -> String? {
        typealias M = MediaRemotes.MusicRoom
        var launcher: String?
        if case let .command(command) = M.fortnite { launcher = command.serviceName }
        let table: [(String?, String)] = [
            (M.xboxOn.serviceName, M.Source.xbox), (M.serverOn.serviceName, M.Source.server),
            (M.windowsPCOn.serviceName, M.Source.windowsPC), (launcher, M.Source.fortnite),
        ]
        return table.first { $0.0 == service }?.1
    }

    /// `domain.service key=value …` with keys sorted, e.g. `remote.send_command command=DPAD_UP entity_id=remote.demo_remote`.
    static func describe(_ domain: String, _ service: String, _ data: [String: any Sendable]) -> String {
        let pairs = data.keys.sorted().map { key in "\(key)=\(describeValue(data[key]!))" }
        return ([domain + "." + service] + pairs).joined(separator: " ")
    }

    private static func describeValue(_ value: any Sendable) -> String {
        if let array = value as? [any Sendable] { return "[" + array.map(describeValue).joined(separator: ",") + "]" }
        return "\(value)"
    }

    private func echo(_ domain: String, _ service: String, _ data: [String: any Sendable]) {
        let target = data["entity_id"] as? String
        func set(_ id: String, _ state: String) {
            var entity = store.value(id) ?? EntityState(entityId: id, state: state)
            entity.state = state
            store.apply([entity])
        }
        func flip(_ id: String, on: String = "on", off: String = "off") {
            set(id, MediaRemoteState.isOff(store.value(id)?.state) || store.value(id)?.state == off ? on : off)
        }
        switch (domain, service) {
        case ("media_player", "toggle"): if let target { flip(target) }
        case ("switch", "turn_on"), ("light", "turn_on"), ("fan", "turn_on"): if let target { set(target, "on") }
        case ("switch", "turn_off"), ("light", "turn_off"), ("fan", "turn_off"): if let target { set(target, "off") }
        case ("select", "select_option"):
            if let target, let option = data["option"] as? String { set(target, option) }
            // Choosing a sync mode starts syncing, as the Sync Box does.
            if target == MediaRemotes.MusicRoom.hueSyncModeEntityId {
                set(MediaRemotes.MusicRoom.hueSyncPowerEntityId, "on")
                set(MediaRemotes.MusicRoom.hueSyncLightSyncEntityId, "on")
            }
        case ("homeassistant", "toggle"):
            if let target { set(target, store.value(target)?.state == "on" ? "off" : "on") }
        case ("alarm_control_panel", _):
            // The Quick Links Security System disc: Arm Home becomes Disarm and back, as the panel answers.
            if let target, let mode = SecurityConfig.alarmModes.first(where: { $0.service == service }) { set(target, mode.state) }
        case ("climate", "set_hvac_mode"):
            if let target, let mode = data["hvac_mode"] as? String { set(target, mode) }
        case ("climate", "set_fan_mode"):
            if let target, var entity = store.value(target), let mode = data["fan_mode"] as? String {
                entity.attributes["fan_mode"] = .string(mode)
                store.apply([entity])
            }
        case ("climate", "set_temperature"):
            let targets = (data["entity_id"] as? [String]) ?? target.map { [$0] } ?? []
            let changed: [EntityState] = targets.compactMap { id in
                guard var entity = store.value(id) else { return nil }
                for key in ["temperature", "target_temp_low", "target_temp_high"] {
                    if let value = data[key] as? Double { entity.attributes[key] = .number(value) }
                }
                return entity
            }
            store.apply(changed)
        case ("number", "set_value"):
            if let target, let value = data["value"] { set(target, "\(value)") }
        case ("media_player", "volume_set"):
            if let target, var entity = store.value(target), let level = data["volume_level"] as? Double {
                entity.attributes["volume_level"] = .number(level)
                store.apply([entity])
            }
        case ("input_button", "press"):
            // `input_button.<pc>_on` / `_off` drive `input_boolean.<pc>_power` (theater and office PCs).
            if let target, let cut = target.range(of: "_o", options: .backwards) {
                let prefix = target[target.index(target.startIndex, offsetBy: "input_button.".count)..<cut.lowerBound]
                set("input_boolean.\(prefix)_power", target.hasSuffix("_on") ? "on" : "off")
            }
        case ("remote", "send_command") where data["command"] as? String == "POWER":
            flip("media_player.demo_living_room_2", on: "playing")
        case ("script", "apple_tv_power_on_off"):
            flip("media_player.demo_bedroom_1_1", on: "paused", off: "standby")
        case ("script", _) where !ScriptPowerActions.toggleScript.isEmpty && service == ScriptPowerActions.toggleScript:
            flip("media_player.demo_media_room_1")
            // The room's Power key turns the active device off: both active booleans report off.
            for device in ScriptPowerActions.all { set(device.activeEntityId, "off") }
        case ("script", _) where ScriptPowerActions.all.contains { $0.onScript == service }:
            // A Theater device's own script makes it the active one; the boolean reports after the script, which is when the
            // tile's arc spinner settles.
            for device in ScriptPowerActions.all { set(device.activeEntityId, device.onScript == service ? "on" : "off") }
        case ("script", _) where Self.musicRoomSource(forScript: service) != nil:
            // A Music Room source script turns the TV on and names the source (the Media page's selection tiles).
            typealias M = MediaRemotes.MusicRoom
            set(M.controlEntityId, "on")
            set(M.activeMediaSourceEntityId, Self.musicRoomSource(forScript: service) ?? M.Source.tv)
        case ("script", _) where service == MediaRemotes.MusicRoom.tvOn.serviceName:
            set(MediaRemotes.MusicRoom.controlEntityId, "on")
            set(MediaRemotes.MusicRoom.activeMediaSourceEntityId, MediaRemotes.MusicRoom.Source.tv)
        case ("script", _) where service == MediaRemotes.MusicRoom.tvOff.serviceName:
            set(MediaRemotes.MusicRoom.controlEntityId, "off")
            set(MediaRemotes.MusicRoom.activeMediaSourceEntityId, MediaRemotes.MusicRoom.Source.off)
        case ("input_boolean", "turn_on"), ("automation", "turn_on"): if let target { set(target, "on") }
        case ("input_boolean", "turn_off"), ("automation", "turn_off"): if let target { set(target, "off") }
        case ("input_select", "select_option"):
            if let target, let option = data["option"] as? String { set(target, option) }
        default:
            // Vacuums: the robot reacts as Valetudo would, so journeys see the next state without a real run.
            VacuumFixtures.echo(domain, service, target: target, store: store)
        }
    }
}

/// Synthetic entity states for the gallery and hosted tests (not a copy of the live house).
enum MediaRemoteFixtures {
    /// App artwork comes from the household server's public `/local` folder when it is reachable; the tiles fall
    /// back to icons otherwise. `FENTON_GALLERY_OFFLINE=1` forces the fallback.
    static var imageServer: HassServer? {
        let environment = ProcessInfo.processInfo.environment
        if environment["FENTON_GALLERY_OFFLINE"] == "1" { return nil }
        return environment["FENTON_HASS_SERVER"].flatMap(URL.init(string:)).map(HassServer.init(baseURL:)) ?? HassServer.buildDefault()
    }

    @MainActor static func store() -> EntityStore {
        let store = EntityStore()
        store.replaceAll(states, freshness: .live)
        return store
    }

    static let states: [EntityState] = {
        typealias M = MediaRemotes.MusicRoom
        func entity(_ id: String, _ state: String, _ attributes: [String: JSONValue] = [:]) -> EntityState {
            EntityState(entityId: id, state: state, attributes: attributes)
        }
        func options(_ values: [String]) -> [String: JSONValue] { ["options": .array(values.map(JSONValue.string))] }
        return [
            entity("media_player.demo_living_room_2", "playing"),
            entity("media_player.demo_media_player_3", "playing", ["volume_level": .number(0.32)]),
            entity("media_player.demo_bedroom_1_1", "paused"),
            entity("media_player.demo_media_player_4", "idle", ["volume_level": .number(0.24)]),
            entity("media_player.demo_media_room_1", "on"),
            entity("media_player.demo_media_player_5", "on", ["volume_level": .number(0.45)]),
            entity("media_player.demo_media_player_2", "on"),
            entity("input_boolean.demo_power_1", "off"),
            entity(M.controlEntityId, "on"),
            entity(M.xboxEntityId, "off"),
            entity(M.volumeEntityId, "on", ["volume_level": .number(0.3)]),
            entity(M.activeMediaSourceEntityId, "TV"),
            entity(M.mediaSourceEntityId, "TV"),
            entity(M.hueSyncPowerEntityId, "on"),
            entity(M.hueSyncLightSyncEntityId, "off"),
            entity(M.hueSyncModeEntityId, "video", options(["video", "music", "game"])),
            entity(M.hueSyncIntensityEntityId, "moderate", options(["subtle", "moderate", "high", "intense"])),
            entity(M.hueSyncBrightnessEntityId, "50", ["min": .number(0), "max": .number(100), "step": .number(1)]),
            entity(M.hueSyncHdmiInputEntityId, "HDMI 1", options(["HDMI 1", "HDMI 2", "HDMI 3", "HDMI 4"])),
        ] + zip(M.hueSyncHdmiStatusEntityIds, ["linked", "connected", "plugged", "unplugged"]).map { entity($0, $1) }
    }()
}
#endif
