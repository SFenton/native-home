import HassCore
import HassDemoHouse
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// A layout-driven page builds what comes from the house document when the document exists, and again when its hash changes, not
/// once in `viewDidLoad` (`.agents/design/house-config-states.md`, rule 17; the owner's first sign-in showed Home with only Weather,
/// 2026-11-10).
///
/// The page is built with the app's facades empty (a first sign-in: no disk copy, the document not yet arrived). The test then fills
/// the app's facades (`GalleryHouse`) and delivers the document through the store the gate follows, which is the order the app's own
/// path has: the store adopts the document, the gate sees it and asks the page to rebuild.
@MainActor
final class UKHostedHouseLayoutRebuildTests: DemoHouseTestCase {
    /// Built in the app's copy of HassCore, the one the gate observes (`GalleryHouseRig`).
    private let rig = GalleryHouseRig()
    private var source: HouseConfigSource { rig.source }
    private var transport: StubHouseTransport { rig.transport }

    private func makeStore() -> HouseConfigStore {
        // swiftlint:disable:next force_try
        try! rig.makeStore()
    }

    private func context(store: HouseConfigStore) -> (UKContext, GalleryServiceRecorder) {
        let entities = HomeFixtures.store(environment: [:])
        let recorder = GalleryServiceRecorder(store: entities)
        var context = UKGalleryChrome.context(store: entities, caller: recorder)
        context.houseConfigStore = store
        context.houseConfigSource = source
        return (context, recorder)
    }

    private func home(store: HouseConfigStore) -> UKHomeViewController {
        var configuration = UKHomeConfiguration()
        configuration.weatherStore = WeatherForecastStore(requestTimeout: 3600)
        configuration.weatherCaller = WeatherFixtureCaller(mode: .normal)
        return UKHomeViewController(context: context(store: store).0, configuration: configuration)
    }

    private func security(store: HouseConfigStore) -> UKSecurityViewController {
        let (context, recorder) = context(store: store)
        return UKSecurityViewController(context: context, caller: recorder, canSend: { true }, showsCameras: true, showsVehicle: false)
    }

