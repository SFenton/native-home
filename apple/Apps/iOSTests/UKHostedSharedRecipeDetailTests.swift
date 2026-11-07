import HassCore
import UIKit
import XCTest
@testable import HassUI

/// A recipe whose lists the server cut short says so on the ingredients and method tabs.
@MainActor
final class UKHostedSharedRecipeDetailTests: DemoHouseTestCase {
    func testTruncatedIngredientsAndStepsAreSaidAndASingleStepGroupHasNoHeading() async {
        var detail = FoodFixtures.detail(id: 2)
        detail.ingredientsTruncated = true
        detail.capabilities.ingredients = .checklist
        detail.instructions.truncated = true
        let step = detail.instructions.groups.first?.steps ?? []
        detail.instructions.groups = [RecipeDetail.StepGroup(key: "only", label: nil, steps: step)]
        let model = RecipeDetailModel(recipe: FoodFixtures.catalog.first { $0.id == 2 }!, service: nil, cached: detail)
        let context = UKGalleryChrome.context(store: FoodFixtures.store())
        let page = UKRecipeDetailViewController(model: model, context: context, setsNavigationTitle: true)
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context), size: CGSize(width: 393, height: 2200))
        defer { window.isHidden = true }
        await FeatureHost.settleAsync(0.6)

        model.tab = .ingredients
        await FeatureHost.settleAsync(0.4)
        XCTAssertTrue(HostedPage.labels(in: page.view).contains("This ingredient list is truncated."), "the ingredients tab says the list is cut")

        model.tab = .instructions
        await FeatureHost.settleAsync(0.4)
        let labels = HostedPage.labels(in: page.view)
        XCTAssertTrue(labels.contains("These instructions are truncated."), "the method tab says the steps are cut; saw \(labels.prefix(10))")
        XCTAssertFalse(labels.contains("Section 1"), "one unnamed group gets no generated heading")
    }
}
