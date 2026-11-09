import XCTest

/// The Settings tab's root list on fixtures (`FENTON_GALLERY=settings`: the same `SettingsScreen` under the shell's page
/// chrome, no sign-in): every row is a named 44 pt control in the web's order, the list scrolls to its last row, and the
/// page passes the accessibility audit on iPhone, iPhone Duo and iPad. The signed-in Settings journeys
/// (`SettingsJourneyTests`) cover the Home Assistant modal.
final class SettingsTabJourneyTests: JourneyTestCase {
    /// The rows in order: Vacation and (for a viewer who sees it) To-Do, the household topics, Home Assistant, Performance,
    /// then the two feedback rows (`FeedbackKind` raw values) and the About section's Version row.
    private static let rows = [
        "settings.vacation", "settings.topic.admin", "settings.topic.specialDeviceModes", "settings.topic.guests",
        "settings.topic.car", "settings.homeAssistant", "settings.performance", "settings.feedback.bug", "settings.feedback.feature",
        "settings.version",
    ]

    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchArguments += arguments
        app.launchEnvironment["FENTON_GALLERY"] = "settings"
        app.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1"
        // The gallery's switches are `FENTON_GALLERY_*` variables, so each test is a reset of the class's resident app
        // (`app-reuse.md`); AX5 (`arguments`) launches fresh by signature. The class is fixtures only: no sign-in or session.
        _ = startApp(app)
        XCTAssertTrue(element("settings.list", in: app).appears(timeout: 30), "The Settings list did not appear")
        return app
    }

    /// Scrolls until `row` can be tapped (a `List` only exposes rows it has laid out).
    private func reveal(_ row: XCUIElement, in app: XCUIApplication) {
        let list = element("settings.list", in: app)
        for _ in 0..<12 where !(row.exists && row.isHittable) { list.swipeUp(velocity: .slow) }
    }

    func testRowsAreNamedControlsWithTargets() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Household"].appears(timeout: 5), "The Household header is missing")
        // Only Vacation is certain to be on screen: Appearance sits between it and the household topics, which on the
        // folded Duo start below the fold.
        for id in Self.rows.prefix(1) {
            let row = element(id, in: app)
            XCTAssertTrue(row.appears(timeout: 5), id)
            assertLabelledTarget(row, id)
        }
        // Rows below the fold exist once scrolled to.
        for id in Self.rows.dropFirst(1) {
            let row = element(id, in: app)
            reveal(row, in: app)
            XCTAssertTrue(row.exists, "\(id) never came into view")
            assertLabelledTarget(row, id)
        }
    }

    /// The row has a label and a 44 pt target, from one snapshot (``assertTarget`` plus the label check cost five requests).
    private func assertLabelledTarget(_ row: XCUIElement, _ id: String) {
        guard let facts = try? row.snapshot() else { return XCTFail("\(id) has no snapshot") }
        XCTAssertFalse(facts.label.isEmpty, "\(id) has no label")
        XCTAssertGreaterThanOrEqual(facts.frame.width, 43, facts.label)
        XCTAssertGreaterThanOrEqual(facts.frame.height, 43, facts.label)
    }

    /// The page is a `ScrollView` over a plain `VStack` (owner, 2026-10-27): `settings.list` is a scroll view, every row is in
    /// the accessibility tree from the first frame (a `List` exposes only the rows it has laid out), each row below the fold is
    /// off screen until scrolled to, and the page scrolls (a gesture on the rows once stopped it taking drags).
    func testPageIsAScrollViewThatBuildsEveryRowOnOpen() {
        let app = launch()
        XCTAssertTrue(app.scrollViews["settings.list"].exists, "settings.list should be the scroll view")
        // One tree read for every row's presence (about ten lookups before).
        if let root = try? app.snapshot() {
            func flatten(_ node: any XCUIElementSnapshot) -> [any XCUIElementSnapshot] { node.children.flatMap { [$0] + flatten($0) } }
            let ids = Set(flatten(root).map(\.identifier))
            for id in Self.rows { XCTAssertTrue(ids.contains(id), "\(id) is not in the tree on open") }
        } else {
            XCTFail("No snapshot of the page")
        }
        let last = element("settings.version", in: app)
        XCTAssertFalse(last.isHittable, "Version should start below the fold")
        let first = element("settings.vacation", in: app)
        let top = first.frame.minY
        app.scrollViews["settings.list"].swipeUp(velocity: .fast)
        XCTAssertLessThan(first.frame.minY, top, "The page did not scroll")
    }

    /// Tapping Version copies it: the footer says "Copied." (the pasteboard itself is the system's), and the row reads as
    /// "Version" with the build as its value, so VoiceOver names each part (`AppBuildInfo.spokenVersionText`).
    func testVersionRowCopiesAndConfirms() {
        let app = launch()
        let row = element("settings.version", in: app)
        reveal(row, in: app)
        XCTAssertTrue(row.exists, "The Version row never came into view")
        XCTAssertEqual(row.label, "Version")
        let value = row.value as? String ?? ""
        XCTAssertTrue(value.contains("build"), "The value should name the version and build: \(value)")
        // The footer sits below the row: on the folded Duo's short screen it is beyond the fold until scrolled to.
        let footer = element("settings.version.footer", in: app)
        reveal(footer, in: app)
        XCTAssertEqual(footer.label, "Tap to copy.")
        XCTAssertTrue(row.isHittable, "Scrolling to the footer pushed the row off screen")
        row.tap()
        let copied = expectation(for: NSPredicate(format: "label == %@", "Copied."), evaluatedWith: footer)
        wait(for: [copied], timeout: 3)
    }

    /// A tap in a row's padding, near the card's leading edge and outside the label, still activates the row (owner, 2026-10-27:
    /// the stack's rows are tappable across the whole cell, as in a `List`). The Version row copies and confirms in its footer.
    func testATapAtTheRowsEdgeActivatesTheRow() {
        let app = launch()
        let row = element("settings.version", in: app)
        reveal(row, in: app)
        let footer = element("settings.version.footer", in: app)
        reveal(footer, in: app)
        XCTAssertTrue(row.isHittable, "Scrolling to the footer pushed the row off screen")
        // 6 pt inside the cell's leading edge (the label starts 15 pt in) and 4 pt below its top (the label sits 15 pt down).
        // The row's element is the whole cell (the button owns the padding, `groupedRowButton`), so the offsets are inside its
        // frame. Anchored to the row itself (an iPad window need not sit at the screen's origin).
        row.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 6, dy: 4)).tap()
        let copied = expectation(for: NSPredicate(format: "label == %@", "Copied."), evaluatedWith: footer)
        wait(for: [copied], timeout: 3)
    }

    /// The same holds for a `NavigationLink` row: a tap in Vacation's leading padding pushes its page.
    func testATapAtALinkRowsEdgePushesItsPage() {
        let app = launch()
        let row = element("settings.vacation", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 6, dy: 4)).tap()
        XCTAssertTrue(element("settings.gallery.pushed", in: app).waitForExistence(timeout: 5), "A tap in the row's padding did not push Vacation")
    }

    /// The list keeps its place and its rows through fast flicks both ways (the probe's drag, by hand).
    func testFlickingTheListKeepsItsRows() {
        let app = launch()
        let list = element("settings.list", in: app)
        for _ in 0..<3 {
            list.swipeUp(velocity: .fast)
            list.swipeDown(velocity: .fast)
        }
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(element("settings.vacation", in: app).appears(timeout: 5), "The first row vanished after flicking")
    }

    func testSettingsTabPassesAccessibilityAudit() throws {
        let app = launch()
        settleScreen() // Let the list settle before the audit reads it.
        try FentonHomeApp.audit(app) {
            let large = self.launch(arguments: FentonHomeApp.ax5)
            settleScreen()
            return large
        }
    }
}
