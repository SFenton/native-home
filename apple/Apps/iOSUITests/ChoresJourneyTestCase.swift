import XCTest

/// The base of the Chores journeys: the gallery launch, the scrolling and swipe helpers, and the per-sheet accessibility audit every
/// area class shares. The old single `ChoresJourneyTests` class was split by area (`contracts/test-map.json`) so a change to one
/// area runs only its journeys; nothing here is specific to one area.
@MainActor
class ChoresJourneyTestCase: JourneyTestCase {
    // MARK: - Helpers

    /// The settings belong to the simulator: leave it as found.
    override func tearDown() {
        super.tearDown()
        let reduced = reducedMotion
        MainActor.assumeIsolated {
            if reduced { FentonHomeApp.launchGallery("system-accessibility").terminate() }
        }
    }

    var reducedMotion = false

    /// Drags a row part of the way left, which opens its trailing swipe actions without performing the full swipe. A quick drag
    /// is dropped now and then (iPad, 2026-10-29: the row bounced back with no actions), so a slow drag with a hold is repeated up to
    /// three times until the row's Delete action (`todo.swipe.delete.<id>`) is in the tree.
    func revealTrailingActions(of row: XCUIElement, id: String = "13--fixture", in app: XCUIApplication) {
        let delete = element("todo.swipe.delete.\(id)", in: app)
        for _ in 0..<3 where !delete.exists {
            let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            if delete.appears(timeout: 1.5) { return }
        }
    }

    /// Launches the `chores` gallery through ``JourneyTestCase/startApp(_:)``, so with reuse on each class keeps one resident app
    /// per launch signature (`.agents/testing/apple/app-reuse.md`). The gallery keeps no process state across a reset: its fixtures,
    /// service and model are built per gallery from the `FENTON_GALLERY*` variables.
    /// - Parameter fresh: Launches a new process instead of resetting the resident one. For a test that types into a text field: in a reset
    ///   app the page went blank when the keyboard came up, or the sheet's field never appeared (accessibility tree empty but for the
    ///   reset marker; passes in a fresh process; intermittent, cause not found, 2026-11-02).
    func launch(page: String? = nil, empty: Bool = false, arguments: [String] = [], environment: [String: String] = [:],
                fresh: Bool = false) -> XCUIApplication {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "chores"
        configured.launchEnvironment.merge(environment) { _, new in new }
        if let page { configured.launchEnvironment["FENTON_GALLERY_TODO_PAGE"] = page }
        if empty { configured.launchEnvironment["FENTON_GALLERY_EMPTY"] = "1" }
        configured.launchArguments += arguments
        let app: XCUIApplication
        if fresh {
            configured.launch()
            app = configured
        } else {
            app = startApp(configured)
        }
        XCTAssertTrue(app.buttons["fab.add"].appears(timeout: FentonHomeApp.launchWait()), "Add button missing")
        return app
    }

    /// Scrolls the page until `element` is hittable and clear of the floating Add bar and the gallery's
    /// last-call line (XCUITest calls an element under them hittable, but the tap lands on the overlay), through the shared
    /// ``JourneyTestCase/scrollTo(_:in:scroller:deadline:isClear:file:line:)``.
    /// - Parameter clearOfBar: false asks only for a hittable element whose centre is in the upper part of the list, for a row big
    ///   enough that no scroll position puts all of it above the bar (the folded Duo's AX5 rows are 386 pt tall and the bar crosses
    ///   the screen at y 430); a row hittable only at the foot of the screen sat under the Add bar (2026-10-26).
    @discardableResult
    func reveal(_ element: XCUIElement, in app: XCUIApplication, clearOfBar: Bool = true) -> XCUIElement {
        scrollTo(element, in: app, scroller: { self.scroller(app) }) { element in
            guard clearOfBar else {
                let list = self.scroller(app).frame
                return element.frame.midY <= list.minY + list.height * 0.7
            }
            // Each overlay is read by one snapshot (absent ones throw and drop out) instead of an `exists` and a frame read.
            let overlays = [app.buttons["fab.add"], app.staticTexts["gallery.lastCall"]].compactMap { try? $0.snapshot().frame.minY }
            let top = overlays.min() ?? .greatestFiniteMagnitude
            return element.frame.maxY <= top
        }
        return element
    }

    /// The page's scrolling list: a `List` is a collection view to XCUITest.
    func scroller(_ app: XCUIApplication) -> XCUIElement {
        app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
    }

    func screenshotName(_ name: String) -> String {
        let orientation = ProcessInfo.processInfo.environment["FENTON_UITEST_ORIENTATION"] ?? "portrait"
        return "\(name)-\(FentonHomeApp.family)-\(orientation)"
    }

    /// Taps a sheet's submit button and waits for `closing` to go. On iPad the first tap can only end editing in
    /// the focused field, so it taps once more if the sheet stayed.
    func submit(_ button: XCUIElement, closing: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        button.tap()
        if !closing.disappears(timeout: 2), button.exists, button.isHittable { button.tap() }
        XCTAssertTrue(closing.disappears(timeout: 5), "Sheet stayed open", file: file, line: line)
    }

    // MARK: - Sheet audits

    /// Opens one todo sheet from a fresh launch of `page`, keeps its screenshot, and runs the accessibility audit at the standard
    /// size and again at AX5 (`FentonHomeApp.audit` relaunches through the same opening). Each sheet has its own test so a flaky
    /// audit of one does not rerun the others.
    /// - Parameters:
    ///   - name: The screenshot name (`task-create`).
    ///   - page: The gallery todo page, or nil for the Chores tab.
    ///   - ready: The identifier that says the sheet is open.
    ///   - open: Opens the sheet from the page.
    func auditSheet(_ name: String, page: String? = nil, ready: String, open: @escaping (XCUIApplication) -> Void) throws {
        func opened(_ app: XCUIApplication) -> XCUIApplication {
            open(app)
            XCTAssertTrue(app.descendants(matching: .any)[ready].firstMatch.appears(timeout: 5), "\(name) did not open")
            app.descendants(matching: .any)[ready].firstMatch.settled() // Let the sheet settle.
            return app
        }
        let app = opened(launch(page: page))
        keepScreenshot(app, screenshotName(name))
        try FentonHomeApp.audit(app) { opened(self.launch(page: page, arguments: FentonHomeApp.ax5)) }
    }
}
