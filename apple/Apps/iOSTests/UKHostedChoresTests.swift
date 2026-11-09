import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// Chores, Groceries and To-Do on the gallery's fixture lists with a recording service: what each page lists, what a check-off and an
/// Add do, and the add/edit forms' validation.
@MainActor
final class UKHostedChoresTests: DemoHouseTestCase {
    private struct Screen {
        let page: UKTodoPageViewController
        let service: ChoresFixtureService
        let model: ChoresModel
        let host: UIViewController
        let window: UIWindow
        let context: UKContext
    }

    private func screen(_ pageId: String, viewer: ChoresConfig.Resident = .resident1, empty: Bool = false) async -> Screen {
        guard let choresPage = ChoresConfig.page(pageId) else { preconditionFailure("the demo house has no \(pageId) page") }
        let store = EntityStore()
        let service = ChoresFixtureService(store: store, lists: empty ? [:] : ChoresFixtures.lists())
        store.replaceAll(service.entityStates())
        let model = ChoresModel(service: service, todos: TodoStore(service: service), viewerUserId: viewer.haUserId)
        let context = UKGalleryChrome.context(store: store)
        let page = pageId == "chores"
            ? UKChoresPages.root(context: context, model: model)
            : UKChoresPages.page(choresPage, context: context, model: model)
        let host = UKGalleryChrome.wrap(page, context: context)
        let window = HostedPage.show(host, size: CGSize(width: 393, height: 2400))
        await FeatureHost.settleAsync(0.8)
        return Screen(page: page, service: service, model: model, host: host, window: window, context: context)
    }

    // MARK: Pages

    func testEveryPageShowsItsListOrItsEmptyState() async {
        for page in ChoresConfig.pages {
            let s = await screen(page.id)
            defer { s.window.isHidden = true }
            XCTAssertNotNil(FeatureHost.view("todo.page.\(page.id)", in: s.page.view), "\(page.id) shows its list")
            XCTAssertNotNil(FeatureHost.view("fab.add", in: s.page.view), "\(page.id) offers Add")
        }
    }

    func testTheChoresTabListsQuickLinksAndTheViewersChores() async {
        let s = await screen("chores")
        defer { s.window.isHidden = true }
        let ids = FeatureHost.identifiers(in: s.page.view)
        XCTAssertTrue(ids.contains { $0.contains("quick") || $0.contains("chores") || $0.contains("groceries") }, "quick links are in the header: \(ids.sorted().prefix(20))")
        XCTAssertTrue(HostedPage.labels(in: s.page.view).contains("Take out the recycling"), "Alex's overdue chore is listed")
    }

    func testASecondResidentSeesTheirOwnChores() async {
        let s = await screen("chores", viewer: .resident2)
        defer { s.window.isHidden = true }
        let labels = HostedPage.labels(in: s.page.view)
        XCTAssertTrue(labels.contains("Fold laundry"), "Sam's own chore is listed: \(labels)")
        XCTAssertFalse(labels.contains("Take out the recycling"), "Alex's chore is not")
    }

    func testAnEmptyHouseSaysSo() async {
        let s = await screen("groceries", empty: true)
        defer { s.window.isHidden = true }
        XCTAssertNotNil(FeatureHost.view("todo.empty", in: s.page.view), "an empty list explains itself")
    }

    func testAQuickLinkPushesThatPageInTheGallery() async throws {
        let s = await screen("chores")
        defer { s.window.isHidden = true }
        s.page.openQuickLink(try demoChoresPage("groceries"))
        await FeatureHost.settleAsync(0.8)
        XCTAssertEqual(s.page.navigationController?.viewControllers.count, 2)
        XCTAssertNotNil(FeatureHost.view("todo.page.groceries", in: s.page.navigationController!.topViewController!.view))
    }

    // MARK: Check-off

    func testCheckingAGroceryItemOffCallsTheList() async throws {
        let s = await screen("groceries")
        defer { s.window.isHidden = true }
        let identity = try XCTUnwrap(FeatureHost.identifiers(in: s.page.view).first { $0.hasPrefix("todo.item.") }, "an item is listed")
        XCTAssertTrue(FeatureHost.press(identity, in: s.page.view))
        await FeatureHost.settleAsync(0.8)
        XCTAssertTrue(s.service.lastCall.hasPrefix("todo.update_item"), "checking it off calls Home Assistant: \(s.service.lastCall)")
    }

