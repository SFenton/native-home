import Foundation
import Testing
@testable import HassCore

// MARK: - Fixed decimals, title case, list reads and the raw state

/// A reader over fixed reads and raw states.
private struct Reader: ServerUIReading {
    var reads: [String: ServerUIReadResult] = [:]
    var raw: [String: ServerUIReadResult] = [:]
    var isFlow = false
    var rawAsked: [String] = []

    func read(sourceId: String, path: [String]) -> ServerUIReadResult { reads[([sourceId] + path).joined(separator: "/")] ?? .unavailable }
    func readRaw(sourceId: String) -> ServerUIReadResult { raw[sourceId] ?? .unavailable }
    var viewer: ServerUIViewer? { nil }
    func viewerPersonState() -> ServerUIReadResult { .unavailable }
}

private let modes = "hvac/attributes/hvac_modes"
private func strings(_ items: String...) -> ServerUIReadResult { .value(.array(items.map { .string($0) })) }
private func text(_ value: String) -> ServerUIOperand { .literal(.string(value)) }

/// The decimals of a number hole (`sh.pipeline-operands@1`).
@Suite struct ServerUINumberFormatFixedDigitsTests {
    @Test func aMinimumKeepsTheZerosItNames() {
        let one = ServerUINumberFormat(maximumFractionDigits: 1, minimumFractionDigits: 1)
        #expect(one.text(72) == "72.0" && one.text(72.5) == "72.5" && one.text(72.04) == "72.0")
        let wide = ServerUINumberFormat(maximumFractionDigits: 3, minimumFractionDigits: 1)
        #expect(wide.text(72) == "72.0" && wide.text(72.5) == "72.5" && wide.text(72.1234) == "72.123" && wide.text(72.1) == "72.1")
        #expect(ServerUINumberFormat(maximumFractionDigits: 3).text(72.5) == "72.5" && ServerUINumberFormat(maximumFractionDigits: 3).text(72) == "72")
    }

    @Test func theExactBinaryValueIsRoundedAndATieGoesToTheEvenDigit() {
        let two = ServerUINumberFormat(maximumFractionDigits: 2)
        #expect(two.text(0.125) == "0.12" && two.text(0.375) == "0.38" && two.text(1.005) == "1")
        #expect(ServerUINumberFormat(maximumFractionDigits: 0).text(2.5) == "2" && ServerUINumberFormat(maximumFractionDigits: 0).text(3.5) == "4")
    }

    @Test func aSignedZeroLosesItsSign() {
        let one = ServerUINumberFormat(maximumFractionDigits: 1, minimumFractionDigits: 1)
        #expect(one.text(-0.04) == "0.0" && one.text(-0.0) == "0.0" && one.text(-0.6) == "-0.6")
        #expect(ServerUINumberFormat(maximumFractionDigits: 0).text(-0.4) == "0")
        #expect(ServerUINumberFormat(maximumFractionDigits: 2).text(-0.001) == "0")
    }

    @Test func theCountsAreClamped() {
        let format = ServerUINumberFormat(maximumFractionDigits: 9, minimumFractionDigits: 12)
        #expect(format.maximumFractionDigits == 6 && format.minimumFractionDigits == 6)
        let below = ServerUINumberFormat(maximumFractionDigits: 2, minimumFractionDigits: 5)
        #expect(below.minimumFractionDigits == 2)
        #expect(ServerUINumberFormat(maximumFractionDigits: -1, minimumFractionDigits: -3) == ServerUINumberFormat(maximumFractionDigits: 0))
    }
}

/// The title case of a text hole (`sh.pipeline-operands@1`).
@Suite struct ServerUITextCaseTests {
    @Test func onlyUnderscoreSeparatesWordsAndOnlyAnAsciiLetterChanges() {
        #expect(ServerUITextCase.title.apply(to: "armed_away") == "Armed Away")
        #expect(ServerUITextCase.title.apply(to: "heat cool") == "Heat cool")
        #expect(ServerUITextCase.title.apply(to: "heat") == "Heat")
        #expect(ServerUITextCase.title.apply(to: "Heat_COOL") == "Heat COOL")
        #expect(ServerUITextCase.title.apply(to: "école_été") == "école été")
        #expect(ServerUITextCase.title.apply(to: "3rd_floor") == "3rd Floor")
    }

