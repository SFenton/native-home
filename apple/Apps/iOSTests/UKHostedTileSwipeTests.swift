import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// A pan recognizer that reports what the test says.
final class ScriptedSwipePan: UIPanGestureRecognizer {
    var scriptedState: UIGestureRecognizer.State = .possible
    var point = CGPoint.zero
    var speed = CGPoint(x: 120, y: 0)
    /// How far the finger has travelled since it went down; a stroke that begins sideways by default.
    var travel = CGPoint(x: 30, y: 0)
    override var state: UIGestureRecognizer.State {
        get { scriptedState }
        set {}
    }
    override func location(in view: UIView?) -> CGPoint { point }
    override func translation(in view: UIView?) -> CGPoint { travel }
    override func velocity(in view: UIView?) -> CGPoint { speed }
}

// MARK: - Swipe to adjust, UX and accessibility

/// Hosted UX and accessibility checks for swipe to adjust (`sh.tile-swipe@1`, `.agents/patterns/tile-swipe.md`), the state words
/// (`sh.state-words@1`) and the default tile ink (`sh.tile-ink-default@1`) on a tile.
///
/// Each test runs at the tile widths of the three families: the folded iPhone Duo (170 pt), the iPhone (179 pt) and the iPad (192 pt), the
/// widths the design computes from the grid rule (`tile-swipe.md` section 1).
@MainActor
final class UKHostedTileSwipeTests: XCTestCase {
    private static let widths: [CGFloat] = [170, 179, 192]

