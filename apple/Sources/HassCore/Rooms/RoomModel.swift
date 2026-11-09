import Foundation

// MARK: - Cards

/// What a room card represents (web `RoomSourceKind`, `ha-sfenton-react-dash@9ac2a46:src/constants/roomPages.ts:22`).
public enum RoomCardKind: String, Hashable, Sendable, CaseIterable, Codable {
    case air, appliance, climate, contact, fan, grill, humidifier, laundry, light, media, occupancy, power, vacuum, vent
    case wakeLight = "wake-light"

    /// The tile tone (web `toneForSourceKind`, `DashboardViewPage.tsx:500`).
    public var tone: RoomTone {
        switch self {
        case .light, .wakeLight: .light
        case .air: .air
        case .climate, .vent, .fan, .humidifier: .climate
        case .occupancy: .presence
        case .contact: .contact
        case .vacuum: .vacuum
        case .media: .media
        case .power: .power
        case .grill: .warning
        case .appliance, .laundry: .neutral
        }
    }
}

/// A tile's color family (web `GlassTile` tones).
public enum RoomTone: String, Hashable, Sendable, Codable {
    case light, air, climate, presence, contact, vacuum, media, power, warning, neutral
}

/// A plain RGBA color so configs stay free of UI frameworks.
public struct RoomColor: Hashable, Sendable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    /// Creates a color from 0–255 channels, like the web's `rgba()`.
    public init(_ red: Double, _ green: Double, _ blue: Double, opacity: Double = 1) {
        self.red = red / 255
        self.green = green / 255
        self.blue = blue / 255
        self.opacity = opacity
    }
}

/// What tapping a card does when it has no sheet (web `RoomSourceCardAction`).
public enum RoomCardAction: Hashable, Sendable, Codable {
    /// Flips the entity from its shown state with an explicit `turn_on` / `turn_off` (web `{ type: 'toggle' }`,
    /// which sent `homeassistant.toggle`; explicit services keep Presence Based Lighting from reverting it).
    case flip
    /// A service call, possibly chosen by state, shared with the media remote's action model.
    case remote(MediaRemoteAction)
}

/// What assistive technologies should be told a card is (web `ControlSemanticsResolver` on room cards).
public enum RoomCardSemantics: Hashable, Sendable, Codable {
    /// Opens a sheet.
    case modal
    /// Fires a command.
    case command
    /// A state-dependent toggle or choice.
    case rule(SemanticsRule)
}

/// A bespoke tile and sheet the web draws instead of the generic card (web `card.control`).
public enum RoomCardControl: String, Hashable, Sendable, Codable {
    case bathroomFan = "bathroom-fan"
    case garageDoor = "garage-door"
}

/// How a personalized card names its owner (web `residentLabel`).
public enum ResidentLabel: Hashable, Sendable, Codable {
    case bedSide, pc
}

/// One entry in a card's item sheet (web `RoomSourceModalItem`).
public struct RoomModalItem: Hashable, Sendable, Identifiable, Codable {
    public var title: String
    public var entityId: String
    public var icon: String
    public var id: String { entityId + title }

    public init(_ title: String, _ entityId: String, icon: String) {
        self.title = title
        self.entityId = entityId
        self.icon = icon
    }
}

/// A card that shows a different entity while another entity is in some states (web `alternate`, the
/// dishwasher's progress while it runs).
public struct RoomCardAlternate: Hashable, Sendable, Codable {
    public var whenEntityId: String
    public var whenStates: [String]
    public var entityId: String
    public var showState: Bool
    public var subtitleEntityIds: [String]
}

/// One card on a room page or in its status rail (web `RoomSourceCardConfig`).
public struct RoomCard: Hashable, Sendable, Identifiable, Codable {
    public var title: String
    public var entityId: String
    /// Web MDI icon name.
    public var icon: String
    public var kind: RoomCardKind
    /// The sheet the card opens: the web hash without `#` (e.g. `lights-kitchen`), or `nil` for none.
    public var sheet: String?
    public var showState = false
    /// Entities whose formatted states make the subtitle, joined with " • ".
    public var subtitleEntityIds: [String] = []
    /// States that mark the card active (else the web `isActiveState`).
    public var activeStates: [String] = []
    /// States that disable the card.
    public var disabledStates: [String] = []
    /// Labels that replace a raw state.
    public var stateLabels: [String: String] = [:]
    /// Background washes by state (towel racks).
    public var stateColors: [String: RoomColor] = [:]
    /// Tint the card by the climate entity's `hvac_action` (Eight Sleep beds).
    public var climateActionTone = false
    public var alternate: RoomCardAlternate?
    public var control: RoomCardControl?
    /// The entity the sheet is about when it differs from ``entityId`` (air purifier PM2.5).
    public var modalEntityId: String?
    public var modalItems: [RoomModalItem] = []
    public var modalTitle: String?
    public var action: RoomCardAction?
    public var semantics: RoomCardSemantics?
    /// Spans the whole section row.
    public var isFullWidth = false
    public var resident: HouseholdResident?
    public var residentLabel: ResidentLabel?

