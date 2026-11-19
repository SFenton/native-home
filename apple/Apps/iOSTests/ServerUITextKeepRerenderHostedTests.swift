import HassCore
import UIKit
import XCTest
@testable import HassUI

/// Kept text survives a draw again (`sh.text-keep@1`, T-text-keep): a slot answered, gone unavailable and then drawn again (a publication
/// update, a Dynamic Type change) still draws what it was last answered with, on the hosts that own their memory on the retained node.
@MainActor
final class ServerUITextKeepRerenderHostedTests: XCTestCase {
    private typealias F = ServerUIChartFixture

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private static func entity(_ state: String) -> EntityState { EntityState(entityId: "sensor.demo_bath_temperature", state: state, attributes: [:]) }

    /// The demo sensor's state as text, kept while it is unavailable.
    private static let keeps: JSONValue = .object([
        "type": .string("read"),
        "from": .object(["type": .string("source"), "sourceId": .string("temp"), "path": .array([.string("state")])]),
        "as": .string("string"), "missing": .string("unavailable"), "whenUnavailable": .string("keep"), "fallback": .string("No reading")
    ])

    private func labels(in view: UIView) -> [String] { F.all(UILabel.self, in: view).compactMap(\.text) }

    /// Answers, goes unavailable, then draws the page again by a publication update and by a Dynamic Type change.
    private func drawAgain(_ shown: F, check: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) throws {
        try check()
        shown.store.apply([Self.entity("unavailable")])
        shown.settle()
        try check()
        shown.page.update(shown.page.definition, inheritedGroups: [], close: nil)
        shown.settle()
        try check()
        shown.window.traitOverrides.preferredContentSizeCategory = .accessibilityLarge
        shown.settle()
        try check()
    }

    /// An info box's message keeps the temperature it was last given.
    func testInfoBoxKeepsItsMessageWhenDrawnAgain() throws {
        let box: JSONValue = .object(["id": .string("notice"), "title": .string("Notice"), "layout": .object(["span": .number(1)]),
                                      "type": .string("info-box"),
                                      "props": .object(["message": Self.keeps, "tone": .string("neutral"), "unavailableText": .string("Unavailable")])])
        let shown = try F.show("list-parts-row-action", width: 390, entities: [Self.entity("21.5")], adding: ["sh.info-box@1", "sh.text-keep@1"],
                                removing: ["sh.list-parts@1", "sh.operands@1", "sh.row-collection@1"]) { _ in [box] }
        defer { shown.window.isHidden = true }
        let view = try XCTUnwrap(shown.page.nodes["notice"]?.view)
        try drawAgain(shown) {
            XCTAssertTrue(labels(in: view).contains("21.5"), "drew \(labels(in: view))")
            XCTAssertFalse(labels(in: view).contains("No reading"))
        }
    }

    /// A dial's centre line keeps its text.
    func testDialCentreLineKeepsItsTextWhenDrawnAgain() throws {
        let shown = try F.show("dial-center-text", width: 390, entities: [Self.entity("1013")], adding: ["sh.rules@1", "sh.text-keep@1"]) { components in
            guard case .object(var dial)? = components.first, case .object(var props)? = dial["props"], case .array(var lines)? = props["center"],
                  case .object(var line)? = lines.first else { return components }
            line["value"] = Self.keeps
            lines[0] = .object(line)
            props["center"] = .array(lines)
            dial["props"] = .object(props)
            return [.object(dial)]
        }
        defer { shown.window.isHidden = true }
        let view = try XCTUnwrap(shown.page.nodes["d"]?.view as? UKDialView)
        try drawAgain(shown) {
            XCTAssertEqual(view.centerLines.first?.accessibilityLabel, "1013")
        }
    }

    /// A collection's empty message keeps its text.
    func testCollectionEmptyMessageKeepsItsTextWhenDrawnAgain() throws {
        let shown = try F.show("list-parts-row-action", width: 390, entities: [Self.entity("21.5")], records: [], adding: ["sh.text-keep@1"], removing: ["sh.operands@1"]) { components in
            F.setting(["providerId"], to: .string("records-flow"), in: F.setting(["emptyMessage"], to: Self.keeps, in: components))
        }
        defer { shown.window.isHidden = true }
        let view = try XCTUnwrap(shown.page.nodes["rows"]?.view)
        try drawAgain(shown) {
            XCTAssertTrue(labels(in: view).contains("21.5"), "drew \(labels(in: view))")
        }
    }
}
