#if os(iOS)
import HassCore
import Observation

// MARK: - Canonical multi-list Chores projection

/// Combines the existing page projection and shared TodoStore, never whole feature controllers.
@MainActor @Observable
final class UKServerUIChoresCollection: UKServerUICollectionSource {
    let configuration: ChoresConfig.Page
    let model: ChoresModel
    let store: EntityStore
    let template = ServerUICompositionDocument.Collection.Template.todo
    var searchText = ""
    private let sources: [String: UKServerUITodoCollection]
    private var selected: UKServerUITodoCollection?
    private let people: ServerUITodoPeople
    @ObservationIgnored private let bag = UKObservationBag()
    @ObservationIgnored private var loadKeys: [String: TodoReloadKey] = [:]
    @ObservationIgnored private var observing = false
    private var loadFailure: String?
    private var summaryTab: SummaryTab?
    private let allowed: Bool
    private let personalization: ServerUICompositionDocument.TodoCollection.Personalization?

    /// The caller passes only `ServerUISummaryScope.lists(for:)` for the authenticated viewer.
    convenience init(summary tab: SummaryTab, lists: [ChoresConfig.TodoList],
                     model: ChoresModel, store: EntityStore, people: ServerUITodoPeople) throws {
        guard tab == .overdue || tab == .upcoming else { throw ServerUIRecordFailure.invalidValue }
        let copy = ProfileSummary.choresEmpty(tab, vacationMode: false)
        let page = ChoresConfig.Page(id: "summary-" + tab.id, title: tab.title, lists: lists, emptyTitle: copy.title,
            emptyDescription: copy.description, hasTaskForm: true, addAction: .assignedTask(defaultAssignee: ""))
        try self.init(configuration: page, model: model, store: store, people: people)
        summaryTab = tab
    }

    init(configuration: ChoresConfig.Page, model: ChoresModel, store: EntityStore, people: ServerUITodoPeople,
         personalization: ServerUICompositionDocument.TodoCollection.Personalization? = nil, allowed: Bool = true) throws {
        guard !configuration.lists.isEmpty, Set(configuration.lists.map(\.entityId)).count == configuration.lists.count else {
            throw ServerUIRecordFailure.missingProvider
        }
        self.configuration = configuration; self.model = model; self.store = store; self.people = people
        self.allowed = allowed
        self.personalization = personalization
        var sources: [String: UKServerUITodoCollection] = [:]
        for list in configuration.lists {
            let provider = ServerUITodoProvider(configuration: try .init(entityId: list.entityId,
                completionScript: list.completionScript, hideCompleted: list.hideCompleted,
                canRename: configuration.editsAdminTodo, canDelete: configuration.deletesItems,
                canAdd: !configuration.hasTaskForm, canCreateTask: configuration.hasTaskForm,
                canEditTask: configuration.hasTaskForm, allowsAttachments: configuration.editsAdminTodo),
                store: model.todos, service: model.service)
            sources[list.entityId] = UKServerUITodoCollection(provider)
        }
        self.sources = sources
    }

