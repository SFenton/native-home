import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// The action discs, their strip and the volume slider under a tile.
@MainActor
final class UKHostedTileActionTests: XCTestCase {
    private func disc(_ item: TileActionItem, face: TileActionFace = .filled) -> UKTileActionDisc {
        UKTileActionDisc(item: item, face: face, family: .lights, surface: .page, title: "Lamp", identifier: "disc")
    }

    func testDiscSpeaksItsVerbAndStateAndDisablesWhileBusy() {
        let ready = disc(TileActionItem(id: "p", verb: "Turn Off", symbol: "power", isOn: true))
        XCTAssertEqual(ready.accessibilityLabel, "Turn Off Lamp")
        XCTAssertEqual(ready.accessibilityValue, "On")
        XCTAssertTrue(ready.accessibilityTraits.contains(.toggleButton))
        XCTAssertTrue(ready.isEnabled)
        XCTAssertEqual(ready.intrinsicContentSize.width, UKTileActionDisc.diameter(traits: ready.traitCollection))
        XCTAssertEqual(ready.sizeThatFits(.zero), ready.intrinsicContentSize)
        ready.spokenLabel = "Switch the lamp"
        XCTAssertEqual(ready.accessibilityLabel, "Switch the lamp")
        ready.spokenLabel = nil
        ready.isHighlighted = true
        ready.isHighlighted = false

        for phase in [TileActionItem.Phase.inFlight, .unavailable] {
            let item = TileActionItem(id: "p", verb: "Lock", symbol: "lock", isOn: false, phase: phase)
            ready.configure(item: item, face: .dark, family: .lights, surface: .page, title: "Lamp", identifier: "disc", animated: false)
            XCTAssertFalse(ready.isEnabled, "\(phase) cannot be tapped")
            XCTAssertTrue(ready.accessibilityTraits.contains(.notEnabled))
        }
        let labelled = disc(TileActionItem(id: "x", verb: "Cancel", symbol: "xmark", label: "Cancel Hot Flash Mode"))
        XCTAssertEqual(labelled.accessibilityLabel, "Cancel Hot Flash Mode")
        XCTAssertEqual(labelled.accessibilityValue, "")
        XCTAssertFalse(labelled.accessibilityTraits.contains(.toggleButton))
    }

    func testDiscHitTargetIsAtLeast44Points() {
        let small = disc(TileActionItem(id: "p", verb: "Go", symbol: "play"))
        small.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        XCTAssertTrue(small.point(inside: CGPoint(x: -6, y: 15), with: nil))
        XCTAssertFalse(small.point(inside: CGPoint(x: -20, y: 15), with: nil))
    }

    func testSelectionDiscsShowChosenAndOrderedStates() {
        for (selection, selected) in [(TileSelection.single(isSelected: true), true), (.single(isSelected: false), false),
                                      (.ordered(position: 2), true), (.ordered(position: nil), false)] {
            let d = disc(TileActionItem(id: "s", verb: "Pick", symbol: "star", selection: selection), face: .dark)
            let host = UIViewController()
            let window = HostedPage.show(host)
            host.view.addSubview(d)
            d.frame = CGRect(x: 0, y: 60, width: 44, height: 44)
            d.layoutIfNeeded()
            XCTAssertEqual(d.accessibilityTraits.contains(.selected), selected)
            XCTAssertEqual(d.accessibilityValue, "", "a selection disc has no value")
            d.configure(item: TileActionItem(id: "s", verb: "Pick", symbol: "star", phase: .inFlight, selection: selection), face: .filled,
                        family: .lights, surface: .page, title: "Lamp", identifier: "disc", animated: true)
            d.layoutIfNeeded()
            XCTAssertFalse(d.isEnabled)
            window.isHidden = true
        }
    }

    func testStripReusesDiscsAndReportsTapsByItemId() {
        let strip = UKTileActionStrip()
        var performed: [String] = []
        strip.onPerform = { performed.append($0) }
        let items = [TileActionItem(id: "a", verb: "Pause", symbol: "pause"), TileActionItem(id: "b", verb: "Next", symbol: "forward")]
        strip.configure(items: items, title: "TV", tileIdentifier: "tile.tv", face: .dark, family: nil, surface: .page, animated: false)
        XCTAssertEqual(strip.discs.map(\.accessibilityIdentifier), ["tile.tv.action.a", "tile.tv.action.b"])
        let first = strip.discs[0]
        strip.configure(items: [items[0]], title: "TV", tileIdentifier: "tile.tv", face: .filled, family: nil, surface: .page, animated: true)
        XCTAssertEqual(strip.discs.count, 1)
        XCTAssertTrue(strip.discs[0] === first, "an action that stays keeps its disc")
        first.sendActions(for: .touchUpInside)
        XCTAssertEqual(performed, ["a"])
        XCTAssertEqual(strip.sizeThatFits(.zero).width, UKTileActionStrip.width(count: 1, traits: strip.traitCollection))
        strip.configure(items: [], title: "TV", tileIdentifier: nil, face: .dark, family: nil, surface: .page, animated: false)
        XCTAssertEqual(strip.sizeThatFits(.zero).height, 0)
        strip.configure(items: items, title: "TV", tileIdentifier: nil, face: .dark, family: nil, surface: .page, animated: false)
        strip.frame = CGRect(x: 0, y: 0, width: 100, height: 44)
        strip.semanticContentAttribute = .forceRightToLeft
        strip.layoutIfNeeded()
        XCTAssertLessThan(strip.discs[0].frame.minX, strip.discs[1].frame.minX + 100)
    }

    func testVolumeSliderStepsForVoiceOverAndCommitsOnce() {
        var committed: [Int] = []
        let slider = UKTileVolumeSlider(title: "Kitchen", percent: 30, identifier: "vol") { committed.append($0) }
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        host.view.addSubview(slider)
        slider.frame = CGRect(x: 20, y: 80, width: 200, height: 44)
        slider.layoutIfNeeded()
        XCTAssertEqual(slider.accessibilityLabel, "Volume Kitchen")
        XCTAssertEqual(slider.accessibilityValue, "30 percent")
        XCTAssertTrue(slider.accessibilityTraits.contains(.adjustable))
        slider.accessibilityIncrement()
        XCTAssertEqual(committed, [35])
        XCTAssertEqual(slider.accessibilityValue, "35 percent", "the level just asked for shows until the live one arrives")
        slider.accessibilityDecrement()
        XCTAssertEqual(committed, [35, 30])
        slider.update(percent: 60, isDisabled: false)
        XCTAssertEqual(slider.accessibilityValue, "60 percent")
        slider.update(percent: 60, isDisabled: true)
        XCTAssertEqual(slider.alpha, 0.5)
        slider.accessibilityIncrement()
        XCTAssertEqual(committed.count, 2, "a disabled slider ignores steps")
        XCTAssertEqual(slider.sizeThatFits(CGSize(width: 100, height: 0)).width, 100)
        XCTAssertGreaterThanOrEqual(slider.intrinsicContentSize.height, 44)
        slider.title = "Den"
        XCTAssertEqual(slider.accessibilityLabel, "Volume Den")
        slider.semanticContentAttribute = .forceRightToLeft
        slider.setNeedsLayout(); slider.layoutIfNeeded()
    }
}
