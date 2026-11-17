import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - A swiped state tile through the renderer

/// Hosted UX and accessibility checks for a document's `state-tile` with a swipe (`sh.tile-swipe@1`), rendered by the host so the whole path runs:
/// `UKServerUITileSwipeBinding` reads the value, draws the band, speaks it, and sends the one call through the renderer.
///
/// Each test runs at the page widths of the three families: the folded iPhone Duo, the iPhone and the iPad.
@MainActor
final class UKHostedStateTileSwipeTests: XCTestCase {
    private static let widths: [CGFloat] = [364, 393, 834]
    private static let blinds = "cover.demo_blinds"
    private static let gate = "fan.demo_bath_fan"
    private static let capabilities = ["sh.tile-swipe@1", "sh.state-style@1", "sh.call-service@1", "sh.operands@1"]

    override func tearDown() async throws {
        UKMotion.reduceMotionOverride = nil
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Fixture

    /// A blinds tile: reads `current_position`, 0 to 100 in steps of 1, sends `cover.set_cover_position` with the control's value.
    private static func tile(band: Bool = true, enabledWhen: Bool = false, revert: Double = 0.5) -> String {
        let gate = "{\"type\":\"state\",\"sourceId\":\"gate\",\"path\":[\"state\"],\"in\":[\"on\"]}"
        let rule = enabledWhen ? ",\"enabledWhen\":{\"condition\":\(gate),\"whenUnknown\":\"disabled\"}" : ""
        let bandProp = band ? "" : ",\"band\":false"
        return """
        {"id":"blinds-tile","title":"Blinds","type":"state-tile","layout":{"span":1}\(rule),
         "icon":{"type":"sf-symbol","name":"blinds.horizontal.open","rendering":"canonical","unavailable":"fallback"},
         "binding":{"entityId":"\(blinds)","builtIn":"blind"},
         "props":{"swipe":{"axis":"horizontal","range":{"min":0,"max":100,"step":1},"commit":"release",
          "value":{"type":"read","from":{"type":"source","sourceId":"blinds","path":["attributes","current_position"]},"as":"number","missing":"unavailable"},
          "action":{"type":"call-service","domain":"cover","service":"set_cover_position",
           "target":{"entity_id":{"type":"literal","value":"\(blinds)"}},
           "data":{"type":"object","fields":{"position":{"type":"control"}}},
           "optimistic":[{"sourceId":"blinds","value":"open","revertAfterSeconds":\(revert),"failsOnTimeout":false}]},
          "label":"position","format":"{value}%"\(bandProp)}}}
        """
    }

    private struct Rig {
        let host: UKServerUIRenderer
        let store: EntityStore
        let window: UIWindow
        let caller: HostedCaller
        let tile: UKGlassTileView
        let controller: UKTileSwipeController
    }

    private func rig(width: CGFloat, band: Bool = true, enabledWhen: Bool = false, gateOn: Bool = true, position: Int = 40, state: String = "open",
                     revert: Double = 0.5) async throws -> Rig {
        var root = try ServerUIRendererFixture.json()
        func json(_ text: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }
        let components = try XCTUnwrap(root["document"]?["pages"]?.array?.first?["components"]?.array)
        root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components",
                                                    to: .array(components + [json(Self.tile(band: band, enabledWhen: enabledWhen, revert: revert))]))
        let sources = try XCTUnwrap(root["document"]?["dataSources"]?.array)
        let added = [
            "{\"id\":\"blinds\",\"kind\":\"ha-entity\",\"entityId\":{\"type\":\"literal\",\"value\":\"\(Self.blinds)\"}}",
            "{\"id\":\"gate\",\"kind\":\"ha-entity\",\"entityId\":{\"type\":\"literal\",\"value\":\"\(Self.gate)\"}}",
        ]
        root = try ServerUIRendererFixture.changing(root, path: "/document/dataSources", to: .array(sources + added.map(json)))
        let capabilities = ServerUICompositionPublication.firstSliceCapabilities + Self.capabilities + (enabledWhen ? ["sh.enabled-when@1"] : [])
        root = try ServerUIRendererFixture.changing(root, path: "/capabilities", to: .array(Array(Set(capabilities)).sorted().map(JSONValue.string)))
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "switch.demo_lamp", state: "off"),
                          EntityState(entityId: Self.gate, state: gateOn ? "on" : "off"),
                          EntityState(entityId: Self.blinds, state: state, attributes: ["current_position": .number(Double(position))])])
        let caller = HostedCaller()
        let host = try UKServerUIRenderer(publication: ServerUIRendererFixture.publication(root),
                                          context: UKContext(store: store, caller: caller), backdrop: ServerUIRendererFixture.backdrop())
        host.stateStylesEnabled = true
        let window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: width, height: 900)))
        let page = try ServerUIRendererFixture.root(host)
        let landed = await HostedPage.settle { page.nodes["blinds-tile"]?.view is UKGlassTileView }
        XCTAssertTrue(landed, "the tile is drawn (width \(width))")
        let tile = try XCTUnwrap(page.nodes["blinds-tile"]?.view as? UKGlassTileView)
        await HostedPage.pump(passes: 3)
        return Rig(host: host, store: store, window: window, caller: caller, tile: tile, controller: try XCTUnwrap(tile.swipe))
    }

    /// Plays a touch as UIKit would: a recogniser the controller refuses at `gestureRecognizerShouldBegin` never reaches `panned`.
    private func drag(_ rig: Rig, _ fractions: [Double], end: UIGestureRecognizer.State = .ended) {
        guard rig.controller.gestureRecognizerShouldBegin(ScriptedSwipePan()) else { return }
        let pan = ScriptedSwipePan()
        let selector = NSSelectorFromString("panned:")
        for (index, fraction) in fractions.enumerated() {
            pan.scriptedState = index == 0 ? .began : .changed
            pan.point = CGPoint(x: rig.tile.bounds.width * fraction, y: 40)
            rig.controller.perform(selector, with: pan)
        }
        pan.scriptedState = end
        rig.controller.perform(selector, with: pan)
    }

    private func body(_ tile: UKGlassTileView) -> NSObject? { tile.accessibilityElements?.first as? NSObject }

    private func sent(_ caller: HostedCaller) -> [Double] {
        caller.data.compactMap { ($0["position"] as? Double) ?? ($0["position"] as? Int).map(Double.init) }
    }

    // MARK: UX

    func testASwipeSendsOneCallWithTheControlValueAndTheBandHoldsItThenRevertsToTheLiveValue() async throws {
        for width in Self.widths {
            let r = try await rig(width: width)
            defer { r.window.isHidden = true }
            XCTAssertEqual(try XCTUnwrap(r.tile.model.progress), 0.4, accuracy: 0.001, "the band starts at the live value (width \(width))")
            drag(r, [0.2, 0.5, 0.7])
            let called = await HostedPage.settle { !r.caller.calls.isEmpty }
            XCTAssertTrue(called, "width \(width)")
            XCTAssertEqual(r.caller.calls, ["cover.set_cover_position"], "one call on release")
            XCTAssertEqual(sent(r.caller), [70], "the `control` operand is the snapped value")
            XCTAssertEqual(r.caller.data.first?["entity_id"] as? String, Self.blinds)
            await HostedPage.pump(passes: 3)
            XCTAssertEqual(try XCTUnwrap(r.tile.model.progress), 0.7, accuracy: 0.001, "optimistic: the band stays where the finger left it")
            // Home Assistant never answers: the hold ends at `revertAfterSeconds` and the live value draws again.
            let reverted = await HostedPage.settle { abs((r.tile.model.progress ?? 0) - 0.4) < 0.001 }
            XCTAssertTrue(reverted, "the band reverts to the live 40% (width \(width))")
            XCTAssertEqual(r.caller.calls.count, 1, "reverting sends nothing")
            HostedPage.hideTracked()
        }
    }

    func testALiveAnswerReplacesTheOptimisticValueAtOnce() async throws {
        let r = try await rig(width: 393, revert: 30)
        defer { r.window.isHidden = true }
        drag(r, [0.2, 0.8])
        _ = await HostedPage.settle { !r.caller.calls.isEmpty }
        XCTAssertEqual(try XCTUnwrap(r.tile.model.progress), 0.8, accuracy: 0.001)
        r.store.apply([EntityState(entityId: Self.blinds, state: "open", attributes: ["current_position": .number(65)])])
        let live = await HostedPage.settle { abs((r.tile.model.progress ?? 0) - 0.65) < 0.001 }
        XCTAssertTrue(live, "the entity's own value ends the hold well before the 30 s revert")
    }

    func testAFailedCallRevertsTheBand() async throws {
        let r = try await rig(width: 393, revert: 30)
        defer { r.window.isHidden = true }
        r.caller.fails = true
        drag(r, [0.2, 0.9])
        let reverted = await HostedPage.settle { abs((r.tile.model.progress ?? 0) - 0.4) < 0.001 && !r.caller.calls.isEmpty }
        XCTAssertTrue(reverted, "a failed call draws the live value again, not the one the finger chose")
    }

    func testWithBandOffTheTileDrawsNoBandAndStillSendsTheValue() async throws {
        for width in Self.widths {
            let r = try await rig(width: width, band: false)
            defer { r.window.isHidden = true }
            XCTAssertNil(r.tile.model.progress, "no band at rest (width \(width))")
            drag(r, [0.2, 0.6], end: .possible)
            XCTAssertNil(r.tile.model.progress, "no band under the finger")
            drag(r, [0.2, 0.6])
            let called = await HostedPage.settle { !r.caller.calls.isEmpty }
            XCTAssertTrue(called)
            XCTAssertEqual(sent(r.caller), [60])
            await HostedPage.pump(passes: 3)
            XCTAssertNil(r.tile.model.progress, "no band after the call either")
            HostedPage.hideTracked()
        }
    }

    /// C8, the user's case: the house sends a new state with a new word while a finger is on the tile. Nothing about the tile changes under the
    /// finger, its width included; the drag stays live and the new state is drawn on release.
    func testAChangeWithANewWordDuringADragWaitsForTheFingerAndIsDrawnOnRelease() async throws {
        for width in Self.widths {
            let r = try await rig(width: width, revert: 30)
            defer { r.window.isHidden = true }
            r.window.layoutIfNeeded()
            await HostedPage.pump(passes: 5)
            let tileWidth = r.tile.bounds.width
            drag(r, [0.2, 0.5], end: .possible)
            XCTAssertTrue(r.controller.isDragging, "the finger is down (width \(width))")
            let heldSubtitle = r.tile.model.subtitle
            let heldProgress = try XCTUnwrap(r.tile.model.progress)
            r.store.apply([EntityState(entityId: Self.blinds, state: "closing", attributes: ["current_position": .number(20)])])
            await HostedPage.pump(passes: 8)
            XCTAssertTrue(r.controller.isDragging, "the drag stays live (width \(width)): \(r.controller.lastCancelReason ?? "not cancelled")")
            XCTAssertEqual(r.tile.bounds.width * r.tile.transform.a, tileWidth, accuracy: 0.5, "the tile keeps the room it was given under the finger")
            XCTAssertEqual(r.tile.model.subtitle, heldSubtitle, "the held subtitle is drawn")
            XCTAssertEqual(try XCTUnwrap(r.tile.model.progress), heldProgress, accuracy: 0.001, "the held band is drawn")
            drag(r, [0.5], end: .cancelled)
            let applied = await HostedPage.settle { r.tile.model.subtitle != heldSubtitle && abs((r.tile.model.progress ?? 0) - 0.2) < 0.001 }
            XCTAssertTrue(applied, "the new state is drawn after release (width \(width))")
            XCTAssertEqual(r.caller.calls, [], "a cancelled drag sends nothing")
            HostedPage.hideTracked()
        }
    }

    /// A value-only change (same word) during a drag: the band holds, then follows.
    func testAValueOnlyChangeDuringADragHoldsTheBandUntilRelease() async throws {
        let r = try await rig(width: 393, revert: 30)
        defer { r.window.isHidden = true }
        r.window.layoutIfNeeded()
        await HostedPage.pump(passes: 5)
        drag(r, [0.2, 0.5], end: .possible)
        r.store.apply([EntityState(entityId: Self.blinds, state: "open", attributes: ["current_position": .number(20)])])
        await HostedPage.pump(passes: 8)
        XCTAssertTrue(r.controller.isDragging, r.controller.lastCancelReason ?? "")
        XCTAssertEqual(try XCTUnwrap(r.tile.model.progress), 0.4, accuracy: 0.001)
        drag(r, [0.5], end: .cancelled)
        let applied = await HostedPage.settle { abs((r.tile.model.progress ?? 0) - 0.2) < 0.001 }
        XCTAssertTrue(applied)
    }

    func testEnabledWhenSaysNoAndTheTileTakesNoDragNoStepAndSendsNothing() async throws {
        for width in Self.widths {
            let r = try await rig(width: width, enabledWhen: true, gateOn: false)
            defer { r.window.isHidden = true }
            XCTAssertFalse(r.controller.gestureRecognizerShouldBegin(ScriptedSwipePan()), "the rule says no: no drag (width \(width))")
            drag(r, [0.2, 0.7])
            body(r.tile)?.accessibilityIncrement()
            await HostedPage.pump(passes: 5)
            XCTAssertEqual(r.caller.calls, [], "nothing is sent")
            r.store.apply([EntityState(entityId: Self.gate, state: "on")])
            let enabled = await HostedPage.settle { r.tile.onAdjust != nil }
            XCTAssertTrue(enabled, "the rule says yes: the tile adjusts again, in place")
            XCTAssertTrue(r.controller.gestureRecognizerShouldBegin(ScriptedSwipePan()))
            HostedPage.hideTracked()
        }
    }

    func testAnUnavailableEntityTakesNoDrag() async throws {
        let r = try await rig(width: 393, state: "unavailable")
        defer { r.window.isHidden = true }
        XCTAssertFalse(r.controller.gestureRecognizerShouldBegin(ScriptedSwipePan()))
        drag(r, [0.2, 0.7])
        await HostedPage.pump(passes: 3)
        XCTAssertEqual(r.caller.calls, [])
    }

    // MARK: Accessibility

    func testTheSpokenValueIsTheNumberThenTheStateWord() async throws {
        for width in Self.widths {
            let r = try await rig(width: width)
            defer { r.window.isHidden = true }
            let element = try XCTUnwrap(body(r.tile))
            XCTAssertEqual(r.tile.model.spokenValue, "40%, Open", "width \(width)")
            XCTAssertEqual(element.accessibilityValue, "40%, Open")
            XCTAssertTrue(element.accessibilityTraits.contains(.adjustable))
            XCTAssertEqual(element.accessibilityCustomActions?.map(\.name), ["Increase Position", "Decrease Position"])
            HostedPage.hideTracked()
        }
    }

    func testIncrementAndDecrementEachSendOneCallWithTheSteppedValue() async throws {
        for width in Self.widths {
            let r = try await rig(width: width, revert: 30)
            defer { r.window.isHidden = true }
            let element = try XCTUnwrap(body(r.tile))
            element.accessibilityIncrement()
            _ = await HostedPage.settle { r.caller.calls.count == 1 }
            XCTAssertEqual(sent(r.caller), [50], "one detent up (10) through the renderer (width \(width))")
            let action = try XCTUnwrap(element.accessibilityCustomActions?.last)
            _ = action.actionHandler?(action)
            _ = await HostedPage.settle { r.caller.calls.count == 2 }
            XCTAssertEqual(sent(r.caller), [50, 40], "the named action steps from the value the tile shows, not the stale live one")
            HostedPage.hideTracked()
        }
    }

    func testAnUnavailableOrDisabledTileHasNoAdjustableTraitNoHintAndNoActions() async throws {
        let off = try await rig(width: 393, enabledWhen: true, gateOn: false)
        defer { off.window.isHidden = true }
        let unavailable = try await rig(width: 393, state: "unavailable")
        defer { unavailable.window.isHidden = true }
        for r in [off, unavailable] {
            let element = body(r.tile)
            XCTAssertFalse((element?.accessibilityTraits ?? r.tile.accessibilityTraits).contains(.adjustable))
            XCTAssertNil(element?.accessibilityCustomActions)
            XCTAssertFalse((element?.accessibilityHint ?? "").contains("Swipe"))
            XCTAssertNil(r.tile.onAdjust)
        }
    }
}
