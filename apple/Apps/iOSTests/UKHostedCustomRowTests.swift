import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// A `.custom` form row is only redrawn when its row id changes: state shows either in a view the form keeps and updates in place, or
/// in the id. These tests hold both ways to what a person sees.
@MainActor
final class UKHostedCustomRowTests: DemoHouseTestCase {
    private func label(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        return label
    }

    func testACustomRowWithStateInItsIdIsRedrawnWhenTheStateChanges() {
        let form = UKFormViewController()
        let window = HostedPage.show(form)
        defer { window.isHidden = true }
        func sections(_ empty: Bool) -> [UKFormSection] {
            [UKFormSection(id: "images", rows: [UKFormRow(id: empty ? "pick" : "pick-change", .custom { [self] in label(empty ? "Add Images" : "Choose Different Images") })])]
        }
        form.setSections(sections(true), animated: false)
        hostedSettle(0.3)
        XCTAssertTrue(HostedPage.labels(in: form.view).contains("Add Images"))
        form.setSections(sections(false), animated: false)
        hostedSettle(0.3)
        let texts = HostedPage.labels(in: form.view)
        XCTAssertTrue(texts.contains("Choose Different Images"), "the row follows the state; saw \(texts)")
        XCTAssertFalse(texts.contains("Add Images"), "and the old words are gone")
    }

    func testACustomRowThatKeepsItsViewShowsTheViewsLatestContent() {
        let form = UKFormViewController()
        let window = HostedPage.show(form)
        defer { window.isHidden = true }
        let kept = label("Save Eggs")
        let sections = [UKFormSection(id: "changes", rows: [UKFormRow(id: "save", .custom { kept })])]
        form.setSections(sections, animated: false)
        hostedSettle(0.3)
        XCTAssertTrue(HostedPage.labels(in: form.view).contains("Save Eggs"))
        kept.text = "Saving Eggs"
        form.setSections(sections, animated: false)
        hostedSettle(0.3)
        XCTAssertTrue(HostedPage.labels(in: form.view).contains("Saving Eggs"), "the kept view is the row, so it shows its new words")
    }

    func testTheRecipeFilterSheetsKeptRowsFollowTheDraft() async throws {
        let service = FixtureRecipeService(delay: .milliseconds(20))
        let context = UKGalleryChrome.context(store: FoodFixtures.store())
        let page = UKRecipesViewController(context: context, models: FoodModels(service: service))
        let host = UKGalleryChrome.wrap(page, context: context)
        let window = HostedPage.show(host, size: CGSize(width: 393, height: 2200))
        defer { window.isHidden = true }
        await FeatureHost.settleAsync(0.8)
        XCTAssertTrue(FeatureHost.press("fab.filter", in: page.view))
        await FeatureHost.settleAsync(0.8)
        let sheet = try XCTUnwrap(page.shownSheet)
        let horizon = try XCTUnwrap(FeatureHost.reveal("recipes.filter.horizon", in: sheet.view))
        let control = { (horizon as? UIControl) ?? HostedPage.descendants(of: horizon).compactMap { $0 as? UIControl }.first { !$0.isHidden } }
        HostedPage.until { control() != nil }
        let segmented = control()
        XCTAssertNotNil(segmented, "\(horizon) \(HostedPage.descendants(of: horizon).map { "\(type(of: $0)) hidden=\($0.isHidden) alpha=\($0.alpha) \($0.frame)" })")
        XCTAssertEqual(segmented?.isEnabled, false, "Expiring Within waits for Expiring Ingredients Only")
        XCTAssertTrue(FeatureHost.flip("recipes.filter.expiringOnly", in: sheet.view))
        await FeatureHost.settleAsync(0.5)
        XCTAssertEqual(segmented?.isEnabled, true, "turning the switch on enables the row beside it")
        XCTAssertTrue(FeatureHost.flip("recipes.filter.expiringOnly", in: sheet.view))
        await FeatureHost.settleAsync(0.5)
        XCTAssertEqual(segmented?.isEnabled, false, "and off disables it again")
    }
}
