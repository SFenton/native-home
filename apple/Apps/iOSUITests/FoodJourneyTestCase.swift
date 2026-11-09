import XCTest

/// The base of the Food journeys: the gallery launch (through ``AppReuse``, so every area class opts into app reuse), the orientation
/// handling, the accessibility audit with the recipe cards' reflow allowance, and the element, call-line and scrolling helpers every area
/// class shares. The old single `FoodJourneyTests` class was split by area (`contracts/test-map.json`) so a change to one area runs only
/// its journeys; nothing here is specific to one area. The pages run in the debug gallery (fixture recipes, recording service; nothing
/// reaches the house) on iPhone, iPhone Duo and iPad (`.agents/pages/food/spec.md`). This is not a `JourneyTestCase`: it keeps the
/// class's own orientation and app-reuse teardown.
@MainActor
class FoodJourneyTestCase: XCTestCase {
    /// `TEST_RUNNER_FENTON_ORIENTATION=landscape` runs every journey in landscape (iPad and unfolded Duo
    /// screenshots per layout); otherwise portrait.
    static var orientation: UIDeviceOrientation {
        ProcessInfo.processInfo.environment["FENTON_ORIENTATION"] == "landscape" ? .landscapeLeft : .portrait
    }

    override func setUp() {
        continueAfterFailure = false
        MainActor.assumeIsolated {
            if FentonHomeApp.family != .iPhone { XCUIDevice.shared.orientation = Self.orientation }
        }
    }
    /// Ends the class's resident app when reuse is on (``AppReuse``). This class is not a `JourneyTestCase`, so it does it itself.
    override class func tearDown() {
        MainActor.assumeIsolated { AppReuse.finish(owner: String(describing: self)) }
        super.tearDown()
    }
    override func tearDown() {
        MainActor.assumeIsolated {
            if FentonHomeApp.family != .iPhone { XCUIDevice.shared.orientation = Self.orientation }
        }
    }

    // MARK: - Helpers

    var device: String {
        switch FentonHomeApp.family {
        case .iPhone: "iphone"
        case .iPhoneDuo: Self.orientation == .portrait ? "duo" : "duo-landscape"
        case .iPad: Self.orientation == .portrait ? "ipad" : "ipad-landscape"
        }
    }

    /// Launches `configured` through ``AppReuse`` with this class as the owner (one resident app per class and launch signature).
    func startApp(_ configured: XCUIApplication) -> XCUIApplication {
        AppReuse.start(configured, owner: String(describing: type(of: self)))
    }

    func launch(_ route: String, mode: String? = nil, arguments: [String] = [], environment: [String: String] = [:]) -> XCUIApplication {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment.merge(environment) { $1 }
        configured.launchEnvironment["FENTON_GALLERY"] = "food"
        configured.launchEnvironment["FENTON_GALLERY_ROUTE"] = route
        if let mode { configured.launchEnvironment["FENTON_GALLERY_FOOD_MODE"] = mode }
        configured.launchArguments += arguments
        let app = startApp(configured)
        return app
    }

    /// The accessibility audit, unless `TEST_RUNNER_FENTON_SKIP_AUDIT=1` (screenshot-only passes, so a failing
    /// audit cannot stop a journey before its later pages are captured).
    func audit(_ app: XCUIApplication, presenter: XCUIElement? = nil, ax5Page: (() throws -> XCUIApplication)? = nil) throws {
        guard ProcessInfo.processInfo.environment["FENTON_SKIP_AUDIT"] != "1" else { return }
        // The recipe cards reflow into a compact thumbnail row at AX5 and can be shorter than the photo card.
        try FentonHomeApp.audit(app, ax5Page: ax5Page, presenter: presenter, reflowing: ["recipes.card.", "food.suggestion."])
    }

    func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    func expectCall(_ prefix: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let matched = waitFor(label, "label BEGINSWITH %@", "Last call: \(prefix)")
        XCTAssertTrue(matched, "Last call was '\(label.exists ? label.label : "(label missing)")', expected '\(prefix)'", file: file, line: line)
    }

    func waitFor(_ element: XCUIElement, _ format: String, _ argument: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format, argument), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Swipes up until `element` is on screen; `container` (e.g. the recipe's scroll view in a split pane)
    /// receives the swipes, the app otherwise.
    ///
    /// One element snapshot per swipe answers "in the tree" and "where" (the window is measured once); `isHittable`, a live read, is
    /// asked only once the frame is inside the window; and the loop ends when three swipes in a row do not move the element (the
    /// foot of the page), instead of swiping a fixed 12 times (see `VacuumJourneyTestCase.reveal`).
    func reveal(_ element: XCUIElement, in app: XCUIApplication, swiping container: XCUIElement? = nil) {
        let target = container ?? app
        // Fully on screen, not merely hittable: a tile whose top edge shows still reports hittable, and the tap at its
        // centre then lands below the window (the hub's All Food tile on iPhone, 2026-10-17).
        let window = app.windows.firstMatch.frame
        var lastMinY: CGFloat?
        var stuck = 0
        var inView = false
        for _ in 0..<12 {
            let frame = (try? element.snapshot())?.frame
            if let frame, !frame.isEmpty, window.contains(frame), element.isHittable { inView = true; break }
            if let frame, let lastMinY, abs(lastMinY - frame.minY) < 1 { stuck += 1 } else { stuck = 0 }
            if stuck >= 3 { break }
            lastMinY = frame?.minY
            target.swipeUp()
        }
        if !inView, let frame = (try? element.snapshot())?.frame, window.contains(frame), element.isHittable { inView = true }
        XCTAssertTrue(inView, "\(element) never came into view")
    }

    func assertTarget(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.width, 43, element.label, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 43, element.label, file: file, line: line)
    }

    func waitForGrid(_ app: XCUIApplication) {
        XCTAssertTrue(element("recipes.card.1", in: app).appears(timeout: 15), "Recipes did not load")
        settleScreen() // Mid-animation frames fail contrast and clipping.
    }
}
