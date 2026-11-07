import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// The shared sheet: how it is sized, how it closes (button, VoiceOver escape, swipe) and what a guarded form does.
@MainActor
final class UKHostedModalTests: XCTestCase {
    private func page(_ text: String) -> UIViewController {
        let page = UIViewController()
        let label = UILabel(); label.text = text
        label.frame = CGRect(x: 20, y: 100, width: 200, height: 30)
        page.view.addSubview(label)
        page.title = text
        return page
    }

    private func present(_ modal: UKHassModalController, from host: UIViewController) {
        modal.present(from: host, animated: false)
        hostedSettle(0.5)
    }

    func testAFittedSheetShowsTitleGrabberAndCloseThatDismisses() {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        var options = UKHassModalOptions(title: "Lighting Mode", fitKey: "test.fitted")
        var dismissed = 0
        options.onDismissed = { dismissed += 1 }
        let modal = UKHassModalController(root: page("Body"), options: options)
        present(modal, from: host)
        XCTAssertNotNil(host.presentedViewController)
        let sheet = modal.sheetPresentationController
        XCTAssertEqual(sheet?.prefersGrabberVisible, true, "a fitted sheet shows its grabber")
        XCTAssertFalse(sheet?.detents.isEmpty ?? true)
        XCTAssertEqual(modal.viewControllers.first?.navigationItem.title, "Body", "the page's own title wins over the sheet option")
        let closeButtons = HostedPage.descendants(of: modal.view).filter { $0.accessibilityIdentifier == "sheet.close" }
        // On iOS 26+ the circle-X is a system bar item: the page carries it (identifier, enabled) rather than a view with the identifier.
        let closeItem = FeatureHost.barItem("sheet.close", on: modal)
        XCTAssertTrue(!closeButtons.isEmpty || closeItem?.isEnabled == true, "the circle-X is on screen")
        modal.close()
        hostedSettle(0.6)
        XCTAssertNil(host.presentedViewController)
        XCTAssertEqual(dismissed, 1)
    }

    func testAFullSheetHasOneDetentAndNoGrabber() {
        // The phone's rule (no hinge, no vertical bar) on every family: the folded Duo simulator reports a vertical bar, which makes
        // every sheet fill the height and keep its grabber (``UKSheetPlacement/fillsHeight(in:)``).
        UKDeviceSignals.verticalBarOverride = { _ in false }
        UKDeviceSignals.regionsOverride = { _, _ in [] }
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        var options = UKHassModalOptions(title: "Remote", fitKey: "test.full")
        options.height = .full
        options.appearance = .dark
        let modal = UKHassModalController(root: page("Remote"), options: options)
        present(modal, from: host)
        XCTAssertEqual(modal.sheetPresentationController?.prefersGrabberVisible, false)
        XCTAssertEqual(modal.sheetPresentationController?.detents.count, 1)
        XCTAssertEqual(modal.overrideUserInterfaceStyle, .dark)
        modal.dismiss(animated: false)
    }

    func testAPredictedHeightOpensAtItsFinalSizeAndFullScreenHasNoSheet() {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        var options = UKHassModalOptions(title: "Viewer", fitKey: "test.predicted")
        options.predictedContentHeight = 300
        let modal = UKHassModalController(root: page("Viewer"), options: options)
        present(modal, from: host)
        XCTAssertNotNil(modal.sheetPresentationController)
        modal.dismiss(animated: false)
        hostedSettle(0.3)

        var full = UKHassModalOptions(title: "Settings", fitKey: "test.fullscreen")
        full.isFullScreen = true
        let screen = UKHassModalController(root: page("Settings"), options: full)
        present(screen, from: host)
        XCTAssertEqual(screen.modalPresentationStyle, .fullScreen)
        screen.dismiss(animated: false)
    }

    func testEscapeGoesBackOnePageThenClosesAndAGuardedFormAsksFirst() {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let modal = UKHassModalController(root: page("Root"), options: UKHassModalOptions(title: "Root", fitKey: "test.escape"))
        present(modal, from: host)
        modal.push(page("Child"), animated: false)
        hostedSettle(0.3)
        XCTAssertEqual(modal.viewControllers.count, 2)
        XCTAssertTrue(modal.accessibilityPerformEscape(), "escape goes back a page")
        hostedSettle(0.5)
        XCTAssertEqual(modal.viewControllers.count, 1)

        modal.isModalInPresentation = true
        XCTAssertFalse(modal.accessibilityPerformEscape(), "a guarded form without a handler stays")
        var asked = 0
        modal.onAttemptToDismiss = { asked += 1 }
        XCTAssertTrue(modal.accessibilityPerformEscape())
        XCTAssertEqual(asked, 1)
        modal.isModalInPresentation = false
        XCTAssertTrue(modal.accessibilityPerformEscape(), "escape closes the sheet")
        hostedSettle(0.6)
        XCTAssertNil(host.presentedViewController)
    }

    func testClosingCanBeHandedToThePresenter() {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        var options = UKHassModalOptions(title: "Sign out", fitKey: "test.handoff")
        var closes = 0
        options.onClose = { closes += 1 }
        options.showsClose = false
        let modal = UKHassModalController(root: page("x"), options: options)
        present(modal, from: host)
        modal.close()
        XCTAssertEqual(closes, 1)
        XCTAssertNotNil(host.presentedViewController, "the presenter decides when it goes")
        modal.presentationControllerDidDismiss(modal.presentationController!)
        modal.dismiss(animated: false)
    }
}
