import XCTest

/// The base of the Climate journeys: the `climate` gallery launch (fixture state, recording service caller; nothing reaches the house) through
/// `startApp`, so every area class is on app reuse (`.agents/testing/apple/app-reuse.md`), the sheet's own scroll-to-reveal, the recorded-call
/// check, heading, back and menu helpers and the per-screen accessibility audit. The old single `ClimateJourneyTests` class was split by area
/// (`contracts/test-map.json`) so a change to one source file runs only its journeys; nothing here is specific to one area. iPhone, iPhone Duo
/// and iPad (`.agents/pages/climate/`).
@MainActor
class ClimateJourneyTestCase: JourneyTestCase {
    // Only the iPad journeys rotate; leave a Duo pose set in Device Hub alone.

    /// Launches the Climate gallery, optionally on the away fixture or with the sheet open on `open`.
    func launch(open: String? = nil, scenario: String? = nil, clean: Bool = false, arguments: [String] = []) -> XCUIApplication {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "climate"
        if let open { configured.launchEnvironment["FENTON_GALLERY_CLIMATE_OPEN"] = open }
        if let scenario { configured.launchEnvironment["FENTON_GALLERY_CLIMATE_SCENARIO"] = scenario }
        if clean { configured.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1" }
        configured.launchArguments += arguments
        let app = startApp(configured)
        let ready = open == nil ? element("climate.wholeHome", in: app) : app.buttons["Close"]
        XCTAssertTrue(ready.appears(timeout: 15), "Climate did not appear")
        return app
    }

    /// Scrolls the frontmost scroll view until `element` is fully on screen, through the shared
    /// ``JourneyTestCase/scrollTo(_:in:scroller:deadline:isClear:gesture:file:line:)`` with this page's own scroll view lookup.
    @discardableResult
    func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let window = app.windows.firstMatch
        // Scroll inside the sheet when one is up: an iPad sheet doesn't cover the window, and a drag on the
        // dimmed area outside it scrolls nothing.
        // Sheet pages are forms (collection views); the page is a scroll view.
        func area() -> XCUIElement {
            let named = NSPredicate(format: "identifier BEGINSWITH 'climate.sheet.' OR identifier == 'climate.detail'")
            let sheets = app.descendants(matching: .any).matching(NSPredicate(format: "elementType IN %@",
                [XCUIElement.ElementType.scrollView, .collectionView, .table].map(\.rawValue))).matching(named)
            // The one holding the element: after Back the popped detail's scroll view can linger in the tree.
            let candidates = sheets.allElementsBoundByIndex
            let holder = element.exists
                ? candidates.first { $0.descendants(matching: .any)[element.identifier].exists }
                : nil
            return holder ?? candidates.last { isReachable($0) } ?? window
        }
        // The scroll area does not change size while one reveal runs, so its frame is read once (lazily) and again after each drag
        // (a pushed page can swap the area), not on every clear check: each `area()` is a tree query over the whole sheet.
        var areaFrame: CGRect?
        // A row at the page's scroll limit can sit outside the clear band (the first row under a short bar, an AX5 entry taller
        // than the sheet) yet be fully usable: main accepted it by hittability once the page stopped moving. So an element that is
        // hittable with its centre inside the sheet, and did not move under a drag, counts as clear.
        var drags = 0, lastDrags = 0
        var lastFrame = CGRect.null
        scrollTo(element, in: app, isClear: { element in
            // Clear of the bars: navigation bar and the gallery's last-call line at the top, home indicator below.
            let frame = areaFrame ?? area().frame
            areaFrame = frame
            // One snapshot for the element's frame instead of a live frame read per comparison.
            guard let elementFrame = (try? element.snapshot())?.frame else { return false }
            let top = frame.minY + Swift.min(frame.height * 0.18, 160)
            let bottom = frame.maxY - frame.height * 0.08
            if elementFrame.maxY <= bottom && elementFrame.minY >= top { return true }
            // An element over half the sheet's height (an AX5 entry) rarely lands inside the band between fixed-size drags: the centre being on the sheet is enough.
            let inSheet = frame.contains(CGPoint(x: elementFrame.midX, y: elementFrame.midY))
            if elementFrame.height > frame.height * 0.5 && inSheet { return true }
            let atLimit = drags > lastDrags && abs(elementFrame.midY - lastFrame.midY) < 3 && inSheet
            lastFrame = elementFrame
            lastDrags = drags
            return atLimit
        }, gesture: { element, above in
            drags += 1
            let area = area()
            let frame = area.frame
            areaFrame = frame
            // Slow drag with a hold so the scroll doesn't coast: a tap during momentum only stops the scroll.
            // A row that is not in the tree yet is searched for downwards first, then upwards: a lazy Form drops the rows
            // that scrolled away, so on the folded Duo's short screen the row can be above the end the page was left at
            // (Predictive Comfort While Away, above the reasons; 2026-10-17).
            let start = area.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: above ? 0.35 : 0.7))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: (above ? 1 : -1) * frame.height * 0.2)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
        }, file: file, line: line)
        return element
    }

    func lastCall(_ app: XCUIApplication) -> String { app.staticTexts["gallery.lastCall"].firstMatch.label }

    func waitForCall(_ prefix: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let matches = NSPredicate(format: "label BEGINSWITH %@", "Last call: \(prefix)")
        let found = XCTNSPredicateExpectation(predicate: matches, object: label)
        XCTAssertEqual(XCTWaiter().wait(for: [found], timeout: 4), .completed, "Last call was '\(label.label)'", file: file, line: line)
    }

    /// The sheet page's navigation bar titled `title`.
    func heading(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.navigationBars[title]
    }

    /// The Thermostat Hub row's text: "Thermostat Hub, <state>" (its mode menu is a separate element).
    func hubRow(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Thermostat Hub, '")).firstMatch
    }

    /// Flips a system switch in a form row: XCUITest's tap on the row's centre misses the switch.
    func flip(_ toggle: XCUIElement) {
        let inner = toggle.switches.firstMatch
        if isReachable(inner) { inner.tap() } else { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
    }

    /// A section header (grouped forms may draw it in capitals).
    func header(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", title)).firstMatch
    }

    func value(_ element: XCUIElement) -> String { element.value as? String ?? "" }

    /// Waits up to 10 s for `element`'s accessibility value to become `expected` (the gallery echoes a toggle after a
    /// short delay, and 3 s was not enough on a loaded host: iPad Tracking, 2026-10-17).
    /// Whether the element gains the selected trait (a checklist row that is on).
    func isSelected(_ element: XCUIElement) -> Bool {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: element)
        return XCTWaiter().wait(for: [match], timeout: 10) == .completed
    }

    func hasValue(_ element: XCUIElement, _ expected: String) -> Bool {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: element)
        return XCTWaiter().wait(for: [match], timeout: 10) == .completed
    }

    /// Back to the parent page, confirmed by its heading (`parent`, default the sheet's root title). Tries the
    /// `BackButton` (folded Duo rail, iPad), then the bar button that isn't Close.
    func back(_ app: XCUIApplication, to parent: String = "Advanced Controls",
                      file: StaticString = #filePath, line: UInt = #line) {
        var candidates: [XCUIElement] = [app.buttons["BackButton"]]
        candidates += app.navigationBars.buttons.allElementsBoundByIndex.filter { $0.label != "Close" }
        for button in candidates where isReachable(button) {
            button.tap()
            // Hittable, not just present: the root page stays in the tree under a pushed detail.
            let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: heading(parent, in: app))
            if XCTWaiter().wait(for: [shown], timeout: 4) == .completed { return }
        }
        XCTFail("Back did not return to \(parent)", file: file, line: line)
    }

    /// A choice in the hub's dropdown menu (the system menu's item button).
    func menuItem(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.collectionViews.buttons[title].exists ? app.collectionViews.buttons[title] : app.buttons[title].firstMatch
    }

    // MARK: - Accessibility audit

    func audit(open: String? = nil, scenario: String? = nil, prepare: ((XCUIApplication) -> Void)? = nil) throws {
        // Clean: the gallery's debug line is not part of the product and covers content under it.
        let app = launch(open: open, scenario: scenario, clean: true)
        prepare?(app)
        try FentonHomeApp.audit(app) {
            let large = self.launch(open: open, scenario: scenario, clean: true, arguments: FentonHomeApp.ax5)
            prepare?(large)
            settleScreen()
            return large
        }
    }
}
