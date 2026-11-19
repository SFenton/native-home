import Foundation
import Testing
@testable import HassCore

// MARK: - Stack arrangement

/// The arrangement rule of a `stack` (`sh.stack@1`): the Studio's 17 `stack-reflow-*` evaluation cases are the oracle, run through
/// ``ServerUIExpressionCorpusTests``; the cases here pin what those do not name.
@Suite(.timeLimit(.minutes(2)))
struct ServerUIStackLayoutTests {
    typealias D = ServerUICompositionDocument

    // MARK: Corpus adapter

    private static func space(_ json: JSONValue?) throws -> D.Space {
        guard let json else { throw ServerUICompositionError(.missingRequired, "") }
        if json["type"]?.string == "points" { return .points(json["value"]?.number ?? 0) }
        return .token(try #require(D.SpaceToken(rawValue: json["name"]?.string ?? "")))
    }

    private static func group(_ json: JSONValue) throws -> ServerUIStack.Group {
        try .init(children: (json["children"]?.array ?? []).compactMap(\.string),
                  spacing: json["spacing"] == nil ? nil : space(json["spacing"]),
                  distribution: ServerUIStack.Distribution(rawValue: json["distribution"]?.string ?? "") ?? .natural,
                  align: ServerUIStack.Align(rawValue: json["align"]?.string ?? "") ?? .start, grow: json["grow"]?.bool ?? false)
    }

    private static func input(_ subject: JSONValue) throws -> ServerUIStackLayout.Input {
        let props = try #require(subject["props"])
        var collapse: ServerUIStack.Collapse?
        if let rule = props["collapse"] {
            collapse = try .init(when: (rule["when"]?.array ?? []).compactMap { $0.string.flatMap(ServerUIStack.Trigger.init(rawValue:)) },
                                 fits: (rule["fits"]?.array ?? []).compactMap(\.string),
                                 spacing: rule["spacing"] == nil ? nil : space(rule["spacing"]),
                                 groups: rule["groups"]?.array.map { try $0.map(group) })
        }
        return try .init(axis: ServerUIStack.Axis(rawValue: props["axis"]?.string ?? "") ?? .horizontal, spacing: space(props["spacing"]),
                         groups: props["groups"]?.array.map { try $0.map(group) }, collapse: collapse,
                         children: (subject["children"]?.array ?? []).map {
                             .init(id: $0["id"]?.string ?? "", width: $0["width"]?.number ?? 0, shrinks: $0["shrinks"]?.bool ?? false)
                         },
                         width: subject["width"]?.number ?? 0, accessibilitySize: subject["accessibilitySize"]?.bool ?? false)
    }

    /// The answer in the shape the Studio's evaluation files record: `{"stack": {collapsed, reason, axis, spacing, groups}}`.
    static func answer(_ subject: JSONValue) throws -> JSONValue {
        let result = ServerUIStackLayout.arrange(try input(subject))
        let groups: [JSONValue] = result.groups.map {
            .object(["children": .array($0.children.map(JSONValue.string)), "spacing": .number($0.spacing),
                     "distribution": .string($0.distribution.rawValue), "align": .string($0.align.rawValue), "grow": .bool($0.grow)])
        }
        return .object(["stack": .object([
            "collapsed": .bool(result.collapsed), "reason": result.reason.map { .string($0.rawValue) } ?? .null,
            "axis": .string(result.axis.rawValue), "spacing": .number(result.spacing), "groups": .array(groups)
        ])])
    }

    @Test func theCorpusHoldsTheNineteenReflowCases() {
        let reflow = ServerUIExpressionCorpusTests.cases.filter { $0.name.hasPrefix("stack-reflow-") }
        #expect(reflow.count == 19)
    }

    // MARK: Arrangement

    private let header = ServerUIStackLayout.Input(
        axis: .horizontal, spacing: .token(.m),
        groups: [.init(children: ["glyph", "condition", "range"], spacing: .token(.xs), grow: true), .init(children: ["numeral"])],
        collapse: .init(when: [.accessibilitySize, .overflow], fits: ["range"], spacing: .token(.s), groups: [
            .init(children: ["glyph", "numeral"], distribution: .spread, align: .center), .init(children: ["condition"]), .init(children: ["range"])
        ]),
        children: [.init(id: "glyph", width: 40), .init(id: "condition", width: 320, shrinks: true), .init(id: "range", width: 200),
                   .init(id: "numeral", width: 88)],
        width: 300, accessibilitySize: false)

    @Test func theHeaderFitsBesideTheNumeralAtTheDefaultTextSize() {
        let result = ServerUIStackLayout.arrange(header)
        #expect(!result.collapsed)
        #expect(result.axis == .horizontal)
        #expect(result.groups.map(\.children) == [["glyph", "condition", "range"], ["numeral"]])
    }

    @Test func anAccessibilitySizeNamesItselfBeforeTheOverflow() {
        var input = header
        input.accessibilitySize = true
        input.width = 100
        let result = ServerUIStackLayout.arrange(input)
        #expect(result.collapsed)
        #expect(result.reason == .accessibilitySize)
        #expect(result.axis == .vertical)
        #expect(result.spacing == 8)
        #expect(result.groups.map(\.children) == [["glyph", "numeral"], ["condition"], ["range"]])
        #expect(result.groups.first?.distribution == .spread)
    }

    @Test func aColumnNeverCollapses() {
        var input = header
        input.axis = .vertical
        input.accessibilitySize = true
        #expect(!ServerUIStackLayout.arrange(input).collapsed)
    }

    @Test func childrenWithoutGroupsEachMakeOne() {
        let result = ServerUIStackLayout.arrange(.init(axis: .vertical, spacing: .points(6), children: [.init(id: "a", width: 1), .init(id: "b", width: 2)],
                                                       width: 10, accessibilitySize: false))
        #expect(result.groups.map(\.children) == [["a"], ["b"]])
        #expect(result.groups.map(\.spacing) == [6, 6])
    }

    @Test func aNamedChildThatIsNotDrawnCountsNothing() {
        var input = header
        input.children = input.children.map { $0.id == "range" ? .init(id: "range", width: 0) : $0 }
        input.width = 1
        #expect(!ServerUIStackLayout.overflows(input), "every named width is 0, so there is nothing that must fit")
    }
}

// MARK: - Stack placement

/// Where the children of a stack go once the arrangement is chosen (`ServerUIStackPlacement`).
@Suite(.timeLimit(.minutes(2)))
struct ServerUIStackPlacementTests {
    typealias Item = ServerUIStackPlacement.Item

