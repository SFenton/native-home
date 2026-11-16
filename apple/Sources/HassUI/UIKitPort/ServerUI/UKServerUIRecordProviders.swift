#if os(iOS)
import HassCore

// MARK: - Authenticated record registrations

/// One window's selections and forms over the account's shared todo controllers.
///
/// Identity and the household's people come from the session. The record pages (lists, Add action, empty copy, resident
/// variant) come only from the publication's `todo-collection@1` sources: nothing about a page is read from house
/// configuration, and a todo collection the publication names without defining shows nothing.
@MainActor
final class UKServerUIRecordProviders {
    let definition: Definition
    let scope: ServerUISummaryScope
    let records: UKServerUIRecords
    private let inventory: InventoryModels
    private let food: RecipeBrowsingSource

    /// Everything a registry is built from besides the session: when it changes the registry is replaced.
    struct Definition: Equatable {
        /// The household's people, a fact of house configuration.
        let people: [HouseConfig.Person]
        /// The document's record pages by source id, in document order.
        let collections: [(id: String, page: ServerUICompositionDocument.TodoCollection)]
        /// Todo collection ids the document uses without defining them.
        let absent: Set<String>
        /// The `add` and `edit` forms of an absent collection, with the fields the document asks of them.
        let absentForms: [String: [String: ServerUICompositionDocument.Form.Control]]

        init(people: [HouseConfig.Person], document: ServerUICompositionDocument) {
            self.people = people
            collections = document.dataSources.compactMap {
                if case .todoCollection(let id, let page) = $0 { (id, page) } else { nil }
            }
            let defined = Set(collections.map(\.id))
            var absent: Set<String> = [], forms: [String: [String: ServerUICompositionDocument.Form.Control]] = [:]
            var formNodes: [ServerUICompositionDocument.Form] = []
            func visit(_ nodes: [ServerUICompositionDocument.Component]) {
                for node in nodes {
                    switch node {
                    case .collection(let value) where value.template == .todo && !defined.contains(value.providerId):
                        absent.insert(value.providerId)
                    case .form(let value): formNodes.append(value)
                    default: break
                    }
                    visit(node.childComponents)
                }
            }
            visit((document.pages.map(\.surface) + document.modals.map(\.surface)).flatMap(\.components))
            for form in formNodes {
                for suffix in ["-add", "-edit"] where form.providerId.hasSuffix(suffix) {
                    if absent.contains(String(form.providerId.dropLast(suffix.count))) {
                        forms[form.providerId] = Dictionary(form.fields.map { ($0.key, $0.control) }, uniquingKeysWith: { first, _ in first })
                    }
                }
            }
            self.absent = absent
            absentForms = forms
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.people == rhs.people && lhs.absent == rhs.absent && lhs.absentForms == rhs.absentForms
                && lhs.collections.map(\.id) == rhs.collections.map(\.id) && lhs.collections.map(\.page) == rhs.collections.map(\.page)
        }
    }

