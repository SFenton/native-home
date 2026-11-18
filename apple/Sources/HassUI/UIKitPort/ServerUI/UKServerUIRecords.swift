#if os(iOS)
import HassCore
import Observation
import UIKit

// MARK: - Narrow injectable providers

/// One collection source, shared by every authored consumer. It neither creates a session nor routes pages.
@MainActor
protocol UKServerUICollectionSource: AnyObject {
    var template: ServerUICompositionDocument.Collection.Template { get }
    var records: [UKServerUIRecord] { get }
    var sections: [UKServerUIRecordSection] { get }
    var emptyState: (title: String, message: String, symbol: String)? { get }
    var summary: String? { get }
    var navigationTitle: String? { get }
    var loading: Bool { get }
    var error: String? { get }
    var hasPendingIntent: Bool { get }
    var isPinned: Bool { get }
    var hasMore: Bool { get }
    /// Whether the next page is loading, which shows the footer spinner.
    var loadingMore: Bool { get }
    var searchText: String { get set }
    /// What the list is currently asked, besides ``searchText`` (a sort or filter): when it changes the rows are replaced, never animated
    /// as removals and insertions (`ListUpdateCause.reset`).
    var listQuestion: String { get }
    var showsSearch: Bool { get }
    func actionState(_ role: ServerUICompositionDocument.PinnedActions.Role) -> UKServerUIActionState
    func load() async throws
    func loadMore() async throws
    func select(_ record: UKServerUIRecord) throws
    func displayed(_ record: UKServerUIRecord)
}

struct UKServerUIRecordSection {
    let id: String
    let title: String?
    let records: [UKServerUIRecord]
}

struct UKServerUIActionState: Equatable {
    var visible = true
    var active = false
    var showsTitle: Bool?
    var enabled = true
    var busy = false
}

extension UKServerUICollectionSource {
    var listQuestion: String { "" }
    var sections: [UKServerUIRecordSection] { [.init(id: "rows", title: nil, records: records)] }
    var emptyState: (title: String, message: String, symbol: String)? { nil }
    var summary: String? { nil }
    var navigationTitle: String? { nil }
    var isPinned: Bool { hasPendingIntent }
    var loadingMore: Bool { false }
    var showsSearch: Bool { true }
    func actionState(_ role: ServerUICompositionDocument.PinnedActions.Role) -> UKServerUIActionState { .init() }
    func displayed(_ record: UKServerUIRecord) {}
}

/// Closed native row-template payloads. These are values, not feature view controllers.
@MainActor
enum UKServerUIRecord {
    case row(ServerUIRowItem)
    case bedroom(ServerUIBedroomAlarms.Row, UKServerUIBedroomSource)
    case todo(TodoItem, ServerUITodoProvider)
    case inventory(InventoryDisplayItem, InventoryCompositionProvider)
    case recipe(RecipeCard)
    var id: String {
        switch self {
        case .row(let item): item.id
        case .bedroom(let item, _): item.id
        case .todo(let item, let source): source.configuration.entityId + ":" + item.identity
        case .inventory(let item, _): item.id
        case .recipe(let item): item.dedupeKey
        }
    }

    /// Whether this record draws and acts exactly as `other` did, so its retained row needs no reconfiguration.
    ///
    /// Records that carry no comparable value (a bedroom alarm) always count as changed.
    func isUnchanged(from other: UKServerUIRecord) -> Bool {
        switch (self, other) {
        case (.row(let new), .row(let old)): new == old
        case (.todo(let new, let newSource), .todo(let old, let oldSource)): new == old && newSource === oldSource
        case (.inventory(let new, let newSource), .inventory(let old, let oldSource)): new == old && newSource === oldSource
        case (.recipe(let new), .recipe(let old)): new == old
        default: false
        }
    }

    func matches(_ template: ServerUICompositionDocument.Collection.Template) -> Bool {
        switch (self, template) {
        case (.row, .rows), (.bedroom, .rows), (.todo, .todo), (.inventory, .inventory), (.recipe, .recipes), (.recipe, .carousel): true
        default: false
        }
    }
}

/// Factory metadata is checked before publication; opening a form captures the selected immutable target.
@MainActor
struct UKServerUIFormFactory {
    let fields: [String: ServerUICompositionDocument.Form.Control]
    let selectionOnly: Bool
    let open: @MainActor () async throws -> any ServerUIFormSession
}

