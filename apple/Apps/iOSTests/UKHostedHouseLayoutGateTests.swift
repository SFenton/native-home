import HassCore
import HassDemoHouse
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// The skeleton and the missing-layout messages on the layout-driven pages, and the swap to content
/// (`.agents/design/house-config-states.md` rules 10 to 15). Compile-only in the migration tier: run in the deferred pass.
@MainActor
final class UKHostedHouseLayoutGateTests: DemoHouseTestCase {
    /// Built in the app's copy of HassCore, the one the gate observes (`GalleryHouseRig`).
    private let rig = GalleryHouseRig()
    private var source: HouseConfigSource { rig.source }
    private var transport: StubHouseTransport { rig.transport }

    private func makeStore(timeout: Duration = .seconds(60)) -> HouseConfigStore {
        // swiftlint:disable:next force_try
        try! rig.makeStore(timeout: timeout)
    }

    private func homeContext(store: HouseConfigStore) -> UKContext {
        let entities = HomeFixtures.store(environment: [:])
        var context = UKGalleryChrome.context(store: entities, caller: GalleryServiceRecorder(store: entities))
        context.houseConfigStore = store
        context.houseConfigSource = source
        return context
    }

    private func home(store: HouseConfigStore) -> UKHomeViewController {
        var configuration = UKHomeConfiguration()
        configuration.weatherStore = WeatherForecastStore(requestTimeout: 3600)
        configuration.weatherCaller = WeatherFixtureCaller(mode: .normal)
        return UKHomeViewController(context: homeContext(store: store), configuration: configuration)
    }

    /// Answers the subscription once the store has made it (it subscribes a task after `start()`; an earlier answer is dropped).
    private func emit(_ result: Result<Data, Error>) async {
        _ = await FeatureHost.settleAsync(until: { self.transport.subscribeCount > 0 }, timeout: 4)
        transport.emit(result)
    }

