import Foundation
import XCTest
@testable import HassCore

// MARK: - Copy table resolution

/// `CopyTable` over the real compiled catalog (`Copy.xcstrings` through `Bundle.module`) and over override dictionaries.
final class CopyTableTests: XCTestCase {
    func testCatalogDefaultResolvesThroughBundleModule() {
        let table = CopyTable()
        XCTAssertEqual(table.text("copy.sample.allClosed", fallback: "?"), "All Closed")
        XCTAssertTrue(table.diagnostics.isEmpty)
    }

    func testInterpolatesNamedPlaceholder() {
        XCTAssertEqual(CopyTable().text("copy.sample.greeting", ["name": "Ada"], fallback: "?"), "Welcome home, Ada")
    }

    func testEnglishOneAndOtherPlurals() {
        let table = CopyTable()
        XCTAssertEqual(table.text("copy.sample.lightsOn", ["count": "1", "room": "Den"], fallback: "?"), "1 light on in Den")
        XCTAssertEqual(table.text("copy.sample.lightsOn", ["count": "3", "room": "Den"], fallback: "?"), "3 lights on in Den")
        XCTAssertEqual(table.text("copy.sample.lightsOn", ["count": "0", "room": "Den"], fallback: "?"), "0 lights on in Den")
        XCTAssertEqual(table.text("copy.sample.lightsOn", ["count": "1.5", "room": "Den"], fallback: "?"), "1.5 lights on in Den")
    }

    func testOverrideBeatsCatalogDefault() {
        let table = CopyTable(overrides: ["copy.sample.allClosed": "Everything Shut"])
        XCTAssertEqual(table.text("copy.sample.allClosed", fallback: "?"), "Everything Shut")
    }

    func testOverridePluralMembersAreChosenByCount() {
        let table = CopyTable(overrides: ["copy.sample.contactsOpen_one": "One open", "copy.sample.contactsOpen_other": "{{count}} are open"])
        XCTAssertEqual(table.text("copy.sample.contactsOpen", ["count": "1"], fallback: "?"), "One open")
        XCTAssertEqual(table.text("copy.sample.contactsOpen", ["count": "4"], fallback: "?"), "4 are open")
    }

    func testInlineBeatsOverrideAndCatalog() {
        let table = CopyTable(overrides: ["copy.sample.allClosed": "Everything Shut"])
        XCTAssertEqual(table.text("copy.sample.allClosed", inline: "Locked Up", fallback: "?"), "Locked Up")
    }

    func testMissingKeyReturnsFallbackAndRecordsOneDiagnostic() {
        let table = CopyTable()
        XCTAssertEqual(table.text("copy.sample.nope", fallback: "Plain"), "Plain")
        XCTAssertEqual(table.text("copy.sample.nope", fallback: "Plain"), "Plain")
        XCTAssertEqual(table.diagnostics, [.missingKey("copy.sample.nope")])
    }

    func testUnfilledPlaceholderIsRecorded() {
        let table = CopyTable()
        XCTAssertEqual(table.text("copy.sample.greeting", fallback: "?"), "Welcome home, {{name}}")
        XCTAssertEqual(table.diagnostics, [.unfilledPlaceholder(id: "copy.sample.greeting", name: "name")])
        XCTAssertEqual(table.diagnostics.first?.id, "copy.sample.greeting")
    }

    func testResourceBundleCarriesTheCompiledCatalog() {
        let value = Bundle.module.localizedString(forKey: "copy.sample.allClosed", value: "missing", table: CopyTable.tableName)
        XCTAssertEqual(value, "All Closed")
    }
}