    var sections: [UKServerUIRecordSection] {
        guard allowed else { return [] }
        return TodoPageLayout.sections(for: configuration, viewerUserId: model.viewerUserId, store: store, todos: model.todos)
            .filter(\.isShown).compactMap { section in
                guard let source = sources[section.list.entityId] else { return nil }
                let rows = source.records.filter {
                    if case .todo(let item, _) = $0 { return searchText.isEmpty || item.displayTitle.localizedCaseInsensitiveContains(searchText) }
                    return false
                }
                return .init(id: section.list.entityId, title: configuration.hideListHeaders ? nil : section.list.title, records: rows)
            }
    }
    var records: [UKServerUIRecord] { sections.flatMap(\.records) }
    var emptyState: (title: String, message: String, symbol: String)? {
        if let summaryTab {
            let copy = ProfileSummary.choresEmpty(summaryTab, vacationMode: store.entity(ChoresConfig.vacationModeEntityId).state?.state == "on")
            return (copy.title, copy.description, "checklist")
        }
        return (configuration.emptyTitle, configuration.emptyDescription(viewer: model.viewer,
            vacationModeOn: store.entity(ChoresConfig.vacationModeEntityId).state?.state == "on"), "checklist")
    }
    var loading: Bool { visibleSources.contains { $0.loading } }
    var error: String? { allowed ? loadFailure ?? visibleSources.compactMap(\.error).first : ServerUITodoProvider.Failure.forbidden.localizedDescription }
    var hasPendingIntent: Bool { sources.values.contains(where: \.hasPendingIntent) }
    var isPinned: Bool { sources.values.contains(where: \.isPinned) }
    var hasMore: Bool { false }
    var showsSearch: Bool { false }
    /// The authored title, or the resident variant once the signed-in person is known.
    var navigationTitle: String? {
        guard let personalization, let viewer = model.viewer else { return configuration.title }
        return viewer.key == personalization.residentId ? personalization.ownTitle : personalization.otherTitle
    }
    private var visibleSources: [UKServerUITodoCollection] {
        guard allowed else { return [] }
        return configuration.lists.filter { $0.isVisible(to: model.viewerUserId, openItems: store.entity($0.entityId).state,
            keepsOpen: !model.todos.controller(for: $0.entityId).recentlyCompleted.isEmpty) }.compactMap { sources[$0.entityId] }
    }
    func load() async throws {
        guard allowed else { throw ServerUITodoProvider.Failure.forbidden }
        await model.refreshViewer()
        for source in visibleSources { try await source.load() }
        loadFailure = nil
        if !observing {
            observing = true
            for source in visibleSources {
                let id = source.provider.configuration.entityId
                loadKeys[id] = TodoReloadKey(entity: store.entity(id).state, version: 0)
            }
            bag.observe { [weak self] in self?.syncLoads() }
        }
    }
    private func syncLoads() {
        for list in configuration.lists where list.isVisible(to: model.viewerUserId, openItems: store.entity(list.entityId).state) {
            guard let source = sources[list.entityId], !source.hasPendingIntent else { continue }
            let key = TodoReloadKey(entity: store.entity(list.entityId).state, version: 0)
            guard loadKeys[list.entityId] != key else { continue }
            loadKeys[list.entityId] = key
            Task { [weak self] in
                do { try await source.load(); self?.loadFailure = nil }
                catch { self?.loadFailure = error.localizedDescription }
            }
        }
    }
    func loadMore() async throws { throw ServerUIRecordFailure.invalidValue }
    func select(_ record: UKServerUIRecord) throws {
        guard case .todo(_, let provider) = record, let source = sources[provider.configuration.entityId] else { throw ServerUIRecordFailure.staleSelection }
        try authorize(source)
        try source.select(record)
        selected = source
    }
    var editFactory: UKServerUIFormFactory {
        let fields = configuration.hasTaskForm ? (taskPrototype?.fields ?? [:]) : ["name": ServerUICompositionDocument.Form.Control.text]
        return .init(fields: fields, selectionOnly: false) { [self] in
            guard let selected else { throw ServerUIRecordFailure.staleSelection }
            try authorize(selected)
            return try await (configuration.hasTaskForm
                ? selected.taskFactory(editing: true, people: people, viewerUserId: model.viewerUserId)
                : selected.textFactory(editing: true)).open()
        }
    }
    private var taskPrototype: UKServerUIFormFactory? {
        sources.values.first?.taskFactory(editing: false, people: people, viewerUserId: model.viewerUserId)
    }
    var addFactory: UKServerUIFormFactory {
        get throws {
            let firstList = configuration.lists.first { $0.userIds.isEmpty || $0.userIds.contains(model.viewerUserId ?? "") }
                ?? configuration.lists.first
            guard let first = firstList.flatMap({ sources[$0.entityId] }) else { throw ServerUIRecordFailure.missingProvider }
            switch configuration.addAction {
            case .assignedTask(let assignee):
                return authorized(first.taskFactory(editing: false, people: people, viewerUserId: model.viewerUserId, defaultAssignee: assignee), source: first)
            case .groceryItem(let id):
                guard let source = sources[id] else { throw ServerUIRecordFailure.missingProvider }
                return authorized(source.textFactory(editing: false), source: source)
            case .adminTodo(let id):
                guard let source = sources[id] else { throw ServerUIRecordFailure.missingProvider }
                return authorized(source.adminFactory(accessToken: model.accessToken), source: source)
            }
        }
    }

    private func authorize(_ source: UKServerUITodoCollection) throws {
        guard allowed, let list = configuration.lists.first(where: { $0.entityId == source.provider.configuration.entityId }),
              list.userIds.isEmpty || list.userIds.contains(model.viewerUserId ?? "") else {
            throw ServerUITodoProvider.Failure.forbidden
        }
    }

    private func authorized(_ factory: UKServerUIFormFactory, source: UKServerUITodoCollection) -> UKServerUIFormFactory {
        .init(fields: factory.fields, selectionOnly: factory.selectionOnly) { [self] in
            try authorize(source)
            return try await factory.open()
        }
    }
}
#endif
