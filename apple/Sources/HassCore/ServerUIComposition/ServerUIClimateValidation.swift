import Foundation

// MARK: - Semantic climate validation

enum ServerUIClimateValidation {
    typealias E = ServerUICompositionError

    static func source(_ source: ServerUIClimateSource, at path: String) -> [E] {
        var issues: [E] = []
        func entity(_ id: String, _ key: String, domains: [String]) {
            if !ServerUICompositionShape.matches(id, "^[a-z][a-z0-9_]*\\.[a-z0-9_]+$") {
                issues.append(E(.invalidValue, path + "/" + key))
            } else if !domains.contains(String(id.prefix(while: { $0 != "." }))) {
                issues.append(E(.invalidCombination, path + "/" + key))
            }
        }
        entity(source.entityId, "entityId", domains: ["climate", "switch", "input_boolean", "select", "sensor", "binary_sensor", "cover"])
        for (index, id) in source.rangeCommitEntityIds.enumerated() {
            entity(id, "rangeCommitEntityIds/\(index)", domains: ["climate"])
        }
        if Set(source.rangeCommitEntityIds).count != source.rangeCommitEntityIds.count {
            issues.append(E(.invalidCombination, path + "/rangeCommitEntityIds"))
        }
        if !source.rangeCommitEntityIds.isEmpty, !source.entityId.hasPrefix("climate.") {
            issues.append(E(.invalidCombination, path + "/rangeCommitEntityIds"))
        }
        if let id = source.actionEntityId { entity(id, "actionEntityId", domains: ["climate"]) }
        if let id = source.sensorEntityId { entity(id, "sensorEntityId", domains: ["sensor"]) }
        if let id = source.occupancyEntityId { entity(id, "occupancyEntityId", domains: ["sensor", "binary_sensor"]) }
        if let away = source.effectiveAway {
            if !source.entityId.hasPrefix("climate.") { issues.append(E(.invalidCombination, path + "/effectiveAway")) }
            entity(away.ecoEntityId, "effectiveAway/ecoEntityId", domains: ["climate"])
            entity(away.modeEntityId, "effectiveAway/modeEntityId", domains: ["sensor"])
            entity(away.fallbackEntityId, "effectiveAway/fallbackEntityId", domains: ["binary_sensor", "input_boolean"])
        }
        if let gate = source.trackingGate {
            entity(gate.selectedEntityId, "trackingGate/selectedEntityId", domains: ["switch", "input_boolean"])
            if let id = gate.criticalEntityId { entity(id, "trackingGate/criticalEntityId", domains: ["select"]) }
            if let id = gate.trackedEntityId { entity(id, "trackingGate/trackedEntityId", domains: ["switch", "input_boolean"]) }
            if (gate.criticalEntityId == nil) != (gate.criticalOption == nil) {
                issues.append(E(.invalidCombination, path + "/trackingGate"))
            }
        }
        if let status = source.homeAway {
            entity(status.modeEntityId, "homeAway/modeEntityId", domains: ["sensor"])
            entity(status.reasonEntityId, "homeAway/reasonEntityId", domains: ["sensor"])
            entity(status.fallbackEntityId, "homeAway/fallbackEntityId", domains: ["binary_sensor", "input_boolean"])
            entity(status.vacationEntityId, "homeAway/vacationEntityId", domains: ["switch", "input_boolean"])
        }
        if let tracking = source.tracking {
            entity(source.entityId, "entityId", domains: ["switch", "input_boolean"])
            entity(tracking.policyEntityId, "tracking/policyEntityId", domains: ["select"])
            var ids: Set<String> = []
            for (index, room) in tracking.rooms.enumerated() {
                for (key, id) in [("selectedEntityId", room.selectedEntityId), ("criticalEntityId", room.criticalEntityId),
                                  ("occupiedOnlyEntityId", room.occupiedOnlyEntityId)] {
                    entity(id, "tracking/rooms/\(index)/\(key)", domains: ["switch", "input_boolean"])
                    if !ids.insert(id).inserted { issues.append(E(.invalidCombination, path + "/tracking/rooms/\(index)/\(key)")) }
                }
            }
        }
        return issues
    }

    static func control(_ control: ServerUIClimateControl, source: ServerUIClimateSource, at path: String) -> [E] {
        let props = control.props
        let domains: [String]
        switch props.kind {
        case .dial, .mode, .fan, .preset, .hub, .notice, .roomTile: domains = ["climate"]
        case .toggle, .check: domains = ["switch", "input_boolean"]
        case .explicitSwitch: domains = ["switch"]
        case .options: domains = ["select"]
        case .status, .link: domains = ["climate", "switch", "input_boolean", "select", "sensor", "binary_sensor", "cover"]
        }
        var issues: [E] = []
        if props.kind == .notice, source.homeAway == nil { issues.append(E(.bindingType, path + "/sourceId")) }
        if props.kind == .roomTile, source.sensorEntityId == nil || source.occupancyEntityId == nil {
            issues.append(E(.bindingType, path + "/sourceId"))
        }
        if let projection = props.status?.projection, [.trackingSelected, .trackingCritical, .trackingOccupiedOnly].contains(projection),
           source.tracking == nil { issues.append(E(.bindingType, path + "/sourceId")) }
        if source.effectiveAway != nil, props.kind != .dial && props.kind != .status && props.kind != .notice {
            issues.append(E(.invalidCombination, path + "/sourceId"))
        }
        if !domains.contains(String(source.entityId.prefix(while: { $0 != "." }))) {
            issues.append(E(.bindingType, path + "/sourceId"))
        }
        if let dial = props.dial, dial.maximum <= dial.minimum || dial.step > dial.maximum - dial.minimum {
            issues.append(E(.invalidCombination, path + "/dial"))
        }
        if let choices = props.choices, Set(choices.map(\.value)).count != choices.count {
            issues.append(E(.invalidCombination, path + "/choices"))
        }
        if let hub = props.hub {
            if Set(hub.modes.map(\.value)).count != hub.modes.count { issues.append(E(.invalidCombination, path + "/hub/modes")) }
            if Set(hub.fans.map(\.value)).count != hub.fans.count { issues.append(E(.invalidCombination, path + "/hub/fans")) }
        }
        if let status = props.status, Set(status.states.map(\.state)).count != status.states.count {
            issues.append(E(.invalidCombination, path + "/status/states"))
        }
        return issues
    }
}
