import XCTest

/// The page title (`.agents/patterns/header-edge-fade.md`, R7). Owner, 2026-10-28: "Bring back the title collapse as well." On the
/// iPhone and the iPad with its flyout the page has the system's large title, which collapses into the leading-aligned inline title (right of the hamburger) in the
/// bar as the page scrolls; on the folded iPhone Duo (the vertical bar has no hamburger) the system's inline title is in the bar from the start. No
/// custom `nav.title` view; a long title is truncated by the system. Runs on the `shell-header` gallery with a title no bar is wide
/// enough for, with no sign-in.
@MainActor
final class PageTitleJourneyTests: JourneyTestCase {
    static let longTitle = JourneyExpectations.gallery[.longPageTitle]

    // MARK: - Helpers

    private func launch(largeTitle: Bool, pushed: Bool = false, title: String = longTitle, arguments: [String] = []) -> XCUIApplication {
        var environment = ["FENTON_GALLERY_SCROLL": "1", "FENTON_GALLERY_TITLE": title]
        if largeTitle { environment["FENTON_GALLERY_PHONE"] = "1" }
        if pushed { environment["FENTON_GALLERY_PUSHED"] = "1" }
        // Every switch is a `FENTON_GALLERY_*` variable, so a test's state is a reset of the class's resident app (`app-reuse.md`);
        // AX5 (`arguments`) and Reduce Motion launch fresh by signature.
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "shell-header"
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launchArguments += arguments
        _ = startApp(app)
        XCTAssertTrue(app.buttons["nav.profile"].appears(timeout: 20), "No Profile button")
        settleScreen() // Let the bar settle.
        return app
    }

    private func scrollThePage(_ app: XCUIApplication) {
        app.swipeUp()
        settleScreen()
    }

    /// The tree of the page, flattened, each node with whether it sits in a navigation bar.
    private func nodes(_ app: XCUIApplication) -> [(node: any XCUIElementSnapshot, inBar: Bool)] {
        guard let root = try? app.snapshot() else { return [] }
        func walk(_ node: any XCUIElementSnapshot, _ inBar: Bool) -> [(node: any XCUIElementSnapshot, inBar: Bool)] {
            let bar = inBar || node.elementType == .navigationBar
            return node.children.flatMap { [($0, bar)] + walk($0, bar) }
        }
        return walk(root, false)
    }

    /// The system's own inline title in the navigation bar (its frame), nil while it is not showing (the folded Duo's vertical bar has none).
    private func systemBarTitle(_ app: XCUIApplication, title: String) -> CGRect? {
        let element = app.navigationBars.staticTexts[title].firstMatch
        guard element.appears(timeout: 3) else { return nil }
        let frame = nodes(app).first { $0.inBar && $0.node.elementType == .staticText && $0.node.label == title }?.node.frame ?? element.frame
        return frame.width > 1 ? frame : nil
    }

    private func assertInlineTitle(_ app: XCUIApplication, title: String, _ when: String) throws {
        guard let frame = systemBarTitle(app, title: title) else {
            XCTAssertFalse(app.descendants(matching: .any)["nav.title"].firstMatch.exists, "The custom bar title is installed")
            XCTAssertEqual(FentonHomeApp.family, .iPhoneDuo, "The system title is not in the bar \(when)")
            let note = XCTAttachment(string: "Duo: no inline title \(when). Bar statics: \(app.navigationBars.staticTexts.allElementsBoundByIndex.map(\.label))")
            note.lifetime = .keepAlways
            add(note)
            return
        }
        // One tree read for the title's neighbours: the hamburger, the header buttons, the leading button and the window.
        let all = nodes(app)
        XCTAssertFalse(all.contains { $0.node.identifier == "nav.title" }, "The custom bar title is installed")
        func first(_ id: String) -> CGRect? { all.first { $0.node.identifier == id && $0.node.elementType == .button }?.node.frame }
        XCTAssertLessThan(frame.height, 40, "The title is large \(when): \(frame)")
        // Leading aligned (`.toolbarRole(.browser)`, R7 (5)): left of centre, right of the hamburger where there is one.
        // "Climate" is short: only a leading-aligned title sits left of centre (a long title fills the bar either way).
        if title.count <= 12 {
            let window = app.windows.firstMatch.frame
            XCTAssertLessThan(frame.midX, window.midX, "The collapsed title is centred \(when): \(frame)")
        }
        if let menu = first("nav.open"), abs(menu.midY - frame.midY) < 20 {
            XCTAssertGreaterThanOrEqual(frame.minX, menu.maxX - 1, "The title overlaps the hamburger \(when)")
        }
        if let links = first("quickLinks.open"), abs(links.midY - frame.midY) < 20 {
            XCTAssertLessThanOrEqual(frame.maxX, links.minX + 1, "The title runs under the header buttons \(when)")
        }
        if let back = all.first(where: { $0.inBar && $0.node.elementType == .button })?.node.frame, abs(back.midY - frame.midY) < 20 {
            XCTAssertGreaterThanOrEqual(frame.minX, back.maxX - 1, "The title overlaps the leading button \(when)")
        }
    }

