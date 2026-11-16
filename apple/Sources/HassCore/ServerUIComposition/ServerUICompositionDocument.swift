import Foundation
import FentonActivityModel

// MARK: - Immutable first-slice plan

/// Studio's schema-2 first-slice composition. Containers own nodes; actions reference surfaces.
///
/// Exact policy selections are retained; no renderer defaults, page dispatch, HA state, or
/// executable expressions are embedded. Empty dictionaries are explicit first-slice constraints.
public struct ServerUICompositionDocument: Equatable, Sendable {
    public let schemaVersion: String
    public let id: String
    public let name: String
    public let theme: Theme
    public let navigation: Navigation
    public let pages: [Page]
    public let modals: [Modal]
    public internal(set) var dataSources: [Source]
    public let variables: EmptyObject
    public let assets: [Asset]
    public let liveActivities: [ActivityPresentation]
    public var localState: [LocalField] = []
    public let bootstrap: ServerUIBootstrapPolicy?
    public var extensions: NativeExtensionPresentation? = nil
    /// The saved state styles `state-tile` nodes apply by id (`sh.state-style@1`); nil when the document carries none.
    public var stateStyles: ServerUIStateStyleLibrary? = nil

    /// An explicitly authored empty object; parameterized routes and legacy `variables` remain unsupported.
    public struct EmptyObject: Equatable, Sendable {}

    /// Closed named policies. Each receiving slot is independently checked by the compiler.
    public enum Policy: String, Sendable {
        case canonical = "canonical"
        case canonicalV1 = "canonical@1"
        case dynamicType = "dynamic-type@1"
        case shellBase = "shell-base@1"
        case houseR3 = "house-r3@1"
        case stationary = "stationary@1"
        case canonicalBase = "canonical-base@1"
        case canonicalShell = "canonical-shell@1"
        case preserveCut = "preserve-cut@1"
        case popRootThenScroll = "pop-root-then-scroll@1"
        case canonicalStack = "canonical-stack@1"
        case scene = "scene@1"
        case reject
        case fallback
        case replace
        case separateCircles = "separate-circles@1"
        case shared = "shared@1"
        case separate = "separate@1"
        case contentFit = "content-fit@1"
        case canonicalPage = "canonical-page@1"
        case host
        case tile = "tile@1"
        case tileDynamicType = "tile-dynamic-type@1"
        case sectionWide = "section-wide@1"
        case navigationPath = "navigation-path"
        case none
        case provider, policy, power
        case powerTile = "power-tile@1"
        case sender
        case reuseNearest = "reuse-nearest"
        case currentModal = "current-modal"
        case canonicalSheet = "canonical-sheet@1"
        case localStack = "local-stack@1"
        case backdropBlur = "backdrop-blur"
        case alarmNavigation = "alarm-navigation@1"
    }

    /// Whether the shell draws dark only or follows the system appearance.
    public enum Appearance: String, Sendable { case dark, system }
    /// The document's appearance, token and typography policies, and the background behind every page.
    public struct Theme: Equatable, Sendable {
        public let appearance: Appearance
        public let tokens: Policy
        public let typography: Policy
        public let background: Background
    }
    /// The ground behind the pages: a token, or a downloaded asset with its blur and scrim.
    public enum Background: Equatable, Sendable {
        case solid(token: Policy)
        case downloaded(assetId: String, recipe: Policy, blur: Blur, scrim: Scrim,
                        motion: Policy, reducedTransparency: Policy)
    }
    /// How much a downloaded backdrop is blurred: a fixed percentage, or a person's saved preference with its starting value.
    public enum Blur: Equatable, Sendable {
        case fixed(percent: Int)
        case preference(key: Policy, initialPercent: Int)
    }
    /// The darkening laid over a backdrop: the canonical scrim, or a gradient of stops with a contrast boost.
    public enum Scrim: Equatable, Sendable {
        case canonical
        case gradient(stops: [GradientStop], increasedContrastBoost: Double)
    }
    /// One stop of a scrim gradient: a position from 0 to 1 and the opacity there.
    public struct GradientStop: Equatable, Sendable {
        public let location: Double
        public let opacity: Double
    }