    override func tearDown() async throws {
        UKMotion.reduceMotionOverride = nil
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Fixtures

    private func lightTile(width: CGFloat, percent: Int = 40, swipe: UKTileSwipeConfig? = .brightness, unavailable: Bool = false,
                           words: UKLightWords = UKLightWords()) -> (view: UKBrightnessTileView, tile: UKGlassTileView, window: UIWindow) {
        let host = UIViewController()
        let window = HostedPage.show(host)
        let view = UKBrightnessTileView(title: "Lamp", tint: .systemYellow, percent: percent, isUnavailable: unavailable)
        view.swipe = swipe
        view.words = words
        view.frame = CGRect(x: 20, y: 120, width: width, height: 90)
        host.view.addSubview(view)
        view.layoutIfNeeded()
        let tile = HostedPage.descendants(of: view).compactMap { $0 as? UKGlassTileView }.first!
        return (view, tile, window)
    }

    /// Plays `fractions` of the tile's width as one touch: began, changed for the rest, then `end`.
    private func drag(_ controller: UKTileSwipeController, tile: UIView, _ fractions: [Double], end: UIGestureRecognizer.State = .ended,
                      speed: CGPoint = CGPoint(x: 120, y: 0)) {
        let pan = ScriptedSwipePan()
        pan.speed = speed
        let selector = NSSelectorFromString("panned:")
        for (index, fraction) in fractions.enumerated() {
            pan.scriptedState = index == 0 ? .began : .changed
            pan.point = CGPoint(x: tile.bounds.width * fraction, y: 40)
            controller.perform(selector, with: pan)
        }
        pan.scriptedState = end
        controller.perform(selector, with: pan)
    }

    private func element(of tile: UKGlassTileView) -> NSObject? { tile.accessibilityElements?.first as? NSObject }

    private func traits(of tile: UKGlassTileView) -> UIAccessibilityTraits { element(of: tile)?.accessibilityTraits ?? tile.accessibilityTraits }

    // MARK: UX: the drag

    func testASwipeSetsTheLevelUnderTheFingerAndSendsOneCallOnReleaseAtEveryWidth() throws {
        for width in Self.widths {
            let (view, tile, window) = lightTile(width: width)
            defer { window.isHidden = true }
            var levels: [Int] = []
            view.onBrightness = { levels.append($0) }
            let controller = try XCTUnwrap(tile.swipe)
            drag(controller, tile: tile, [0.2, 0.4, 0.6], end: .possible)
            XCTAssertEqual(levels, [], "nothing is sent while the finger is down (width \(width))")
            XCTAssertEqual(controller.dragValue, 60)
            drag(controller, tile: tile, [0.2, 0.6])
            XCTAssertEqual(levels, [60], "one call on release with the snapped value (width \(width))")
        }
    }

    func testTheBandAndTheBubbleFollowTheFingerWithNoConfigureAndNoCall() throws {
        for width in Self.widths {
            let (view, tile, window) = lightTile(width: width)
            defer { window.isHidden = true }
            var calls = 0
            view.onBrightness = { _ in calls += 1 }
            let configures = tile.configureCount
            let controller = try XCTUnwrap(tile.swipe)
            drag(controller, tile: tile, [0.3, 0.5, 0.7], end: .possible)
            XCTAssertEqual(try XCTUnwrap(tile.face.content.level), 0.7, accuracy: 0.001, "the band is where the finger is (width \(width))")
            XCTAssertEqual(tile.face.content.subtitle, "70%", "the state line follows the drag")
            XCTAssertEqual(HostedPage.labels(in: controller.bubble), ["70%"])
            XCTAssertEqual(controller.bubble.alpha, 1)
            XCTAssertEqual(tile.configureCount, configures, "a drag does not rebuild the tile (C8)")
            XCTAssertEqual(calls, 0)
            XCTAssertGreaterThanOrEqual(controller.sampleCount, 3)
            XCTAssertTrue(view.hasActiveInteraction, "a republish does not replace a dragging tile")
        }
    }

    func testAReleaseAtTheShownValueSendsNothing() throws {
        let (view, tile, window) = lightTile(width: 179, percent: 60)
        defer { window.isHidden = true }
        var levels: [Int] = []
        view.onBrightness = { levels.append($0) }
        drag(try XCTUnwrap(tile.swipe), tile: tile, [0.3, 0.6])
        XCTAssertEqual(levels, [])
    }

    func testACancelledDragSendsNothingAndRestoresTheBand() throws {
        for width in Self.widths {
            let (view, tile, window) = lightTile(width: width)
            defer { window.isHidden = true }
            var levels: [Int] = []
            view.onBrightness = { levels.append($0) }
            let controller = try XCTUnwrap(tile.swipe)
            drag(controller, tile: tile, [0.3, 0.9], end: .cancelled)
            XCTAssertEqual(levels, [])
            XCTAssertNil(controller.dragValue)
            XCTAssertEqual(try XCTUnwrap(tile.face.content.level), 0.4, accuracy: 0.001, "the band returns to the live value (width \(width))")
            XCTAssertEqual(tile.face.content.subtitle, "40%")
        }
    }

    func testAVerticalStartNeverBegins() throws {
        let (_, tile, window) = lightTile(width: 179)
        defer { window.isHidden = true }
        let controller = try XCTUnwrap(tile.swipe)
        let pan = ScriptedSwipePan()
        pan.speed = CGPoint(x: 10, y: 120)
        XCTAssertFalse(controller.gestureRecognizerShouldBegin(pan), "a vertical start is the page's scroll (C1)")
        pan.speed = CGPoint(x: 120, y: 10)
        XCTAssertTrue(controller.gestureRecognizerShouldBegin(pan))
    }

    func testAnEdgePanIsNotBlockedByATileButTheTilesPanWaitsForIt() throws {
        let (_, tile, window) = lightTile(width: 179)
        defer { window.isHidden = true }
        let controller = try XCTUnwrap(tile.swipe)
        let pan = try XCTUnwrap(tile.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer }.first)
        XCTAssertTrue(controller.gestureRecognizer(pan, shouldRequireFailureOf: UIScreenEdgePanGestureRecognizer()), "the edge swipe wins (C2)")
        XCTAssertFalse(controller.gestureRecognizer(pan, shouldRequireFailureOf: UITapGestureRecognizer()))
    }

