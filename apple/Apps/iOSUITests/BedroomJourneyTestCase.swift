import XCTest

/// The base of the Bedroom journeys: the `bedroom` gallery launch (fixture state, a recorder that answers like Home Assistant; nothing reaches the house) through
/// `startApp`, so every area class is on app reuse (`.agents/testing/apple/app-reuse.md`), the recorded-call checks, the sheet's own scroll-to-reveal, the tab
/// and power-off helpers and the per-sheet accessibility audit with its AX5 relaunch. The old single `BedroomJourneyTests` class was split by area
/// (`contracts/test-map.json`) so a change to one source file runs only its journeys; nothing here is specific to one area. iPhone, iPhone Duo and iPad
/// (`.agents/patterns/bedroom-devices.md`).
@MainActor
class BedroomJourneyTestCase: JourneyTestCase {

    // MARK: - Helpers

    func launch(sheet: String? = nil, tab: String? = nil, scenario: String = "default", clean: Bool = false,
                        arguments: [String] = []) -> XCUIApplication {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "bedroom"
        configured.launchEnvironment["FENTON_GALLERY_SCENARIO"] = scenario
        if let sheet { configured.launchEnvironment["FENTON_GALLERY_SHEET"] = sheet }
        if let tab { configured.launchEnvironment["FENTON_GALLERY_TAB"] = tab }
        if clean { configured.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1" }
        configured.launchArguments += arguments
        let app = startApp(configured)
        let anchor = element(sheet == nil ? "room.card.Wake-Light Alarms" : sheet == "wake-light" ? "wake.tabs" : "bed.hint", in: app)
        XCTAssertTrue(anchor.appears(timeout: 30), "Bedroom gallery did not open \(sheet ?? "tiles")")
        settleScreen() // Mid-animation frames fail contrast and clipping.
        return app
    }

    func expectCall(startingWith prefix: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let predicate = NSPredicate(format: "label BEGINSWITH %@", "Last call: \(prefix)")
        let matched = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: label)], timeout: 10) == .completed
        XCTAssertTrue(matched, "Last call was '\(label.label)'", file: file, line: line)
    }

    func expectCall(containing text: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let matched = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: label)], timeout: 10) == .completed
        XCTAssertTrue(matched, "Last call was '\(label.label)'", file: file, line: line)
    }

    /// Scrolls in short drags until `element` is hittable (see `MediaRemoteJourneyTests.reveal`). One snapshot per look gives "in the tree", its
    /// frame and which way to drag; the window is read once. It stops once three drags in a row did not move the element (it sits at the scroll limit).
    func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: -window.minX, dy: -window.minY))
        var lastMinY: CGFloat?
        var stuck = 0
        for _ in 0..<24 {
            let frame = (try? element.snapshot())?.frame
            if let frame, !frame.isEmpty, element.isHittable { return }
            if let frame, let lastMinY, abs(lastMinY - frame.minY) < 1 { stuck += 1 } else { stuck = 0 }
            if stuck >= 3 { break }
            lastMinY = frame?.minY
            let known = frame.map { !$0.isEmpty } ?? false
            let above = known ? frame!.midY < window.midY : false
            var x = known && frame!.midX > 0 ? frame!.midX : window.midX
            if FentonHomeApp.family == .iPhoneDuo { x = min(x, window.maxX - 96) }
            // Keep clear of the dial: drag along the column's leading edge.
            x = max(window.minX + 24, min(x, window.minX + 40))
            let from = origin.withOffset(CGVector(dx: x, dy: window.minY + window.height * (above ? 0.35 : 0.65)))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: above ? 220 : -220)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(element.isHittable, "\(element) never came into view")
    }

    func tap(_ id: String, in app: XCUIApplication) {
        let target = element(id, in: app)
        XCTAssertTrue(target.appears(timeout: 10), "\(id) missing")
        reveal(target, in: app)
        target.tap()
    }

    func selectTab(_ title: String, in app: XCUIApplication) {
        // The sheet's section bar (bottom of the sheet); editors carry segmented choices of their own.
        let segmented = app.segmentedControls.matching(NSPredicate(format: "identifier IN %@", ["bed.tabs", "wake.tabs"])).firstMatch
        if segmented.exists { segmented.buttons[title].tap() } else { app.buttons[title].firstMatch.tap() }
    }

    /// The confirmation dialog's "Turn Off" action; the power button itself is also labelled "Turn Off".
    func turnOffConfirmation(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Turn Off", "bed.power")).firstMatch
    }

    // MARK: - Accessibility audits

    /// The pose a test runs in. Phones and the Duo have one pose, so ``upright`` leaves them as they are; on an iPad it sets portrait.
    /// ``iPadLandscape`` is the iPad-only second pose (skipped elsewhere before any launch): the layout-relevant one.
    enum Pose { case upright, iPadLandscape }

    /// Puts the iPad in `pose` before the launch; skips ``Pose/iPadLandscape`` on other families.
    func enter(_ pose: Pose) throws {
        switch pose {
        case .upright:
            if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
        case .iPadLandscape:
            try XCTSkipUnless(FentonHomeApp.family == .iPad, "iPad landscape is the iPad's second pose")
            XCUIDevice.shared.orientation = .landscapeLeft
        }
    }

    /// Audits a sheet, or a page pushed inside it when `open` taps through to one (after each launch, including
    /// the AX5 relaunch), in `pose` (the orientation is set before the launch, never during the test).
    func audit(sheet: String?, tab: String? = nil, scenario: String = "default", pose: Pose = .upright,
                       open: ((XCUIApplication) -> Void)? = nil) throws {
        try enter(pose)
        let app = launch(sheet: sheet, tab: tab, scenario: scenario)
        open?(app)
        try FentonHomeApp.audit(app) {
            let large = self.launch(sheet: sheet, tab: tab, scenario: scenario, arguments: FentonHomeApp.ax5)
            open?(large)
            return large
        }
    }
}
