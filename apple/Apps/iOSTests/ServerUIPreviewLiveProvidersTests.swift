import CryptoKit
import HassCore
import HassDemoHouse
import UIKit
import XCTest
@testable import HassUI

// MARK: - Read-only live providers

/// The preview's live mode must supply the providers the production route supplies, over its read-only connection, and refuse writes.
///
/// Synthetic ids only: the house document is the demo house, the connection never opens a socket. The hosted checks run at the
/// iPhone, Duo and iPad widths.
@MainActor
final class ServerUIPreviewLiveProvidersTests: XCTestCase {
    private var directory: URL!
    private var lives: [UKServerUIPreviewLiveData] = []
    private var providers: [UKServerUIPreviewLiveProviders] = []

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appendingPathComponent("ServerUIPreviewLiveProvidersTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        providers.forEach { $0.stop() }
        lives.forEach { $0.lifecycle.stop() }
        providers = []
        lives = []
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try FileManager.default.removeItem(at: directory)
    }

    // MARK: Fixtures

    private struct SilentTransport: HouseConfigTransport {
        func subscribe(_ handler: @escaping @Sendable (Result<Data, Error>) -> Void) -> @Sendable () -> Void { {} }
    }

    private var house: HouseConfig { DemoHouse.config }
    private var viewer: HouseConfig.Person { house.chores.people[0] }

    private func make(document: Bool = true, signedIn: Bool = true) throws -> (UKServerUIPreviewLiveData, UKServerUIPreviewLiveProviders) {
        let live = try UKServerUIPreviewLiveData(configuration: .init(server: "https://home.example.com", accountID: "demo"),
                                                 credential: "test-only-token", directory: directory, store: EntityStore())
        let cache = HouseConfigCache(fileURL: directory.appendingPathComponent("house-\(UUID().uuidString).json"))
        if document { try cache.save(house, hash: "synthetic", server: live.connection.server) }
        let store = HouseConfigStore(server: live.connection.server, transport: SilentTransport(), cache: cache,
                                     source: HouseConfigSource(), loadsCacheSynchronously: true)
        store.start()
        let providers = try UKServerUIPreviewLiveProviders(live: live, houseConfigCache: cache,
            defaultsName: "ServerUIPreviewLiveProvidersTests-" + UUID().uuidString, houseConfig: store)
        if signedIn { providers.user = HassUser(id: viewer.haUserId, name: viewer.name, isOwner: false, isAdmin: false) }
        lives.append(live)
        self.providers.append(providers)
        return (live, providers)
    }

