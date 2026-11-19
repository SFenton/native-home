@testable import HassCore
import HassDemoHouse
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - A kept height follows live changes and width changes

/// A fitting container keeps its height (``UKFitCache``). These tests prove the kept height never goes stale: a live change to the text
/// it draws (a failure caption, an info box message) and a new width each produce the height a freshly built twin measures.
///
/// Every case runs at the four family widths: iPhone 390, folded Duo 466, unfolded Duo 868 and iPad 744 points.
@MainActor
final class ServerUIFitLiveChangeHostedTests: DemoHouseTestCase {
    private typealias D = ServerUICompositionDocument
    private static let widths: [CGFloat] = [390, 466, 868, 744]

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Hosting

    /// Puts `holder` in a `UKColumnView` inset like a page, in a window `width` wide, and lays it out a few times.
    private func host(_ holder: UIView, width: CGFloat) -> (UKColumnView, UIWindow) {
        let controller = UIViewController()
        let column = UKColumnView(insets: UIEdgeInsets(top: 60, left: HassTokens.Spacing.l, bottom: 0, right: HassTokens.Spacing.l))
        column.setViews([holder])
        column.frame = CGRect(x: 0, y: 0, width: width, height: 800)
        controller.view.addSubview(column)
        let window = HostedPage.show(controller, size: CGSize(width: width, height: 800))
        settle(window)
        return (column, window)
    }

    private func settle(_ window: UIWindow) {
        for _ in 0..<3 { HostedPage.wait(0.05); window.layoutIfNeeded() }
    }

    private func inner(_ width: CGFloat) -> CGFloat { width - 2 * HassTokens.Spacing.l }

    // MARK: A control that turns failed

    private static let failure = "The lamp did not answer. Check that it is switched on and in range of the hub, then try again in a moment."

    /// A bound toggle row whose last call can fail.
    private struct Binding: UKServerUIControlBinding {
        var failed: Bool
        var subtitle = "On"
        var spec: UKServerUIControlSpec {
            UKServerUIControlSpec(title: "Desk lamp", identifier: "desk-lamp", face: .toggle, unavailableText: nil,
                                  row: .init(failureText: ServerUIFitLiveChangeHostedTests.failure, hasSubtitle: true))
        }
        func value() -> D.LocalValue? { .boolean(true) }
        func send(_ value: D.LocalValue) {}
        func rowDetails() -> UKServerUIRowDetails? { UKServerUIRowDetails(subtitle: subtitle, failed: failed) }
    }

    private func control(failed: Bool) -> UKServerUILocalControl {
        let control = UKServerUILocalControl()
        control.apply(Binding(failed: failed), surface: .page)
        return control
    }

    /// UX: a bound row turns failed, its caption appears, and the holder grows to the height of a row built failed.
    func testABoundRowThatTurnsFailedGrowsItsHolderAtEveryFamilyWidth() {
        for width in Self.widths {
            let live = control(failed: false)
            let (_, window) = host(live, width: width)
            defer { window.isHidden = true }
            let before = live.frame.height
            live.apply(Binding(failed: true), surface: .page)
            settle(window)
            let twin = control(failed: true).gridHeight(forWidth: inner(width))
            XCTAssertGreaterThan(live.frame.height, before + 8, "\(width): the caption added height")
            XCTAssertEqual(live.frame.height, twin, accuracy: 1, "\(width): the holder is as tall as a row built failed")
            live.apply(Binding(failed: false), surface: .page)
            settle(window)
            XCTAssertEqual(live.frame.height, before, accuracy: 1, "\(width): the caption leaving gives the height back")
        }
    }

    /// UX: a bound row's subtitle gets longer and wraps, and the holder grows to the height of a row built with the longer subtitle.
    func testABoundRowWithALongerSubtitleGrowsItsHolderAtEveryFamilyWidth() {
        let long = "Last changed from the hallway panel at ten past seven, when the whole floor went to its evening scene and the shutters closed"
        for width in Self.widths {
            let live = control(failed: false)
            let (_, window) = host(live, width: width)
            defer { window.isHidden = true }
            let before = live.frame.height
            live.apply(Binding(failed: false, subtitle: long), surface: .page)
            settle(window)
            let twin = UKServerUILocalControl()
            twin.apply(Binding(failed: false, subtitle: long), surface: .page)
            XCTAssertGreaterThan(live.frame.height, before + 8, "\(width): the longer subtitle added height")
            XCTAssertEqual(live.frame.height, twin.gridHeight(forWidth: inner(width)), accuracy: 1, "\(width): the holder holds the longer subtitle")
        }
    }

    /// A plain switch row (no parts) whose value cannot be read says why under its title.
    private struct Plain: UKServerUIControlBinding {
        var readable: Bool
        var spec: UKServerUIControlSpec {
            UKServerUIControlSpec(title: "Desk lamp", identifier: "desk-lamp", face: .toggle,
                                  unavailableText: "The lamp is not answering. Check that it is switched on and in range of the hub, that the hub itself is online, and that the lamp has not been unplugged at the wall or switched off at its own button. Then try again in a moment, or restart the hub if the lamp still does not answer.", row: nil)
        }
        func value() -> D.LocalValue? { readable ? .boolean(true) : nil }
        func send(_ value: D.LocalValue) {}
    }

