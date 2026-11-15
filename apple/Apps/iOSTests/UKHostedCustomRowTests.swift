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
}
