import Foundation

// MARK: - Layout rules (L3)

/// What the layout capabilities evaluate: a badge's text, a tile's progress and faces, and the tab a container shows.
///
/// Every function is pure and total over ``ServerUIReading``. Loading and unavailable are different answers where the difference is
/// visible: a badge that is loading keeps what it showed (AGENTS.md, "No reload"), one that is unavailable draws nothing.
public enum ServerUILayoutRules {
    // MARK: Badges (`sh.badges@1`)

    /// What a badge shows now.
    public enum BadgeResult: Equatable, Sendable {
        /// The text to draw, or `nil` for no badge (none, empty, 0, unavailable, or a boolean).
        case text(String?)
        /// The value is not here yet: the badge keeps what it showed.
        case loading
    }

    /// A badge value as text. A value of 0 (a number, or text that reads as 0), an empty text and a `none` badge draw nothing.
    ///
    /// HIG, Badging: a badge is a short count or word; zero is the absence of the thing counted, so no badge is drawn for it.
    /// - Parameters:
    ///   - badge: The badge operand, or `nil` for a node with no badge.
    ///   - environment: What the operand reads.
    public static func badge(_ badge: ServerUIOperand?, in environment: some ServerUIReading) -> BadgeResult {
        guard let badge else { return .text(nil) }
        switch badge.evaluate(environment) {
        case .loading: return .loading
        case .unavailable: return .text(nil)
        case .value(let value):
            guard value.isStringOrNumber, let raw = ServerUIOperand.scalarText(value) else { return .text(nil) }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return .text(nil) }
            if JSONValue.string(text).finiteNumber == 0 { return .text(nil) }
            return .text(text)
        }
    }

    // MARK: Tile parts and look (`sh.tile-parts@1`, `sh.tile-look@1`)

    /// A state tile's progress: the operand's number clamped to 0 through 1. Anything that is not a number, a value that is loading and
    /// a value that is unavailable draw no progress (`nil`).
    public static func progress(_ operand: ServerUIOperand?, in environment: some ServerUIReading) -> Double? {
        guard let operand, case .value(let value) = operand.evaluate(environment), case .number(let number) = value, number.isFinite else { return nil }
        return min(1, max(0, number))
    }

    /// What a state tile's look conditions decide; `nil` leaves the face to the style's class.
    public struct Faces: Equatable, Sendable {
        public var active: Bool?
        public var filled: Bool?
        public var error: Bool?
        /// Creates faces.
        public init(active: Bool? = nil, filled: Bool? = nil, error: Bool? = nil) {
            self.active = active
            self.filled = filled
            self.error = error
        }
    }

    /// The faces `look` decides. A condition that holds sets its face on, one that does not sets it off, and one that cannot be
    /// answered, or is absent, leaves the face to the style.
    public static func faces(_ look: ServerUITileLook, in environment: some ServerUIReading) -> Faces {
        func face(_ rule: ServerUIPredicate?) -> Bool? {
            switch rule?.evaluate(environment) {
            case .yes?: true
            case .no?: false
            default: nil
            }
        }
        return Faces(active: face(look.activeWhen), filled: face(look.filledWhen), error: face(look.errorWhen))
    }

    // MARK: Tabs (`sh.tab-blocks@1`, `sh.tab-fallback@1`)

    /// The tab a container shows: the one asked for while its rule lets it show, else the fallback tab while that shows, else the first
    /// tab that shows. When no tab shows, the first tab: a container never draws nothing.
    /// - Parameters:
    ///   - container: The tab container.
    ///   - requested: The tab chosen by the person or a rule.
    ///   - environment: What the tabs' rules read.
    ///   - previous: Whether each tab was shown, by id, for `keep`.
    public static func tabOnShow(_ container: ServerUICompositionDocument.LocalTabs, requested: String?, in environment: some ServerUIReading,
                                 previous: [String: Bool] = [:]) -> String {
        func shows(_ id: String?) -> Bool {
            guard let tab = container.tabs.first(where: { $0.id == id }) else { return false }
            return tab.visibility?.isShown(environment, previous: previous[tab.id]) ?? true
        }
        if shows(requested), let requested { return requested }
        if shows(container.fallbackTabId), let fallback = container.fallbackTabId { return fallback }
        return container.tabs.first { shows($0.id) }?.id ?? container.tabs[0].id
    }

    /// The areas drawn while `tab` is on show, in document order, each with whether its own rule lets it show.
    public static func areas(_ container: ServerUICompositionDocument.LocalTabs, on tab: String, in environment: some ServerUIReading,
                             previous: [String: Bool] = [:]) -> [ServerUITabArea] {
        container.areas.filter { area in
            area.scope.shows(on: tab) && (area.visibility?.isShown(environment, previous: previous[area.id]) ?? true)
        }
    }
}

private extension JSONValue {
    var isStringOrNumber: Bool {
        switch self {
        case .string, .number: true
        default: false
        }
    }
}
