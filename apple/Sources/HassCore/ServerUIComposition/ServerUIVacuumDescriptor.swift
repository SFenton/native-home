import Foundation

// MARK: - Configured vacuum source

/// Wire-only descriptor. Targets and map transforms are authored, never resolved from house globals.
public struct ServerUIVacuumDescriptor: Codable, Equatable, Sendable {
    /// The authored auto clean.
    public struct AutoClean: Codable, Equatable, Sendable {
        /// The authored kind choices.
        public enum Kind: String, Codable, Sendable { case automation, pause }
        public let title: String
        public let entityId: String
        public let kind: Kind
        public var configuration: Vacuums.AutoCleanControl {
            .init(title: title, entityId: entityId, icon: "mdi:clock-outline", kind: kind == .pause ? .pause : .automation)
        }
    }
    /// The authored consumable.
    public struct Consumable: Codable, Equatable, Sendable {
        /// The authored kind choices.
        public enum Kind: String, Codable, Sendable { case duration, status }
        public let title: String
        public let entityId: String
        public let icon: String
        public let kind: Kind
    }

    /// The authored reconciliation.
    public struct Reconciliation: Codable, Equatable, Sendable {
        public let roomId: String
        public let entityId: String
    }
    /// The authored room name.
    public struct RoomName: Codable, Equatable, Sendable {
        public let roomId: String
        public let name: String
    }

    public let title: String
    public let entityId: String
    public let batteryEntityId: String
    public let cleanScript: String
    public let consumables: [Consumable]
    public let coordinatorSessionEntityId: String?
    public let dockButtonEntityId: String?
    public let dockControls: VacuumConfig.DockControls?
    public let errorEntityId: String
    public let fanEntityId: String?
    public let areaCleaning: VacuumConfig.AreaCleaning?
    public let autoCleanDisabledRooms: [VacuumConfig.AutoCleanRoom]
    public let autoCleanControl: AutoClean?
    public let mapFocus: VacuumConfig.MapFocus?
    public let mapRoomSelection: Bool
    public let mapRotationDegrees: Double
    public let mapScale: Double
    public let modeEntityId: String?
    public let modeTextEntityId: String?
    public let outcomeRoomNames: [RoomName]
    public let outcomeReconciliations: [Reconciliation]
    public let passesEntityId: String
    public let statusEntityId: String
    public let statusFlagEntityId: String
    public let vacuumMapId: String
    public let waterEntityId: String?
    public let zoneDescription: [String]
    public let zones: [VacuumConfig.Zone]

    /// Converts the validated wire descriptor to the existing command and map model.
    public var configuration: VacuumConfig {
        VacuumConfig(
            title: title, entityId: entityId, batteryEntityId: batteryEntityId, cleanScript: cleanScript,
            consumables: consumables.map {
                .init(title: $0.title, entityId: $0.entityId, icon: $0.icon,
                      valueKind: $0.kind == .duration ? .duration : .status)
            }, coordinatorSessionEntityId: coordinatorSessionEntityId, dockButtonEntityId: dockButtonEntityId,
            dockControls: dockControls, errorEntityId: errorEntityId, fanEntityId: fanEntityId,
            areaCleaning: areaCleaning, autoCleanDisabledRooms: autoCleanDisabledRooms, mapFocus: mapFocus,
            mapRoomSelection: mapRoomSelection, mapRotationDegrees: mapRotationDegrees, mapScale: mapScale,
            modeEntityId: modeEntityId, modeTextEntityId: modeTextEntityId,
            outcomeRoomNames: Dictionary(outcomeRoomNames.map { ($0.roomId, $0.name) }, uniquingKeysWith: { first, _ in first }),
            passesEntityId: passesEntityId, statusEntityId: statusEntityId, statusFlagEntityId: statusFlagEntityId,
            vacuumMapId: vacuumMapId, waterEntityId: waterEntityId, zoneDescription: zoneDescription, zones: zones
        )
    }
}

// MARK: - Atomic presentation contract

public extension ServerUICompositionDocument {
    /// A native domain primitive, not a feature/page dispatch key. Containers and tabs remain shell-owned.
    struct VacuumControl: Equatable, Sendable {
        public let node: Node
        public let sourceId: String
        public let primitive: VacuumPrimitive
    }

    enum VacuumPrimitive: Equatable, Sendable {
        case card(icon: Symbol, commands: [VacuumCardCommand], destination: Action)
        case map(overlay: VacuumMapOverlay, height: Double, runtimeHeight: Double,
                 label: String, loading: String, unavailable: String, locate: Bool)
        case status(metric: VacuumMetric)
        case notices
        case autoClean
        case settings(rows: [VacuumSettingLabel])
        case command(kind: VacuumController.Action.Kind, icon: Symbol)
        case choice(entityId: String, selection: VacuumSelection)
        case consumable(entityId: String)
        case report(destination: Action)
        case outcomes
        case target(mode: VacuumTarget, icon: Symbol, destination: Action)
        case clearArea(icon: Symbol)
        case areaEditor(height: Double, use: Action, discardLabel: String, discard: Action)
    }
    enum VacuumMapOverlay: String, Sendable { case rooms, autoClean }
    enum VacuumCardCommand: String, Sendable { case startPause = "start_pause", dock }
    enum VacuumMetric: String, Sendable { case status, battery, dock }
    enum VacuumSelection: String, Sendable { case rooms, autoClean }
    enum VacuumTarget: String, Sendable { case rooms, area }
    struct VacuumSettingLabel: Equatable, Sendable {
        public let role: VacuumSettingRole
        public let title: String
        public let hint: String
    }
}