/// Parent integration supplies providers, never an unrestricted connection to a preview renderer.
@MainActor
struct UKServerUIRecords {
    private(set) var identity = UUID()
    var collections: [String: any UKServerUICollectionSource] = [:] { didSet { identity = UUID() } }
    var forms: [String: UKServerUIFormFactory] = [:] { didSet { identity = UUID() } }
    var recipes: [String: RecipeBrowsingSource] = [:] { didSet { identity = UUID() } }
    var sections: [String: @MainActor () -> UKServerUISectionState] = [:] { didSet { identity = UUID() } }
    var tabScopes: [String: UKServerUITabScope] = [:] { didSet { identity = UUID() } }
    var actionStates: [String: @MainActor () -> UKServerUIActionState] = [:] { didSet { identity = UUID() } }

    var hasPendingIntent: Bool {
        collections.values.contains(where: \.isPinned) || recipes.values.contains(where: \.hasPendingIntent)
    }

    func isVisible(_ component: ServerUICompositionDocument.Component) -> Bool {
        if case .section(let value) = component, let id = value.presentationProviderId {
            return sections[id]?().visible == true
        }
        return true
    }

    func validate(_ document: ServerUICompositionDocument) throws {
        func unavailable(_ pointer: String) throws -> Never {
            throw UKServerUIRendererError(code: .unavailableSource, pointer: pointer)
        }
        func walk(_ nodes: [ServerUICompositionDocument.Component], _ path: String, root: Bool) throws {
            for (index, node) in nodes.enumerated() {
                let path = path + "/\(index)"
                switch node {
                case .section(let value):
                    if let id = value.presentationProviderId, sections[id] == nil { try unavailable(path + "/props/presentationProviderId") }
                case .localTabs(let value):
                    if let id = value.scopeProviderId {
                        guard let scope = tabScopes[id], !scope.allowedTabIDs.isEmpty,
                              Set(scope.allowedTabIDs).count == scope.allowedTabIDs.count,
                              scope.allowedTabIDs.contains(scope.initialTabID),
                              Set(scope.allowedTabIDs).isSubset(of: Set(value.tabs.map(\.id))),
                              value.showsSelector || scope.automaticSelection != nil else {
                            try unavailable(path + "/props/scopeProviderId")
                        }
                        for tab in value.tabs where scope.allowedTabIDs.contains(tab.id) {
                            try walk(tab.children, path + "/tabs/" + tab.id + "/children", root: false)
                        }
                        continue
                    }
                case .navigationTile(let value):
                    if let id = value.titleProviderId, collections[id]?.navigationTitle == nil {
                        try unavailable(path + "/props/titleProviderId")
                    }
                case .collection(let value):
                    guard let provider = collections[value.providerId], provider.template == value.template else {
                        try unavailable(path + "/props/providerId")
                    }
                    if !value.bedroomLinks.isEmpty {
                        guard let bedroom = provider as? UKServerUIBedroomCollection,
                              bedroom.source.providerID == bedroom.source.session.descriptor.wakeProviderId,
                              value.bedroomLinks.allSatisfy({
                                  bedroom.source.session.devices.wakeLight.config.source(for: $0.side) != nil
                              }) else { try unavailable(path + "/props/bedroomLinks") }
                    }
                    if let inventory = provider as? UKServerUIInventoryCollection,
                       inventory.provider.query == .expiredFoodSummary, inventory.summaryStore == nil {
                        try unavailable(path + "/props/providerId")
                    }
                case .form(let value):
                    guard root else { throw UKServerUIRendererError(code: .unsupportedPolicy, pointer: path) }
                    guard let factory = forms[value.providerId], factory.selectionOnly == value.selectionOnly,
                          Dictionary(value.fields.map { ($0.key, $0.control) }, uniquingKeysWith: { first, _ in first }) == factory.fields
                    else { try unavailable(path + "/props") }
                case .recipePart(let value):
                    if recipes[value.providerId] == nil { try unavailable(path + "/props/providerId") }
                case .pinnedActions(let value):
                    guard root else { throw UKServerUIRendererError(code: .unsupportedPolicy, pointer: path) }
                    if let id = value.searchProviderId, collections[id] == nil { try unavailable(path + "/props/searchProviderId") }
                    for item in value.items {
                        if let id = item.stateProviderId, actionStates[id] == nil { try unavailable(path + "/props/items/" + item.id) }
                    }
                default: break
                }

                try walk(node.childComponents, path + "/children", root: false)
            }

        }
        for surface in document.pages.map(\.surface) + document.modals.map(\.surface) {
            guard surface.components.filter({ if case .pinnedActions = $0 { true } else { false } }).count <= 1,
                  surface.components.filter({ if case .form = $0 { true } else { false } }).count <= 1 else {
                throw UKServerUIRendererError(code: .unsupportedPolicy, pointer: "/document/pages")
            }
            try walk(surface.components, "/document/surfaces/" + surface.id + "/components", root: true)
        }
        for (index, source) in document.dataSources.enumerated() {
            if case .inventoryList(let id, let space) = source {
                guard let provider = collections[id] as? UKServerUIInventoryCollection, provider.provider.model.space == space,
                      provider.provider.sourceID == id else { try unavailable("/document/dataSources/\(index)") }
            }
        }
    }
}