    func testARowOffersItsActionsInAContextMenu() async throws {
        let s = await screen("groceries")
        defer { s.window.isHidden = true }
        let list = try XCTUnwrap(FeatureHost.view("todo.page.groceries", in: s.page.view) as? UICollectionView)
        let path = try XCTUnwrap(list.indexPathsForVisibleItems.sorted().first { list.cellForItem(at: $0) is UKTodoRowCell })
        let configuration = s.page.collectionView(list, contextMenuConfigurationForItemAt: path, point: .zero)
        XCTAssertNotNil(configuration)
        XCTAssertFalse(s.page.collectionView(list, shouldSelectItemAt: path), "rows are not selectable; their controls act")
        XCTAssertFalse(s.page.collectionView(list, shouldHighlightItemAt: path))
    }

    // MARK: Add forms

    func testAddOnGroceriesOpensAFormThatAddsTheItem() async throws {
        let s = await screen("groceries")
        defer { s.window.isHidden = true }
        XCTAssertTrue(FeatureHost.press("fab.add", in: s.page.view))
        await FeatureHost.settleAsync(0.8)
        let modal = try XCTUnwrap(s.page.shownSheet as? UKHassModalController, "Add opens a sheet")
        let form = try XCTUnwrap(modal.viewControllers.first as? UKAddGroceryItemController)
        XCTAssertFalse(try XCTUnwrap(form.navigationItem.rightBarButtonItem).isEnabled, "Add is off until something is typed")
        let field = try XCTUnwrap(FeatureHost.view("grocery.item", in: form.view) as? UITextField)
        field.text = "Bananas"
        field.sendActions(for: .editingChanged)
        await FeatureHost.settleAsync(0.3)
        XCTAssertTrue(try XCTUnwrap(form.navigationItem.rightBarButtonItem).isEnabled)
        form.confirmTapped()
        await FeatureHost.settleAsync(0.8)
        XCTAssertEqual(s.service.lastCall, "todo.add_item Bananas")
    }

    func testAddOnChoresOpensTheTaskFormWithValidation() async throws {
        let s = await screen("alexs-chores")
        defer { s.window.isHidden = true }
        XCTAssertTrue(FeatureHost.press("fab.add", in: s.page.view))
        await FeatureHost.settleAsync(1.0)
        let modal = try XCTUnwrap(s.page.shownSheet as? UKHassModalController)
        let form = try XCTUnwrap(modal.viewControllers.first as? UKDonetickTaskViewController)
        XCTAssertEqual(form.title, "New Task")
        XCTAssertFalse(form.canConfirm, "a task needs a name")
        let name = try XCTUnwrap(FeatureHost.view("task.name", in: form.view) as? UITextField)
        name.text = "Wash the car"
        name.sendActions(for: .editingChanged)
        await FeatureHost.settleAsync(0.3)
        XCTAssertTrue(form.canConfirm)
        XCTAssertTrue(form.hasEdits)
        for id in ["task.assignee", "task.priority", "task.recurrence", "task.hasDueDate", "task.hasDueTime", "task.hideOnVacation"] {
            XCTAssertNotNil(FeatureHost.view(id, in: form.view), "\(id) is on the form")
        }
        XCTAssertTrue(FeatureHost.flip("task.hasDueDate", in: form.view))
        await FeatureHost.settleAsync(0.3)
        XCTAssertNotNil(FeatureHost.view("task.dueDate", in: form.view), "turning on Due Date shows the date")
        XCTAssertTrue(FeatureHost.flip("task.hasDueTime", in: form.view))
        await FeatureHost.settleAsync(0.3)
        XCTAssertNotNil(FeatureHost.view("task.dueTime", in: form.view))
    }

    func testAdminTodoAddFormValidatesItsTitle() async throws {
        let s = await screen("to-do")
        defer { s.window.isHidden = true }
        XCTAssertTrue(FeatureHost.press("fab.add", in: s.page.view))
        await FeatureHost.settleAsync(1.0)
        let modal = try XCTUnwrap(s.page.shownSheet as? UKHassModalController)
        let form = try XCTUnwrap(modal.viewControllers.first as? UKAddAdminTodoController)
        XCTAssertFalse(form.canConfirm)
        XCTAssertFalse(form.hasEdits)
        let sections = form.sections()
        XCTAssertFalse(sections.isEmpty)
    }

