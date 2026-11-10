import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// The tile's own accessibility element, its accessory controls, its mirrored layout, a stale confirmation and the text-measure cache.
///
/// Companion to ``UKHostedTileTests``: those cover what a tile says; these cover how the pieces around the tile (the body element, an
/// accessory's controls, a disc under a touch) behave when a tile tells its containers its size changed.
@MainActor
final class UKHostedTileElementsTests: DemoHouseTestCase {
    private func place(_ tile: UKGlassTileView, width: CGFloat = 175, in host: UIViewController) {
        host.view.addSubview(tile)
        tile.frame = CGRect(x: 10, y: 80, width: width, height: tile.gridHeight(forWidth: width))
        tile.layoutIfNeeded()
    }

    private func twoDiscs(confirm: Bool = false) -> [TileActionItem] {
        [TileActionItem(id: "lock", verb: "Unlock", symbol: "lock.fill", isOn: true, feedback: .tracked,
                        confirmation: confirm ? TileActionConfirmation(title: "Unlock the door?", confirmVerb: "Unlock") : nil),
         TileActionItem(id: "alarm", verb: "Arm", symbol: "shield.fill", isOn: false)]
    }

    func testBodyElementForwardsAdjustAndActivate() throws {
        var steps: [Bool] = []
        var taps = 0
        let tile = UKGlassTileView(model: UKGlassTileModel(title: "Dim", subtitle: "40%", symbol: "sun.max", isActive: true)) { taps += 1 }
        tile.onAdjust = { steps.append($0) }
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        place(tile, in: host)
        tile.configure(UKGlassTileModel(title: "Dim", subtitle: "40%", symbol: "sun.max", isActive: true), animated: false)
        let body = try XCTUnwrap(tile.accessibilityElements?.first as? UKTileAccessibilityElement)
        XCTAssertTrue(body.accessibilityTraits.contains(.adjustable), "a tile that adjusts says so on its body")
        body.accessibilityIncrement()
        body.accessibilityDecrement()
        XCTAssertEqual(steps, [true, false])
        XCTAssertTrue(body.accessibilityActivate())
        XCTAssertEqual(taps, 1)
        tile.isEnabled = false
        XCTAssertFalse(body.accessibilityActivate(), "a disabled tile has nothing to activate")
        XCTAssertEqual(taps, 1)
    }

    func testAnAccessoryOfControlsExposesEachControlAndTheTileIgnoresSetters() throws {
        let tile = UKGlassTileView(model: UKGlassTileModel(title: "Speaker", subtitle: "Playing", symbol: "hifispeaker", isActive: true))
        let rail = UIView(frame: CGRect(x: 0, y: 0, width: 80, height: 32))
        let controls = (0..<2).map { index -> UIButton in
            let button = UIButton(frame: CGRect(x: CGFloat(index) * 40, y: 0, width: 40, height: 32))
            button.isAccessibilityElement = true
            button.accessibilityLabel = "Control \(index)"
            rail.addSubview(button)
            return button
        }
        tile.setAccessory(rail)
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        place(tile, width: 300, in: host)
        let elements = tile.accessibilityElements ?? []
        for control in controls { XCTAssertTrue(elements.contains { ($0 as AnyObject) === control }, "\(control.accessibilityLabel ?? "") is its own stop") }
        XCTAssertFalse(elements.contains { ($0 as AnyObject) === rail }, "the rail is not a stop when its controls are")

        rail.isAccessibilityElement = true
        XCTAssertTrue((tile.accessibilityElements ?? []).contains { ($0 as AnyObject) === rail }, "a rail that is an element is one stop")

        tile.isAccessibilityElement = true
        tile.accessibilityElements = []
        XCTAssertFalse(tile.isAccessibilityElement, "a tile with controls is a container whatever is assigned")
        XCTAssertFalse((tile.accessibilityElements ?? []).isEmpty)
    }

    func testAnAccessoryTileMirrorsAndKeepsItsBodyOffTheControlsInRightToLeft() throws {
        let tile = UKGlassTileView(model: UKGlassTileModel(title: "Speaker", subtitle: "Playing", symbol: "hifispeaker", isActive: true))
        let rail = UIView(frame: CGRect(x: 0, y: 0, width: 60, height: 32))
        tile.setAccessory(rail)
        tile.semanticContentAttribute = .forceRightToLeft
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        place(tile, width: 300, in: host)
        XCTAssertEqual(tile.effectiveUserInterfaceLayoutDirection, .rightToLeft)
        XCTAssertLessThan(rail.frame.midX, tile.bounds.midX, "the trailing accessory sits on the left when mirrored")
        let body = try XCTUnwrap(tile.accessibilityElements?.first as? UIAccessibilityElement)
        XCTAssertEqual(body.accessibilityFrameInContainerSpace.minX, rail.frame.maxX, accuracy: 1, "the body starts where the controls end")
        XCTAssertEqual(body.accessibilityFrameInContainerSpace.maxX, tile.bounds.width, accuracy: 1)
    }