    /// UX: a plain switch row turns unavailable, its words wrap under the title, and the holder grows to a twin's height.
    func testAPlainRowThatTurnsUnavailableGrowsItsHolderAtEveryFamilyWidth() {
        for width in Self.widths {
            let live = UKServerUILocalControl()
            live.apply(Plain(readable: true), surface: .page)
            let (_, window) = host(live, width: width)
            defer { window.isHidden = true }
            let before = live.frame.height
            live.apply(Plain(readable: false), surface: .page)
            settle(window)
            let twin = UKServerUILocalControl()
            twin.apply(Plain(readable: false), surface: .page)
            XCTAssertGreaterThan(live.frame.height, before + 8, "\(width): the words added height")
            XCTAssertEqual(live.frame.height, twin.gridHeight(forWidth: inner(width)), accuracy: 1, "\(width): the holder holds the words")
        }
    }

    // MARK: An info box with a longer message

    private func infoBox(_ message: String, bindings: UKServerUIBindings) -> UKServerUIInfoBox {
        let box = UKServerUIInfoBox()
        box.apply(D.InfoBox(node: .init(id: "notice", title: "Heads up", span: 1), message: .literal(message), tone: .neutral,
                            unavailableText: "Unavailable"), bindings: bindings, memories: UKServerUITextMemories())
        return box
    }

    /// UX: an info box message gets longer, and its column grows to the height of a box built with the longer message.
    func testAnInfoBoxWithALongerMessageGrowsItsColumnAtEveryFamilyWidth() {
        let bindings = UKServerUIBindings(sources: [], context: .sheetPlaceholder)
        let short = "Away mode is on."
        let long = "Away mode is on until Sunday. Lights, heating and the front door follow the away schedule, and the cameras record motion "
            + "in every room until you are home again."
        for width in Self.widths {
            let live = infoBox(short, bindings: bindings)
            let (_, window) = host(live, width: width)
            defer { window.isHidden = true }
            let before = live.frame.height
            live.apply(D.InfoBox(node: .init(id: "notice", title: "Heads up", span: 1), message: .literal(long), tone: .neutral,
                                 unavailableText: "Unavailable"), bindings: bindings, memories: UKServerUITextMemories())
            settle(window)
            let twin = infoBox(long, bindings: bindings).gridHeight(forWidth: inner(width))
            XCTAssertGreaterThan(live.frame.height, before + 8, "\(width): the longer message added height")
            XCTAssertEqual(live.frame.height, twin, accuracy: 1, "\(width): the column holds the longer message")
        }
    }

    // MARK: A width change

    /// A subtitle that wraps at the folded Duo width and not at the unfolded one.
    private static let subtitle = "Away dates, the checklist before you leave and who feeds the cat while the house is empty for a week"

    private func subtitleHolder() -> UKServerUIFittingView {
        let row = UKRowView(UKRowContent("Vacation", subtitle: Self.subtitle), accessory: UISwitch())
        return UKServerUIFittingView.wrapping(UKModuleListView(.thin, hasGlyphs: false, rows: [row]))
    }

    /// UX: a holder placed at one width and then given another keeps the height a new twin measures at that width, going 868, 466, 868.
    func testAPlacedHolderKeepsItsHeightWhenTheWidthChanges() throws {
        let holder = subtitleHolder()
        let (column, window) = host(holder, width: 868)
        defer { window.isHidden = true }
        var heights: [CGFloat: CGFloat] = [:]
        for width in [868, 466, 868] as [CGFloat] {
            column.frame.size.width = width
            settle(window)
            XCTAssertEqual(holder.frame.width, inner(width), accuracy: 0.5, "\(width): the holder has the new width")
            let twin = subtitleHolder().gridHeight(forWidth: inner(width))
            XCTAssertEqual(holder.frame.height, twin, accuracy: 1, "\(width): the holder is as tall as a twin measured at its width")
            XCTAssertEqual(holder.gridHeight(forWidth: inner(width)), twin, accuracy: 1, "\(width): and it measures the same asked directly")
            heights[width] = holder.frame.height
        }
        XCTAssertGreaterThan(try XCTUnwrap(heights[466]), try XCTUnwrap(heights[868]) + 8, "the subtitle wraps at 466 and not at 868")
    }

    /// UX: asking a placed holder for another width answers at that width and leaves it where it was.
    func testAskingAPlacedHolderForAnotherWidthAnswersAtThatWidth() {
        let holder = subtitleHolder()
        let (_, window) = host(holder, width: 868)
        defer { window.isHidden = true }
        let wide = holder.frame.height
        let narrow = holder.gridHeight(forWidth: inner(466))
        XCTAssertEqual(narrow, subtitleHolder().gridHeight(forWidth: inner(466)), accuracy: 1, "the answer is the height at 466")
        XCTAssertGreaterThan(narrow, wide + 8, "and it is taller than the wide one")
        XCTAssertEqual(holder.bounds.width, inner(868), accuracy: 0.5, "the holder keeps the width it was placed at")
    }

    // MARK: Bold Text

    /// UX: Bold Text is part of the kept height's key, so a change to it measures again.
    func testBoldTextMeasuresAgain() {
        let holder = subtitleHolder()
        let (_, window) = host(holder, width: 466)
        defer { window.isHidden = true }
        let fits = holder.fitCache.fits
        XCTAssertNotNil(holder.fitCache.height(forWidth: inner(466), category: holder.traitCollection.preferredContentSizeCategory,
                                               weight: holder.traitCollection.legibilityWeight))
        XCTAssertNil(holder.fitCache.height(forWidth: inner(466), category: holder.traitCollection.preferredContentSizeCategory, weight: .bold)
                     , "a height kept without Bold Text is not the height with it")
        XCTAssertGreaterThan(fits, 0)
    }
}
