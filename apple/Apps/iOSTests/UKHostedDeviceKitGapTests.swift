import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The shared sheet kit (`UKDeviceKit`): text styles, button retitling, the one-second clock, the single-line name field and the
/// hero-and-tabs sheet that goes to two columns when the window is wide.
@MainActor
final class UKHostedDeviceKitGapTests: XCTestCase {
    func testDeviceTextStylesCarryTheirTextAndInk() {
        let sub = UKDeviceText.subheadline("Next alarm")
        XCTAssertEqual(sub.text, "Next alarm")
        let body = UKDeviceText.body("Wake at 7", ink: .systemRed)
        XCTAssertEqual(body.text, "Wake at 7")
        XCTAssertEqual(body.textColor, .systemRed)
        XCTAssertNotEqual(sub.font, body.font, "the two styles differ in size")
    }

    func testFilledButtonRetitleUpdatesTheSpokenLabel() {
        let button = UKFilledButton(title: "Save", fill: .systemBlue) {}
        button.setTitle("Saving…")
        XCTAssertEqual(button.accessibilityLabel, "Saving…")
        XCTAssertEqual(button.configuration?.title, "Saving…")
    }

    func testEverySecondTicksOnStartAndStopsWhenAskedTo() {
        var ticks = 0
        let clock = UKEverySecond { _ in ticks += 1 }
        clock.setRunning(true)
        XCTAssertEqual(ticks, 1, "starting reads the clock once straight away")
        clock.setRunning(true)
        XCTAssertEqual(ticks, 2, "asking again does not start a second timer, it only refreshes")
        clock.stop()
        let before = ticks
        HostedPage.wait(1.2)
        XCTAssertEqual(ticks, before, "a stopped clock does not tick")
        clock.setRunning(true)
        clock.setRunning(false)
        HostedPage.wait(1.2)
        XCTAssertEqual(ticks, before + 2, "stopping through setRunning(false) also silences it")
    }

    func testOutlinedNameFieldIsOneLineAndLimited() throws {
        let field = UKOutlinedTextField(placeholder: "Name", text: "", limit: 5, identifier: "name")
        var changes: [String] = []
        field.onChange = { changes.append($0) }
        let window = HostedPage.show(UIViewController(), size: CGSize(width: 300, height: 200))
        defer { window.isHidden = true }
        window.rootViewController?.view.addSubview(field)
        field.frame = CGRect(x: 0, y: 0, width: 300, height: 60)
        let text = try XCTUnwrap(HostedPage.descendants(of: field).first { $0 is UITextView } as? UITextView)
        let placeholder = try XCTUnwrap(HostedPage.descendants(of: field).first { ($0 as? UILabel)?.text == "Name" } as? UILabel)
        XCTAssertFalse(placeholder.isHidden, "the placeholder shows while the field is empty")

        text.text = "ab\ncdefgh"
        text.delegate?.textViewDidChange?(text)
        XCTAssertEqual(text.text, "abcde", "newlines are dropped and the text stops at the limit")
        XCTAssertEqual(changes.last, "abcde")
        XCTAssertTrue(placeholder.isHidden)

        field.show("xy")
        XCTAssertEqual(text.text, "xy")
        XCTAssertEqual(changes.last, "abcde", "show(_:) never reports a change")
        field.show("")
        XCTAssertFalse(placeholder.isHidden, "an emptied field shows its placeholder again")

        XCTAssertTrue(try XCTUnwrap(text.delegate?.textView?(text, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementText: "a")))
        XCTAssertFalse(try XCTUnwrap(text.delegate?.textView?(text, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementText: "\n")),
                       "Return ends editing instead of adding a line")
    }

    func testHeroTabsSheetSwitchesBetweenOneAndTwoColumns() throws {
        var wide = false
        let hero = UIView()
        let tabs = UIView()
        let sheet = UKHeroTabsViewController(hero: hero, tabs: tabs, identifierBase: "kit") { _, _, _ in wide }
        var reported: [Int] = []
        sheet.onScrollViewsChanged = { reported.append($0.count) }
        let window = HostedPage.show(sheet, size: CGSize(width: 900, height: 600))
        defer { window.isHidden = true }
        XCTAssertEqual(sheet.view.accessibilityIdentifier, "kit.singleColumn")
        XCTAssertEqual(reported.last, 1)

        wide = true
        sheet.view.setNeedsLayout()
        sheet.view.layoutIfNeeded()
        XCTAssertEqual(sheet.view.accessibilityIdentifier, "kit.twoColumn")
        XCTAssertEqual(reported.last, 2)
        let scrolls = sheet.view.subviews.compactMap { $0 as? UIScrollView }
        XCTAssertEqual(scrolls.count, 2)
        XCTAssertEqual(scrolls[0].frame.width, 450, accuracy: 1, "each column takes half the width")
        XCTAssertEqual(scrolls[1].frame.minX, 450, accuracy: 1)
        XCTAssertTrue(hero.isDescendant(of: scrolls[0]), "the hero sits in the first column")
        XCTAssertTrue(tabs.isDescendant(of: scrolls[1]), "the tabs sit in the second column")

        wide = false
        sheet.view.setNeedsLayout()
        sheet.view.layoutIfNeeded()
        XCTAssertEqual(sheet.view.accessibilityIdentifier, "kit.singleColumn")
        XCTAssertEqual(sheet.view.subviews.compactMap { $0 as? UIScrollView }.count, 1, "one scroll again")
    }
}
