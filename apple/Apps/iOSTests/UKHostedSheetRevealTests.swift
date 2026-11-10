import HassCore
import HassDesign
import Observation
import UIKit
import XCTest
@testable import HassUI

/// The modal reveal (`.agents/design/sheet-reveal.md`): the driver that draws it, the centred arc, the tile glyph rule and the
/// regression guard that no other arc draws in a presented chip sheet.
@MainActor
final class UKHostedSheetRevealTests: DemoHouseTestCase {
    /// A page-shaped host: `content` fills it, and `guide` is the arc's centre, inset to stand in for a bar above and a rail beside.
    private func rig(isReady: Bool) -> (host: UIViewController, window: UIWindow, content: UIView, guide: UILayoutGuide, driver: UKContentGateDriver) {
        let host = UIViewController()
        let window = HostedPage.show(host)
        let content = UIView(frame: host.view.bounds)
        content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.addSubview(content)
        let guide = UILayoutGuide()
        host.view.addLayoutGuide(guide)
        NSLayoutConstraint.activate([
            guide.topAnchor.constraint(equalTo: host.view.topAnchor, constant: 120), guide.bottomAnchor.constraint(equalTo: host.view.bottomAnchor, constant: -34),
            guide.leadingAnchor.constraint(equalTo: host.view.leadingAnchor, constant: 60), guide.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
        ])
        let model = ContentGateModel(page: "Test", isReady: isReady, firstLoad: .sheet)
        let driver = UKContentGateDriver(model: model, content: content, arcHost: host.view, arcCenter: guide, label: "Loading Test", isReady: isReady)
        host.view.layoutIfNeeded()
        return (host, window, content, guide, driver)
    }

    func testTheDriverHidesContentUntilPresentedThenFadesItInTogether() {
        let (_, window, content, _, driver) = rig(isReady: true)
        defer { window.isHidden = true }
        XCTAssertEqual(content.alpha, 0)
        XCTAssertTrue(content.accessibilityElementsHidden)
        XCTAssertFalse(content.isUserInteractionEnabled)
        hostedSettle(0.5)
        XCTAssertEqual(content.alpha, 0, "ready content still waits for the presentation")
        driver.presentationCompleted()
        XCTAssertTrue(HostedPage.until(3) { content.alpha == 1 })
        XCTAssertFalse(content.accessibilityElementsHidden)
        XCTAssertTrue(content.isUserInteractionEnabled)
        XCTAssertNil(driver.arc, "ready content never shows the arc")
    }

    func testTheArcIsCentredOnItsGuideOnItsFirstFrameAndGoneAtIdle() {
        let (host, window, content, guide, driver) = rig(isReady: false)
        defer { window.isHidden = true }
        driver.presentationCompleted()
        XCTAssertTrue(HostedPage.until(3) { driver.arc != nil }, "not ready: the arc comes after the grace")
        let arc = driver.arc
        XCTAssertEqual(arc?.accessibilityLabel, "Loading Test")
        XCTAssertEqual(arc?.accessibilityIdentifier, "contentGate.spinner")
        guard let arc else { return }
        // Laid out the moment it was added: its frame is already its centred frame, never the origin.
        let centre = host.view.convert(arc.center, from: arc.superview)
        let expected = CGPoint(x: guide.layoutFrame.midX, y: guide.layoutFrame.midY)
        XCTAssertEqual(centre.x, expected.x, accuracy: 1)
        XCTAssertEqual(centre.y, expected.y, accuracy: 1)
        XCTAssertNotEqual(arc.frame.origin, .zero)
        XCTAssertEqual(arc.frame.width, ArcSpinner.Size.page.diameter, accuracy: 1, "page size, not scaled by text")
        XCTAssertEqual(content.alpha, 0)
        driver.isReady = true
        XCTAssertTrue(HostedPage.until(5) { content.alpha == 1 && driver.arc == nil }, "the arc leaves, then the content shows")
        XCTAssertNil(HostedPage.descendants(of: host.view).first { $0 is UKArcSpinnerView })
    }