    // MARK: - Geometry and symbols

    /// Exact SF identity. OS availability is deliberately deferred to UIKit preparation, where a name the OS cannot draw
    /// degrades to a fallback symbol and never rejects the document. Core keeps the authored name and no process state:
    /// the drawn name is the UIKit layer's answer, read from its preflight facts.
    public struct Symbol: Equatable, Sendable {
        /// The name the document asked for, whatever this OS draws.
        public let name: String
        public let rendering: Policy
        /// What a device gap does to the symbol: ``Policy/fallback`` (or the legacy alias ``Policy/reject``) draws
        /// ``ServerUIDeviceFacts/fallbackSymbol``. Nothing rejects the document for a device gap.
        public let unavailable: Policy

        init(name: String, rendering: Policy, unavailable: Policy) {
            self.name = name
            self.rendering = rendering
            self.unavailable = unavailable
        }
    }
    /// A distance: a named token or a literal number of points.
    public enum Space: Equatable, Sendable {
        case token(SpaceToken)
        case points(Double)
        public var points: Double {
            switch self {
            case .token(let token): token.points
            case .points(let points): points
            }
        }
    }
    /// The named spacing steps a document may use.
    public enum SpaceToken: String, Sendable {
        case zero, xs, s, m, l, xl
        case sectionHeader = "section-header"
        public var points: Double {
            switch self {
            case .zero: 0
            case .xs: 4
            case .s: 8
            case .m: 12
            case .l: 16
            case .xl: 24
            case .sectionHeader: 10
            }
        }
    }
    /// The four edge distances of a body.
    public struct Insets: Equatable, Sendable {
        public let top: Space
        public let leading: Space
        public let bottom: Space
        public let trailing: Space
    }
    /// A body's widest extent: unbounded, or a number of points.
    public enum Width: Equatable, Sendable { case unbounded, points(Double) }
    /// How a surface's body is laid out: padding, spacing, width, scroll, chrome and ground.
    public struct BodyLayout: Equatable, Sendable {
        public let padding: Insets
        public let spacing: Space
        public let maxWidth: Width
        public let scroll: Policy
        public let chrome: Policy
        public let ground: Policy
    }
    /// Whether a page navigates as a stack or as navigation columns.
    public enum RouteLayout: String, Sendable { case stack, columns = "navigation-columns" }

    // MARK: - Shell, surfaces, and chrome

