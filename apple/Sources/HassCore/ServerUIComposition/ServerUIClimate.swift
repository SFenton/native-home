import Foundation

// MARK: - Climate composition

/// Explicit targets for the canonical Climate controller. No house configuration is consulted.
public struct ServerUIClimateSource: Equatable, Sendable, Decodable {
    public let entityId: String
    public let rangeCommitEntityIds: [String]
    public let actionEntityId: String?
    public let sensorEntityId: String?
    public let occupancyEntityId: String?
    public let effectiveAway: EffectiveAway?
    public let trackingGate: TrackingGate?
    public let homeAway: HomeAway?
    public let tracking: Tracking?

    /// The authored tracking.
    public struct Tracking: Equatable, Sendable, Decodable {
        public let policyEntityId: String
        public let criticalOption: String
        public let rooms: [Room]
        /// The authored room.
        public struct Room: Equatable, Sendable, Decodable {
            public let selectedEntityId: String
            public let criticalEntityId: String
            public let occupiedOnlyEntityId: String
        }
    }

    /// The authored home away.
    public struct HomeAway: Equatable, Sendable, Decodable {
        public let modeEntityId: String
        public let reasonEntityId: String
        public let fallbackEntityId: String
        public let vacationEntityId: String
    }

    /// Whole-home target selection uses the same effective-away rule as the legacy feature.
    public struct EffectiveAway: Equatable, Sendable, Decodable {
        public let ecoEntityId: String
        public let modeEntityId: String
        public let fallbackEntityId: String
    }

    /// Server-owned tracking policy gates a room command; critical protection excludes tracked rooms.
    public struct TrackingGate: Equatable, Sendable, Decodable {
        public let selectedEntityId: String
        public let criticalEntityId: String?
        public let criticalOption: String?
        public let trackedEntityId: String?
    }

    public var commandEntityIds: [String] {
        [entityId] + rangeCommitEntityIds + (effectiveAway.map { [$0.ecoEntityId] } ?? [])
    }

    /// Resolves the target afresh for display and again at gesture commit.
    public func target(_ lookup: EntityLookup) -> String {
        guard let effectiveAway else { return entityId }
        let entity = lookup(effectiveAway.modeEntityId)
        let state = entity?.isUnavailable == false ? entity?.state ?? "Unavailable" : "Unavailable"
        let away = ClimateLogic.isEffectivelyAway(
            state: state == "unknown" ? "Unknown" : state,
            fallbackAway: lookup(effectiveAway.fallbackEntityId)?.state == "on"
        )
        return away ? effectiveAway.ecoEntityId : entityId
    }

    /// No local automation: this only disables the same controls the canonical tracking page disables.
    public func isEnabled(state: (String) -> String?) -> Bool {
        guard let gate = trackingGate else { return true }
        guard state(gate.selectedEntityId) == "on" else { return false }
        if let entity = gate.criticalEntityId, state(entity) != gate.criticalOption { return false }
        if let entity = gate.trackedEntityId, state(entity) == "on" { return false }
        return true
    }
}

/// One atomic native control, freely ordered in pages, grids and modal bodies.
public struct ServerUIClimateControl: Equatable, Sendable {
    public let node: ServerUICompositionDocument.Node
    public let props: Properties
    public var action: ServerUICompositionDocument.Action? = nil

    /// The authored kind choices.
    public enum Kind: String, Sendable, Decodable, CaseIterable {
        case dial, toggle, check, explicitSwitch = "explicit-switch", mode, fan, preset, options, status, hub, notice, link
        case roomTile = "room-tile"
        public var capability: String {
            switch self {
            case .toggle, .explicitSwitch: "sh.climate-toggle@1"
            default: "sh.climate-\(rawValue)@1"
            }
        }
    }

    /// Shape validation requires exactly the fields of the selected variant before decoding.
    public struct Properties: Equatable, Sendable, Decodable {
        public let kind: Kind
        public let sourceId: String
        public let icon: String
        public let hint: String
        public let loadingText: String
        public let unavailableText: String
        public let errorText: String
        public let dial: Dial?
        public let choices: [Choice]?
        public let status: Status?
        public let hub: Hub?
        public let notice: Notice?
        public let paletteIndex: Int?
        public let presentation: StatusPresentation?
    }

    /// The authored status presentation choices.
    public enum StatusPresentation: String, Sendable, Decodable { case row, metric, headline, paragraphs }

    /// The authored dial.
    public struct Dial: Equatable, Sendable, Decodable {
        public let minimum: Double
        public let maximum: Double
        public let step: Double
        public let unit: String
        public let size: Size
        /// The authored size choices.
        public enum Size: String, Sendable, Decodable { case page, modal, compact }
    }

    /// Authored order/copy is intersected with HA's current supported options, never invented.
    public struct Choice: Equatable, Sendable, Decodable {
        public let value: String
        public let label: String
        public let icon: String
        public let detail: String
    }

    /// The authored hub.
    public struct Hub: Equatable, Sendable, Decodable {
        public let modeLabel: String
        public let fanLabel: String
        public let modes: [Choice]
        public let fans: [Choice]
    }

    /// The authored notice.
    public struct Notice: Equatable, Sendable, Decodable {
        public let useEffectiveMode: Bool
        public let isWarning: Bool
        public let awayText: String
        public let vacationText: String
        public let unknownText: String
        public let unavailableModeText: String
        public let reasonFallback: String
        public let separator: String
    }

    /// The authored status.
    public struct Status: Equatable, Sendable, Decodable {
        public let projection: Projection
        public let unit: String
        public let states: [StateLabel]
        public let fallbackText: String
        /// The authored projection choices.
        public enum Projection: String, Sendable, Decodable {
            case state, action, temperature, occupancy, vent, recommendation, reason
            case indoor, predicted, comfortLow, comfortHigh, forecastLow, forecastHigh, weather, adjustment
            case comfortBand, forecastRange, explanation, predictive
            case trackingSelected, trackingCritical, trackingOccupiedOnly
        }
        /// The authored state label.
        public struct StateLabel: Equatable, Sendable, Decodable {
            public let state: String
            public let text: String
        }
    }
}
