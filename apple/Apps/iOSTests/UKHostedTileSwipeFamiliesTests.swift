import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - Swipe to adjust on every family: the start, the bubble and the sheet

/// Hosted UX and accessibility checks for three Verifier findings on the tile swipe (`sh.tile-swipe@1`, `build/design/tile-swipe.md`), each
/// written for the iPhone, the iPhone Duo and the iPad:
///
/// - **diag-ipad (C1).** A drag that starts about 60 degrees from horizontal belongs to the page's scroll, never to a tile.
/// - **bubble-wide.** The value bubble sits over the band's edge in the wide layouts, in the window's own coordinates.
/// - **ipad-sheet-drag.** A sheet that holds swipe tiles keeps the dismissal machinery it has without them.
///
/// The families are the windows each one draws: the iPhone, the folded Duo, the iPad in both orientations and the unfolded Duo lying flat.
/// Run the class with `tools/ios_uitest.sh --hosted --only iphone|duo|ipad` (`FENTON_HOSTED_FILTER=UKHostedTileSwipeFamiliesTests`).
@MainActor
final class UKHostedTileSwipeFamiliesTests: XCTestCase {
    // MARK: Families

    /// One family's window and the width its tiles get there (`tile-swipe.md` section 1, and the measured wide tiles of the Verifier's pass).
    private struct Family {
        let name: String
        let window: CGSize
        let tileWidth: CGFloat
        /// Whether the window is wide enough to split into two columns (`SplitPolicy`).
        let isWide: Bool
    }

    private static let families = [
        Family(name: "iPhone", window: CGSize(width: 393, height: 852), tileWidth: 179, isWide: false),
        Family(name: "Duo folded", window: CGSize(width: 466, height: 678), tileWidth: 170, isWide: false),
        Family(name: "iPad portrait", window: CGSize(width: 834, height: 1194), tileWidth: 192, isWide: false),
        Family(name: "iPad landscape", window: CGSize(width: 1194, height: 834), tileWidth: 583, isWide: true),
        Family(name: "Duo unfolded landscape", window: CGSize(width: 1338, height: 669), tileWidth: 200, isWide: true),
    ]