    func testATileInAHorizontalScrollerTakesNoPanButKeepsItsValue() throws {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let scroller = UIScrollView(frame: CGRect(x: 0, y: 100, width: 393, height: 120))
        scroller.contentSize = CGSize(width: 800, height: 120)
        host.view.addSubview(scroller)
        let view = UKBrightnessTileView(title: "Lamp", tint: .systemYellow, percent: 40)
        view.frame = CGRect(x: 10, y: 10, width: 179, height: 90)
        scroller.addSubview(view)
        view.layoutIfNeeded()
        let tile = try XCTUnwrap(HostedPage.descendants(of: view).compactMap { $0 as? UKGlassTileView }.first)
        XCTAssertFalse(try XCTUnwrap(tile.swipe).gestureRecognizerShouldBegin(ScriptedSwipePan()), "the scroller above wins (C3)")
        XCTAssertTrue(traits(of: tile).contains(.adjustable), "the value is still settable by VoiceOver there")
    }

    func testOnlyOneTileDragsAtATime() throws {
        let (_, first, window) = lightTile(width: 179)
        defer { window.isHidden = true }
        let (_, second, window2) = lightTile(width: 179)
        defer { window2.isHidden = true }
        drag(try XCTUnwrap(first.swipe), tile: first, [0.2, 0.5], end: .possible)
        XCTAssertFalse(try XCTUnwrap(second.swipe).gestureRecognizerShouldBegin(ScriptedSwipePan()), "a second tile does not begin during a drag (C6)")
        try XCTUnwrap(first.swipe).cancel()
        XCTAssertTrue(try XCTUnwrap(second.swipe).gestureRecognizerShouldBegin(ScriptedSwipePan()))
    }

    func testRightToLeftMirrorsTheMapAndTheBubbleKeepsItsDigits() throws {
        let (view, tile, window) = lightTile(width: 179)
        defer { window.isHidden = true }
        tile.semanticContentAttribute = .forceRightToLeft
        var levels: [Int] = []
        view.onBrightness = { levels.append($0) }
        drag(try XCTUnwrap(tile.swipe), tile: tile, [0.1, 0.25])
        XCTAssertEqual(levels, [75], "the minimum stays on the leading edge, so the right is low in a right to left layout")
    }

    func testTheLiftScalesTheTileUnlessReduceMotionIsOn() throws {
        let (_, tile, window) = lightTile(width: 179)
        defer { window.isHidden = true }
        let controller = try XCTUnwrap(tile.swipe)
        drag(controller, tile: tile, [0.3, 0.5], end: .possible)
        XCTAssertEqual(tile.transform.a, 1.03, accuracy: 0.001)
        controller.cancel()
        UKMotion.reduceMotionOverride = true
        drag(controller, tile: tile, [0.3, 0.5], end: .possible)
        XCTAssertEqual(tile.transform, .identity, "Reduce Motion: no scale")
        XCTAssertEqual(try XCTUnwrap(tile.face.content.level), 0.5, accuracy: 0.001, "the band still tracks")
        XCTAssertEqual(controller.bubble.alpha, 1)
        controller.cancel()
    }

    func testTheBubbleStaysInsideTheTileAtTheMinimumAndTheMaximum() throws {
        for width in Self.widths {
            let (_, tile, window) = lightTile(width: width)
            defer { window.isHidden = true }
            let controller = try XCTUnwrap(tile.swipe)
            drag(controller, tile: tile, [0.5, 0], end: .possible)
            XCTAssertEqual(controller.bubble.frame.minX, 0, accuracy: 0.5, "flush with the leading edge at the minimum (width \(width))")
            XCTAssertEqual(controller.bubble.frame.width, 60, accuracy: 0.5)
            XCTAssertEqual(controller.bubble.frame.height, 32, accuracy: 0.5)
            XCTAssertEqual(HostedPage.labels(in: controller.bubble), ["Off"])
            drag(controller, tile: tile, [0.5, 1.2], end: .possible)
            XCTAssertEqual(controller.bubble.frame.maxX, tile.bounds.width, accuracy: 0.5, "flush with the trailing edge at the maximum")
            XCTAssertEqual(controller.bubble.frame.maxY, -8, accuracy: 0.5, "8 pt clear above the tile")
            controller.cancel()
        }
    }

