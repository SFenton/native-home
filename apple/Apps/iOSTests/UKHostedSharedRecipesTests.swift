import HassCore
import UIKit
import XCTest
@testable import HassUI

/// An open recipe follows the window: a sheet while the window is narrow, a pane beside the grid once it can split, a sheet again
/// when it narrows, and closing the sheet closes the recipe.
@MainActor
final class UKHostedSharedRecipesTests: DemoHouseTestCase {
    func testAnOpenRecipeMovesBetweenSheetAndPaneAsTheWindowResizes() async throws {
        let service = FixtureRecipeService(delay: .milliseconds(10))
        let context = UKGalleryChrome.context(store: FoodFixtures.store())
        let page = UKRecipesViewController(context: context, models: FoodModels(service: service), selected: FoodFixtures.catalog[0])
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context), size: HostedPage.inScene(CGSize(width: 393, height: 852)))
        defer { window.isHidden = true }
        await FeatureHost.settleAsync(1.2)
        let sheet = try XCTUnwrap(page.shownSheet, "a narrow window shows the recipe as a sheet")
        XCTAssertNotNil(FeatureHost.view("recipe.tabs", in: sheet.view))

        window.frame = CGRect(origin: .zero, size: HostedPage.splitSize)  // as far inside the scene as a split allows (HostedPage.splitSize)
        window.rootViewController?.traitOverrides.horizontalSizeClass = .regular
        window.rootViewController?.view.setNeedsLayout()
        window.layoutIfNeeded()
        await FeatureHost.settleAsync(1.0)
        XCTAssertTrue(HostedPage.until(6) { page.shownSheet == nil && FeatureHost.view("recipe.tabs", in: page.view) != nil },
                      "a wide window moves the recipe into the pane beside the grid (class \(page.traitCollection.horizontalSizeClass.rawValue), window \(window.bounds.size), sheet \(String(describing: page.shownSheet.map { type(of: $0) })), pane \(FeatureHost.view("recipe.pane", in: page.view) != nil), tabs \(FeatureHost.view("recipe.tabs", in: page.view) != nil), page \(page.view.bounds.size))")

        window.frame = CGRect(origin: .zero, size: HostedPage.inScene(CGSize(width: 393, height: 852)))
        window.rootViewController?.traitOverrides.horizontalSizeClass = .compact
        window.rootViewController?.view.setNeedsLayout()
        window.layoutIfNeeded()
        await FeatureHost.settleAsync(1.0)
        XCTAssertTrue(HostedPage.until(6) { page.shownSheet != nil }, "narrowing moves it back to a sheet")

        let reopened = try XCTUnwrap(page.shownSheet)
        XCTAssertTrue(FeatureHost.press("recipe.done", in: reopened.view) || FeatureHost.tapRow("recipe.done", in: reopened.view), "Done is on the sheet")
        await FeatureHost.settleAsync(0.8)
        XCTAssertTrue(HostedPage.until(6) { page.shownSheet == nil && FeatureHost.view("recipe.tabs", in: page.view) == nil },
                      "closing the sheet closes the recipe")
    }
}
