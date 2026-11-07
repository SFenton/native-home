import HassCore
import UIKit
import XCTest
@testable import HassUI

/// A Chores page opening a quick link where there is no shell: the link is a plain push of that page.
@MainActor
final class UKHostedChoresLinksTests: DemoHouseTestCase {
    func testAQuickLinkPushesItsPageWhenThereIsNoShellToShowColumns() async throws {
        let store = EntityStore()
        let service = ChoresFixtureService(store: store, lists: ChoresFixtures.lists())
        store.replaceAll(service.entityStates())
        let model = ChoresModel(service: service, todos: TodoStore(service: service), viewerUserId: ChoresConfig.Resident.resident1.haUserId)
        let context = UKGalleryChrome.context(store: store)
        let page = try XCTUnwrap(UKChoresPages.page(try demoChoresPage("groceries"), context: context, model: model) as? UKTodoPageViewController)
        let nav = UINavigationController(rootViewController: page)
        let window = HostedPage.show(nav, size: CGSize(width: 393, height: 1200))
        defer { window.isHidden = true }
        await FeatureHost.settleAsync(0.6)
        XCTAssertEqual(nav.viewControllers.count, 1)
        page.openQuickLink(try demoChoresPage("to-do"))
        await FeatureHost.settleAsync(0.8)
        XCTAssertEqual(nav.viewControllers.count, 2, "the link's page is pushed")
        XCTAssertTrue(nav.topViewController is UKTodoPageViewController)
    }
}
