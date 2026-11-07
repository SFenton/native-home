#if DEBUG
import HassCore
import HassDesign
import SwiftUI

/// The gallery's service caller: records every call for the "Last call" line, and answers calls that return a
/// response (wake light, Solo Trip) like Home Assistant through the bedroom gallery's recorder, so the Master
/// Bedroom's wake-light and bed sheets open here too.
@MainActor
final class RoomsGalleryCaller: HassServiceResponding {
    let recorder: GalleryServiceRecorder
    let bedroom: BedroomGalleryRecorder

    init(recorder: GalleryServiceRecorder, bedroom: BedroomGalleryRecorder) {
        self.recorder = recorder
        self.bedroom = bedroom
    }

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        try await recorder.callService(domain, service, data: data)
    }

    func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        try? await recorder.callService(domain, service, data: data)
        return try await bedroom.callServiceWithResponse(domain, service, data: data)
    }
}

/// Synthetic states for every room card, group, counter and Quick Links tile (not a copy of the live house).
enum RoomsFixtures {
    @MainActor static func store() -> EntityStore {
        let store = EntityStore()
        store.replaceAll(states, freshness: .live)
        return store
    }

    /// Built on every read, not cached: it reads `FENTON_GALLERY_SCENARIO` and stamps the fan timer from the clock, and a reused app
    /// (`.agents/testing/apple/app-reuse.md`) must see each reset's scenario and a fresh countdown.
    static var states: [EntityState] {
        var byId: [String: EntityState] = [:]
        func add(_ id: String, _ state: String, _ attributes: [String: JSONValue] = [:]) {
            if byId[id] == nil { byId[id] = EntityState(entityId: id, state: state, attributes: attributes) }
        }
        for state in MediaRemoteFixtures.states { byId[state.entityId] = state }
        // Device sheets wired from room cards: the room device lane's fixtures (fans off and unlocked).
        // The Guest Bathroom fan is off and unlocked; the Master's is on, locked and timed (12:34 left), so the room
        // pages show the "Off in 12:34" status and a lit lock. `FENTON_GALLERY_SCENARIO=fan-unavailable` makes the
        // Guest fan's entities unavailable (no buttons, "Unavailable").
        let fanScenario = ProcessInfo.processInfo.environment["FENTON_GALLERY_SCENARIO"]
        let fans = BathroomFanConfig.all
        let devices = (fans.first.map { RoomDeviceFixture.fanStates($0, power: "off", locked: false, pending: false, now: Date()) } ?? [])
            + (fans.dropFirst().first.map { RoomDeviceFixture.fanStates($0, power: "on", locked: true, pending: true, now: Date()) } ?? [])
            + AirPurifierConfig.all.flatMap { RoomDeviceFixture.purifierStates($0, mode: "Auto", percentage: 33) }
            + RoomDeviceFixture.grillStates
        for state in devices { byId[state.entityId] = state }
        if fanScenario == "fan-unavailable" {
            for state in (fans.first.map { RoomDeviceFixture.fanStates($0, power: "off", locked: false, pending: false, now: Date()) } ?? []) {
                byId[state.entityId] = EntityState(entityId: state.entityId, state: "unavailable", attributes: [:])
            }
        }
        // Wake light and both bed sides with schedules (the bedroom lane's fixtures).
        for state in BedroomFixtures.states(.default) { byId[state.entityId] = state }

        // A lived-in evening: some lights on, one room occupied, one window open.
        add("light.demo_living_room_item_1", "on", ["brightness": .number(180), "supported_color_modes": .array([.string("brightness")])])
        add("binary_sensor.demo_living_room_1", "on")
        add("binary_sensor.demo_living_room_contact_1", "on")
        // The live pods sit in heat mode. One heats (filled); one has nothing running, so it draws its off face with
        // the Heating glyph (`ThermostatTileFace`). The bedroom fixtures' own attributes stay.
        func setPod(_ id: String, state: String, action: String) {
            var attributes = byId[id]?.attributes ?? [:]
            attributes["hvac_action"] = .string(action)
            byId[id] = EntityState(entityId: id, state: state, attributes: attributes)
        }
        setPod("climate.demo_climate_1", state: "heat", action: "heating")
        setPod("climate.demo_climate_2", state: "heat", action: "idle")
        add(MasterBedroom.wakeLight.statusEntityId, "6:45 AM")
        add(RoomsConfig.dishwasherProgramEntityId, "Eco 50°C")

        let groups = RoomsConfig.pages.flatMap { page in
            [RoomGroups.lights(room: page.title), RoomGroups.climate(room: page.title),
             RoomGroups.occupancy(room: page.title), RoomGroups.contacts(room: page.title)].compactMap { $0 }
        } + RoomGroups.allContacts
        for group in groups {
            for item in group.items { add(item.entityId, defaultState(item.entityId), defaultAttributes(item.entityId)) }
        }
        for card in RoomsConfig.pages.flatMap(\.allCards) {
            for id in [card.entityId, card.modalEntityId].compactMap({ $0 }) + card.subtitleEntityIds + card.modalItems.map(\.entityId) {
                add(id, defaultState(id), defaultAttributes(id))
            }
            if card.kind == .air { add(RoomFormat.aqiEntityId(forPM25: card.modalEntityId ?? card.entityId), "38") }
            if let alternate = card.alternate { add(alternate.whenEntityId, "off"); add(alternate.entityId, defaultState(alternate.entityId)) }
        }
        for (index, item) in RoomNavigation.items.enumerated() {
            add(item.accessCounterEntityId, "\([4, 1, 2, 9, 7, 0, 12, 5, 1, 3][index % 10])")
        }
        add(QuickLinks.securityEntityId, "armed_home")
        add(SprinklersConfig.visibilityEntityId, "on")
        add(QuickLinks.totalItemsEntityId, "42")
        add(QuickLinks.expiringSoonEntityId, "3")
        add(RoomsConfig.Groceries.listEntityId, "5")
        return Array(byId.values)
    }

    private static func defaultState(_ id: String) -> String {
        let domain = id.prefix { $0 != "." }
        switch domain {
        case "light", "switch", "input_boolean", "fan": return "off"
        case "binary_sensor": return "off"
        case "cover": return "open"
        case "vacuum": return "docked"
        case "media_player": return "off"
        case "select": return "Auto"
        case "climate": return "off"
        case "input_text":
            if id.hasSuffix("_climate_range") { return "68–72°F" }
            if id.hasSuffix("_power_state") { return "Off" }
            return "—"
        case "sensor":
            if id.contains("temperature") { return "70.4" }
            if id.contains("humidity") { return "44" }
            if id.contains("pm2_5") { return "6" }
            return "Ready"
        default: return "off"
        }
    }

    private static func defaultAttributes(_ id: String) -> [String: JSONValue] {
        if id.hasPrefix("sensor."), id.contains("temperature") { return ["unit_of_measurement": .string("°F")] }
        if id.hasPrefix("sensor."), id.contains("humidity") { return ["unit_of_measurement": .string("%")] }
        if id.hasPrefix("sensor."), id.contains("pm2_5") { return ["unit_of_measurement": .string("µg/m³")] }
        if id.hasPrefix("light.") { return ["supported_color_modes": .array([.string("brightness")])] }
        // Vents report how far they are open, which their tiles show.
        if id.hasPrefix("cover.") { return ["current_position": .number(60)] }
        return [:]
    }
}
#endif
