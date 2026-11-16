import Foundation

// MARK: - Configured room primitives

extension ServerUICompositionDocument {
    /// An entity-state gate, not an expression language. Missing/unknown data never reveals a tile.
    public struct RoomVisibility: Equatable, Sendable {
        public let sourceId: String
        public let states: [String]
    }

    /// A configured room grid. Order is sampled once per presentation; visibility remains live.
    public struct RoomNavigation: Equatable, Sendable {
        public let items: [RoomDestination]
        public let ranking: RoomRanking
        public let visitScriptEntityId: String?
    }

    /// The authored room ranking choices.
    public enum RoomRanking: String, Sendable {
        case configured
        case visits = "visits-descending-configured-ties@1"
    }

    /// The authored room destination.
    public struct RoomDestination: Equatable, Sendable {
        public let id: String
        public let title: String
        public let icon: Symbol
        public let fill: TileFill
        public let counterEntityId: String?
        public let visibility: RoomVisibility?
        public let visitKey: String?
        public let action: Action
        public let bodyHint: String
    }

    /// The authored room navigation grid.
    public struct RoomNavigationGrid: Equatable, Sendable {
        public let node: Node
        public let sourceId: String
    }

    /// Canonical room state formatting over explicit source IDs. Device controls are attachments.
    public struct RoomCard: Equatable, Sendable {
        public let node: Node
        public let icon: Symbol
        public let sourceId: String
        public let kind: RoomCardKind
        public let showState: Bool
        public let subtitleSourceIds: [String]
        public let activeStates: [String]
        public let disabledStates: [String]
        public let stateLabels: [RoomStateLabel]
        public let visibility: RoomVisibility?
        public let action: Action?
        public let power: PowerAction?
        public var alternate: RoomAlternate? = nil
        public var chipSources: RoomChipSources? = nil
        public var personalization: RoomPersonalization? = nil
        public var stateColors: [RoomStateColor] = []
        public var climateActionTone: Bool = false
    }

    /// The authored room alternate.
    public struct RoomAlternate: Equatable, Sendable {
        public let when: RoomVisibility
        public let sourceId: String
        public let showState: Bool
        public let subtitleSourceIds: [String]
    }
    /// The authored room chip sources.
    public struct RoomChipSources: Equatable, Sendable {
        public let aqiSourceId: String?
        public let colorSourceId: String?
        public let alarmSourceId: String?
        public let homeAwaySourceId: String?
        public let awaySourceIds: [String]
        public let pluralContacts: Bool
    }
    /// The authored room personalization.
    public struct RoomPersonalization: Equatable, Sendable {
        public let residentId: String
        public let ownTitle: String
        public let otherTitle: String
    }
    /// The authored room state color.
    public struct RoomStateColor: Equatable, Sendable {
        public let state: String
        public let fill: TileFill
        /// How the fill follows a rule or an entity's color (`sh.rules@1`); ``fill`` is then its `otherwise` or fallback.
        public var fillRule: ServerUIDynamicLook<TileFill>? = nil
    }
    /// The authored room state label.
    public struct RoomStateLabel: Equatable, Sendable {
        public let state: String
        public let label: String
    }

    /// The authored room section.
    public struct RoomSection: Equatable, Sendable {
        public let node: Node
        public let layout: RoomSectionArrangement
        public let leadJoinsAtRegularWidth: Bool
        public let visibility: RoomVisibility?
        public let children: [Component]
    }

    /// The authored room section arrangement choices.
    public enum RoomSectionArrangement: String, Sendable {
        case grid, leadRow = "lead-row", twoColumnFill = "two-column-fill"
    }
}

// MARK: - Pure room intent and ranking adapters

/// Reuses the production counter parser and explicit script command without consulting house config.
public enum ServerUIRooms {
    /// The d type.
    public typealias D = ServerUICompositionDocument

