import XCTest

/// How a status chip's sheet appears (`.agents/design/sheet-reveal.md`): the tiles fade in together once the sheet is up, with no arc
/// when the content is ready; with the content held back (`FENTON_SHEET_REVEAL_HOLD_MS`) a centred, labelled arc shows first and then
/// gives way to the tiles. Runs on iPhone, the folded Duo and iPad. These journeys measure animation, so their launches keep it on.
@MainActor
final class RoomOverviewRevealJourneyTests: JourneyTestCase {
    override class var measuresAnimation: Bool { true }

    private static let chips: [(chip: String, title: String)] = [
        ("lights", "Lights"), ("climate", "Climate"), ("occupancy", "Occupancy"), ("contacts", "Contacts"), ("airQuality", "Air Quality"),
    ]

    /// The first room tile of a chip's overview. Any element type: most overviews open a room (buttons), Air Quality's tiles are read-only.
    private func firstRoom(_ chip: String, in app: XCUIApplication) -> XCUIElement {
        let prefix = chip == "airQuality" ? "overview.airQuality.room." : "overview.\(chip).room."
        return app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND NOT identifier CONTAINS '.action.'", prefix)).firstMatch
    }

    private func tapChip(_ chip: String, in app: XCUIApplication) {
        let button = app.buttons["home.chip.\(chip)"]
        XCTAssertTrue(button.appears(timeout: 10), chip)
        let window = app.windows.firstMatch
        // The rail scrolls sideways: bring a chip past the edge into view first.
        for _ in 0..<6 where button.frame.maxX > window.frame.maxX - 8 || button.frame.minX < window.frame.minX + 8 {
            let direction: CGFloat = button.frame.maxX > window.frame.maxX - 8 ? -1 : 1
            let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.frame.midX, dy: button.frame.midY))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: direction * window.frame.width * 0.4, dy: 0)))
        }
        button.tap()
    }

    /// A ready sheet shows its tiles together and never an arc.
    func testReadyChipSheetsFadeTheirTilesInWithNoArc() throws {
        let app = try FentonHomeApp.launchSignedIn()
        for (chip, _) in Self.chips {
            tapChip(chip, in: app)
            let spinner = app.descendants(matching: .any)["contentGate.spinner"]
            XCTAssertTrue(firstRoom(chip, in: app).appears(timeout: 10), "\(chip) tiles appear on \(layout)")
            XCTAssertFalse(spinner.exists, "\(chip): a sheet whose content is ready shows no arc on \(layout)")
            XCTAssertTrue(app.buttons["Close"].exists)
            app.buttons["Close"].tap()
            XCTAssertTrue(app.buttons["home.chip.lights"].appears(timeout: 5))
        }
    }

    /// Held back, the sheet shows a centred arc named for it, then the tiles.
    func testAHeldSheetShowsACentredLabelledArcThenItsTiles() throws {
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_SHEET_REVEAL_HOLD_MS": "9000"])
        tapChip("climate", in: app)
        let spinner = app.descendants(matching: .any)["contentGate.spinner"]
        XCTAssertTrue(spinner.appears(timeout: 5), "the arc fades in after the grace on \(layout)")
        XCTAssertEqual(spinner.label, "Loading Climate")
        let page = app.otherElements["overview.climate"]
        XCTAssertTrue(page.exists)
        // Centred on the page's content area (its safe area), which on the folded Duo stops short of the rail: the sheet's own midpoint is
        // not the content's. The tiles, drawn in that same area, give its centre once they show (checked below).
        let arcMidX = spinner.frame.midX
        XCTAssertEqual(arcMidX, page.frame.midX, accuracy: page.frame.width / 4, "near the middle of the sheet on \(layout)")
        XCTAssertGreaterThan(spinner.frame.midY, page.frame.minY + 44, "below the bar")
        XCTAssertLessThan(spinner.frame.midY, page.frame.maxY, "inside the sheet")
        XCTAssertGreaterThan(spinner.frame.minX, page.frame.minX, "never clipped at the leading edge")
        XCTAssertFalse(firstRoom("climate", in: app).exists, "the tiles wait while the arc shows")
        XCTAssertTrue(firstRoom("climate", in: app).appears(timeout: 20), "then the tiles appear")
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'overview.climate.room.' AND NOT identifier CONTAINS '.action.'"))
            .allElementsBoundByIndex.map(\.frame).filter { $0.width > 0 }
        let content = (tiles.map(\.minX).min() ?? 0, tiles.map(\.maxX).max() ?? 0)
        XCTAssertEqual(arcMidX, (content.0 + content.1) / 2, accuracy: 6, "the arc was centred on the tiles' area, not under the rail, on \(layout)")
        XCTAssertFalse(spinner.exists, "and the arc has gone")
    }

    /// The Occupancy sheet: the Climate sheet's own audit (`HomeJourneyTests.testClimateOverviewAudit`) already fails on main with "Label not
    /// human-readable" on its temperature values ('70.2°F'), before this change, so it is not repeated here.
    func testChipSheetPassesAccessibilityAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        tapChip("occupancy", in: app)
        XCTAssertTrue(firstRoom("occupancy", in: app).appears(timeout: 10))
        settleScreen()
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.tapChip("occupancy", in: large)
            XCTAssertTrue(self.firstRoom("occupancy", in: large).appears(timeout: 10))
            settleScreen()
            return large
        }
    }
}
