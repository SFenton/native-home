import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// The entity tile: what it says, which action a tap runs, and what VoiceOver gets.
@MainActor
final class UKHostedTileTests: XCTestCase {
    private func lockItems(confirm: Bool = false) -> [TileActionItem] {
        [TileActionItem(id: "lock", verb: "Unlock", symbol: "lock.fill", isOn: true, feedback: .tracked,
                        confirmation: confirm ? TileActionConfirmation(title: "Unlock the door?", confirmVerb: "Unlock") : nil)]
    }

    private func place(_ tile: UKGlassTileView, width: CGFloat = 175, in host: UIViewController) {
        host.view.addSubview(tile)
        tile.frame = CGRect(x: 10, y: 80, width: width, height: tile.gridHeight(forWidth: width))
        tile.layoutIfNeeded()
    }

    func testToggleTileSpeaksStateAndTapRunsTheAction() {
        var taps = 0
        let tile = UKGlassTileView(model: UKGlassTileModel(title: "Kitchen", subtitle: "On", symbol: "lightbulb", family: .lights, isActive: true,
                                                          identifier: "tile.kitchen")) { taps += 1 }
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        place(tile, in: host)
        XCTAssertEqual(tile.accessibilityLabel, "Kitchen")
        XCTAssertEqual(tile.accessibilityValue, "On")
        let body = tile.accessibilityElements?.first as? UIAccessibilityElement
        XCTAssertEqual(body?.accessibilityIdentifier, "tile.kitchen")
        XCTAssertTrue(body?.accessibilityTraits.contains(.toggleButton) ?? false, "a tile with a state line is a container; its body is the switch")
        XCTAssertTrue(body?.accessibilityActivate() ?? false)
        tile.sendActions(for: .touchUpInside)
        XCTAssertEqual(taps, 2)
        XCTAssertEqual((tile.accessibilityElements?.dropFirst().first as? UIAccessibilityElement)?.accessibilityLabel, "On", "the state line is its own text stop")
        tile.isHighlighted = true
        XCTAssertLessThan(tile.face.alpha, 1)
        tile.isHighlighted = false
        XCTAssertEqual(tile.face.alpha, 1)
    }

    func testStateErrorUnavailableAndLoadingValues() {
        let model = UKGlassTileModel(title: "Door", subtitle: "Jammed", symbol: "lock", isActive: false, isError: true)
        XCTAssertEqual(model.accessibilityValue(valuesPending: false), "Jammed")
        XCTAssertEqual(model.accessibilityValue(valuesPending: true), "Loading")
        let bare = UKGlassTileModel(title: "Door", symbol: "lock", isActive: false, isError: true)
        XCTAssertEqual(bare.accessibilityValue(valuesPending: false), "Error")
        let gone = UKGlassTileModel(title: "Door", subtitle: "x", symbol: "lock", isActive: false, isUnavailable: true)
        XCTAssertEqual(gone.accessibilityValue(valuesPending: false), "Unavailable")
        let spoken = UKGlassTileModel(title: "Dim", symbol: "sun.max", isActive: true, spokenValue: "40%")
        XCTAssertEqual(spoken.accessibilityValue(valuesPending: false), "40%")
        let off = UKGlassTileModel(title: "Lamp", symbol: "lamp", isActive: false)
        XCTAssertEqual(off.accessibilityValue(valuesPending: false), "Off")
        var command = UKGlassTileModel(title: "Dim", symbol: "sun", isActive: true)
        command.useCommandSemantics()
        XCTAssertEqual(command.kind, .command)
        let twoLine = UKGlassTileModel(title: "T", subtitle: "Line one\nLine two", symbol: "star", isActive: false, kind: .state)
        XCTAssertEqual(twoLine.spokenSubtitle, "Line one, Line two")
        XCTAssertTrue(UKGlassTileModel(title: "S", symbol: "star", isActive: false, kind: .state).isInert)
    }

    func testInertAndUnavailableTilesAreNotButtons() {
        let inert = UKGlassTileView(model: UKGlassTileModel(title: "Temp", subtitle: "21°", symbol: "thermometer", isActive: false, kind: .state))
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        place(inert, in: host)
        XCTAssertFalse(inert.accessibilityActivate(), "a read-only tile has nothing to activate")
        XCTAssertNil(inert.hitTest(CGPoint(x: 20, y: 20), with: nil), "touches pass through a read-only tile")
        XCTAssertTrue(inert.accessibilityTraits.contains(.staticText))

        let off = UKGlassTileView(model: UKGlassTileModel(title: "Fan", subtitle: "Unavailable", symbol: "fan", isActive: false, isUnavailable: true))
        place(off, in: host)
        XCTAssertTrue(off.accessibilityTraits.contains(.notEnabled))
    }

    func testNavigateTileShowsAChevronAndCommandTileIsAButton() {
        let nav = UKGlassTileView(model: UKGlassTileModel(title: "Cameras", symbol: "video", isActive: false, kind: .navigate))
        XCTAssertEqual(nav.accessibilityTraits, .button)
        let selected = UKGlassTileModel(title: "Mode", symbol: "star", isActive: true, behavior: .perform("pick"),
                                        actions: [TileActionItem(id: "pick", verb: "Pick", symbol: "star", selection: .single(isSelected: true))])
        XCTAssertEqual(selected.kind, .selection(isSelected: true))
        let selTile = UKGlassTileView(model: selected)
        XCTAssertTrue(selTile.accessibilityTraits.contains(.selected))
    }