    /// Stable configured ties, including absent, fractional, negative and unavailable counters.
    public static func ranked(_ configuration: D.RoomNavigation, state: (String) -> String?) -> [D.RoomDestination] {
        guard configuration.ranking == .visits else { return configuration.items }
        let ranked = configuration.items.enumerated().map { index, item in
            let count = item.counterEntityId.map { RoomNavigation.accessCount(state($0)) } ?? 0
            return (index: index, count: count, item: item)
        }
        return ranked.sorted { lhs, rhs in
            lhs.count != rhs.count ? lhs.count > rhs.count : lhs.index < rhs.index
        }.map(\.item)
    }

    /// The caller owns lifetime and reporting. Compilation guarantees script/key pairing.
    public static func visitCall(_ item: D.RoomDestination, configuration: D.RoomNavigation) -> ServiceCall? {
        guard let target = configuration.visitScriptEntityId, let key = item.visitKey else { return nil }
        return RoomNavigation.accessIncrementCall(accessKey: key, scriptEntityId: target)
    }

    /// One room-grid presentation's order. New definitions append; counter updates never move retained rooms.
    public struct ServerUIRoomOrder: Sendable {
        private var ids: [String]?
        /// Creates a server uiroom order.
        public init() {}

        /// The room items to show, ranked per the configuration.
        public mutating func items(_ configuration: ServerUICompositionDocument.RoomNavigation,
                                   state: (String) -> String?) -> [ServerUICompositionDocument.RoomDestination] {
            if ids == nil { ids = ServerUIRooms.ranked(configuration, state: state).map(\.id) }
            let configured = configuration.items.map(\.id)
            var retained = (ids ?? []).filter { configured.contains($0) }
            retained += configured.filter { !retained.contains($0) }
            ids = retained
            let items = Dictionary(uniqueKeysWithValues: configuration.items.map { ($0.id, $0) })
            return retained.compactMap { items[$0] }
        }
    }

    /// Converts the closed authored state fields to the existing room formatter's value model. With an `environment`, a state color that
    /// follows a rule or an entity (`sh.rules@1`) is resolved against it; without one it draws its fallback.
    public static func card(_ definition: D.RoomCard, entityId: String, in environment: (any ServerUIReading)? = nil) -> RoomCard {
        var card = RoomCard(definition.node.title, entityId, icon: definition.icon.name, kind: definition.kind,
                            sheet: definition.action == nil ? nil : definition.node.id)
        card.showState = definition.showState
        card.activeStates = definition.activeStates
        card.disabledStates = definition.disabledStates
        card.stateLabels = Dictionary(uniqueKeysWithValues: definition.stateLabels.map { ($0.state, $0.label) })
        card.climateActionTone = definition.climateActionTone
        card.stateColors = Dictionary(uniqueKeysWithValues: definition.stateColors.compactMap { item -> (String, RoomColor)? in
            let fill = environment.map { item.resolvedFill(in: $0) } ?? item.fill
            guard let (light, dark) = fill.appearances else { return nil }
            var color = RoomColor(Double(light.red), Double(light.green), Double(light.blue))
            if dark != light { color.dark = .init(Double(dark.red), Double(dark.green), Double(dark.blue)) }
            return (item.state, color)
        })
        return card
    }

    /// Alternate display targets do not retarget a command or change the keyed card's identity.
    public static func display(_ definition: D.RoomCard, read: (String) -> EntityState?) -> (sourceId: String, showState: Bool, subtitles: [String]) {
        if let alternate = definition.alternate, let gate = read(alternate.when.sourceId),
           !gate.isUnavailable, alternate.when.states.contains(gate.state) {
            return (alternate.sourceId, alternate.showState, alternate.subtitleSourceIds)
        }
        return (definition.sourceId, definition.showState, definition.subtitleSourceIds)
    }

    /// Contact tone uses the same effective-away precedence as the canonical climate projection.
    public static func isAway(_ sources: D.RoomChipSources, read: (String) -> EntityState?) -> Bool {
        let entity = sources.homeAwaySourceId.flatMap(read)
        let state = entity?.state == "unknown" ? "Unknown" : ClimateLogic.compactState(entity)
        return ClimateLogic.isEffectivelyAway(state: state, fallbackAway: sources.awaySourceIds.contains { read($0)?.state == "on" })
    }
}
