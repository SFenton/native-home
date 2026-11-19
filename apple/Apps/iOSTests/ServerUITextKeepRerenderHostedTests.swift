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
    private func drawAgain(_ shown: F, gone: EntityState = entity("unavailable"), check: () throws -> Void,
                           file: StaticString = #filePath, line: UInt = #line) throws {
        try check()
        shown.store.apply([gone])
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

    /// A state tile's button label keeps the words it was last answered with: spoken by VoiceOver and held in the node's layout memory.
    func testStateTileDiscLabelKeepsItsWordsWhenDrawnAgain() throws {
        let robot = EntityState(entityId: "vacuum.demo_robot", state: "Pause", attributes: [:])
        let label: JSONValue = .object([
            "type": .string("read"),
            "from": .object(["type": .string("source"), "sourceId": .string("robot"), "path": .array([.string("state")])]),
            "as": .string("string"), "missing": .string("unavailable"), "whenUnavailable": .string("keep"), "fallback": .string("Start")
        ])
        let shown = try F.show("parts-disc-label-by-expression", width: 390, entities: [robot], adding: ["sh.text-keep@1"]) { components in
            guard case .object(var tile)? = components.first, case .object(var props)? = tile["props"], case .array(var discs)? = props["discs"],
                  case .object(var disc)? = discs.first else { return components }
            disc["label"] = label
            discs[0] = .object(disc)
            props["discs"] = .array(discs)
            tile["props"] = .object(props)
            return [.object(tile)]
        }
        defer { shown.window.isHidden = true }
        let node = try XCTUnwrap(shown.page.nodes["main-floor"])
        let view = try XCTUnwrap(node.view)
        try drawAgain(shown, gone: EntityState(entityId: "vacuum.demo_robot", state: "unavailable", attributes: [:])) {
            XCTAssertEqual(node.layoutMemory.discLabelText["start-pause"]?.answered, "Pause", "the disc's memory holds the answer")
            XCTAssertTrue(Self.spoken(in: view).contains("Pause"), "spoke \(Self.spoken(in: view))")
            XCTAssertFalse(Self.spoken(in: view).contains("Start"), "the fallback is for before an answer")
        }
    }

    /// A dial's spoken value (an accessibility slot) keeps the words it was last answered with.
    func testSpokenValueKeepsItsWordsWhenDrawnAgain() throws {
        let shown = try F.show("dial-a11y-value", width: 390, entities: [Self.entity("steady")], adding: ["sh.text-keep@1", "sh.rules@1"]) { components in
            F.setting(["value"], to: Self.keeps, in: components, under: "a11y")
        }
        defer { shown.window.isHidden = true }
        let view = try XCTUnwrap(shown.page.nodes["d"]?.view as? UKDialView)
        try drawAgain(shown) {
            XCTAssertEqual(view.accessibilityLabel, "Level")
            XCTAssertEqual(view.accessibilityValue, "steady", "spoke \(view.accessibilityValue ?? "nil")")
        }
    }

    /// Every label, title and accessibility name under `view`.
    private static func spoken(in view: UIView) -> [String] {
        var words = [view.accessibilityLabel, view.accessibilityValue].compactMap { $0 }
        words += (view as? UILabel).flatMap(\.text).map { [$0] } ?? []
        words += (view.accessibilityCustomActions ?? []).map(\.name)
        return words + view.subviews.flatMap { spoken(in: $0) }
    }
}
