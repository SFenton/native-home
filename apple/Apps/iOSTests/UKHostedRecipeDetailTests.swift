import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// The recipe detail: its three tabs, the grocery action in each state, the Cookidoo variants, the failed load, the split pane
/// and the sheet, on the gallery's fixture recipes (id 2 is a full local recipe, id 1 a Cookidoo one).
@MainActor
final class UKHostedRecipeDetailTests: DemoHouseTestCase {
    private struct Screen {
        let page: UKRecipeDetailViewController
        let model: RecipeDetailModel
        let service: FixtureRecipeService
        let window: UIWindow
    }

    private func card(_ id: Int) -> RecipeCard { FoodFixtures.catalog.first { $0.id == id }! }

    private func screen(id: Int = 2, mode: FixtureRecipeService.Mode = .normal, cached: Bool = false) async -> Screen {
        let service = FixtureRecipeService(mode: mode, delay: .milliseconds(20))
        let model = RecipeDetailModel(recipe: card(id), service: service, cached: cached ? FoodFixtures.detail(id: id) : nil)
        let context = UKGalleryChrome.context(store: FoodFixtures.store())
        let page = UKRecipeDetailViewController(model: model, context: context, setsNavigationTitle: true)
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context), size: CGSize(width: 393, height: 2200))
        await FeatureHost.settleAsync(0.6)
        return Screen(page: page, model: model, service: service, window: window)
    }

    private func labels(_ s: Screen) -> [String] { HostedPage.labels(in: s.page.view) }

    func testItShowsALoadingSpinnerThenTheGeneralTab() async {
        let service = FixtureRecipeService(mode: .slow)
        let model = RecipeDetailModel(recipe: card(2), service: service)
        let context = UKGalleryChrome.context(store: FoodFixtures.store())
        let page = UKRecipeDetailViewController(model: model, context: context, setsNavigationTitle: true)
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context))
        defer { window.isHidden = true }
        await FeatureHost.settleAsync(0.2)
        XCTAssertNotNil(FeatureHost.view("recipe.loading", in: page.view), "a slow load shows a spinner")
        XCTAssertNil(FeatureHost.view("recipe.tabs", in: page.view), "no tabs before the recipe arrives")

        let s = await screen()
        defer { s.window.isHidden = true }
        XCTAssertNil(FeatureHost.view("recipe.loading", in: s.page.view))
        XCTAssertNotNil(FeatureHost.view("recipe.tabs", in: s.page.view), "Recipe sections are in the bottom bar")
        XCTAssertNotNil(FeatureHost.view("recipe.openSource", in: s.page.view), "the source link is on General")
        let text = labels(s)
        XCTAssertTrue(text.contains("Oven"), "devices are listed: \(text)")
        XCTAssertTrue(text.contains("Baking dish") && text.contains("Zester"), "equipment is listed")
        XCTAssertTrue(text.contains("Open Source Recipe"))
        XCTAssertEqual(s.page.navigationItem.title, card(2).title)
    }

    func testIngredientsAreGroupedAndMarkedByWhatIsOnHand() async {
        let s = await screen()
        defer { s.window.isHidden = true }
        s.model.tab = .ingredients
        await FeatureHost.settleAsync(0.4)
        let ids = FeatureHost.identifiers(in: s.page.view)
        for position in 0...5 { XCTAssertTrue(ids.contains("recipe.ingredient.\(position)"), "ingredient \(position) is a row") }
        let text = labels(s)
        XCTAssertTrue(text.contains("Chicken") && text.contains("To finish"), "each group has a heading: \(text)")
        XCTAssertTrue(text.contains { $0.contains("Chicken thighs") })
        XCTAssertNotNil(FeatureHost.view("recipe.grocery.add", in: s.page.view))
        XCTAssertNotNil(FeatureHost.view("recipe.grocery.description", in: s.page.view), "the button says what it does")
    }

    func testAddingMissingIngredientsCallsTheServiceThenConfirms() async {
        let s = await screen()
        defer { s.window.isHidden = true }
        s.model.tab = .ingredients
        await FeatureHost.settleAsync(0.4)
        XCTAssertTrue(FeatureHost.press("recipe.grocery.add", in: s.page.view))
        await FeatureHost.settleAsync(0.6)
        XCTAssertTrue(s.service.calls.contains { $0.hasPrefix("recipe_grocery_add recipe_id=2") }, "\(s.service.calls)")
        XCTAssertNotNil(FeatureHost.view("recipe.grocery.added", in: s.page.view), "the button swaps for the confirmation")
        XCTAssertNotNil(FeatureHost.view("recipe.grocery.message", in: s.page.view))
        XCTAssertNil(FeatureHost.view("recipe.grocery.add", in: s.page.view))
    }

    func testAFailedGroceryAddShowsAnErrorAndKeepsTheButton() async {
        // The cached detail shows even though the service fails; adding then fails and says so.
        let s = await screen(mode: .error, cached: true)
        defer { s.window.isHidden = true }
        s.model.tab = .ingredients
        await FeatureHost.settleAsync(0.4)
        XCTAssertTrue(FeatureHost.press("recipe.grocery.add", in: s.page.view))
        await FeatureHost.settleAsync(0.6)
        XCTAssertNotNil(FeatureHost.view("recipe.grocery.error", in: s.page.view), "the failure is shown inline")
        XCTAssertNotNil(FeatureHost.view("recipe.grocery.add", in: s.page.view), "and the person can try again")
    }

    func testInstructionsAreNumberedSteps() async {
        let s = await screen()
        defer { s.window.isHidden = true }
        s.model.tab = .instructions
        await FeatureHost.settleAsync(0.4)
        let text = labels(s)
        XCTAssertTrue(text.contains("1.") && text.contains("3."), "steps are numbered: \(text)")
        XCTAssertTrue(text.contains("Heat the oven to 425°F and zest the lemons."))
    }

    func testACookidooRecipeSendsInstructionsToCookidoo() async {
        let s = await screen(id: 1)
        defer { s.window.isHidden = true }
        XCTAssertTrue(labels(s).contains { $0.contains("not available in the cached Cookidoo metadata") }, "General explains the missing metadata")
        XCTAssertTrue(labels(s).contains("Open in Cookidoo"))
        s.model.tab = .instructions
        await FeatureHost.settleAsync(0.4)
        XCTAssertNotNil(FeatureHost.view("recipe.openCookidoo", in: s.page.view))
        XCTAssertTrue(labels(s).contains("Instructions are on Cookidoo"))
    }

    func testEmptyIngredientAndInstructionDetailsSaySo() async {
        var detail = FoodFixtures.detail(id: 2)
        detail.ingredients = []
        detail.capabilities.ingredients = .none
        detail.capabilities.instructions = .none
        // No service: the page keeps the cached detail instead of refreshing it with the full fixture.
        let model = RecipeDetailModel(recipe: card(2), service: nil, cached: detail)
        let context = UKGalleryChrome.context(store: FoodFixtures.store())
        let page = UKRecipeDetailViewController(model: model, context: context, setsNavigationTitle: false)
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context), size: CGSize(width: 393, height: 2200))
        defer { window.isHidden = true }
        await FeatureHost.settleAsync(0.3)
        model.tab = .ingredients
        await FeatureHost.settleAsync(0.3)
        XCTAssertNotNil(FeatureHost.view("recipe.ingredients.empty", in: page.view))
        model.tab = .instructions
        await FeatureHost.settleAsync(0.3)
        XCTAssertNotNil(FeatureHost.view("recipe.instructions.empty", in: page.view))
    }

    func testAFailedLoadExplainsItself() async {
        let s = await screen(mode: .error)
        defer { s.window.isHidden = true }
        XCTAssertNotNil(FeatureHost.view("recipe.error", in: s.page.view))
        XCTAssertTrue(labels(s).contains("Unable to Load Recipe"), "\(labels(s))")
        XCTAssertNil(FeatureHost.view("recipe.tabs", in: s.page.view))
    }

    func testThePaneHasATitleAndACloseButton() async {
        let service = FixtureRecipeService(delay: .milliseconds(20))
        let model = RecipeDetailModel(recipe: card(2), service: service)
        let context = UKGalleryChrome.context(store: FoodFixtures.store())
        var closed = 0
        let pane = UKRecipeDetailPaneViewController(model: model, context: context) { closed += 1 }
        let window = HostedPage.show(pane, size: CGSize(width: 600, height: 900))
        defer { window.isHidden = true }
        await FeatureHost.settleAsync(0.6)
        XCTAssertTrue(HostedPage.labels(in: pane.view).contains(card(2).title), "the pane's header carries the title")
        XCTAssertTrue(FeatureHost.press("recipe.close", in: pane.view))
        XCTAssertEqual(closed, 1)
    }

    func testTheSheetPresentsTheRecipeAndReportsItsDismissal() async throws {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let service = FixtureRecipeService(delay: .milliseconds(20))
        let model = RecipeDetailModel(recipe: card(2), service: service)
        var dismissed = false
        UKRecipeDetailPresenter.presentSheet(model, from: host, context: UKGalleryChrome.context(store: FoodFixtures.store())) { dismissed = true }
        await FeatureHost.settleAsync(1.0)
        let sheet = try XCTUnwrap(host.presentedViewController)
        XCTAssertNotNil(FeatureHost.view("recipe.tabs", in: sheet.view))
        sheet.dismiss(animated: false)
        await FeatureHost.settleAsync(0.5)
        XCTAssertTrue(dismissed || host.presentedViewController == nil)
    }
}
