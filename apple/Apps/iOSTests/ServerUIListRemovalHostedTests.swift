@testable import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - Food removals through the generic record list

/// A Food delete through the real record views: the swiped row stays open under the confirmation, cancel closes it, confirm lets it
/// leave with the list animation (a fade under Reduce Motion), "<item> deleted" is announced, the neighbour's card corner is redrawn,
/// a removal from another device animates without an announcement, and the first apply and a reconnect never animate. They run
/// unchanged at the widths of iPhone, iPhone Duo (folded and unfolded) and iPad. Pattern: `.agents/patterns/list-row-removal.md`.
@MainActor
final class ServerUIListRemovalHostedTests: XCTestCase {
    override func tearDown() async throws {
        UKListAnnouncements.sink = nil
        UKMotion.reduceMotionOverride = nil
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private static let sizes = [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678),
                                CGSize(width: 744, height: 1133), CGSize(width: 1024, height: 768)]

    private struct Rig {
        let server: EverShelfFixtureServer
        let model: InventoryListModel
        let source: UKServerUIInventoryCollection
        let store: EntityStore
        let page: UKServerUIPage
        let collection: UKServerUICollectionView
        let controller: UKRecordCollectionController
        let window: UIWindow
    }

    private func fixture() throws -> JSONValue {
        var root = try ServerUIRendererFixture.json()
        let component: JSONValue = .object(["id": "record-list", "title": "Food", "type": "collection", "layout": .object(["span": .number(1)]),
            "props": .object(["providerId": "demo-items", "template": "inventory", "loadingText": "Loading Food", "emptyText": "No Food"])])
        root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components", to: .array([component]))
        root = try ServerUIRendererFixture.changing(root, path: "/document/navigation/chrome/groups/1/items/0/priority", to: .string("normal"))
        let capabilities = ServerUICompositionPublication.firstSliceCapabilities.filter { $0 != "sh.grid@1" } + ["sh.collection@1"]
        return try ServerUIRendererFixture.changing(root, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
    }

    /// A pantry with three single-unit cards, shown as the page's one scroller.
    private func rig(_ size: CGSize) async throws -> Rig {
        let server = EverShelfFixtureServer(rows: [
            .init(id: 1, name: "Honey", quantity: 1, location: .pantry, expiryDate: nil, productId: 1),
            .init(id: 2, name: "Spaghetti", quantity: 1, location: .pantry, expiryDate: nil, productId: 2),
            .init(id: 3, name: "Rice", quantity: 1, location: .pantry, expiryDate: nil, productId: 3),
        ])
        let model = InventoryListModel(space: .pantry, client: EverShelfClient(caller: server))
        await model.load()
        let provider = try InventoryCompositionProvider(sourceID: "demo-items", space: .pantry, model: model)
        let source = UKServerUIInventoryCollection(provider)
        let store = EntityStore()
        let renderer = try UKServerUIRenderer(publication: ServerUIRendererFixture.publication(fixture()),
            context: UKContext(store: store), backdrop: ServerUIRendererFixture.backdrop(),
            records: UKServerUIRecords(collections: ["demo-items": source]))
        let window = HostedPage.show(renderer, size: HostedPage.inScene(size))
        let page = try ServerUIRendererFixture.root(renderer)
        let collection = try XCTUnwrap(page.nodes["record-list"]?.view as? UKServerUICollectionView)
        let controller = try XCTUnwrap(collection.recordController)
        let shown = await HostedPage.settle { controller.visibleKeys.count == 3 }
        XCTAssertTrue(shown, "the three cards are drawn")
        return Rig(server: server, model: model, source: source, store: store, page: page, collection: collection, controller: controller, window: window)
    }

    private func deleteAction(_ rig: Rig, _ key: String) throws -> UIContextualAction {
        let configuration = try XCTUnwrap(rig.collection.recordSwipe(for: key, leading: false), "a single-unit card swipes to Delete")
        return try XCTUnwrap(configuration.actions.first { $0.title == "Delete" })
    }

    /// Runs the swipe's Delete the way UIKit does and returns what the swipe completion was told (nil until it is told).
    private func swipeDelete(_ rig: Rig, _ key: String, completion: @escaping (Bool) -> Void) throws {
        let action = try deleteAction(rig, key)
        action.handler(action, UIView(), completion)
    }

    private func keys(_ rig: Rig) -> [String] { rig.controller.visibleKeys }

    // MARK: Held swipe

    func testASwipedRowStaysOpenUnderTheQuestionAndCancelClosesItOnEveryFamily() async throws {
        for size in Self.sizes {
            let rig = try await rig(size)
            defer { rig.window.isHidden = true }
            var answered: Bool?
            try swipeDelete(rig, "honey") { answered = $0 }
            let alert = try XCTUnwrap(FeatureHost.alert(on: rig.page), "width \(size.width): Delete asks first")
            XCTAssertNil(answered, "the swipe is held open while the question is up")
            XCTAssertEqual(alert.title, "Delete Honey?")
            XCTAssertTrue(FeatureHost.answer(alert, "Cancel"))
            XCTAssertEqual(answered, false, "cancel closes the swipe and the row stays")
            XCTAssertTrue(keys(rig).contains("honey"))
            XCTAssertTrue(rig.model.pendingRemoval.isEmpty)
            HostedPage.hideTracked()
        }
    }

    func testConfirmingLetsTheRowLeaveAnnouncedAndRedrawsTheNeighbourCornerOnEveryFamily() async throws {
        for size in Self.sizes {
            let rig = try await rig(size)
            defer { rig.window.isHidden = true }
            var announced: [String] = []
            UKListAnnouncements.sink = { announced.append($0) }
            let order = keys(rig)
            let last = try XCTUnwrap(order.last)
            let before = try XCTUnwrap(order.dropLast().last)
            var answered: Bool?
            try swipeDelete(rig, last) { answered = $0 }
            let alert = try XCTUnwrap(FeatureHost.alert(on: rig.page))
            XCTAssertTrue(FeatureHost.answer(alert, "Delete Item"))
            let gone = await HostedPage.settle { !self.keys(rig).contains(last) && answered != nil }
            XCTAssertTrue(gone, "width \(size.width): the card leaves the list")
            XCTAssertEqual(answered, true, "confirm completes the swipe as the row leaves")
            XCTAssertEqual(rig.controller.lastPlan?.transition, .animate, "it leaves with the list animation")
            XCTAssertEqual(rig.controller.lastPlan?.removedByPerson, true)
            XCTAssertEqual(announced.count, 1)
            XCTAssertTrue(announced.first?.hasSuffix(" deleted") == true, "VoiceOver hears the removal: \(announced)")
            let neighbour = try XCTUnwrap(rig.controller.collectionView.cellForItem(at: IndexPath(item: keys(rig).firstIndex(of: before) ?? 0, section: 0)))
            let corners = try XCTUnwrap(neighbour.backgroundView as? UKModuleRowBackgroundView).layer.maskedCorners
            XCTAssertTrue(corners.contains([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]), "the new last row rounds its bottom corners")
            HostedPage.hideTracked()
        }
    }

    func testAFailedDeleteBringsTheCardBackWithoutAnnouncingIt() async throws {
        let rig = try await rig(Self.sizes[0])
        defer { rig.window.isHidden = true }
        var announced: [String] = []
        UKListAnnouncements.sink = { announced.append($0) }
        rig.server.failing = ["evershelf.delete_inventory"]
        var answered: Bool?
        try swipeDelete(rig, "honey") { answered = $0 }
        XCTAssertTrue(FeatureHost.answer(try XCTUnwrap(FeatureHost.alert(on: rig.page)), "Delete Item"))
        let back = await HostedPage.settle { answered != nil && rig.model.rowErrors["honey"] != nil && self.keys(rig).contains("honey") }
        XCTAssertTrue(back, "the refused delete restores the card")
        XCTAssertFalse(announced.contains { $0.hasPrefix("Honey") } && !self.keys(rig).contains("honey"))
    }

    // MARK: Motion rules

    func testARemovalFromAnotherDeviceAnimatesWithoutAnAnnouncement() async throws {
        let rig = try await rig(Self.sizes[0])
        defer { rig.window.isHidden = true }
        var announced: [String] = []
        UKListAnnouncements.sink = { announced.append($0) }
        XCTAssertEqual(rig.controller.lastPlan?.transition, ListUpdateTransition.none, "the first apply never animates")
        rig.server.rows.removeAll { $0.name == "Spaghetti" }
        await rig.model.load()
        let gone = await HostedPage.settle { !self.keys(rig).contains("spaghetti") }
        XCTAssertTrue(gone)
        XCTAssertEqual(rig.controller.lastPlan?.transition, .animate, "a remote removal on screen animates")
        XCTAssertEqual(rig.controller.lastPlan?.removedByPerson, false)
        XCTAssertTrue(announced.isEmpty, "nobody did it here, so nothing is announced")
    }

    func testAReconnectNeverAnimatesARemoval() async throws {
        let rig = try await rig(Self.sizes[0])
        defer { rig.window.isHidden = true }
        rig.store.noteReapply()
        rig.server.rows.removeAll { $0.name == "Rice" }
        await rig.model.load()
        let gone = await HostedPage.settle { !self.keys(rig).contains("rice") }
        XCTAssertTrue(gone)
        XCTAssertEqual(rig.controller.lastPlan?.transition, ListUpdateTransition.none, "state handed back as a whole is a reapply, not a removal")
    }

    func testReduceMotionFadesTheLeavingRowInsteadOfSlidingIt() async throws {
        UKMotion.reduceMotionOverride = true
        let rig = try await rig(Self.sizes[3])
        defer { rig.window.isHidden = true }
        rig.server.rows.removeAll { $0.name == "Honey" }
        await rig.model.load()
        let gone = await HostedPage.settle { !self.keys(rig).contains("honey") }
        XCTAssertTrue(gone)
        XCTAssertEqual(rig.controller.lastPlan?.transition, .fade, "Reduce Motion cross-fades; nothing slides")
    }

    // MARK: Accessibility

    func testDeleteIsOfferedToVoiceOverAsASwipeActionWithItsOwnLabelOnEveryFamily() async throws {
        for size in Self.sizes {
            let rig = try await rig(size)
            defer { rig.window.isHidden = true }
            let action = try deleteAction(rig, "honey")
            XCTAssertEqual(action.style, .destructive, "width \(size.width): Delete is the destructive swipe action")
            XCTAssertEqual(action.title, "Delete", "VoiceOver reads it as a custom action named Delete")
            XCTAssertNotNil(action.image)
            HostedPage.hideTracked()
        }
    }
}