    // MARK: - Inline title

    /// The large title at rest: a title taller than the bar's inline one (nil where the system shows none).
    private func largeTitle(_ app: XCUIApplication, title: String) -> CGRect? {
        guard let frame = systemBarTitle(app, title: title), frame.height >= 40 else { return nil }
        return frame
    }

    /// The large title collapses into the inline title as the page scrolls and comes back at the top.
    func testTheLargeTitleCollapsesIntoTheBarWhileScrolling() throws {
        try XCTSkipIf(FentonHomeApp.family == .iPhoneDuo, "The Duo keeps its title in the bar (no large title)")
        let app = launch(largeTitle: true, title: "Climate")
        XCTAssertNotNil(largeTitle(app, title: "Climate"), "No large title at rest")
        scrollThePage(app)
        try assertInlineTitle(app, title: "Climate", "after scrolling")
        app.swipeDown(); app.swipeDown()
        settleScreen()
        XCTAssertNotNil(largeTitle(app, title: "Climate"), "The large title did not come back at the top")
    }

    /// A pushed page has Back leading; its collapsed title is the system's, in the bar beside it.
    func testPushedPageTitleCollapsesBesideBack() throws {
        try XCTSkipIf(FentonHomeApp.family == .iPhoneDuo, "The Duo keeps its title in the bar (no large title)")
        let app = launch(largeTitle: true, pushed: true)
        scrollThePage(app)
        try assertInlineTitle(app, title: Self.longTitle, "after scrolling")
    }

    /// Once collapsed, the page names its title once (VoiceOver reads one header).
    func testCollapsedTitleIsNamedOnce() throws {
        try XCTSkipIf(FentonHomeApp.family == .iPhoneDuo, "The Duo keeps its title in the bar (no large title)")
        let app = launch(largeTitle: true)
        scrollThePage(app)
        let named = nodes(app).map(\.node).filter { $0.label == Self.longTitle && $0.frame.width > 1 }
        XCTAssertEqual(named.count, 1, "The title is named \(named.count) times, not once: \(named.map(\.frame))")
    }

    /// Accessibility: at the largest text size the collapsed title still exists, stays out from under the header buttons and does
    /// not wrap past the bar.
    func testCollapsedTitleAtAccessibilityTextSize() throws {
        try XCTSkipIf(FentonHomeApp.family == .iPhoneDuo, "The Duo keeps its title in the bar (no large title)")
        let app = launch(largeTitle: true, arguments: FentonHomeApp.ax5)
        scrollThePage(app)
        try assertInlineTitle(app, title: Self.longTitle, "at AX5 after scrolling")
    }

    // MARK: - Title in the bar

    /// The folded Duo (no hamburger) has no large title: the system's inline title is in the bar from the start, the
    /// system's placement (no custom view), truncated by the system when long, still named in full. On the folded Duo's vertical
    /// bar the title may be absent (system behaviour, recorded by the attachment below).
    func testTitleInTheBarIsTheSystemsFromTheStart() throws {
        let app = launch(largeTitle: false)
        XCTAssertFalse(app.descendants(matching: .any)["nav.title"].firstMatch.exists, "The custom bar title is installed")
        guard let title = systemBarTitle(app, title: Self.longTitle) else {
            XCTAssertEqual(FentonHomeApp.family, .iPhoneDuo, "The system title is not in the bar")
            let note = XCTAttachment(string: "Duo: no inline title in the navigation bar. Bar statics: \(app.navigationBars.staticTexts.allElementsBoundByIndex.map(\.label))")
            note.lifetime = .keepAlways
            add(note)
            return
        }
        let window = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(title.maxX, window.width, "The title runs off the screen")
        XCTAssertLessThanOrEqual(title.height, 60, "The title wrapped in the bar: \(title)")
        let note = XCTAttachment(string: "title frame \(title) in window \(window)")
        note.lifetime = .keepAlways
        add(note)
    }

    /// Reduce Motion changes nothing about the system title: still one line.
    func testReduceMotionKeepsTheSystemTitleOnOneLine() throws {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "shell-header"
        app.launchEnvironment.merge([
            "FENTON_GALLERY_SCROLL": "1", "FENTON_GALLERY_TITLE": Self.longTitle,
        ].merging(FentonHomeApp.SystemSetting.environment([.reduceMotion])) { $1 }) { _, new in new }
        _ = startApp(app) // Its own resident app: FENTON_SYSTEM_SETTINGS is part of the launch signature.
        XCTAssertTrue(app.buttons["nav.profile"].appears(timeout: 20))
        settleScreen()
        guard let title = systemBarTitle(app, title: Self.longTitle) else {
            XCTAssertEqual(FentonHomeApp.family, .iPhoneDuo, "The system title is not in the bar under Reduce Motion")
            return
        }
        XCTAssertLessThanOrEqual(title.height, 60, "The title wrapped in the bar: \(title)")
    }
}
