import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - Tests

/// Hosted UX and accessibility checks for the dial and the arc track (`sh.dial@1`, `sh.arc-track@1`) at the widths of the iPhone, the folded iPhone
/// Duo and the iPad.
///
/// Every document is a case of the shared corpus, so what the Studio previews is what these draw. A simulator narrower than a width draws it at the
/// simulator's own, so each check reads the width the view really has. A dial and an arc take no touch, so nothing here taps: what changes is the
/// data (an entity's state), and each change is one write to one view.
@MainActor
final class ServerUIDialHostedTests: XCTestCase {
    private static let widths: [CGFloat] = [390, 744, 1024]
    private typealias F = ServerUIChartFixture

    override func tearDown() async throws {
        UKMotion.reduceMotionOverride = nil
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Helpers

    private static func entity(_ state: String) -> EntityState { EntityState(entityId: "sensor.demo_bath_temperature", state: state, attributes: [:]) }

    /// A number read from the demo temperature sensor's state.
    private static let reads: JSONValue = .object([
        "type": .string("read"),
        "from": .object(["type": .string("source"), "sourceId": .string("temp"), "path": .array([.string("state")])]),
        "as": .string("number"), "missing": .string("unavailable")
    ])

    private func dial(_ shown: ServerUIChartFixture, _ id: String = "d") throws -> UKDialView {
        try XCTUnwrap(shown.page.nodes[id]?.view as? UKDialView, "no dial named \(id)")
    }

    private func arc(_ shown: ServerUIChartFixture, _ id: String = "a") throws -> UKArcTrackView {
        try XCTUnwrap(shown.page.nodes[id]?.view as? UKArcTrackView, "no arc named \(id)")
    }

    /// A needle whose number follows the temperature sensor.
    private func followed(_ file: String, width: CGFloat, state: String, reduceMotion: Bool = false, animates: Bool? = nil) throws -> ServerUIChartFixture {
        try F.show(file, width: width, entities: [Self.entity(state)], reduceMotion: reduceMotion) { components in
            let bound = F.setting(["pointer", "value"], to: Self.reads, in: components)
            return animates.map { F.setting(["pointer", "animates"], to: .bool($0), in: bound) } ?? bound
        }
    }

    // MARK: Placing

    /// The ring, the lit tick and the letters stand where the shared arithmetic puts them, as wide as the room, and the dial is as tall as its shape.
    func testATickDialIsPlacedByTheSharedArithmeticAcrossTheRoom() throws {
        for width in Self.widths {
            let shown = try F.show("dial-tick", width: width)
            defer { shown.window.isHidden = true }
            let view = try dial(shown)
            let document = try XCTUnwrap(view.dial)
            XCTAssertEqual(view.dialFrame.width, view.bounds.width, accuracy: 1, "a dial with no size fills the room (width \(width))")
            XCTAssertEqual(view.dialFrame.height, view.dialFrame.width / CGFloat(document.aspect), accuracy: 0.01)
            let expected = ServerUIDialLayout.layoutDial(document.layoutInput(width: Double(view.dialFrame.width), value: 0.5, rtl: false))
            XCTAssertEqual(view.placed, expected, "the layout is the shared one")
            XCTAssertEqual(expected.ticks.count, 25)
            XCTAssertNotNil(expected.lit)
            XCTAssertEqual(view.gridHeight(forWidth: view.bounds.width), view.dialFrame.height, accuracy: 0.01)
            XCTAssertFalse(view.isNeedleShown, "a tick pointer has no needle")
        }
    }

    /// The compass's letters stand on the rim at a fifth of the radius in size (never below 10), E and W only while the needle has a direction.
    func testTheLettersStandOnTheRimAndEastAndWestNeedADirection() throws {
        for width in Self.widths {
            let shown = try followed("dial-needle", width: width, state: "90")
            defer { shown.window.isHidden = true }
            let view = try dial(shown)
            XCTAssertEqual(view.shownLetters, ["N", "E", "S", "W"], "width \(width)")
            let placed = try XCTUnwrap(view.placed)
            for (label, spot) in zip(view.letterLabels, placed.labels) {
                XCTAssertEqual(label.center.x, view.dialFrame.minX + CGFloat(spot.x), accuracy: 0.5)
                XCTAssertEqual(label.center.y, view.dialFrame.minY + CGFloat(spot.y), accuracy: 0.5)
                XCTAssertEqual(label.font.pointSize, CGFloat(spot.fontSize), accuracy: 0.01)
            }
            shown.store.apply([Self.entity("unavailable")])
            HostedPage.until { view.shownLetters == ["N", "S"] }
            XCTAssertEqual(view.shownLetters, ["N", "S"], "no direction drops E and W")
            XCTAssertFalse(view.isNeedleShown, "and hides the needle")
        }
    }

    /// The text in the middle is centred on the ring's centre, one line under the other, and is not read on its own.
    func testTheTextInTheMiddleIsCentredOnTheRingAndSilent() throws {
        for width in Self.widths {
            let shown = try F.show("dial-center-text", width: width, entities: [Self.entity("1013")])
            defer { shown.window.isHidden = true }
            let view = try dial(shown)
            let lines = view.centerLines
            XCTAssertEqual(lines.count, 2, "width \(width)")
            XCTAssertEqual(lines[0].accessibilityLabel, "1013", "a line reads its entity")
            XCTAssertEqual(lines[1].accessibilityLabel, "unit")
            let top = lines[0].frame.minY, bottom = lines[1].frame.maxY
            let cy = view.dialFrame.minY + CGFloat(try XCTUnwrap(view.placed).cy)
            XCTAssertEqual((top + bottom) / 2, cy, accuracy: 1, "the block is centred on the ring")
            XCTAssertLessThanOrEqual(lines[0].frame.maxY, lines[1].frame.minY + 0.5, "one under the other")
            XCTAssertTrue(lines.allSatisfy { !$0.isAccessibilityElement && $0.accessibilityElementsHidden }, "not read on their own")
            XCTAssertTrue(lines[0].drawnShrinks, "a single line shrinks before it is cut")
            XCTAssertFalse(view.isAccessibilityElement, "a dial that names nothing is hidden")
        }
    }

    // MARK: Needle

    /// The needle turns the short way round (350 to 10 is 20 degrees on), in place, with the standard glide.
    func testTheNeedleTurnsTheShortWayRoundInPlace() throws {
        for width in Self.widths {
            let shown = try followed("dial-needle", width: width, state: "350")
            defer { shown.window.isHidden = true }
            let view = try dial(shown)
            XCTAssertEqual(try XCTUnwrap(view.turned), 350, accuracy: 0.01, "the first draw is placed at once (width \(width))")
            let (draws, turns, face, needle) = (view.drawCount, view.animatedTurns, view.faceView, view.needleView)
            shown.store.apply([Self.entity("10")])
            HostedPage.until { view.drawCount > draws }
            XCTAssertEqual(view.drawCount, draws + 1, "one entity change is one update")
            XCTAssertEqual(view.animatedTurns, turns + 1, "the needle glides")
            XCTAssertEqual(try XCTUnwrap(view.turned), 370, accuracy: 0.01, "20 degrees on, not 340 back")
            HostedPage.wait(0.5)
            XCTAssertEqual(view.needleDegrees, 10, accuracy: 1.5)
            XCTAssertTrue(view.faceView === face && view.needleView === needle, "the parts stay")
            XCTAssertTrue(shown.page.nodes["d"]?.view === view, "the view stays")

            shown.store.apply([Self.entity("350")])
            HostedPage.until { view.drawCount > draws + 1 }
            XCTAssertEqual(try XCTUnwrap(view.turned), 350, accuracy: 0.01, "and 20 degrees back")
        }
    }

    /// Reduce Motion, or a needle that says it does not animate, turns at once.
    func testTheNeedleJumpsUnderReduceMotionAndWhenTheDocumentSaysSo() throws {
        for width in Self.widths {
            let still = try followed("dial-needle", width: width, state: "350", reduceMotion: true)
            defer { still.window.isHidden = true }
            let reduced = try dial(still)
            let draws = reduced.drawCount
            still.store.apply([Self.entity("10")])
            HostedPage.until { reduced.drawCount > draws }
            XCTAssertEqual(reduced.animatedTurns, 0, "under Reduce Motion the needle jumps (width \(width))")
            XCTAssertEqual(reduced.needleDegrees, 10, accuracy: 0.5, "and is already where it ends")

            let fixed = try followed("dial-needle", width: width, state: "350", animates: false)
            defer { fixed.window.isHidden = true }
            let view = try dial(fixed)
            let fixedDraws = view.drawCount
            fixed.store.apply([Self.entity("10")])
            HostedPage.until { view.drawCount > fixedDraws }
            XCTAssertEqual(view.animatedTurns, 0, "animates: false never glides")
            XCTAssertEqual(view.needleDegrees, 10, accuracy: 0.5)
        }
    }

    /// A needle that goes away and returns appears where it belongs and never glides in from where it last stood.
    func testANeedleThatReturnsAppearsInPlace() throws {
        for width in Self.widths {
            let shown = try followed("dial-needle", width: width, state: "90")
            defer { shown.window.isHidden = true }
            let view = try dial(shown)
            shown.store.apply([Self.entity("unavailable")])
            HostedPage.until { !view.isNeedleShown }
            let turns = view.animatedTurns
            shown.store.apply([Self.entity("200")])
            HostedPage.until { view.isNeedleShown }
            XCTAssertEqual(view.animatedTurns, turns, "it appears in place (width \(width))")
            XCTAssertEqual(try XCTUnwrap(view.turned), 200, accuracy: 0.01)
        }
    }

    /// A tick pointer lights the tick of the entity's share, and the face redraws only when that changes.
    func testTheLitTickFollowsItsEntityAndAnUnchangedReadingDrawsNothing() throws {
        for width in Self.widths {
            let shown = try F.show("dial-pointer-bound", width: width, entities: [Self.entity("20")])
            defer { shown.window.isHidden = true }
            let view = try dial(shown)
            let face = try XCTUnwrap(view.faceView as? UKDialFaceView)
            let lit = try XCTUnwrap(view.placed?.lit)
            let draws = view.drawCount
            shown.store.apply([Self.entity("0.9")])
            HostedPage.until { view.drawCount > draws }
            XCTAssertNotEqual(view.placed?.lit, lit, "the lit tick moved (width \(width))")
            let faceDraws = face.drawCount
            shown.store.apply([Self.entity("0.9")])
            shown.settle()
            XCTAssertEqual(view.drawCount, draws + 1, "the same reading is not an update")
            for _ in 0..<10 { shown.page.view.setNeedsLayout(); shown.page.view.layoutIfNeeded(); HostedPage.layoutTracked() }
            XCTAssertEqual(face.drawCount, faceDraws, "laying out again writes nothing")
        }
    }

    // MARK: Size and direction

    /// A dial with a size scales with the text size up to its cap; one with no size fills the room up to `maxWidth`.
    func testASizedDialScalesWithTheTextSizeUpToItsCap() throws {
        for width in Self.widths {
            let large = try F.show("dial-size-scaled", width: width, category: .large)
            defer { large.window.isHidden = true }
            XCTAssertEqual(try dial(large).dialFrame.width, 104, accuracy: 1, "104 points at the default size (width \(width))")
            XCTAssertEqual(try dial(large).intrinsicContentSize, CGSize(width: 104, height: 104))

            let huge = try F.show("dial-size-scaled", width: width, category: .accessibilityExtraExtraExtraLarge)
            defer { huge.window.isHidden = true }
            XCTAssertEqual(try dial(huge).dialFrame.width, min(160, huge.page.view.bounds.width), accuracy: 1, "scaled, and never more than 160")
            XCTAssertGreaterThan(try dial(huge).dialFrame.width, 104)
        }
    }

    /// A dial keeps its places in a right-to-left layout unless it says it mirrors; an arc mirrors unless it says it does not.
    func testADialKeepsItsPlacesAndAnArcMirrorsInARightToLeftLayout() throws {
        for width in Self.widths {
            let kept = try F.show("dial-tick", width: width)
            defer { kept.window.isHidden = true }
            let still = try dial(kept)
            let before = try XCTUnwrap(still.placed)
            still.semanticContentAttribute = .forceRightToLeft
            still.setNeedsLayout()
            kept.settle()
            XCTAssertEqual(still.placed, before, "a dial that does not mirror keeps its places (width \(width))")

            let flipped = try F.show("dial-mirrors", width: width) { F.setting(["pointer", "value"], to: .object(["type": .string("literal"), "value": .number(0.25)]), in: $0) }
            defer { flipped.window.isHidden = true }
            let mirrored = try dial(flipped)
            let plain = try XCTUnwrap(mirrored.placed)
            mirrored.semanticContentAttribute = .forceRightToLeft
            mirrored.setNeedsLayout()
            flipped.settle()
            XCTAssertNotEqual(mirrored.placed?.lit, plain.lit, "a dial that mirrors flips")

            let sun = try F.show("arc-track-minimal", width: width)
            defer { sun.window.isHidden = true }
            let track = try arc(sun)
            let marker = try XCTUnwrap(ServerUIArcLayout.layoutArc(try XCTUnwrap(track.arc).layoutInput(width: Double(track.bounds.width), value: 0.5, rtl: false)).marker)
            track.semanticContentAttribute = .forceRightToLeft
            track.setNeedsDisplay()
            sun.settle()
            XCTAssertEqual(try XCTUnwrap(track.placed?.marker).x, marker.x, accuracy: 0.01, "a half marker is in the middle both ways")

            let off = try F.show("arc-track-mirrors-off", width: width)
            defer { off.window.isHidden = true }
            XCTAssertEqual(try arc(off).arc?.mirrors, false)
            let stays = try arc(off)
            stays.semanticContentAttribute = .forceRightToLeft
            stays.setNeedsDisplay()
            off.settle()
            XCTAssertEqual(stays.drawnOrigin, 0, accuracy: 0.01, "an arc that does not mirror keeps its left-to-right place (width \(width))")
            XCTAssertGreaterThan(track.drawnOrigin, 0, "one that mirrors stands at the right of a room wider than it")
        }
    }

    // MARK: Arc

    /// The arc is as wide as the room up to its cap, as tall as its box's shape, with the marker where the shared arithmetic puts it.
    func testAnArcIsCappedAtItsMaxWidthAndPlacesItsMarkerByTheSharedArithmetic() throws {
        for width in Self.widths {
            let shown = try F.show("arc-track-minimal", width: width)
            defer { shown.window.isHidden = true }
            let view = try arc(shown)
            view.setNeedsDisplay()
            shown.settle()
            let layout = try XCTUnwrap(view.placed)
            XCTAssertEqual(CGFloat(layout.width), min(view.bounds.width, 200), accuracy: 0.01, "capped at 200 points (width \(width))")
            XCTAssertEqual(CGFloat(layout.height), CGFloat(layout.width) * 0.48, accuracy: 0.01, "100 : 48")
            XCTAssertEqual(view.gridHeight(forWidth: view.bounds.width), CGFloat(layout.height), accuracy: 0.01)
            let marker = try XCTUnwrap(layout.marker)
            XCTAssertEqual(marker.t, 0.5)
            XCTAssertEqual(marker.x, layout.width / 2, accuracy: 0.01, "the middle of the curve")
        }
    }

    /// The marker follows the entity in place; no progress hides it; the arc does not glide.
    func testTheMarkerFollowsItsEntityInPlace() throws {
        for width in Self.widths {
            let shown = try F.show("arc-track-progress-bound", width: width, entities: [Self.entity("0.25")])
            defer { shown.window.isHidden = true }
            let view = try arc(shown)
            view.setNeedsDisplay()
            shown.settle()
            XCTAssertEqual(try XCTUnwrap(view.placed?.marker).t, 0.25, accuracy: 0.0001, "width \(width)")
            let draws = view.drawCount
            shown.store.apply([Self.entity("1")])
            HostedPage.until { view.drawCount > draws }
            view.setNeedsDisplay()
            shown.settle()
            XCTAssertEqual(view.drawCount, draws + 1, "one entity change is one update")
            XCTAssertEqual(try XCTUnwrap(view.placed?.marker).t, 1, accuracy: 0.0001)
            XCTAssertTrue(shown.page.nodes["a"]?.view === view, "the view stays")
            shown.store.apply([Self.entity("unavailable")])
            HostedPage.until { view.progress == nil }
            view.setNeedsDisplay()
            shown.settle()
            XCTAssertNil(view.placed?.marker, "no progress, no marker")
        }
    }

    // MARK: VoiceOver

    /// A dial or an arc that is named is one element whose value is its text or the percent; one that is not is hidden.
    func testANamedDialAndArcAreOneElementAndAnUnnamedOneIsHidden() throws {
        for width in Self.widths {
            let named = try F.show("dial-a11y-value", width: width)
            defer { named.window.isHidden = true }
            let view = try dial(named)
            XCTAssertTrue(view.isAccessibilityElement, "width \(width)")
            XCTAssertEqual(view.accessibilityLabel, "Level")
            XCTAssertEqual(view.accessibilityValue, "Steady")
            XCTAssertTrue(view.centerLines.allSatisfy { !$0.isAccessibilityElement })
            XCTAssertTrue(view.letterLabels.allSatisfy { !$0.isAccessibilityElement }, "letters are not read apart")

            let arcNamed = try F.show("arc-track-a11y-value", width: width)
            defer { arcNamed.window.isHidden = true }
            XCTAssertTrue(try arc(arcNamed).isAccessibilityElement)
            XCTAssertEqual(try arc(arcNamed).accessibilityLabel, "Progress")
            XCTAssertEqual(try arc(arcNamed).accessibilityValue, "Halfway")

            let silent = try F.show("dial-tick", width: width)
            defer { silent.window.isHidden = true }
            XCTAssertFalse(try dial(silent).isAccessibilityElement)
            let quiet = try F.show("arc-track-minimal", width: width)
            defer { quiet.window.isHidden = true }
            XCTAssertFalse(try arc(quiet).isAccessibilityElement)
        }
    }

    /// With no words of its own a named dial and arc speak the percent of the sweep and of the curve.
    func testANamedMeterWithNoValueSpeaksItsPercent() throws {
        for width in Self.widths {
            let shown = try F.show("dial-a11y-value", width: width) { F.setting(["value"], to: .null, in: $0, under: "a11y") }
            defer { shown.window.isHidden = true }
            XCTAssertEqual(try dial(shown).accessibilityValue, "50%", "width \(width)")
            let sun = try F.show("arc-track-a11y-value", width: width) { F.setting(["value"], to: .null, in: $0, under: "a11y") }
            defer { sun.window.isHidden = true }
            XCTAssertEqual(try arc(sun).accessibilityValue, "50%")
        }
    }
}
