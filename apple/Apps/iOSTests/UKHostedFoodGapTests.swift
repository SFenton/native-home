import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// A recipe service whose second page of results fails once, over the fixture catalog.
@MainActor
final class FlakyRecipeService: RecipeServing {
    let inner = FixtureRecipeService(delay: .milliseconds(10))
    var failNextPage = true
    private(set) var pageRequests = 0

    func recommendations(limit: Int) async throws -> [RecipeCard] { try await inner.recommendations(limit: limit) }
    func browse(_ criteria: RecipeBrowseCriteria, cursor: String?) async throws -> RecipeBrowsePage {
        if cursor != nil {
            pageRequests += 1
            if failNextPage { failNextPage = false; throw FixtureRecipeService.Failure() }
        }
        return try await inner.browse(criteria, cursor: cursor)
    }
    func hydrate(_ criteria: RecipeBrowseCriteria, searchId: String?) async throws -> RecipeHydration { try await inner.hydrate(criteria, searchId: searchId) }
    func detail(recipeId: Int) async throws -> RecipeDetail { try await inner.detail(recipeId: recipeId) }
    func addToGroceries(recipeId: Int, ingredients: [RecipeDetail.Ingredient], idempotencyKey: String) async throws -> RecipeGroceryResult {
        try await inner.addToGroceries(recipeId: recipeId, ingredients: ingredients, idempotencyKey: idempotencyKey)
    }
}

/// The Food hub in a window that splits (and the Recipes grid across a fold), plus the grid's failure footer and restored search.
@MainActor
final class UKHostedFoodGapTests: DemoHouseTestCase {
    private func inWideRoot(_ host: UIViewController, size: CGSize = CGSize(width: 1100, height: 800)) -> UIWindow {
        let root = UIViewController()
        root.addChild(host)
        host.view.frame = root.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.view.addSubview(host.view)
        host.didMove(toParent: root)
        root.setOverrideTraitCollection(UITraitCollection(horizontalSizeClass: .regular), forChild: host)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.traitOverrides.horizontalSizeClass = .regular
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.layoutIfNeeded()
        return window
    }

    private func hub(navigator: ShellNavigator?, routes: [ShellRoute] = []) async -> (UKFoodHubViewController, ShellNavigator?, UIWindow) {
        let service = FixtureRecipeService(delay: .milliseconds(10))
        let server = EverShelfFixtureServer.sample()
        server.latency = .milliseconds(10)
        var context = UKGalleryChrome.context(store: FoodFixtures.store())
        if let navigator {
            context.navigator = navigator
            context.section = .home
            for route in routes { navigator.append(route, in: .home) }
        }
        let page = UKFoodHubViewController(context: context, models: FoodModels(service: service), inventory: InventoryModels(client: EverShelfClient(caller: server)))
        let window = inWideRoot(UKGalleryChrome.wrap(page, context: context))
        await FeatureHost.settleAsync(0.5)
        // Under the shell the section's navigation controller flips the columns; stand in for it.
        if navigator != nil { page.columns.setWide(true) }
        await FeatureHost.settleAsync(1.0)
        return (page, navigator, window)
    }

    func testOnASplitWindowTheHubWaitsForASpaceThenAddsItsRoute() async throws {
        let navigator = ShellNavigator()
        let (page, _, window) = await hub(navigator: navigator, routes: [.home(.food)])
        defer { window.isHidden = true }
        XCTAssertTrue(page.columns.isWide, "an iPad-landscape window splits")
        XCTAssertNotNil(FeatureHost.view("food.pane.placeholder", in: page.view), "the right column invites a pick")
        let space = try XCTUnwrap(FeatureHost.identifiers(in: page.view).sorted().first { $0.hasPrefix("food.space.") })
        XCTAssertTrue(FeatureHost.press(space, in: page.view))
        await FeatureHost.settleAsync(0.5)
        XCTAssertEqual(navigator.routes(in: .home).count, 2, "the space is a route after the hub")
        // The shell hands the routes back: the space opens in the column.
        page.syncColumnRoutes(navigator.routes(in: .home).compactMap { $0 }, animated: false)
        await FeatureHost.settleAsync(1.0)
        XCTAssertNil(FeatureHost.view("food.pane.placeholder", in: page.view), "the prompt gives way to the space")
        XCTAssertTrue(FeatureHost.identifiers(in: page.view).contains { $0.hasPrefix("inventory.") || $0.hasPrefix("fab.inventory") }, "the inventory page is in the column")
        // Tapping the same space again changes nothing.
        let count = navigator.routes(in: .home).count
        FeatureHost.press(space, in: page.view)
        XCTAssertEqual(navigator.routes(in: .home).count, count)
    }

