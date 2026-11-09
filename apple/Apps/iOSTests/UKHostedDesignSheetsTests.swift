import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// A pan recognizer that reports what the test says, so a slider's drag handling runs without a touch.
private final class ScriptedPan: UIPanGestureRecognizer {
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

/// The shared sheet beyond its basics (pushed pages, iPad widths, the Duo's full-height rule), the tile's controls changing shape and
/// moving, the volume slider's drag and the floating bar on a split window.
@MainActor
final class UKHostedDesignSheetsTests: XCTestCase {
    private func page(_ text: String) -> UIViewController {
        let page = UIViewController()
        let label = UILabel()
        label.text = text
        label.frame = CGRect(x: 20, y: 100, width: 200, height: 30)
        page.view.addSubview(label)
        page.title = text
        return page
    }

    // MARK: Sheet

    func testASheetFittedToItsTopPageFollowsPushesAndPops() {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        var options = UKHassModalOptions(title: "Steps", fitKey: "test.top")
        options.height = .fittedToTopPage
        let modal = UKHassModalController(root: page("One"), options: options)
        modal.present(from: host, animated: false)
        hostedSettle(0.5)
        modal.push(page("Two"), animated: false)
        hostedSettle(0.4)
        XCTAssertEqual(modal.viewControllers.count, 2)
        XCTAssertEqual(modal.topViewController?.navigationItem.title, "Two")
        modal.popViewController(animated: false)
        hostedSettle(0.4)
        XCTAssertEqual(modal.viewControllers.count, 1)
        XCTAssertFalse(modal.sheetPresentationController?.detents.isEmpty ?? true, "the sheet keeps a detent while pages come and go")
        modal.setViewControllers([page("Replaced")], animated: false)
        XCTAssertEqual(modal.viewControllers.first?.navigationItem.title, "Replaced")
        modal.dismiss(animated: false)
    }

    func testAnIPadHostPresentsAFormSheetAtTheFormWidthAndAPageSheetOtherwise() {
        let host = UIViewController()
        let window = HostedPage.show(host, size: CGSize(width: 1024, height: 768))
        defer { window.isHidden = true }
        host.traitOverrides.horizontalSizeClass = .regular
        let form = UKHassModalController(root: page("Form"), options: UKHassModalOptions(title: "Form", fitKey: "test.ipad.form"))
        form.present(from: host, animated: false)
        hostedSettle(0.5)
        XCTAssertEqual(form.modalPresentationStyle, .formSheet)
        XCTAssertEqual(form.preferredContentSize.width, HassFormSheetSize.width, "a form sheet is the form width on iPad")
        form.dismiss(animated: false)
        hostedSettle(0.4)

        var wide = UKHassModalOptions(title: "Grid", fitKey: "test.ipad.page")
        wide.width = .page
        let grid = UKHassModalController(root: page("Grid"), options: wide)
        grid.present(from: host, animated: false)
        hostedSettle(0.5)
        XCTAssertEqual(grid.modalPresentationStyle, .pageSheet)
        grid.dismiss(animated: false)
    }

    func testAFormSheetKeepsItsHeightWhenPresentedAgainBecauseTheBarIsNotCountedTwice() {
        let host = UIViewController()
        let window = HostedPage.show(host, size: CGSize(width: 1024, height: 768))
        defer { window.isHidden = true }
        host.traitOverrides.horizontalSizeClass = .regular
        let form = UKHassModalController(root: page("Form"), options: UKHassModalOptions(title: "Form", fitKey: "test.ipad.again"))
        form.present(from: host, animated: false)
        hostedSettle(0.5)
        let first = form.preferredContentSize.height
        form.dismiss(animated: false)
        hostedSettle(0.4)
        form.present(from: host, animated: false)
        hostedSettle(0.5)
        XCTAssertEqual(form.preferredContentSize.height, first, accuracy: 0.5, "presenting again must not add the navigation bar's height again")
        form.dismiss(animated: false)
    }

    func testBesideTheHingeOrOnTheFoldedScreenASheetTakesTheLargeDetentOnly() {
        UKDeviceSignals.verticalBarOverride = { _ in true }
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        XCTAssertTrue(UKSheetPlacement.hasHinge(in: window), "the vertical bar means a Duo")
        XCTAssertTrue(UKSheetPlacement.fillsHeight(in: window))
        let modal = UKHassModalController(root: page("Folded"), options: UKHassModalOptions(title: "Folded", fitKey: "test.folded"))
        modal.present(from: host, animated: false)
        hostedSettle(0.5)
        XCTAssertEqual(modal.sheetPresentationController?.detents.count, 1, "one full-height detent")
        XCTAssertEqual(modal.sheetPresentationController?.prefersGrabberVisible, true, "the grabber stays where every sheet fills the height")
        modal.dismiss(animated: false)
    }

