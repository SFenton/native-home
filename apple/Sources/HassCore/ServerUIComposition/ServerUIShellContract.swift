import Foundation

// MARK: - Shared shell values

extension ServerUICompositionDocument {
    /// Scene-local UI values, never Home Assistant state or a persisted credential.
    public enum LocalValue: Equatable, Sendable {
        case string(String), number(Double), boolean(Bool)
    }

    /// Closed validation, shared by local controls and native domain draft adapters.
    public struct LocalField: Equatable, Sendable {
        public let id: String
        public let initial: LocalValue
        public let rule: Rule

        /// The authored rule choices.
        public enum Rule: Equatable, Sendable {
            case string(maxLength: Int)
            case number(minimum: Double, maximum: Double, step: Double)
            case boolean
            case choice(options: [Option])
        }

        /// The authored option.
        public struct Option: Equatable, Sendable {
            public let id: String
            public let label: String
            /// The symbol a segmented choice draws for the option, and the words VoiceOver adds after the label (`sh.choice-icons@1`).
            public var symbol: ServerUICompositionDocument.Symbol?
            public var hint: String?
            /// Whether the option carries a symbol or a hint, which only a segmented choice draws.
            public var isDecorated: Bool { symbol != nil || hint != nil }
            /// Creates a option.
            public init(id: String, label: String) { self.id = id; self.label = label }
        }

        /// Creates a local field.
        public init(id: String, initial: LocalValue, rule: Rule) {
            self.id = id
            self.initial = initial
            self.rule = rule
        }

        var isValidDefinition: Bool {
            guard ServerUICompositionShape.validID(id), accepts(initial) else { return false }
            switch rule {
            case .boolean: return true
            case .string(let maximum): return (1...16_384).contains(maximum)
            case .number(let minimum, let maximum, let step):
                return minimum >= -1_000_000 && maximum <= 1_000_000 && step >= 0.000_001 && step <= 1_000_000
            case .choice(let options):
                return (2...12).contains(options.count) && Set(options.map(\.id)).count == options.count
                    && options.allSatisfy {
                        ServerUICompositionShape.validID($0.id) && $0.label.utf16.count <= 80
                            && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
            }
        }

        /// No coercion, clamping, or evaluation of downloaded expressions.
        public func accepts(_ value: LocalValue) -> Bool {
            switch (rule, value) {
            case (.string(let length), .string(let value)): return value.utf16.count <= length
            case (.boolean, .boolean): return true
            case (.choice(let options), .string(let value)): return options.contains { $0.id == value }
            case (.number(let minimum, let maximum, let step), .number(let value)):
                guard value.isFinite, minimum.isFinite, maximum.isFinite, step.isFinite,
                      minimum <= maximum, step > 0, value >= minimum, value <= maximum else { return false }
                let steps = (value - minimum) / step
                return steps.isFinite && abs(steps - steps.rounded()) <= 0.000_001
            default: return false
            }
        }
    }

    /// The authored section.
    public struct Section: Equatable, Sendable {
        public let node: Node
        public let header: String
        public let footer: String
        public let style: Style
        public let density: Density
        public let hasGlyphs: Bool
        public let spacing: Space
        public internal(set) var children: [Component]
        public var presentationProviderId: String? = nil
        /// The authored style choices.
        public enum Style: String, Sendable { case plain, moduleList = "module-list" }
        /// The authored density choices.
        public enum Density: String, Sendable { case thin, dense }
    }

    /// The authored info box.
    public struct InfoBox: Equatable, Sendable {
        public let node: Node
        public let message: StringValue
        public let tone: Tone
        public let unavailableText: String
        /// The authored tone choices.
        public enum Tone: String, Sendable { case neutral, success }
    }

    /// The authored status pill.
    public struct StatusPill: Equatable, Sendable {
        public let node: Node
        public let icon: Symbol
        public let value: StringValue
        public let detail: StringValue
        public let tone: Tone
        public let unavailableText: String
        /// The cases that choose the tone by rule (`sh.rules@1`); ``tone`` is then the `otherwise`.
        public var toneCases: [ServerUIConditional<Tone>.Case] = []
        /// The authored tone choices.
        public enum Tone: String, Sendable { case neutral, ok, active, warning, danger, unavailable }
    }

    /// The authored paged row.
    public struct PagedRow: Equatable, Sendable {
        public let node: Node
        public let perPage: Int
        public let pageLabel: String
        public let showsIndicator: Bool
        public internal(set) var children: [Component]

        /// Creates a paged row (a `repeat` draws its pages through the same row).
        public init(node: Node, perPage: Int, pageLabel: String, showsIndicator: Bool, children: [Component] = []) {
            self.node = node
            self.perPage = perPage
            self.pageLabel = pageLabel
            self.showsIndicator = showsIndicator
            self.children = children
        }
    }

    /// The canonical row's slots. There is deliberately no feature/page discriminator.
    public struct Row: Equatable, Sendable {
        public let node: Node
        public let primary: StringValue
        public let secondary: StringValue
        public let value: StringValue
        public let icon: Symbol?
        public let accessory: Accessory
        public let loadingText: String
        public let unavailableText: String
        public let action: Action?
        /// The authored accessory choices.
        public enum Accessory: String, Sendable { case none, disclosure }
    }

