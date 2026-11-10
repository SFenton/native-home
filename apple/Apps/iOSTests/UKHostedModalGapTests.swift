import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// The shared sheet's paths the other modal suites leave out: the swipe-down hooks a presenter listens to, the debug probes a
/// journey reads, the pushed-page fit and a window that changes size under an open sheet.
@MainActor
final class UKHostedModalGapTests: XCTestCase {
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

    func testASwipeDownTellsOptionsAndTheObserverAndARefusedOneAsksThePresenter() {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        var options = UKHassModalOptions(title: "Swipe", fitKey: "test.gap.swipe")
        var order: [String] = []
        options.onDismissed = { order.append("options") }
        let modal = UKHassModalController(root: page("x"), options: options)
        modal.swipeDismissObserver = { order.append("observer") }
        var asked = 0
        modal.onAttemptToDismiss = { asked += 1 }
        present(modal, from: host)
        let controller = modal.presentationController!
        modal.presentationControllerDidAttemptToDismiss(controller)
        XCTAssertEqual(asked, 1, "a refused swipe asks the presenter")
        modal.presentationControllerDidDismiss(controller)
        XCTAssertEqual(order, ["options", "observer"], "the observer hears the swipe after the options hook")
        XCTAssertTrue(controller.delegate === modal, "the modal stays the sheet's delegate")
        modal.configureSheet()
        XCTAssertTrue(modal.sheetPresentationController?.delegate === modal, "a re-configure keeps it too")
    }

    func testTheBarBehaviourAndAppearanceFollowTheOptions() {
        // The phone's rule (no hinge, no vertical bar) on every family, so no window fills the height.
        UKDeviceSignals.verticalBarOverride = { _ in false }
        UKDeviceSignals.regionsOverride = { _, _ in [] }
        defer {
            UKDeviceSignals.verticalBarOverride = nil
            UKDeviceSignals.regionsOverride = nil
        }
        var options = UKHassModalOptions(title: "Bar", fitKey: "test.gap.bar")
        options.closeStaysInBar = true
        options.appearance = .dark
        let dark = UKHassModalController(root: page("x"), options: options)
        XCTAssertEqual(dark.overrideUserInterfaceStyle, .dark)
        if #available(iOS 27.1, *) {
            XCTAssertEqual(dark.preferredVerticalBarBehavior, .disabled, "Close stays in the sheet's own bar where the sheet does not fill the height")
            XCTAssertNil(dark.childForPreferredVerticalBarBehavior, "the modal answers for its pages")
        }
        options.appearance = .system
        options.closeStaysInBar = false
        let plain = UKHassModalController(root: page("x"), options: options)
        if #available(iOS 27.1, *) { XCTAssertEqual(plain.preferredVerticalBarBehavior, .automatic, "a sheet that keeps the rail leaves the system's choice") }
        XCTAssertEqual(plain.overrideUserInterfaceStyle, SystemAppearance.current() == .light ? .light : .dark, "a system-appearance sheet follows the system")
    }

    func testAPageOnAFittedToTopPageSheetTakesTheHeight() {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        var options = UKHassModalOptions(title: "Top", fitKey: "test.gap.top")
        options.height = .fittedToTopPage
        options.closeStaysInBar = true
        let modal = UKHassModalController(root: page("Root"), options: options)
        present(modal, from: host)
        modal.pushViewController(page("Second"), animated: false)
        hostedSettle(0.5)
        XCTAssertEqual(modal.viewControllers.count, 2)
        XCTAssertEqual(modal.topViewController?.title, "Second", "the pushed page is on top")
        modal.popViewController(animated: false)
        hostedSettle(0.3)
        XCTAssertEqual(modal.topViewController?.title, "Root", "Back returns to the first page")
    }

    func testTheFitProbeAndTheDetentTrackerRunUnderTheirSwitches() {
        setenv("FENTON_SHEETFIT_PROBE", "1", 1)
        setenv("FENTON_DEBUG_SHEET", "1", 1)
        defer {
            unsetenv("FENTON_SHEETFIT_PROBE")
            unsetenv("FENTON_DEBUG_SHEET")
        }
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let modal = UKHassModalController(root: page("Probe"), options: UKHassModalOptions(title: "Probe", fitKey: "test.gap.probe"))
        present(modal, from: host)
        let probe = HostedPage.descendants(of: modal.view).compactMap { $0 as? UKSheetFitProbeView }.first
        let value = probe?.accessibilityValue ?? ""
        XCTAssertTrue(value.contains("initial="), "the probe reads the fit")
        XCTAssertTrue(value.contains("geo=["), "and the transforms up to the window")
        probe?.accessibilityValue = "ignored"
        XCTAssertEqual(probe?.accessibilityValue, value, "the probe's value is composed, not stored")
        modal.configureSheet()
        // The tracker stops itself a little over a second after a detent change.
        hostedSettle(1.5)
    }

    func testAWindowThatChangesSizeUnderTheSheetRefitsIt() {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let modal = UKHassModalController(root: page("Resize"), options: UKHassModalOptions(title: "Resize", fitKey: "test.gap.resize"))
        present(modal, from: host)
        window.frame = CGRect(x: 0, y: 0, width: 900, height: 500)
        hostedSettle(0.6)
        XCTAssertEqual(modal.view.window?.bounds.width, 900, "the sheet follows the window's new width")
        XCTAssertTrue(modal.sheetPresentationController?.delegate === modal, "and keeps its delegate")
        XCTAssertFalse(modal.sheetPresentationController?.detents.isEmpty ?? true, "and its detents")
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        hostedSettle(0.6)
        XCTAssertEqual(modal.view.window?.bounds.height, 852)
        XCTAssertNotNil(modal.presentingViewController, "the sheet is still up")
    }
    /// A size-class change under an open sheet resolves the grabber (a full-height sheet) or the detent and form width (a fitted one) again.
    func testASizeClassChangeUnderAnOpenSheetResolvesItAgain() {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        var full = UKHassModalOptions(title: "Full", fitKey: "test.gap.traitfull")
        full.height = .full
        let tall = UKHassModalController(root: page("Full"), options: full)
        present(tall, from: host)
        tall.traitCollectionDidChange(UITraitCollection(horizontalSizeClass: .unspecified))
        XCTAssertNotNil(tall.sheetPresentationController, "the full-height sheet is still a sheet")
        XCTAssertTrue(HostedPage.until(4) { tall.sheetPresentationController?.delegate === tall }, "and keeps its delegate")
        tall.dismiss(animated: false)
        XCTAssertTrue(HostedPage.until(4) { host.presentedViewController == nil }, "the full-height sheet has gone")
        let fitted = UKHassModalController(root: page("Fit"), options: UKHassModalOptions(title: "Fit", fitKey: "test.gap.traitfit"))
        present(fitted, from: host)
        fitted.traitCollectionDidChange(UITraitCollection(horizontalSizeClass: .unspecified))
        XCTAssertFalse(fitted.sheetPresentationController?.detents.isEmpty ?? true, "the fitted sheet keeps its detents")
    }
}
