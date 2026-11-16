import Foundation

// MARK: - Layout contract (L3)

/// Where a tab container's bar sits and how it labels its tabs (`sh.tab-bar@1`).
///
/// HIG, Tab bars: a tab bar at the bottom of the screen switches between top-level sections, and a segmented control at the head of
/// the content switches between closely related views. `pinned: true` alone keeps meaning a bottom bar with automatic labels.
public struct ServerUITabBar: Equatable, Sendable {
    /// Which edge the bar sits on.
    public enum Placement: String, Sendable { case bottom, top }
    /// What each segment shows.
    public enum Labels: String, Sendable {
        /// Icons while every tab has one and the window is narrow, titles when it is wide.
        case bySize = "by-size"
        case icons, titles
        case iconsAndTitles = "icons-and-titles"
    }

    public let placement: Placement
    public let labels: Labels

    /// Creates the bar settings.
    public init(placement: Placement, labels: Labels) {
        self.placement = placement
        self.labels = labels
    }

    /// Whether this label mode draws an icon on every segment, so every tab must have one.
    public var needsIcons: Bool { placement == .bottom || labels == .icons || labels == .iconsAndTitles }
}

/// One area of a tab container (`sh.tab-blocks@1`): children drawn once for the tabs it names, in order with the other areas.
///
/// An area is one view for as long as the tab on show is one of its tabs. A tab change adds and removes only the areas whose tabs
/// change (AGENTS.md, "No reload").
public struct ServerUITabArea: Equatable, Sendable {
    /// The tabs an area shows on.
    public enum Scope: Equatable, Sendable {
        /// Every tab: a shared area.
        case all
        /// The listed tabs, in the order written.
        case tabs([String])

        /// Whether the area shows while `tabId` is on show.
        public func shows(on tabId: String) -> Bool {
            switch self {
            case .all: true
            case .tabs(let ids): ids.contains(tabId)
            }
        }
    }

    public let id: String
    public let scope: Scope
    /// Shows or hides the area by a rule; `nil` for an area that is always there.
    public let visibility: ServerUIVisibility?
    public let children: [ServerUICompositionDocument.Component]
}

/// A node that draws small controls over a base (`sh.overlay@1`): the first child is the base, the rest sit at five anchors.
///
/// Every control on top is at least 44 pt (HIG, Buttons: "the hit region is at least 44x44 pt"). `leading` and `trailing` are the
/// logical edges, so they mirror in a right-to-left language (HIG, Right to left).
public struct ServerUIOverlay: Equatable, Sendable {
    /// The five places a control on top can sit.
    public enum Anchor: String, CaseIterable, Sendable {
        case topLeading = "top-leading", topTrailing = "top-trailing"
        case bottomLeading = "bottom-leading", bottomTrailing = "bottom-trailing"
        case center
    }
    /// Where one child sits and how far from the edge.
    public struct Placement: Equatable, Sendable {
        public let childId: String
        public let anchor: Anchor
        public let inset: ServerUICompositionDocument.Space
    }

    public let node: ServerUICompositionDocument.Node
    public let anchors: [Placement]
    /// The base first, then up to four controls on top.
    public let children: [ServerUICompositionDocument.Component]

    /// The most controls that sit on top of the base.
    public static let maximumOnTop = 4

    /// The smallest side of a control on top, in points.
    public static let minimumTarget = 44.0

    /// The place of the child with `id`, or `nil` for the base.
    public func placement(of id: String) -> Placement? { anchors.first { $0.childId == id } }
}

/// A state tile's own parts (`sh.tile-parts@1`), each optional: a line under the title, a progress fill and up to two buttons.
public struct ServerUITileParts: Equatable, Sendable {
    /// One round button on the tile. Its label is what VoiceOver reads and is never drawn.
    public struct Disc: Equatable, Sendable {
        public let id: String
        public let icon: ServerUICompositionDocument.Symbol
        public let label: String
        public let action: ServerUICompositionDocument.Action
        public let visibility: ServerUIVisibility?
        /// Dims the button and stops its tap while a rule says no (`sh.enabled-when@1`); `nil` for a button that is always enabled.
        public let enabledWhen: ServerUIEnabledRule?
    }

    /// The text under the title, drawn instead of the style's state words.
    public var subtitle: ServerUICompositionDocument.StringValue?
    /// A number from 0 to 1 (clamped); the fill from the leading edge.
    public var progress: ServerUIOperand?
    /// Up to two buttons, in order.
    public var discs: [Disc] = []

    /// The most buttons a tile has.
    public static let maximumDiscs = 2

    /// Whether the tile has any part, so the capability is required.
    public var isEmpty: Bool { subtitle == nil && progress == nil && discs.isEmpty }
}

/// The conditions that decide a state tile's faces (`sh.tile-look@1`). Each, when it holds, overrides the style's class for its face.
public struct ServerUITileLook: Equatable, Sendable {
    public var activeWhen: ServerUIPredicate?
    public var filledWhen: ServerUIPredicate?
    public var errorWhen: ServerUIPredicate?

    /// Whether the tile has no condition.
    public var isEmpty: Bool { activeWhen == nil && filledWhen == nil && errorWhen == nil }
}
