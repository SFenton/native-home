import Foundation

/// One robot vacuum and the Home Assistant entities around it (web `VacuumConfig`).
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/constants/portedDashboard.ts:99` and `VACUUMS` (`:516`).
public struct VacuumConfig: Sendable, Identifiable, Hashable, Codable {
    /// Drawing a rectangle on the map and cleaning only that area.
    public struct AreaCleaning: Sendable, Hashable, Codable {
        /// The smallest side of a drawn area, in centimetres.
        public var minimumSizeCm: Double
        /// Script that cleans a zone (`x_min_cm`, `x_max_cm`, `y_min_cm`, `y_max_cm`).
        public var script: String
    }

    /// The mop dock's wash and dry actions.
    public struct DockControls: Sendable, Hashable, Codable {
        public var cleanScript: String
        public var dockStatusEntityId: String
        public var dryScript: String
        public var mopAttachmentEntityId: String
    }

    /// One consumable or dock-component sensor.
    public struct Consumable: Sendable, Hashable, Identifiable, Codable {
        /// Minutes remaining, or an `ok`-style status.
        public enum ValueKind: Sendable, Hashable, Codable { case duration, status }
        public var title: String
        public var entityId: String
        public var icon: String
        public var valueKind: ValueKind
        public var id: String { entityId }
    }

    /// One selectable room (an `input_boolean` the clean script reads).
    public struct Zone: Sendable, Hashable, Identifiable, Codable {
        public var title: String
        public var entityId: String
        public var icon: String
        /// The Valetudo segment name, when it differs from ``title``.
        public var mapName: String?
        /// Whether the room needs mopping when no live hint says otherwise.
        public var mopRequired: Bool?
        /// A coordinator sensor whose `mop_required` attribute overrides ``mopRequired``.
        public var mopRequiredEntityId: String?
        public var id: String { entityId }

        /// The segment name on the Valetudo map.
        public var segmentName: String { mapName ?? title }
    }

    /// A room the away-clean coordinator can be told to skip.
    public struct AutoCleanRoom: Sendable, Hashable, Identifiable, Codable {
        public var title: String
        public var entityId: String
        public var icon: String
        public var id: String { entityId }
    }

    /// Segments the map may crop to when nothing outside them matters (web `VacuumMapFocusConfig`).
    public struct MapFocus: Sendable, Hashable, Codable {
        public struct Segment: Sendable, Hashable, Codable {
            public var id: String
            public var name: String?
        }
        public var maximumViewAreaRatio: Double?
        public var minimumExcludedAreaM2: Double?
        public var minimumExcludedFraction: Double?
        public var paddingCm: Double?
        public var requiredSegments: [Segment]
        public var wallAssociationCm: Double?
    }

    public var title: String
    public var entityId: String
    public var batteryEntityId: String
    public var cleanScript: String
    public var consumables: [Consumable]
    public var coordinatorSessionEntityId: String?
    public var dockButtonEntityId: String?
    public var dockControls: DockControls?
    public var errorEntityId: String
    public var fanEntityId: String?
    public var areaCleaning: AreaCleaning?
    public var autoCleanDisabledRooms: [AutoCleanRoom]
    public var mapFocus: MapFocus?
    public var mapRoomSelection: Bool
    public var mapRotationDegrees: Double
    public var mapScale: Double
    public var modeEntityId: String?
    public var modeTextEntityId: String?
    public var outcomeRoomNames: [String: String]
    public var passesEntityId: String
    public var statusEntityId: String
    public var statusFlagEntityId: String
    /// The Valetudo id, e.g. `valetudo_exaltedsneakydeer`.
    public var vacuumMapId: String
    public var waterEntityId: String?
    public var zoneDescription: [String]
    public var zones: [Zone]

    public var id: String { entityId }

    /// The camera entity whose image carries the Valetudo map (`mapCameraEntityId`).
    public var mapCameraEntityId: String { "camera.\(vacuumMapId)_map_data" }
}

/// The house's robot vacuums and auto-clean switches, from the server's document.
public enum Vacuums {
    // MARK: - Page

    /// One Auto-Clean tile (`VACUUM_AUTO_CLEAN_CONTROLS`, `src/constants/vacuumAutoClean.ts`).
    public struct AutoCleanControl: Sendable, Hashable, Identifiable, Codable {
        /// A plain automation (on = enabled), or the Main Floor coordinator's pause switch (off = enabled).
        public enum Kind: Sendable, Hashable, Codable { case automation, pause }
        public var title: String
        public var entityId: String
        public var icon: String
        public var kind: Kind
        public var id: String { entityId }

        /// Whether auto-clean runs for this state.
        public func isEnabled(state: String) -> Bool {
            kind == .pause ? state == "off" : state == "on"
        }

        /// The service domain that flips it.
        public var domain: String { kind == .automation ? "automation" : "switch" }
    }

    /// Auto-Clean tiles in web order; it also orders the vacuum tiles (`ORDERED_VACUUMS`). The server's document.
    public static var autoCleanControls: [AutoCleanControl] { HouseConfigSource.active.read { $0.vacuums.autoCleanControls } ?? [] }

    /// Vacuums in page order: Auto-Clean order, then title (`DashboardViewPage.tsx:346`). The server's document.
    public static var all: [VacuumConfig] { HouseConfigSource.active.read { $0.vacuums.vacuums } ?? [] }

    /// Finds a vacuum by entity id.
    public static func config(entityId: String) -> VacuumConfig? { all.first { $0.entityId == entityId } }

    /// `input_text` markers that reconcile a failed outcome room as done (`VACUUM_OUTCOME_RECONCILIATIONS`, portedDashboard.ts:844).
    public static func outcomeReconciliations(_ vacuumMapId: String) -> [(roomId: String, entityId: String)] {
        (HouseConfigSource.active.read { $0.vacuums.outcomeReconciliations }?[vacuumMapId] ?? []).map { ($0.roomId, $0.entityId) }
    }
}