    func testEditingATaskLoadsItThenOffersSave() async throws {
        let s = await screen("alexs-chores")
        defer { s.window.isHidden = true }
        let target = DonetickEditTarget(itemUid: "11--fixture", taskId: 11, todoEntityId: ChoresConfig.page("alexs-chores")?.lists.first?.entityId ?? "")
        let form = UKDonetickTaskViewController(model: s.model, mode: .edit(target), connection: nil)
        let modal = UKHassModalController(root: form, options: UKHassModalOptions(title: "Edit Task"))
        s.page.present(modal, animated: false)
        await FeatureHost.settleAsync(1.5)
        XCTAssertEqual(form.title, "Edit Task")
        XCTAssertNotNil(FeatureHost.view("task.name", in: form.view), "the task loaded into the form")
        XCTAssertFalse(form.canConfirm, "Save is off until something changes")
        let name = try XCTUnwrap(FeatureHost.view("task.name", in: form.view) as? UITextField)
        name.text = (name.text ?? "") + " now"
        name.sendActions(for: .editingChanged)
        await FeatureHost.settleAsync(0.3)
        XCTAssertTrue(form.canConfirm)
        XCTAssertNotNil(FeatureHost.view("task.delete", in: form.view), "an existing task can be deleted")
    }

    func testRenamingAnAdminTodoNeedsADifferentTitle() async throws {
        let s = await screen("to-do")
        defer { s.window.isHidden = true }
        let target = AdminTodoEditTarget(itemUid: "a1", originalTitle: "Port the Chores page", todoEntityId: ChoresConfig.adminTodoEntityId)
        let form = UKRenameTodoItemController(model: s.model, target: target)
        let modal = UKHassModalController(root: form, options: UKHassModalOptions(title: "Rename"))
        s.page.present(modal, animated: false)
        await FeatureHost.settleAsync(0.8)
        XCTAssertFalse(form.canConfirm, "unchanged title cannot be saved")
        XCTAssertFalse(form.sections().isEmpty)
    }

    // MARK: Large text in a short window

    /// At AX5 in the folded Duo's page size (382 by 678 pt, beside the vertical bar) the Quick Links take more than the window, and the
    /// chores below them are still reached by scrolling: the list scrolls and its last row is built at the end.
    func testAtAX5InAShortWindowTheListScrollsToItsLastChore() async throws {
        let s = await screen("chores")
        defer { s.window.isHidden = true }
        s.window.frame = CGRect(origin: .zero, size: HostedPage.inScene(CGSize(width: 382, height: 678)))
        s.host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        await FeatureHost.settleAsync(0.8)
        let list = try XCTUnwrap(FeatureHost.view("todo.page.chores", in: s.page.view) as? UICollectionView)
        list.layoutIfNeeded()
        XCTAssertTrue(list.isScrollEnabled, "the list scrolls")
        // A drag that starts on a Quick Links tile must reach the list's pan (a tile fills the window at AX5).
        let tile = try XCTUnwrap(HostedPage.descendants(of: list).first { $0 is UKGlassTileView && $0.window != nil && !$0.isHidden })
        let point = tile.convert(CGPoint(x: tile.bounds.midX, y: min(tile.bounds.midY, 40)), to: list)
        let hit = try XCTUnwrap(list.hitTest(point, with: nil), "a point on the tile hits something")
        XCTAssertTrue(hit.isDescendant(of: list), "the tile under the finger is inside the list")
        XCTAssertTrue(list.canCancelContentTouches && list.touchesShouldCancel(in: hit), "the list takes a drag from \(type(of: hit))")
        let visible = list.bounds.height - list.adjustedContentInset.top - list.adjustedContentInset.bottom
        XCTAssertGreaterThan(list.contentSize.height, visible, "the list is taller than the window at AX5: \(list.contentSize) in \(list.bounds.size)")
        // Scroll to the end the way a drag does, a window at a time, so the rows are built as they come in.
        var rounds = 0
        while rounds < 60 {
            let end = list.contentSize.height + list.adjustedContentInset.bottom - list.bounds.height
            guard list.contentOffset.y < end - 1 else { break }
            list.setContentOffset(CGPoint(x: 0, y: min(end, list.contentOffset.y + list.bounds.height * 0.6)), animated: false)
            list.layoutIfNeeded()
            rounds += 1
        }
        await FeatureHost.settleAsync(0.3)
        let rows = FeatureHost.identifiers(in: list).filter { $0.hasPrefix("todo.item.") }
        XCTAssertTrue(rows.contains("todo.item.15--fixture"), "the last chore is built at the end of the list; saw \(rows)")
    }
}