    /// The shell's navigation: the first page and tab, the tab list, the shell policy and the chrome.
    public struct Navigation: Equatable, Sendable {
        public let initialPageId: String
        public let initialTabId: String?
        public let initialArguments: EmptyObject
        public let tabs: [Tab]
        public let policy: ShellPolicy
        public let chrome: Chrome
    }
    /// The shell's navigation policies: its type, tab switching and tab reselection.
    public struct ShellPolicy: Equatable, Sendable {
        public let type: Policy
        public let tabSwitch: Policy
        public let reselect: Policy
        public let stackMotion: Policy
        public let restoration: Policy
        public let selectionWhileModal: Policy
    }
    /// One tab: its label, symbol and the page it opens.
    public struct Tab: Equatable, Sendable {
        public let id: String
        public let label: String
        public let icon: Symbol
        public let pageId: String
        public let arguments: EmptyObject
        /// Shows or hides the tab by a rule; `nil` for a tab that is always there.
        public let visibleWhen: ServerUIVisibility?
        /// A count or text drawn on the tab (`sh.badges@1`); `nil` for none.
        public var badgeValue: ServerUIOperand? = nil
    }
    /// The shell chrome: its bar button groups.
    public struct Chrome: Equatable, Sendable { public let groups: [ChromeGroup] }
    /// The side of the bar a group sits on.
    public enum Placement: String, Sendable { case leading, trailing }
    /// Where a chrome item shows: always, on a root page only, or on a root page when the shell menu is available.
    public enum Visibility: String, Sendable {
        case always
        case rootOnly = "root-only"
        case rootWhenMenuAvailable = "root-when-menu-available"
    }
    /// How a chrome item yields space in a crowded bar: required items stay, low items go first.
    public enum Priority: String, Sendable { case required, normal, low }
    /// Whether a chrome item may sit in a vertical rail or stays in the horizontal bar.
    public enum Rail: String, Sendable {
        case eligible
        case horizontalOnly = "horizontal-only"
    }
    /// A chrome item's badge; none is defined.
    public enum Badge: String, Sendable { case none, value }
    /// A group of chrome items with one placement and a horizontal and a vertical grouping policy.
    public struct ChromeGroup: Equatable, Sendable {
        public let id: String
        public let placement: Placement
        public let horizontal: Policy
        public let vertical: Policy
        public let items: [ChromeItem]
    }
    /// The shell menu item: a label, a symbol and where it shows.
    public struct MenuItem: Equatable, Sendable {
        public let id: String
        public let label: String
        public let icon: Symbol
        public let visibility: Visibility
    }
    /// A chrome button: its labels, symbol, visibility, priority, rail, badge and the action it runs.
    public struct ChromeButton: Equatable, Sendable {
        public let id: String
        public let label: String
        public let menuLabel: String
        public let icon: Symbol
        public let visibility: Visibility
        public let priority: Priority
        public let rail: Rail
        public let badge: Badge
        /// The badge's value (`sh.badges@1`), when `badge` says `value` in the document; `nil` for none.
        public var badgeValue: ServerUIOperand? = nil
        public let action: Action
    }
    /// The canonical Quick Links, Profile and connection-state group, with authored destinations.
    public struct ShellHeader: Equatable, Sendable {
        public let id: String
        public let visibility: Visibility
        public let quickLinksAction: Action
        public let profileAction: Action
    }
    /// One item of a chrome group: the shell menu, a button or the shell header.
    public enum ChromeItem: Equatable, Sendable {
        case shellMenu(MenuItem), button(ChromeButton), shellHeader(ShellHeader)
        public var id: String {
            switch self {
            case .shellMenu(let item): item.id
            case .button(let item): item.id
            case .shellHeader(let item): item.id
            }
        }
    }
    /// A surface's toolbar: the shell's chrome, or its own groups in place of it.
    public enum Toolbar: Equatable, Sendable {
        case inherit
        case replace(groups: [ChromeGroup])
    }
    /// The content shared by pages and modals: identity, symbol, body layout, toolbar and components.
    public struct Surface: Equatable, Sendable {
        public let id: String
        public let title: String
        public let icon: Symbol
        public let parameters: EmptyObject
        public let layout: BodyLayout
        public let toolbar: Toolbar
        public let components: [Component]
        public var titleSourceId: String? = nil
    }
    /// A page: a surface the shell navigates to, with its navigation style.
    public struct Page: Equatable, Sendable {
        public let surface: Surface
        public let navigation: RouteLayout
        public var columnPlaceholder: String? = nil
        public var standaloneColumns = false
        public var columnsOnDemand = false
        public var id: String { surface.id }
    }
    /// A modal: a surface presented as a sheet.
    public struct Modal: Equatable, Sendable {
        public let surface: Surface
        public let presentation: Sheet
        public var id: String { surface.id }
    }
    /// How a modal is presented: its size, appearance, placement, grabber, close control and adaptivity.
    public struct Sheet: Equatable, Sendable {
        public let width: SheetWidth
        public let height: SheetHeight
        public let appearance: Appearance
        public let placement: Policy
        public let grabber: Policy
        public let navigation: Policy
        public let close: Close
        public var adaptive = false
        public var fullScreen = false
    }
    /// A sheet's width: form or full page.
    public enum SheetWidth: String, Sendable { case form, page }
    /// A sheet's height: the full height, or fitted to the root or top page.
    public enum SheetHeight: Equatable, Sendable {
        case full
        case fitted(follows: SheetFitFollow, firstOpen: Policy)
    }
    /// Which page a fitted sheet follows.
    public enum SheetFitFollow: String, Sendable {
        case root
        case topPage = "top-page"
    }
    /// A sheet's close control: when it shows, where it sits, its rail behaviour and its exit guard.
    public struct Close: Equatable, Sendable {
        public let visibility: CloseVisibility
        public let placement: Placement
        public let rail: CloseRail
        public let guardPolicy: ExitGuard
    }
    /// At which depths a sheet's close control shows.
    public enum CloseVisibility: String, Sendable {
        case rootOnly = "root-only", allDepths = "all-depths"
    }
    /// Whether the close control may leave the vertical rail.
    public enum CloseRail: String, Sendable {
        case automatic, keepHorizontalWhenAllowed = "keep-horizontal-when-allowed"
    }
    /// A guard run before a sheet closes; none is defined.
    public enum ExitGuard: String, Sendable { case none }