extension ServerUICompositionDocument.Action {
    var leavesForm: Bool {
        switch self {
        case .back, .dismiss, .dismissThenPush, .selectTab: true
        case .present(_, _, let policy): policy == .replace
        case .push, .domain, .setLocal, .callService: false
        case .conditional(let rule): rule.actions.contains(where: \.leavesForm)
        }
    }
}

// MARK: - Todo collection

@MainActor @Observable
final class UKServerUITodoCollection: UKServerUICollectionSource {
    static let taskFields: [String: ServerUICompositionDocument.Form.Control] = [
        "name": .text, "assignee": .choice, "description": .multiline,
        "hasDueDate": .toggle, "dueDate": .date, "hasDueTime": .toggle, "dueTime": .time,
        "hideOnVacation": .toggle, "priority": .choice, "recurrence": .choice,
        "recurrenceInterval": .number, "recurrenceUnit": .choice, "recurrenceDays": .weekdays,
    ]
    let provider: ServerUITodoProvider
    let template = ServerUICompositionDocument.Collection.Template.todo
    var searchText = ""
    private(set) var selected: TodoItem?
    init(_ provider: ServerUITodoProvider) { self.provider = provider }
    var records: [UKServerUIRecord] {
        (provider.items ?? []).filter { searchText.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(searchText) }
            .map { .todo($0, provider) }
    }
    var loading: Bool { provider.items == nil }
    var error: String? { provider.error }
    var hasPendingIntent: Bool { provider.hasPendingIntent }
    var isPinned: Bool { provider.isPinned }
    var hasMore: Bool { false }
    func load() async throws { try await provider.load() }
    func loadMore() async throws { throw ServerUIRecordFailure.invalidValue }
    func select(_ record: UKServerUIRecord) throws {
        guard case .todo(let item, let source) = record, source === provider else { throw ServerUIRecordFailure.staleSelection }
        try provider.validate(expected: item)
        selected = item
    }

    func textFactory(editing: Bool) -> UKServerUIFormFactory {
        .init(fields: ["name": .text], selectionOnly: false) { [self] in
            if editing {
                guard let selected else { throw ServerUIRecordFailure.staleSelection }
                try provider.validate(expected: selected)
                return try provider.textForm(identity: selected.identity)
            }

            return try provider.textForm()
        }
    }

    func adminFactory(accessToken: @escaping @MainActor () async throws -> String) -> UKServerUIFormFactory {
        .init(fields: ["name": .multiline, "images": .attachment], selectionOnly: false) { [provider] in
            try ServerUIAdminTodoForm(provider: provider, accessToken: accessToken)
        }
    }

    func taskFactory(editing: Bool, people: ServerUITodoPeople,
                     viewerUserId: String? = nil, defaultAssignee: String = "") -> UKServerUIFormFactory {
        .init(fields: Self.taskFields,
              selectionOnly: false) { [self] in
            let identity: String?
            if editing {
                guard let selected else { throw ServerUIRecordFailure.staleSelection }
                try provider.validate(expected: selected)
                identity = selected.identity
            } else { identity = nil }
            return try await provider.taskForm(identity: identity, people: people, viewerUserId: viewerUserId,
                                               defaultAssignee: defaultAssignee, grouping: Self.taskGroups)
        }
    }