    @Test func emptyPartsStayAndEmptyTextStaysEmpty() {
        #expect(ServerUITextCase.title.apply(to: "a__b") == "A  B")
        #expect(ServerUITextCase.title.apply(to: "_a") == " A")
        #expect(ServerUITextCase.title.apply(to: "").isEmpty)
    }

    @Test func itAgreesWithTheStatePhrasingForAsciiStates() {
        for state in ["armed_away", "heat_cool", "off", "on", "fan_only", "auto"] {
            #expect(ServerUITextCase.title.apply(to: state) == StateText.titleCase(state))
        }
    }

    @Test func aFormatHoleDrawsTheArgumentsText() {
        let operand = ServerUIOperand.format(pattern: "Mode: {m}, {n}", args: ["m": text("heat_cool"), "n": .literal(.number(72))],
                                             formats: ["m": .text(.title), "n": .text(.title)])
        #expect(operand.evaluate(Reader()) == .value(.string("Mode: Heat Cool, 72")))
        let gap = ServerUIOperand.format(pattern: "{m}", args: ["m": .literal(.null)], formats: ["m": .text(.title)])
        #expect(gap.evaluate(Reader()) == .unavailable)
    }
}

/// The parser of the new formats and operands.
@Suite struct ServerUIGrammar2ParserTests {
    private func parse(_ json: String, flow: Bool = false) throws -> (operand: ServerUIOperand?, parser: ServerUIExpressionParser) {
        var parser = ServerUIExpressionParser(flow: flow)
        let operand = parser.operand(try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)), at: "")
        return (operand, parser)
    }

    private func parseCondition(_ json: String) throws -> (predicate: ServerUIPredicate?, parser: ServerUIExpressionParser) {
        var parser = ServerUIExpressionParser()
        let predicate = parser.predicate(try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)), at: "")
        return (predicate, parser)
    }

    private func codes(_ parser: ServerUIExpressionParser) -> [String] { parser.issues.map { "\($0.code.rawValue) \($0.pointer)" } }

    private func format(_ spec: String, argument: String = #"{"type":"literal","value":"x"}"#) -> String {
        #"{"type":"format","pattern":"{t}","args":{"t":\#(argument)},"formats":{"t":\#(spec)}}"#
    }

    @Test func aMinimumNeedsPipelineOperandsAndAMaximumAloneDoesNot() throws {
        let fixed = try parse(format(#"{"number":{"maximumFractionDigits":3,"minimumFractionDigits":1}}"#, argument: #"{"type":"literal","value":72}"#))
        #expect(fixed.parser.issues.isEmpty && fixed.parser.needs == ["pipeline-operands"])
        #expect(fixed.operand == .format(pattern: "{t}", args: ["t": .literal(.number(72))],
                                         formats: ["t": .number(.init(maximumFractionDigits: 3, minimumFractionDigits: 1))]))
        let plain = try parse(format(#"{"number":{"maximumFractionDigits":3}}"#, argument: #"{"type":"literal","value":72}"#))
        #expect(plain.parser.issues.isEmpty && plain.parser.needs.isEmpty)
    }

    @Test func theCountsAreWholeNumbersFromZeroToSixAndTheMinimumNeverPassesTheMaximum() throws {
        let at = "/formats/t/number/"
        func number(_ body: String) throws -> [String] { try codes(parse(format(#"{"number":{\#(body)}}"#, argument: #"{"type":"literal","value":1}"#)).parser) }
        #expect(try number(#""maximumFractionDigits":2,"minimumFractionDigits":3"#) == ["invalid_combination \(at)minimumFractionDigits"])
        #expect(try number(#""maximumFractionDigits":2,"minimumFractionDigits":7"#) == ["limit_exceeded \(at)minimumFractionDigits"])
        #expect(try number(#""maximumFractionDigits":2,"minimumFractionDigits":-1"#) == ["limit_exceeded \(at)minimumFractionDigits"])
        #expect(try number(#""maximumFractionDigits":2,"minimumFractionDigits":0.5"#) == ["invalid_value \(at)minimumFractionDigits"])
        #expect(try number(#""maximumFractionDigits":2,"minimumFractionDigits":"1""#) == ["invalid_value \(at)minimumFractionDigits"])
        #expect(try number(#""maximumFractionDigits":7"#) == ["limit_exceeded \(at)maximumFractionDigits"])
        #expect(try number(#""maximumFractionDigits":1.5"#) == ["invalid_value \(at)maximumFractionDigits"])
        #expect(try number(#""minimumFractionDigits":1"#) == ["missing_required \(at)maximumFractionDigits"])
        #expect(try number(#""maximumFractionDigits":2,"locale":"en""#) == ["unknown_field \(at)locale"])
    }

    @Test func aTitleCaseSpecNeedsTextAndNamesItsCapability() throws {
        let good = try parse(format(#"{"text":{"case":"title"}}"#))
        #expect(good.parser.issues.isEmpty && good.parser.needs == ["pipeline-operands"])
        #expect(good.operand == .format(pattern: "{t}", args: ["t": text("x")], formats: ["t": .text(.title)]))
        #expect(try codes(parse(format(#"{"text":{"case":"title"}}"#, argument: #"{"type":"literal","value":3}"#)).parser) == ["binding_type /formats/t"])
        let unknown = try parse(format(#"{"text":{"case":"upper"}}"#))
        #expect(codes(unknown.parser) == ["unknown_variant /formats/t"])
        #expect(try codes(parse(format(#"{"text":{"case":"title","locale":"en"}}"#)).parser) == ["unknown_field /formats/t/text/locale"])
        #expect(try codes(parse(format(#"{"text":{}}"#)).parser) == ["missing_required /formats/t/text/case"])
    }

    @Test func oneArgumentHasOneFormat() throws {
        let both = try parse(format(#"{"text":{"case":"title"},"number":{"maximumFractionDigits":1}}"#))
        #expect(codes(both.parser) == ["unknown_variant /formats/t"])
        #expect(try codes(parse(format("{}")).parser) == ["unknown_variant /formats/t"])
        #expect(try codes(parse(format(#"{"date":{"style":"tiny"}}"#)).parser) == ["unknown_variant /formats/t"])
        #expect(try codes(parse(format(#"{"mood":{}}"#)).parser) == ["unknown_variant /formats/t"])
    }

    @Test func rawStateIsATextReadOfASourceAndNothingElse() throws {
        let raw = try parse(#"{"type":"raw-state","sourceId":"sensor"}"#)
        #expect(raw.operand == .rawState(sourceId: "sensor") && raw.parser.issues.isEmpty && raw.parser.needs == ["raw-state"])
        #expect(raw.parser.references == [.init(sourceId: "sensor", path: ["state"], pointer: "", kind: nil, access: .raw)])
        #expect(try codes(parse(#"{"type":"raw-state","sourceId":"sensor","path":["state"]}"#).parser) == ["unknown_field /path"])
        #expect(try codes(parse(#"{"type":"raw-state"}"#).parser) == ["missing_required /sourceId"])
        #expect(try codes(parse(#"{"type":"raw-state","sourceId":"sensor"}"#, flow: true).parser) == ["invalid_combination "])
        #expect(ServerUIExpressionParser.kind(.rawState(sourceId: "a")) == .string)
    }

    @Test func aRawStateCompareIsCheckedForItsKind() throws {
        let number = try parseCondition(#"{"type":"compare","op":"eq","left":{"type":"raw-state","sourceId":"s"},"right":{"type":"literal","value":3}}"#)
        #expect(codes(number.parser) == ["binding_type /right"])
        let text = try parseCondition(#"{"type":"compare","op":"eq","left":{"type":"raw-state","sourceId":"s"},"right":{"type":"literal","value":"unknown"}}"#)
        #expect(text.parser.issues.isEmpty && text.parser.needs == ["conditions", "raw-state"])
    }

    @Test func listReadsNameOneAttributeAndAnIncludesNamesTheValue() throws {
        let from = #""from":{"type":"source","sourceId":"hvac","path":["attributes","hvac_modes"]}"#
        let count = try parse(#"{"type":"list-count",\#(from)}"#)
        #expect(count.operand == .listCount(sourceId: "hvac", path: ["attributes", "hvac_modes"]) && count.parser.needs == ["list-read"])
        #expect(count.parser.references == [.init(sourceId: "hvac", path: ["attributes", "hvac_modes"], pointer: "", kind: nil, access: .list)])
        let includes = try parse(#"{"type":"list-includes",\#(from),"value":{"type":"literal","value":"heat"}}"#)
        #expect(includes.operand == .listIncludes(sourceId: "hvac", path: ["attributes", "hvac_modes"], value: text("heat")))
        #expect(try codes(parse(#"{"type":"list-includes",\#(from)}"#).parser) == ["missing_required /value"])
        #expect(try codes(parse(#"{"type":"list-count",\#(from),"value":{"type":"literal","value":"a"}}"#).parser) == ["unknown_field /value"])
        #expect(try codes(parse(#"{"type":"list-includes",\#(from),"value":{"type":"list","items":[]}}"#).parser) == ["binding_type /value"])
        #expect(try codes(parse(#"{"type":"list-count",\#(from)}"#, flow: true).parser) == ["invalid_combination "])
        #expect(try codes(parse(#"{"type":"list-count","from":{"type":"source","sourceId":"hvac","path":[]}}"#).parser) == ["limit_exceeded /from/path"])
    }

    @Test func aListReadsKindsAreNumberAndBoolean() throws {
        let from = #""from":{"type":"source","sourceId":"hvac","path":["attributes","hvac_modes"]}"#
        let compare = try parseCondition(#"{"type":"compare","op":"eq","left":{"type":"list-count",\#(from)},"right":{"type":"literal","value":"two"}}"#)
        #expect(codes(compare.parser) == ["binding_type /right"])
        let includes = try parse(#"{"type":"list-includes",\#(from),"value":{"type":"literal","value":"heat"}}"#)
        #expect(includes.operand.flatMap(ServerUIExpressionParser.kind) == .boolean)
        #expect(includes.operand?.staticKind == .boolean && ServerUIOperand.listCount(sourceId: "a", path: []).staticKind == .number)
    }

    @Test func theNodeBudgetCountsTheValueOfAnIncludes() throws {
        var value = #"{"type":"literal","value":"a"}"#
        for _ in 0..<7 { value = #"{"type":"list","items":[\#(value)]}"# }
        let from = #""from":{"type":"source","sourceId":"hvac","path":["attributes","m"]}"#
        // The includes is depth one, so its value may nest seven more.
        #expect(try codes(parse(#"{"type":"list-includes",\#(from),"value":\#(value)}"#).parser).contains("limit_exceeded /value/items/0/items/0/items/0/items/0/items/0/items/0"))
    }
}

/// The evaluation of the three entity reads.
@Suite struct ServerUIEntityReadsTests {
    private let count = ServerUIOperand.listCount(sourceId: "hvac", path: ["attributes", "hvac_modes"])
    private func includes(_ value: ServerUIOperand) -> ServerUIOperand {
        .listIncludes(sourceId: "hvac", path: ["attributes", "hvac_modes"], value: value)
    }

    @Test func rawStateGivesTheStateTextAndUnknownAndUnavailableAreValues() {
        var reader = Reader()
        reader.raw = ["a": .value(.string("unknown")), "b": .value(.string("unavailable")), "c": .loading, "d": .value(.number(3))]
        #expect(ServerUIOperand.rawState(sourceId: "a").evaluate(reader) == .value(.string("unknown")))
        #expect(ServerUIOperand.rawState(sourceId: "b").evaluate(reader) == .value(.string("unavailable")))
        #expect(ServerUIOperand.rawState(sourceId: "c").evaluate(reader) == .loading)
        #expect(ServerUIOperand.rawState(sourceId: "d").evaluate(reader) == .unavailable)
        #expect(ServerUIOperand.rawState(sourceId: "none").evaluate(reader) == .unavailable)
    }

    @Test func aReaderWithoutARawReadSaysUnavailable() {
        struct Plain: ServerUIReading {
            func read(sourceId: String, path: [String]) -> ServerUIReadResult { .value(.string("on")) }
            var viewer: ServerUIViewer? { nil }
            func viewerPersonState() -> ServerUIReadResult { .unavailable }
        }
        #expect(ServerUIOperand.rawState(sourceId: "a").evaluate(Plain()) == .unavailable)
    }

    @Test func rawStateOfAnEntityBoxIsAValueWhateverItsState() {
        func entity(_ state: String) -> EntityState { EntityState(entityId: "sensor.x", state: state) }
        #expect(ServerUIReadResult.rawState(of: entity("unknown"), statesLoaded: true) == .value(.string("unknown")))
        #expect(ServerUIReadResult.rawState(of: entity("unavailable"), statesLoaded: true) == .value(.string("unavailable")))
        #expect(ServerUIReadResult.rawState(of: entity("72.5"), statesLoaded: true) == .value(.string("72.5")))
        #expect(ServerUIReadResult.rawState(of: nil, statesLoaded: true) == .unavailable)
        #expect(ServerUIReadResult.rawState(of: nil, statesLoaded: false) == .loading)
        #expect(ServerUIReadResult.rawState(of: entity("on"), statesLoaded: false) == .loading)
    }

    @Test func aFlowReadsNoneOfThemAndTheGapIsNull() {
        var reader = Reader(reads: [modes: strings("heat")], raw: ["s": .value(.string("on"))])
        reader.isFlow = true
        #expect(ServerUIOperand.rawState(sourceId: "s").evaluate(reader) == .value(.null))
        #expect(count.evaluate(reader) == .value(.null))
        #expect(includes(text("heat")).evaluate(reader) == .value(.null))
    }

    @Test func listCountCountsEveryItemAndNeedsAList() {
        #expect(count.evaluate(Reader(reads: [modes: strings("heat", "cool")])) == .value(.number(2)))
        #expect(count.evaluate(Reader(reads: [modes: .value(.array([.null, .array([]), .string("a")]))])) == .value(.number(3)))
        #expect(count.evaluate(Reader(reads: [modes: .value(.array([]))])) == .value(.number(0)))
        #expect(count.evaluate(Reader(reads: [modes: .value(.string("heat"))])) == .unavailable)
        #expect(count.evaluate(Reader()) == .unavailable)
        #expect(count.evaluate(Reader(reads: [modes: .loading])) == .loading)
    }

    @Test func listIncludesComparesScalarsByTheGrammarsEquality() {
        let reader = Reader(reads: [modes: .value(.array([.string("heat"), .number(2), .bool(true), .null, .array([.string("x")]),
                                                           .object([:]), .string("e\u{301}")]))])
        #expect(includes(text("heat")).evaluate(reader) == .value(.bool(true)))
        #expect(includes(text("Heat")).evaluate(reader) == .value(.bool(false)))
        #expect(includes(text("2")).evaluate(reader) == .value(.bool(true)))
        #expect(includes(.literal(.number(2))).evaluate(reader) == .value(.bool(true)))
        #expect(includes(text("true")).evaluate(reader) == .value(.bool(true)))
        #expect(includes(text("\u{E9}")).evaluate(reader) == .value(.bool(true)))
        #expect(includes(text("x")).evaluate(reader) == .value(.bool(false)))
        #expect(includes(.literal(.null)).evaluate(reader) == .unavailable)
        #expect(includes(.list([text("x")])).evaluate(reader) == .unavailable)
    }

    @Test func listIncludesWaitsForEitherPartAndLoadingOutranksUnavailable() {
        let want = ServerUIOperand.read(sourceId: "want", path: ["state"], as: .string)
        var reader = Reader(reads: [modes: strings("heat"), "want/state": .value(.string("heat"))])
        #expect(includes(want).evaluate(reader) == .value(.bool(true)))
        reader.reads["want/state"] = .loading
        #expect(includes(want).evaluate(reader) == .loading)
        reader.reads["want/state"] = .unavailable
        #expect(includes(want).evaluate(reader) == .unavailable)
        reader.reads[modes] = .loading
        #expect(includes(want).evaluate(reader) == .loading)
        #expect(includes(text("heat")).evaluate(Reader(reads: [modes: .value(.string("heat"))])) == .unavailable)
    }

    @Test func theOperandsReportWhatTheyTouch() {
        let want = ServerUIOperand.read(sourceId: "want", path: ["state"], as: .string)
        #expect(ServerUIOperand.rawState(sourceId: "a").sourceIds == ["a"])
        #expect(count.sourceIds == ["hvac"])
        #expect(includes(want).sourceIds == ["hvac", "want"])
        #expect(includes(.viewer(.userId)).readsViewer && !count.readsViewer && !ServerUIOperand.rawState(sourceId: "a").readsViewer)
        #expect(includes(.control).usesControl && !count.usesControl)
        #expect(includes(.clock(.today)).readsClock && !count.readsClock)
    }
}
