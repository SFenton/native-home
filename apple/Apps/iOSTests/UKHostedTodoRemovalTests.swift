import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// Deleting a row from a Chores page through its VoiceOver Delete action: groceries leave at once, task lists ask first. The delete runs in the
/// page's own code (the app's copy of HassCore), so the list follows it.
@MainActor
final class UKHostedTodoRemovalTests: DemoHouseTestCase {
    private struct Screen {
        let page: UKTodoPageViewController
        let service: ChoresFixtureService
        let list: UICollectionView
        let window: UIWindow
    }

    private func screen(_ pageId: String) async throws -> Screen {
        let choresPage = try XCTUnwrap(ChoresConfig.page(pageId), "the demo house has a \(pageId) page")
        let store = EntityStore()
        let service = ChoresFixtureService(store: store, lists: ChoresFixtures.lists())
        store.replaceAll(service.entityStates())
        let model = ChoresModel(service: service, todos: TodoStore(service: service), viewerUserId: ChoresConfig.Resident.resident1.haUserId)
        let context = UKGalleryChrome.context(store: store)
        let page = UKChoresPages.page(choresPage, context: context, model: model)
        let host = UKGalleryChrome.wrap(page, context: context)
        let window = HostedPage.show(host, size: CGSize(width: 393, height: 2400))
        await FeatureHost.settleAsync(0.8)
        let list = try XCTUnwrap(FeatureHost.view("todo.page.\(pageId)", in: page.view) as? UICollectionView)
        return Screen(page: page, service: service, list: list, window: window)
    }

    private func customActions(in view: UIView) -> [UIAccessibilityCustomAction] {
        (view.accessibilityCustomActions ?? []) + view.subviews.flatMap { customActions(in: $0) }
    }

    /// Performs the first row's VoiceOver Delete action (swipe is not discoverable, so the row offers Delete to VoiceOver too).
    private func deleteFirstRow(_ s: Screen) throws {
        let path = try XCTUnwrap(s.list.indexPathsForVisibleItems.sorted().first { s.list.cellForItem(at: $0) is UKTodoRowCell }, "a row is listed")
        let cell = try XCTUnwrap(s.list.cellForItem(at: path))
        let delete = try XCTUnwrap(customActions(in: cell).first { $0.name == "Delete" }, "the row offers Delete to VoiceOver")
        XCTAssertEqual(delete.actionHandler?(delete), true)
    }

    func testAGroceryItemLeavesAtOnceFromItsMenu() async throws {
        let s = try await screen("groceries")
        defer { s.window.isHidden = true }
        let before = s.list.numberOfItems(inSection: 0)
        try deleteFirstRow(s)
        await FeatureHost.settleAsync(until: { s.service.lastCall.hasPrefix("todo.remove_item") })
        XCTAssertTrue(s.service.lastCall.hasPrefix("todo.remove_item"), "no question first: \(s.service.lastCall)")
        await FeatureHost.settleAsync(until: { s.list.numberOfItems(inSection: 0) < before })
        XCTAssertLessThan(s.list.numberOfItems(inSection: 0), before, "the row left the list")
    }

    func testATaskAsksBeforeItIsDeleted() async throws {
        let s = try await screen("alexs-chores")
        defer { s.window.isHidden = true }
        try deleteFirstRow(s)
        await FeatureHost.settleAsync(until: { FeatureHost.alert(on: s.page) != nil })
        let confirm = try XCTUnwrap(FeatureHost.alert(on: s.page), "a task asks first")
        XCTAssertFalse(s.service.lastCall.hasPrefix("todo.remove_item"), "nothing is deleted before the answer")
        XCTAssertTrue(FeatureHost.answer(confirm, try XCTUnwrap(confirm.actions.first { $0.style == .destructive }?.title)))
        await FeatureHost.settleAsync(until: { s.service.lastCall.hasPrefix("todo.remove_item") })
        XCTAssertTrue(s.service.lastCall.hasPrefix("todo.remove_item"), "\(s.service.lastCall)")
    }
}