    override func tearDown() async throws {
        UKMotion.reduceMotionOverride = nil
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Fixtures

    /// A lamp tile of `width` in a vertical scroller that fills `window`, `x` points from its leading edge.
    private func lamp(in host: UIViewController, width: CGFloat, x: CGFloat = 16, y: CGFloat = 160)
        -> (view: UKBrightnessTileView, tile: UKGlassTileView, scroll: UIScrollView) {
        let scroll = UIScrollView(frame: host.view.bounds)
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.contentSize = CGSize(width: host.view.bounds.width, height: host.view.bounds.height * 2)
        host.view.addSubview(scroll)
        let view = UKBrightnessTileView(title: "Lamp", tint: .systemYellow, percent: 40)
        view.frame = CGRect(x: x, y: y, width: width, height: 90)
        scroll.addSubview(view)
        view.layoutIfNeeded()
        let tile = HostedPage.descendants(of: view).compactMap { $0 as? UKGlassTileView }.first!
        return (view, tile, scroll)
    }

    /// Plays `fractions` of the tile's width as one touch, ending as `end`.
    private func drag(_ controller: UKTileSwipeController, tile: UIView, _ fractions: [Double], end: UIGestureRecognizer.State = .possible) {
        let pan = ScriptedSwipePan()
        let selector = NSSelectorFromString("panned:")
        for (index, fraction) in fractions.enumerated() {
            pan.scriptedState = index == 0 ? .began : .changed
            pan.point = CGPoint(x: tile.bounds.width * fraction, y: 40)
            controller.perform(selector, with: pan)
        }
        pan.scriptedState = end
        controller.perform(selector, with: pan)
    }

    /// A pan that has travelled `distance` points at `degrees` above horizontal, moving at 120 pt/s the same way.
    private func stroke(degrees: Double, distance: CGFloat = 12) -> ScriptedSwipePan {
        let radians = degrees * .pi / 180
        let pan = ScriptedSwipePan()
        pan.travel = CGPoint(x: distance * cos(radians), y: -distance * sin(radians))
        pan.speed = CGPoint(x: 120 * cos(radians), y: -120 * sin(radians))
        return pan
    }

    // MARK: diag-ipad: the start (C1)

    /// A stroke wider than 45 degrees begins as a swipe; a steeper one is the page's, on every family's window.
    func testAStrokeBeginsAsASwipeOnlyBelowFortyFiveDegreesOnEveryFamily() throws {
        for family in Self.families {
            let host = UIViewController()
            let window = HostedPage.show(host, size: family.window)
            defer { window.isHidden = true }
            let (_, tile, _) = lamp(in: host, width: family.tileWidth)
            let controller = try XCTUnwrap(tile.swipe)
            for degrees in [0.0, 15, 30, 40] {
                XCTAssertTrue(controller.gestureRecognizerShouldBegin(stroke(degrees: degrees)), "\(degrees) degrees begins (\(family.name))")
            }
            for degrees in [50.0, 60, 75, 90] {
                XCTAssertFalse(controller.gestureRecognizerShouldBegin(stroke(degrees: degrees)), "\(degrees) degrees scrolls (\(family.name))")
            }
        }
    }

    /// The Verifier's stroke: 60 degrees from horizontal (dx 60, dy -104). A first sample that leaned sideways made the velocity read
    /// "horizontal" at begin; the stroke's travel says it has gone up the page, so the scroll keeps it and the value never changes.
    func testASixtyDegreeStartWithASidewaysFirstSampleIsTheScrollsOnEveryFamily() throws {
        for family in Self.families {
            let host = UIViewController()
            let window = HostedPage.show(host, size: family.window)
            defer { window.isHidden = true }
            let (view, tile, _) = lamp(in: host, width: family.tileWidth)
            var levels: [Int] = []
            view.onBrightness = { levels.append($0) }
            let controller = try XCTUnwrap(tile.swipe)
            let pan = stroke(degrees: 60)
            pan.speed = CGPoint(x: 40, y: -10)
            XCTAssertTrue(pan.velocity(in: nil).x > abs(pan.velocity(in: nil).y), "the first sample reads horizontal: the velocity-only rule began here")
            XCTAssertFalse(controller.gestureRecognizerShouldBegin(pan), "the travel says 60 degrees (\(family.name))")
            // A pan the delegate refuses never reaches the action: the driver here does what UIKit does.
            if controller.gestureRecognizerShouldBegin(pan) { drag(controller, tile: tile, [0.0, 0.3], end: .ended) }
            XCTAssertEqual(levels, [], "no call (\(family.name))")
            XCTAssertNil(controller.dragValue)
            XCTAssertEqual(controller.sampleCount, 0, "not one sample was taken")
            XCTAssertEqual(try XCTUnwrap(tile.face.content.level), 0.4, accuracy: 0.001, "the band stays where it was")
        }
    }

    /// A stroke that begins sideways in both measures still swipes, with or without a slight dip, and a touch that has not travelled yet is
    /// judged by its velocity (the rule's floor).
    func testASidewaysStrokeStillBeginsAndAStationaryTouchIsJudgedByVelocity() throws {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let (_, tile, _) = lamp(in: host, width: 179)
        let controller = try XCTUnwrap(tile.swipe)
        let dip = ScriptedSwipePan()
        dip.travel = CGPoint(x: 14, y: 5)
        dip.speed = CGPoint(x: 100, y: 30)
        XCTAssertTrue(controller.gestureRecognizerShouldBegin(dip))
        let still = ScriptedSwipePan()
        still.travel = .zero
        still.speed = CGPoint(x: 90, y: 10)
        XCTAssertTrue(controller.gestureRecognizerShouldBegin(still), "no travel yet: velocity decides")
        still.speed = CGPoint(x: 10, y: 90)
        XCTAssertFalse(controller.gestureRecognizerShouldBegin(still))
        let reversed = ScriptedSwipePan()
        reversed.travel = CGPoint(x: 4, y: -12)
        reversed.speed = CGPoint(x: 120, y: 20)
        XCTAssertFalse(controller.gestureRecognizerShouldBegin(reversed), "sideways velocity cannot override a stroke that went up the page")
    }

    /// The rule is the tile's own and says nothing of VoiceOver: the two named actions and increment still step the value.
    func testVoiceOverStillStepsATileWhoseVerticalStartsAreRefused() throws {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let (view, tile, _) = lamp(in: host, width: 179)
        var levels: [Int] = []
        view.onBrightness = { levels.append($0) }
        XCTAssertFalse(try XCTUnwrap(tile.swipe).gestureRecognizerShouldBegin(stroke(degrees: 90)))
        let body = try XCTUnwrap(tile.accessibilityElements?.first as? NSObject)
        body.accessibilityIncrement()
        XCTAssertEqual(levels, [50])
    }

    // MARK: bubble-wide: the bubble over the band's edge

    /// The bubble's centre and the band's right edge, both in the window's coordinates.
    private func bubbleAndEdge(_ tile: UKGlassTileView, _ controller: UKTileSwipeController, in window: UIWindow) -> (bubble: CGFloat, edge: CGFloat) {
        let edge = window.convert(CGPoint(x: tile.face.drawnBandFrame.maxX, y: 0), from: tile.face).x
        let bubble = window.convert(CGPoint(x: controller.bubble.center.x, y: 0), from: tile).x
        return (bubble, edge)
    }

    /// In every family's window, at every width the wide layouts give a tile, the bubble is centred on the band's edge wherever the edge leaves
    /// room for it, and flush with the tile's own edge at the two ends. A tile far from the window's origin (the trailing column) is the case
    /// that a coordinate-space slip would show.
    func testTheBubbleIsCentredOnTheBandEdgeInTheWindowsCoordinatesOnEveryFamily() throws {
        for family in Self.families {
            let host = UIViewController()
            let window = HostedPage.show(host, size: family.window)
            defer { window.isHidden = true }
            // Half-way across the window, like a tile in the trailing column.
            let x = family.isWide ? family.window.width - family.tileWidth - 24 : 16
            let (_, tile, _) = lamp(in: host, width: family.tileWidth, x: x)
            let controller = try XCTUnwrap(tile.swipe)
            for fraction in [0.25, 0.5, 0.75] {
                drag(controller, tile: tile, [0.5, fraction])
                let (bubble, edge) = bubbleAndEdge(tile, controller, in: window)
                XCTAssertEqual(bubble, edge, accuracy: 1, "bubble over the band edge at \(Int(fraction * 100))% (\(family.name), tile \(family.tileWidth) pt)")
                controller.cancel()
            }
            let size = controller.bubble.frame.size
            XCTAssertLessThanOrEqual(size.width, 100, "a capsule the width of its text, not of the tile (\(family.name))")
            XCTAssertEqual(size.height, 32, accuracy: 0.5)
            drag(controller, tile: tile, [0.5, 0.0])
            let low = window.convert(controller.bubble.frame, from: tile)
            let tileFrame = window.convert(tile.bounds, from: tile)
            XCTAssertEqual(low.minX, tileFrame.minX, accuracy: 1, "flush with the leading edge at the minimum (\(family.name))")
            controller.cancel()
            drag(controller, tile: tile, [0.5, 1.0])
            let high = window.convert(controller.bubble.frame, from: tile)
            XCTAssertEqual(high.maxX, tileFrame.maxX, accuracy: 1, "flush with the trailing edge at the maximum (\(family.name))")
            controller.cancel()
        }
    }

    /// The same, in the shell's own split container: the tile is the trailing column's page, set by `UKColumnsViewController`.
    func testTheBubbleIsCentredOnTheBandEdgeInTheTrailingColumnOfTheSplitLayouts() throws {
        for family in Self.families where family.isWide {
            let owner = HostedColumnOwner()
            let root = UIViewController()
            let columns = UKColumnsViewController(rootController: root, shell: nil) {
                UKPanePlaceholderViewController(symbol: "lightbulb", text: "Select", identifier: "pane.empty")
            }
            owner.addChild(columns)
            owner.view.addSubview(columns.view)
            columns.view.frame = owner.view.bounds
            columns.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            columns.didMove(toParent: owner)
            let window = HostedPage.show(owner, size: family.window)
            defer { window.isHidden = true }
            columns.setWide(true)
            owner.view.layoutIfNeeded()
            let page = UIViewController()
            columns.open(page, tag: "lights")
            HostedPage.wait(0.5)
            HostedPage.until { page.view.window != nil && page.view.bounds.width > 100 }
            page.view.layoutIfNeeded()
            let width = min(family.tileWidth, page.view.bounds.width - 32)
            let (_, tile, _) = lamp(in: page, width: width)
            let controller = try XCTUnwrap(tile.swipe)
            XCTAssertGreaterThan(window.convert(tile.bounds, from: tile).minX, family.window.width / 4, "the tile sits in the trailing column (\(family.name))")
            for fraction in [0.25, 0.5, 0.75] {
                drag(controller, tile: tile, [0.5, fraction])
                let (bubble, edge) = bubbleAndEdge(tile, controller, in: window)
                XCTAssertEqual(bubble, edge, accuracy: 1, "bubble over the band edge at \(Int(fraction * 100))% in the split (\(family.name))")
                controller.cancel()
            }
        }
    }

    /// The tile is lifted by 1.03 while it drags; the bubble is its child, so the two scale together and the gap stays the design's 8 pt
    /// scaled with the tile.
    func testTheLiftScalesTheBubbleWithTheBandSoTheyNeverDriftApart() throws {
        let family = Self.families[3]
        let host = UIViewController()
        let window = HostedPage.show(host, size: family.window)
        defer { window.isHidden = true }
        let (_, tile, _) = lamp(in: host, width: family.tileWidth, x: 300)
        let controller = try XCTUnwrap(tile.swipe)
        drag(controller, tile: tile, [0.5, 0.9])
        XCTAssertEqual(tile.transform.a, 1.03, accuracy: 0.001)
        let (bubble, edge) = bubbleAndEdge(tile, controller, in: window)
        XCTAssertEqual(bubble, edge, accuracy: 1, "a wide tile at the lift's scale still has its bubble on the band")
        controller.cancel()
    }

    // MARK: ipad-sheet-drag: the sheet keeps its dismissal

    /// A sheet whose page holds two swipe tiles, and the same page with none.
    private func present(tiles: Bool, family: Family, style: UIModalPresentationStyle? = nil, width: HassSheetWidth = .form)
        -> (modal: UKHassModalController, window: UIWindow, tiles: [UKGlassTileView]) {
        let host = UIViewController()
        let window = HostedPage.show(host, size: family.window)
        // A regular width, as the iPad has, on any simulator.
        window.traitOverrides.horizontalSizeClass = family.window.width >= 600 ? .regular : .compact
        host.view.layoutIfNeeded()
        HostedPage.wait(0.2)
        let page = UIViewController()
        page.title = "Lights"
        var found: [UKGlassTileView] = []
        if tiles {
            let scroll = UIScrollView(frame: CGRect(origin: .zero, size: CGSize(width: 540, height: 600)))
            scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            scroll.contentSize = CGSize(width: 540, height: 1200)
            page.view.addSubview(scroll)
            for index in 0..<2 {
                let view = UKBrightnessTileView(title: "Lamp \(index + 1)", tint: .systemYellow, percent: 40)
                view.frame = CGRect(x: 16 + CGFloat(index) * 196, y: 24, width: 180, height: 90)
                scroll.addSubview(view)
                view.layoutIfNeeded()
                found += HostedPage.descendants(of: view).compactMap { $0 as? UKGlassTileView }
            }
        }
        var options = UKHassModalOptions(title: "Lights", fitKey: "test.swipe.sheet.\(family.name).\(tiles)")
        options.width = width
        let modal = UKHassModalController(root: page, options: options)
        modal.present(from: host, animated: false)
        HostedPage.wait(0.5)
        return (modal, window, found)
    }

    /// Every recogniser on the sheet's container and on the sheet itself up to its window, by class, sorted: what the system uses to dismiss it
    /// (the window's own system recognisers belong to the scene, not the sheet).
    private func dismissalMachinery(of modal: UKHassModalController) -> [String] {
        var views: [UIView] = [modal.view]
        if let container = modal.presentationController?.containerView { views.append(container) }
        var names: [String] = []
        var seen = Set<ObjectIdentifier>()
        for root in views {
            var current: UIView? = root
            while let view = current, !(view is UIWindow) {
                for recognizer in view.gestureRecognizers ?? [] where seen.insert(ObjectIdentifier(recognizer)).inserted {
                    names.append("\(type(of: view)).\(type(of: recognizer))")
                }
                current = view.superview
            }
        }
        return names.sorted()
    }

    /// Swipe tiles add nothing to what dismisses the sheet: the same recognisers sit on the sheet and its container with and without them, the
    /// presentation is as interactive as before, and a vertical drag over a tile is refused by the tile at once, so the page scrolls (or the
    /// sheet's own gesture takes it) exactly as over a plain row. This is the iPad form sheet's behaviour on every family.
    func testSwipeTilesLeaveTheSheetsDismissalMachineryAsTheyFoundItOnEveryFamily() throws {
        for family in Self.families {
            let plain = present(tiles: false, family: family)
            let plainMachinery = dismissalMachinery(of: plain.modal)
            let plainStyle = plain.modal.modalPresentationStyle
            plain.window.isHidden = true
            let swiped = present(tiles: true, family: family)
            defer { swiped.window.isHidden = true }
            XCTAssertEqual(swiped.modal.modalPresentationStyle, plainStyle, "the same presentation (\(family.name))")
            XCTAssertEqual(dismissalMachinery(of: swiped.modal), plainMachinery, "the same recognisers on the sheet and its container (\(family.name))")
            XCTAssertFalse(swiped.modal.isModalInPresentation, "a tile never makes the sheet modal in presentation")
            let presentation = try XCTUnwrap(swiped.modal.presentationController)
            XCTAssertTrue(presentation.delegate?.presentationControllerShouldDismiss?(presentation) ?? true, "the sheet allows its dismissal")
            XCTAssertEqual(swiped.tiles.count, 2)
            for tile in swiped.tiles {
                let controller = try XCTUnwrap(tile.swipe)
                for degrees in [60.0, 90] {
                    XCTAssertFalse(controller.gestureRecognizerShouldBegin(stroke(degrees: degrees)), "a drag down over a tile is not the tile's (\(family.name))")
                }
                let own = tile.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer } ?? []
                XCTAssertEqual(own.count, 1, "one pan on the tile, none shared with the sheet")
                XCTAssertFalse(own.contains { $0.cancelsTouchesInView && $0.state != .possible }, "an idle tile holds no touch")
            }
            swiped.modal.dismiss(animated: false)
        }
    }

    /// The page sheet and the form sheet are the two iPad styles (HIG: Sheets, "Prefer page or form sheet styles in an iPadOS app"); a
    /// compact width is always the page sheet. The tile changes none of it.
    func testTheSheetsPresentationStyleDoesNotDependOnItsTiles() throws {
        for family in Self.families {
            let regular = family.window.width >= 600
            let form = present(tiles: true, family: family, width: .form)
            XCTAssertEqual(form.modal.modalPresentationStyle, regular ? .formSheet : .pageSheet, "form width (\(family.name))")
            form.modal.dismiss(animated: false)
            form.window.isHidden = true
            let page = present(tiles: true, family: family, width: .page)
            XCTAssertEqual(page.modal.modalPresentationStyle, .pageSheet, "page width (\(family.name))")
            page.modal.dismiss(animated: false)
            page.window.isHidden = true
        }
    }
}