    // MARK: - Typed reads and intents

    /// The scalar types a typed read can produce.
    public enum ScalarKind: String, Sendable {
        case string, number, boolean, entityID = "entity-id"
    }
    /// A typed read of a data source: the source, the path into its value and the type expected.
    public struct Read: Equatable, Sendable {
        public let sourceId: String
        public let path: [String]
        public let kind: ScalarKind

        /// Creates a read.
        public init(sourceId: String, path: [String], kind: ScalarKind) {
            self.sourceId = sourceId
            self.path = path
            self.kind = kind
        }
    }
    /// A string given literally, read from a source, or made by an operand (`sh.rules@1`).
    ///
    /// A `read` and an `expression` may carry the text to draw while the value is unavailable (never while it is loading: the slot keeps
    /// what it showed). ``ServerUIStringResolver`` is the one place that turns one into text.
    public enum StringValue: Equatable, Sendable {
        case literal(String)
        case read(Read, fallback: String? = nil)
        case expression(ServerUIOperand, fallback: String?)
    }
    /// An entity id given literally or read from a source.
    public enum EntityValue: Equatable, Sendable { case literal(String), read(Read) }
    /// Reads supply typed descriptors, not ready runtime data. The power adapter must validate
    /// read-derived entity IDs against ``powerEntityDomains`` before any optimistic write/call.
    public enum Source: Equatable, Sendable {
        public static let powerEntityDomains = ["switch", "input_boolean"]
        case haEntity(id: String, entityId: EntityValue)
        case powerToggle(id: String, entityId: EntityValue)
        case alarmMode(id: String, entityId: String)
        case securityDoor(id: String, entityId: String, kind: DoorKind)
        case householdAwayStatus(id: String, entityId: String)
        case inventorySummary(id: String, configuration: InventorySummary)
        case homeStatus(id: String, configuration: HomeStatus)
        case homeWeather(id: String, configuration: HomeWeather)
        case homeLight(id: String, entityId: String, memberEntityIds: [String] = [])
        case climate(id: String, configuration: ServerUIClimateSource)
        case todoCounts(id: String, configuration: TodoCounts)
        case roomNavigation(id: String, configuration: RoomNavigation)
        case roomDevice(id: String, descriptor: ServerUIRoomDeviceDescriptor)
        case deviceProvider(id: String, descriptor: ServerUIDeviceProviderDescriptor)
        case bedroom(id: String, providerId: String, kind: ServerUIBedroomControl.ProviderKind)
        case mediaRemote(id: String, providerId: String)
        case sprinklerState(id: String, configuration: SprinklerState)
        case vacuum(id: String, descriptor: ServerUIVacuumDescriptor)
        case inventoryList(id: String, space: InventorySpace)
        case todoCollection(id: String, configuration: TodoCollection)
        case profileAccount(id: String)
        case settingsProvider(id: String, configuration: ServerUISettingsSource)
        case camera(id: String, configuration: ServerUICameraDescriptor)
        /// Facts about the app and its window that no entity holds (`sh.app-state@1`), one source per topic.
        case appState(id: String, topic: ServerUIAppState.Topic)
        public var id: String {
            switch self {
            case .haEntity(let id, _), .powerToggle(let id, _),
                 .alarmMode(let id, _), .inventorySummary(let id, _),
                 .homeStatus(let id, _), .homeWeather(let id, _), .homeLight(let id, _, _),
                 .securityDoor(let id, _, _), .climate(let id, _), .todoCounts(let id, _),
                 .roomNavigation(let id, _), .roomDevice(let id, _), .deviceProvider(let id, _), .bedroom(let id, _, _),
                 .mediaRemote(let id, _), .sprinklerState(let id, _), .vacuum(let id, _),
                 .inventoryList(let id, _), .todoCollection(let id, _), .householdAwayStatus(let id, _),
                 .profileAccount(let id), .camera(let id, _), .settingsProvider(let id, _), .appState(let id, _): id
            }
        }
        public var entityId: EntityValue? {
            switch self {
            case .haEntity(_, let value), .powerToggle(_, let value): value
            case .alarmMode(_, let value), .securityDoor(_, let value, _),
                 .householdAwayStatus(_, let value): .literal(value)
            case .inventorySummary, .todoCounts, .roomNavigation, .roomDevice, .deviceProvider, .bedroom,
                 .mediaRemote, .sprinklerState, .vacuum, .inventoryList, .todoCollection, .profileAccount, .settingsProvider, .appState: nil
            case .homeStatus, .homeWeather: nil
            case .homeLight(_, let value, _): .literal(value)
            case .climate(_, let configuration): .literal(configuration.entityId)
            case .camera(_, let configuration): .literal(configuration.entityId)
            }
        }
    }
    /// Explicit inventory sensors and copy; no house configuration or downloaded expressions.
    public struct InventorySummary: Equatable, Sendable {
        public let totalEntityId: String
        public let expiringEntityId: String?
        public let spaceEntityIds: [String]
        public let singular: String
        public let plural: String
        public let expiringSuffix: String
        public let separator: String
        public let loadingText: String
        public let unavailableText: String
        public var expiringLocation: String? = nil
    }
    /// Explicit list counters and authored copy for a chores quick-link subtitle.
    public struct TodoCounts: Equatable, Sendable {
        /// A todo list a counter reads, and whether its open items count as overdue.
        public struct List: Equatable, Sendable {
            public let entityId: String
            public let overdue: Bool
        }
        public let lists: [List]
        public let openSuffix: String
        public let overdueSuffix: String
        public let separator: String
        public let zeroText: String
        public let loadingText: String
        public let unavailableText: String
    }
    /// A read-only sprinkler model with explicit entities and battery threshold.
    public struct SprinklerState: Equatable, Sendable {
        public let controller: SprinklersConfig.Controller
        public let lowBatteryPercent: Double
    }
    /// A navigation push to a page, with its origin and duplicate handling.
    public struct Push: Equatable, Sendable {
        public let pageId: String
        public let arguments: EmptyObject
        public let origin: Policy
        public let duplicate: Policy
    }
    /// A power toggle on a data source, with its feedback and confirmation.
    public struct PowerAction: Equatable, Sendable {
        public let sourceId: String
        public let intent: PowerIntent
        public let feedback: Policy
        public let confirmation: Confirmation
        /// Ask only while this holds (`sh.confirm-when@1`); `nil` always asks. A condition that cannot be answered asks.
        public var confirmWhen: ServerUIPredicate? = nil
    }
    /// What a power action does; toggle is the one intent.
    public enum PowerIntent: String, Sendable { case toggle = "power.toggle" }
    /// The question asked before an action runs: the policy's own, or an authored alert or dialog.
    public enum Confirmation: Equatable, Sendable {
        case policy
        case additional(style: ConfirmationStyle, title: String, message: String?,
                        confirmLabel: String, cancelLabel: String, destructive: Bool)
    }
    /// How an authored confirmation is presented.
    public enum ConfirmationStyle: String, Sendable { case alert, dialog }
    /// What a tap or a rule does: navigate, present or dismiss a surface, toggle power, set local state or call a service.
    public enum Action: Equatable, Sendable {
        case push(Push)
        case selectTab(tabId: String)
        case present(modalId: String, arguments: EmptyObject, ifPresented: Policy)
        case back
        case dismiss(scope: Policy)
        case dismissThenPush(Push)
        case domain(PowerAction)
        case setLocal(stateId: String, value: LocalValue)
        /// Calls any Home Assistant service on a user gesture (`sh.call-service@1`).
        case callService(ServerUICallService)
        /// An action chosen by rule: the first case whose condition holds, else `otherwise` or nothing (`sh.action-rules@1`).
        /// ``ServerUIActionRule/resolve(_:)`` gives the plain action to run, at gesture time.
        indirect case conditional(ServerUIActionRule)
    }