    /// The placeholder fixture (weather, camera, an away provider and one vacation check) with the demo house's own checklist
    /// item, a to-do collection and every other settings provider kind.
    private func publication() throws -> ServerUICompositionPublication {
        let check = try XCTUnwrap(house.vacation.checklist.first).entityId
        var json = try ServerUIPreviewPlaceholderTests.json(checkItem: check)
        json = try ServerUITodoPublicationFixture.adding(house.chores.pages, to: json)
        let component: JSONValue = .object([
            "id": "account-records", "title": "Groceries", "type": "collection", "layout": .object(["span": .number(1)]),
            "props": .object(["providerId": "records-groceries", "template": "todo", "loadingText": "Loading", "emptyText": "Empty"]),
        ])
        let components = try XCTUnwrap(json["document"]?["pages"]?.array?.first?["components"]?.array)
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(components + [component]))
        let sources: [JSONValue] = ["household", "profile", "preferences", "performance", "feedback-bug", "feedback-feature"].map { id in
            .object(["id": .string("settings-" + id), "kind": "model", "model": "settings-provider@1",
                     "inputs": .object(["providerId": .string(id), "domain": .string(id.hasPrefix("feedback-") ? "feedback" : id)])])
        }
        json = try ServerUIRendererFixture.changing(json, path: "/document/dataSources",
            to: .array(try XCTUnwrap(json["document"]?["dataSources"]?.array) + sources))
        let capabilities = try XCTUnwrap(json["capabilities"]?.array).compactMap(\.string) + ["sh.collection@1"]
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities",
            to: .array(Set(capabilities).sorted().map(JSONValue.string)))
        return try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
    }

    private func stagedAssets(_ publication: ServerUICompositionPublication) async throws -> ServerUIStagedAssets {
        let server = HassServer(baseURL: URL(string: "https://preview.invalid")!)
        let partition = try ServerUIPublicationPartition(server: server)
        let stager = try ServerUIAssetStager(partition: partition, partitionDirectory: partition.storageDirectory(in: directory),
            transport: ServerUIAssetTransport(server: server, tokenProvider: { throw URLError(.notConnectedToInternet) }))
        return try await stager.stage(publication, documentDigest: publication.documentSha256)
    }

    // MARK: Logic

    func testSupplyBuildsEveryProviderKindTheProductionRouteBuilds() throws {
        let (live, providers) = try make()
        let publication = try publication()
        let backdrop = try ServerUIRendererFixture.backdrop()
        let supply = try providers.supply(for: publication, blur: backdrop.blur)

        XCTAssertEqual(Set(supply.settings.keys), ["household", "away", "profile", "preferences", "performance",
                                                    "feedback-bug", "feedback-feature"])
        XCTAssertTrue(supply.settings["household"] is UKServerUIHouseholdProvider)
        XCTAssertTrue(supply.settings["away"] is UKServerUIAwayProvider)
        XCTAssertTrue(supply.settings["profile"] is UKServerUIProfileProvider)
        XCTAssertTrue(supply.settings["preferences"] is UKServerUIPreferencesProvider)
        XCTAssertTrue(supply.settings["performance"] is UKServerUIPerformanceProvider)
        XCTAssertTrue(supply.settings["feedback-bug"] is UKServerUIFeedbackProvider)
        XCTAssertTrue(supply.settings["feedback-feature"] is UKServerUIFeedbackProvider)
        let away = try XCTUnwrap(supply.settings["away"] as? UKServerUIAwayProvider)
        XCTAssertEqual(away.solo.viewer?.key, viewer.key, "The away provider is scoped to the signed-in person")

        XCTAssertTrue(supply.records.collections["records-groceries"] is UKServerUIChoresCollection, "To-do")
        XCTAssertTrue(supply.records.collections.keys.contains { $0.hasPrefix("records-inventory-") }, "Inventory")
        XCTAssertNotNil(supply.records.collections["records-recipes"], "Recipes")
        XCTAssertTrue(supply.collections.keys.contains { $0.hasPrefix("performance-") }, "Performance rows")
        XCTAssertEqual(Set(supply.remotes.keys), Set(house.media.remotes.map(\.id)), "Media remotes")
        let room = house.bedroom
        XCTAssertEqual(Set(supply.bedrooms.keys), Set([room.wakeLight.id] + room.beds.map(\.id)), "Bedroom")
        XCTAssertFalse(supply.canEditBedroom)
        XCTAssertEqual(supply.roomResidentId(), viewer.key)
        guard case .ready(let name, let server, _) = supply.account.account else { return XCTFail("Account") }
        XCTAssertEqual(name, viewer.name)
        XCTAssertEqual(server, "home.example.com")
        XCTAssertEqual(supply.shellHeader.state().profileName, viewer.name)
        XCTAssertEqual(live.caller.blockedCommands, 0, "Building the providers writes nothing")
        XCTAssertEqual(live.connection.status, .disconnected)

        let again = try providers.supply(for: publication, blur: backdrop.blur)
        XCTAssertTrue(again.settings["away"] === supply.settings["away"], "Providers are retained across a second supply")
        XCTAssertTrue((again.records.collections["records-groceries"] as? UKServerUIChoresCollection)
                      === (supply.records.collections["records-groceries"] as? UKServerUIChoresCollection))
    }

    func testARowFlowGetsItsCollectionAndItsServiceCallIsRefused() async throws {
        let (live, providers) = try make()
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: apple.appendingPathComponent(
            "Tests/HassCoreTests/ContractCorpus/accept/pipeline-overdue-chores.json")))
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/2/components", to: .array([]))
        let capabilities = try XCTUnwrap(json["capabilities"]?.array?.compactMap(\.string)).filter { $0 != "sh.collection@1" }
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
        let publication = try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
        let supply = try providers.supply(for: publication, blur: ServerUIRendererFixture.backdrop().blur)
        XCTAssertNotNil(supply.collections["overdue"], "The row flow's collection is supplied")
        do {
            _ = try await providers.services.rejectFlowCall()
            XCTFail("A flow's service call was accepted")
        } catch { XCTAssertEqual(error as? UKServerUIPreviewLiveData.Failure, .commandsDisabled) }
        XCTAssertEqual(live.caller.blockedCommands, 1)
    }

    func testWritesAreStillRefusedThroughEveryServicePath() async throws {
        let (live, providers) = try make()
        let services = providers.services
        var refused = 0
        func expectRefusal(_ name: String, _ work: () async throws -> Void) async {
            do { try await work(); XCTFail("\(name) was accepted") }
            catch { XCTAssertEqual(error as? UKServerUIPreviewLiveData.Failure, .commandsDisabled, name); refused += 1 }
            XCTAssertEqual(live.caller.blockedCommands, refused, name)
        }
        await expectRefusal("service") { try await services.callService("light", "turn_on", data: ["entity_id": "light.x"]) }
        await expectRefusal("service with response") { _ = try await services.callServiceWithResponse("script", "run", data: [:]) }
        await expectRefusal("evershelf") { _ = try await services.callServiceForResponse("evershelf", "add", data: [:]) }
        await expectRefusal("schedule update") { _ = try await services.updateSchedule([:]) }
        await expectRefusal("upload bearer") { _ = try await services.accessToken() }
        await expectRefusal("flow call") { _ = try await services.rejectFlowCall() }
        let supplied = try providers.supply(for: publication(), blur: ServerUIRendererFixture.backdrop().blur)
        XCTAssertTrue(supplied.responder === services && supplied.schedules === services,
                      "The renderer's responder and schedule store are the refusing ones")
        XCTAssertEqual(live.caller.blockedCommands, refused, "Preparing providers adds no write")
        XCTAssertEqual(live.connection.status, .disconnected, "No refused path opens a socket")
    }

    func testAMissingHouseDocumentOrPersonWaitsInsteadOfBuildingGuesses() throws {
        let blur = try ServerUIRendererFixture.backdrop().blur
        let publication = try publication()
        let (_, noDocument) = try make(document: false)
        XCTAssertThrowsError(try noDocument.supply(for: publication, blur: blur)) {
            XCTAssertEqual(($0 as? UKServerUIRendererError)?.code, .inputsPending)
        }
        let (_, noPerson) = try make(signedIn: false)
        XCTAssertThrowsError(try noPerson.supply(for: publication, blur: blur)) {
            XCTAssertEqual(($0 as? UKServerUIRendererError)?.code, .inputsPending)
        }
        guard case .loading = noPerson.account else { return XCTFail("The account loads until the user answers") }
    }

    func testAwaitInputsReturnsAtTheDeadlineWhenNobodyAnswers() async throws {
        let (live, providers) = try make(signedIn: false)
        let started = ContinuousClock.now
        await providers.awaitInputs(timeout: .milliseconds(200))
        XCTAssertLessThan(started.duration(to: .now), .seconds(5))
        XCTAssertNil(providers.user)
        XCTAssertEqual(live.caller.blockedCommands, 0)
    }

    // MARK: Hosted UX and accessibility

    func testCameraWeatherAndVacationCheckAreAcceptedAtIPhoneDuoAndIPadWidths() async throws {
        let publication = try publication()
        let assets = try await stagedAssets(publication)
        XCTAssertThrowsError(try UKServerUIRenderer(publication: publication, context: UKContext(store: EntityStore()),
            backdrop: ServerUIRendererFixture.backdrop()), "With no providers the layout is refused whole, as it was")
        for (family, size) in [("iPhone", CGSize(width: 390, height: 844)), ("Duo", CGSize(width: 466, height: 678)),
                               ("iPad", CGSize(width: 820, height: 1180))] {
            let (live, providers) = try make()
            let backdrop = try ServerUIRendererFixture.backdrop()
            let supply = try providers.supply(for: publication, blur: backdrop.blur)
            let prepared = try UKServerUIPreview.Prepared(publication: publication, context: live.context, assets: assets,
                backdrop: backdrop, renderDirectory: directory,
                weatherReader: live.weatherReader(for: publication.document),
                cameraReader: live.cameraReader(for: publication.document, pool: CameraStreamPool(modes: [], observesApp: false)),
                live: supply)
            let renderer = prepared.renderer
            let window = HostedPage.show(renderer, size: HostedPage.inScene(size))
            defer { window.isHidden = true }
            HostedPage.layoutTracked()
            let page = try XCTUnwrap(renderer.stacks[.initial]?.viewControllers.first as? UKServerUIPage, family)

            XCTAssertNotNil(renderer.bindings.cameras["demo-camera-source"], "\(family): camera source")
            XCTAssertNotNil(page.nodes["demo-camera-tile"]?.view, "\(family): camera tile")
            XCTAssertNotNil(renderer.bindings.weather["fixture-weather"], "\(family): weather source")
            let row = try XCTUnwrap(page.nodes["fixture-vacation-check"]?.view, "\(family): vacation check")
            let check = try XCTUnwrap(HostedPage.descendants(of: row).compactMap { $0 as? UKVacationChecklistRow }.first
                                      ?? row as? UKVacationChecklistRow, family)
            let toggle = try XCTUnwrap(check.accessibilityElements?.first as? UIView, family)
            XCTAssertEqual(toggle.accessibilityLabel, "Placeholder task", family)
            XCTAssertNotNil(toggle.accessibilityValue, family)
            XCTAssertTrue(check.bounds.width > 0 && check.bounds.width <= size.width, family)
            XCTAssertEqual(live.caller.blockedCommands, 0, "\(family): drawing writes nothing")
        }
    }

    func testFixturesModeKeepsTheDemoHouseProviders() async throws {
        let source = HouseConfigSource.active
        let original = source.current
        GalleryHouse.install(into: source)
        defer { source.set(original) }
        let publication = try publication()
        let assets = try await stagedAssets(publication)
        let store = EntityStore()
        let fixtures = try UKServerUIPreviewFixtures(
            configuration: .init(viewerUserID: viewer.haUserId, administrator: false), store: store)
        let prepared = try UKServerUIPreview.Prepared(publication: publication, context: fixtures.context, assets: assets,
            backdrop: ServerUIRendererFixture.backdrop(), renderDirectory: directory,
            weatherReader: fixtures.weatherReader(for: publication.document),
            cameraReader: UKServerUIPreviewPlaceholders.cameraReader(for: publication.document), fixtures: fixtures)
        XCTAssertEqual(Set(fixtures.settings.keys), ["household", "away", "profile", "preferences", "performance",
                                                    "feedback-bug", "feedback-feature"])
        XCTAssertTrue(fixtures.records.collections["records-groceries"] is UKServerUIChoresCollection)
        XCTAssertNil(fixtures.context.connection)
        XCTAssertNotNil(prepared.renderer.view, "The fixtures renderer is built without a live supply")
    }
}
