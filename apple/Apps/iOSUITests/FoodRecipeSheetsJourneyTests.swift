import XCTest

/// The Recipes sort and filter sheets, one audit test each (with the AX5 comparison page, as `FloatingActionsJourneyTests` does for its
/// sheet). Sources: `RecipeSortFilterSheets`, `RecipeFilters`. The helpers that open and scroll each sheet live here: no other class uses them.
@MainActor
final class FoodRecipeSheetsJourneyTests: FoodJourneyTestCase {
    /// The Sort sheet with a changed choice (so Reset to Defaults shows), scrolled until `reveal` is on screen,
    /// for an audit and its AX5 comparison page.
    private func openSortSheet(_ app: XCUIApplication, reveal: String = "Reset to Defaults") -> XCUIApplication {
        waitForGrid(app)
        element("fab.sort", in: app).tap()
        XCTAssertTrue(app.buttons["filterSheet.apply"].appears(timeout: 5))
        let alphabetical = element("recipes.sort.alphabetical", in: app)
        let sheet = app.collectionViews.firstMatch
        // At AX5 the row starts below the fold, and the Form only creates rows on screen.
        for _ in 0..<6 where !isReachable(alphabetical) { sheet.swipeUp() }
        alphabetical.tap()
        if reveal == "Sort By" {
            // Only while the header is off screen: a swipe down on a sheet already at the top drags it closed, which a
            // fitted sheet (content-height detent) reaches at the default text size.
            for _ in 0..<6 where !isReachable(app.staticTexts["Sort By"]) { sheet.swipeDown() }
            settleScreen()
        } else {
            scroll(to: reveal, in: app, sheet: sheet)
        }
        return app
    }

    /// The Filter sheet with expiring-only on (so Reset to Defaults shows), scrolled until `reveal` is on screen.
    private func openFilterSheet(_ app: XCUIApplication, reveal: String = "Reset to Defaults") -> XCUIApplication {
        waitForGrid(app)
        element("fab.filter", in: app).tap()
        XCTAssertTrue(app.buttons["filterSheet.apply"].appears(timeout: 5))
        let toggle = element("recipes.filter.expiringOnly", in: app).switches.firstMatch
        let sheet = app.collectionViews.firstMatch
        for _ in 0..<6 where !isReachable(toggle) { sheet.swipeUp() }
        toggle.tap()
        scroll(to: reveal, in: app, sheet: sheet)
        return app
    }

    /// Logs Reset to Defaults' frame against the sheet and window (evidence for the FilterSheet audit findings).
    private func logResetFrame(_ moment: String, in app: XCUIApplication) {
        let reset = app.buttons["Reset to Defaults"]
        let sheet = app.collectionViews.firstMatch
        let resetFrame = (try? reset.snapshot())?.frame
        print("FOODDIAG reset \(moment): exists=\(resetFrame != nil) hittable=\(resetFrame != nil && reset.isHittable) "
              + "frame=\(resetFrame ?? .zero) sheet=\((try? sheet.snapshot())?.frame ?? .zero) window=\(app.windows.firstMatch.frame) "
              + "keyboard=\(app.keyboards.firstMatch.exists)")
    }

    /// Scrolls the sheet until the text or button labeled `label` is on screen, so the AX5 comparison page can
    /// measure it (the Form only creates rows on screen).
    private func scroll(to label: String, in app: XCUIApplication, sheet: XCUIElement) {
        let target = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        for _ in 0..<8 where !isReachable(target) { sheet.swipeUp() }
        // One more so the row clears the sheet's bottom edge: a row cut by the edge reads as clipped text with
        // unsupported Dynamic Type. Headers stay put so the AX5 page still shows them. Only when the row is cut.
        if !["Ranking Strength", "Sort By"].contains(label), let targetFrame = (try? target.snapshot())?.frame, !sheet.frame.contains(targetFrame) { sheet.swipeUp() }
        settleScreen()
    }

    /// The Sort sheet alone, with the AX5 comparison page (as FloatingActionsJourneyTests does for its sheet), at one scroll
    /// position: `reveal` is the label scrolled on screen, and each AX5 page shows what it measures.
    private func auditSortSheet(reveal: String) throws {
        let app = openSortSheet(launch("recipes"), reveal: reveal)
        keepScreenshot(app, "food-recipes-sort-\(device)")
        try audit(app, presenter: element("fab.sort", in: app)) {
            self.openSortSheet(self.launch("recipes", arguments: FentonHomeApp.ax5), reveal: reveal)
        }
    }

    /// The Sort sheet at the top (the Sort By header). One of the split positions (`testSortSheetPassesAccessibilityAudit*`).
    func testSortSheetPassesAccessibilityAuditAtTop() throws { try auditSortSheet(reveal: "Sort By") }

    /// The Sort sheet scrolled to Reset to Defaults.
    func testSortSheetPassesAccessibilityAuditAtReset() throws { try auditSortSheet(reveal: "Reset to Defaults") }

    /// The Filter sheet alone, with the AX5 comparison page, at one scroll position: `reveal` is the row scrolled on screen at the
    /// default size and `ax5Reveal` the one the AX5 page shows.
    private func auditFilterSheet(reveal: String, ax5Reveal: String) throws {
        let app = openFilterSheet(launch("recipes"), reveal: reveal)
        keepScreenshot(app, "food-recipes-filter-\(device)")
        logResetFrame("filter \(reveal)", in: app)
        try audit(app, presenter: element("fab.filter", in: app)) {
            let large = self.openFilterSheet(self.launch("recipes", arguments: FentonHomeApp.ax5), reveal: ax5Reveal)
            self.logResetFrame("filter AX5 \(ax5Reveal)", in: large)
            self.keepScreenshot(large, "food-recipes-filter-\(self.device)-ax5-\(ax5Reveal == "Reset to Defaults" ? "reset" : "ranking")")
            return large
        }
    }

    /// The Filter sheet scrolled to Reset to Defaults (`testFilterSheetPassesAccessibilityAudit*`).
    func testFilterSheetPassesAccessibilityAuditAtReset() throws {
        try auditFilterSheet(reveal: "Reset to Defaults", ax5Reveal: "Reset to Defaults")
    }

    /// The Ranking Strength section, scrolled to its last row so no row is cut by the sheet's edge; the AX5 page shows the header
    /// it measures.
    func testFilterSheetPassesAccessibilityAuditAtRankingStrength() throws {
        try auditFilterSheet(reveal: "Expiry Weight", ax5Reveal: "Ranking Strength")
    }
}
