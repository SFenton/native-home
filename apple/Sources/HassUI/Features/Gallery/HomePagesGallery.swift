

#if DEBUG
import HassCore
import HassDesign
import Observation
import SwiftUI

/// Gallery pages for the Media, Custom Lights and Sprinklers pages: each page on fixture state with a recording
/// service caller, so journeys, audits and screenshots run signed out and never touch the house.
///
/// Launch options: `FENTON_GALLERY_REMOTE=<id>` opens a remote from Media (on the tab `FENTON_GALLERY_TAB=<tab>` names,
/// Controls by default); `FENTON_GALLERY_LIGHT=<entity>` opens a
/// custom light's sheet; `FENTON_GALLERY_SPRINKLER=<id>` opens a
/// controller and `FENTON_GALLERY_DETAIL=water-<zone>|schedule-<zone>` a page in it. `FENTON_GALLERY_CLEAN=1` hides the
/// last-call line for screenshots.
struct HomePageGallery {
    enum Kind { case media, customLights, sprinklers }

    var kind: Kind



    /// `water-1` or `schedule-0`.
    static func detail(_ text: String) -> SprinklerDetail? {
        let parts = text.split(separator: "-")
        guard parts.count == 2, let zone = Int(parts[1]) else { return nil }
        switch parts[0] {
        case "water": return .water(zone: zone)
        case "schedule": return .schedule(zone: zone)
        default: return nil
        }
    }
}

// MARK: - Recorder

/// Records service calls and echoes the ones these pages send after a short delay, like Home Assistant.
/// Media remote calls go through the remote gallery's recorder so its echoes apply too.
@MainActor
@Observable
final class PageGalleryRecorder: HassServiceCalling {
    private(set) var lastCall = "None"
    static let theaterShield = "media_player.demo_media_room_1"
    @ObservationIgnored private let store: EntityStore
    @ObservationIgnored private let remote: GalleryServiceRecorder

    init(store: EntityStore) {
        self.store = store
        remote = GalleryServiceRecorder(store: store)
    }

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        lastCall = GalleryServiceRecorder.describe(domain, service, data)
        // Read before the forwarded recorder echoes: it flips the SHIELD on a toggle script, which would hide the state Power ran from.
        let shieldWasOn = store.value(Self.theaterShield)?.state == "on"
        try await remote.callService(domain, service, data: data)
        echo(domain, service, data, shieldWasOn: shieldWasOn)
    }

    private func echo(_ domain: String, _ service: String, _ data: [String: any Sendable], shieldWasOn: Bool) {
        let target = data["entity_id"] as? String
        func update(_ id: String, _ change: (inout EntityState) -> Void) {
            var entity = store.value(id) ?? EntityState(entityId: id, state: "unknown")
            change(&entity)
            store.apply([entity])
        }
        switch (domain, service) {
        // Gallery-only, so a journey and the motion perf test can flip a remote's action set from the page: Cinema Streamer's Power
        // turns it on as playing (transport and volume), and Next on it stops it (Power again).
        case ("script", _) where !ScriptPowerActions.toggleScript.isEmpty && service == ScriptPowerActions.toggleScript:
            if shieldWasOn { update(Self.theaterShield) { $0.state = "playing" } }
        case ("media_player", "media_next_track") where target == Self.theaterShield:
            update(Self.theaterShield) { $0.state = "off" }
        case ("input_boolean", "turn_on"), ("input_boolean", "turn_off"):
            if let target { update(target) { $0.state = service == "turn_on" ? "on" : "off" } }
        case ("input_select", "select_option"):
            if let target, let option = data["option"] as? String { update(target) { $0.state = option } }
        case ("light", "turn_off"):
            if let target { update(target) { $0.state = "off"; $0.attributes["brightness"] = nil } }
        case ("light", "turn_on"):
            guard let target else { return }
            let ids = target == CustomLightsConfig.groupEntityId ? CustomLightsConfig.lights.map(\.entityId) + [target] : [target]
            for id in ids {
                update(id) { entity in
                    entity.state = "on"
                    if let percent = data["brightness_pct"] as? Int { entity.attributes["brightness"] = .number(Double(percent) * 2.55) }
                    if let brightness = data["brightness"] as? Int { entity.attributes["brightness"] = .number(Double(brightness)) }
                    if let rgb = data["rgb_color"] as? [any Sendable] { entity.attributes["rgb_color"] = .array(rgb.compactMap { ($0 as? Int).map { .number(Double($0)) } }) }
                    if data["color_temp_kelvin"] != nil { entity.attributes["rgb_color"] = .array([.number(255), .number(137), .number(14)]) }
                }
            }
        case ("bhyve", "start_watering"), ("bhyve", "stop_watering"):
            if let valve = data["entity_id"] as? String { update(valve) { $0.state = service == "start_watering" ? "open" : "closed" } }
        case ("bhyve", "update_program"):
            guard let program = data["entity_id"] as? String else { return }
            update(program) { entity in
                if let budget = data["budget"] as? Int { entity.attributes["budget"] = .number(Double(budget)) }
                if let times = data["start_times"] as? [any Sendable] { entity.attributes["start_times"] = .array(times.compactMap { ($0 as? String).map(JSONValue.string) }) }
                if let frequency = data["frequency"] as? [String: any Sendable], let days = frequency["days"] as? [any Sendable] {
                    entity.attributes["frequency"] = .object(["type": .string("days"), "days": .array(days.compactMap { ($0 as? Int).map { .number(Double($0)) } })])
                }
            }
        default: break
        }
    }
}