    private func document() throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: DemoHouse.config.encoded()) as? [String: Any])
        let schema = object.removeValue(forKey: "schema") ?? 1
        return try JSONSerialization.data(withJSONObject: ["schema": schema, "hash": "h1", "config": object])
    }

    private func has(_ identifier: String, in page: UIViewController) -> Bool { FeatureHost.view(identifier, in: page.view) != nil }

    private func expectWait(_ identifier: String, in page: UIViewController, present: Bool = true, _ message: String = "",
                            file: StaticString = #filePath, line: UInt = #line) async {
        let reached = await waitFor(identifier, in: page, present: present)
        XCTAssertTrue(reached, message.isEmpty ? "\(identifier) \(present ? "did not appear" : "did not go")" : message, file: file, line: line)
    }

    private func waitFor(_ identifier: String, in page: UIViewController, present: Bool = true) async -> Bool {
        await FeatureHost.settleAsync(until: { self.has(identifier, in: page) == present }, timeout: 6)
    }

    /// A plain page with a marker for its content, gated by a forced state.
    private func gated(_ forced: HouseLayoutDebug.Forced, role: HouseLayoutState.Role?, size: CGSize? = nil)
        throws -> (UKPageViewController, UKHouseLayoutGate, UIWindow, (session: AppSession, connection: HassConnection, context: UKContext)) {
        let host = try FeatureHost.signedIn()
        let page = UKPageViewController(context: host.context, title: "Layout")
        let marker = UIView()
        marker.accessibilityIdentifier = "fixture.content"
        marker.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        page.contentView.addSubview(marker)
        let window = HostedPage.show(page, size: size)
        let gate = UKHouseLayoutGate(page: page, kind: .page, forced: forced, role: role)
        HostedPage.wait(0.3)
        return (page, gate, window, host)
    }

    // MARK: - Skeleton

    func testHomeShowsItsSkeletonUntilTheDocumentArrivesThenSwapsToContent() async throws {
        let store = makeStore()
        let page = home(store: store)
        let window = HostedPage.show(page)
        defer { window.isHidden = true }
        await expectWait("home.skeleton", in: page, "no document yet: the skeleton")
        let skeleton = try XCTUnwrap(FeatureHost.view("home.skeleton", in: page.view))
        XCTAssertTrue(skeleton.isAccessibilityElement)
        XCTAssertEqual(skeleton.accessibilityLabel, "Getting your home from Home Assistant")
        XCTAssertEqual(page.contentView.alpha, 0, "the content waits behind the skeleton, still built")
        XCTAssertFalse(has("houseConfig.state", in: page))

        await emit(.success(try document()))
        await expectWait("home.skeleton", in: page, present: false, "the document arrived: the skeleton goes")
        _ = await FeatureHost.settleAsync(until: { page.contentView.alpha == 1 }, timeout: 4)
        XCTAssertEqual(page.contentView.alpha, 1)
        XCTAssertEqual(page.contentView.transform, .identity)
        XCTAssertTrue(page.contentView.isUserInteractionEnabled)
    }

    func testSecurityShowsTheGenericSkeletonAndTheDocumentSwapsItAway() async throws {
        let store = makeStore()
        let entities = HomeFixtures.store(environment: [:])
        let recorder = GalleryServiceRecorder(store: entities)
        var context = UKGalleryChrome.context(store: entities, caller: recorder)
        context.houseConfigStore = store
        context.houseConfigSource = source
        let page = UKSecurityViewController(context: context, caller: recorder, canSend: { true }, showsCameras: false, showsVehicle: false)
        let window = HostedPage.show(page)
        defer { window.isHidden = true }
        await expectWait("page.skeleton", in: page)
        XCTAssertEqual(FeatureHost.view("page.skeleton", in: page.view)?.accessibilityLabel, "Getting your home from Home Assistant")
        await emit(.success(try document()))
        await expectWait("page.skeleton", in: page, present: false)
    }

    func testTheSkeletonStaysOneElementAtTheLargestTextSize() async throws {
        let store = makeStore()
        let page = home(store: store)
        let window = HostedPage.show(page)
        defer { window.isHidden = true }
        window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        page.view.setNeedsLayout()
        await expectWait("home.skeleton", in: page)
        let skeleton = try XCTUnwrap(FeatureHost.view("home.skeleton", in: page.view) as? UKConfigSkeletonView)
        skeleton.layoutIfNeeded()
        XCTAssertTrue(skeleton.isAccessibilityElement, "one element at AX5")
        XCTAssertTrue(skeleton.subviews.allSatisfy { !$0.isAccessibilityElement }, "the shapes are hidden from VoiceOver")
        XCTAssertTrue(skeleton.subviews.filter { !$0.isHidden }.allSatisfy { $0.frame.maxX <= skeleton.bounds.width + 0.5 })
    }

    func testAPageWithADocumentNeverShowsAStateWhateverTheStatus() async throws {
        rig.setDocument(DemoHouse.config)
        let store = makeStore()
        let page = home(store: store)
        let window = HostedPage.show(page)
        defer { window.isHidden = true }
        await emit(.success(Data(#"{"configured": false}"#.utf8)))
        _ = await FeatureHost.settleAsync(until: { rig.status == .notConfigured }, timeout: 4)
        XCTAssertEqual(rig.status, .notConfigured)
        XCTAssertFalse(has("home.skeleton", in: page) || has("houseConfig.state", in: page), "a saved layout always wins")
        XCTAssertEqual(page.contentView.alpha, 1)
    }

    // MARK: - Messages

    func testEachMessageShowsItsTitleAndTheActionOnlyForAnAdministrator() async throws {
        let cases: [(String, HouseLayoutDebug.Forced, String, String?)] = [
            ("integration missing", .init(status: .integrationMissing, hasDocument: false), "Add the S+H Home Integration", "Open Integrations"),
            ("not configured", .init(status: .notConfigured, hasDocument: false), "Home Isn't Set Up Yet", "Open S+H Home Integration"),
            ("invalid", .init(status: .invalid, hasDocument: false), "Unable to Read the House Layout", "Open Repairs"),
            ("newer", .init(status: .newerSchema(found: 99), hasDocument: false), "Update S+H", nil),
            ("timed out", .init(status: .timedOut, hasDocument: false), "Unable to Load the House Layout", "Try Again"),
        ]
        for (name, forced, title, action) in cases {
            for role in [HouseLayoutState.Role.admin, .member] {
                let (page, gate, window, _) = try gated(forced, role: role)
                defer { window.isHidden = true }
                XCTAssertNotNil(FeatureHost.view("houseConfig.state", in: page.view), "\(name) \(role): the message")
                XCTAssertTrue(HostedPage.labels(in: page.view).contains(title), "\(name) \(role): title \(title)")
                let button = FeatureHost.view("houseConfig.action", in: page.view) as? UKPrimaryButton
                let expectsAction = action != nil && (role == .admin || forced.status == .timedOut)
                XCTAssertEqual(button != nil, expectsAction, "\(name) \(role): action presence")
                if let button, let action {
                    XCTAssertEqual(button.title, action)
                    XCTAssertGreaterThanOrEqual(button.bounds.height, 50, "the 50 pt button")
                }
                XCTAssertEqual(page.contentView.alpha, 0, "\(name): the content is held back")
                _ = gate
            }
        }
    }

    func testTheMessageTitleIsAHeadingAndTheGlyphIsHidden() throws {
        let (page, _, window, _) = try gated(.init(status: .integrationMissing, hasDocument: false), role: .admin)
        defer { window.isHidden = true }
        let views = HostedPage.descendants(of: page.view)
        let title = try XCTUnwrap(views.compactMap { $0 as? UILabel }.first { $0.text == "Add the S+H Home Integration" })
        XCTAssertTrue(title.accessibilityTraits.contains(.header))
        XCTAssertTrue(views.compactMap { $0 as? UIImageView }.allSatisfy { !$0.isAccessibilityElement })
    }

    func testTheMessageScrollsAtTheLargestTextSizeWithoutClipping() throws {
        let (page, _, window, _) = try gated(.init(status: .integrationMissing, hasDocument: false), role: .admin, size: CGSize(width: 393, height: 600))
        defer { window.isHidden = true }
        window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        page.view.layoutIfNeeded()
        HostedPage.wait(0.3)
        let scroll = try XCTUnwrap(HostedPage.descendants(of: page.view).compactMap { $0 as? UKCenteredStateMessageView }.first)
        scroll.layoutIfNeeded()
        XCTAssertGreaterThan(scroll.contentSize.height, 0)
        XCTAssertGreaterThanOrEqual(scroll.contentSize.height, scroll.state.systemLayoutSizeFitting(
            CGSize(width: scroll.bounds.width, height: UIView.layoutFittingCompressedSize.height)).height - 1, "nothing is cut: the content is as tall as the text")
    }

    func testOnAHingeBandTheMessageStaysInTheLeadingRegion() throws {
        let (page, _, window, _) = try gated(.init(status: .notConfigured, hasDocument: false), role: .admin, size: CGSize(width: 1024, height: 700))
        defer { window.isHidden = true; UKHinge.frame = nil }
        UKHinge.frame = CGRect(x: 500, y: 0, width: 24, height: 700)
        page.view.layoutIfNeeded()
        HostedPage.wait(0.3)
        let state = try XCTUnwrap(FeatureHost.view("houseConfig.state", in: page.view))
        XCTAssertLessThanOrEqual(state.convert(state.bounds, to: nil).maxX, 500 + 1, "the message never crosses the band")
    }

    func testTheActionOpensTheHomeAssistantModal() async throws {
        let (page, _, window, _) = try gated(.init(status: .integrationMissing, hasDocument: false), role: .admin)
        defer { window.isHidden = true }
        XCTAssertTrue(FeatureHost.press("houseConfig.action", in: page.view))
        await FeatureHost.settleAsync(0.6)
        XCTAssertTrue(page.presentedViewController is UKHassModalController, "Open Integrations opens the Home Assistant modal")
    }

    func testTheModalPushesTheNamedPageAfterItAppears() async throws {
        let signedIn = try FeatureHost.signedIn()
        let page = UKHomeAssistantSettingsViewController(session: signedIn.session, connection: signedIn.connection,
                                                         user: HassUser(id: "u1", name: "A", isOwner: false, isAdmin: true), initialPage: .repairs)
        var options = UKHassModalOptions(title: "Home Assistant")
        options.closeIdentifier = "haSettings.done"
        let modal = UKHassModalController(root: page, options: options)
        page.modal = modal
        let window = HostedPage.show(modal, size: CGSize(width: 393, height: 1600))
        defer { window.isHidden = true }
        _ = await FeatureHost.settleAsync(until: { modal.viewControllers.count == 2 }, timeout: 6)
        XCTAssertEqual(modal.viewControllers.count, 2, "Repairs is pushed on the modal")
    }

    func testTryAgainOnATimeoutShowsTheBusyTitle() throws {
        let (page, _, window, _) = try gated(.init(status: .timedOut, hasDocument: false), role: .member)
        defer { window.isHidden = true }
        let before = try XCTUnwrap(FeatureHost.view("houseConfig.action", in: page.view) as? UKPrimaryButton)
        XCTAssertFalse(before.isBusy)
        XCTAssertTrue(FeatureHost.press("houseConfig.action", in: page.view))
        HostedPage.wait(0.3)
        let after = try XCTUnwrap(FeatureHost.view("houseConfig.action", in: page.view) as? UKPrimaryButton)
        XCTAssertTrue(after.isBusy)
        XCTAssertEqual(after.activeTitle, "Trying Again")
    }

    func testARealTimeoutShowsTheMessageThenTheDocumentReplacesIt() async throws {
        let store = makeStore(timeout: .milliseconds(150))
        let page = home(store: store)
        let window = HostedPage.show(page)
        defer { window.isHidden = true }
        await expectWait("houseConfig.state", in: page, "10 s with no answer, shortened: the message")
        await emit(.success(try document()))
        await expectWait("houseConfig.state", in: page, present: false, "the message goes without anyone tapping")
        _ = await FeatureHost.settleAsync(until: { page.contentView.alpha == 1 }, timeout: 4)
        XCTAssertEqual(page.contentView.alpha, 1)
    }

    // MARK: - Missing entities

    func testAMissingConfiguredEntityReadsUnavailableOnItsChip() throws {
        // The first state set arrived but lacks everything the chips read: they say Unavailable, not Loading, and are not hidden.
        let entities = EntityStore()
        entities.replaceAll([EntityState(entityId: "sensor.demo_unrelated", state: "1")], freshness: .live)
        var context = UKGalleryChrome.context(store: entities, caller: GalleryServiceRecorder(store: entities))
        context.valuesPending = false
        let page = UKHomeViewController(context: context, configuration: UKHomeConfiguration(parts: .statusRail))
        let window = HostedPage.show(page)
        defer { window.isHidden = true }
        let pills = HostedPage.descendants(of: page.view).compactMap { $0 as? UKStatusPillView }
        XCTAssertFalse(pills.isEmpty, "the chips are still there")
        XCTAssertTrue(pills.contains { ($0.accessibilityValue ?? "").contains("Unavailable") }, "a missing entity reads Unavailable")
        XCTAssertFalse(pills.contains { $0.accessibilityValue == "Loading" })
    }

    // MARK: - The modal's House Layout row

    func testTheModalShowsTheHouseLayoutRow() async throws {
        let signedIn = try FeatureHost.signedIn()
        let page = UKHomeAssistantSettingsViewController(session: signedIn.session, connection: signedIn.connection,
                                                         user: HassUser(id: "u1", name: "A", isOwner: false, isAdmin: true))
        let window = HostedPage.show(page, size: CGSize(width: 393, height: 1600))
        defer { window.isHidden = true }
        await FeatureHost.settleAsync(0.5)
        let row = try XCTUnwrap(FeatureHost.view("haSettings.houseLayout", in: page.view), "the Server section has a House Layout row")
        XCTAssertTrue(row.accessibilityLabel?.hasPrefix("House Layout, ") == true, "got \(row.accessibilityLabel ?? "nil")")
        let ids = FeatureHost.identifiers(in: page.view)
        XCTAssertTrue(ids.contains("haSettings.server") && ids.contains("haSettings.status"))
    }

    // MARK: - Rule 15: a missing configured entity reads Unavailable on every tile kind, hidden or moved never

    /// A store whose first state set arrived and lacks everything the document names.
    private func storeLackingTheHouse() -> EntityStore {
        let entities = EntityStore()
        entities.replaceAll([EntityState(entityId: "sensor.demo_unrelated", state: "1")], freshness: .live)
        return entities
    }

    private func frames(_ root: UIView, prefix: String) -> [String: CGRect] {
        var result: [String: CGRect] = [:]
        for view in HostedPage.descendants(of: root) {
            if let id = view.accessibilityIdentifier, id.hasPrefix(prefix) { result[id] = view.convert(view.bounds, to: root) }
        }
        return result
    }

    func testMissingDoorTilesReadUnavailableStayPutAndDoNotMoveWhenTheEntitiesArrive() throws {
        let entities = storeLackingTheHouse()
        var context = UKGalleryChrome.context(store: entities, caller: GalleryServiceRecorder(store: entities))
        context.valuesPending = false
        let page = UKSecurityViewController(context: context, caller: GalleryServiceRecorder(store: entities), canSend: { true },
                                            showsCameras: false, showsVehicle: false)
        let window = HostedPage.show(page, size: CGSize(width: 393, height: 1600))
        defer { window.isHidden = true }
        let before = frames(page.view, prefix: "security.tile.")
        XCTAssertFalse(before.isEmpty, "the glass tiles are drawn, not hidden")
        let unavailable = HostedPage.descendants(of: page.view).filter {
            guard let id = $0.accessibilityIdentifier, id.hasPrefix("security.tile.") else { return false }
            return ($0.accessibilityValue ?? "").contains("Unavailable") || ($0.accessibilityLabel ?? "").contains("Unavailable")
        }
        XCTAssertFalse(unavailable.isEmpty, "a missing entity's GlassTile reads Unavailable")
        // The entities arrive: nothing reflows.
        entities.apply(UKSecurityViewController.doorTiles.map { EntityState(entityId: $0.entityId, state: "locked") })
        HostedPage.wait(0.4)
        page.view.layoutIfNeeded()
        let after = frames(page.view, prefix: "security.tile.")
        XCTAssertEqual(Set(before.keys), Set(after.keys), "no tile appears or disappears")
        for (id, frame) in before { XCTAssertEqual(after[id], frame, "\(id) did not move") }
    }

    func testAMissingLightIsAnUnavailableBrightnessTileThatStaysPut() throws {
        let entities = storeLackingTheHouse()
        var context = UKGalleryChrome.context(store: entities, caller: GalleryServiceRecorder(store: entities))
        context.valuesPending = false
        let page = UKCustomLightsViewController(context: context)
        let window = HostedPage.show(page, size: CGSize(width: 393, height: 1600))
        defer { window.isHidden = true }
        let tiles = HostedPage.descendants(of: page.view).compactMap { $0 as? UKBrightnessTileView }
        XCTAssertFalse(tiles.isEmpty, "the brightness tiles are drawn")
        XCTAssertTrue(tiles.allSatisfy(\.isUnavailable), "a missing light is an unavailable tile")
        XCTAssertTrue(tiles.allSatisfy { !$0.isHidden && $0.alpha > 0 })
        let before = tiles.map { $0.convert($0.bounds, to: page.view) }
        entities.apply(CustomLightsConfig.lights.map { EntityState(entityId: $0.entityId, state: "on", attributes: ["brightness": .number(128)]) })
        HostedPage.wait(0.4)
        page.view.layoutIfNeeded()
        let after = HostedPage.descendants(of: page.view).compactMap { $0 as? UKBrightnessTileView }.map { $0.convert($0.bounds, to: page.view) }
        XCTAssertEqual(before, after, "no reflow when the lights arrive")
    }

    func testMissingCameraTilesAreStillDrawnAndKeepTheirPlace() throws {
        let entities = storeLackingTheHouse()
        var context = UKGalleryChrome.context(store: entities, caller: GalleryServiceRecorder(store: entities))
        context.valuesPending = false
        let page = UKHomeViewController(context: context, configuration: UKHomeConfiguration(parts: .cameras))
        let window = HostedPage.show(page, size: CGSize(width: 393, height: 1600))
        defer { window.isHidden = true }
        let tiles = HostedPage.descendants(of: page.view).compactMap { $0 as? UKCameraTileView }
        XCTAssertEqual(tiles.count, HomeConfig.cameras.count, "every configured camera has its tile")
        XCTAssertTrue(tiles.allSatisfy { !$0.isHidden && $0.alpha > 0 })
        let before = tiles.map { $0.convert($0.bounds, to: page.view) }
        entities.apply(HomeConfig.cameras.map { EntityState(entityId: $0.entityId, state: "idle") })
        HostedPage.wait(0.4)
        page.view.layoutIfNeeded()
        let after = HostedPage.descendants(of: page.view).compactMap { $0 as? UKCameraTileView }.map { $0.convert($0.bounds, to: page.view) }
        XCTAssertEqual(before, after, "no reflow when the cameras arrive")
    }

    func testMissingRowsKeepTheirTitlesAndStayPut() throws {
        let entities = storeLackingTheHouse()
        var context = UKGalleryChrome.context(store: entities, caller: GalleryServiceRecorder(store: entities))
        context.valuesPending = false
        let page = UKRoomOverviewViewController(context: context, kind: .lights)
        let window = HostedPage.show(page, size: CGSize(width: 393, height: 1600))
        defer { window.isHidden = true }
        let rows = HostedPage.descendants(of: page.view).compactMap { $0 as? UKGlassTileView }
        XCTAssertFalse(rows.isEmpty, "the room rows are drawn")
        XCTAssertTrue(rows.allSatisfy { !$0.isHidden })
        let before = rows.map { $0.convert($0.bounds, to: page.view) }
        entities.apply(RoomOverview.groups(.lights).compactMap(\.entityId).map { EntityState(entityId: $0, state: "off") })
        HostedPage.wait(0.4)
        page.view.layoutIfNeeded()
        let after = HostedPage.descendants(of: page.view).compactMap { $0 as? UKGlassTileView }.map { $0.convert($0.bounds, to: page.view) }
        XCTAssertEqual(before, after, "no reflow when the entities arrive")
    }

    // MARK: - Rule 14: which pages are gated

    func testEveryLayoutDrivenPageOptsIntoTheGate() throws {
        let context = UKGalleryChrome.context()
        XCTAssertEqual(UKHomeViewController(context: context).houseLayoutSkeleton, .home)
        XCTAssertEqual(UKHouseholdColumnPage(context: context, title: "Household").houseLayoutSkeleton, .page)
        XCTAssertEqual(UKRoomOverviewViewController(context: context, kind: .lights).houseLayoutSkeleton, .page)
        XCTAssertEqual(UKCustomLightsViewController(context: context).houseLayoutSkeleton, .page)
        let signedIn = try FeatureHost.signedIn()
        let todo = try XCTUnwrap(UKScreens.groceryList(signedIn.context) as? UKTodoPageViewController)
        XCTAssertEqual(todo.houseLayoutSkeleton, .page, "Chores")
        XCTAssertNil(UKStatePageViewController(title: "x", state: UKStateMessageView(symbol: "house", title: "x")).houseLayoutSkeleton,
                     "navigation chrome and state pages never depend on the document")
    }

    // MARK: - Cold launch with a saved layout

    func testAColdLaunchWithASavedLayoutNeverDrawsASkeleton() throws {
        let store = try rig.makeStore(cached: (DemoHouse.config, "saved"), loadsCacheSynchronously: true)
        let page = home(store: store)
        let window = HostedPage.show(page)
        defer { window.isHidden = true }
        XCTAssertFalse(has("home.skeleton", in: page), "the saved layout was there before the page built")
        XCTAssertEqual(page.contentView.alpha, 1)
        XCTAssertTrue(page.contentView.layer.animationKeys()?.isEmpty ?? true, "nothing animates the content")
    }
}