    private func document(hash: String, mutate: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: DemoHouse.config.encoded()) as? [String: Any])
        let schema = object.removeValue(forKey: "schema") ?? 1
        mutate(&object)
        return try JSONSerialization.data(withJSONObject: ["schema": schema, "hash": hash, "config": object])
    }

    /// The tiles in the page's guest section, hidden or not (the section hides itself while no guest stays).
    private func guestTileCount(in page: UIViewController) -> Int {
        guard let section = HostedPage.descendants(of: page.view).first(where: { $0 is UKGuestPresenceSectionView }) else { return 0 }
        return HostedPage.descendants(of: section).filter { $0 is UKGlassTileView }.count
    }

    private func view(_ identifier: String, in page: UIViewController) -> UIView? { FeatureHost.view(identifier, in: page.view) }

    /// The ids the demo house's facades name, read from the test bundle's own copy (filled by ``DemoHouseTestCase``).
    private var chipIds: [String] { HomeConfig.statusChips.map { "home.chip.\($0.sheet.rawValue)" } }
    private var cameraIds: [String] { HomeConfig.cameras.map(\.rtcStreamId) }
    private var guestIds: [String] { HomeConfig.guestToggles.map { "guest.tile.\($0.entityId)" } }

    /// Empties the app's facades (what a first sign-in sees when the page builds); ``deliver(_:)`` fills them again.
    private func startWithoutADocument() {
        GalleryHouse.uninstall()
    }

    /// Delivers the document the way the app does: the facades and the store's source carry it, then the transport answers.
    private func deliver(_ data: Data, store: HouseConfigStore) async {
        GalleryHouse.install()
        // The store subscribes after its cache read, a task later: an answer sent before that is dropped.
        _ = await FeatureHost.settleAsync(until: { self.transport.subscribeCount > 0 }, timeout: 4)
        transport.emit(.success(data))
        _ = await FeatureHost.settleAsync(until: { rig.hasDocument }, timeout: 4)
    }

    // MARK: - First document

    func testHomeBuildsItsChipsCamerasAndGuestsWhenTheDocumentFirstArrives() async throws {
        XCTAssertFalse(chipIds.isEmpty, "the demo house has status chips")
        XCTAssertFalse(cameraIds.isEmpty, "the demo house has cameras")
        XCTAssertFalse(guestIds.isEmpty, "the demo house has guest toggles")
        startWithoutADocument()
        let store = makeStore()
        let page = home(store: store)
        let window = HostedPage.show(page)
        defer { window.isHidden = true }
        XCTAssertNotNil(view("home.skeleton", in: page), "no document yet: the skeleton")
        XCTAssertNil(view(chipIds[0], in: page), "built before the document: no chips yet")

        await deliver(try document(hash: "h1"), store: store)
        for id in chipIds {
            let reached = await FeatureHost.settleAsync(until: { self.view(id, in: page) != nil }, timeout: 6)
            XCTAssertTrue(reached, "\(id) is built when the document arrives")
        }
        for id in cameraIds { XCTAssertNotNil(view("home.camera.\(id)", in: page), "camera \(id)") }
        XCTAssertEqual(guestTileCount(in: page), guestIds.count, "a toggle per guest in the document")
        let reveal = await FeatureHost.settleAsync(until: { page.contentView.alpha == 1 }, timeout: 4)
        XCTAssertTrue(reveal, "the built content is revealed")
    }

    func testSecurityBuildsItsChipsCamerasAndGuestsWhenTheDocumentFirstArrives() async throws {
        // Read the ids while the demo house is installed: ``startWithoutADocument()`` empties the facades.
        let chips = HomeConfig.statusChips.filter { [.security, .contacts].contains($0.sheet) }.map { "security.chip.\($0.sheet.rawValue)" }
        XCTAssertFalse(chips.isEmpty, "the demo house has Security chips")
        startWithoutADocument()
        let store = makeStore()
        let page = security(store: store)
        let window = HostedPage.show(page)
        defer { window.isHidden = true }
        XCTAssertNotNil(view("page.skeleton", in: page))
        XCTAssertNil(view(chips[0], in: page), "built before the document: no chips yet")

        await deliver(try document(hash: "h1"), store: store)
        for id in chips {
            let reached = await FeatureHost.settleAsync(until: { self.view(id, in: page) != nil }, timeout: 6)
            XCTAssertTrue(reached, "\(id) is built when the document arrives")
        }
        for id in cameraIds { XCTAssertNotNil(view("security.camera.\(id)", in: page), "camera \(id)") }
        XCTAssertEqual(guestTileCount(in: page), guestIds.count, "a toggle per guest in the document")
    }

    // MARK: - Cached launch

    func testACachedLaunchBuildsOnceAndNeverRebuildsWhenTheServerAnswersWithTheSameHash() async throws {
        let store = try rig.makeStore(cached: (DemoHouse.config, "h1"), loadsCacheSynchronously: true)
        let page = home(store: store)
        let window = HostedPage.show(page)
        defer { window.isHidden = true }
        let first = try XCTUnwrap(view(chipIds[0], in: page), "a saved layout: built at once")
        XCTAssertNil(view("home.skeleton", in: page))

        transport.emit(.success(try document(hash: "h1")))
        _ = await FeatureHost.settleAsync(until: { rig.status == .ready }, timeout: 4)
        HostedPage.wait(0.3)
        XCTAssertTrue(view(chipIds[0], in: page) === first, "the same chip: nothing rebuilt, nothing re-faded")
        XCTAssertEqual(page.contentView.alpha, 1)
    }

    // MARK: - Hash change

    func testAChangedHashRebuildsThePageOnceAndAnEqualHashDoesNot() async throws {
        let store = makeStore()
        startWithoutADocument()
        let page = home(store: store)
        let window = HostedPage.show(page)
        defer { window.isHidden = true }
        await deliver(try document(hash: "h1"), store: store)
        _ = await FeatureHost.settleAsync(until: { self.view(self.chipIds[0], in: page) != nil }, timeout: 6)
        let first = try XCTUnwrap(view(chipIds[0], in: page))

        transport.emit(.success(try document(hash: "h1")))
        HostedPage.wait(0.3)
        XCTAssertTrue(view(chipIds[0], in: page) === first, "an equal hash is not a change")

        transport.emit(.success(try document(hash: "h2")))
        let rebuilt = await FeatureHost.settleAsync(until: { (self.view(self.chipIds[0], in: page)).map { $0 !== first } ?? false }, timeout: 6)
        XCTAssertTrue(rebuilt, "a new hash rebuilds the structure from the facades")
        XCTAssertEqual(page.contentView.alpha, 1, "the page stays on screen while it rebuilds")
        XCTAssertEqual(count(UKColumnScrollView.self, in: page), 1, "the old scroll view is gone, not stacked")
        for id in chipIds { XCTAssertEqual(countExact(id, in: page), 1, "one \(id) after the rebuild") }
    }

    func testSecurityRebuildsOnceOnAChangedHashWithoutStackingViews() async throws {
        startWithoutADocument()
        let store = makeStore()
        let page = security(store: store)
        let window = HostedPage.show(page)
        defer { window.isHidden = true }
        await deliver(try document(hash: "h1"), store: store)
        let chips = HomeConfig.statusChips.filter { [.security, .contacts].contains($0.sheet) }.map { "security.chip.\($0.sheet.rawValue)" }
        _ = await FeatureHost.settleAsync(until: { self.view(chips[0], in: page) != nil }, timeout: 6)
        let first = try XCTUnwrap(view(chips[0], in: page))
        await deliver(try document(hash: "h2"), store: store)
        let rebuilt = await FeatureHost.settleAsync(until: { (self.view(chips[0], in: page)).map { $0 !== first } ?? false }, timeout: 6)
        XCTAssertTrue(rebuilt, "a new hash rebuilds the sections")
        XCTAssertEqual(count(UKColumnScrollView.self, in: page), 1)
        for id in chips { XCTAssertEqual(countExact(id, in: page), 1, "one \(id) after the rebuild") }
    }

    // MARK: - The other layout-driven pages

    private func count(_ prefix: String, in page: UIViewController) -> Int {
        HostedPage.descendants(of: page.view).filter { ($0.accessibilityIdentifier ?? "").hasPrefix(prefix) }.count
    }

    /// Builds `page` with no document, delivers one, and expects `prefix` to name more views afterwards.
    private func expectRebuild(_ name: String, prefix: String, store: HouseConfigStore, page: UIViewController) async throws {
        let window = HostedPage.show(page)
        defer { window.isHidden = true }
        XCTAssertEqual(count(prefix, in: page), 0, "\(name): built before the document: nothing yet")
        await deliver(try document(hash: "h1"), store: store)
        let built = await FeatureHost.settleAsync(until: { self.count(prefix, in: page) > 0 }, timeout: 6)
        XCTAssertTrue(built, "\(name): built when the document arrives")
    }

    func testVacuumsBuildsItsRobotsAndAutoCleanRowsWhenTheDocumentFirstArrives() async throws {
        startWithoutADocument()
        let store = makeStore()
        let (context, recorder) = context(store: store)
        let page = UKVacuumsViewController(context: context, caller: recorder) { vacuum in
            UKVacuumSheetViewController(controller: VacuumController(vacuum: vacuum, store: context.store, caller: recorder),
                                        loader: VacuumFixtures.loader(vacuum, scenario: .docked), server: nil, catalog: nil,
                                        services: VacuumFixtures.services, context: context.with { $0.surface = .sheet })
        }
        try await expectRebuild("Vacuums", prefix: "vacuums.tile.", store: store, page: page)
        XCTAssertGreaterThan(count("vacuums.autoClean.", in: page), 0, "the Auto-Clean rows too")
    }

    func testCustomLightsBuildsItsTilesWhenTheDocumentFirstArrives() async throws {
        startWithoutADocument()
        let store = makeStore()
        try await expectRebuild("Custom Lights", prefix: "customLights.light.", store: store,
                                page: UKCustomLightsViewController(context: context(store: store).0))
    }

    func testMediaBuildsItsSectionsWhenTheDocumentFirstArrives() async throws {
        startWithoutADocument()
        let store = makeStore()
        try await expectRebuild("Media", prefix: "media.section.", store: store, page: UKMediaViewController(context: context(store: store).0))
    }

    private func countExact(_ identifier: String, in page: UIViewController) -> Int {
        HostedPage.descendants(of: page.view).filter { $0.accessibilityIdentifier == identifier }.count
    }

    private func count<T: UIView>(_ type: T.Type, in page: UIViewController) -> Int {
        HostedPage.descendants(of: page.view).filter { $0 is T }.count
    }

    func testSprinklersBuildsItsControllerCardsWhenTheDocumentFirstArrives() async throws {
        startWithoutADocument()
        let store = makeStore()
        let page = UKSprinklersViewController(context: context(store: store).0)
        let window = HostedPage.show(page)
        defer { window.isHidden = true }
        XCTAssertEqual(count(UKSprinklerControllerCard.self, in: page), 0, "built before the document: no cards")
        await deliver(try document(hash: "h1"), store: store)
        let built = await FeatureHost.settleAsync(until: { self.count(UKSprinklerControllerCard.self, in: page) > 0 }, timeout: 6)
        XCTAssertTrue(built, "a card per controller once the document arrives")
    }

    func testAHouseholdTopicBuildsItsTilesWhenTheDocumentFirstArrives() async throws {
        startWithoutADocument()
        let store = makeStore()
        let page = UKHouseholdSettingsViewController.make(page: .guests, context: context(store: store).0)
        let window = HostedPage.show(page)
        defer { window.isHidden = true }
        XCTAssertEqual(count(UKGlassTileView.self, in: page), 0, "built before the document: no tiles")
        await deliver(try document(hash: "h1"), store: store)
        let built = await FeatureHost.settleAsync(until: { self.count(UKGlassTileView.self, in: page) > 0 }, timeout: 6)
        XCTAssertTrue(built, "a toggle per guest once the document arrives")
        // A changed hash rebuilds the topic once: the old tiles are gone, not stacked under the new ones.
        let before = count(UKGlassTileView.self, in: page)
        await deliver(try document(hash: "h2"), store: store)
        HostedPage.wait(0.3)
        XCTAssertEqual(count(UKGlassTileView.self, in: page), before, "the rebuild replaces the tiles")
    }

    func testFoodBuildsItsSpaceTilesWhenTheDocumentFirstArrives() async throws {
        startWithoutADocument()
        let store = makeStore()
        var context = context(store: store).0
        context.houseConfigStore = store
        let server = EverShelfFixtureServer.sample()
        let page = UKFoodHubViewController(context: context, models: FoodModels(service: FixtureRecipeService(delay: .milliseconds(10))),
                                           inventory: InventoryModels(client: EverShelfClient(caller: server)))
        try await expectRebuild("Food", prefix: "food.space.", store: store, page: UKGalleryChrome.wrap(page, context: context))
    }

    func testVacationShowsAFreshContentWhenTheDocumentFirstArrives() async throws {
        startWithoutADocument()
        let store = makeStore()
        let house = VacationGalleryHouse(store: VacationFixtures.store(.idle), delay: .milliseconds(30))
        var context = UKGalleryChrome.context(store: house.store, caller: house)
        context.houseConfigStore = store
        context.houseConfigSource = source
        let page = UKVacationViewController(context: context, responder: house, caller: house, currentUserId: { nil })
        let window = HostedPage.show(page, size: CGSize(width: 393, height: 1800))
        defer { window.isHidden = true }
        let before = page.contentView.subviews.compactMap { $0 as? UIScrollView }.first
        await deliver(try document(hash: "h1"), store: store)
        let swapped = await FeatureHost.settleAsync(until: {
            guard let now = page.contentView.subviews.compactMap({ $0 as? UIScrollView }).first else { return false }
            return now !== before
        }, timeout: 6)
        XCTAssertTrue(swapped, "the chooser is made again from the document")
    }

    // MARK: - Try Again

    func testTryAgainKeepsTheMessageBusyWhileTheStoreAsksAgain() async throws {
        let store = try rig.makeStore(timeout: .milliseconds(150))
        let page = home(store: store)
        let window = HostedPage.show(page)
        defer { window.isHidden = true }
        let appeared = await FeatureHost.settleAsync(until: { self.view("houseConfig.action", in: page) != nil }, timeout: 6)
        XCTAssertTrue(appeared, "10 s with no answer, shortened: the message with Try Again")
        XCTAssertTrue(FeatureHost.press("houseConfig.action", in: page.view))
        let busy = await FeatureHost.settleAsync(until: { (self.view("houseConfig.action", in: page) as? UKPrimaryButton)?.isBusy == true }, timeout: 4)
        XCTAssertTrue(busy, "the button shows Trying Again while the store asks")
        await deliver(try document(hash: "h1"), store: store)
        let gone = await FeatureHost.settleAsync(until: { self.view("houseConfig.state", in: page) == nil }, timeout: 6)
        XCTAssertTrue(gone, "the message goes when the document arrives")
    }
}