    // MARK: - Closed component variants

    /// The identity and placement shared by every node: id, title, column span and its visibility rule.
    public struct Node: Equatable, Sendable {
        public let id: String
        public let title: String
        public let span: Int
        /// Shows or hides the node in place by a rule (`sh.visible-when@1`); `nil` for a node that is always there.
        public let visibleWhen: ServerUIVisibility?
        /// Enables the node's action only while a rule holds (`sh.enabled-when@1`); `nil` for a node that is always enabled.
        public let enabledWhen: ServerUIEnabledRule?
        /// A count or text drawn on the node's corner (`sh.badges@1`); `nil` for none. A value of 0 or empty draws nothing.
        public var badgeValue: ServerUIOperand? = nil

        init(id: String, title: String, span: Int, visibleWhen: ServerUIVisibility? = nil, enabledWhen: ServerUIEnabledRule? = nil) {
            self.id = id
            self.title = title
            self.span = span
            self.visibleWhen = visibleWhen
            self.enabledWhen = enabledWhen
        }
    }
    /// The text styles a document may name.
    public enum TextStyle: String, CaseIterable, Sendable {
        case body, headline, caption1, subheadline, footnote
        case sectionTitle = "section-title"
    }
    /// A text node: a string value drawn in a text style, with copy for when it is unavailable.
    public struct Text: Equatable, Sendable {
        public let node: Node
        public let value: StringValue
        public let style: TextStyle
        public let unavailableText: String
    }
    /// An account header resolves its identity and avatar exclusively from a native provider.
    public struct AccountHeader: Equatable, Sendable {
        public let node: Node
        public let sourceId: String
        public let fallbackName: String
        public let loadingText: String
        public let unavailableText: String
    }
    /// An authored settings link using the canonical grouped row and navigation intent.
    public struct SettingsLink: Equatable, Sendable {
        public let node: Node
        public let icon: Symbol
        public let subtitle: String
        public let hint: String?
        public let showsChevron: Bool
        public let action: Action
    }
    /// A grid of components: its column rules, spacing, short-row behaviour and children.
    public struct Grid: Equatable, Sendable {
        public let node: Node
        public let minimum: Policy
        public let maxColumns: Int
        public let spacing: Space
        public let equalRowHeights: Bool
        public let shortRow: ShortRow
        public let fold: Fold
        public let children: [Component]
    }
    /// How a short last row fills: shared across the width or leading.
    public enum ShortRow: String, Sendable { case share, leading }
    /// Whether a grid folds columns by the page or by its own container.
    public enum Fold: String, Sendable { case page, container }
    /// The colour family a tile draws in.
    public enum Family: String, Sendable {
        case neutral, lights, occupancy, groceries
        case choreResident1 = "chore-resident-1", choreResident2 = "chore-resident-2"
        case choreUnassigned = "chore-unassigned", choreHome = "chore-home"
    }
    /// Optional, explicitly negotiated presentation of a canonical navigation tile.
    public struct TilePresentation: Equatable, Sendable {
        public let layout: TileLayout
        public let titleLines: Int
        public let fill: TileFill
        public let bodyHint: String?
        /// How the fill follows a rule or an entity's color (`sh.rules@1`); ``fill`` is then its `otherwise` or fallback.
        public var fillRule: ServerUIDynamicLook<TileFill>? = nil
    }
    /// How a tile lays its text out.
    public enum TileLayout: String, Sendable {
        case standard, anchoredBottom = "anchored-bottom"
    }
    /// A tile's fill: the standard one or an authored solid colour.
    public enum TileFill: Equatable, Sendable {
        case standard
        case solidRGB(red: Int, green: Int, blue: Int)
    }
    /// A tile that navigates: its symbol, family, subtitle, optional alarm disc and the action it runs.
    public struct NavigationTile: Equatable, Sendable {
        public let node: Node
        public let icon: Symbol
        public let family: Family
        public let selected: Policy
        public let subtitle: StringValue
        public let presentation: TilePresentation?
        public let alarm: AlarmNavigation?
        public let action: Action
        public var roomVisibility: RoomVisibility? = nil
        public var titleProviderId: String? = nil
    }
    /// Canonical alarm disc beside a navigation body. Service, verb and confirmation remain provider-owned.
    public struct AlarmNavigation: Equatable, Sendable {
        public let sourceId: String
        public let projection: Policy
        public let states: [AlarmStateAppearance]
        public let fallback: AlarmAppearance
        public let loadingText: String
        public let unavailableText: String
        public let errorText: String
        public let hiddenText: String
    }
    /// The alarm appearance for one alarm state.
    public struct AlarmStateAppearance: Equatable, Sendable {
        public let state: String
        public let appearance: AlarmAppearance
    }
    /// How the alarm disc looks in one state: symbol, fill and text.
    public struct AlarmAppearance: Equatable, Sendable {
        public let icon: Symbol
        public let fill: TileFill
        public let text: String
    }
    /// A tile that toggles a data source: its symbol, binding, family and the power action.
    public struct ActionTile: Equatable, Sendable {
        public let node: Node
        public let icon: Symbol
        public let binding: PowerBinding
        public let family: Family
        public let bodyActionId: Policy
        public let actionOrder: [Policy]
        public let stateText: Policy
        public let feedback: Policy
        public let action: PowerAction
        public var powerLabels: PowerLabels? = nil