    func testTheBubbleComesDownNearTheTopOfTheScroller() throws {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let scroller = UIScrollView(frame: CGRect(x: 0, y: 100, width: 393, height: 400))
        scroller.contentSize = CGSize(width: 393, height: 1200)
        host.view.addSubview(scroller)
        let view = UKBrightnessTileView(title: "Lamp", tint: .systemYellow, percent: 40)
        view.frame = CGRect(x: 10, y: 10, width: 179, height: 90)
        scroller.addSubview(view)
        view.layoutIfNeeded()
        let tile = try XCTUnwrap(HostedPage.descendants(of: view).compactMap { $0 as? UKGlassTileView }.first)
        let controller = try XCTUnwrap(tile.swipe)
        drag(controller, tile: tile, [0.3, 0.5], end: .possible)
        XCTAssertEqual(controller.bubble.frame.minY + view.frame.minY, 4, accuracy: 2, "4 pt inside the top of the scroller, never below the tile")
        controller.cancel()
    }

    // MARK: Off by default

    func testATileWithNoSwipeHasNoPanNoTraitAndNoHint() throws {
        for width in Self.widths {
            let (_, tile, window) = lightTile(width: width, swipe: nil)
            defer { window.isHidden = true }
            XCTAssertNil(tile.swipe)
            XCTAssertTrue(tile.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer }.isEmpty ?? true, "no recogniser (width \(width))")
            XCTAssertFalse(traits(of: tile).contains(.adjustable))
            XCTAssertEqual(element(of: tile)?.accessibilityHint, "Double-tap to turn off.")
            XCTAssertNil(element(of: tile)?.accessibilityCustomActions)
            XCTAssertNil(tile.onAdjust)
        }
    }

    // MARK: Accessibility

    func testASwipedTileIsAdjustableWithItsValueHintAndNamedActions() throws {
        for width in Self.widths {
            let (_, tile, window) = lightTile(width: width, percent: 45)
            defer { window.isHidden = true }
            let body = try XCTUnwrap(element(of: tile))
            XCTAssertTrue(body.accessibilityTraits.contains(.adjustable), "width \(width)")
            XCTAssertEqual(body.accessibilityValue, "45%")
            XCTAssertEqual(body.accessibilityHint, "Double-tap to turn off. Swipe up or down to adjust brightness.")
            XCTAssertEqual(body.accessibilityCustomActions?.map(\.name), ["Increase Brightness", "Decrease Brightness"])
        }
    }

    func testIncrementAndDecrementEachSendOneCallWithTheSteppedValueAndStopAtTheEnds() throws {
        let (view, tile, window) = lightTile(width: 179, percent: 95)
        defer { window.isHidden = true }
        var levels: [Int] = []
        view.onBrightness = { levels.append($0) }
        let body = try XCTUnwrap(element(of: tile))
        body.accessibilityIncrement()
        XCTAssertEqual(levels, [100])
        body.accessibilityIncrement()
        XCTAssertEqual(levels, [100], "the maximum is the end: no second call")
        body.accessibilityDecrement()
        XCTAssertEqual(levels, [100, 90])
        let actions = try XCTUnwrap(body.accessibilityCustomActions)
        _ = actions[1].actionHandler?(actions[1])
        XCTAssertEqual(levels, [100, 90, 80], "the named action does what decrement does")
        let (low, lowTile, window2) = lightTile(width: 179, percent: 4)
        defer { window2.isHidden = true }
        var lowLevels: [Int] = []
        low.onBrightness = { lowLevels.append($0) }
        try XCTUnwrap(element(of: lowTile)).accessibilityDecrement()
        XCTAssertEqual(lowLevels, [0])
        try XCTUnwrap(element(of: lowTile)).accessibilityDecrement()
        XCTAssertEqual(lowLevels, [0], "the minimum is the end")
    }

    func testAnUnavailableTileHasNoTraitNoHintAndNoActions() throws {
        let (_, tile, window) = lightTile(width: 179, unavailable: true)
        defer { window.isHidden = true }
        XCTAssertFalse(traits(of: tile).contains(.adjustable))
        XCTAssertNil(element(of: tile)?.accessibilityCustomActions)
        XCTAssertFalse((element(of: tile)?.accessibilityHint ?? "").contains("Swipe"))
        XCTAssertFalse(try XCTUnwrap(tile.swipe).gestureRecognizerShouldBegin(ScriptedSwipePan()), "an unavailable tile takes no drag")
    }

    func testTheBubbleIsNotAnAccessibilityElement() throws {
        let (_, tile, window) = lightTile(width: 179)
        defer { window.isHidden = true }
        let controller = try XCTUnwrap(tile.swipe)
        drag(controller, tile: tile, [0.3, 0.5], end: .possible)
        XCTAssertFalse(controller.bubble.isAccessibilityElement)
        XCTAssertTrue(controller.bubble.accessibilityElementsHidden)
        controller.cancel()
    }

    func testTheBubbleIsLargerAtAccessibilityTextSizes() throws {
        let (_, tile, window) = lightTile(width: 192)
        defer { window.isHidden = true }
        let controller = try XCTUnwrap(tile.swipe)
        tile.overrideUserInterfaceStyle = .dark
        let large = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        controller.bubble.show("100%", metrics: TileSwipeBubble.metrics(isAccessibilitySize: large.preferredContentSizeCategory.isAccessibilityCategory), traits: large)
        XCTAssertEqual(controller.bubble.size(maxWidth: 192).height, 44)
        XCTAssertGreaterThanOrEqual(controller.bubble.size(maxWidth: 192).width, 84)
    }

    // MARK: Words

    func testTheStateLineAndTheSpokenValueSayTheAuthoredWords() throws {
        for width in Self.widths {
            let words = UKLightWords(on: "Lit", off: "Dark", unavailable: "No Answer", level: "{value} percent")
            let (view, tile, window) = lightTile(width: width, percent: 45, words: words)
            defer { window.isHidden = true }
            XCTAssertEqual(tile.face.content.subtitle, "45 percent", "width \(width)")
            XCTAssertEqual(element(of: tile)?.accessibilityValue, "45 percent")
            view.update(fillTint: nil, percent: 0, isUnavailable: false)
            XCTAssertEqual(tile.face.content.subtitle, "Dark")
            XCTAssertEqual(element(of: tile)?.accessibilityValue, "Dark")
            view.update(fillTint: nil, percent: 0, isUnavailable: true)
            XCTAssertEqual(tile.face.content.subtitle, "No Answer")
        }
    }

    func testWithNoWordsTheTileSaysProductionsText() throws {
        let (view, tile, window) = lightTile(width: 179, percent: 45)
        defer { window.isHidden = true }
        XCTAssertEqual(tile.face.content.subtitle, "45%")
        view.update(fillTint: nil, percent: 0, isUnavailable: false)
        XCTAssertEqual(tile.face.content.subtitle, "Off")
        view.update(fillTint: nil, percent: 0, isUnavailable: true)
        XCTAssertEqual(tile.face.content.subtitle, "Unavailable")
    }

    // MARK: What a release draws (`.agents/patterns/tile-swipe.md`)

    /// The controller's order on a release, with a fake host: a release that sends the value commits first, drops the held configure unrun and
    /// keeps the frame; a release that sends nothing, and a cancel, clear the frame and run the held configure once.
    func testTheControllerCommitsBeforeAnyRedrawAndDropsTheHeldConfigureOnlyWhenItSendsTheValue() throws {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let view = UIView(frame: CGRect(x: 20, y: 120, width: 170, height: 90))
        host.view.addSubview(view)
        func rig(shown: Double, holds: Bool) -> (UKTileSwipeController, () -> [String], () -> Int) {
            var events: [String] = []
            var held = 0
            let controller = UKTileSwipeController(host: view, config: .brightness)
            controller.shownValue = { shown }
            controller.onFrame = { events.append($0 == nil ? "frame cleared" : "frame") }
            controller.onCommit = { _ in events.append("commit") }
            controller.holdsCommittedFrame = { holds }
            controller.onFrameHold = { events.append("frame kept") }
            drag(controller, tile: view, [0.2, 0.6], end: .possible)
            XCTAssertTrue(controller.hold { held += 1 })
            events.removeAll()
            return (controller, { events }, { held })
        }
        let (kept, keptEvents, keptHeld) = rig(shown: 40, holds: true)
        drag(kept, tile: view, [0.6], end: .ended)
        XCTAssertEqual(keptEvents(), ["frame", "commit", "frame kept"], "the call first, the frame kept")
        XCTAssertEqual(keptHeld(), 0, "the held configure is dropped, never run")
        XCTAssertFalse(kept.isDragging)
        kept.detach()

        let (bare, bareEvents, bareHeld) = rig(shown: 40, holds: false)
        drag(bare, tile: view, [0.6], end: .ended)
        XCTAssertEqual(bareEvents(), ["frame", "commit", "frame cleared"], "no value behind the call: the frame goes back in the same turn")
        XCTAssertEqual(bareHeld(), 0)
        bare.detach()

        let (same, sameEvents, sameHeld) = rig(shown: 60, holds: true)
        drag(same, tile: view, [0.6], end: .ended)
        XCTAssertEqual(sameEvents(), ["frame", "frame cleared"], "a release at the shown value sends nothing")
        XCTAssertEqual(sameHeld(), 1, "and the held configure runs once")
        same.detach()

        let (cancelled, cancelEvents, cancelHeld) = rig(shown: 40, holds: true)
        drag(cancelled, tile: view, [0.6], end: .cancelled)
        XCTAssertEqual(cancelEvents(), ["frame", "frame cleared"])
        XCTAssertEqual(cancelHeld(), 1)
        cancelled.detach()
    }

    /// The light group tile shares the controller: a live change held under the finger never draws between the drag and the commit.
    func testALightsCommittedBandNeverLeavesTheCommittedValueAfterAHeldLiveChange() throws {
        for width in Self.widths {
            let (view, tile, window) = lightTile(width: width, percent: 40)
            defer { window.isHidden = true }
            tile.tracesBand = true
            var levels: [Int] = []
            view.onBrightness = { levels.append($0) }
            let controller = try XCTUnwrap(tile.swipe)
            drag(controller, tile: tile, [0.2, 0.6], end: .possible)
            view.update(fillTint: nil, percent: 20, isUnavailable: false)
            let traced = tile.bandTrace.count
            drag(controller, tile: tile, [0.6])
            HostedPage.wait(0.5)
            XCTAssertEqual(levels, [60], "width \(width)")
            var collapsed: [Double] = []
            for level in tile.bandTrace.dropFirst(traced) {
                let value = ((level ?? -1) * 1000).rounded() / 1000
                if collapsed.last != value { collapsed.append(value) }
            }
            XCTAssertEqual(collapsed, [0.6], "the band is 60 from the lift on, never the held 20 or the old 40")
        }
    }

    // MARK: Ink

    private func inkTile(_ ink: TileInkDefault, surface: TileSurface, style: UIUserInterfaceStyle, family: ColorFamily? = .neutral,
                         unavailable: Bool = false, kind: GlassTileKind = .toggle, warning: Bool = false) -> (UKGlassTileView, UIWindow) {
        var environment = UKTileEnvironment()
        environment.surface = surface
        environment.inkDefault = ink
        var model = UKGlassTileModel(title: "Fan", subtitle: "Off", symbol: "fan", family: family, isActive: false, isUnavailable: unavailable, kind: kind)
        model.isWarning = warning
        let tile = UKGlassTileView(model: model, environment: environment)
        let host = UIViewController()
        host.view.addSubview(tile)
        let window = HostedPage.show(host)
        window.overrideUserInterfaceStyle = style
        tile.frame = CGRect(x: 10, y: 100, width: 179, height: tile.gridHeight(forWidth: 179))
        HostedPage.wait(0.1)
        tile.layoutIfNeeded()
        return (tile, window)
    }

    private func packed(_ color: UIColor, in view: UIView) -> UInt32 {
        let c = color.resolvedColor(with: view.traitCollection)
        var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UInt32((r * 255).rounded()) << 16 | UInt32((g * 255).rounded()) << 8 | UInt32((b * 255).rounded())
    }

    func testAnIdleIconAndItsStateLineDrawThePrimaryInkOnADarkAndALightSheet() throws {
        let (dark, w1) = inkTile(.primary, surface: .sheet, style: .dark)
        defer { w1.isHidden = true }
        XCTAssertEqual(packed(dark.face.drawnGlyphColor, in: dark), 0xFFFFFF, "white on a dark sheet")
        XCTAssertEqual(packed(dark.face.drawnStateLineColor, in: dark), 0xFFFFFF)
        let (light, w2) = inkTile(.primary, surface: .sheet, style: .light)
        defer { w2.isHidden = true }
        XCTAssertEqual(packed(light.face.drawnGlyphColor, in: light), 0x000000, "black on a light sheet")
        XCTAssertEqual(packed(light.face.drawnStateLineColor, in: light), 0x000000)
    }

    func testADocumentThatDoesNotDeclareTheInkDrawsTodaysGrey() throws {
        let (dark, w1) = inkTile(.muted, surface: .sheet, style: .dark)
        defer { w1.isHidden = true }
        XCTAssertNotEqual(packed(dark.face.drawnGlyphColor, in: dark), 0xFFFFFF, "the muted grey, not the primary ink")
        XCTAssertNotEqual(packed(dark.face.drawnStateLineColor, in: dark), 0xFFFFFF)
    }

    func testAnIdleIconWithAFamilyKeepsItsTintAndAnUnavailableTileStaysGrey() throws {
        let (family, w1) = inkTile(.primary, surface: .sheet, style: .dark, family: .climate)
        defer { w1.isHidden = true }
        let (muted, w2) = inkTile(.muted, surface: .sheet, style: .dark, family: .climate)
        defer { w2.isHidden = true }
        XCTAssertEqual(packed(family.face.drawnGlyphColor, in: family), packed(muted.face.drawnGlyphColor, in: muted))
        let (unavailable, w3) = inkTile(.primary, surface: .sheet, style: .dark, unavailable: true)
        defer { w3.isHidden = true }
        XCTAssertNotEqual(packed(unavailable.face.drawnGlyphColor, in: unavailable), 0xFFFFFF, "the grey, not the primary ink")
        XCTAssertEqual(unavailable.face.drawnGlyphAlpha, 0.5, accuracy: 0.001, "unavailable draws the grey at 50%")
    }

    func testAnUnavailableStateTileDrawsGreyAndGroupsAsUnavailableLikeAnyOtherTile() throws {
        for style in [UIUserInterfaceStyle.dark, .light] {
            let (state, w1) = inkTile(.primary, surface: style == .dark ? .page : .sheet, style: style, unavailable: true, kind: .state)
            defer { w1.isHidden = true }
            let (button, w2) = inkTile(.primary, surface: style == .dark ? .page : .sheet, style: style, unavailable: true, kind: .toggle)
            defer { w2.isHidden = true }
            XCTAssertTrue(state.model.isInert, "a state tile is read-only")
            XCTAssertNotEqual(packed(state.face.drawnGlyphColor, in: state), style == .dark ? 0xFFFFFF : 0x000000, "the grey, not the primary ink (\(style.rawValue))")
            XCTAssertEqual(packed(state.face.drawnGlyphColor, in: state), packed(button.face.drawnGlyphColor, in: button), "the same grey as a button tile")
            XCTAssertEqual(packed(state.face.drawnStateLineColor, in: state), packed(button.face.drawnStateLineColor, in: button))
            XCTAssertEqual(state.face.drawnGlyphAlpha, 0.5, accuracy: 0.001, "at 50%")
            XCTAssertEqual(state.gridFace, .unavailable, "it groups with the unavailable tiles")
            XCTAssertTrue(state.isEnabled, "the control itself is still never dimmed as disabled")
        }
    }

    func testAnAvailableStateTileKeepsThePrimaryInkAndItsFace() throws {
        for kind in [GlassTileKind.state, .toggle] {
            let (tile, w) = inkTile(.primary, surface: .sheet, style: .dark, kind: kind)
            defer { w.isHidden = true }
            XCTAssertEqual(packed(tile.face.drawnGlyphColor, in: tile), 0xFFFFFF, "\(kind)")
            XCTAssertEqual(tile.gridFace, .idle)
        }
    }

    func testAWarningStateLineIsPrimaryOnADarkFaceAndItsIconKeepsTheAmber() throws {
        for kind in [GlassTileKind.state, .toggle] {
            let (tile, w) = inkTile(.primary, surface: .page, style: .dark, kind: kind, warning: true)
            defer { w.isHidden = true }
            XCTAssertEqual(packed(tile.face.drawnStateLineColor, in: tile), 0xFFFFFF, "state line primary (\(kind))")
            XCTAssertNotEqual(packed(tile.face.drawnGlyphColor, in: tile), 0xFFFFFF, "the icon still carries the warning")
            let (muted, w2) = inkTile(.muted, surface: .page, style: .dark, kind: kind, warning: true)
            defer { w2.isHidden = true }
            XCTAssertNotEqual(packed(muted.face.drawnStateLineColor, in: muted), 0xFFFFFF, "a document without the id keeps today's amber")
        }
    }

    // MARK: Minimum width (`n-lgt-minwidth`)

    /// The Studio's `lightTileWidths(title, false).minimum` (`src/preview2/nodes/tile-minimum.ts`): two 12 pt paddings, the 42 pt glyph column, the
    /// title (9.2 pt a character, 96 pt at least), and the 52 pt strip of the one power disc.
    private func studioMinimum(_ title: String) -> CGFloat { 24 + 42 + max((CGFloat(title.count) * 9.2).rounded(.up), 96) + 52 }

    private func groupTile(_ title: String) -> UKLightGroupTileView {
        let tile = UKLightGroupTileView(title: title, entityId: "light.demo_group", identifier: "tile", environment: UKTileEnvironment(), send: { _ in })
        tile.update(state: EntityState(entityId: "light.demo_group", state: "off", attributes: ["supported_color_modes": .array([.string("brightness")])]))
        return tile
    }

    /// The native minimum is two 12 pt paddings, the title measured at its 17 pt semibold (96 pt at least) and the 52 pt strip of the power disc:
    /// the disc carries the glyph, so there is no 42 pt glyph column. The Studio's `lightTileWidths` adds that column and estimates the title at
    /// 9.2 pt a character, so it asks for more than the app needs (a Studio finding, not a native one): it never asks for less.
    func testALightGroupTileReportsTheMinimumWidthItDrawsBy() throws {
        let pinned: [(title: String, native: CGFloat)] = [("Lamp", 172), ("Kitchen Lights", 179), ("Primary Bedroom Lights", 249),
                                                          ("Primary Bedroom Closet Ceiling Lights", 352)]
        for (title, native) in pinned {
            let tile = groupTile(title)
            XCTAssertEqual(tile.gridMinimumWidth, native, accuracy: 1, "\(title)")
            XCTAssertGreaterThanOrEqual(studioMinimum(title), tile.gridMinimumWidth, "the Studio never asks for less than the app (\(title))")
        }
        XCTAssertGreaterThan(groupTile("Primary Bedroom Closet Ceiling Lights").gridMinimumWidth, groupTile("Lamp").gridMinimumWidth, "a longer name asks for more")
        XCTAssertEqual(groupTile("Lamp").gridMinimumWidth, 24 + 96 + 52, accuracy: 0.5, "a short name is held at the 96 pt text floor")
    }

    func testTwoLongNamedLightGroupTilesDoNotWrapOnAnyFamilyWidth() throws {
        for width in [364.0, 393.0, 834.0] {
            let host = UIViewController()
            let window = HostedPage.show(host)
            defer { window.isHidden = true }
            let grid = UKDynamicGridView()
            host.view.addSubview(grid)
            let names = ["Primary Bedroom Closet Lights", "Guest Bathroom Mirror Lights"]
            let tiles = names.map(groupTile)
            grid.regroupItems(tiles.map { UKGridItem($0) })
            grid.frame = CGRect(x: 0, y: 100, width: width, height: grid.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
            grid.layoutIfNeeded()
            let single = groupTile("Lamp").gridHeight(forWidth: 300)
            for tile in tiles {
                XCTAssertGreaterThanOrEqual(tile.frame.width + 0.5, tile.gridMinimumWidth, "the grid gave the tile the width it asked for (\(width))")
                XCTAssertEqual(tile.gridHeight(forWidth: tile.frame.width), single, accuracy: 1, "the name stays on one line (\(width))")
            }
        }
    }
}