    func testAHubOpenedWithoutItsRouteStillOpensASpaceBesideIt() async throws {
        let navigator = ShellNavigator()
        let (page, _, window) = await hub(navigator: navigator)
        defer { window.isHidden = true }
        let space = try XCTUnwrap(FeatureHost.identifiers(in: page.view).sorted().first { $0.hasPrefix("food.space.") })
        XCTAssertTrue(FeatureHost.press(space, in: page.view))
        await FeatureHost.settleAsync(1.0)
        XCTAssertNil(FeatureHost.view("food.pane.placeholder", in: page.view), "the page opened in the column itself")
        XCTAssertTrue(navigator.routes(in: .home).isEmpty, "and no route was added")
    }

    func testRoutesThatAreNotASpaceShowAPlaceholder() async throws {
        let navigator = ShellNavigator()
        let (page, _, window) = await hub(navigator: navigator, routes: [.home(.food)])
        defer { window.isHidden = true }
        page.syncColumnRoutes([.home(.food), .foodSpace("not-a-space")], animated: false)
        await FeatureHost.settleAsync(0.8)
        XCTAssertNil(FeatureHost.view("food.pane.placeholder", in: page.view))
        page.syncColumnRoutes([.home(.food)], animated: false)
        await FeatureHost.settleAsync(0.8)
    }

    // MARK: Recipes

    private func recipes(service: any RecipeServing, wide: Bool = false, size: CGSize = CGSize(width: 393, height: 2200), prepare: (FoodModels) -> Void = { _ in }) async -> (UKRecipesViewController, FoodModels, UIWindow) {
        let context = UKGalleryChrome.context(store: FoodFixtures.store())
        let models = FoodModels(service: service)
        prepare(models)
        let page = UKRecipesViewController(context: context, models: models)
        let host = UKGalleryChrome.wrap(page, context: context)
        let window = wide ? inWideRoot(host, size: size) : HostedPage.show(host, size: size)
        await FeatureHost.settleAsync(1.0)
        return (page, models, window)
    }

    func testAFailedNextPageOffersTryAgainAndRetryLoadsIt() async throws {
        let service = FlakyRecipeService()
        let (page, models, window) = await recipes(service: service)
        defer { window.isHidden = true }
        models.collection.loadNextPage()
        await FeatureHost.settleAsync(0.8)
        XCTAssertTrue(models.collection.nextPageFailed)
        let retry = try XCTUnwrap(FeatureHost.reveal("recipes.nextPage.retry", in: page.view) as? UIButton, "the footer offers Try Again")
        XCTAssertTrue(HostedPage.labels(in: page.view).contains("Unable to load more recipes."))
        retry.sendActions(for: .touchUpInside)
        await FeatureHost.settleAsync(1.0)
        XCTAssertFalse(models.collection.nextPageFailed)
        XCTAssertEqual(service.pageRequests, 2, "the retry asked for the same page again")
    }

    func testASearchTypedBeforeTheGridOpensIsStillThere() async throws {
        let service = FixtureRecipeService(delay: .milliseconds(10))
        let (page, _, window) = await recipes(service: service) { $0.collection.searchText = "pasta" }
        defer { window.isHidden = true }
        XCTAssertTrue(service.calls.contains { $0.contains("q=pasta") }, "the grid is filtered by the remembered search: \(service.calls)")
        let field = HostedPage.descendants(of: page.view).compactMap { $0 as? UITextField }.first
        XCTAssertEqual(field?.text, "pasta", "and the search field shows it")
    }

    func testAnOpenedRecipeShowsAtOnceAsASheet() async throws {
        let service = FixtureRecipeService(delay: .milliseconds(10))
        let context = UKGalleryChrome.context(store: FoodFixtures.store())
        let card = FoodFixtures.catalog[0]
        let page = UKRecipesViewController(context: context, models: FoodModels(service: service), selected: card)
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context), size: CGSize(width: 393, height: 2200))
        defer { window.isHidden = true }
        await FeatureHost.settleAsync(1.2)
        let sheet = try XCTUnwrap(page.shownSheet, "a recipe handed to the page opens its detail")
        XCTAssertNotNil(FeatureHost.view("recipe.tabs", in: sheet.view))
    }

    func testAcrossAFoldNoRecipeCardStraddlesTheHinge() async throws {
        let size = CGSize(width: 720, height: 900)
        let band = CGRect(x: 348, y: 0, width: 24, height: 900)
        UKHinge.hasFold = true
        UKHinge.frame = band
        defer { UKHinge.frame = nil; UKHinge.hasFold = false }
        let (page, _, window) = await recipes(service: FixtureRecipeService(delay: .milliseconds(10)), wide: false, size: size)
        defer { window.isHidden = true }
        await FeatureHost.settleAsync(0.5)
        let cards = HostedPage.descendants(of: page.view).filter { ($0.accessibilityIdentifier ?? "").hasPrefix("recipes.card.") }
        XCTAssertGreaterThanOrEqual(cards.count, 4, "cards are laid out")
        for card in cards {
            let frame = card.convert(card.bounds, to: nil)
            XCTAssertFalse(frame.minX < band.minX + 1 && frame.maxX > band.maxX - 1 && frame.width > 0 && frame.minX < band.midX && frame.maxX > band.midX,
                           "\(card.accessibilityIdentifier ?? "?") at \(frame) crosses the hinge")
        }
    }
}
