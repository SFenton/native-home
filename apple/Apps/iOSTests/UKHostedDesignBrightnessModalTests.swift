import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// A pan recognizer that reports what the test says.
private final class BrightnessPan: UIPanGestureRecognizer {
    var scriptedState: UIGestureRecognizer.State = .possible
    var point = CGPoint.zero
    var travel = CGPoint.zero
    var speed = CGPoint.zero
    override var state: UIGestureRecognizer.State {
        get { scriptedState }
        set {}
    }
    override func location(in view: UIView?) -> CGPoint { point }
    override func translation(in view: UIView?) -> CGPoint { travel }
    override func velocity(in view: UIView?) -> CGPoint { speed }
}

/// The light tile's intents (flip, VoiceOver adjust, drag) and the shared sheet's remaining behaviours.
@MainActor
final class UKHostedDesignBrightnessModalTests: XCTestCase {
    private func tileView(percent: Int, unavailable: Bool = false) -> (UKBrightnessTileView, UIWindow) {
        let host = UIViewController()
        let window = HostedPage.show(host)
        let view = UKBrightnessTileView(title: "Lamp", tint: .systemYellow, percent: percent, isUnavailable: unavailable)
        view.frame = CGRect(x: 20, y: 120, width: 170, height: 90)
        host.view.addSubview(view)
        view.layoutIfNeeded()
        return (view, window)
    }

    private func glassTile(in view: UIView) -> UKGlassTileView? { HostedPage.descendants(of: view).compactMap { $0 as? UKGlassTileView }.first }

    // MARK: Brightness tile

    func testAdjustingByVoiceOverSendsTheNextStepAndFlippingSendsPowerAndTheLiveStateReplacesIt() {
        let (view, window) = tileView(percent: 40)
        defer { window.isHidden = true }
        var levels: [Int] = []
        var power: [Bool] = []
        view.onBrightness = { levels.append($0) }
        view.onPower = { power.append($0) }
        let tile = glassTile(in: view)
        tile?.accessibilityIncrement()
        tile?.accessibilityDecrement()
        XCTAssertEqual(levels, [40 + BrightnessTile.step, 40], "the second adjust steps from the optimistic level the first one showed")
        tile?.onPerform?(BrightnessTile.powerId)
        XCTAssertEqual(power, [false], "a lit light is turned off")
        view.update(fillTint: nil, percent: 70, isUnavailable: false)
        XCTAssertEqual(view.percent, 70)
    }

    func testUpdatingTheTilesTitleSymbolAndTintShowsThemAndAnUnavailableTileCannotBeAdjusted() {
        let (view, window) = tileView(percent: 0)
        defer { window.isHidden = true }
        view.update(title: "Reading Lamp", symbol: "lamp.desk", tint: .systemOrange, fillTint: .systemOrange, percent: 0, isUnavailable: false)
        XCTAssertEqual(view.title, "Reading Lamp")
        XCTAssertEqual(view.symbol, "lamp.desk")
        XCTAssertEqual(view.tint, .systemOrange)
        XCTAssertTrue(HostedPage.labels(in: view).contains("Reading Lamp"))
        var levels = 0
        view.onBrightness = { _ in levels += 1 }
        view.update(fillTint: nil, percent: 50, isUnavailable: true)
        glassTile(in: view)?.accessibilityIncrement()
        XCTAssertEqual(levels, 0, "an unavailable light sends nothing")
        XCTAssertFalse(glassTile(in: view)?.accessibilityTraits.contains(.adjustable) ?? true)
    }

    func testATileThatOpensDetailsOpensOnTapAndAFlipOtherwise() {
        let (view, window) = tileView(percent: 100)
        defer { window.isHidden = true }
        var opened = 0
        var power: [Bool] = []
        view.onPower = { power.append($0) }
        glassTile(in: view)?.action?()
        XCTAssertEqual(power, [false], "a plain tile flips power on tap")
        view.onOpen = { opened += 1 }
        glassTile(in: view)?.action?()
        XCTAssertEqual(opened, 1)
        XCTAssertEqual(power, [false], "an opening tile does not flip")
        view.update(fillTint: nil, percent: 100, isUnavailable: true)
        XCTAssertEqual(view.sizeThatFits(CGSize(width: 170, height: 0)).height, view.gridHeight(forWidth: 170), accuracy: 0.5)
    }

