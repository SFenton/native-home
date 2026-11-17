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
        tile.tracesBand = true
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

    /// The band levels the face was given, from `start`, with consecutive repeats collapsed and a missing band as -1: `[0.7, 0.4]` is a band that
    /// stayed at 70 and then went to 40, and a flash would show as `[0.7, 0.4, 0.7]`.
    private func levels(_ tile: UKGlassTileView, from start: Int) -> [Double] {
        var out: [Double] = []
        for level in tile.bandTrace.dropFirst(start) {
            let value = ((level ?? -1) * 1000).rounded() / 1000
            if out.last != value { out.append(value) }
        }
        return out
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
            drag(r, [0.2, 0.5, 0.7], end: .possible)
            let traced = r.tile.bandTrace.count
            drag(r, [0.7])
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
            XCTAssertEqual(levels(r.tile, from: traced), [0.7, 0.4], "the band is the committed 70 until the hold ends, never the live 40 first (width \(width))")
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

    /// C8, the user's case: the house sends a new state with a new word while a finger is on the tile. The tile draws what it drew (subtitle and
    /// band) and keeps the slot its container gave it (its `bounds` equal the slot, its transform being the lift); the drag stays live and the
    /// new state is drawn on release.
    func testAChangeWithANewWordDuringADragWaitsForTheFingerAndIsDrawnOnRelease() async throws {
        for width in Self.widths {
            let r = try await rig(width: width, revert: 30)
            defer { r.window.isHidden = true }
            r.window.layoutIfNeeded()
            await HostedPage.pump(passes: 5)
            let slot = r.tile.frame
            drag(r, [0.2, 0.5], end: .possible)
            XCTAssertTrue(r.controller.isDragging, "the finger is down (width \(width))")
            let heldSubtitle = r.tile.model.subtitle
            let heldProgress = try XCTUnwrap(r.tile.model.progress)
            r.store.apply([EntityState(entityId: Self.blinds, state: "closing", attributes: ["current_position": .number(20)])])
            await HostedPage.pump(passes: 8)
            XCTAssertTrue(r.controller.isDragging, "the drag stays live (width \(width)): \(r.controller.lastCancelReason ?? "not cancelled")")
            XCTAssertEqual(r.tile.bounds.size.width, slot.width, accuracy: 0.5, "the tile's bounds are its slot under the lift (width \(width))")
            XCTAssertEqual(r.tile.bounds.size.height, slot.height, accuracy: 0.5)
            XCTAssertEqual(r.tile.model.subtitle, heldSubtitle, "the held subtitle is drawn")
            XCTAssertEqual(try XCTUnwrap(r.tile.model.progress), heldProgress, accuracy: 0.001, "the held band is drawn")
            drag(r, [0.5], end: .cancelled)
            let applied = await HostedPage.settle { r.tile.model.subtitle != heldSubtitle && abs((r.tile.model.progress ?? 0) - 0.2) < 0.001 }
            XCTAssertTrue(applied, "the new state is drawn after release (width \(width))")
            XCTAssertEqual(r.caller.calls, [], "a cancelled drag sends nothing")
            HostedPage.hideTracked()
        }
    }

    /// What a release draws (`build/design/tile-swipe-release.md`): live 40, a drag to 50, "closing" 20 held under the finger, the lift at 50 and a
    /// hold of 3 s the house never answers.
    /// 1. one call with 50 and the band stays at 50, the held configure never drawn;
    /// 2. the first configure after the lift keeps the band at 50 and speaks "50%";
    /// 3. nothing moves the band until the deadline;
    /// 4. at the deadline the store's live state is drawn: "closing", 20.
    func testAHeldChangeThenTheFingerLiftsDrawsTheCommittedBandUntilTheHoldEndsThenTheStoresState() async throws {
        for width in Self.widths {
            let r = try await rig(width: width, revert: 3)
            defer { r.window.isHidden = true }
            r.window.layoutIfNeeded()
            await HostedPage.pump(passes: 5)
            drag(r, [0.2, 0.5], end: .possible)
            let heldSubtitle = r.tile.model.subtitle
            r.store.apply([EntityState(entityId: Self.blinds, state: "closing", attributes: ["current_position": .number(20)])])
            await HostedPage.pump(passes: 8)
            XCTAssertTrue(r.controller.isDragging, r.controller.lastCancelReason ?? "")
            XCTAssertEqual(r.tile.model.subtitle, heldSubtitle, "row 0: held under the finger (width \(width))")
            let traced = r.tile.bandTrace.count
            let configures = r.tile.configureCount
            drag(r, [0.5], end: .ended)
            XCTAssertFalse(r.controller.isDragging, "row 1: the lift ends the drag in the same turn")
            let called = await HostedPage.settle { !r.caller.calls.isEmpty }
            XCTAssertTrue(called)
            XCTAssertEqual(r.caller.calls, ["cover.set_cover_position"], "row 1: one call")
            XCTAssertEqual(sent(r.caller), [50])
            let configured = await HostedPage.settle { r.tile.configureCount > configures }
            XCTAssertTrue(configured, "row 2: the tile is configured after the lift")
            XCTAssertEqual(try XCTUnwrap(r.tile.model.progress), 0.5, accuracy: 0.001, "row 2: the model carries the committed value")
            let element = try XCTUnwrap(body(r.tile))
            XCTAssertTrue((element.accessibilityValue ?? "").hasPrefix("50%"), "row 2: spoken \(element.accessibilityValue ?? "nil")")
            // Row 3: sample until just before the deadline.
            try await Task.sleep(for: .seconds(1.5))
            XCTAssertEqual(levels(r.tile, from: traced), [0.5], "rows 1 to 3: the band is 50 and never 20 or 40 (width \(width))")
            XCTAssertTrue((element.accessibilityValue ?? "").hasPrefix("50%"), "row 3: still \(element.accessibilityValue ?? "nil")")
            XCTAssertEqual(r.caller.calls.count, 1, "row 3: no second call")
            // Row 4: the deadline draws the store's state.
            let ended = await HostedPage.settle { abs((r.tile.model.progress ?? 0) - 0.2) < 0.001 && r.tile.model.subtitle != heldSubtitle }
            XCTAssertTrue(ended, "row 4: the store's state at the deadline: \(String(describing: r.tile.model.subtitle)), \(String(describing: r.tile.model.progress))")
            XCTAssertEqual(levels(r.tile, from: traced), [0.5, 0.2], "the band went 50 to 20 once")
            XCTAssertEqual(r.caller.calls.count, 1, "row 4: no call, no second send")
            HostedPage.hideTracked()
        }
    }

    /// 4a: a house update that moves the value during the hold ends it at once, well before the deadline.
    func testAHouseUpdateDuringTheHoldEndsItAtOnce() async throws {
        let r = try await rig(width: 393, revert: 30)
        defer { r.window.isHidden = true }
        r.window.layoutIfNeeded()
        await HostedPage.pump(passes: 5)
        drag(r, [0.2, 0.5], end: .possible)
        r.store.apply([EntityState(entityId: Self.blinds, state: "closing", attributes: ["current_position": .number(20)])])
        await HostedPage.pump(passes: 8)
        drag(r, [0.5], end: .ended)
        _ = await HostedPage.settle { abs((r.tile.model.progress ?? 0) - 0.5) < 0.001 }
        r.store.apply([EntityState(entityId: Self.blinds, state: "closing", attributes: ["current_position": .number(35)])])
        let followed = await HostedPage.settle { abs((r.tile.model.progress ?? 0) - 0.35) < 0.001 }
        XCTAssertTrue(followed, "the new live value ends the hold: \(String(describing: r.tile.model.progress))")
        XCTAssertEqual(r.caller.calls.count, 1)
    }

    /// The held update alone does not end the hold (`liveAtCommit` is read at the commit, after that update reached the store).
    func testTheUpdateHeldUnderTheFingerDoesNotEndTheHoldItself() async throws {
        let r = try await rig(width: 393, revert: 3)
        defer { r.window.isHidden = true }
        r.window.layoutIfNeeded()
        await HostedPage.pump(passes: 5)
        drag(r, [0.2, 0.5], end: .possible)
        r.store.apply([EntityState(entityId: Self.blinds, state: "closing", attributes: ["current_position": .number(20)])])
        await HostedPage.pump(passes: 8)
        drag(r, [0.5], end: .ended)
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(try XCTUnwrap(r.tile.model.progress), 0.5, accuracy: 0.001, "a second before the deadline the band is still 50")
    }

    /// Nothing arrives during the hold: at the deadline the tile draws the store's last word, the held state, because the house said nothing since.
    func testWithNoUpdateAtAllTheDeadlineDrawsTheLiveValueNotTheDraggedOne() async throws {
        let r = try await rig(width: 393, revert: 1)
        defer { r.window.isHidden = true }
        r.window.layoutIfNeeded()
        await HostedPage.pump(passes: 5)
        drag(r, [0.2, 0.7])
        let reverted = await HostedPage.settle { abs((r.tile.model.progress ?? 0) - 0.4) < 0.001 && !r.caller.calls.isEmpty }
        XCTAssertTrue(reverted, "the unconfirmed 70 is dropped for the store's 40")
    }

    /// A relayout of the container during a lifted drag keeps the tile's bounds equal to the slot (the container places by bounds and centre, as a
    /// transform requires); after release the tile's frame is the slot again.
    func testARelayoutDuringALiftedDragKeepsTheSlotAndAfterReleaseTheFrameIsTheSlot() async throws {
        for width in Self.widths {
            let r = try await rig(width: width, revert: 30)
            defer { r.window.isHidden = true }
            r.window.layoutIfNeeded()
            await HostedPage.pump(passes: 5)
            let slot = r.tile.frame
            let container = try XCTUnwrap(r.tile.superview)
            drag(r, [0.2, 0.5], end: .possible)
            XCTAssertTrue(r.controller.isDragging)
            XCTAssertFalse(r.tile.transform.isIdentity, "lifted (width \(width))")
            container.setNeedsLayout()
            r.window.layoutIfNeeded()
            container.setNeedsLayout()
            r.window.layoutIfNeeded()
            XCTAssertTrue(r.controller.isDragging, "a relayout is no change of window: \(r.controller.lastCancelReason ?? "")")
            XCTAssertEqual(r.tile.bounds.width, slot.width, accuracy: 0.5, "bounds equal the slot (width \(width))")
            XCTAssertEqual(r.tile.bounds.height, slot.height, accuracy: 0.5)
            XCTAssertEqual(r.tile.center.x, slot.midX, accuracy: 0.5)
            drag(r, [0.5], end: .cancelled)
            let settled = await HostedPage.settle { r.tile.transform.isIdentity }
            XCTAssertTrue(settled, "the lift ends")
            await HostedPage.pump(passes: 3)
            XCTAssertEqual(r.tile.frame.width, slot.width, accuracy: 0.5, "after release the frame is the slot")
            XCTAssertEqual(r.tile.frame.height, slot.height, accuracy: 0.5)
            XCTAssertEqual(r.tile.frame.minX, slot.minX, accuracy: 0.5)
            HostedPage.hideTracked()
        }
    }

    /// A real change of the host's width during a drag (a fold, a split) cancels it, and releasing then sends nothing.
    func testARealWidthChangeOfTheHostDuringADragCancelsItAndSendsNothing() async throws {
        for width in Self.widths {
            let r = try await rig(width: width, revert: 30)
            defer { r.window.isHidden = true }
            r.window.layoutIfNeeded()
            await HostedPage.pump(passes: 5)
            let container = try XCTUnwrap(r.tile.superview)
            drag(r, [0.2, 0.5], end: .possible)
            XCTAssertTrue(r.controller.isDragging)
            var narrower = container.bounds
            narrower.size.width -= 40
            container.bounds = narrower
            container.layoutIfNeeded()
            XCTAssertFalse(r.controller.isDragging, "a changed width drops the drag (width \(width))")
            XCTAssertTrue(r.controller.lastCancelReason?.hasPrefix("width") == true, r.controller.lastCancelReason ?? "no reason")
            // The finger lifts: the controller has no drag left, so the release has no value to send.
            let lift = ScriptedSwipePan()
            lift.scriptedState = .ended
            r.controller.perform(NSSelectorFromString("panned:"), with: lift)
            await HostedPage.pump(passes: 5)
            XCTAssertEqual(r.caller.calls, [], "nothing is sent")
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

    /// After a committing release the spoken value is the committed one at the first read and until the deadline.
    func testTheSpokenValueIsTheCommittedOneAfterAHeldReleaseUntilTheHoldEnds() async throws {
        for width in Self.widths {
            let r = try await rig(width: width, revert: 3)
            defer { r.window.isHidden = true }
            r.window.layoutIfNeeded()
            await HostedPage.pump(passes: 5)
            drag(r, [0.2, 0.5], end: .possible)
            r.store.apply([EntityState(entityId: Self.blinds, state: "closing", attributes: ["current_position": .number(20)])])
            await HostedPage.pump(passes: 8)
            drag(r, [0.5], end: .ended)
            let element = try XCTUnwrap(body(r.tile))
            let committed = await HostedPage.settle { (element.accessibilityValue ?? "").hasPrefix("50%") }
            XCTAssertTrue(committed, "the first read after the lift: \(element.accessibilityValue ?? "nil") (width \(width))")
            for _ in 0..<20 {
                XCTAssertFalse((element.accessibilityValue ?? "").hasPrefix("20%"), "the held value is never spoken before the deadline")
                try await Task.sleep(for: .milliseconds(80))
            }
            HostedPage.hideTracked()
        }
    }
}