    private static func taskGroups(_ fields: [ServerUIFormValue]) -> [ServerUIFormGroup] {
        func group(_ id: String, _ keys: [String], title: String = "", footer: String = "") -> ServerUIFormGroup {
            .init(id: id, title: title, footer: footer, fields: keys.compactMap { key in fields.first { $0.key == key } })
        }
        return [
            group("name", ["name"], title: "Task Name", footer: DonetickTaskFormFields.nameFooter),
            group("description", ["description"], title: "Description", footer: DonetickTaskFormFields.descriptionFooter),
            group("who", ["assignee", "priority"]),
            group("when", ["hasDueDate", "dueDate", "hasDueTime", "dueTime", "recurrence"]),
            group("interval", ["recurrenceInterval", "recurrenceUnit"],
                  footer: "How often to repeat: every 1 to 365 days, weeks, months, or years."),
            group("days", ["recurrenceDays"], title: "Days of Week"),
            group("vacation", ["hideOnVacation"], footer: "This task will not show up in your chores lists while Vacation Mode is on."),
        ].filter { $0.fields.contains(where: \.visible) }
    }
}

// MARK: - Inventory collection

@MainActor @Observable
final class UKServerUIInventoryCollection: UKServerUICollectionSource {
    let provider: InventoryCompositionProvider
    let summaryStore: EntityStore?
    let template = ServerUICompositionDocument.Collection.Template.inventory
    private(set) var selected: InventoryCompositionProvider.Selection?
    @ObservationIgnored private let summaryBag = UKObservationBag()
    @ObservationIgnored private var observingSummary = false
    @ObservationIgnored private var lastSummarySensor: EntityState?
    @ObservationIgnored private var lastSummaryVacation = false
    private var summaryLoadFailure: String?
    init(_ provider: InventoryCompositionProvider, summaryStore: EntityStore? = nil) {
        self.provider = provider; self.summaryStore = summaryStore
    }
    private var summaryEmpty: ProfileSummary.EmptyCopy? {
        guard provider.query == .expiredFoodSummary, let summaryStore else { return nil }
        return ProfileSummary.expiredFoodEmpty(
            count: ProfileSummary.expiredFoodCount(summaryStore.entity(ProfileSummary.expiredFoodEntityId).state,
                now: provider.model.calendar.now(), calendar: provider.model.calendar.calendar),
            vacationMode: summaryStore.entity(ChoresConfig.vacationModeEntityId).state?.state == "on")
    }
    var searchText: String {
        get { provider.model.searchQuery }
        set { provider.model.searchQuery = newValue }
    }
    var listQuestion: String { "\(provider.model.sortMode)|\(provider.model.sortDirection)|\(provider.model.filterMode)|\(provider.model.phase)" }
    var records: [UKServerUIRecord] { summaryEmpty == nil ? provider.items.map { .inventory($0, provider) } : [] }
    var sections: [UKServerUIRecordSection] {
        if provider.query == .expiredFoodSummary { return [.init(id: "expired-food", title: SummaryTab.expiredFood.title, records: records)] }
        return InventorySections.make(provider.items, sort: provider.model.sortMode, calendar: provider.model.calendar).map {
            .init(id: $0.id, title: $0.title, records: $0.items.map { .inventory($0, provider) })
        }
    }
    var emptyState: (title: String, message: String, symbol: String)? {
        if provider.query == .expiredFoodSummary {
            let copy = summaryEmpty ?? ProfileSummary.noExpiredFood
            let vacation = summaryStore?.entity(ChoresConfig.vacationModeEntityId).state?.state == "on"
            return (copy.title, copy.description, vacation ? "airplane" : "checkmark.circle")
        }
        return provider.model.emptyState.map { ($0.title, $0.description, provider.model.loadError == nil ? "basket" : "exclamationmark.triangle") }
    }
    var showsSearch: Bool { provider.query == .collection && provider.model.phase == .content && (!provider.model.items.isEmpty || provider.model.searchActive) }
    func actionState(_ role: ServerUICompositionDocument.PinnedActions.Role) -> UKServerUIActionState {
        if provider.query == .expiredFoodSummary { return .init(visible: false) }
        let controls = !provider.model.items.isEmpty || provider.model.searchActive
        switch role {
        case .sort: return .init(visible: controls, active: provider.model.sortActive)
        case .filter: return .init(visible: controls, active: provider.model.filterActive)
        case .create: return .init(showsTitle: !controls)
        }
    }
    var loading: Bool { summaryEmpty == nil && (provider.model.phase == .loading || provider.model.isSearching) }
    var error: String? { summaryEmpty == nil ? summaryLoadFailure ?? provider.model.loadError : nil }
    var hasPendingIntent: Bool { provider.hasPendingIntent }
    var hasMore: Bool { false }
    func load() async throws {
        if provider.query == .expiredFoodSummary, let summaryStore, !observingSummary {
            observingSummary = true
            lastSummarySensor = summaryStore.entity(ProfileSummary.expiredFoodEntityId).state
            lastSummaryVacation = summaryStore.entity(ChoresConfig.vacationModeEntityId).state?.state == "on"
            summaryBag.observe { [weak self] in self?.refreshSummary() }
        }
        guard summaryEmpty == nil else { return }
        await provider.model.load()
        summaryLoadFailure = nil
        if let error { throw ServerUIRecordFailure.unavailable(error) }
    }
    private func refreshSummary() {
        guard let summaryStore else { return }
        let sensor = summaryStore.entity(ProfileSummary.expiredFoodEntityId).state
        let vacation = summaryStore.entity(ChoresConfig.vacationModeEntityId).state?.state == "on"
        guard sensor != lastSummarySensor || vacation != lastSummaryVacation else { return }
        lastSummarySensor = sensor
        lastSummaryVacation = vacation
        Task { [weak self] in
            do { try await self?.load() }
            catch { self?.summaryLoadFailure = error.localizedDescription }
        }
    }
    func loadMore() async throws { throw ServerUIRecordFailure.invalidValue }
    func select(_ record: UKServerUIRecord) throws {
        guard case .inventory(let item, let source) = record, source === provider else { throw ServerUIRecordFailure.staleSelection }
        let selection = try provider.select(item.id)
        guard selection.item == item else { throw ServerUIRecordFailure.staleSelection }
        selected = selection
    }
    var editorFactory: UKServerUIFormFactory {
        .init(fields: ["quantity": .number, "hasExpiry": .toggle, "expiry": .date, "prepared": .toggle], selectionOnly: false) { [self] in
            guard let selected else { throw ServerUIRecordFailure.staleSelection }
            return try ServerUIInventoryForm(sourceID: provider.sourceID, model: provider.editor(for: selected))
        }
    }
    func preferencesFactory(sort: Bool) -> UKServerUIFormFactory {
        .init(fields: sort ? ["sort": .options, "direction": .options] : ["filter": .options], selectionOnly: true) { [provider] in
            try provider.preferencesForm(sort: sort)
        }
    }
}