    func testASheetBesideAVerticalHingeSizesToTheLeadingHalfAndRestoresItsSizeAfter() {
        // The phone's rule (no hinge, no vertical bar) on every family: the folded Duo simulator reports a vertical bar, which makes
        // every sheet fill the height and keep its grabber (``UKSheetPlacement/fillsHeight(in:)``).
        UKDeviceSignals.verticalBarOverride = { _ in false }
        let host = UIViewController()
        let window = HostedPage.show(host, size: CGSize(width: 1000, height: 700))
        defer { window.isHidden = true }
        UKDeviceSignals.regionsOverride = { view, _ in view === host.view ? [(CGRect(x: 488, y: 0, width: 24, height: 700), true)] : [] }
        let half = UKSheetPlacement.leadingHalfSize(in: window)
        XCTAssertNotNil(half, "beside a vertical hinge a sheet takes the leading half")
        XCTAssertLessThanOrEqual(half?.width ?? 0, 488)
        let modal = UKHassModalController(root: page("Half"), options: UKHassModalOptions(title: "Half", fitKey: "test.half"))
        modal.preferredContentSize = CGSize(width: 400, height: 500)
        // A navigation controller reports its visible bar on top of what it is given; the sheet's own size is what it reports.
        // A form sheet in a regular window takes the form width when it is presented; the height stays its own.
        let own = CGSize(width: HassFormSheetSize.width, height: 500 + modal.navigationBar.frame.height)
        XCTAssertEqual(modal.preferredContentSize.height, own.height)
        // The form width is applied only when the presenter is regular (iPad, the unfolded Duo). The hosted window sits in an
        // iPhone scene, whose width class stays compact whatever the window's size, so the presenter is made regular here.
        host.traitOverrides.horizontalSizeClass = .regular
        HostedPage.until { host.traitCollection.horizontalSizeClass == .regular }
        XCTAssertEqual(host.traitCollection.horizontalSizeClass, .regular)
        modal.present(from: host, animated: false)
        hostedSettle(0.5)
        let sheet = modal.sheetPresentationController
        XCTAssertEqual(sheet?.prefersPageSizing, false)
        XCTAssertEqual(half?.height, 700 - 2 * DuoSheetPolicy.halfMargin, "the half is the window's height less the system's margin top and bottom")
        // The scene may resize the window once the sheet is up; the sheet follows the window it sits in, not the height at first look.
        let now = UKSheetPlacement.leadingHalfSize(in: window)
        XCTAssertEqual(modal.preferredContentSize.width, half?.width, "the leading half's width")
        XCTAssertEqual(modal.preferredContentSize.height, window.bounds.height - 2 * DuoSheetPolicy.halfMargin, "full window height less the margin")
        XCTAssertEqual(modal.preferredContentSize, now, "the sheet is the half of the window it sits in now")
        UKDeviceSignals.regionsOverride = { _, _ in [] }
        UKSheetPlacement.place(sheet, in: window)
        XCTAssertEqual(modal.preferredContentSize, own, "leaving the half gives the sheet its own size back")
        modal.dismiss(animated: false)
    }

    func testASizeIsReportedAsAskedWhateverBarsTheNavigationControllerAddsToIt() {
        /// Adds a vertical bar's width and a top bar's height to what it is given, as the Duo's navigation controller does once its
        /// sheet is up (580 read back 668, 2026-11-04).
        final class Barred: UINavigationController {
            private var given = CGSize.zero
            override var preferredContentSize: CGSize {
                get { given == .zero ? .zero : CGSize(width: given.width + 88, height: given.height + navigationBar.frame.height) }
                set { given = newValue }
            }
        }
        let barred = Barred(rootViewController: page("Barred"))
        barred.loadViewIfNeeded()
        UKSheetPlacement.setContentSize(CGSize(width: 580, height: 558), on: barred)
        XCTAssertEqual(barred.preferredContentSize, CGSize(width: 580, height: 558), "the bars are taken off what it is given")
        let plain = UIViewController()
        UKSheetPlacement.setContentSize(CGSize(width: 480, height: 684), on: plain)
        XCTAssertEqual(plain.preferredContentSize, CGSize(width: 480, height: 684), "a controller without bars gets the size as it is")
    }

