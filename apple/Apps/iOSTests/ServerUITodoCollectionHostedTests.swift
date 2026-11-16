import XCTest
import HassCore
import HassDemoHouse
@testable import HassUI

/// The pages that moved from house configuration to the publication: a todo collection the document defines, one it only
/// names, its resident-dependent title, and the household controls the document places. Nothing here is family specific, so the
/// tests run unchanged on iPhone, iPhone Duo (folded and unfolded) and iPad.
@MainActor
final class ServerUITodoCollectionHostedTests: XCTestCase {
    private func providers(_ publication: ServerUICompositionPublication, user: String, entities: EntityStore = EntityStore(),
                           service: ChoresFixtureService? = nil) throws -> (UKServerUIRecordProviders, ChoresFixtureService) {
        let service = service ?? ChoresFixtureService(store: entities, lists: ChoresFixtures.lists())
        let definition = UKServerUIRecordProviders.Definition(people: DemoHouse.config.chores.people, document: publication.document)
        let result = try UKServerUIRecordProviders(definition: definition, authenticatedUserID: user, service: service,
            recipes: FixtureRecipeService(delay: .zero), todos: TodoStore(service: service), store: entities,
            accessToken: { "synthetic" }, isCurrentSession: { true })
        return (result, service)
    }

    private func nodeJSON(provider: String) -> JSONValue {
        .object(["id": .string("node-" + provider), "type": "collection", "title": "Page", "layout": .object(["span": .number(1)]),
                 "props": .object(["providerId": .string(provider), "template": "todo", "loadingText": "Loading", "emptyText": "Empty"])])
    }

    /// A publication whose first page shows a todo collection node for `provider`, with `pages` defined as sources.
    private func publication(showing provider: String, defining pages: [ChoresConfig.Page]) throws -> ServerUICompositionPublication {
        var json = try ServerUITodoPublicationFixture.adding(pages, to: ServerUIRendererFixture.json())
        let components = try XCTUnwrap(json["document"]?["pages"]?.array?.first?["components"]?.array)
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(components + [nodeJSON(provider: provider)]))
        var capabilities = Set(try XCTUnwrap(json["capabilities"]?.array).compactMap(\.string))
        capabilities.insert("sh.collection@1")
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
        return try ServerUIRendererFixture.publication(json)
    }

    func testACollectionTheDocumentNamesButDoesNotDefineIsInertEvenWhenTheHouseDefinesThePage() async throws {
        let source = HouseConfigSource()
        source.set(DemoHouse.config)
        try await HouseConfigSource.$scoped.withValue(source) {
            let person = try XCTUnwrap(DemoHouse.config.chores.people.first)
            let page = try XCTUnwrap(DemoHouse.config.chores.pages.first)
            let (registry, service) = try providers(publication(showing: "records-" + page.id, defining: []), user: person.haUserId)
            let collection = try XCTUnwrap(registry.records.collections["records-" + page.id])
            XCTAssertTrue(collection is UKServerUIAbsentTodoCollection, "House layout must not fill in a page the publication lacks.")
            try await collection.load()
            XCTAssertTrue(collection.records.isEmpty)
            XCTAssertNil(collection.error)
            XCTAssertEqual(collection.navigationTitle, "")
            XCTAssertEqual(service.lastCall, "none", "An absent collection must not call a service.")
        }
    }

    func testADefinedCollectionComesFromThePublicationNotFromTheHouse() async throws {
        let source = HouseConfigSource()
        source.set(DemoHouse.config)
        try await HouseConfigSource.$scoped.withValue(source) {
            let person = try XCTUnwrap(DemoHouse.config.chores.people.first)
            var page = try XCTUnwrap(DemoHouse.config.chores.pages.first(where: { $0.lists.count > 1 }))
            page.title = "Published Title"
            page.lists = [page.lists[0]]
            let (registry, _) = try providers(publication(showing: "records-" + page.id, defining: [page]), user: person.haUserId)
            let collection = try XCTUnwrap(registry.records.collections["records-" + page.id] as? UKServerUIChoresCollection)
            XCTAssertEqual(collection.configuration.title, "Published Title")
            XCTAssertEqual(collection.configuration.lists.map(\.entityId), [page.lists[0].entityId],
                           "The page's lists are the document's, not the house's.")
        }
    }

    func testTheNavigationTitleFollowsTheViewerWhenThePageIsAResidentsOwn() throws {
        let source = HouseConfigSource()
        source.set(DemoHouse.config)
        try HouseConfigSource.$scoped.withValue(source) {
            let people = DemoHouse.config.chores.people
            XCTAssertGreaterThanOrEqual(people.count, 2)
            var page = try XCTUnwrap(DemoHouse.config.chores.pages.first)
            page.resident = Resident(key: people[0].key)
            let publication = try publication(showing: "records-" + page.id, defining: [page])
            let own = try providers(publication, user: people[0].haUserId).0
            let other = try providers(publication, user: people[1].haUserId).0
            XCTAssertEqual(try XCTUnwrap(own.records.collections["records-" + page.id]).navigationTitle, "Your " + page.title)
            XCTAssertEqual(try XCTUnwrap(other.records.collections["records-" + page.id]).navigationTitle, page.title)
        }
    }

    func testHouseholdProviderOffersExactlyTheControlsTheDocumentPlaces() throws {
        var json = try ServerUIRendererFixture.json()
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities",
            to: .array((ServerUICompositionPublication.firstSliceCapabilities + ["sh.settings-controls@1"]).sorted().map(JSONValue.string)))
        let sources = try XCTUnwrap(json["document"]?["dataSources"]?.array)
        json = try ServerUIRendererFixture.changing(json, path: "/document/dataSources", to: .array(sources + [
            .object(["id": "settings", "kind": "model", "model": "settings-provider@1",
                     "inputs": .object(["providerId": "household", "domain": "household"])])]))
        func control(_ id: String, kind: String, item: String) -> JSONValue {
            .object(["id": .string(id), "title": .string(id), "type": "settings-control", "layout": .object(["span": .number(1)]),
                     "icon": .object(["type": "sf-symbol", "name": "lightbulb", "rendering": "canonical", "unavailable": "reject"]),
                     "props": .object(["sourceId": "settings", "kind": .string(kind), "item": .string(item), "subtitle": ""])])
        }
        let placed = [control("lamp", kind: "household-toggle", item: "switch.demo_lamp"),
                      control("car", kind: "household-read-only", item: "sensor.demo_car")]
        let components = try XCTUnwrap(json["document"]?["pages"]?.array?.first?["components"]?.array)
        let withControls = try ServerUIRendererFixture.publication(
            ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(components + placed)))
        let controls = withControls.document.settingsControls(overProvider: "household")
        XCTAssertEqual(controls.map(\.item), ["switch.demo_lamp", "sensor.demo_car"])
        let bare = try ServerUIRendererFixture.publication(json)
        let none = try UKServerUIHouseholdProviders.household(id: "household", configuration: DemoHouse.config, document: bare.document,
            store: EntityStore(), caller: LoggingResponder(), current: { true })
        XCTAssertTrue(controls.allSatisfy { !none.accepts($0) }, "With no controls placed, the house offers nothing.")
        let built = try UKServerUIHouseholdProviders.household(id: "household", configuration: DemoHouse.config, document: withControls.document,
            store: EntityStore(), caller: LoggingResponder(), current: { true })
        XCTAssertTrue(controls.allSatisfy(built.accepts), "Every control the document places over the provider is offered.")
    }
}
