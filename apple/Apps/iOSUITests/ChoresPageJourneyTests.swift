import XCTest

/// The Chores tab's page and its quick links on the fixture gallery: counts, navigation, tile colours and the tab's accessibility
/// audit (area A of the Chores split). Spec: `.agents/pages/chores/spec.md`.
@MainActor
final class ChoresPageJourneyTests: ChoresJourneyTestCase {
    /// Quick links are navigation tiles with the chevron, named buttons with their open counts in the state line ("5 open · 2 overdue",
    /// no numeral: rollout lane M, item 26); the viewer's own link reads "Your Chores".
    func testQuickLinksShowCountsAndNavigate() {
        let app = launch()
        let mine = element("chores.link.\(expectations[.choresFirstPageId])", in: app)
        XCTAssertTrue(mine.appears(timeout: 5))
        XCTAssertEqual(mine.label, "Your Chores")
        let count = mine.value as? String ?? ""
        XCTAssertTrue(count.range(of: #"^\d+ open · 2 overdue$"#, options: .regularExpression) != nil, "Open count and overdue: \(count)")
        XCTAssertEqual(element("chores.link.groceries", in: app).value as? String, "3 open")
        XCTAssertEqual(element("chores.link.\(expectations[.choresSecondPageId])", in: app).label, expectations[.choresSecondLinkTitle])
        XCTAssertGreaterThanOrEqual(mine.frame.height, 43)
        mine.tap()
        // The page that opens is the tapped link's (in a list row, the links all fired and Groceries, the last, won).
        XCTAssertTrue(app.navigationBars[expectations[.choresFirstPageTitle]].appears(timeout: 10), "Your Chores did not open the first resident's page")
    }

    /// Owner, 2026-10-16: quick-link tiles are filled in colours that nothing else in the app uses, with white filled
    /// glyphs. Each tile's fill is sampled from the screen and matched to its family.
    func testQuickLinkTilesAreFilledInTheirOwnColours() throws {
        let app = launch()
        let expected: [(id: String, family: String, rgb: (Int, Int, Int))] = [
            (expectations[.choresFirstPageId], "choreFirst", expectations.rgb(.choresFirstLinkTint)),
            (expectations[.choresSecondPageId], "choreSecond", expectations.rgb(.choresSecondLinkTint)),
            ("unassigned-chores", "choreUnassigned", expectations.rgb(.choresUnassignedLinkTint)),
            ("home-improvement-chores", "choreHome", expectations.rgb(.choresHomeLinkTint)),
            ("groceries", "groceries", expectations.rgb(.choresGroceriesLinkTint)),
        ]
        keepScreenshot(app, screenshotName("chores-quick-links"))
        let capture = try XCTUnwrap(RenderedContrast.Capture.screen())
        for tile in expected {
            let link = element("chores.link.\(tile.id)", in: app)
            XCTAssertTrue(link.exists, tile.id)
            // The bottom-leading corner area, below the text and clear of the top highlight. On the page the tile is tinted
            // glass: the fill at 78% over the dark underlay, then the sheen's bottom shade (`TileGeometry.glass`).
            let point = CGPoint(x: link.frame.minX + 10, y: link.frame.maxY - 6)
            let sample = try XCTUnwrap(RenderedContrast.rgb(at: point, in: capture), tile.id)
            let fill = UInt32(tile.rgb.0 << 16 | tile.rgb.1 << 8 | tile.rgb.2)
            XCTAssertTrue(TileGeometry.matchesGlass((sample.red, sample.green, sample.blue), fill, onPage: true,
                                                    heightFraction: 1 - 6 / link.frame.height),
                          "\(tile.id) is \(sample), expected \(tile.rgb) (\(tile.family)) under tinted glass")
        }
    }

    func testChoresTabPassesAccessibilityAudit() throws {
        let app = launch()
        keepScreenshot(app, screenshotName("chores"))
        try FentonHomeApp.audit(app) { self.launch(arguments: FentonHomeApp.ax5) }
    }
}