    func testATouchOnADiscReachesTheDiscNotTheBody() throws {
        let model = UKGlassTileModel(title: "Front door", subtitle: "Locked", symbol: "lock.fill", isActive: true, behavior: .perform("lock"),
                                     actions: twoDiscs(), identifier: "tile.door")
        let tile = UKGlassTileView(model: model)
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        place(tile, width: 300, in: host)
        let disc = try XCTUnwrap(HostedPage.descendants(of: tile).compactMap { $0 as? UKTileActionDisc }.first)
        let point = tile.convert(CGPoint(x: disc.bounds.midX, y: disc.bounds.midY), from: disc)
        XCTAssertTrue(tile.hitTest(point, with: nil) === disc, "a tap on a disc never also taps the body")
    }

    func testAConfirmationWhoseActionChangedBeforeTheAnswerIsDropped() {
        var performed: [String] = []
        let model = UKGlassTileModel(title: "Front door", subtitle: "Locked", symbol: "lock.fill", isActive: true, behavior: .perform("lock"),
                                     actions: twoDiscs(confirm: true), identifier: "tile.door")
        let tile = UKGlassTileView(model: model)
        tile.onPerform = { performed.append($0) }
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        place(tile, width: 300, in: host)
        tile.sendActions(for: .touchUpInside)
        hostedSettle(0.4)
        let alert = host.presentedViewController as? UIAlertController
        XCTAssertEqual(alert?.title, "Unlock the door?")
        // The door was unlocked elsewhere while the question was open: the action the person was asked about is gone.
        var moved = model
        moved.actions = [TileActionItem(id: "lock", verb: "Lock", symbol: "lock.fill", isOn: false)] + Array(model.actions.dropFirst())
        tile.configure(moved, animated: false)
        if let confirm = alert?.actions.last, let handler = confirm.value(forKey: "handler") {
            typealias Handler = @convention(block) (UIAlertAction) -> Void
            unsafeBitCast(handler as AnyObject, to: Handler.self)(confirm)
        }
        XCTAssertTrue(performed.isEmpty, "a changed action is dropped, never run in place of the old one")
    }

    override func tearDown() async throws {
        UKMotion.reduceMotionOverride = nil
        try await super.tearDown()
    }

    func testReduceMotionCrossFadesAChangedActionSetInsteadOfAnimatingItsHeight() {
        UKMotion.reduceMotionOverride = true
        XCTAssertTrue(UKDesign.reduceMotion, "one source of truth for Reduce Motion")
        let model = UKGlassTileModel(title: "Front door", subtitle: "Locked", symbol: "lock.fill", isActive: true, behavior: .perform("lock"),
                                     actions: twoDiscs(), identifier: "tile.door")
        let tile = UKGlassTileView(model: model)
        tile.spansFullRow = true
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        place(tile, width: 300, in: host)
        let before = tile.subviews.count
        var fewer = model
        fewer.actions = Array(model.actions.prefix(1))
        tile.configure(fewer, animated: true)
        XCTAssertGreaterThan(tile.subviews.count, before, "the old discs fade out in a snapshot holder while the new layout is already in place")
        let holder = tile.subviews.last
        XCTAssertFalse(holder?.isUserInteractionEnabled ?? true, "the fading snapshots take no touches")
        XCTAssertFalse(holder?.isAccessibilityElement ?? true)
        hostedSettle(0.6)
        XCTAssertEqual(tile.subviews.count, before, "the holder goes once the cross-fade ends")
    }

    func testAToggleTileSpeaksItsStateWithOrWithoutADisc() {
        let plain = UKGlassTileModel(title: "Lamp", symbol: "lamp", isActive: true)
        XCTAssertEqual(plain.accessibilityValue(valuesPending: false), "On")
        let items = UKGlassTileModel(title: "Door", symbol: "lock", isActive: false, behavior: .perform("lock"), actions: twoDiscs())
        XCTAssertEqual(items.accessibilityValue(valuesPending: false), "Off", "with no state line a disc tile reads its on or off")
        let worded = UKGlassTileModel(title: "Door", subtitle: "Locked", symbol: "lock", isActive: false, behavior: .perform("lock"), actions: twoDiscs())
        XCTAssertEqual(worded.accessibilityValue(valuesPending: false), "Locked")
    }

    func testTheTextMeasureIsZeroForNothingAndSurvivesAFullCache() {
        let traits = UITraitCollection(preferredContentSizeCategory: .large)
        XCTAssertEqual(UKTileTextMeasure.width("", state: true, traits: traits), 0)
        let first = UKTileTextMeasure.width("Kitchen", state: false, traits: traits)
        for index in 0..<4_100 { _ = UKTileTextMeasure.width("Tile \(index)", state: true, traits: traits) }
        XCTAssertEqual(UKTileTextMeasure.width("Kitchen", state: false, traits: traits), first, "a cleared cache measures the same width again")
    }
}