    func testANewSymbolOnAFaceWithoutAWindowSetsTheImageWithNoTransition() {
        let environment = UKTileEnvironment()
        let first = UKGlassTileModel(title: "A", symbol: "circle", isActive: false, kind: .state)
        let face = UKGlassTileFaceView(content: first.faceContent(trailingInset: 0, bottomInset: 0))
        face.frame = CGRect(x: 0, y: 0, width: 160, height: 90)
        face.layoutIfNeeded()
        let glyph = { HostedPage.descendants(of: face).compactMap { $0 as? UIImageView }.first { $0.image != nil && $0.bounds.width > 0 } }
        let before = glyph()?.image
        XCTAssertNil(face.window)
        let next = UKGlassTileModel(title: "A", symbol: "thermometer.medium", isActive: false, kind: .state)
        face.apply(next.faceContent(trailingInset: 0, bottomInset: 0), environment: environment)
        XCTAssertNotNil(glyph()?.image)
        XCTAssertNotEqual(glyph()?.image, before, "the new glyph is there at once")
        XCTAssertEqual(glyph()?.layer.animationKeys() ?? [], [], "no symbol transition runs off screen")
    }

    func testAChipSheetTilesCarryTheirRealGlyphFromTheFirstFrame() {
        let store = HomeFixtures.store(environment: [:])
        let context = UKGalleryChrome.context(store: store)
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let modal = UKRoomOverviewSheet.controller(context: context, kind: .climate)
        XCTAssertEqual(modal.options.reveal, .gate(.sheet))
        modal.present(from: host, animated: false)
        let found = { HostedPage.descendants(of: modal.view).compactMap { $0 as? UKGlassTileView } }
        XCTAssertTrue(HostedPage.until(3) { !found().isEmpty }, "the grid lays its tiles out")
        let tiles = found()
        let built = tiles.map(\.model.symbol)
        hostedSettle(0.6)
        XCTAssertEqual(tiles.map(\.model.symbol), built, "no tile changes its glyph after it is built: none starts as a placeholder")
    }

    /// A root page that says when its content can draw, read inside the reveal's observation.
    @Observable
    @MainActor
    final class Readiness: UKRevealReadiness {
        var isContentReady: Bool
        init(ready: Bool) { isContentReady = ready }
    }

    /// A reveal on a bare page in a window, plus the readiness it reads.
    func revealRig(ready: Bool) -> (window: UIWindow, page: UKPageViewController, readiness: Readiness, reveal: UKSheetRevealController) {
        let host = UIViewController()
        let window = HostedPage.show(host)
        let page = UKPageViewController(sheetTitle: "Reveal")
        host.addChild(page)
        page.view.frame = host.view.bounds
        host.view.addSubview(page.view)
        page.didMove(toParent: host)
        page.view.layoutIfNeeded()
        let readiness = Readiness(ready: ready)
        let reveal = UKSheetRevealController(page: page, profile: .sheet, label: "Loading Reveal", readiness: readiness, name: "Reveal")
        return (window, page, readiness, reveal)
    }

    func testAPageThatIsNotReadyShowsTheArcThenFinishesWhenItBecomesReady() {
        let (window, page, readiness, reveal) = revealRig(ready: false)
        defer { window.isHidden = true }
        var finished = 0
        reveal.onFinished = { finished += 1 }
        XCTAssertTrue(reveal.isLoading, "the content area keeps its minimum height from the start")
        XCTAssertNil(reveal.arc)
        reveal.presentationCompleted()
        XCTAssertTrue(HostedPage.until(3) { reveal.arc != nil }, "not ready: the arc comes after the grace")
        XCTAssertEqual(page.contentView.alpha, 0)
        readiness.isContentReady = true
        XCTAssertTrue(HostedPage.until(5) { finished == 1 }, "the content shows, then the reveal lets go")
        XCTAssertEqual(page.contentView.alpha, 1)
        XCTAssertFalse(reveal.isLoading)
        XCTAssertTrue(reveal.isFinished)
        XCTAssertNil(reveal.arc)
    }

    func testCancellingTheRevealDropsTheArcAndStopsLoading() {
        let (window, _, _, reveal) = revealRig(ready: false)
        defer { window.isHidden = true }
        reveal.presentationCompleted()
        XCTAssertTrue(HostedPage.until(3) { reveal.arc != nil })
        reveal.cancel()
        XCTAssertTrue(reveal.isFinished)
        XCTAssertFalse(reveal.isLoading)
        XCTAssertTrue(HostedPage.until(3) { reveal.arc == nil }, "the arc goes with the sheet")
    }

    func testTheArcIsLabelledForTheSheetUnlessTheCallSiteNamesIt() {
        var options = UKHassModalOptions(title: nil)
        XCTAssertEqual(options.spokenRevealLabel, "Loading", "no title: a bare Loading")
        options.title = ""
        XCTAssertEqual(options.spokenRevealLabel, "Loading")
        options.title = "Climate"
        XCTAssertEqual(options.spokenRevealLabel, "Loading Climate")
        options.revealLabel = "Reading the sensors"
        XCTAssertEqual(options.spokenRevealLabel, "Reading the sensors")
    }

