import Foundation

// MARK: - Home domain contracts

public extension ServerUICompositionDocument {
    /// Explicit entity membership, never a lookup of the active house's rooms.
    struct HomeStatus: Equatable, Sendable {
        public let projection: Projection
        public let format: Format
        public let entityIds: [String]
        public let rangeEntityId: String?
        public let secondaryEntityId: String?
        public let alarmEntityId: String?
        public let awayEntityIds: [String]
        public let labels: Labels
        public var members: [Member] = []
        public var colorEntityId: String? = nil

        /// Explicit physical metadata for grouped contacts; omitted members retain legacy inference.
        public struct Member: Equatable, Sendable {
            public let entityId: String
            public let title: String
            public let contactCount: Int
            public let contactKind: ContactKind
            /// The contact kind type.
            public typealias ContactKind = RoomGroupItem.ContactKind
        }

        /// The authored projection choices.
        public enum Projection: String, Sendable { case lights, climate, occupancy, contacts, airQuality = "air-quality", entity }
        /// The authored format choices.
        public enum Format: String, Sendable { case summary, room, item, detail }
        /// The authored labels.
        public struct Labels: Equatable, Sendable {
            public let idle: String
            public let active: String
            public let countSuffix: String
            public let loading: String
            public let unavailable: String
            public let empty: String
            public let hidden: String
        }
    }

    /// Presentation states are authored independently of the projection's native formatting.
    struct StatusAppearance: Equatable, Sendable {
        public let icon: Symbol
        public let fill: TileFill
        public let glyph: TileFill?
    }
    struct StatusState: Equatable, Sendable {
        public let state: String
        public let appearance: StatusAppearance
        public let text: String?
    }
    struct StatusChip: Equatable, Sendable {
        public let node: Node
        public let sourceId: String
        public let states: [StatusState]
        public let fallback: StatusAppearance
        public let announcement: Announcement
        public let action: Action?
    }
    enum Announcement: String, Sendable { case none, valueChange = "value-change" }
    struct StatusRail: Equatable, Sendable {
        public let node: Node
        public let children: [Component]
    }
    struct RoomOverviewTile: Equatable, Sendable {
        public let chip: StatusChip
        public let hidesContactSubtitle: Bool
        public var powerSourceId: String? = nil
    }
    struct HomeLightTile: Equatable, Sendable {
        public let node: Node
        public let sourceId: String
    }
    /// One shared forecast model can feed any number of independently authored panels.
    struct HomeWeather: Equatable, Sendable {
        public let weatherEntityId: String
        public let sunEntityId: String?
        public let airQualityEntityId: String?
    }
    struct WeatherPanel: Equatable, Sendable {
        public let node: Node
        public let sourceId: String
        public let panel: Panel
        public let modes: [Mode]
        public let initialMode: Mode
        public let highlights: [Highlight]
        public let compactHours: Int
        public let regularHours: Int
        public let labels: Labels
        public let action: Action?

        /// The authored panel choices.
        public enum Panel: String, Sendable { case summary, hero, briefing, hourly, daily, highlights }
        /// The authored mode choices.
        public enum Mode: String, Sendable { case condition, precipitation, wind }
        /// The highlight type.
        public typealias Highlight = WeatherHighlights.PanelItem
        /// The authored labels.
        public struct Labels: Equatable, Sendable {
            public let loading: String
            public let empty: String
            public let stale: String
            public let error: String
            public let open: String
        }
    }
}
