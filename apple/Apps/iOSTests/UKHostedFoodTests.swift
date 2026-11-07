import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// Food & Recipes: the hub, the Recipes grid, a recipe, and the entry points that route to them, on the gallery's fixture service.
@MainActor
final class UKHostedFoodTests: DemoHouseTestCase {
    private var lastModels: FoodModels?

    private func hub(mode: FixtureRecipeService.Mode = .normal) async -> (UKFoodHubViewController, FixtureRecipeService, UIViewController, UIWindow) {
        let service = FixtureRecipeService(mode: mode, delay: .milliseconds(20))
        let server = EverShelfFixtureServer.sample()
        server.latency = .milliseconds(20)
        let inventory = InventoryModels(client: EverShelfClient(caller: server))
        let context = UKGalleryChrome.context(store: FoodFixtures.store())
        let models = FoodModels(service: service)
        lastModels = models
        let page = UKFoodHubViewController(context: context, models: models, inventory: inventory)
        let host = UKGalleryChrome.wrap(page, context: context)
        let window = HostedPage.show(host, size: CGSize(width: 393, height: 2200))
        await FeatureHost.settleAsync(0.8)
        return (page, service, host, window)
    }

    private func recipes(mode: FixtureRecipeService.Mode = .normal) async -> (UKRecipesViewController, FixtureRecipeService, UIWindow) {
        let service = FixtureRecipeService(mode: mode, delay: .milliseconds(20))
        let context = UKGalleryChrome.context(store: FoodFixtures.store())
        let page = UKRecipesViewController(context: context, models: FoodModels(service: service))
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context), size: CGSize(width: 393, height: 2200))
        await FeatureHost.settleAsync(0.8)
        return (page, service, window)
    }

    // MARK: Hub

    func testTheHubOffersRecipesAndEverySpaceAndLoadsSuggestions() async {
        let (page, service, _, window) = await hub()
        defer { window.isHidden = true }
        let ids = FeatureHost.identifiers(in: page.view)
        XCTAssertTrue(ids.contains("food.allRecipes") && ids.contains("food.allFood"))
        XCTAssertTrue(ids.contains { $0.hasPrefix("food.space.") }, "each storage space is a tile")
        XCTAssertTrue(ids.contains("food.suggestions") || ids.contains { $0.hasPrefix("food.suggestion.") }, "suggested recipes arrived")
        XCTAssertTrue(service.calls.contains { $0.contains("recommendations") }, "suggestions came from the service: \(service.calls)")
    }

    func testTheHubSaysWhenSuggestionsFailAndOffersTryAgain() async {
        let (page, _, _, window) = await hub(mode: .error)
        defer { window.isHidden = true }
        await FeatureHost.settleAsync(0.5)
        let carouselDiagnosis = "before relayout: \(FeatureHost.identifiers(in: page.view).filter { $0.hasPrefix("food.suggestions") }.sorted())"
        page.view.setNeedsLayout(); page.view.layoutIfNeeded()
        FeatureHost.relayout(page.view)
        XCTAssertNotNil(FeatureHost.view("food.suggestions.error", in: page.view), "a failed load is explained: \(carouselDiagnosis) phase=\(String(describing: lastModels?.suggestions.phase)) \(FeatureHost.describeLists(in: page.view)) \(FeatureHost.identifiers(in: page.view).filter { $0.hasPrefix("food") }.sorted())")
    }

    func testTheHubSaysWhenThereAreNoSuggestions() async {
        let (page, _, _, window) = await hub(mode: .empty)
        defer { window.isHidden = true }
        await FeatureHost.settleAsync(0.5)
        FeatureHost.relayout(page.view)
        XCTAssertNotNil(FeatureHost.view("food.suggestions.empty", in: page.view), "\(FeatureHost.identifiers(in: page.view).filter { $0.hasPrefix("food") }.sorted())")
    }

    func testHubTilesPushTheirPages() async {
        let (page, _, host, window) = await hub()
        defer { window.isHidden = true }
        XCTAssertTrue(FeatureHost.press("food.allRecipes", in: page.view) || FeatureHost.tapRow("food.allRecipes", in: page.view))
        await FeatureHost.settleAsync(0.8)
        XCTAssertEqual(page.navigationController?.viewControllers.count, 2, "All Recipes is pushed")
        XCTAssertNotNil(host)
        page.navigationController?.popViewController(animated: false)
        await FeatureHost.settleAsync(0.4)
        XCTAssertTrue(FeatureHost.press("food.allFood", in: page.view) || FeatureHost.tapRow("food.allFood", in: page.view))
        await FeatureHost.settleAsync(0.8)
        XCTAssertEqual(page.navigationController?.viewControllers.count, 2, "All Food is pushed")
    }

    // MARK: Recipes

    func testTheRecipesGridShowsCardsAndPagesInMore() async throws {
        let (page, service, window) = await recipes()
        defer { window.isHidden = true }
        let grid = try XCTUnwrap(FeatureHost.view("recipes.grid", in: page.view) as? UICollectionView)
        XCTAssertGreaterThan(grid.numberOfItems(inSection: 0), 0)
        XCTAssertTrue(FeatureHost.identifiers(in: page.view).contains { $0.hasPrefix("recipes.card.") })
        XCTAssertTrue(service.calls.contains { $0.contains("kind=browse") })
        grid.layoutIfNeeded()
        grid.setContentOffset(CGPoint(x: 0, y: max(0, grid.contentSize.height - grid.bounds.height)), animated: false)
        grid.layoutIfNeeded()
        await FeatureHost.settleAsync(1.0)
        XCTAssertTrue(service.calls.filter { $0.contains("kind=browse") }.count >= 2, "scrolling to the end asks for the next page")
    }

    func testAnEmptyOrFailedRecipeListSaysWhy() async {
        let (empty, _, emptyWindow) = await recipes(mode: .empty)
        defer { emptyWindow.isHidden = true }
        XCTAssertNotNil(FeatureHost.view("recipes.empty", in: empty.view))
        let (failed, _, failedWindow) = await recipes(mode: .error)
        defer { failedWindow.isHidden = true }
        XCTAssertNotNil(FeatureHost.view("recipes.error", in: failed.view))
        XCTAssertTrue(FeatureHost.press("recipes.retry", in: failed.view))
    }

    func testSortAndFilterSheetsOpenFromTheFloatingActions() async throws {
        let (page, service, window) = await recipes()
        defer { window.isHidden = true }
        XCTAssertTrue(FeatureHost.press("fab.sort", in: page.view))
        await FeatureHost.settleAsync(0.8)
        let sheet = try XCTUnwrap(page.shownSheet)
        XCTAssertNotNil(FeatureHost.view("recipes.sort.\(RecipeSort.allCases.first!.rawValue)", in: sheet.view), "sort options are listed")
        sheet.dismiss(animated: false)
        await FeatureHost.settleAsync(0.4)
        XCTAssertTrue(FeatureHost.press("fab.filter", in: page.view))
        await FeatureHost.settleAsync(0.8)
        let filter = try XCTUnwrap(page.shownSheet)
        XCTAssertNotNil(FeatureHost.view("recipes.filter.coverage", in: filter.view))
        XCTAssertNotNil(FeatureHost.view("recipes.filter.expiringOnly", in: filter.view))
        XCTAssertNotNil(service)
    }

    func testOpeningACardShowsTheRecipe() async throws {
        let (page, service, window) = await recipes()
        defer { window.isHidden = true }
        let card = try XCTUnwrap(FeatureHost.identifiers(in: page.view).sorted().first { $0.hasPrefix("recipes.card.") })
        XCTAssertTrue(FeatureHost.press(card, in: page.view) || FeatureHost.tapRow(card, in: page.view))
        await FeatureHost.settleAsync(1.2)
        XCTAssertTrue(service.calls.contains { $0.contains("recipe_detail") || $0.contains("detail") || $0.contains("kind=recipe") }, "the recipe was fetched: \(service.calls)")
    }

    // MARK: Routing

    func testSignedOutSpacesAndUnknownSpacesDegradeGracefully() async {
        let context = UKGalleryChrome.context()
        XCTAssertTrue(UKScreens.foodSpace("not-a-space", context: context) is UKPlaceholderViewController)
        let space = InventorySpace.allCases.first!
        XCTAssertTrue(UKScreens.foodSpace(space.rawValue, context: context) is UKNotSignedInViewController, "no models while signed out")
        let notSignedIn = UKNotSignedInViewController(context: context)
        let window = HostedPage.show(notSignedIn)
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.labels(in: notSignedIn.view).contains("Not Signed In"))
        XCTAssertTrue(UKScreens.food(context) is UKFoodHubViewController)
    }

    func testTheFoodServiceFollowsTheSignedInConnection() async throws {
        let host = try FeatureHost.signedIn()
        let models = FoodModels()
        UKFoodNavigation.connect(models, context: host.context)
        XCTAssertTrue(models.service is EverShelfRecipeService)
        let override = FixtureRecipeService()
        UKFoodNavigation.connect(models, context: host.context, override: override)
        XCTAssertTrue(models.service === override)
        XCTAssertNotNil(UKFoodNavigation.inventoryModels(context: host.context, injected: nil))
        XCTAssertNil(UKFoodNavigation.inventoryModels(context: UKGalleryChrome.context(), injected: nil))
        let page = UKFoodNavigation.inventoryPage(InventorySpace.allCases.first!, context: host.context, models: UKFoodNavigation.inventoryModels(context: host.context, injected: nil))
        XCTAssertTrue(page is UKInventoryViewController)
    }

    func testLaunchRoutesFromTheEnvironment() async {
        let context = UKGalleryChrome.context(store: FoodFixtures.store())
        setenv("FENTON_OPEN_FOOD", "hub", 1)
        XCTAssertTrue(UKFoodLaunch.requestedPage(context: context, models: FoodModels(service: FixtureRecipeService())) is UKFoodHubViewController)
        setenv("FENTON_OPEN_FOOD", "recipes", 1)
        XCTAssertTrue(UKFoodLaunch.requestedPage(context: context, models: FoodModels(service: FixtureRecipeService())) is UKRecipesViewController)
        unsetenv("FENTON_OPEN_FOOD")
        setenv("FENTON_OPEN_INVENTORY", InventorySpace.allCases.first!.rawValue, 1)
        let server = EverShelfFixtureServer.sample()
        XCTAssertNotNil(UKFoodLaunch.requestedPage(context: context, inventory: InventoryModels(client: EverShelfClient(caller: server))))
        unsetenv("FENTON_OPEN_INVENTORY")
        XCTAssertNil(UKFoodLaunch.requestedPage(context: context))
        setenv("FENTON_OPEN_FOOD", "hub", 1)
        defer { unsetenv("FENTON_OPEN_FOOD") }
        let navigation = UINavigationController(rootViewController: UIViewController())
        UKFoodLaunch.pushRequested(on: navigation, context: context, models: FoodModels(service: FixtureRecipeService()))
        XCTAssertEqual(navigation.viewControllers.count, 2)
    }
}