    init(definition: Definition, authenticatedUserID: String,
         service: any TodoServicing, recipes: any RecipeServing, todos: TodoStore,
         store: EntityStore, accessToken: @escaping @MainActor () async throws -> String,
         isCurrentSession: @escaping @MainActor () -> Bool,
         retaining previous: UKServerUIRecordProviders? = nil) throws {
        self.definition = definition
        let scope = try ServerUISummaryScope(authenticatedUserID: authenticatedUserID, people: definition.people)
        self.scope = scope
        let chores = ChoresModel(service: service, todos: todos, viewerUserId: authenticatedUserID, accessToken: accessToken)
        var assignees = definition.people.map {
            ServerUITodoPeople.Person(userId: $0.haUserId, assignee: $0.taskAssignee, name: $0.name)
        }
        let homeImprovement = DonetickTaskForm.homeImprovementAssignee
        if !assignees.contains(where: { $0.assignee == homeImprovement.value }) {
            assignees.append(.init(userId: nil, assignee: homeImprovement.value, name: homeImprovement.label))
        }
        let people = try ServerUITodoPeople(people: assignees, anyone: "Anyone", viewer: "You", unknownPrefix: "User")
        let inventory = previous?.inventory ?? InventoryModels(client: EverShelfClient(caller: service))
        let food = previous?.food ?? RecipeBrowsingSource(models: FoodModels(service: recipes))
        self.inventory = inventory
        self.food = food
        var records = UKServerUIRecords()

        for (id, authored) in definition.collections {
            let page = authored.page(id: id)
            let source = try UKServerUIChoresCollection(configuration: page, model: chores, store: store, people: people,
                personalization: authored.personalization, allowed: !page.editsAdminTodo || scope.showsAdminTodo)
            records.collections[id] = source
            records.forms[id + "-add"] = try source.addFactory
            records.forms[id + "-edit"] = source.editFactory
        }
        for id in definition.absent { records.collections[id] = UKServerUIAbsentTodoCollection() }
        for (id, fields) in definition.absentForms {
            records.forms[id] = .init(fields: fields, selectionOnly: false) { throw ServerUIRecordFailure.missingProvider }
        }
        for space in InventorySpace.allCases {
            let id = "records-inventory-" + space.rawValue
            let model = inventory.model(for: space)
            let source = try (previous?.records.collections[id] as? UKServerUIInventoryCollection)
                ?? UKServerUIInventoryCollection(InventoryCompositionProvider(sourceID: id, space: space, model: model))
            records.collections[id] = source
            records.forms[id + "-edit"] = source.editorFactory
            records.forms[id + "-sort"] = source.preferencesFactory(sort: true)
            records.forms[id + "-filter"] = source.preferencesFactory(sort: false)
            records.forms[id + "-scan"] = UKServerUIScanForm.factory(sourceID: id,
                makeModel: { ScanItemModel(space: space, client: inventory.everShelf) }) {
                // A successful add is not retried when this refresh fails.
                try await model.refresh()
                for other in InventorySpace.allCases where other != space {
                    let loaded = inventory.model(for: other)
                    if loaded.phase == .content { try await loaded.refresh() }
                }
            }
        }

        let recipeCollection = (previous?.records.collections["records-recipes"] as? UKServerUIRecipeCollection)
            ?? UKServerUIRecipeCollection(food)
        records.collections["records-recipes"] = recipeCollection
        records.collections["records-suggestions"] = previous?.records.collections["records-suggestions"]
            ?? UKServerUIRecipeCollection(food, suggested: true)
        records.recipes["recipes"] = food
        records.forms["records-recipes-sort"] = recipeCollection.preferencesFactory(sort: true, sourceID: "records-recipes")
        records.forms["records-recipes-filter"] = recipeCollection.preferencesFactory(sort: false, sourceID: "records-recipes")

        records.tabScopes["summary"] = .init(allowedTabIDs: scope.tabs.map(\.id), initialTabID: scope.initialTab.id,
            title: { scope.title }, badges: {
                let counts = ProfileSummary.counts(viewer: scope.viewer, store: store)
                return Dictionary(uniqueKeysWithValues: scope.tabs.map { ($0.id, counts.badge(for: $0)) })
            })
        for tab in [SummaryTab.overdue, .upcoming] {
            let id = "summary-" + tab.id
            let lists = scope.lists(for: tab)
            if scope.tabs.contains(tab), !lists.isEmpty {
                let source = try UKServerUIChoresCollection(summary: tab, lists: lists, model: chores, store: store, people: people)
                records.collections[id] = source
                records.forms[id + "-edit"] = source.editFactory
            } else {
                records.forms[id + "-edit"] = .init(fields: UKServerUITodoCollection.taskFields, selectionOnly: false) {
                    throw ServerUITodoProvider.Failure.forbidden
                }
            }
        }
        let expiredID = "summary-expired-food"
        let expired = UKServerUIInventoryCollection(try InventoryCompositionProvider(sourceID: expiredID, space: .allFood,
            model: inventory.model(for: .allFood), query: .expiredFoodSummary), summaryStore: store)
        if scope.tabs.contains(.expiredFood) {
            records.collections[expiredID] = expired
            records.forms[expiredID + "-edit"] = expired.editorFactory
        } else {
            records.forms[expiredID + "-edit"] = .init(fields: expired.editorFactory.fields, selectionOnly: false) {
                throw ServerUITodoProvider.Failure.forbidden
            }
        }

        records.forms = records.forms.mapValues { factory in
            .init(fields: factory.fields, selectionOnly: factory.selectionOnly) {
                guard isCurrentSession() else { throw CancellationError() }
                let form = try await factory.open()
                guard isCurrentSession() else {
                    try form.discard()
                    throw CancellationError()
                }
                return form
            }
        }
        self.records = records
    }

    /// Settings-only presentation state is supplied by its own provider bundle.
    static func required(by document: ServerUICompositionDocument) -> Bool {
        func needs(_ nodes: [ServerUICompositionDocument.Component]) -> Bool {
            nodes.contains { node in
                switch node {
                case .collection, .form, .recipePart: return true
                case .localTabs(let tabs) where tabs.scopeProviderId == "summary": return true
                case .pinnedActions(let actions) where actions.searchProviderId != nil: return true
                case .navigationTile(let tile) where tile.titleProviderId != nil: return true
                default: return needs(node.childComponents)
                }
            }
        }
        return (document.pages.map(\.surface) + document.modals.map(\.surface)).contains { needs($0.components) }
            || document.dataSources.contains { if case .inventoryList = $0 { true } else { false } }
    }
}
#endif