    private func arrange(_ groups: [ServerUIStack.Group], axis: ServerUIStack.Axis = .horizontal) -> ServerUIStackLayout.Result {
        ServerUIStackLayout.arrange(.init(axis: axis, spacing: .points(10), groups: groups,
                                          children: groups.flatMap(\.children).map { .init(id: $0, width: 10) }, width: 1_000, accessibilitySize: false))
    }

    @Test func aRowOfTwoColumnsPutsTheSecondAfterTheFirstWithTheSpacingBetween() {
        let layout = arrange([.init(children: ["a", "b"]), .init(children: ["c"])])
        let placed = ServerUIStackPlacement.place(layout, items: [.init(id: "a", width: 40), .init(id: "b", width: 60), .init(id: "c", width: 20)],
                                                  align: .start, distribution: .natural, dividerWidth: nil, width: 300) { _, _ in 10 }
        #expect(placed.frames["a"] == .init(x: 0, y: 0, width: 40, height: 10))
        #expect(placed.frames["b"] == .init(x: 0, y: 20, width: 60, height: 10))
        #expect(placed.frames["c"] == .init(x: 70, y: 0, width: 20, height: 10))
        #expect(placed.height == 30)
    }

    @Test func aGrowingGroupTakesWhatTheOthersLeave() {
        let layout = arrange([.init(children: ["a"], grow: true), .init(children: ["b"])])
        let placed = ServerUIStackPlacement.place(layout, items: [.init(id: "a", width: 40, fillsWidth: true), .init(id: "b", width: 50)],
                                                  align: .start, distribution: .natural, dividerWidth: nil, width: 300) { _, _ in 10 }
        #expect(placed.frames["a"]?.width == 240)
        #expect(placed.frames["b"]?.x == 250)
    }

    @Test func aGroupThatCanShrinkGivesRoomFirst() {
        let layout = arrange([.init(children: ["a"]), .init(children: ["b"])])
        let placed = ServerUIStackPlacement.place(layout, items: [.init(id: "a", width: 200, shrinks: true), .init(id: "b", width: 150)],
                                                  align: .start, distribution: .natural, dividerWidth: nil, width: 300) { _, _ in 10 }
        #expect(placed.frames["b"]?.width == 150)
        #expect(placed.frames["a"]?.width == 140)
    }

    @Test func spreadGroupsPutTheRoomBetweenThem() {
        let layout = arrange([.init(children: ["a"]), .init(children: ["b"])])
        let placed = ServerUIStackPlacement.place(layout, items: [.init(id: "a", width: 40), .init(id: "b", width: 40)],
                                                  align: .center, distribution: .spread, dividerWidth: 1, width: 300) { _, _ in 10 }
        #expect(placed.frames["a"]?.x == 0)
        #expect(placed.frames["b"]?.x == 260)
        #expect(placed.dividers.count == 1)
    }

    @Test func aCollapsedStackStacksItsRowsAndSpreadsAGroup() {
        let layout = arrange([.init(children: ["a", "b"], distribution: .spread, align: .center), .init(children: ["c"])], axis: .vertical)
        let placed = ServerUIStackPlacement.place(layout, items: [.init(id: "a", width: 40), .init(id: "b", width: 60), .init(id: "c", width: 20)],
                                                  align: .start, distribution: .natural, dividerWidth: 2, width: 300) { id, _ in id == "a" ? 20 : 10 }
        #expect(placed.frames["a"] == .init(x: 0, y: 0, width: 40, height: 20))
        #expect(placed.frames["b"] == .init(x: 240, y: 5, width: 60, height: 10))
        #expect(placed.frames["c"]?.y == 42.0)
        #expect(placed.dividers == [.init(x: 0, y: 30, width: 300, height: 2)])
    }

    @Test func nothingShownPlacesNothing() {
        let layout = arrange([.init(children: ["a"])])
        let placed = ServerUIStackPlacement.place(layout, items: [], align: .start, distribution: .natural, dividerWidth: nil, width: 100) { _, _ in 1 }
        #expect(placed == .init())
    }
}