    func testOnlyAModalWithARevealOffersItsReadinessTracker() {
        let store = HomeFixtures.store(environment: [:])
        let context = UKGalleryChrome.context(store: store)
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let modal = UKRoomOverviewSheet.controller(context: context, kind: .lights)
        XCTAssertNil(modal.revealTracker, "nothing is attached before the sheet appears")
        modal.present(from: host, animated: true)
        XCTAssertTrue(HostedPage.until(3) { modal.revealTracker != nil }, "children of the root can hold the fade-in while the reveal runs")
        XCTAssertTrue(HostedPage.until(5) { modal.revealTracker == nil }, "once the content has shown the tracker is gone")
        modal.dismiss(animated: false)
    }

    func testTheRiseFollowsTheProfileAndIsOffUnderReduceMotion() {
        XCTAssertEqual(UKContentReveal.rise(reduceMotion: false, profile: .sheet), ContentGateModel.Profile.sheet.contentRise)
        XCTAssertEqual(UKContentReveal.rise(reduceMotion: false), ContentGateModel.Profile.page.contentRise)
        XCTAssertEqual(UKContentReveal.rise(reduceMotion: true), 0)
    }

    func testRevealingHeldBackContentFadesItInAndReportsCompletion() {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let content = UIView(frame: host.view.bounds)
        host.view.addSubview(content)
        UKContentReveal.hold(content)
        XCTAssertEqual(content.alpha, 0)
        XCTAssertTrue(content.accessibilityElementsHidden)
        var done = false
        UKContentReveal.reveal(content, animated: true, profile: .sheet) { done = true }
        XCTAssertTrue(HostedPage.until(3) { done })
        XCTAssertEqual(content.alpha, 1)
        XCTAssertEqual(content.transform, .identity)
        XCTAssertTrue(content.isUserInteractionEnabled)
    }

    func testAGateViewExposesItsModelTrackerAndReadiness() {
        let gate = UKContentGateView(page: "Pantry", isReady: false, label: "Loading Pantry", content: UIView())
        XCTAssertFalse(gate.isReady)
        XCTAssertEqual(gate.model.phase, .loading)
        XCTAssertTrue(gate.tracker === gate.model.tracker)
        gate.isReady = true
        XCTAssertTrue(gate.isReady)
    }

    #if DEBUG
    func testTheDebugHoldKeepsReadyContentBackUntilItEnds() {
        setenv("FENTON_SHEET_REVEAL_HOLD_MS", "400", 1)
        defer { unsetenv("FENTON_SHEET_REVEAL_HOLD_MS") }
        let (window, page, _, reveal) = revealRig(ready: true)
        defer { window.isHidden = true }
        var finished = 0
        reveal.onFinished = { finished += 1 }
        reveal.presentationCompleted()
        XCTAssertEqual(page.contentView.alpha, 0, "held: ready content still waits")
        XCTAssertEqual(finished, 0)
        XCTAssertTrue(HostedPage.until(5) { finished == 1 }, "when the hold ends the content shows")
        XCTAssertEqual(page.contentView.alpha, 1)
    }
    #endif

    /// Regression guard for the owner's "arc clipped at the sheet's leading edge": while a chip sheet slides up and settles, the only
    /// arc anywhere in it (view tree and navigation bar) is the reveal's own, and it is never at the origin or off the sheet.
    func testNoStrayArcDrawsInAPresentedChipSheet() {
        let store = HomeFixtures.store(environment: [:])
        let context = UKGalleryChrome.context(store: store)
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        for kind in [RoomOverviewKind.climate, .occupancy] {
            let modal = UKRoomOverviewSheet.controller(context: context, kind: kind)
            modal.present(from: host, animated: true)
            var strays: [String] = []
            for _ in 0..<12 {
                let arcs = HostedPage.descendants(of: window).compactMap { $0 as? UKArcSpinnerView }
                for arc in arcs where arc.accessibilityIdentifier != "contentGate.spinner" {
                    var chain: [String] = []
                    var view: UIView? = arc
                    while let current = view { chain.append(String(describing: type(of: current))); view = current.superview }
                    strays.append("\(arc.accessibilityLabel ?? "?") @ \(arc.convert(arc.bounds, to: nil)) in \(chain.joined(separator: " < "))")
                }
                hostedSettle(0.06)
            }
            XCTAssertEqual(strays, [], "\(kind): no arc other than the reveal's centred one")
            modal.dismiss(animated: false)
            hostedSettle(0.2)
        }
    }
}
