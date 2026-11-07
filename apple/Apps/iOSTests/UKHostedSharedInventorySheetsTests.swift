import HassCore
import UIKit
import XCTest
@testable import HassUI

/// Sort and filter on the pantry list: nothing changes until Apply, Apply changes the list's order or filter, and Reset puts the
/// defaults back.
@MainActor
final class UKHostedSharedInventorySheetsTests: DemoHouseTestCase {
    private func pantry() -> (UKInventoryViewController, InventoryListModel, UIWindow) {
        let server = EverShelfFixtureServer.sample()
        server.latency = .milliseconds(20)
        let models = InventoryModels(client: EverShelfClient(caller: server))
        let model = models.model(for: .pantry)
        let context = UKGalleryChrome.context()
        let page = UKInventoryViewController(context: context, model: model, models: models, launch: nil)
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context), size: CGSize(width: 393, height: 2200))
        FeatureHost.settle(0.8)
        return (page, model, window)
    }

    private func openSheet(_ fab: String, on page: UKInventoryViewController) throws -> UIViewController {
        XCTAssertTrue(FeatureHost.press(fab, in: page.view))
        FeatureHost.settle(0.8)
        return try XCTUnwrap(page.shownSheet)
    }

    func testSortAppliesTheChosenModeAndDirectionAndResetRestoresTitleAscending() throws {
        let (page, model, window) = pantry()
        defer { window.isHidden = true }
        var sheet = try openSheet("fab.inventory.sort", on: page)
        XCTAssertTrue(FeatureHost.tapRow("inventory.sort.expiry", in: sheet.view))
        XCTAssertTrue(FeatureHost.tapRow("inventory.sort.direction.descending", in: sheet.view))
        FeatureHost.settle(0.3)
        XCTAssertEqual(model.sortMode, .title, "choosing does not sort until Apply")
        XCTAssertTrue(FeatureHost.press("filterSheet.apply", in: sheet.view))
        FeatureHost.settle(0.6)
        XCTAssertEqual(model.sortMode, .expiry)
        XCTAssertEqual(model.sortDirection, .descending)
        XCTAssertTrue(model.sortActive)

        sheet = try openSheet("fab.inventory.sort", on: page)
        XCTAssertNotNil(FeatureHost.reveal("filterSheet.reset", in: sheet.view), "a non-default sort offers Reset")
        XCTAssertTrue(FeatureHost.tapRow("filterSheet.reset", in: sheet.view) || FeatureHost.press("filterSheet.reset", in: sheet.view))
        FeatureHost.settle(0.3)
        XCTAssertTrue(FeatureHost.press("filterSheet.apply", in: sheet.view))
        FeatureHost.settle(0.6)
        XCTAssertEqual(model.sortMode, .title)
        XCTAssertEqual(model.sortDirection, .ascending)
        XCTAssertFalse(model.sortActive)
    }

    func testFilterAppliesTheChosenStatusAndResetShowsEverythingAgain() throws {
        let (page, model, window) = pantry()
        defer { window.isHidden = true }
        var sheet = try openSheet("fab.inventory.filter", on: page)
        XCTAssertTrue(FeatureHost.tapRow("inventory.filter.expired", in: sheet.view))
        FeatureHost.settle(0.3)
        XCTAssertEqual(model.filterMode, .all, "choosing does not filter until Apply")
        XCTAssertTrue(FeatureHost.press("filterSheet.apply", in: sheet.view))
        FeatureHost.settle(0.6)
        XCTAssertEqual(model.filterMode, .expired)

        sheet = try openSheet("fab.inventory.filter", on: page)
        XCTAssertNotNil(FeatureHost.reveal("filterSheet.reset", in: sheet.view))
        XCTAssertTrue(FeatureHost.tapRow("filterSheet.reset", in: sheet.view) || FeatureHost.press("filterSheet.reset", in: sheet.view))
        FeatureHost.settle(0.3)
        XCTAssertTrue(FeatureHost.press("filterSheet.apply", in: sheet.view))
        FeatureHost.settle(0.6)
        XCTAssertEqual(model.filterMode, .all)
    }
}