        /// Authored guest-state copy never replaces the canonical failure/unavailable face.
        public func powerText(spec: TileActionSpec?, failed: Bool, fallback: String?) -> String? {
            guard !failed, let spec, spec.phase != .unavailable, let on = spec.isOn, let powerLabels else { return fallback }
            return on ? powerLabels.on : powerLabels.off
        }
    }
    /// The words a power tile shows when on and when off.
    public struct PowerLabels: Equatable, Sendable {
        public let on: String
        public let off: String
    }
    /// The data source and projection a power tile reads.
    public struct PowerBinding: Equatable, Sendable {
        public let sourceId: String
        public let projection: Policy
    }
    /// Read-only native state copy; no auth, service, permission or feature-controller dispatch.
    public struct BootstrapMessage: Equatable, Sendable {
        public let node: Node
        public let icon: Symbol
        public let message: String
    }
    /// A banner that asks to enable notifications, with its message and button labels.
    public struct NotificationBanner: Equatable, Sendable {
        public let node: Node
        public let message: String
        public let enableLabel: String
        public let dismissLabel: String
    }
    /// The authored component choices.
    public indirect enum Component: Equatable, Sendable {
        case text(Text), grid(Grid), navigationTile(NavigationTile), actionTile(ActionTile), stateTile(StateTile)
        case settingsLink(SettingsLink), remote(Remote), accountHeader(AccountHeader)
        case settingsControl(ServerUISettingsControl)
        case section(Section), row(Row), localTabs(LocalTabs), localControl(LocalControl), boundControl(BoundControl)
        case infoBox(InfoBox), statusPill(StatusPill), pagedRow(PagedRow)
        case button(Button), rowCollection(RowCollection)
        case collection(Collection), form(Form), recipePart(RecipePart), pinnedActions(PinnedActions)
        case statusChip(StatusChip), statusRail(StatusRail), roomOverviewTile(RoomOverviewTile)
        case homeLightTile(HomeLightTile), weatherPanel(WeatherPanel)
        case alarmPanel(AlarmPanel)
        case climate(ServerUIClimateControl)
        case roomCard(RoomCard), roomChip(RoomCard), roomSection(RoomSection), roomNavigationGrid(RoomNavigationGrid)
        case roomDeviceControl(ServerUIRoomDeviceControl)
        case deviceControl(ServerUIDeviceControl)
        case bedroom(ServerUIBedroomControl)
        case vacuum(VacuumControl)
        case cameraTile(CameraTile), cameraVideo(CameraVideo), cameraControls(CameraControls), cameraViewer(CameraControls)
        case bootstrapMessage(BootstrapMessage)
        case notificationBanner(NotificationBanner)
        case overlay(ServerUIOverlay)
        public var node: Node {
            switch self {
            case .text(let value): value.node
            case .grid(let value): value.node
            case .navigationTile(let value): value.node
            case .actionTile(let value): value.node
            case .stateTile(let value): value.node
            case .section(let value): value.node
            case .infoBox(let value): value.node
            case .statusPill(let value): value.node
            case .pagedRow(let value): value.node
            case .row(let value): value.node
            case .localTabs(let value): value.node
            case .localControl(let value): value.node
            case .boundControl(let value): value.node
            case .button(let value): value.node
            case .rowCollection(let value): value.node
            case .collection(let value): value.node
            case .form(let value): value.node
            case .recipePart(let value): value.node
            case .pinnedActions(let value): value.node
            case .statusChip(let value): value.node
            case .statusRail(let value): value.node
            case .roomOverviewTile(let value): value.chip.node
            case .homeLightTile(let value): value.node
            case .weatherPanel(let value): value.node
            case .alarmPanel(let value): value.node
            case .climate(let value): value.node
            case .settingsLink(let value): value.node
            case .settingsControl(let value): value.node
            case .roomCard(let value), .roomChip(let value): value.node
            case .roomSection(let value): value.node
            case .roomNavigationGrid(let value): value.node
            case .roomDeviceControl(let value): value.node
            case .deviceControl(let value): value.node
            case .bedroom(let value): value.node
            case .remote(let value): value.node
            case .vacuum(let value): value.node
            case .accountHeader(let value): value.node
            case .cameraTile(let value): value.node
            case .cameraVideo(let value): value.node
            case .cameraControls(let value): value.node
            case .cameraViewer(let value): value.node
            case .bootstrapMessage(let value): value.node
            case .notificationBanner(let value): value.node
            case .overlay(let value): value.node
            }
        }
    }

    // MARK: - Publisher asset descriptors

    /// Integrity metadata only. Downloaded bytes, origin trust, and decoded image validation are
    /// mandatory parent-owned staging work, not successful compilation.
    public struct Asset: Equatable, Sendable {
        public let id: String
        public let role: AssetRole
        public let source: PublisherAssetSource
        public let sha256: String
        public let mimeType: MIMEType
        public let byteLength: Int
        public let pixelWidth: Int
        public let pixelHeight: Int
    }
    /// An asset the publisher serves from a path.
    public struct PublisherAssetSource: Equatable, Sendable { public let path: String }
    /// What an asset is for: a backdrop or a content image.
    public enum AssetRole: String, Sendable { case backdrop, contentImage = "content-image" }
    /// The image types an asset may be.
    public enum MIMEType: String, Sendable { case png = "image/png", jpeg = "image/jpeg" }
}