// MARK: - Last call banner



extension View {
}


// MARK: - Fixtures

/// Synthetic states for the three pages (not a copy of the live house).
enum HomePageFixtures {
    static func entity(_ id: String, _ state: String, _ attributes: [String: JSONValue] = [:]) -> EntityState {
        EntityState(entityId: id, state: state, attributes: attributes)
    }

    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> JSONValue { .array([.number(r), .number(g), .number(b)]) }

    static func numbers(_ values: [Double]) -> JSONValue { .array(values.map(JSONValue.number)) }

    @MainActor static func store() -> EntityStore {
        let store = EntityStore()
        store.replaceAll(states, freshness: .live)
        return store
    }

    static var states: [EntityState] { MediaRemoteFixtures.states + media + customLights + sprinklers }

    /// The scripted devices' booleans come from ``ScriptPowerActions/all`` (the document); the demo
    /// document's own tiles for them are seeded too. The last device reads on.
    static var media: [EntityState] {
        [entity("media_player.demo_living_room_1", "playing"),
         entity("input_boolean.demo_switch_1", "off"),
         entity("input_boolean.demo_input_boolean_5", "on")]
            + ScriptPowerActions.all.enumerated().map { index, device in
                entity(device.activeEntityId, index == ScriptPowerActions.all.count - 1 ? "on" : "off")
            }
    }

    static var customLights: [EntityState] {
        let color: [String: JSONValue] = ["supported_color_modes": .array([.string("color_temp"), .string("xy")])]
        let colors = [rgb(0, 255, 0), rgb(0, 0, 255), rgb(255, 0, 234), rgb(255, 0, 0), rgb(0, 255, 0), rgb(255, 137, 14), rgb(0, 0, 255)]
        var states = [
            entity(CustomLightsConfig.manualControlEntityId, "on"),
            entity(CustomLightsConfig.modeEntityId, "Custom", ["options": .array(CustomLightsConfig.fallbackModes.map(JSONValue.string))]),
            entity(CustomLightsConfig.groupEntityId, "on", color),
        ]
        for (index, light) in CustomLightsConfig.lights.enumerated() {
            if index < colors.count {
                states.append(entity(light.entityId, "on", color.merging(["brightness": .number(Double(255 - index * 25)), "rgb_color": colors[index]]) { $1 }))
            } else {
                states.append(entity(light.entityId, "off", color))
            }
        }
        return states
    }

