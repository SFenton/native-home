import XCTest

/// Partly folded iPhone Duo (`.agents/design/section-sides.md`): every section of a page sits wholly on one side of the hinge band.
/// Duo only (a layout journey). Partly folded the page is split and nothing crosses the band; folded or flat it is one column. The test
/// never skips on the pose: an `XCTSkip` on the Duo hangs the runner and the restart returns the Duo to folded.
@MainActor
final class SectionSidesJourneyTests: JourneyTestCase {
    /// The band measured on the simulator: 455.3 to 495.7 pt.
    private static let band: ClosedRange<CGFloat> = 455.3...495.7

    private struct Page {
        var gallery: String
        var marker: String
        var scroll: String
        var environment: [String: String] = [:]
        var sections: String
    }

    private static let security = Page(gallery: "security", marker: "security.columns.split", scroll: "security.scroll", sections: "security.")
    private static let climate = Page(gallery: "climate", marker: "climate.columns.split", scroll: "climate.scroll", sections: "climate.")
    private static let customLights = Page(gallery: "custom-lights", marker: "customLights.columns.split", scroll: "customLights.scroll",
                                           sections: "customLights.")
    private static let sprinklers = Page(gallery: "sprinklers", marker: "sprinklers.columns.split", scroll: "sprinklers.scroll", sections: "sprinklers.")
    private static let media = Page(gallery: "media-page", marker: "media.columns.split", scroll: "media.scroll", sections: "media.")

    private static func room(_ id: String) -> Page {
        Page(gallery: "rooms", marker: "room.columns.split", scroll: "room.scroll.\(id)",
             environment: ["FENTON_GALLERY_ROOM": id, "FENTON_GALLERY_OFFLINE": "1", "FENTON_GALLERY_CLEAN": "1"], sections: "room.")
    }

    // MARK: Helpers

    private func open(_ page: Page, arguments: [String] = []) throws -> XCUIApplication {
        try XCTSkipUnless(FentonHomeApp.family == .iPhoneDuo, "Only the iPhone Duo has a hinge band")
        let app = startApp({
            let configured = FentonHomeApp.makeApp()
            configured.launchEnvironment["FENTON_GALLERY"] = page.gallery
            configured.launchEnvironment.merge(page.environment) { _, new in new }
            configured.launchArguments += arguments
            return configured
        }())
        XCTAssertTrue(element(page.scroll, in: app).appears(timeout: 30), "\(page.gallery) did not open")
        settleScreen()
        return app
    }

    /// The pose decides the shape. Partly folded (a section starts past the band, or the container's marker shows) the page is split and
    /// the checks below hold it to the band. Folded or flat it is the ordinary single-column page: nothing runs past the window. XCUITest drives
    /// the outer panel (466 x 678 pt) even while the inner one is lit, so a run usually sees the folded pose; the partly folded layout is
    /// asserted by `UKHostedSectionSidesTests` at the measured 868 pt content, and the pose-matrix captures of the inner panel.
    private func assertPoseLayout(_ app: XCUIApplication, _ page: Page, file: StaticString = #filePath, line: UInt = #line) {
        let frames = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", page.sections))
            .allElementsBoundByIndex.filter { $0.exists && $0.frame.width > 0 && $0.identifier != page.scroll && !$0.identifier.contains(".chip.") }.map(\.frame)
        XCTAssertFalse(frames.isEmpty, "\(page.gallery) shows no sections", file: file, line: line)
        let split = element(page.marker, in: app).exists || frames.contains { $0.minX >= Self.band.upperBound - 1 }
        if !split {
            let window = app.windows.firstMatch.frame
            XCTAssertTrue(frames.allSatisfy { $0.maxX <= window.width + 1 }, "\(page.gallery) overflows the window outside the partly folded pose", file: file, line: line)
        }
    }

    /// Everything a person can press or read as a section on the page keeps clear of the band. The status rail's chips are not sections:
    /// the rail scrolls over the band by design (E1).
    private func assertClearOfTheBand(_ app: XCUIApplication, _ page: Page, file: StaticString = #filePath, line: UInt = #line) {
        let elements = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", page.sections)).allElementsBoundByIndex
        XCTAssertFalse(elements.isEmpty, "No elements", file: file, line: line)
        for element in elements where element.exists && element.frame.width > 0 && element.identifier != page.scroll && !element.identifier.contains(".chip.") {
            let frame = element.frame
            XCTAssertFalse(frame.minX < Self.band.upperBound - 1 && frame.maxX > Self.band.lowerBound + 1,
                           "\(element.identifier) crosses the band: \(frame)", file: file, line: line)
        }
    }

    /// 44 pt targets and column-major order: the controls of the leading side come before those of the trailing side.
    private func assertTargetsAndOrder(_ app: XCUIApplication, _ page: Page, file: StaticString = #filePath, line: UInt = #line) {
        // Section controls only: the back button and the status rail's chips are page chrome, not sections.
        let buttons = app.buttons.allElementsBoundByIndex.filter {
            $0.exists && $0.isHittable && $0.frame.width > 0 && $0.identifier.hasPrefix(page.sections) && !$0.identifier.contains(".chip.")
        }
        for control in buttons {
            XCTAssertGreaterThanOrEqual(min(control.frame.width, control.frame.height), 43.5, "\(control.identifier) is under 44 pt: \(control.frame)", file: file, line: line)
        }
        let sides = buttons.map { $0.frame.midX > Self.band.upperBound }
        if let firstTrailing = sides.firstIndex(of: true) {
            XCTAssertFalse(sides[firstTrailing...].contains(false), "A leading control is read after a trailing one", file: file, line: line)
        }
    }

    private func check(_ page: Page, audit: Bool = true) throws {
        let app = try open(page)
        assertPoseLayout(app, page)
        assertClearOfTheBand(app, page)
        assertTargetsAndOrder(app, page)
        if audit { try FentonHomeApp.audit(app) { try self.open(page, arguments: FentonHomeApp.ax5) } }
    }

    // MARK: Pages

    /// One test visits every page: the Duo runner may restart after a test and come back folded. The page list is the per-page table of the design record, a sample of each kind (hero page, config
    /// grid, tile set, room with two sections, room with one).
    func testEverySectionStaysOnOneSideOfTheBand() throws {
        let pages = [Self.room("living-room"), Self.room("back-deck"), Self.security, Self.climate, Self.customLights, Self.sprinklers, Self.media]
        for page in pages {
            try check(page, audit: page.gallery == "security")
        }
        // At AX5 the band is still physical: two columns, nothing across it, and Security's wrapped rail leads.
        let app = try open(Self.security, arguments: FentonHomeApp.ax5)
        assertClearOfTheBand(app, Self.security)
    }
}
