import Foundation
import Testing
@testable import HassCore

private struct House: ServerUIReading {
    var values: [String: JSONValue] = [:]
    var viewer: ServerUIViewer?
    var controlValue: JSONValue?
    func read(sourceId: String, path: [String]) -> ServerUIReadResult { values[sourceId].map { .value($0) } ?? .unavailable }
    func viewerPersonState() -> ServerUIReadResult { .unavailable }
}

private typealias Operand = ServerUIOperand
private let filler = Operand.literal(.number(1))

/// Every way an operand can hold another one, around `leaf`.
private func wrappers(around leaf: Operand) -> [(name: String, operand: Operand)] {
    [
        ("date-from", .date(from: leaf, to: filler)),
        ("date-to", .date(from: filler, to: leaf)),
        ("choose-then", .choose(cases: [.init(when: .exists(filler), then: leaf)], otherwise: filler)),
        ("choose-when", .choose(cases: [.init(when: .exists(leaf), then: filler)], otherwise: filler)),
        ("choose-otherwise", .choose(cases: [], otherwise: leaf)),
        ("format", .format(pattern: "{a}", args: ["a": leaf], formats: [:])),
        ("map-of", .map(of: leaf, cases: [], otherwise: filler)),
        ("map-then", .map(of: filler, cases: [.init(equals: .null, then: leaf)], otherwise: filler)),
        ("map-otherwise", .map(of: filler, cases: [], otherwise: leaf)),
        ("math", .math(.add, [filler, leaf])),
        ("list", .list([leaf])),
        ("object", .object(["k": leaf])),
    ]
}

/// Fails if: an operand nested in another is missed by the walk that tells the app which sources, viewer, control or clock to
/// watch, so a rule would never re-run when its data changes.
@Suite struct ServerUIOperandTreeTests {
    @Test func theSourcesAreFoundAtEveryDepth() {
        for (name, operand) in wrappers(around: .read(sourceId: "r", path: ["state"], as: .string)) {
            #expect(operand.sourceIds == ["r"], "\(name)")
        }
        #expect(filler.sourceIds.isEmpty)
    }

    @Test func theViewerIsFoundAtEveryDepth() {
        for (name, operand) in wrappers(around: .viewer(.userId)) { #expect(operand.readsViewer, "\(name)") }
        for (name, operand) in wrappers(around: filler) { #expect(!operand.readsViewer, "\(name)") }
    }

    @Test func theControlIsFoundAtEveryDepth() {
        for (name, operand) in wrappers(around: .control) where name != "choose-when" { #expect(operand.usesControl, "\(name)") }
        for (name, operand) in wrappers(around: filler) { #expect(!operand.usesControl, "\(name)") }
    }

    @Test func theClockIsFoundAtEveryDepth() {
        for (name, operand) in wrappers(around: .clock(.now)) { #expect(operand.readsClock, "\(name)") }
        for (name, operand) in wrappers(around: filler) { #expect(!operand.readsClock, "\(name)") }
    }

    @Test func eachViewerFactIsReadOrUnavailableAndNoViewerIsLoading() {
        let viewer = ServerUIViewer(userId: "u1", isAdmin: true, personEntityId: "person.demo_person_1")
        let known = House(viewer: viewer)
        #expect(Operand.viewer(.userId).evaluate(known) == .value(.string("u1")))
        #expect(Operand.viewer(.isAdmin).evaluate(known) == .value(.bool(true)))
        #expect(Operand.viewer(.personEntityId).evaluate(known) == .value(.string("person.demo_person_1")))
        let bare = House(viewer: ServerUIViewer())
        for field in Operand.ViewerField.allCases { #expect(Operand.viewer(field).evaluate(bare) == .unavailable) }
        #expect(Operand.viewer(.userId).evaluate(House()) == .loading)
    }

    @Test func aFormatDrawsHolesAndKeepsAnUnclosedBraceAsText() {
        let house = House(values: ["n": .number(2.75)])
        let n = Operand.read(sourceId: "n", path: [], as: .number)
        #expect(Operand.format(pattern: "a {n", args: ["n": n], formats: [:]).evaluate(house) == .value(.string("a {n")))
        #expect(Operand.format(pattern: "{n}!", args: ["n": n], formats: [:]).evaluate(house) == .value(.string("2.75!")))
        #expect(Operand.format(pattern: "{n}", args: ["n": n], formats: ["n": .number(.init(maximumFractionDigits: 0))]).evaluate(house)
                == .value(.string("3")))
        #expect(Operand.format(pattern: "{missing}", args: ["n": n], formats: [:]).evaluate(house) == .unavailable)
        let word = Operand.literal(.string("hello"))
        #expect(Operand.format(pattern: "{w}", args: ["w": word], formats: ["w": .number(.init(maximumFractionDigits: 2))]).evaluate(house)
                == .value(.string("hello")), "a non-number keeps its plain text under a number format")
    }

    @Test func aNumberFormatDropsTrailingZerosAndTheDotAndNeverDrawsMinusZero() {
        let format = ServerUINumberFormat(maximumFractionDigits: 2)
        #expect(format.text(2) == "2")
        #expect(format.text(2.5) == "2.5")
        #expect(format.text(-0.001) == "0")
        #expect(ServerUINumberFormat(maximumFractionDigits: 99).maximumFractionDigits == 6)
    }

    @Test func aReadIsCoercedToTheKindAskedFor() {
        let house = House(values: ["s": .string("7"), "t": .string("true"), "f": .string("false"), "x": .string("maybe"),
                                   "e": .string("light.kitchen"), "bad": .string("Light Kitchen"), "n": .number(.infinity)])
        func read(_ id: String, _ kind: ServerUICompositionDocument.ScalarKind) -> ServerUIReadResult {
            Operand.read(sourceId: id, path: [], as: kind).evaluate(house)
        }
        #expect(read("s", .number) == .value(.number(7)))
        #expect(read("t", .boolean) == .value(.bool(true)))
        #expect(read("f", .boolean) == .value(.bool(false)))
        #expect(read("x", .boolean) == .unavailable)
        #expect(read("e", .entityID) == .value(.string("light.kitchen")))
        #expect(read("bad", .entityID) == .unavailable)
        #expect(read("n", .number) == .unavailable)
        #expect(read("s", .boolean) == .unavailable)
    }

    @Test func aScalarMatchesItsTextForm() {
        #expect(Operand.matches(.number(3), .string("3")))
        #expect(Operand.matches(.bool(true), .string("true")))
        #expect(!Operand.matches(.bool(false), .string("true")))
        #expect(!Operand.matches(.array([]), .string("x")))
        #expect(Operand.scalarText(.number(1.5)) == "1.5")
        #expect(Operand.scalarText(.null) == nil)
    }
}
