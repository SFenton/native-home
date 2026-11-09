#if DEBUG
import HassCore
import HassDesign
import Observation
import SwiftUI

/// Records calls and echoes them into the fixture store after short delays, like Home Assistant: a garage door
/// reports `opening` then `open`, locks and the alarm switch at once.
@MainActor
@Observable
final class SecurityGalleryRecorder: HassServiceCalling {
    private(set) var lastCall = "None"
    @ObservationIgnored private let store: EntityStore
    @ObservationIgnored private let fails: Bool

    struct Failure: Error {}

    init(store: EntityStore, fails: Bool) {
        self.store = store
        self.fails = fails
    }

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        lastCall = GalleryServiceRecorder.describe(domain, service, data)
        // A door's "Sending…" lasts until the call returns; hold it long enough for a journey to read it.
        try? await Task.sleep(for: domain == "cover" ? .seconds(2.5) : .milliseconds(300))
        if fails { throw Failure() }
        guard let target = data["entity_id"] as? String else { return }
        switch (domain, service) {
        case ("cover", "open_cover"): moveDoor(target, through: "opening", to: "open")
        case ("cover", "close_cover"): moveDoor(target, through: "closing", to: "closed")
        case ("lock", "lock"): set(target, "locked")
        case ("lock", "unlock"): set(target, "unlocked")
        case ("alarm_control_panel", _):
            if let mode = SecurityConfig.alarmModes.first(where: { $0.service == service }) { set(target, mode.state) }
        default: break
        }
    }

    private func moveDoor(_ id: String, through moving: String, to final: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            set(id, moving)
            try? await Task.sleep(for: .seconds(3))
            set(id, final)
        }
    }

    private func set(_ id: String, _ state: String) {
        var entity = store.value(id) ?? EntityState(entityId: id, state: state)
        entity.state = state
        entity.lastChanged = .now
        store.apply([entity])
    }
}

/// Synthetic Security states for the gallery and hosted tests (not a copy of the live house).
enum SecurityFixtures {
    /// Which house the fixtures describe.
    enum Scenario: String {
        /// Armed Home, the front door locked, the left door closed and the right one open.
        case standard
        /// Home Assistant lost the alarm, locks and doors.
        case unavailable
        /// The alarm is sounding.
        case triggered
        /// A door is open, someone is home and the system is off: the Contact Sensors chip's amber state.
        case openHome
        /// A door is open and the household is away: the coral state.
        case openAway
        /// A door is open while the system is armed: the red state with the alert glyph.
        case openArmed
    }

    /// - Parameter unavailable: Report the alarm, locks and doors as `unavailable` (Home Assistant lost them).
    @MainActor static func store(unavailable: Bool = false) -> EntityStore {
        store(unavailable ? .unavailable : .standard)
    }

    @MainActor static func store(_ scenario: Scenario) -> EntityStore {
        let store = EntityStore()
        store.replaceAll(states(scenario), freshness: .live)
        return store
    }

    /// The states for a scenario. The alarm entered its mode 40 minutes ago, so the card reads "Since …".
    static func states(_ scenario: Scenario) -> [EntityState] {
        let since = Date.now.addingTimeInterval(-40 * 60)
        let mode: String? = switch scenario {
        case .triggered: "triggered"
        case .openHome, .openAway: "disarmed"
        case .standard, .unavailable, .openArmed: nil
        }
        var states = (scenario == .unavailable ? unavailableStates : states).map { entity in
            guard entity.entityId == SecurityConfig.alarmEntityId, scenario != .unavailable else { return entity }
            return EntityState(entityId: entity.entityId, state: mode ?? entity.state, attributes: entity.attributes, lastChanged: since)
        }
        // The Contact Sensors chip counts the real sensors: the open scenarios open one and set the house around it.
        if [.openHome, .openAway, .openArmed].contains(scenario) {
            if let contact = RoomOverview.contactEntityIds.first { states.append(EntityState(entityId: contact, state: "on")) }
            states.append(EntityState(entityId: ClimateConfig.homeAwayEntityId, state: scenario == .openAway ? "Away" : "Home"))
        }
        return states
    }

    /// ``states`` with every tile's entity reporting `unavailable`.
    static var unavailableStates: [EntityState] {
        let tiles: Set = [
            SecurityConfig.alarmEntityId, SecurityConfig.frontDoorLockEntityId, SecurityConfig.leftGarageDoorEntityId,
            SecurityConfig.rightGarageDoorEntityId, SecurityConfig.vehicleLockEntityId,
        ]
        return states.map { tiles.contains($0.entityId) ? EntityState(entityId: $0.entityId, state: "unavailable") : $0 }
    }

    /// Read at each call: the entity ids are the house facade's, which answer with the demo house in the gallery.
    static var states: [EntityState] {
        [
            EntityState(entityId: SecurityConfig.alarmEntityId, state: "armed_home"),
            EntityState(entityId: SecurityConfig.frontDoorLockEntityId, state: "locked"),
            EntityState(entityId: SecurityConfig.leftGarageDoorEntityId, state: "closed"),
            EntityState(entityId: SecurityConfig.rightGarageDoorEntityId, state: "open"),
            EntityState(entityId: SecurityConfig.vehicleLockEntityId, state: "locked"),
            EntityState(entityId: SecurityConfig.contactSensorsEntityId, state: "on", attributes: [
                "entity_id": .array([.string("binary_sensor.demo_front_door_contact"), .string("binary_sensor.demo_back_door_contact")]),
            ]),
            EntityState(entityId: "binary_sensor.demo_front_door_contact", state: "off", attributes: ["friendly_name": .string("Front Door")]),
            EntityState(entityId: "binary_sensor.demo_back_door_contact", state: "on", attributes: ["friendly_name": .string("Back Door")]),
        ]
    }
}
#endif
