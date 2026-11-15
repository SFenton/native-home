import Foundation

// MARK: - Semantic descriptor validation

enum ServerUIVacuumValidation {
    static func validate(_ d: ServerUIVacuumDescriptor, at path: String) -> [ServerUICompositionError] {
        var issues: [ServerUICompositionError] = []
        func entity(_ value: String?, _ key: String, _ domains: [String]) {
            guard let value else { return }
            if !ServerUICompositionShape.matches(value, "^[a-z][a-z0-9_]*\\.[a-z0-9_]+$") {
                issues.append(.init(.invalidValue, path + "/" + key))
            } else if !domains.contains(String(value.prefix(while: { $0 != "." }))) {
                issues.append(.init(.invalidCombination, path + "/" + key))
            }
        }
        entity(d.entityId, "entityId", ["vacuum"])
        entity(d.batteryEntityId, "batteryEntityId", ["sensor"])
        entity(d.errorEntityId, "errorEntityId", ["sensor"])
        entity(d.statusEntityId, "statusEntityId", ["sensor"])
        entity(d.statusFlagEntityId, "statusFlagEntityId", ["sensor", "input_text"])
        entity(d.passesEntityId, "passesEntityId", ["select", "input_select"])
        entity(d.cleanScript, "cleanScript", ["script"])
        entity(d.coordinatorSessionEntityId, "coordinatorSessionEntityId", ["sensor"])
        entity(d.dockButtonEntityId, "dockButtonEntityId", ["button"])
        entity(d.modeTextEntityId, "modeTextEntityId", ["input_text", "sensor"])
        if let control = d.autoCleanControl {
            entity(control.entityId, "autoCleanControl/entityId", [control.kind == .pause ? "switch" : "automation"])
        }
        for (key, value) in [("modeEntityId", d.modeEntityId), ("fanEntityId", d.fanEntityId), ("waterEntityId", d.waterEntityId)] {
            entity(value, key, ["select", "input_select"])
        }
        if let area = d.areaCleaning { entity(area.script, "areaCleaning/script", ["script"]) }
        if let dock = d.dockControls {
            entity(dock.cleanScript, "dockControls/cleanScript", ["script"])
            entity(dock.dryScript, "dockControls/dryScript", ["script"])
            entity(dock.dockStatusEntityId, "dockControls/dockStatusEntityId", ["sensor"])
            entity(dock.mopAttachmentEntityId, "dockControls/mopAttachmentEntityId", ["binary_sensor"])
        }
        if !ServerUICompositionShape.matches(d.vacuumMapId, "^[a-z][a-z0-9_]*$") {
            issues.append(.init(.invalidValue, path + "/vacuumMapId"))
        }
        func unique(_ ids: [String], _ key: String) {
            if Set(ids).count != ids.count { issues.append(.init(.invalidCombination, path + "/" + key)) }
        }
        for (i, room) in d.zones.enumerated() {
            entity(room.entityId, "zones/\(i)/entityId", ["input_boolean"])
            entity(room.mopRequiredEntityId, "zones/\(i)/mopRequiredEntityId", ["sensor"])
        }
        for (i, room) in d.autoCleanDisabledRooms.enumerated() { entity(room.entityId, "autoCleanDisabledRooms/\(i)/entityId", ["switch"]) }
        for (i, value) in d.consumables.enumerated() { entity(value.entityId, "consumables/\(i)/entityId", ["sensor", "binary_sensor"]) }
        for (i, value) in d.outcomeReconciliations.enumerated() { entity(value.entityId, "outcomeReconciliations/\(i)/entityId", ["input_text"]) }
        unique(d.zones.map(\.entityId), "zones")
        unique(d.autoCleanDisabledRooms.map(\.entityId), "autoCleanDisabledRooms")
        unique(d.consumables.map(\.entityId), "consumables")
        unique(d.outcomeRoomNames.map(\.roomId), "outcomeRoomNames")
        unique(d.outcomeReconciliations.map(\.roomId), "outcomeReconciliations")
        return issues
    }
}
