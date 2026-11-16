import Foundation
import HassTestSupport
import Testing
@testable import HassCore

// MARK: - The publication's todo collections

/// The `todo-collection@1` source: what it compiles to, how it becomes the page the todo views read, and that nothing about
/// a page depends on house configuration.
@Suite @MainActor
struct ServerUITodoCollectionTests {
    private func corpus(_ name: String) throws -> ServerUICompositionPublication {
        let url = ServerUIContractCorpusTests.directory.appendingPathComponent("accept/\(name).json")
        return try ServerUICompositionPublication.decode(Data(contentsOf: url))
    }

    private func collections(_ publication: ServerUICompositionPublication) -> [String: ServerUICompositionDocument.TodoCollection] {
        Dictionary(uniqueKeysWithValues: publication.document.dataSources.compactMap {
            if case .todoCollection(let id, let page) = $0 { (id, page) } else { nil }
        })
    }

    @Test func taskPageCompilesToItsLists() throws {
        let page = try #require(collections(corpus("todo-collection-task-page"))["chores-page"])
        #expect(page.title == "Chores")
        #expect(page.lists.map(\.entityId) == ["todo.demo_overdue", "todo.demo_upcoming"])
        #expect(page.lists[0].completionScript == "script.demo_finish")
        #expect(page.lists[0].userIds == ["user-1", "user-2"])
        #expect(page.lists[1].userIds.isEmpty && page.lists[1].visibility == nil)
        #expect(page.lists[1].hideWhenNoOpenItems && !page.lists[0].hideWhenNoOpenItems)
        #expect(page.addAction == .task(defaultAssignee: "") && page.hasTaskForm)
        #expect(page.personalization == .init(residentId: "resident_1", ownTitle: "Your Chores", otherTitle: "Alex's Chores",
                                              ownEmptyDescription: "You have no chores due."))
    }

    @Test func groceryAndAdminPagesChooseTheirAddActionAndFlags() throws {
        let grocery = try #require(collections(corpus("todo-collection-grocery-page"))["chores-page"])
        #expect(grocery.addAction == .grocery(entityId: "todo.demo_groceries") && !grocery.hasTaskForm)
        #expect(grocery.hideListHeaders && !grocery.lists[0].hideCompleted)
        let admin = try #require(collections(corpus("todo-collection-admin-page"))["chores-page"])
        #expect(admin.addAction == .admin(entityId: "todo.demo_admin") && admin.hiddenByVacation)
        #expect(admin.personalization == nil)
    }

    @Test func thePageValueCarriesWhatTheViewsRead() throws {
        let authored = try #require(collections(corpus("todo-collection-task-page"))["chores-page"])
        let page = authored.page(id: "chores-page")
        #expect(page.id == "chores-page" && page.title == "Chores")
        #expect(page.lists.map(\.userIds) == [["user-1", "user-2"], []])
        #expect(page.lists.map(\.completionScript) == ["script.demo_finish", nil])
        #expect(page.resident == Resident(key: "resident_1"))
        #expect(!page.editsAdminTodo && page.deletesItems && page.hasTaskForm)
        #expect(page.emptyDescription(viewer: Resident(key: "resident_1"), vacationModeOn: false) == "You have no chores due.")
        #expect(page.emptyDescription(viewer: Resident(key: "resident_2"), vacationModeOn: false) == "No chores due.")
        let grocery = try #require(collections(corpus("todo-collection-grocery-page"))["chores-page"]).page(id: "g")
        #expect(grocery.deletesItems && !grocery.editsAdminTodo)
        if case .groceryItem(let id) = grocery.addAction { #expect(id == "todo.demo_groceries") } else { Issue.record("grocery action") }
        let admin = try #require(collections(corpus("todo-collection-admin-page"))["chores-page"]).page(id: "a")
        #expect(admin.editsAdminTodo && !admin.deletesItems && admin.hiddenByVacation)
    }

    @Test func aPageWithoutAResidentUsesTheCompiledOwnWording() {
        let page = ChoresConfig.Page(id: "p", title: "P", lists: [], emptyTitle: "T", emptyDescription: "Empty",
                                     resident: Resident(key: "resident_1"), addAction: .assignedTask(defaultAssignee: ""))
        #expect(page.emptyDescription(viewer: Resident(key: "resident_1"), vacationModeOn: false) == "You have no chores due. Nice job!")
    }

    @Test func aTodoCollectionNodeWithoutASourceStillCompiles() throws {
        let publication = try corpus("todo-collection-collection-without-source")
        #expect(collections(publication).isEmpty)
        #expect(publication.capabilities.contains("sh.collection@1") && !publication.capabilities.contains("sh.todo-collection@1"))
    }

    @Test func theCapabilityIsRequiredOnlyByADocumentThatDeclaresACollection() throws {
        #expect(try corpus("todo-collection-task-page").capabilities.contains("sh.todo-collection@1"))
        #expect(try corpus("todo-collection-source-without-collection").capabilities.contains("sh.todo-collection@1"))
        #expect(try !corpus("fixture-composition-first-slice").capabilities.contains("sh.todo-collection@1"))
        #expect(ServerUICompositionPublication.supportedCapabilities.contains("sh.todo-collection@1"))
    }

    // MARK: Household controls

    @Test func settingsControlsListTheControlsPlacedOverOneProvider() throws {
        let publication = try corpus("family-settings-controls")
        let providers = publication.document.dataSources.compactMap { source -> String? in
            if case .settingsProvider(_, let configuration) = source { configuration.providerId } else { nil }
        }
        #expect(!providers.isEmpty)
        let all = providers.flatMap { publication.document.settingsControls(overProvider: $0) }
        #expect(!all.isEmpty)
        #expect(publication.document.settingsControls(overProvider: "not-a-provider").isEmpty)
    }
}