    public var id: String { "\(title)|\(entityId)" }

    public init(_ title: String, _ entityId: String, icon: String, kind: RoomCardKind, sheet: String? = nil) {
        self.title = title
        self.entityId = entityId
        self.icon = icon
        self.kind = kind
        self.sheet = sheet
    }

    /// The card's title for the signed-in resident: "Your Side" / "Sam's PC" (web `personalizedRoomCardTitle`).
    public func title(for viewer: HouseholdResident?) -> String {
        guard let viewer, let resident, let residentLabel else { return title }
        if resident == viewer { return residentLabel == .bedSide ? "Your Side" : "Your PC" }
        return residentLabel == .bedSide ? "\(resident.name)'s Side" : "\(resident.name)'s PC"
    }

    /// Whether tapping does anything at all.
    public var hasInteraction: Bool { sheet != nil || action != nil }
}

// MARK: - Sections and pages

/// How a section lays out its cards (web `RoomSourceSectionLayout`).
public enum RoomSectionLayout: Hashable, Sendable, Codable {
    /// The default responsive grid.
    case grid
    /// The first card on its own row above the rest.
    case leadRow
    /// Two columns filling the section width.
    case twoColumnFill
    /// Square app tiles from a media remote's apps.
    case appLaunch(remoteId: String)
}

/// The side of the hinge a section takes while the iPhone Duo is partly folded (`.agents/design/section-sides.md`).
public enum RoomSectionSide: String, Hashable, Sendable, Codable {
    /// Before the hinge band.
    case leading
    /// After the hinge band.
    case trailing
}

/// One titled group of cards on a room page (web `RoomSourceSectionConfig`).
public struct RoomSection: Hashable, Sendable, Identifiable, Codable {
    public var title: String
    public var layout: RoomSectionLayout
    public var cards: [RoomCard]
    /// `false` keeps the section in config but off the page (Music Room's Fortnite launcher).
    public var showOnRoomPage: Bool
    /// An explicit side while partly folded; nil takes the parity of the section's index in the visible list (even leads).
    public var foldSide: RoomSectionSide?

    public var id: String { title }

    public init(_ title: String, layout: RoomSectionLayout = .grid, showOnRoomPage: Bool = true, foldSide: RoomSectionSide? = nil,
                cards: [RoomCard] = []) {
        self.foldSide = foldSide
        self.title = title
        self.layout = layout
        self.cards = cards
        self.showOnRoomPage = showOnRoomPage
    }
}

/// One config-driven room page (web `RoomPageSourceConfig`).
public struct RoomPage: Hashable, Sendable, Identifiable, Codable {
    /// The web route path, e.g. `living-room`.
    public var id: String
    public var title: String
    /// Status rail chips under the title.
    public var overviewCards: [RoomCard]
    public var sections: [RoomSection]
    /// A remote whose optimistic overlay the page's tiles share (Music Room), so a tapped source shows at once.
    public var optimisticRemoteId: String?

    public init(id: String, title: String, overviewCards: [RoomCard], sections: [RoomSection], optimisticRemoteId: String? = nil) {
        self.id = id
        self.title = title
        self.overviewCards = overviewCards
        self.sections = sections
        self.optimisticRemoteId = optimisticRemoteId
    }

    /// Sections drawn on the page.
    public var visibleSections: [RoomSection] { sections.filter(\.showOnRoomPage) }

    /// Every card in the rail and the sections.
    public var allCards: [RoomCard] { overviewCards + sections.flatMap(\.cards) }

    /// Remotes the page talks to: media cards' sheets, app launchers and the optimistic remote.
    public var remoteIds: [String] {
        var ids: [String] = []
        func add(_ id: String?) { if let id, !ids.contains(id) { ids.append(id) } }
        add(optimisticRemoteId)
        for section in sections {
            if case let .appLaunch(remoteId) = section.layout { add(remoteId) }
        }
        for card in allCards where card.kind == .media {
            if let sheet = card.sheet, MediaRemotes.config(id: sheet) != nil { add(sheet) }
        }
        return ids
    }
}