    /// The authored local tabs.
    public struct LocalTabs: Equatable, Sendable {
        public let node: Node
        public let stateId: String
        public var tabs: [TabContent]
        public var resetOnPresentation = false
        public var pinned = false
        public var scopeProviderId: String? = nil
        public var showsSelector = true
        public var retainsAutomaticSelection = false
        /// Rules that choose the panel from entity state, first match first (`sh.selected-when@1`).
        public var automatic: [AutomaticRule] = []
        /// The tab to open when the one the container would choose cannot show (`sh.tab-fallback@1`); `nil` means the first tab.
        public var fallbackTabId: String? = nil
        /// Where the bar sits and what it shows (`sh.tab-bar@1`); `nil` keeps the shipped forms.
        public var tabBar: ServerUITabBar? = nil
        /// The areas, in draw order (`sh.tab-blocks@1`); empty for the shipped shape, where each tab holds its own children.
        public var areas: [ServerUITabArea] = []
        /// A panel the document picks while its predicate holds.
        public struct AutomaticRule: Equatable, Sendable {
            public let tabId: String
            public let selectedWhen: ServerUIPredicate
        }
        /// The authored tab content.
        public struct TabContent: Equatable, Sendable {
            public let id: String
            public let label: String
            public internal(set) var children: [Component]
            public var icon: Symbol? = nil
            public var centerWhenFits = false
            /// Shows or hides the tab by a rule (`sh.tab-blocks@1`); `nil` for a tab that is always there.
            public var visibility: ServerUIVisibility? = nil
        }
    }

    /// The authored local control.
    public struct LocalControl: Equatable, Sendable {
        public let node: Node
        public let stateId: String
        public let kind: Kind
        public let placeholder: String
        /// The authored kind choices.
        public enum Kind: String, Sendable {
            case toggle, stepper, choice, textField = "text-field", segmentedChoice = "segmented-choice"
        }
    }

    /// The authored button.
    public struct Button: Equatable, Sendable {
        public let node: Node
        public let icon: Symbol?
        public let action: Action
    }

    /// An injected, bounded native row projection, not a sample endpoint or independent transport.
    public struct RowCollection: Equatable, Sendable {
        public let node: Node
        public let providerId: String
        public let loadingText: String
        public let emptyText: String
        public let unavailableText: String
        public let errorText: String
        public let staleText: String
        /// What a tap on a row does (`sh.list-parts@1`); never a domain action.
        public var rowAction: Action?
        /// Whether pulling the list runs its flow again (`sh.list-parts@1`).
        public var refreshable = false
        /// The line under the empty title (`sh.list-parts@1`).
        public var emptyMessage: StringValue?
    }
}

// MARK: - Uniform tree traversal

extension ServerUICompositionDocument.Component {
    /// All definitions, including hidden local tabs, participate in validation and publication guards.
    public var childComponents: [Self] {
        switch self {
        case .grid(let value): value.children
        case .section(let value): value.children
        case .pagedRow(let value): value.children
        case .pinnedActions(let value): value.children
        case .statusRail(let value): value.children
        case .roomSection(let value): value.children
        case .localTabs(let value): value.tabs.flatMap(\.children) + value.areas.flatMap(\.children)
        case .overlay(let value): value.children
        case .stack(let value): value.children
        case .repeatNode(let value): value.children
        default: []
        }
    }

    /// The plain actions the component can run: an action chosen by rule counts as each action it can pick.
    public var ownActions: [ServerUICompositionDocument.Action] { declaredActions.flatMap(\.plainActions) }

    /// The actions as authored, a rule counting as one.
    private var declaredActions: [ServerUICompositionDocument.Action] {
        switch self {
        case .navigationTile(let value): return [value.action]
        case .actionTile(let value): return [.domain(value.action)]
        case .row(let value): return value.action.map { [$0] } ?? []
        case .stack(let value): return value.action.map { [$0] } ?? []
        case .climate(let value): return value.action.map { [$0] } ?? []
        case .button(let value): return [value.action]
        case .boundControl(let value): return value.actions.map { .callService($0) }
        case .collection(let value): return value.selection.map { [$0] } ?? []
        case .rowCollection(let value): return value.rowAction.map { [$0] } ?? []
        case .form(let value): return value.success.map { [$0] } ?? []
        case .pinnedActions(let value): return value.items.map(\.action)
        case .statusChip(let value): return value.action.map { [$0] } ?? []
        case .roomOverviewTile(let value): return value.chip.action.map { [$0] } ?? []
        case .weatherPanel(let value): return value.action.map { [$0] } ?? []
        case .settingsLink(let value): return [value.action]
        case .settingsControl(let value): return value.destination.map { [$0] } ?? []
        case .roomCard(let value), .roomChip(let value):
            return (value.action.map { [$0] } ?? []) + (value.power.map { [.domain($0)] } ?? [])
        case .roomDeviceControl(let value): return value.navigationAction.map { [$0] } ?? []
        case .deviceControl(let value): return value.action.map { [$0] } ?? []
        case .bedroom(let value): return value.action.map { [$0] } ?? []
        case .remote(let value):
            if case .card(_, _, _, _, _, _, _, _, _, let action) = value.control { return [action] }
            return []
        case .vacuum(let value):
            switch value.primitive {
            case .target(_, _, let destination), .report(let destination), .card(_, _, let destination):
                return [destination]
            case .areaEditor(_, let use, _, let discard): return [use, discard]
            default: return []
            }
        case .cameraTile(let value): return [value.action]
        case .stateTile(let value): return value.parts.discs.map(\.action) + (value.action.map { [$0] } ?? [])
        default: return []
        }
    }
}
