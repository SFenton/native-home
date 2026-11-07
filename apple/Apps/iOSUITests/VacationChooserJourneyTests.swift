import XCTest

/// The Vacation chooser: both modes as 44 pt rows and the page each opens, and the chooser's accessibility audit.
@MainActor
final class VacationChooserJourneyTests: VacationJourneyTestCase {
    /// The chooser offers both modes as 44 pt rows.
    func testChooserTargets() {
        let app = open(.chooser)
        assertTarget("vacation.chooser.vacationMode", in: app)
        assertTarget("vacation.chooser.soloTrip", in: app)
        // A UIKit row is one button element: its subtitle is part of the label, not a static text of its own.
        XCTAssertTrue(element("vacation.chooser.soloTrip", in: app).label.contains("One traveler, one home resident"))
    }

    /// The Vacation Mode row opens the Vacation Mode page.
    func testChooserOpensVacationMode() {
        let app = open(.chooser)
        tap("vacation.chooser.vacationMode", in: app)
        XCTAssertTrue(element("vacation.modeCard", in: app).appears(timeout: 5))
    }

    /// The Solo Trip row opens the Solo Trip page.
    func testChooserOpensSoloTrip() {
        let app = open(.chooser)
        tap("vacation.chooser.soloTrip", in: app)
        XCTAssertTrue(element("soloTrip.toggle", in: app).appears(timeout: 5))
    }

    func testChooserPassesAudit() throws { try audit(.chooser) }
}
