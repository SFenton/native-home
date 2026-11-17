import Foundation

// MARK: - Conditions on controls, tiles, actions and tabs

/// What an `enabledWhen` does while its condition cannot be answered (`sh.enabled-when@1`).
public enum ServerUIEnabledUnknown: String, Sendable, CaseIterable {
    case enabled, disabled
    /// Repeat the last answer, so a reconnect never flips a control; enabled when it was never answered.
    case keep
}

/// The three faces a state tile's conditions decide; `nil` is "from the style".
public struct ServerUITileFaces: Equatable, Sendable {
    public var active: Bool?
    public var filled: Bool?
    public var error: Bool?

    /// Creates the faces.
    public init(active: Bool? = nil, filled: Bool? = nil, error: Bool? = nil) {
        self.active = active
        self.filled = filled
        self.error = error
    }
}

/// Evaluators for the conditions authored on controls, tiles, actions and tabs.
public enum ServerUIControlRules {
    /// Whether a control is enabled (`sh.enabled-when@1`). No rule means enabled. While the condition cannot be answered, `enabled` and
    /// `disabled` say so and `keep` repeats `previous` (enabled when it was never answered).
    public static func isEnabled(_ condition: ServerUIPredicate?, whenUnknown: ServerUIEnabledUnknown, previous: Bool? = nil,
                                 in environment: some ServerUIReading) -> Bool {
        guard let condition else { return true }
        switch condition.evaluate(environment) {
        case .yes: return true
        case .no: return false
        case .unknown:
            switch whenUnknown {
            case .enabled: return true
            case .disabled: return false
            case .keep: return previous ?? true
            }
        }
    }

    /// What a state tile's look conditions decide (`sh.tile-look@1`). A condition that holds sets its face on; one that does not hold sets
    /// it off. A condition that cannot be answered, or is absent, leaves the face to the style's class.
    public static func tileFaces(active: ServerUIPredicate?, filled: ServerUIPredicate?, error: ServerUIPredicate?,
                                 in environment: some ServerUIReading) -> ServerUITileFaces {
        func face(_ rule: ServerUIPredicate?) -> Bool? {
            guard let rule else { return nil }
            switch rule.evaluate(environment) {
            case .unknown: return nil
            case .yes: return true
            case .no: return false
            }
        }
        return ServerUITileFaces(active: face(active), filled: face(filled), error: face(error))
    }

    /// Whether an action asks first (`sh.confirm-when@1`). With no `when` it always asks; a `when` that holds asks, one that does not
    /// holds back the question, and one that cannot be answered asks, so a gap never skips a question the author wanted.
    public static func asksFirst(_ when: ServerUIPredicate?, in environment: some ServerUIReading) -> Bool {
        guard let when else { return true }
        return when.evaluate(environment) != .no
    }

    /// The tab a container shows: the one asked for while its rule lets it show, else the fallback tab while that shows, else the first
    /// tab that shows. When no tab shows, the first tab (a container never draws nothing).
    public static func tabOnShow(_ tabs: [Tab], requested: String?, fallback: String?, in environment: some ServerUIReading) -> String? {
        func shows(_ id: String?) -> Bool {
            guard let tab = tabs.first(where: { $0.id == id }) else { return false }
            return tab.visibility?.isShown(environment, previous: nil) ?? true
        }
        if let requested, shows(requested) { return requested }
        if let fallback, shows(fallback) { return fallback }
        return tabs.first(where: { $0.visibility?.isShown(environment, previous: nil) ?? true })?.id ?? tabs.first?.id
    }

    /// A tab for ``tabOnShow(_:requested:fallback:in:)``: its id and its `visibleWhen`.
    public struct Tab: Equatable, Sendable {
        public let id: String
        public let visibility: ServerUIVisibility?

        /// Creates a tab.
        public init(id: String, visibility: ServerUIVisibility? = nil) {
            self.id = id
            self.visibility = visibility
        }
    }
}