// MARK: - Recipe collection and forms

@MainActor
final class UKServerUIRecipeCollection: UKServerUICollectionSource {
    let source: RecipeBrowsingSource
    let suggested: Bool
    init(_ source: RecipeBrowsingSource, suggested: Bool = false) { self.source = source; self.suggested = suggested }
    var template: ServerUICompositionDocument.Collection.Template { suggested ? .carousel : .recipes }
    var records: [UKServerUIRecord] { (suggested ? source.suggestions.items : source.collection.items).map(UKServerUIRecord.recipe) }
    var summary: String? { suggested ? nil : RecipeGrid.sortSummary(source.collection.sort) }
    var loading: Bool {
        suggested ? source.suggestions.phase == .idle || source.suggestions.phase == .loading
            : source.collection.phase == .idle || source.collection.phase == .loading
    }
    var error: String? {
        if !suggested && source.collection.nextPageFailed { return "Unable to load more recipes." }
        return (suggested ? source.suggestions.phase == .failed : source.collection.phase == .failed) ? "Unable to load recipes." : nil
    }
    var hasPendingIntent: Bool { source.hasPendingIntent }
    var hasMore: Bool { !suggested && source.collection.hasMore }
    var loadingMore: Bool { !suggested && (source.collection.nextPageLoading || source.collection.hydrating) }
    var searchText: String {
        get { source.collection.searchText }
        set { source.collection.searchText = newValue }
    }
    func actionState(_ role: ServerUICompositionDocument.PinnedActions.Role) -> UKServerUIActionState {
        switch role {
        case .sort: .init(active: source.collection.sort != .availability)
        case .filter: .init(active: source.collection.filters != RecipeFilters())
        case .create: .init()
        }
    }
    func load() async throws {
        if suggested { source.suggestions.load(); await source.suggestions.settle() }
        else if source.collection.nextPageFailed { try await loadMore() }
        else { source.collection.reload(); await source.collection.settle() }
        if let error { throw ServerUIRecordFailure.unavailable(error) }
    }
    func loadMore() async throws {
        if source.collection.nextPageFailed { source.collection.retryNextPage() }
        else { source.collection.loadNextPage() }
        await source.collection.settle()
        if source.collection.nextPageFailed { throw ServerUIRecordFailure.unavailable("Unable to load more recipes.") }
    }
    func displayed(_ record: UKServerUIRecord) {
        if !suggested, case .recipe(let item) = record { source.collection.itemAppeared(item) }
    }
    func select(_ record: UKServerUIRecord) throws {
        guard case .recipe(let recipe) = record,
              records.contains(where: { if case .recipe(let current) = $0 { current == recipe } else { false } }) else {
            throw ServerUIRecordFailure.staleSelection
        }
        try source.select(recipe).load()
    }
    func preferencesFactory(sort: Bool, sourceID: String) -> UKServerUIFormFactory {
        .init(fields: sort ? ["sort": .options] : ["expiringOnly": .toggle, "horizon": .segmented,
            "minimumCoverage": .percent, "availabilityWeight": .percent, "expiryWeight": .percent], selectionOnly: true) { [source] in
            let model = source.collection, filters = model.filters
            let fields: [ServerUIFormValue] = sort ? [
                .choice("sort", "Sort By", model.sort.rawValue, RecipeSort.allCases.map { .init($0.title, $0.rawValue) }, control: .options),
            ] : [
                .toggle("expiringOnly", "Expiring Ingredients Only", filters.expiringOnly),
                .choice("horizon", "Expiring Within", String(filters.expiringWithinDays),
                        RecipeFilters.horizons.map { .init(RecipeFilters.horizon($0).title, String($0)) }, control: .segmented),
                .number("minimumCoverage", "Minimum Ingredients Available", filters.minimumCoverage, maximum: 100, step: 5, control: .percent),
                .number("availabilityWeight", "Availability Weight", filters.availabilityWeight, maximum: 100, step: 5, control: .percent),
                .number("expiryWeight", "Expiry Weight", filters.expiryWeight, maximum: 100, step: 5, control: .percent),
            ]
            let defaults = RecipeFilters()
            return try ServerUIValueForm(identity: .init(ownerId: sourceID, recordId: sort ? "sort" : "filter"), fields: fields,
                defaults: sort ? ["sort": .string(RecipeSort.availability.rawValue)] : [
                    "expiringOnly": .boolean(defaults.expiringOnly), "horizon": .string(String(defaults.expiringWithinDays)),
                    "minimumCoverage": .number(defaults.minimumCoverage), "availabilityWeight": .number(defaults.availabilityWeight),
                    "expiryWeight": .number(defaults.expiryWeight),
                ], grouping: { fields in
                    if sort { return [.init(id: "sort", title: "Sort By", fields: fields)] }
                    var fields = fields
                    let expiring = fields.first { $0.key == "expiringOnly" }?.value == .boolean(true)
                    for index in fields.indices {
                        if fields[index].key == "horizon" { fields[index].enabled = expiring }
                        if ["availabilityWeight", "expiryWeight"].contains(fields[index].key) {
                            fields[index].enabled = model.sort != .alphabetical
                        }
                    }
                    return [
                        .init(id: "coverage", title: "Ingredient Coverage",
                            footer: "Only show recipes where at least this percentage of required ingredients is available.",
                            fields: fields.filter { $0.key == "minimumCoverage" }),
                        .init(id: "expiring", title: "Expiring Ingredients", fields: fields.filter { ["expiringOnly", "horizon"].contains($0.key) }),
                        .init(id: "ranking", title: "Ranking Strength",
                            footer: model.sort == .alphabetical ? "Weights are unavailable while recipes are sorted alphabetically."
                                : "Tune how strongly available and expiring ingredients influence ranked recipe results.",
                            fields: fields.filter { ["availabilityWeight", "expiryWeight"].contains($0.key) }),
                    ]
                }) { values in
                if sort {
                    guard let sort = try RecipeSort(rawValue: values.formString("sort")) else { throw ServerUIRecordFailure.invalidValue }
                    model.apply(sort: sort)
                } else {
                    guard let horizon = try Int(values.formString("horizon")) else { throw ServerUIRecordFailure.invalidValue }
                    model.apply(filters: try .init(expiringOnly: values.formBoolean("expiringOnly"), expiringWithinDays: horizon,
                        minimumCoverage: values.formNumber("minimumCoverage"), availabilityWeight: values.formNumber("availabilityWeight"),
                        expiryWeight: values.formNumber("expiryWeight")))
                }
            }
        }
    }
}
#endif
