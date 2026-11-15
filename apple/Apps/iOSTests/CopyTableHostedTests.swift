import HassCore
import XCTest

// MARK: - Copy catalog in the host app

/// The compiled copy catalog resolves inside the app process the hosted bundle runs in, where `Bundle.module` is the
/// package resource bundle of the HassCore copy that HassUI links.
final class CopyTableHostedTests: XCTestCase {
    func testCatalogResolvesInTheHostedApp() {
        let table = CopyTable()
        XCTAssertEqual(table.text("copy.sample.allClosed", fallback: "MISSING"), "All Closed")
        XCTAssertEqual(table.text("copy.sample.lightsOn", ["count": "2", "room": "Hall"], fallback: "MISSING"), "2 lights on in Hall")
        XCTAssertTrue(table.diagnostics.isEmpty)
    }

    func testOverrideAndMissingKeyInTheHostedApp() {
        let table = CopyTable(overrides: ["copy.sample.allClosed": "Everything Shut"])
        XCTAssertEqual(table.text("copy.sample.allClosed", fallback: "MISSING"), "Everything Shut")
        XCTAssertEqual(table.text("copy.sample.absent", fallback: "Fallback"), "Fallback")
        XCTAssertEqual(table.diagnostics, [.missingKey("copy.sample.absent")])
    }
}
