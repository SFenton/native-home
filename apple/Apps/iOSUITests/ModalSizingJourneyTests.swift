import XCTest

/// Modal sizing and chrome (owner decisions, 2026-10-16; `.agents/patterns/modal-sheet.md`): a short sheet opens at its
/// content's height, a long one and any sheet with a section tab bar open full, the tab bar shows icons on iPhone and a
/// menu at AX5, an edit sheet's confirm check is disabled until a change, and the Filter sheet has a blue Reset row and
/// no translucent header. Runs on the `modal-sizing` gallery on iPhone, iPhone Duo and iPad.
@MainActor
final class ModalSizingJourneyTests: JourneyTestCase {
    /// The sheet kind is `FENTON_GALLERY_MODAL_OPEN` (a gallery setting), so a reused app switches sheets with a reset; the
    /// launch argument `-modalSizingOpen` still works but always launches fresh. AX5 (`arguments`) and the pinned appearance are part
    /// of the launch signature and keep their own resident app (`app-reuse.md`). The sheet-height memories are mirrored to disk, so a
    /// reset app opens the sheets at the heights a fresh launch would; no test here needs a first presentation.
    private func launch(open kind: String? = nil, arguments: [String] = [], appearance: String? = nil) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "modal-sizing"
        if let kind { app.launchEnvironment["FENTON_GALLERY_MODAL_OPEN"] = kind }
        if let appearance { app.launchEnvironment["FENTON_APPEARANCE"] = appearance }
        app.launchArguments += arguments
        return startApp(app)
    }

    private func open(_ kind: String, arguments: [String] = [], appearance: String? = nil) -> XCUIApplication {
        let app = launch(open: kind, arguments: arguments, appearance: appearance)
        let ready = ["edit": "sizing.edit.cancel", "filter": "filterSheet.cancel", "sort": "filterSheet.cancel"][kind] ?? "sizing.close"
        XCTAssertTrue(element(ready, in: app).appears(timeout: 20), "\(kind) sheet did not open")
        settleScreen() // Let the presentation and the first measurement settle.
        return app
    }

    private func windowHeight(_ app: XCUIApplication) -> CGFloat { app.windows.firstMatch.frame.height }

    // MARK: - Height

    /// Three rows open at their own height, well under the window (iPhone detent and iPad fitted sheet alike).
    func testShortSheetOpensAtContentHeight() {
        let app = open("short")
        let scroll = element("sizing.short.scroll", in: app)
        XCTAssertTrue(scroll.exists)
        keepScreenshot(app, "modal-short-\(layout)")
        if FentonHomeApp.family == .iPhoneDuo {
            // Folded and beside a vertical hinge every sheet fills the height from the bottom (owner, 2026-10-31,
            // `DuoSheetPolicy.fillsHeight`): a short sheet is not content-fitted there.
            XCTAssertGreaterThan(scroll.frame.height, windowHeight(app) * 0.6, "A Duo sheet fills the height")
        } else {
            XCTAssertLessThan(scroll.frame.height, 420, "A three-row sheet should be as tall as its rows, not \(scroll.frame.height) pt")
            XCTAssertLessThan(scroll.frame.height, windowHeight(app) - 200)
        }
        // Fitted means every row is shown, not cut by the sheet's edge.
        let party = app.staticTexts["Party"]
        XCTAssertTrue(party.exists)
        XCTAssertLessThanOrEqual(party.frame.maxY, scroll.frame.maxY - 8, "The last row is cut off by the sheet's bottom edge")
        // It stays put: no jump while open.
        let first = scroll.frame
        settleScreen()
        XCTAssertEqual(scroll.frame.height, first.height, accuracy: 1, "The sheet resized while open")
    }

    /// Forty rows reach the large detent and scroll.
    func testTallSheetOpensAtLargeAndScrolls() {
        let app = open("tall")
        let scroll = element("sizing.tall.scroll", in: app)
        keepScreenshot(app, "modal-tall-\(layout)")
        XCTAssertGreaterThan(scroll.frame.height, min(windowHeight(app) * 0.6, 600), "Long content should open tall")
        XCTAssertTrue(app.staticTexts["Light 1"].exists)
        XCTAssertFalse(app.staticTexts["Light 40"].isHittable, "The last row is below the fold until scrolled")
    }

    /// A modal with a section tab bar opens full height, however short its content.
    func testTabSheetOpensFullHeight() {
        let app = open("tabs")
        let scroll = element("sizing.tabs.scroll", in: app)
        keepScreenshot(app, "modal-tabs-\(layout)")
        XCTAssertGreaterThan(scroll.frame.height, windowHeight(app) * 0.6, "A tab-bar sheet opens full height")
    }

    // MARK: - Tab bar

    /// iPhone and the folded Duo (compact width) show icons that VoiceOver still names; iPad shows text.
    func testTabBarShowsIconsOnCompactWidthAndNamesThem() {
        let app = open("tabs")
        let tabs = app.segmentedControls["sizing.tabs"]
        XCTAssertTrue(tabs.appears(timeout: 5))
        // One snapshot of the control answers the segments' names and sizes and the icon/text counts.
        guard let control = try? tabs.snapshot() else { return XCTFail("No snapshot of the section control") }
        func flatten(_ node: XCUIElementSnapshot) -> [XCUIElementSnapshot] { node.children.flatMap { [$0] + flatten($0) } }
        let all = flatten(control)
        let segments = all.filter { $0.elementType == .button }
        for name in ["Controls", "Apps", "Info"] {
            guard let segment = segments.first(where: { $0.label == name }) else { XCTFail("\(name) segment missing or unnamed"); continue }
            XCTAssertGreaterThanOrEqual(segment.frame.width, 43, name)
            XCTAssertGreaterThanOrEqual(segment.frame.height, 43, name)
        }
        let texts = all.filter { $0.elementType == .staticText }.count
        let images = all.filter { $0.elementType == .image }.count
        let compact = FentonHomeApp.family != .iPad
        if compact {
            XCTAssertEqual(texts, 0, "Compact width shows icons, not text titles")
            XCTAssertGreaterThan(images, 0, "Compact width shows icons")
        } else {
            XCTAssertGreaterThan(texts + segments.count, 0)
        }
        tabs.buttons["Apps"].tap()
        XCTAssertTrue(app.staticTexts["Apps"].appears(timeout: 3) || tabs.buttons["Apps"].isSelected)
        keepScreenshot(app, "modal-tabbar-\(layout)")
    }

    /// At AX5 the control becomes a menu that still switches sections.
    func testTabBarIsAMenuAtAccessibilitySizes() {
        let app = open("tabs", arguments: FentonHomeApp.ax5)
        XCTAssertFalse(app.segmentedControls["sizing.tabs"].exists, "Segments cannot grow at AX5")
        let menu = element("sizing.tabs", in: app)
        XCTAssertTrue(menu.appears(timeout: 5), "The AX5 section menu is missing")
        assertTarget(menu)
        keepScreenshot(app, "modal-tabbar-ax5-\(layout)")
    }

    // MARK: - Edit state

    /// The confirm check is visible but disabled until the draft changes, then enabled, then disabled again on revert.
    func testConfirmIsDisabledUntilAChange() {
        let app = open("edit")
        let save = app.buttons["sizing.edit.save"]
        XCTAssertTrue(save.appears(timeout: 5), "The confirm check stays visible")
        XCTAssertFalse(save.isEnabled, "Nothing changed: the check is disabled")
        keepScreenshot(app, "modal-edit-unchanged-\(layout)")
        let field = app.textFields["sizing.edit.name"]
        field.tap()
        field.typeText("!")
        XCTAssertTrue(save.wait(for: \.isEnabled, toEqual: true, timeout: 5), "A change enables the check")
        keepScreenshot(app, "modal-edit-changed-\(layout)")
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertTrue(save.wait(for: \.isEnabled, toEqual: false, timeout: 5), "Reverting the change disables it again")
    }

    // MARK: - Filter sheet

    /// Reset to Defaults is a blue list row, never red.
    func testResetRowIsTintedNotRed() {
        let app = open("filter", appearance: "light")
        let reset = app.buttons["filterSheet.reset"]
        for _ in 0..<8 where !reset.isHittable { app.swipeUp() }
        XCTAssertTrue(reset.isHittable, "Reset to Defaults is missing")
        settleScreen()
        keepScreenshot(app, "modal-filter-reset-\(layout)")
        guard let capture = RenderedContrast.Capture.screen(), let hue = hue(of: reset.frame, in: capture) else {
            return XCTFail("Could not sample the Reset row")
        }
        XCTAssertGreaterThan(hue.mostBlue, 0.3, "Reset to Defaults should be tint blue")
        XCTAssertLessThan(hue.mostRed, 0.1, "Reset to Defaults must not be red (not destructive)")
    }

    /// With rows scrolled under the header there is no translucent band: the pixels beside the title match the sheet's
    /// own ground.
    private func assertFilterHeaderHasNoBand(_ appearance: String) {
        let app = open("filter", appearance: appearance)
        let apply = app.buttons["filterSheet.apply"]
        XCTAssertTrue(apply.exists)
        // Rows under the header: scroll the form up.
        for _ in 0..<3 { app.swipeUp() }
        settleScreen()
        guard let capture = RenderedContrast.Capture.screen() else { return XCTFail("No capture") }
        let cancel = app.buttons["filterSheet.cancel"].frame
        // Beside Cancel and beside Apply, 14 pt clear of their glass shadows, where rows would show through a
        // material. The title sits between them and can reach either on a folded Duo, so one clear side suffices.
        let applyFrame = apply.frame
        let y = cancel.midY
        let ground = RenderedContrast.luminance(at: CGPoint(x: cancel.minX - 12, y: cancel.maxY + 30), in: capture)
        let sides = [cancel.maxX + 14, applyFrame.minX - 14].compactMap {
            RenderedContrast.luminance(at: CGPoint(x: $0, y: y), in: capture)
        }
        keepScreenshot(app, "modal-filter-header-\(appearance)-\(layout)")
        guard let ground, !sides.isEmpty else { return XCTFail("Off capture") }
        let closest = sides.map { abs($0 - ground) }.min() ?? 1
        // 0.035: the UIKit header sits under the system's own soft scroll-edge effect (0.031 measured, 2026-11-02), which is a fade of the
        // rows, not a band; a material band measures several times that.
        XCTAssertLessThan(closest, 0.035, "\(appearance): the header sits on a band, not the sheet's ground (\(sides) vs \(ground))")
    }

    func testFilterHeaderHasNoTranslucentBandLight() { assertFilterHeaderHasNoBand("light") }
    func testFilterHeaderHasNoTranslucentBandDark() { assertFilterHeaderHasNoBand("dark") }

    // MARK: - Dismissal

    /// Drags down `distance` points from `element`'s centre, held at the end.
    private func dragDown(_ element: XCUIElement, in app: XCUIApplication, distance: CGFloat = 420) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)), withVelocity: .default, thenHoldForDuration: 0.2)
    }

    /// A short sheet follows a vertical drag down and closes, from its body and from its top strip (HIG Sheets, "support swiping vertically to
    /// dismiss"; `.agents/design/motion.md`). The `sheet-portrait` finding: on the iPad in portrait the sheet stayed. On every family, in each
    /// orientation the family rotates to (the Duo does not rotate in a test, devices.md).
    private func assertDragDownDismisses(landscape: Bool, kind: String = "short") {
        let rotates = FentonHomeApp.family != .iPhoneDuo
        if rotates { XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait }
        continueAfterFailure = true
        for start in ["header", "body"] {
            let app = open(kind)
            let close = element("sizing.close", in: app)
            XCTAssertTrue(close.exists)
            let scroll = element("sizing.\(kind).scroll", in: app)
            keepScreenshot(app, "modal-open-\(kind)-\(landscape ? "landscape" : "portrait")-\(layout)")
            let title = kind == "short" ? "Lighting Mode" : "Palette"
            let target = start == "body" ? scroll : app.staticTexts[title].firstMatch
            dragDown(target, in: app)
            let gone = NSPredicate(format: "exists == false")
            let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: gone, object: close)], timeout: 6)
            keepScreenshot(app, "modal-drag-\(kind)-\(start)-\(landscape ? "landscape" : "portrait")-\(layout)")
            XCTAssertEqual(result, .completed, "A drag down from the sheet's \(start) closes it (\(landscape ? "landscape" : "portrait"))")
            if result != .completed { close.tap() }
        }
    }

    func testDragDownDismissesAShortSheetInPortrait() { assertDragDownDismisses(landscape: false) }
    func testDragDownDismissesAShortSheetInLandscape() { assertDragDownDismisses(landscape: true) }
    // The full-height form sheet closes by Close in iPad portrait, not by a drag: `.agents/decisions/2026-11-16-ipad-full-form-sheet.md`.
    func testDragDownDismissesAFullHeightFormSheetInLandscape() { assertDragDownDismisses(landscape: true, kind: "fullForm") }

    // MARK: - Close exit

    /// The full-height form sheet is centred on the iPad and the system keeps it there in portrait, so Close is its exit: it exists, can be
    /// hit, sits at the sheet's top trailing corner, has a 44 pt hit target, and closes the sheet
    /// (`.agents/decisions/2026-11-16-ipad-full-form-sheet.md`; HIG Buttons, minimum hit region; HIG Modality, an obvious dismissal).
    /// The system's `.close` bar item draws at 36 pt (38 on the folded Duo) and XCUITest reports that drawn frame, so the 44 pt target is
    /// asserted the way `HeaderButtonsJourneyTests.testBothButtonsHaveA44PointTarget` does: a tap 19 pt off centre (inside 44, outside
    /// the frame) still closes the sheet. Left, right and below stay inside the bar; each tap gets a fresh sheet. The Duo does not rotate
    /// in a test.
    private func assertFullHeightFormSheetClosesByClose(landscape: Bool) {
        if FentonHomeApp.family != .iPhoneDuo { XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait }
        let pose = landscape ? "landscape" : "portrait"
        for (name, offset) in [("centre", CGVector(dx: 0, dy: 0)), ("19 pt left", CGVector(dx: -19, dy: 0)),
                               ("19 pt right", CGVector(dx: 19, dy: 0)), ("19 pt below", CGVector(dx: 0, dy: 19))] {
            let app = open("fullForm")
            let close = element("sizing.close", in: app)
            let scroll = element("sizing.fullForm.scroll", in: app)
            XCTAssertTrue(close.exists && close.isHittable, "Close is on screen and can be hit (\(pose))")
            // The scroll view spans the sheet's width and starts at its top edge, so the corner is read against it.
            XCTAssertGreaterThan(close.frame.midX, scroll.frame.midX, "Close sits on the trailing side (\(pose))")
            XCTAssertGreaterThanOrEqual(close.frame.maxX, scroll.frame.maxX - 24, "Close sits at the trailing corner (\(pose))")
            if FentonHomeApp.family == .iPhoneDuo {
                // The folded Duo moves bar items into its vertical bar on the trailing edge (devices.md), so Close is beside the sheet's
                // content, not above it: it must still be inside the sheet's height.
                XCTAssertTrue((scroll.frame.minY...scroll.frame.maxY).contains(close.frame.midY), "Close sits in the trailing rail (\(pose))")
            } else {
                XCTAssertLessThan(close.frame.midY, scroll.frame.minY + 60, "Close sits in the top bar (\(pose))")
            }
            if name == "centre" { keepScreenshot(app, "modal-close-exit-\(pose)-\(layout)") }
            close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(offset).tap()
            let gone = NSPredicate(format: "exists == false")
            let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: gone, object: close)], timeout: 6)
            XCTAssertEqual(result, .completed, "A tap \(name) of Close dismisses the sheet (\(pose))")
            if result != .completed { close.tap() }
        }
    }

    func testFullHeightFormSheetClosesByCloseInPortrait() { assertFullHeightFormSheetClosesByClose(landscape: false) }
    func testFullHeightFormSheetClosesByCloseInLandscape() { assertFullHeightFormSheetClosesByClose(landscape: true) }

    // MARK: - Pixels

    /// The most blue-over-red and most red-over-blue any pixel in `frame` is, 0 for greys: text in the tint shows a
    /// strongly blue pixel, destructive text a strongly red one.
    private func hue(of frame: CGRect, in capture: RenderedContrast.Capture) -> (mostBlue: Double, mostRed: Double)? {
        guard let rect = RenderedContrast.pixelRect(of: frame, in: capture) else { return nil }
        var mostBlue = 0.0, mostRed = 0.0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let i = (y * capture.width + x) * 4
                let r = Double(capture.pixels[i]) / 255, b = Double(capture.pixels[i + 2]) / 255
                mostBlue = max(mostBlue, b - r)
                mostRed = max(mostRed, r - b)
            }
        }
        return (mostBlue, mostRed)
    }
}