    func testResizingTheWindowKeepsTheSheetAndItsGrabberRule() {
        // The phone's rule (no hinge, no vertical bar) on every family: the folded Duo simulator reports a vertical bar, which makes
        // every sheet fill the height and keep its grabber (``UKSheetPlacement/fillsHeight(in:)``).
        UKDeviceSignals.verticalBarOverride = { _ in false }
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        var options = UKHassModalOptions(title: "Remote", fitKey: "test.resize")
        options.height = .full
        let full = UKHassModalController(root: page("Remote"), options: options)
        full.present(from: host, animated: false)
        hostedSettle(0.4)
        window.frame = CGRect(x: 0, y: 0, width: 600, height: 500)
        hostedSettle(0.6)
        XCTAssertEqual(full.sheetPresentationController?.detents.count, 1)
        XCTAssertEqual(full.sheetPresentationController?.prefersGrabberVisible, false, "a one-detent sheet promises no resize")
        full.dismiss(animated: false)
        hostedSettle(0.4)

        let fitted = UKHassModalController(root: page("Fitted"), options: UKHassModalOptions(title: "Fitted", fitKey: "test.resize.fitted"))
        fitted.present(from: host, animated: false)
        hostedSettle(0.4)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        hostedSettle(0.6)
        XCTAssertFalse(fitted.sheetPresentationController?.detents.isEmpty ?? true)
        fitted.dismiss(animated: false)
    }

    // MARK: Tile controls

    private func discs(in tile: UIView) -> [UKTileActionDisc] { HostedPage.descendants(of: tile).compactMap { $0 as? UKTileActionDisc } }

    private func remote(_ count: Int, subtitle: String) -> UKGlassTileModel {
        let items = [TileActionItem(id: "a", verb: "Pause", symbol: "pause.fill"), TileActionItem(id: "b", verb: "Next", symbol: "forward.fill"),
                     TileActionItem(id: "c", verb: "Prev", symbol: "backward.fill")]
        return UKGlassTileModel(title: "Remote", subtitle: subtitle, symbol: "tv", isActive: true, behavior: .perform("a"), actions: Array(items.prefix(count)))
    }

