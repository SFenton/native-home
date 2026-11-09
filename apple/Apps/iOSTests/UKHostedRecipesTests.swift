import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// The Recipes page beyond its first screen: applying sort and filters, resetting them, and an open recipe in the split pane
/// versus the sheet.
@MainActor
final class UKHostedRecipesTests: DemoHouseTestCase {
    private func recipes(wide: Bool = false) async -> (UKRecipesViewController, FixtureRecipeService, UIWindow) {
        let service = FixtureRecipeService(delay: .milliseconds(20))
        let context = UKGalleryChrome.context(store: FoodFixtures.store())
        let page = UKRecipesViewController(context: context, models: FoodModels(service: service))
        let host = UKGalleryChrome.wrap(page, context: context)
        let window: UIWindow
        if wide {
            let root = UIViewController()
            root.addChild(host)
            host.view.frame = root.view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            root.view.addSubview(host.view)
            host.didMove(toParent: root)
            root.setOverrideTraitCollection(UITraitCollection(horizontalSizeClass: .regular), forChild: host)
            window = HostedPage.show(root, size: HostedPage.splitSize)
        } else {
            window = HostedPage.show(host, size: CGSize(width: 393, height: 2200))
        }
        await FeatureHost.settleAsync(0.8)
        return (page, service, window)
    }

    func testPickingASortAppliesItOnlyWhenConfirmed() async throws {
        let (page, service, window) = await recipes()
        defer { window.isHidden = true }
        XCTAssertTrue(FeatureHost.press("fab.sort", in: page.view))
        await FeatureHost.settleAsync(0.8)
        let sheet = try XCTUnwrap(page.shownSheet)
        XCTAssertTrue(FeatureHost.tapRow("recipes.sort.\(RecipeSort.alphabetical.rawValue)", in: sheet.view))
        await FeatureHost.settleAsync(0.3)
        XCTAssertFalse(service.calls.contains { $0.contains("sort=alphabetical") }, "choosing does not search until Apply")
        XCTAssertTrue(FeatureHost.press("filterSheet.apply", in: sheet.view), "Apply is on the sheet")
        await FeatureHost.settleAsync(1.0)
        XCTAssertTrue(service.calls.contains { $0.contains("sort=alphabetical") }, "the new order is requested: \(service.calls)")
        XCTAssertTrue(HostedPage.labels(in: page.view).contains { $0.contains("Alphabetical") || $0.contains("Sorted by") }, "the grid names its order")
    }

    func testResettingTheSortGoesBackToAvailability() async throws {
        let (page, service, window) = await recipes()
        defer { window.isHidden = true }
        XCTAssertTrue(FeatureHost.press("fab.sort", in: page.view))
        await FeatureHost.settleAsync(0.8)
        var sheet = try XCTUnwrap(page.shownSheet)
        XCTAssertTrue(FeatureHost.tapRow("recipes.sort.\(RecipeSort.expiry.rawValue)", in: sheet.view))
        XCTAssertTrue(FeatureHost.press("filterSheet.apply", in: sheet.view))
        await FeatureHost.settleAsync(0.8)
        XCTAssertTrue(service.calls.contains { $0.contains("sort=\(RecipeSort.expiry.rawValue)") })
        XCTAssertTrue(FeatureHost.press("fab.sort", in: page.view))
        await FeatureHost.settleAsync(0.8)
        sheet = try XCTUnwrap(page.shownSheet)
        XCTAssertNotNil(FeatureHost.view("filterSheet.reset", in: sheet.view), "a non-default sort offers Reset")
        XCTAssertTrue(FeatureHost.tapRow("filterSheet.reset", in: sheet.view) || FeatureHost.press("filterSheet.reset", in: sheet.view))
        await FeatureHost.settleAsync(0.4)
        XCTAssertTrue(FeatureHost.press("filterSheet.apply", in: sheet.view))
        await FeatureHost.settleAsync(0.8)
        XCTAssertTrue(service.calls.last { $0.contains("kind=browse") }?.contains("sort=\(RecipeSort.availability.rawValue)") == true, "\(service.calls.suffix(3))")
    }

    func testTheExpiringFilterNarrowsTheSearchAndCanBeReset() async throws {
        let (page, _, window) = await recipes()
        defer { window.isHidden = true }
        XCTAssertTrue(FeatureHost.press("fab.filter", in: page.view))
        await FeatureHost.settleAsync(0.8)
        var sheet = try XCTUnwrap(page.shownSheet)
        XCTAssertTrue(FeatureHost.flip("recipes.filter.expiringOnly", in: sheet.view), "Expiring Ingredients Only is a switch")
        await FeatureHost.settleAsync(0.8)
        XCTAssertNotNil(FeatureHost.reveal("filterSheet.reset", in: sheet.view), "a changed draft can be reset")
        XCTAssertTrue(FeatureHost.press("filterSheet.apply", in: sheet.view))
        await FeatureHost.settleAsync(1.0)
        XCTAssertTrue(FeatureHost.press("fab.filter", in: page.view))
        await FeatureHost.settleAsync(0.8)
        sheet = try XCTUnwrap(page.shownSheet)
        XCTAssertTrue(FeatureHost.switchView("recipes.filter.expiringOnly", in: sheet.view)?.isOn == true, "the applied filter is remembered")
        XCTAssertTrue(FeatureHost.press("filterSheet.reset", in: sheet.view) || FeatureHost.tapRow("filterSheet.reset", in: sheet.view))
        await FeatureHost.settleAsync(0.3)
        XCTAssertTrue(FeatureHost.switchView("recipes.filter.expiringOnly", in: sheet.view)?.isOn == false, "Reset puts the defaults back")
    }

    func testOnAWideWindowARecipeOpensBesideTheGridAndCloses() async throws {
        let (page, service, window) = await recipes(wide: true)
        defer { window.isHidden = true }
        let card = try XCTUnwrap(FeatureHost.identifiers(in: page.view).sorted().first { $0.hasPrefix("recipes.card.") })
        XCTAssertTrue(FeatureHost.press(card, in: page.view) || FeatureHost.tapRow(card, in: page.view))
        await FeatureHost.settleAsync(1.2)
        XCTAssertTrue(service.calls.contains { $0.hasPrefix("recipe_detail") })
        XCTAssertNotNil(FeatureHost.view("recipe.pane", in: page.view), "a split shows the recipe in the trailing pane")
        XCTAssertNil(page.presentedViewController, "and not as a sheet")
        XCTAssertTrue(FeatureHost.press("recipe.close", in: page.view))
        await FeatureHost.settleAsync(0.8)
        XCTAssertNil(FeatureHost.view("recipe.pane", in: page.view), "Close removes the pane")
    }

    func testOnANarrowWindowARecipeIsASheetThatClosesWhenDismissed() async throws {
        let (page, _, window) = await recipes()
        defer { window.isHidden = true }
        let card = try XCTUnwrap(FeatureHost.identifiers(in: page.view).sorted().first { $0.hasPrefix("recipes.card.") })
        XCTAssertTrue(FeatureHost.press(card, in: page.view) || FeatureHost.tapRow(card, in: page.view))
        await FeatureHost.settleAsync(1.2)
        let sheet = try XCTUnwrap(page.presentedViewController)
        XCTAssertNotNil(FeatureHost.view("recipe.tabs", in: sheet.view))
        sheet.dismiss(animated: false)
        await FeatureHost.settleAsync(0.6)
        XCTAssertNil(page.presentedViewController)
    }
}
