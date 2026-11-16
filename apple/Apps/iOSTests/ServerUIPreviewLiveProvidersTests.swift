import CryptoKit
import FentonActivityModel
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

    private var defaultsName = ""

    private func make(document: Bool = true, signedIn: Bool = true, retain: Bool = true, source: HouseConfigSource? = nil,
                      start: Bool = true) throws -> (UKServerUIPreviewLiveData, UKServerUIPreviewLiveProviders, HouseConfigStore) {
        let live = try UKServerUIPreviewLiveData(configuration: .init(server: "https://home.example.com", accountID: "demo"),
                                                 credential: "test-only-token", directory: directory, store: EntityStore())
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
        let components = try XCTUnwrap(json["document"]?["pages"]?.array?.first?["components"]?.array)
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(components + placed))
        return try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
    }

    func testEveryWriteDrivenThroughTheBuiltProvidersIsRefusedCountedAndLeavesNoTraceOutsideThePreview() async throws {
        let publication = try writingPublication()
        let assets = try await stagedAssets(publication)
        let standardBlur = UserDefaults.standard.object(forKey: BackdropBlur.defaultsKey) as? Int
        let group = UserDefaults(suiteName: ActivityAppIconStore.appGroup)
        let groupIcon = group?.string(forKey: ActivityAppIconStore.key)
        for (family, size) in [("iPhone", CGSize(width: 390, height: 844)), ("Duo", CGSize(width: 466, height: 678)),
                               ("iPad", CGSize(width: 820, height: 1180))] {
            let (live, providers, _) = try make()
            live.context.store.apply([EntityState(entityId: "switch.synthetic_toggle", state: "off")])
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
            func tap(_ id: String) throws {
                let node = try XCTUnwrap(page.nodes[id]?.view, "\(family): \(id)")
                func control(in view: UIView) -> UIControl? {
                    if view is UKRowButton || view is UKGlassTileView, let found = view as? UIControl { return found }
                    for sub in view.subviews { if let found = control(in: sub) { return found } }
                    return nil
                }
                let found = try XCTUnwrap(control(in: node), "\(family): \(id) control \(node.subviews)")
                if let row = found as? UKRowButton { try XCTUnwrap(row.onTap, "\(family): \(id) tap")() }
                else { found.sendActions(for: .touchUpInside) }
            }
            func blocked(_ count: Int, _ what: String) async {
                let reached = await FeatureHost.settleAsync(until: { live.caller.blockedCommands >= count })
                XCTAssertTrue(reached, "\(family): \(what) was not refused and counted (\(live.caller.blockedCommands))")
                XCTAssertEqual(live.caller.blockedCommands, count, "\(family): \(what)")
            }

            // A household toggle through the household provider.
            try tap("w-toggle")
            await blocked(1, "household toggle")

            // Sign-out through the profile provider: confirm, then the closure is refused and the failure alert offers Cancel.
            try tap("w-signout")
            let confirm = try XCTUnwrap(FeatureHost.alert(on: renderer), "\(family): sign-out confirmation")
            XCTAssertTrue(FeatureHost.answer(confirm, AlertCopy.signOut.confirm.title))
            await blocked(2, "sign-out")
            let failureTitle = AlertCopy.signOutFailed(device: .current).title
            let failureShown = await FeatureHost.settleAsync(until: { FeatureHost.alert(on: renderer)?.title == failureTitle })
            XCTAssertTrue(failureShown, "\(family): the refused sign-out says so")
            if let failed = FeatureHost.alert(on: renderer) { _ = FeatureHost.answer(failed, "Cancel") }
            let cleared = await FeatureHost.settleAsync(until: { FeatureHost.alert(on: renderer) == nil })
            XCTAssertTrue(cleared, family)

            // The Home Assistant web page action: refused at the action with the preview's own notice, no request.
            try tap("w-haweb")
            let noticeShown = await FeatureHost.settleAsync(until: { FeatureHost.alert(on: renderer)?.title == "Unavailable in Preview" })
            XCTAssertTrue(noticeShown, "\(family): web page notice")
            if let notice = FeatureHost.alert(on: renderer) { _ = FeatureHost.answer(notice, "OK") }
            XCTAssertEqual(live.caller.blockedCommands, 2, "\(family): the web action sends nothing")

            // The app icon: held in the preview's model only.
            let preferences = try XCTUnwrap(supply.settings["preferences"] as? UKServerUIPreferencesProvider)
            try tap("w-icon")
            let chosen = await FeatureHost.settleAsync(until: { preferences.icons.selected == .midnightGold })
            XCTAssertTrue(chosen, "\(family): the choice shows in the preview's own model")
            XCTAssertNil(UIApplication.shared.alternateIconName, "\(family): the system icon is untouched")
            XCTAssertEqual(group?.string(forKey: ActivityAppIconStore.key), groupIcon, "\(family): the app group is untouched")

            // A preferences write lands in the isolated suite only.
            try preferences.setBlur(55)
            let isolated = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
            XCTAssertEqual(isolated.object(forKey: BackdropBlur.defaultsKey) as? Int, 55, family)
            XCTAssertEqual(UserDefaults.standard.object(forKey: BackdropBlur.defaultsKey) as? Int, standardBlur,
                           "\(family): standard defaults are untouched")

            // Feedback filing never files.
            let feedback = try XCTUnwrap(supply.settings["feedback-bug"] as? UKServerUIFeedbackProvider)
            feedback.model.title = "Synthetic"
            feedback.model.descriptionText = "Synthetic report"
            await feedback.model.checkAvailability()
            feedback.model.submit(platform: .ios, diagnostics: {
                FeedbackDiagnostics(app: "T", system: "iOS", device: "T", window: "T", homeAssistant: "T", accessibility: "T", locale: "en")
            })
            await FeatureHost.settleAsync(0.3)
            if case .finished = feedback.model.phase { XCTFail("\(family): a report was filed") }

            // The admin to-do upload, through the same services the records were built over.
            let todo = ServerUITodoProvider(configuration: try .init(entityId: "todo.synthetic", canAdd: true, allowsAttachments: true),
                store: TodoStore(service: providers.services), service: providers.services)
            let image = AdminTodoUpload.Image(data: Data([1, 2, 3]), filename: "a.png", mimeType: "image/png")
            do { try await todo.add(name: "Synthetic", images: [image], accessToken: { "synthetic" }); XCTFail("\(family): an upload went out") }
            catch { XCTAssertEqual(error as? UKServerUIPreviewLiveData.Failure, .commandsDisabled, family) }
            XCTAssertEqual(live.caller.blockedCommands, 3, "\(family): upload")

            // A data flow's call through the host the flows run on.
            do {
                _ = try await providers.flowHost(entitySources: [:]).call("light", "turn_on", [:], [:], .seconds(1))
                XCTFail("\(family): a flow call went out")
            } catch { XCTAssertEqual(error as? UKServerUIPreviewLiveData.Failure, .commandsDisabled, family) }
            XCTAssertEqual(live.caller.blockedCommands, 4, "\(family): flow call")
            XCTAssertEqual(live.connection.status, .disconnected, "\(family): nothing reached the connection")
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