    func testActionTileDiscsPerformAndConfirmationAsksFirst() {
        var performed: [String] = []
        let model = UKGlassTileModel(title: "Front door", subtitle: "Locked", symbol: "lock.fill", isActive: true, behavior: .perform("lock"),
                                     actions: lockItems(confirm: true), identifier: "tile.door")
        let tile = UKGlassTileView(model: model)
        tile.onPerform = { performed.append($0) }
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        place(tile, in: host)
        XCTAssertFalse(tile.isAccessibilityElement, "a tile with a disc is a container")
        let elements = tile.accessibilityElements ?? []
        XCTAssertGreaterThanOrEqual(elements.count, 2, "body and subtitle at least")
        XCTAssertEqual(tile.accessibilityIdentifier, "tile.door.tile")
        // A body tap with a confirmation asks first.
        tile.sendActions(for: .touchUpInside)
        hostedSettle(0.4)
        XCTAssertTrue(performed.isEmpty, "asks before unlocking")
        let alert = host.presentedViewController as? UIAlertController
        XCTAssertEqual(alert?.title, "Unlock the door?")
        XCTAssertEqual(alert?.actions.map(\.title), ["Cancel", "Unlock"])
        if let confirm = alert?.actions.last, let handler = confirm.value(forKey: "handler") {
            typealias Handler = @convention(block) (UIAlertAction) -> Void
            unsafeBitCast(handler as AnyObject, to: Handler.self)(confirm)
        }
        XCTAssertEqual(performed, ["lock"])
    }

    func testPlainActionTileRunsTheItemWithoutAsking() {
        var performed: [String] = []
        let model = UKGlassTileModel(title: "Lamp", subtitle: "On", symbol: "lamp", isActive: true, behavior: .perform("lock"), actions: lockItems())
        let tile = UKGlassTileView(model: model)
        tile.onPerform = { performed.append($0) }
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        place(tile, in: host)
        XCTAssertTrue(tile.accessibilityActivate())
        XCTAssertEqual(performed, ["lock"])
        XCTAssertNotNil(tile.accessibilityHint, "the one hidden disc's verb is the body's hint")
    }

    func testAdjustableTileForwardsIncrementAndDecrement() {
        var steps: [Bool] = []
        let tile = UKGlassTileView(model: UKGlassTileModel(title: "Dim", subtitle: "40%", symbol: "sun.max", isActive: true))
        tile.onAdjust = { steps.append($0) }
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        place(tile, in: host)
        tile.configure(UKGlassTileModel(title: "Dim", subtitle: "40%", symbol: "sun.max", isActive: true), animated: false)
        tile.accessibilityIncrement()
        tile.accessibilityDecrement()
        XCTAssertEqual(steps, [true, false])
    }

    func testFitsAndMinimumWidthFollowTheContent() {
        var model = UKGlassTileModel(title: "A fairly long tile title here", subtitle: "Playing something", symbol: "play", isActive: true,
                                     behavior: .perform("a"), actions: [
                                        TileActionItem(id: "a", verb: "Pause", symbol: "pause.fill"),
                                        TileActionItem(id: "b", verb: "Next", symbol: "forward.fill"),
                                        TileActionItem(id: "c", verb: "Prev", symbol: "backward.fill")])
        model.stateCandidates = ["Playing", "Paused", "Idle"]
        let tile = UKGlassTileView(model: model)
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let wide = tile.gridHeight(forWidth: 420)
        let narrow = tile.gridHeight(forWidth: 130)
        XCTAssertGreaterThan(tile.gridMinimumWidth, 96)
        XCTAssertGreaterThanOrEqual(narrow, wide, "a narrow tile moves its discs below and grows")
        for width: CGFloat in [420, 200, 130] { place(tile, width: width, in: host); tile.removeFromSuperview() }
        XCTAssertGreaterThan(tile.sizeThatFits(.zero).height, 0)
        XCTAssertGreaterThan(tile.intrinsicContentSize.height, 0)
    }

    func testChangingTheControlsReshapesTheTile() {
        let one = UKGlassTileModel(title: "Remote", subtitle: "Off", symbol: "tv", isActive: false, behavior: .perform("a"),
                                   actions: [TileActionItem(id: "a", verb: "On", symbol: "power")])
        let three = UKGlassTileModel(title: "Remote", subtitle: "Playing", symbol: "tv", isActive: true, behavior: .perform("a"), actions: [
            TileActionItem(id: "a", verb: "Pause", symbol: "pause.fill"), TileActionItem(id: "b", verb: "Next", symbol: "forward.fill"),
            TileActionItem(id: "c", verb: "Prev", symbol: "backward.fill")])
        let tile = UKGlassTileView(model: one)
        tile.gridFullRow = true
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        place(tile, width: 300, in: host)
        let slider = UIView(); slider.frame = CGRect(x: 0, y: 0, width: 100, height: 30)
        tile.setAccessory(slider)
        tile.configure(three, animated: true)
        hostedSettle(1.5)
        tile.configure(one, animated: false)
        tile.layoutIfNeeded()
        tile.setAccessory(nil)
        let errored = UKGlassTileModel(title: "Remote", subtitle: "Failed", symbol: "tv", isActive: false, isError: true)
        tile.configure(errored, animated: true)
        XCTAssertEqual(tile.accessibilityValue, "Failed")
    }

    func testAccessibilitySizeTilesStillLayOut() {
        let tile = UKGlassTileView(model: UKGlassTileModel(title: "Living room lamp", subtitle: "On, 40%", symbol: "lamp", isActive: true,
                                                          behavior: .perform("a"), actions: [TileActionItem(id: "a", verb: "Off", symbol: "power", isOn: true)]))
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        host.view.addSubview(tile)
        tile.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        tile.frame = CGRect(x: 0, y: 60, width: 340, height: 300)
        tile.overrideUserInterfaceStyle = .dark
        tile.layoutIfNeeded()
        XCTAssertGreaterThan(tile.gridHeight(forWidth: 340), 40)
    }
}