    func testControlsChangedWhileThePageScrollsWaitForItToStopThenAppear() {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 393, height: 600))
        scroll.contentSize = CGSize(width: 393, height: 2000)
        scroll.ukPausesTickersWhileScrolling()
        let tile = UKGlassTileView(model: remote(1, subtitle: "Off"))
        tile.gridFullRow = true
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        host.view.addSubview(scroll)
        scroll.addSubview(tile)
        tile.frame = CGRect(x: 10, y: 20, width: 300, height: tile.gridHeight(forWidth: 300))
        tile.layoutIfNeeded()
        XCTAssertEqual(discs(in: tile).count, 1)
        scroll.contentOffset = CGPoint(x: 0, y: 40)
        XCTAssertEqual(UKTickerScrollGate.nearest(above: tile)?.isScrolling, true)
        tile.configure(remote(3, subtitle: "Playing"), animated: true)
        tile.layoutIfNeeded()
        XCTAssertEqual(discs(in: tile).count, 1, "the old disc stays while the page moves")
        HostedPage.until(3) { UKTickerScrollGate.nearest(above: tile)?.isScrolling == false }
        HostedPage.wait(1.0)
        tile.layoutIfNeeded()
        XCTAssertEqual(discs(in: tile).count, 3, "once the page rests the three controls show")
    }

    func testControlsArriveAtOnceRightAfterTheWholeStateIsHandedBack() {
        var first = remote(1, subtitle: "Off")
        first.reapplyGeneration = 1
        let tile = UKGlassTileView(model: first)
        tile.gridFullRow = true
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        host.view.addSubview(tile)
        tile.frame = CGRect(x: 10, y: 80, width: 300, height: tile.gridHeight(forWidth: 300))
        var again = remote(3, subtitle: "Playing")
        again.reapplyGeneration = 2
        tile.configure(again, animated: true)
        tile.layoutIfNeeded()
        XCTAssertEqual(discs(in: tile).count, 3, "a reconnect or cold launch reshapes the tile without motion")
    }

    func testAnAccessoryFillsTheTrailingEdgeOrDropsBelowAtLargeText() {
        let tile = UKGlassTileView(model: UKGlassTileModel(title: "Speaker", subtitle: "Playing", symbol: "hifispeaker", isActive: true,
                                                          behavior: .navigate, identifier: "tile.speaker"))
        let accessory = UIView(frame: CGRect(x: 0, y: 0, width: 60, height: 30))
        accessory.addConstraints([accessory.widthAnchor.constraint(equalToConstant: 60), accessory.heightAnchor.constraint(equalToConstant: 30)])
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        host.view.addSubview(tile)
        tile.setAccessory(accessory)
        tile.frame = CGRect(x: 10, y: 80, width: 340, height: 90)
        tile.layoutIfNeeded()
        XCTAssertFalse(accessory.isHidden)
        XCTAssertGreaterThan(accessory.frame.minX, tile.bounds.midX, "the accessory sits at the trailing edge")
        XCTAssertLessThan(accessory.frame.maxX, tile.bounds.width, "and leaves room for the chevron")
        XCTAssertEqual(accessory.frame.midY, tile.bounds.midY, accuracy: 1, "centred on the row")

        tile.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        tile.frame = CGRect(x: 10, y: 80, width: 340, height: tile.gridHeight(forWidth: 340))
        tile.layoutIfNeeded()
        XCTAssertLessThan(accessory.frame.minX, tile.bounds.midX, "at large text the accessory leads, below the words")
        XCTAssertGreaterThan(accessory.frame.midY, tile.bounds.midY)

        var hidden = UKGlassTileModel(title: "Speaker", subtitle: "Off", symbol: "hifispeaker", isActive: false, behavior: .navigate)
        hidden.accessoryShown = false
        tile.configure(hidden, animated: false)
        tile.layoutIfNeeded()
        XCTAssertTrue(accessory.isHidden, "an accessory the model hides leaves the row")
    }

    func testASelectionDiscShowsAnArcWhileItsCommandIsInFlightAndTheChoiceAfter() {
        let ready = TileActionItem(id: "s", verb: "Pick", symbol: "star", feedback: .tracked, selection: .single(isSelected: false))
        let pending = TileActionItem(id: "s", verb: "Pick", symbol: "star", phase: .inFlight, feedback: .tracked, selection: .single(isSelected: true))
        let disc = UKTileActionDisc(item: ready, face: .dark, family: nil, surface: .page, title: "Lamp", identifier: "disc")
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        host.view.addSubview(disc)
        disc.frame = CGRect(x: 20, y: 80, width: 44, height: 44)
        disc.layoutIfNeeded()
        disc.configure(item: pending, face: .dark, family: nil, surface: .page, title: "Lamp", identifier: "disc", animated: false)
        let arcs = HostedPage.descendants(of: disc).compactMap { $0 as? UKArcSpinnerView }
        XCTAssertEqual(arcs.count, 1)
        XCTAssertFalse(arcs.first?.isHidden ?? true, "the arc shows while the command runs")
        XCTAssertFalse(disc.isEnabled)
        disc.configure(item: ready, face: .dark, family: nil, surface: .page, title: "Lamp", identifier: "disc", animated: false)
        XCTAssertTrue(arcs.first?.isHidden ?? false, "the arc goes when the command is done")
        XCTAssertTrue(disc.isEnabled)
    }

    // MARK: Volume slider drag

    func testDraggingTheVolumeSliderShowsTheLevelAndCommitsOnceOnRelease() {
        var committed: [Int] = []
        let slider = UKTileVolumeSlider(title: "Kitchen", percent: 30, identifier: "vol") { committed.append($0) }
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        host.view.addSubview(slider)
        slider.frame = CGRect(x: 20, y: 80, width: 200, height: 44)
        slider.layoutIfNeeded()
        let pan = ScriptedPan()

        pan.speed = CGPoint(x: 10, y: 200)
        XCTAssertFalse(slider.gestureRecognizerShouldBegin(pan), "a mostly vertical drag scrolls the page instead")
        pan.speed = CGPoint(x: 200, y: 10)
        XCTAssertTrue(slider.gestureRecognizerShouldBegin(pan))
        slider.isDisabled = true
        XCTAssertFalse(slider.gestureRecognizerShouldBegin(pan), "a disabled slider takes no drag")
        slider.isDisabled = false

        func send(_ state: UIGestureRecognizer.State, x: CGFloat, travel: CGPoint) {
            pan.scriptedState = state
            pan.point = CGPoint(x: x, y: 20)
            pan.travel = travel
            slider.perform(NSSelectorFromString("handlePan:"), with: pan)
        }
        send(.began, x: 100, travel: CGPoint(x: 8, y: 1))
        XCTAssertEqual(slider.accessibilityValue, "50 percent", "the level follows the finger")
        send(.changed, x: 150, travel: CGPoint(x: 50, y: 1))
        XCTAssertEqual(slider.accessibilityValue, "75 percent")
        XCTAssertTrue(committed.isEmpty, "nothing is sent mid-drag")
        send(.ended, x: 150, travel: CGPoint(x: 50, y: 1))
        XCTAssertEqual(committed, [75])

        send(.began, x: 40, travel: CGPoint(x: 1, y: 30))
        send(.ended, x: 40, travel: CGPoint(x: 1, y: 30))
        XCTAssertEqual(committed, [75], "a vertical drag never moves the level")
        send(.began, x: 180, travel: CGPoint(x: 20, y: 0))
        send(.cancelled, x: 180, travel: .zero)
        XCTAssertEqual(slider.accessibilityValue, "75 percent", "a cancelled drag drops back to the shown level")
        XCTAssertEqual(committed, [75])
    }

    // MARK: Floating bar

    private func bar(actions: [UKFloatingAction], search: UKFloatingSearch? = nil) -> (UKFloatingActionBar, UIWindow) {
        let bar = UKFloatingActionBar(actions: actions, search: search)
        let host = UIViewController()
        let window = HostedPage.show(host)
        host.view.addSubview(bar)
        bar.frame = CGRect(x: 0, y: 700, width: 393, height: 80)
        bar.layoutIfNeeded()
        return (bar, window)
    }

    func testAtLargeTextSearchIsACircleThatOpensTheFieldAndShowsAnActiveQuery() {
        let search = UKFloatingSearch(prompt: "Search chores")
        let (bar, window) = self.bar(actions: [UKFloatingAction(id: "add", title: "Add Task", symbol: "plus") {}], search: search)
        defer { window.isHidden = true }
        bar.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        hostedSettle(0.3)
        bar.layoutIfNeeded()
        let circle = HostedPage.descendants(of: bar).first { $0.accessibilityIdentifier == "fab.search" } as? UKBarGlassControl
        XCTAssertNotNil(circle, "search is an icon circle at accessibility sizes")
        XCTAssertEqual(circle?.accessibilityLabel, "Search chores")
        XCTAssertFalse(circle?.accessibilityTraits.contains(.selected) ?? true)
        search.text = "milk"
        hostedSettle(0.3)
        let active = HostedPage.descendants(of: bar).first { $0.accessibilityIdentifier == "fab.search" }
        XCTAssertTrue(active?.accessibilityTraits.contains(.selected) ?? false, "a query in the field marks the circle as applied")
        search.text = ""
        hostedSettle(0.3)
        XCTAssertFalse(HostedPage.descendants(of: bar).first { $0.accessibilityIdentifier == "fab.search" }?.accessibilityTraits.contains(.selected) ?? true)
        _ = (HostedPage.descendants(of: bar).first { $0.accessibilityIdentifier == "fab.search" } as? UKBarGlassControl)?.accessibilityActivate()
        hostedSettle(0.4)
        XCTAssertTrue(search.isExpanded, "the circle opens the search field")
    }

    func testASplitWindowKeepsSearchInTheLeadingColumnAndSpellsOutIconActions() {
        let search = UKFloatingSearch(prompt: "Search recipes")
        let (bar, window) = self.bar(actions: [
            UKFloatingAction(id: "add", title: "Add Recipe", symbol: "plus") {},
            UKFloatingAction(id: "filter", title: "Filter", symbol: "line.3.horizontal.decrease", showsTitle: false, isProminent: true) {},
        ], search: search)
        defer { window.isHidden = true }
        bar.setSplit(leadingColumn: 300, expandsActions: true, animated: false)
        bar.layoutIfNeeded()
        XCTAssertEqual(bar.leadingColumn, 300)
        XCTAssertTrue(bar.expandsActions)
        let labelled = HostedPage.descendants(of: bar).compactMap { $0 as? UKBarCapsuleButton }.compactMap(\.accessibilityLabel)
        XCTAssertTrue(labelled.contains("Filter"), "with room to spare an icon action shows as a capsule with its title; saw \(labelled)")
        let collapsed = HostedPage.descendants(of: bar).first { $0 is UKBarSearchCollapsed }
        XCTAssertLessThanOrEqual(collapsed?.frame.width ?? 0, 300, "the search ends at the hinge")
        bar.setSplit(leadingColumn: nil, expandsActions: false, animated: true)
        hostedSettle(0.6)
        XCTAssertNil(bar.leadingColumn)
        XCTAssertFalse(bar.expandsActions)
        bar.setSplit(leadingColumn: nil, expandsActions: false, animated: true)
        bar.setSearch(nil)
        XCTAssertNil(bar.search)
    }
}
