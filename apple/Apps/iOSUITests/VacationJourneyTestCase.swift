import XCTest

/// The base of the Vacation journeys: the gallery launch (`FENTON_GALLERY=vacation`, a fixture house that echoes like Home Assistant, so
/// nothing reaches the real house), the page opener, and the call, value, reveal and tap helpers. The old single `VacationJourneyTests`
/// class was split by area (`contracts/test-map.json`) so a change to one area runs only its journeys; nothing here is specific to one
/// area. Launches go through `FentonHomeApp.makeApp()` and `launch()`, which reuses one running app per class (`startApp`).
/// iPhone, iPhone Duo and iPad (`.agents/pages/vacation/`).
@MainActor
class VacationJourneyTestCase: JourneyTestCase {
    /// A page of the feature, reached the way a person would.
    enum Page: String, CaseIterable {
        case chooser, vacationChecklist, vacationDates, confirmSheet, soloTripIdle, soloTripEditor, soloTripActive, soloTripRestore
    }

    // MARK: - Helpers

    func launch(_ scenario: String = "idle", clean: Bool = false, arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "vacation"
        app.launchEnvironment["FENTON_GALLERY_AWAY"] = scenario
        if clean { app.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1" }
        app.launchArguments += arguments
        // App reuse (`.agents/testing/apple/app-reuse.md`): the scenario and `clean` are `FENTON_GALLERY_*` settings, which a reset
        // replaces, and the gallery builds its house, store and recorder per gallery (no statics, defaults or files), so no test
        // needs `fresh: true`. The AX5 tests pass a launch argument, which always launches fresh.
        return startApp(app)
    }

    /// Waits until the last recorded call contains `text`.
    func waitForCall(_ text: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let found = expectation(for: predicate, evaluatedWith: app.staticTexts["gallery.lastCall"])
        // Up to 10 s: turning Vacation Mode off sends seven calls one after another.
        if XCTWaiter().wait(for: [found], timeout: 10) != .completed {
            XCTFail("Expected a call containing \(text); last: \(lastCall(in: app))", file: file, line: line)
        }
    }

    /// Waits until `element`'s accessibility value is `value` (an empty string also matches no value).
    func waitForValue(_ value: String, of element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if (element.value as? String ?? "") == value { return true }
            usleep(200_000)
        } while Date() < deadline
        return false
    }

    /// Scrolls the page until `target` can be tapped.
    @discardableResult
    func reveal(_ target: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        // Toward the target, until it sits inside the content area: at AX5 a control can sit above the screen
        // after an earlier reveal, and a partly visible one is "hittable" while its center is under the
        // status bar (the tap then scrolls to the top instead).
        let window = app.windows.firstMatch.frame
        let content = CGRect(x: window.minX, y: window.minY + 90, width: window.width, height: window.height - 120)
        // One snapshot answers "in the tree" and "where"; `isHittable` is asked only once the frame is in the content area.
        func inView() -> Bool {
            guard let frame = (try? target.snapshot())?.frame, !frame.isEmpty else { return false }
            let fits = frame.height > content.height ? content.contains(CGPoint(x: frame.midX, y: frame.midY))
                : content.contains(frame)
            return fits && target.isHittable
        }
        for _ in 0..<8 where !inView() {
            if let frame = (try? target.snapshot())?.frame, !frame.isEmpty, frame.midY < content.midY { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(target.isHittable, "\(target) never came into view")
        return target
    }

    func tap(_ id: String, in app: XCUIApplication) {
        let target = element(id, in: app)
        // A List only exposes rows it has laid out: at AX5 on the folded iPhone Duo the second chooser row
        // starts below the screen.
        if !target.appears(timeout: 10) {
            for _ in 0..<6 where !target.exists { app.swipeUp() }
        }
        XCTAssertTrue(target.exists, "\(id) not found")
        reveal(target, in: app).tap()
    }

    func assertTarget(_ id: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(id, in: app)
        XCTAssertTrue(target.appears(timeout: 10), "\(id) not found", file: file, line: line)
        let height = (try? target.snapshot())?.frame.height ?? target.frame.height
        XCTAssertGreaterThanOrEqual(height, 43, "\(id) is shorter than 44 pt", file: file, line: line)
    }

    /// Launches and navigates to `page`.
    @discardableResult
    func open(_ page: Page, clean: Bool = false, arguments: [String] = []) -> XCUIApplication {
        switch page {
        case .chooser:
            let app = launch(clean: clean, arguments: arguments)
            XCTAssertTrue(element("vacation.chooser.vacationMode", in: app).appears(timeout: 15))
            return app
        case .vacationChecklist:
            let app = launch(clean: clean, arguments: arguments)
            tap("vacation.chooser.vacationMode", in: app)
            XCTAssertTrue(element("vacation.checklist.0", in: app).appears(timeout: 5))
            return app
        case .vacationDates:
            let app = launch("vacation", clean: clean, arguments: arguments)
            XCTAssertTrue(element("vacation.dates.start", in: app).appears(timeout: 15))
            return app
        case .confirmSheet:
            let app = launch("ready", clean: clean, arguments: arguments)
            tap("vacation.chooser.vacationMode", in: app)
            tap("vacation.modeCard", in: app)
            XCTAssertTrue(element("vacation.confirm.action", in: app).appears(timeout: 5))
            settleScreen() // Let the sheet finish presenting.
            return app
        case .soloTripIdle:
            let app = launch(clean: clean, arguments: arguments)
            tap("vacation.chooser.soloTrip", in: app)
            XCTAssertTrue(element("soloTrip.toggle", in: app).appears(timeout: 5))
            // The push is still running: the chooser's list is in the tree until it ends, and a page that audits by swiping the first
            // scroller would swipe a list that is about to leave it.
            settleScreen()
            return app
        case .soloTripEditor:
            let app = open(.soloTripIdle, clean: clean, arguments: arguments)
            tap("soloTrip.traveler.resident_1", in: app)
            tap("soloTrip.toggle", in: app)
            XCTAssertTrue(element("soloTrip.editor.confirm", in: app).appears(timeout: 5))
            settleScreen()
            return app
        case .soloTripActive:
            let app = launch("solo-active", clean: clean, arguments: arguments)
            XCTAssertTrue(element("soloTrip.toggle", in: app).appears(timeout: 15))
            return app
        case .soloTripRestore:
            let app = launch("solo-restore", clean: clean, arguments: arguments)
            XCTAssertTrue(element("soloTrip.status.keepCurrent", in: app).appears(timeout: 15))
            return app
        }
    }

    /// Taps the middle of `element`'s frame through the app, without resolving the element again.
    func tapCenter(of element: XCUIElement, in app: XCUIApplication) {
        let frame = element.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
    }

    // MARK: - Audits

    /// Audits `page` without the gallery's debug line, which is not product UI (behind an iPad form sheet it
    /// is dimmed by the modal).
    func audit(_ page: Page) throws {
        let app = open(page, clean: true)
        let presenter: XCUIElement? = switch page {
        case .confirmSheet: element("vacation.modeCard", in: app)
        case .soloTripEditor: element("soloTrip.toggle", in: app)
        default: nil
        }
        try FentonHomeApp.audit(app, ax5Page: { self.open(page, clean: true, arguments: FentonHomeApp.ax5) }, presenter: presenter)
    }
}
