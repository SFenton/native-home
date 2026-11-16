import CryptoKit
import FentonActivityModel
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
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

    private var defaultsName = ""
    /// The mock HAKit connection under the last connection `make` built: it records every request and subscription sent.
    private var lastMock: HAMockConnection!

    private func make(document: Bool = true, signedIn: Bool = true, retain: Bool = true, source: HouseConfigSource? = nil,
                      start: Bool = true) throws -> (UKServerUIPreviewLiveData, UKServerUIPreviewLiveProviders, HouseConfigStore) {
        let mock = HAMockConnection()
        lastMock = mock
        let server = HassServer(baseURL: URL(string: "https://home.example.com")!)
        let connection = HassConnection(server: server, store: EntityStore(),
            snapshotCache: EntitySnapshotCache(fileURL: directory.appendingPathComponent("entities-\(UUID().uuidString).json")),
            connection: mock)
        let live = UKServerUIPreviewLiveData(connection: connection)
        let cache = HouseConfigCache(fileURL: directory.appendingPathComponent("house-\(UUID().uuidString).json"))
        if document { try cache.save(house, hash: "synthetic", server: live.connection.server) }
        let source = source ?? HouseConfigSource()
        let store = HouseConfigStore(server: live.connection.server, transport: SilentTransport(), cache: cache,
                                     source: source, loadsCacheSynchronously: true)
        if start { store.start() }
        defaultsName = "ServerUIPreviewLiveProvidersTests-" + UUID().uuidString
        let providers = try UKServerUIPreviewLiveProviders(live: live, houseConfigCache: cache, defaultsName: defaultsName,
                                                           source: source, houseConfig: store)
        if signedIn { providers.user = HassUser(id: viewer.haUserId, name: viewer.name, isOwner: false, isAdmin: false) }
        lives.append(live)
        if retain { self.providers.append(providers) }
        return (live, providers, store)
    }

    // MARK: Catching writes on the mock

    /// Whether `request` is exactly the weather panel's forecast read: `call_service` of `weather.get_forecasts` with
    /// `return_response: true`, for one entity under `weather.` and one forecast kind. The weather reader builds nothing else
    /// (`ServerUIWeatherReader` fixes the domain and service, and only approves the document's own weather entities).
    @MainActor private static func isApprovedForecastRead(_ request: HARequest) -> Bool {
        guard request.type.command == "call_service", request.data["domain"] as? String == "weather",
              request.data["service"] as? String == "get_forecasts", request.data["return_response"] as? Bool == true,
              let data = request.data["service_data"] as? [String: Any], Set(data.keys) == ["entity_id", "type"],
              let entity = data["entity_id"] as? String, entity.hasPrefix("weather."),
              let kind = data["type"] as? String, ["hourly", "daily", "twice_daily"].contains(kind) else { return false }
        return true
    }

    /// What the mock holds that would change something: a service call, a script, a schedule change, a to-do change or any REST
    /// call. Reads (the current user, a to-do list, the schedule list, the state feed) are not writes. The one service call let
    /// through is ``isApprovedForecastRead(_:)``; any other `call_service` is a write and is named with its domain and service.
    @MainActor private static func writes(on mock: HAMockConnection) -> [String] {
        let writeCommands = ["execute_script", "schedule/update", "schedule/create", "schedule/delete", "todo/item/add",
                             "todo/item/update", "todo/item/remove", "fire_event", "input_boolean/toggle"]
        let held = mock.pendingRequests.map(\.request) + mock.pendingSubscriptions.map(\.request)
        return held.compactMap { request in
            if case .rest = request.type { return "REST " + request.type.command }
            if request.type.command == "call_service" {
                if isApprovedForecastRead(request) { return nil }
                let domain = request.data["domain"] as? String ?? "?", service = request.data["service"] as? String ?? "?"
                return "call_service \(domain).\(service) return_response=\(String(describing: request.data["return_response"]))"
            }
            return writeCommands.contains(request.type.command) ? request.type.command : nil
        }
    }

    /// Brings the mock's connection up, which is what would release anything a disconnected connection had queued, then asserts no
    /// write message is among what it holds.
    @MainActor private static func assertNoWrite(on mock: HAMockConnection, _ what: String, _ family: String) async {
        mock.setState(.ready(version: "1.0-mock"), waitForQueue: false)
        await FeatureHost.settleAsync(0.2)
        let commands = (mock.pendingRequests.map(\.request.type) + mock.pendingSubscriptions.map(\.request.type)).map(\.command)
        XCTAssertEqual(writes(on: mock), [], "\(family): \(what) reached the connection; it holds \(commands)")
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
        let (live, providers, _) = try make()
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
        let (live, providers, _) = try make()
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

    func testAMissingHouseDocumentOrPersonWaitsInsteadOfBuildingGuesses() throws {
        let blur = try ServerUIRendererFixture.backdrop().blur
        let publication = try publication()
        let (_, noDocument, _) = try make(document: false)
        XCTAssertThrowsError(try noDocument.supply(for: publication, blur: blur)) {
            XCTAssertEqual(($0 as? UKServerUIRendererError)?.code, .inputsPending)
        }
        let (_, noPerson, _) = try make(signedIn: false)
        XCTAssertThrowsError(try noPerson.supply(for: publication, blur: blur)) {
            XCTAssertEqual(($0 as? UKServerUIRendererError)?.code, .inputsPending)
        }
        guard case .loading = noPerson.account else { return XCTFail("The account loads until the user answers") }
    }

    func testAwaitInputsReturnsAtTheDeadlineWhenNobodyAnswers() async throws {
        let (live, providers, _) = try make(signedIn: false)
        let started = ContinuousClock.now
        await providers.awaitInputs(timeout: .milliseconds(200))
        XCTAssertLessThan(started.duration(to: .now), .seconds(5))
        XCTAssertNil(providers.user)
        XCTAssertEqual(live.caller.blockedCommands, 0)
    }

    // MARK: Lifetime

    func testStopPutsTheSharedHouseDocumentBackAndAFixturesPreviewDoesNotSeeTheLiveOne() throws {
        let shared = HouseConfigSource.shared
        let original = shared.current
        defer { shared.set(original) }
        shared.set(nil)
        let (_, providers, store) = try make(source: shared, start: false)
        store.start()
        XCTAssertEqual(HouseConfigSource.active.current, house, "While the live preview runs it publishes the house document")
        providers.stop()
        XCTAssertNil(HouseConfigSource.active.current, "A fixtures preview that follows it must not see the live document")

        var earlier = house
        earlier.vacation.checklist = []
        shared.set(earlier)
        let (_, again, againStore) = try make(source: shared, start: false)
        againStore.start()
        XCTAssertEqual(shared.current, house)
        again.stop()
        XCTAssertEqual(shared.current, earlier, "What the source held before is put back")
    }

    func testACancelledWaitReturnsAtOnceAndNothingKeepsTheProvidersAliveAfterStop() async throws {
        weak var weakProviders: UKServerUIPreviewLiveProviders?
        let waiting: Task<Void, Never>
        do {
            let (_, providers, _) = try make(document: false, signedIn: false, retain: false)
            weakProviders = providers
            waiting = Task { await providers.awaitInputs(timeout: .seconds(60)) }
            await FeatureHost.settleAsync(0.1)
            waiting.cancel()
            providers.stop()
        }
        let started = ContinuousClock.now
        await waiting.value
        XCTAssertLessThan(started.duration(to: .now), .seconds(5), "Cancelling ends the 20 s wait; it does not run it out")
        await FeatureHost.settleAsync(0.2)
        XCTAssertNil(weakProviders, "No input read keeps the providers alive after stop")

        let (_, late, _) = try make(document: false, signedIn: false)
        let task = Task { await late.awaitInputs(timeout: .seconds(60)) }
        task.cancel()
        let begun = ContinuousClock.now
        await task.value
        XCTAssertLessThan(begun.duration(to: .now), .seconds(5), "A task cancelled before it starts does not wait")
    }

    // MARK: Writes through the built providers

    /// Each control is placed in the document, drawn by the renderer from the preview's own providers and driven the way a tap does.
    private func writingPublication() throws -> ServerUICompositionPublication {
        var json = try ServerUIPreviewPlaceholderTests.json(checkItem: XCTUnwrap(house.vacation.checklist.first).entityId)
        json = try ServerUITodoPublicationFixture.adding(house.chores.pages, to: json)
        let icon: JSONValue = .object(["type": "sf-symbol", "name": "gearshape", "rendering": "canonical", "unavailable": "reject"])
        func settings(_ id: String, domain: String) -> JSONValue {
            .object(["id": .string("settings-" + id), "kind": "model", "model": "settings-provider@1",
                     "inputs": .object(["providerId": .string(id), "domain": .string(domain)])])
        }
        func control(_ id: String, source: String, kind: String, item: String) -> JSONValue {
            .object(["id": .string(id), "title": .string(id), "type": "settings-control", "layout": .object(["span": .number(1)]),
                     "icon": icon, "props": .object(["sourceId": .string(source), "kind": .string(kind),
                                                     "item": .string(item), "subtitle": ""])])
        }
        let sources = [settings("household", domain: "household"), settings("profile", domain: "profile"),
                       settings("preferences", domain: "preferences"),
                       settings("feedback-bug", domain: "feedback")]
        json = try ServerUIRendererFixture.changing(json, path: "/document/dataSources",
            to: .array(try XCTUnwrap(json["document"]?["dataSources"]?.array) + sources))
        let placed = [control("w-toggle", source: "settings-household", kind: "household-toggle", item: "switch.synthetic_toggle"),
                      control("w-signout", source: "settings-profile", kind: "sign-out", item: ""),
                      control("w-haweb", source: "settings-profile", kind: "ha-web", item: "profile"),
                      control("w-icon", source: "settings-preferences", kind: "app-icon-choice", item: AppIconChoice.midnightGold.rawValue)]
        // The records providers are built when a page shows a collection, so the admin to-do page's collection is placed too.
        let adminPage = try XCTUnwrap(house.chores.pages.first { $0.editsAdminTodo })
        let collection: JSONValue = .object([
            "id": "w-admin-records", "title": "To-Do", "type": "collection", "layout": .object(["span": .number(1)]),
            "props": .object(["providerId": .string("records-" + adminPage.id), "template": "todo", "loadingText": "Loading", "emptyText": "Empty"]),
        ])
        let components = try XCTUnwrap(json["document"]?["pages"]?.array?.first?["components"]?.array)
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(components + placed + [collection]))
        let capabilities = try XCTUnwrap(json["capabilities"]?.array).compactMap(\.string) + ["sh.collection@1"]
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(Set(capabilities).sorted().map(JSONValue.string)))
        return try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
    }

    /// One preview drawn at one family's size from the preview's own providers, and the helpers that drive it.
    @MainActor private struct Rig {
        let family: String
        let live: UKServerUIPreviewLiveData
        let mock: HAMockConnection
        let providers: UKServerUIPreviewLiveProviders
        let supply: UKServerUIPreviewLiveProviders.Supply
        let renderer: UKServerUIRenderer
        let page: UKServerUIPage
        let defaultsName: String

        /// Taps the row or tile the document placed under `id`, the way a touch does.
        func tap(_ id: String) throws {
            let node = try XCTUnwrap(page.nodes[id]?.view, "\(family): \(id)")
            func control(in view: UIView) -> UIControl? {
                if view is UKRowButton || view is UKGlassTileView, let found = view as? UIControl { return found }
                for sub in view.subviews { if let found = control(in: sub) { return found } }
                return nil
            }
            let found = try XCTUnwrap(control(in: node), "\(family): \(id) control")
            if let row = found as? UKRowButton { try XCTUnwrap(row.onTap, "\(family): \(id) tap")() }
            else { found.sendActions(for: .touchUpInside) }
        }

        /// Answers whatever alert is up, by the action the alert itself offers (its cancel action, else its last), until none is.
        func dismissAlerts() async {
            for _ in 0..<4 {
                _ = await FeatureHost.settleAsync(until: { FeatureHost.alert(on: renderer) != nil }, timeout: 1.5)
                guard let alert = FeatureHost.alert(on: renderer) else { return }
                let action = alert.actions.first { $0.style == .cancel } ?? alert.actions.last
                _ = FeatureHost.answer(alert, action?.title)
                await FeatureHost.settleAsync(0.1)
            }
        }

        /// Answers a confirmation by its own affirmative (non-cancel) action.
        func confirmAlert() async throws {
            let shown = await FeatureHost.settleAsync(until: { FeatureHost.alert(on: renderer) != nil })
            let alert = try XCTUnwrap(shown ? FeatureHost.alert(on: renderer) : nil, "\(family): confirmation")
            let action = try XCTUnwrap(alert.actions.first { $0.style != .cancel }, family)
            _ = FeatureHost.answer(alert, action.title)
        }

        /// That `count` writes were refused and counted, and that none of them reached the mock connection once it came up.
        func assertRefused(_ count: Int, _ what: String) async {
            let reached = await FeatureHost.settleAsync(until: { live.caller.blockedCommands >= count })
            XCTAssertTrue(reached, "\(family): \(what) was not counted (\(live.caller.blockedCommands))")
            XCTAssertEqual(live.caller.blockedCommands, count, "\(family): \(what)")
            await assertNoWrite(what)
        }

        func assertNoWrite(_ what: String) async {
            await ServerUIPreviewLiveProvidersTests.assertNoWrite(on: mock, what, family)
        }
    }

    /// The wake light and household away status entities under the document's own ids, each reporting `command_available`,
    /// so a command passes its controller's guard and reaches the caller the preview supplied.
    private func commandableSnapshots(adminLists: [ChoresConfig.TodoList]) -> [EntityState] {
        let wake = BedroomFixtures.wakeLight(.waking, now: Date())
        return adminLists.map { EntityState(entityId: $0.entityId, state: "1") } + [
            EntityState(entityId: house.bedroom.wakeLight.statusEntityId, state: wake.state, attributes: wake.attributes),
            EntityState(entityId: house.bedroom.householdAwayEntityId, state: "idle", attributes: VacationFixtures.idleAttributes)]
    }

    /// The admin to-do page the publication itself defines, so the fixture's viewer and list states satisfy that page's own rules.
    private func publishedAdminPage(_ publication: ServerUICompositionPublication) throws -> ChoresConfig.Page {
        let definition = UKServerUIRecordProviders.Definition(people: house.chores.people, document: publication.document)
        return try XCTUnwrap(definition.collections.map { $0.page.page(id: $0.id) }.first { $0.editsAdminTodo }, "admin to-do page")
    }

    /// Draws the writes fixture at each family's size and runs `body` on it, as a person who sees the admin to-do.
    private func drive(_ body: @MainActor (Rig) async throws -> Void) async throws {
        let publication = try writingPublication()
        let assets = try await stagedAssets(publication)
        let adminPage = try publishedAdminPage(publication)
        let restricted = adminPage.lists.map(\.userIds).filter { !$0.isEmpty }
        let person = try XCTUnwrap(house.chores.people.first { person in
            person.seesAdminTodo && restricted.allSatisfy { $0.contains(person.haUserId) }
        } ?? house.chores.people.first { $0.seesAdminTodo }, "a viewer who sees the admin to-do")
        let item = try XCTUnwrap(house.vacation.checklist.first)
        for (family, size) in [("iPhone", CGSize(width: 390, height: 844)), ("Duo", CGSize(width: 466, height: 678)),
                               ("iPad", CGSize(width: 820, height: 1180))] {
            let (live, providers, _) = try make()
            let mock = lastMock!
            providers.user = HassUser(id: person.haUserId, name: person.name, isOwner: false, isAdmin: true)
            live.context.store.apply([EntityState(entityId: "switch.synthetic_toggle", state: "off"),
                                      EntityState(entityId: item.entityId, state: "off")] + BedroomFixtures.states(.waking) + self.commandableSnapshots(adminLists: adminPage.lists))
            let backdrop = try ServerUIRendererFixture.backdrop()
            let supply = try providers.supply(for: publication, blur: backdrop.blur)
            let prepared = try UKServerUIPreview.Prepared(publication: publication, context: live.context, assets: assets,
                backdrop: backdrop, renderDirectory: directory, weatherReader: live.weatherReader(for: publication.document),
                cameraReader: live.cameraReader(for: publication.document, pool: CameraStreamPool(modes: [], observesApp: false)),
                live: supply)
            let renderer = prepared.renderer
            let window = HostedPage.show(renderer, size: HostedPage.inScene(size))
            defer { window.isHidden = true }
            HostedPage.layoutTracked()
            let page = try XCTUnwrap(renderer.stacks[.initial]?.viewControllers.first as? UKServerUIPage, family)
            try await body(Rig(family: family, live: live, mock: mock, providers: providers, supply: supply, renderer: renderer,
                               page: page, defaultsName: defaultsName))
        }
    }

    func testTheMockCatchesAWriteSentStraightToTheConnection() async throws {
        let (live, _, _) = try make()
        let mock = lastMock!
        Task { try? await live.connection.callService("light", "turn_on", data: ["entity_id": "light.synthetic"]) }
        let sent = await FeatureHost.settleAsync(until: { !ServerUIPreviewLiveProvidersTests.writes(on: mock).isEmpty })
        XCTAssertTrue(sent, "The detector must see a write that goes to the connection, or the other tests prove nothing")
        XCTAssertEqual(ServerUIPreviewLiveProvidersTests.writes(on: mock).count, 1)
        XCTAssertTrue(ServerUIPreviewLiveProvidersTests.writes(on: mock)[0].hasPrefix("call_service light.turn_on"))
    }

    func testTheOnlyServiceCallsOnTheConnectionAreTheDocumentsApprovedForecastReads() async throws {
        try await drive { rig in
            rig.mock.setState(.ready(version: "1.0-mock"), waitForQueue: false)
            await FeatureHost.settleAsync(0.3)
            let calls = rig.mock.pendingRequests.map(\.request).filter { $0.type.command == "call_service" }
            XCTAssertFalse(calls.isEmpty, "\(rig.family): the weather panel reads its forecasts once connected")
            for call in calls {
                XCTAssertTrue(ServerUIPreviewLiveProvidersTests.isApprovedForecastRead(call), "\(rig.family): \(call.data)")
                let data = call.data["service_data"] as? [String: Any]
                XCTAssertEqual(data?["entity_id"] as? String, "weather.demo_forecast", "\(rig.family): only the document's weather entity")
            }
            XCTAssertEqual(rig.live.caller.blockedCommands, 0, "\(rig.family): they go through the weather reader, not the refusing caller")
        }
    }

    func testAHouseholdToggleIsRefusedCountedAndSendsNothing() async throws {
        try await drive { rig in
            let household = try XCTUnwrap(rig.supply.settings["household"] as? UKServerUIHouseholdProvider)
            try rig.tap("w-toggle")
            await rig.assertRefused(1, "household toggle")
            await rig.dismissAlerts()
            XCTAssertFalse(household.protectsPublication, "\(rig.family): the toggle's pending flag clears")
            XCTAssertEqual(rig.live.context.store.value("switch.synthetic_toggle")?.state, "off", "\(rig.family): the state is untouched")
        }
    }

    func testSignOutIsRefusedCountedAndSendsNothing() async throws {
        try await drive { rig in
            let profile = try XCTUnwrap(rig.supply.settings["profile"] as? UKServerUIProfileProvider)
            try rig.tap("w-signout")
            try await rig.confirmAlert()
            await rig.assertRefused(1, "sign-out")
            await rig.dismissAlerts()
            XCTAssertFalse(profile.protectsPublication, "\(rig.family): the signing-out flag clears")
        }
    }

    func testTheHomeAssistantWebPageActionSendsNothing() async throws {
        try await drive { rig in
            try rig.tap("w-haweb")
            let shown = await FeatureHost.settleAsync(until: { FeatureHost.alert(on: rig.renderer) != nil })
            XCTAssertTrue(shown, "\(rig.family): the action answers with a notice instead of opening a page")
            await rig.dismissAlerts()
            XCTAssertEqual(rig.live.caller.blockedCommands, 0, "\(rig.family): it is refused at the action, not as a command")
            await rig.assertNoWrite("web page")
        }
    }

    func testFeedbackFilingNeverFilesAndSendsNothing() async throws {
        try await drive { rig in
            let feedback = try XCTUnwrap(rig.supply.settings["feedback-bug"] as? UKServerUIFeedbackProvider)
            feedback.model.title = "Synthetic"
            feedback.model.descriptionText = "Synthetic report"
            await feedback.model.checkAvailability()
            feedback.model.submit(platform: .ios, diagnostics: {
                FeedbackDiagnostics(app: "T", system: "iOS", device: "T", window: "T", homeAssistant: "T", accessibility: "T", locale: "en")
            })
            let settled = await FeatureHost.settleAsync(until: { !feedback.model.isSending })
            XCTAssertTrue(settled, "\(rig.family): the sending flag clears")
            if case .finished = feedback.model.phase { XCTFail("\(rig.family): a report was filed") }
            await rig.assertNoWrite("feedback")
        }
    }

    func testAPreferencesWriteLandsOnlyInTheIsolatedSuite() async throws {
        let standardBlur = UserDefaults.standard.object(forKey: BackdropBlur.defaultsKey) as? Int
        try await drive { rig in
            let preferences = try XCTUnwrap(rig.supply.settings["preferences"] as? UKServerUIPreferencesProvider)
            try preferences.setBlur(55)
            let isolated = try XCTUnwrap(UserDefaults(suiteName: rig.defaultsName))
            XCTAssertEqual(isolated.object(forKey: BackdropBlur.defaultsKey) as? Int, 55, rig.family)
            XCTAssertEqual(UserDefaults.standard.object(forKey: BackdropBlur.defaultsKey) as? Int, standardBlur,
                           "\(rig.family): standard defaults are untouched")
            await rig.assertNoWrite("preferences")
        }
    }

    func testTheAppIconChoiceStaysInMemory() async throws {
        let group = UserDefaults(suiteName: ActivityAppIconStore.appGroup)
        let groupIcon = group?.string(forKey: ActivityAppIconStore.key)
        try await drive { rig in
            let preferences = try XCTUnwrap(rig.supply.settings["preferences"] as? UKServerUIPreferencesProvider)
            try rig.tap("w-icon")
            let chosen = await FeatureHost.settleAsync(until: { preferences.icons.selected == .midnightGold && !preferences.icons.isChanging })
            XCTAssertTrue(chosen, "\(rig.family): the choice shows in the preview's own model and the change flag clears")
            await rig.dismissAlerts()
            XCTAssertNil(UIApplication.shared.alternateIconName, "\(rig.family): the system icon is untouched")
            XCTAssertEqual(group?.string(forKey: ActivityAppIconStore.key), groupIcon, "\(rig.family): the app group is untouched")
            await rig.assertNoWrite("app icon")
        }
    }

    func testTheAdminTodoUploadFromTheSuppliedProviderIsRefusedCountedAndSendsNothing() async throws {
        try await drive { rig in
            let page = try XCTUnwrap(rig.supply.records.collections.values.compactMap { $0 as? UKServerUIChoresCollection }
                .first { $0.configuration.editsAdminTodo }, "\(rig.family): the admin to-do page among \(rig.supply.records.collections.keys.sorted())")
            let loading = Task { try? await page.load() }
            // The list reads the load sent are answered on the mock, so the supplied provider holds rows and can be driven.
            let asked = await FeatureHost.settleAsync(until: {
                rig.mock.pendingRequests.contains { $0.request.type.command == "todo/item/list" }
            })
            XCTAssertTrue(asked, "\(rig.family): the load read the lists")
            let items = HAData(value: ["items": [["uid": "synthetic-1", "summary": "Synthetic", "status": "needs_action"]]])
            for pending in rig.mock.pendingRequests where pending.request.type.command == "todo/item/list" {
                pending.completion(.success(items))
            }
            await loading.value
            let provider = try XCTUnwrap(page.records.compactMap { record -> ServerUITodoProvider? in
                if case .todo(_, let provider) = record { provider } else { nil }
            }.first, "\(rig.family): the supplied admin to-do provider")
            XCTAssertTrue(provider.configuration.allowsAttachments, "\(rig.family): it is the admin list, which takes attachments")
            let image = AdminTodoUpload.Image(data: Data([1, 2, 3]), filename: "a.png", mimeType: "image/png")
            do { try await provider.add(name: "Synthetic", images: [image], accessToken: { "synthetic" }); XCTFail("\(rig.family): an upload went out") }
            catch { XCTAssertEqual(error as? UKServerUIPreviewLiveData.Failure, .commandsDisabled, rig.family) }
            await rig.assertRefused(1, "admin to-do upload")
            XCTAssertFalse(provider.hasPendingIntent, "\(rig.family): the pending flag clears")
        }
    }

    func testADataFlowCallFromTheSuppliedFlowIsRefusedCountedAndSendsNothing() async throws {
        let (live, providers, _) = try make()
        let mock = lastMock!
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: apple.appendingPathComponent(
            "Tests/HassCoreTests/ContractCorpus/accept/pipeline-todo-get-items-service.json")))
        let publication = try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
        // The flow waits for the first entity states; the supply starts its session, and the session's call is the write.
        live.context.store.replaceAll([EntityState(entityId: "todo.demo_chores", state: "0")])
        _ = try providers.supply(for: publication, blur: ServerUIRendererFixture.backdrop().blur)
        let counted = await FeatureHost.settleAsync(until: { live.caller.blockedCommands >= 1 })
        XCTAssertTrue(counted, "The flow's own service call was refused and counted (\(live.caller.blockedCommands))")
        await Self.assertNoWrite(on: mock, "flow call", "all")
    }

    func testBedroomProvidersRefuseTheirWritesAndSendNothing() async throws {
        try await drive { rig in
            let room = self.house.bedroom
            guard case .wake(let wake)? = rig.supply.bedrooms[room.wakeLight.id] else { return XCTFail("\(rig.family): wake light") }
            let accepted = await wake.delete(alarmId: "synthetic")
            XCTAssertFalse(accepted, "\(rig.family): the wake light command is refused")
            await rig.assertRefused(1, "wake light command")
            let bedID = try XCTUnwrap(room.beds.first).id
            guard case .bed(let bed)? = rig.supply.bedrooms[bedID] else { return XCTFail("\(rig.family): bed side") }
            bed.setPower(on: true)
            await FeatureHost.settleAsync(0.3)
            XCTAssertFalse(wake.hasPendingCommands, "\(rig.family): the wake light's pending flag clears")
            await rig.assertNoWrite("bed side")
        }
    }

    func testMediaRemoteProvidersRefuseTheirWritesAndSendNothing() async throws {
        try await drive { rig in
            let remote = try XCTUnwrap(rig.supply.remotes.values.first, rig.family)
            remote.controller.press(remote.controller.config.power)
            await remote.controller.waitForCalls()
            await rig.assertRefused(1, "remote button")
        }
    }

    func testAwayAndVacationProvidersRefuseTheirWritesAndSendNothing() async throws {
        try await drive { rig in
            let away = try XCTUnwrap(rig.supply.settings["away"] as? UKServerUIAwayProvider)
            let item = try XCTUnwrap(self.house.vacation.checklist.first)
            away.vacation.toggle(item)
            await away.vacation.drain()
            await rig.assertRefused(1, "vacation check")
            let outcome = await away.solo.household.endNow()
            if case .rejected = outcome {} else { XCTFail("\(rig.family): the household away command was accepted") }
            await rig.assertRefused(2, "household away command")
            XCTAssertFalse(away.solo.household.pending, "\(rig.family): the household command's pending flag clears")
        }
    }

    func testAScheduleUpdateIsRefusedWhileScheduleReadsStillGoOut() async throws {
        try await drive { rig in
            let read = Task { try? await rig.supply.schedules.listSchedules() }
            let listed = await FeatureHost.settleAsync(until: {
                rig.mock.pendingRequests.contains { $0.request.type.command == "schedule/list" }
            })
            XCTAssertTrue(listed, "\(rig.family): a schedule read reaches the connection")
            read.cancel()
            do { _ = try await rig.supply.schedules.updateSchedule(["name": "synthetic"]); XCTFail("\(rig.family): a schedule update went out") }
            catch { XCTAssertEqual(error as? UKServerUIPreviewLiveData.Failure, .commandsDisabled, rig.family) }
            await rig.assertRefused(1, "schedule update")
        }
    }

    // MARK: Hosted UX and accessibility

    func testCameraWeatherAndVacationCheckAreAcceptedAtIPhoneDuoAndIPadWidths() async throws {
        let publication = try publication()
        let assets = try await stagedAssets(publication)
        XCTAssertThrowsError(try UKServerUIRenderer(publication: publication, context: UKContext(store: EntityStore()),
            backdrop: ServerUIRendererFixture.backdrop()), "With no providers the layout is refused whole, as it was")
        for (family, size) in [("iPhone", CGSize(width: 390, height: 844)), ("Duo", CGSize(width: 466, height: 678)),
                               ("iPad", CGSize(width: 820, height: 1180))] {
            let (live, providers, _) = try make()
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