    func testDraggingSetsTheLevelUnderTheFingerAndACancelledDragSendsNothing() {
        let (view, window) = tileView(percent: 20)
        defer { window.isHidden = true }
        var levels: [Int] = []
        view.onBrightness = { levels.append($0) }
        let tile = glassTile(in: view)
        let pan = tile?.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer }.first
        XCTAssertNotNil(pan)
        let scripted = BrightnessPan()
        scripted.speed = CGPoint(x: 120, y: 10)
        XCTAssertTrue(view.gestureRecognizerShouldBegin(scripted), "a mostly horizontal drag begins")
        scripted.speed = CGPoint(x: 10, y: 120)
        XCTAssertFalse(view.gestureRecognizerShouldBegin(scripted), "a vertical one is the page's scroll")
        XCTAssertTrue(view.gestureRecognizerShouldBegin(UITapGestureRecognizer()))
        let handle = NSSelectorFromString("handlePan:")
        let width = tile?.bounds.width ?? 170
        scripted.scriptedState = .began
        scripted.travel = CGPoint(x: 30, y: 0)
        scripted.point = CGPoint(x: width * 0.25, y: 40)
        view.perform(handle, with: scripted)
        scripted.scriptedState = .changed
        scripted.point = CGPoint(x: width * 0.55, y: 40)
        view.perform(handle, with: scripted)
        view.layoutIfNeeded()
        scripted.scriptedState = .ended
        view.perform(handle, with: scripted)
        XCTAssertEqual(levels.count, 1)
        XCTAssertEqual(Double(levels.first ?? 0), 55, accuracy: 6, "the level under the finger on release")
        scripted.scriptedState = .began
        scripted.point = CGPoint(x: width * 0.9, y: 40)
        view.perform(handle, with: scripted)
        scripted.scriptedState = .cancelled
        view.perform(handle, with: scripted)
        scripted.scriptedState = .possible
        view.perform(handle, with: scripted)
        XCTAssertEqual(levels.count, 1, "a cancelled drag commits nothing")
    }

    // MARK: Sheet

    private func page(_ text: String) -> UIViewController {
        let page = UIViewController()
        page.title = text
        return page
    }

    func testEscapeGoesBackOnePageUnlessThePageGuardsItsBackButtonThenClosesOnTheRoot() {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        var options = UKHassModalOptions(title: "Steps", fitKey: "test.escape")
        options.height = .fittedToTopPage
        var closed = 0
        options.onClose = { closed += 1 }
        let modal = UKHassModalController(root: page("One"), options: options)
        modal.present(from: host, animated: false)
        hostedSettle(0.5)
        let guarded = page("Guarded")
        guarded.navigationItem.hidesBackButton = true
        modal.push(guarded, animated: true)
        hostedSettle(0.6)
        XCTAssertFalse(modal.accessibilityPerformEscape(), "a guarded Back is left to its own button")
        XCTAssertEqual(modal.viewControllers.count, 2)
        guarded.navigationItem.hidesBackButton = false
        XCTAssertTrue(modal.accessibilityPerformEscape())
        hostedSettle(0.6)
        XCTAssertEqual(modal.viewControllers.count, 1)
        XCTAssertTrue(modal.accessibilityPerformEscape())
        XCTAssertEqual(closed, 1, "Escape on the root closes")
        modal.dismiss(animated: false)
    }

    func testAFullHeightSheetsGrabberFollowsTheHeightRuleWhenTheSizeClassChanges() {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        var options = UKHassModalOptions(title: "Full", fitKey: "test.full")
        options.height = .full
        let modal = UKHassModalController(root: page("Full"), options: options)
        modal.present(from: host, animated: false)
        hostedSettle(0.5)
        modal.traitOverrides.horizontalSizeClass = .regular
        hostedSettle(0.3)
        XCTAssertEqual(modal.sheetPresentationController?.prefersGrabberVisible, UKSheetPlacement.fillsHeight(in: modal.view.window))
        modal.dismiss(animated: false)
    }

    func testAFittedSheetRefitsWhenItsWindowChangesSizeClass() {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let modal = UKHassModalController(root: page("Fit"), options: UKHassModalOptions(title: "Fit", fitKey: "test.refit"))
        modal.present(from: host, animated: false)
        hostedSettle(0.5)
        modal.traitOverrides.horizontalSizeClass = .regular
        hostedSettle(0.4)
        XCTAssertFalse(modal.sheetPresentationController?.detents.isEmpty ?? true)
        modal.dismiss(animated: false)
    }

    func testTheCloseOnlyBarStaysInTheSheetsBarAndPushedPagesReportTheirHeaderKind() {
        var options = UKHassModalOptions(title: "Bar", fitKey: "test.bar")
        options.closeStaysInBar = true
        options.height = .fittedToTopPage
        let modal = UKHassModalController(root: page("Bar"), options: options)
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        modal.present(from: host, animated: false)
        hostedSettle(0.5)
        if #available(iOS 27.1, *) {
            XCTAssertEqual(modal.preferredVerticalBarBehavior, UKSheetPlacement.fillsHeight(in: modal.view.window) ? .automatic : .disabled)
            XCTAssertNil(modal.childForPreferredVerticalBarBehavior)
        }
        modal.push(page("Next"), animated: true)
        hostedSettle(0.6)
        XCTAssertEqual(modal.viewControllers.count, 2)
        modal.dismiss(animated: false)
    }

    func testAModalPageWithoutAGroundTakesTheSystemGround() {
        let bare = UIViewController()
        bare.view.backgroundColor = .clear
        UKHassModal.applyChrome(to: bare, options: UKHassModalOptions(title: "Bare", fitKey: "test.bare"), dismiss: nil, isRoot: true)
        XCTAssertEqual(bare.view.backgroundColor, UKDesignSurface.systemGround)
        XCTAssertEqual(bare.navigationItem.largeTitleDisplayMode, .never)
    }
}
