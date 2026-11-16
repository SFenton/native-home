#if DEBUG
import HassCore
import HassDesign
import Observation
import SwiftUI

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
        let since = GalleryFixtureClock.shared.now.addingTimeInterval(-40 * 60)
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
