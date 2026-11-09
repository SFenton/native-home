#if DEBUG
import HassCore
import HassDesign
import Observation
import SwiftUI

/// Records service calls and echoes them into the fixture store after a short delay, like Home Assistant.
@MainActor
@Observable
final class HouseholdGalleryRecorder: HassServiceCalling {
    private(set) var lastCall = "None"
    @ObservationIgnored private let store: EntityStore

    init(store: EntityStore) { self.store = store }

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        lastCall = GalleryServiceRecorder.describe(domain, service, data)
        try? await Task.sleep(for: .milliseconds(400))
        echo(domain, service, data)
    }

    private func echo(_ domain: String, _ service: String, _ data: [String: any Sendable]) {
        guard let target = data["entity_id"] as? String, var entity = store.value(target) else { return }
        switch (domain, service) {
        case (_, "turn_on"): entity.state = "on"
        case (_, "turn_off"): entity.state = "off"
        case ("lock", "lock"): entity.state = "locked"
        case ("lock", "unlock"): entity.state = "unlocked"
        case ("presence_based_lighting", "set_automation_state"):
            let mode = data["state"] as? String ?? "active"
            entity.state = mode == "off" ? "off" : "on"
            entity.attributes["automation_state"] = .string(mode)
        default: return
        }
        store.apply([entity])
    }
}

/// Synthetic states for the gallery and hosted tests (not a copy of the live house).
enum HouseholdSettingsFixtures {
    /// A store with every household entity, in a spread of states.
    @MainActor static func store(unavailable: Bool = false) -> EntityStore {
        let store = EntityStore()
        store.replaceAll(states(unavailable: unavailable))
        return store
    }

    static func states(unavailable: Bool = false) -> [EntityState] {
        typealias Config = HouseholdSettingsConfig
        let admin = Config.Admin.self
        if unavailable {
            let ids = Config.toggleEntityIds + [admin.powerRecoveryAutomation] + admin.presenceRooms.map(\.presenceEntityId) + Config.Vehicle.tiles.map(\.entityId)
            return ids.map { EntityState(entityId: $0, state: "unavailable") }
        }
        var states: [EntityState] = []
        func add(_ id: String, _ state: String, _ attributes: [String: JSONValue] = [:]) {
            states.append(EntityState(entityId: id, state: state, attributes: attributes))
        }
        // Tile lists come from the house document: a shorter list gets fewer states, never an out-of-range read.
        func add(_ tiles: [Config.Tile], _ values: [String]) {
            for (tile, value) in zip(tiles, values) { add(tile.entityId, value) }
        }
        add(admin.securityTiles, ["on"])
        add(admin.powerRecoveryAutomation, "on")
        add(admin.relayControlEntityId, "on")
        add(admin.showSpecificTiles, ["off", "on"])
        add(Config.SpecialDeviceModes.highAqiTile.entityId, "off")
        for (index, tile) in Config.Guests.tiles.enumerated() { add(tile.entityId, index == 0 ? "on" : "off") }
        // Cycle the rooms through every mode, with one unavailable.
        let modes: [(String, [String: JSONValue])] = [
            ("on", ["automation_state": .string("active")]),
            ("off", [:]),
            ("on", ["automation_state": .string("paused")]),
            ("on", ["automation_quieted": .bool(true)]),
        ]
        for (index, room) in admin.presenceRooms.enumerated() {
            if room.title == "Upper Deck" {
                add(room.presenceEntityId, "unavailable")
            } else {
                let mode = modes[index % modes.count]
                add(room.presenceEntityId, mode.0, mode.1)
            }
            add(room.autoReenableEntityId, index.isMultiple(of: 3) ? "off" : "on")
        }
        let vehicleTiles = Config.Vehicle.tiles
        add(vehicleTiles, ["ChargingAC", "locked", "off", "heated_low", "72"])
        return states
    }
}
#endif