    static var sprinklers: [EntityState] {
        // The first controller is the one-zone, ready fixture and the last the low-battery, four-zone one (by position).
        let controllers = SprinklersConfig.controllers
        guard controllers.count > 1, let front = controllers.first, let back = controllers.last else {
            return [entity(SprinklersConfig.visibilityEntityId, "on")]
        }
        return [
            entity(SprinklersConfig.visibilityEntityId, "on"),
            // Front yard: ready, one zone.
            entity(front.stateEntityId, "auto"),
            entity(front.modeEntityId, "auto"),
            entity(front.batteryEntityId, "86"),
            entity(front.faultEntityId, "off"),
            entity(front.hubConnectedEntityId, "on"),
            entity(front.nextWateringEntityId, "2026-10-12T13:30:00+00:00"),
            entity(front.rainDelayEntityId, "off"),
            entity(front.smartWateringEntityId, "on"),
        ] + zoneStates(front, zones: frontZones) + [
            // Backyard: low battery, the House zone watering.
            entity(back.stateEntityId, "auto"),
            entity(back.modeEntityId, "auto"),
            entity(back.batteryEntityId, "18"),
            entity(back.faultEntityId, "off"),
            entity(back.hubConnectedEntityId, "on"),
            entity(back.nextWateringEntityId, "unknown"),
            entity(back.rainDelayEntityId, "off"),
            entity(back.smartWateringEntityId, "off"),
        ] + zoneStates(back, zones: backZones)
    }

    /// One zone's fixture row: the valve, its program and its last run.
    private struct ZoneFixture {
        var name: String
        var open = false
        var days: [Double]
        var times: [String]
        var budget: Double
        var minutes: Double
        var on = true
        var history: String?
    }

    private static let frontZones = [
        ZoneFixture(name: "Front Yard", days: [1, 3, 5], times: ["06:30"], budget: 100, minutes: 20, history: "2026-10-10T13:30:00+00:00"),
    ]

    private static let backZones = [
        ZoneFixture(name: "Bushes", days: [0, 1, 2, 3, 4, 5, 6], times: ["05:00", "19:00"], budget: 80, minutes: 10, history: "2026-10-11T12:00:00+00:00"),
        ZoneFixture(name: "House", open: true, days: [2, 4], times: ["06:00"], budget: 100, minutes: 15, history: "2026-10-11T15:00:00+00:00"),
        ZoneFixture(name: "Backyard", days: [6], times: ["07:15"], budget: 120, minutes: 25, on: false),
        ZoneFixture(name: "Sidewalk", days: [], times: [], budget: 100, minutes: 5, on: false),
    ]

    /// The valve, program and history states for the controller's zones, paired with `zones` by position.
    private static func zoneStates(_ controller: SprinklersConfig.Controller, zones: [ZoneFixture]) -> [EntityState] {
        zip(controller.zones, zones.enumerated()).flatMap { zone, entry -> [EntityState] in
            let (index, fixture) = entry
            var states = [
                entity(zone.valveEntityId, fixture.open ? "open" : "closed", ["zone_name": .string(fixture.name), "station": .number(Double(index + 1))]),
                entity(zone.programEntityId, fixture.on ? "on" : "off", [
                    "frequency": .object(["type": .string("days"), "days": numbers(fixture.days)]),
                    "start_times": .array(fixture.times.map(JSONValue.string)),
                    "budget": .number(fixture.budget),
                    "run_times": .array([.object(["station": .number(Double(index + 1)), "run_time": .number(fixture.minutes)])]),
                ]),
            ]
            if let start = fixture.history {
                states.append(entity(zone.historyEntityId, start, ["start_time": .string(start), "run_time": .number(fixture.minutes)]))
            }
            return states
        }
    }
}
#endif
