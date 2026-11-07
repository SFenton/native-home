#if DEBUG
import Foundation
import HassCore
import HassDesign
import SwiftUI

/// Synthetic vacuum states for the gallery and hosted tests (not a copy of the live house).
enum VacuumFixtures {
    enum Scenario: String, Sendable {
        case docked, cleaning, paused, error, resumable, unavailable
        case dockWash, dockPrep, noMop, modeVacuum, modeMop, areaDrawn, autoUnavailable
    }

    /// The area `areaDrawn` draws on Main Floor's mock map (grid cells inside its bounds).
    static let drawnArea = MapGridRect(x0: 595, x1: 665, y0: 700, y1: 780)

    /// Every script and integration service the sheets check for.
    static var services: Set<String> {
        var names: Set<String> = ["valetudo_vacuum_coordinator.dock_action"]
        for vacuum in Vacuums.all {
            names.insert(vacuum.cleanScript)
            if let area = vacuum.areaCleaning { names.insert(area.script) }
            if let dock = vacuum.dockControls { names.formUnion([dock.cleanScript, dock.dryScript]) }
        }
        return names
    }

    /// A loader holding the vacuum's mock map, reported when the robot is unavailable.
    @MainActor static func loader(_ vacuum: VacuumConfig, scenario: Scenario) -> ValetudoMapLoader {
        let loader = ValetudoMapLoader { _ in throw URLError(.notConnectedToInternet) }
        loader.show(ValetudoMapFixtures.map(vacuum.vacuumMapId), provenance: scenario == .unavailable ? .reported : .live)
        return loader
    }

    @MainActor static func store(_ scenario: Scenario = .docked) -> EntityStore {
        let store = EntityStore()
        store.replaceAll(states(scenario), freshness: .live)
        return store
    }

    static func states(_ scenario: Scenario) -> [EntityState] {
        func entity(_ id: String, _ state: String, _ attributes: [String: JSONValue] = [:], changed: Date = .distantPast) -> EntityState {
            EntityState(entityId: id, state: state, attributes: attributes, lastChanged: changed)
        }
        func options(_ values: [String]) -> [String: JSONValue] { ["options": .array(values.map(JSONValue.string))] }
        let base = Date(timeIntervalSince1970: 1_760_000_000)
        var states: [EntityState] = []
        for (index, vacuum) in Vacuums.all.enumerated() {
            let m = vacuum.vacuumMapId
            let robot: String = switch scenario {
            case .docked, .resumable, .dockWash, .noMop, .modeVacuum, .modeMop, .areaDrawn, .autoUnavailable: "docked"
            case .cleaning, .dockPrep: "cleaning"
            case .paused: "paused"
            case .error: "error"
            case .unavailable: "unavailable"
            }
            states += [
                entity(vacuum.entityId, robot),
                entity(vacuum.batteryEntityId, scenario == .unavailable ? "unavailable" : ["87", "100", "64"][index % 3]),
                entity(vacuum.errorEntityId, scenario == .error ? "Main brush jammed" : "No error"),
                entity(vacuum.statusFlagEntityId, scenario == .resumable ? "resumable" : "none"),
                entity(vacuum.passesEntityId, "1", options(["1", "2", "3"])),
                entity("select.\(m)_mode", scenario == .modeVacuum ? "vacuum" : scenario == .modeMop ? "mop" : "vacuum_and_mop", options(["vacuum", "mop", "vacuum_and_mop"])),
                entity("select.\(m)_fan", "medium", options(["low", "medium", "high", "max", "turbo"])),
                entity("select.\(m)_water", "medium", options(["low", "medium", "high"])),
                entity("binary_sensor.\(m)_mop_attachment", scenario == .noMop ? "off" : "on"),
                entity("button.\(m)_trigger_auto_empty_dock", "unknown"),
                entity(vacuum.mapCameraEntityId, "idle"),
            ]
            if let dock = vacuum.dockControls { states.append(entity(dock.dockStatusEntityId, [.dockWash, .dockPrep].contains(scenario) ? "cleaning" : "idle")) }
            if let modeText = vacuum.modeTextEntityId {
                states.append(entity(modeText, scenario == .modeVacuum ? "Vacuum" : scenario == .modeMop ? "Mop" : "Vacuum and Mop"))
            }
            for consumable in vacuum.consumables {
                let value: String = consumable.valueKind == .status
                    ? (consumable.title == "Dustbag" ? "full" : "ok")
                    : (consumable.title == "Main Filter" ? "420" : consumable.title == "Sensors" ? "0" : "5400")
                states.append(entity(consumable.entityId, value, consumable.valueKind == .duration ? ["unit_of_measurement": .string("min")] : [:]))
            }
            for (zoneIndex, zone) in vacuum.zones.enumerated() {
                let selected = scenario == .areaDrawn ? false : vacuum.zones.count > 4 ? [2, 0].contains(zoneIndex) : zoneIndex == 0
                states.append(entity(zone.entityId, selected ? "on" : "off", changed: base.addingTimeInterval(zoneIndex == 2 ? 10 : Double(20 + zoneIndex))))
                if let mop = zone.mopRequiredEntityId {
                    states.append(entity(mop, "2025-10-09T10:00:00+00:00", ["mop_required": .bool(["kitchen", "master_bathroom", "guest_bathroom", "dining_room"].contains { mop.contains($0) })]))
                }
            }
            for (roomIndex, room) in vacuum.autoCleanDisabledRooms.enumerated() {
                states.append(entity(room.entityId, scenario == .autoUnavailable && room.title == "Gym" ? "unavailable" : roomIndex == 5 ? "on" : "off"))
            }
            for (_, entityId) in Vacuums.outcomeReconciliations(m) { states.append(entity(entityId, "")) }
            if let session = vacuum.coordinatorSessionEntityId {
                states.append(entity(session, "idle", ["while_away_outcomes": VacuumOutcomeFixtures.sample]))
            }
        }
        for control in Vacuums.autoCleanControls {
            states.append(entity(control.entityId, control.kind == .pause ? "off" : "on"))
        }
        return states
    }

    /// What the robot does after a command, so journeys see the next state.
    @MainActor static func echo(_ domain: String, _ service: String, target: String?, store: EntityStore) {
        func set(_ id: String, _ state: String) {
            var entity = store.value(id) ?? EntityState(entityId: id, state: state)
            entity.state = state
            store.apply([entity])
        }
        if domain == "vacuum", let target {
            switch service {
            case "start": set(target, "cleaning")
            case "pause": set(target, "paused")
            case "stop": set(target, store.value(target)?.state == "docked" ? "docked" : "idle")
            case "return_to_base": set(target, "returning")
            default: break
            }
            return
        }
        guard domain == "script" else { return }
        for vacuum in Vacuums.all {
            if service == vacuum.cleanScript.dropPrefix("script.") || service == vacuum.areaCleaning?.script.dropPrefix("script.") {
                set(vacuum.entityId, "cleaning")
            }
            if let dock = vacuum.dockControls {
                let current = store.value(dock.dockStatusEntityId)?.state
                if service == dock.cleanScript.dropPrefix("script.") { set(dock.dockStatusEntityId, current == "cleaning" ? "idle" : "cleaning") }
                if service == dock.dryScript.dropPrefix("script.") { set(dock.dockStatusEntityId, current == "drying" ? "idle" : "drying") }
            }
        }
    }
}

private extension String {
    func dropPrefix(_ prefix: String) -> String { hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self }
}
#endif
