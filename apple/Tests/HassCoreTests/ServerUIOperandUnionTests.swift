import Foundation
import Testing
@testable import HassCore

// MARK: - The operand union and the condition leaves

/// A reader over fixed values for the flow, clock and condition cases.
private struct Reader: ServerUIReading {
    var values: [String: JSONValue] = [:]
    var loading: Set<String> = []
    var viewer: ServerUIViewer?
    var clock: ServerUIClock?
    var item: JSONValue?
    var parameters: [String: JSONValue] = [:]
    var isFlow = false
    var locale: Locale?
    var spent = SpendCounter()

    final class SpendCounter: @unchecked Sendable { var count = 0 }

    func read(sourceId: String, path: [String]) -> ServerUIReadResult {
        if loading.contains(sourceId) { return .loading }
        return values[sourceId].map { .value($0) } ?? .unavailable
    }
    func viewerPersonState() -> ServerUIReadResult { .unavailable }
    func parameter(_ name: String) -> JSONValue? { parameters[name] }
    func spend() { spent.count += 1 }
}

private let noon = ServerUIClock(now: "2026-11-15T12:00:00", utcOffsetMinutes: -480)
private func text(_ value: String) -> ServerUIOperand { .literal(.string(value)) }
private func number(_ value: Double) -> ServerUIOperand { .literal(.number(value)) }
private func read(_ id: String, as kind: ServerUICompositionDocument.ScalarKind = .string) -> ServerUIOperand {
    .read(sourceId: id, path: ["state"], as: kind)
}

@Suite struct ServerUIOperandUnionEvaluationTests {
    @Test func itemReadsAPathOfTheStepsItemAndAMissingSegmentIsNull() {
        let reader = Reader(item: .object(["a": .object(["b": .number(7)])]))
        #expect(ServerUIOperand.item(path: ["a", "b"]).evaluate(reader) == .value(.number(7)))
        #expect(ServerUIOperand.item(path: ["a", "x"]).evaluate(reader) == .value(.null))
        #expect(ServerUIOperand.item(path: []).evaluate(reader) == .value(.object(["a": .object(["b": .number(7)])])))
        #expect(ServerUIOperand.item(path: ["a"]).evaluate(Reader()) == .unavailable)
    }

    @Test func paramIsTheFlowsValueOrUnavailable() {
        let reader = Reader(parameters: ["p": .string("x")])
        #expect(ServerUIOperand.param(name: "p").evaluate(reader) == .value(.string("x")))
        #expect(ServerUIOperand.param(name: "q").evaluate(reader) == .unavailable)
    }

    @Test func aFlowHasNoLoadingOrUnavailableOnlyNull() {
        var reader = Reader(loading: ["b"])
        reader.isFlow = true
        #expect(read("ghost").evaluate(reader) == .value(.null))
        #expect(read("b").evaluate(reader) == .value(.null))
        #expect(ServerUIOperand.list([read("ghost"), text("a")]).evaluate(reader) == .value(.array([.null, .string("a")])))
        #expect(ServerUIPredicate.compare(.above, left: read("ghost", as: .number), right: number(1)).evaluate(reader) == .no)
        #expect(ServerUIPredicate.exists(read("ghost")).evaluate(reader) == .no)
    }

    @Test func clockGivesTodayAndNowOrIsUnavailableWithoutOne() {
        var reader = Reader()
        #expect(ServerUIOperand.clock(.today).evaluate(reader) == .unavailable)
        reader.clock = noon
        #expect(ServerUIOperand.clock(.today).evaluate(reader) == .value(.string("2026-11-15")))
        #expect(ServerUIOperand.clock(.now).evaluate(reader) == .value(.string("2026-11-15T12:00:00")))
        reader.clock = ServerUIClock(now: "garbage", utcOffsetMinutes: 0)
        #expect(ServerUIOperand.clock(.today).evaluate(reader) == .unavailable)
    }

    @Test func dateMeasuresWholeCalendarDaysAndLoadingOutranksUnavailable() {
        let reader = Reader(values: ["a": .string("2026-11-10")], loading: ["b"], clock: noon)
        #expect(ServerUIOperand.date(from: read("a"), to: .clock(.today)).evaluate(reader) == .value(.number(5)))
        #expect(ServerUIOperand.date(from: text("2026-11-15"), to: text("2026-11-10")).evaluate(reader) == .value(.number(-5)))
        #expect(ServerUIOperand.date(from: text("nope"), to: text("2026-11-10")).evaluate(reader) == .unavailable)
        #expect(ServerUIOperand.date(from: number(1), to: text("2026-11-10")).evaluate(reader) == .unavailable)
        #expect(ServerUIOperand.date(from: read("b"), to: read("ghost")).evaluate(reader) == .loading)
    }

    @Test func chooseTakesTheFirstHoldingCaseAndAnUndecidedCaseStopsTheRule() {
        let hot = ServerUIPredicate.compare(.above, left: read("t", as: .number), right: number(75))
        let warm = ServerUIPredicate.compare(.above, left: read("t", as: .number), right: number(50))
        let rule = ServerUIOperand.choose(cases: [.init(when: hot, then: text("Hot")), .init(when: warm, then: text("Warm"))],
                                          otherwise: text("Fine"))
        #expect(rule.evaluate(Reader(values: ["t": .string("80")])) == .value(.string("Hot")))
        #expect(rule.evaluate(Reader(values: ["t": .string("60")])) == .value(.string("Warm")))
        #expect(rule.evaluate(Reader(values: ["t": .string("10")])) == .value(.string("Fine")))
        // Unknown is loading: the slot keeps what it showed, and no later case stands in for the undecided one.
        #expect(rule.evaluate(Reader()) == .loading)
        #expect(rule.evaluate(Reader(loading: ["t"])) == .loading)
        #expect(rule.sourceIds == ["t"])
    }

    @Test func mapOfNullIsUnavailable() {
        let map = ServerUIOperand.map(of: .item(path: ["x"]), cases: [.init(equals: .string("a"), then: text("A"))], otherwise: text("none"))
        #expect(map.evaluate(Reader(item: .object(["x": .string("a")]))) == .value(.string("A")))
        #expect(map.evaluate(Reader(item: .object([:]))) == .unavailable)
    }

    @Test func formatDrawsADateInAStyleOrIsUnavailable() {
        let reader = Reader(values: ["d": .string("2026-11-12T09:41:00"), "n": .number(3)], clock: noon)
        func format(_ style: ServerUIDateStyle, _ source: String = "d") -> ServerUIOperand {
            .format(pattern: "On {d}", args: ["d": read(source)], formats: ["d": .date(style)])
        }
        #expect(format(.weekdayDate).evaluate(reader) == .value(.string("On Thu, Nov 12")))
        #expect(format(.dateTime).evaluate(reader) == .value(.string("On Nov 12 at 9:41 AM")))
        #expect(format(.relative).evaluate(reader) == .value(.string("On 3 days ago")))
        #expect(format(.dateTime, "n").evaluate(reader) == .unavailable)
        // The three styles that ask what today is have no text without a clock; the others do.
        var clockless = reader
        clockless.clock = nil
        #expect(format(.shortDate).evaluate(clockless) == .unavailable)
        #expect(format(.time).evaluate(clockless) == .value(.string("On 9:41 AM")))
        // A hole of an unknown kind (a null) has no text.
        #expect(ServerUIOperand.format(pattern: "{a}", args: ["a": .literal(.null)], formats: [:]).evaluate(reader) == .unavailable)
    }

    @Test func readsClockIsTrueOnlyWhereAClockIsRead() {
        #expect(ServerUIOperand.clock(.now).readsClock)
        #expect(ServerUIOperand.choose(cases: [.init(when: .exists(.clock(.today)), then: text("a"))], otherwise: text("b")).readsClock)
        #expect(!ServerUIOperand.date(from: text("2026-01-01"), to: text("2026-01-02")).readsClock)
        #expect(ServerUIOperand.format(pattern: "{d}", args: ["d": text("2026-01-01")], formats: ["d": .date(.relative)]).readsClock)
        #expect(!ServerUIOperand.format(pattern: "{d}", args: ["d": text("2026-01-01")], formats: ["d": .date(.longDate)]).readsClock)
        #expect(!ServerUIPredicate.compare(.eq, left: text("a"), right: text("b")).readsClock)
    }

    @Test func everyEvaluatedNodeIsSpentOnce() {
        let reader = Reader()
        _ = ServerUIPredicate.all([.exists(text("a")), .compare(.eq, left: text("a"), right: text("a"))]).evaluate(reader)
        // all + exists + literal + compare + literal + literal
        #expect(reader.spent.count == 6)
    }
}

@Suite struct ServerUIPredicateLeafTests {
    @Test func compareEqualsByValueAndTextByCanonicalEquivalence() {
        let reader = Reader()
        #expect(ServerUIPredicate.compare(.eq, left: number(1), right: text("1")).evaluate(reader) == .yes)
        #expect(ServerUIPredicate.compare(.eq, left: text("\u{65}\u{301}"), right: text("\u{E9}")).evaluate(reader) == .yes)
        #expect(ServerUIPredicate.compare(.ne, left: .literal(.null), right: text("a")).evaluate(reader) == .no)
        #expect(ServerUIPredicate.compare(.eq, left: .literal(.array([.number(1)])), right: .literal(.array([.number(1)]))).evaluate(reader) == .no)
    }

    @Test func aboveAndBelowTakeNumbersOnlyAndBeforeAndAfterTakeDatesOnTheClocksOffset() {
        let reader = Reader(clock: noon)
        #expect(ServerUIPredicate.compare(.above, left: text("3"), right: number(2)).evaluate(reader) == .no)
        #expect(ServerUIPredicate.compare(.below, left: number(1), right: number(2)).evaluate(reader) == .yes)
        // 23:00 at +02:00 is 21:00 UTC, so it is not after 22:00 UTC.
        #expect(ServerUIPredicate.compare(.after, left: text("2026-11-15T23:00:00+02:00"), right: text("2026-11-15T22:00:00Z"))
            .evaluate(reader) == .no)
        #expect(ServerUIPredicate.compare(.before, left: .clock(.today), right: text("2026-12-01")).evaluate(reader) == .yes)
        #expect(ServerUIPredicate.compare(.before, left: text("not a date"), right: text("2026-12-01")).evaluate(reader) == .no)
    }

    @Test func anOperandThatCannotBeAnsweredMakesALeafUnknownButAValueOfTheWrongKindIsNo() {
        let reader = Reader(values: ["w": .string("warm")], loading: ["l"])
        #expect(ServerUIPredicate.compare(.above, left: read("ghost", as: .number), right: number(1)).evaluate(reader) == .unknown)
        #expect(ServerUIPredicate.compare(.eq, left: read("l"), right: text("a")).evaluate(reader) == .unknown)
        #expect(ServerUIPredicate.compare(.above, left: read("w"), right: number(1)).evaluate(reader) == .no)
    }

    @Test func inMatchesBeatAnUnavailableOptionAndAnUnavailableOptionKeepsNoUnknown() {
        let reader = Reader()
        let options: [ServerUIOperand] = [text("off"), read("ghost")]
        #expect(ServerUIPredicate.in(value: text("off"), options: options).evaluate(reader) == .yes)
        #expect(ServerUIPredicate.in(value: text("x"), options: options).evaluate(reader) == .unknown)
        #expect(ServerUIPredicate.in(value: text("x"), options: [text("off")]).evaluate(reader) == .no)
        #expect(ServerUIPredicate.in(value: read("ghost"), options: [text("off")]).evaluate(reader) == .unknown)
        #expect(ServerUIPredicate.in(value: .literal(.array([])), options: [text("off")]).evaluate(reader) == .no)
    }

    @Test func existsIsUnknownForAGapNoForNullAndYesForAValue() {
        let reader = Reader(values: ["a": .string("on")])
        #expect(ServerUIPredicate.exists(read("a")).evaluate(reader) == .yes)
        #expect(ServerUIPredicate.exists(.literal(.null)).evaluate(reader) == .no)
        #expect(ServerUIPredicate.exists(read("ghost")).evaluate(reader) == .unknown)
    }

    @Test func combinatorsFollowKleeneLogic() {
        let reader = Reader()
        let unknown = ServerUIPredicate.exists(read("ghost"))
        let yes = ServerUIPredicate.exists(text("a")), no = ServerUIPredicate.exists(.literal(.null))
        #expect(ServerUIPredicate.all([unknown, no]).evaluate(reader) == .no)
        #expect(ServerUIPredicate.all([unknown, yes]).evaluate(reader) == .unknown)
        #expect(ServerUIPredicate.any([unknown, yes]).evaluate(reader) == .yes)
        #expect(ServerUIPredicate.not(unknown).evaluate(reader) == .unknown)
    }
}

@Suite struct ServerUIRuleTests {
    @Test func theFirstHoldingCaseIsPickedAndAnUndecidedOneStopsTheRule() {
        func pick(_ answers: [ServerUITri]) -> ServerUIRulePick { ServerUIRule.pick(count: answers.count) { answers[$0] } }
        #expect(pick([.no, .yes, .yes]) == .matched(1))
        #expect(pick([.no, .no]) == .otherwise)
        #expect(pick([]) == .otherwise)
        // An unknown case before a holding one stalls the rule: nothing later may stand in for it.
        #expect(pick([.unknown, .yes]) == .stalled)
        #expect(pick([.no, .unknown]) == .stalled)
        #expect(pick([.yes, .unknown]) == .matched(0))
    }

    @Test func aStalledLookShowsOtherwiseAndATileFaceStaysFromTheStyle() {
        let rule = ServerUIConditional<String>(cases: [.init(when: .compare(.above, left: read("t", as: .number), right: number(1)), then: "hot")],
                                               otherwise: "fine")
        #expect(rule.resolve(Reader()) == "fine")
        #expect(rule.pick(Reader()) == .stalled)
        #expect(rule.resolve(Reader(values: ["t": .string("5")])) == "hot")
        let faces = ServerUIControlRules.tileFaces(active: rule.cases[0].when, filled: nil, error: nil, in: Reader())
        #expect(faces == ServerUITileFaces(active: nil, filled: nil, error: nil))
    }

    @Test func aReconnectNeverFlipsAKeepingControlOrSkipsAQuestion() {
        let gap = ServerUIPredicate.exists(read("ghost"))
        #expect(ServerUIControlRules.isEnabled(gap, whenUnknown: .keep, previous: false, in: Reader()) == false)
        #expect(ServerUIControlRules.isEnabled(gap, whenUnknown: .keep, previous: nil, in: Reader()))
        #expect(!ServerUIControlRules.isEnabled(gap, whenUnknown: .disabled, in: Reader()))
        #expect(ServerUIControlRules.isEnabled(nil, whenUnknown: .disabled, in: Reader()))
        #expect(ServerUIControlRules.asksFirst(gap, in: Reader()))
        #expect(!ServerUIControlRules.asksFirst(.exists(.literal(.null)), in: Reader()))
    }

    @Test func aTabContainerNeverDrawsNothing() {
        let hidden = ServerUIVisibility(predicate: .exists(.literal(.null)), whenUnknown: .hide)
        let tabs: [ServerUIControlRules.Tab] = [.init(id: "a", visibility: hidden), .init(id: "b", visibility: hidden)]
        #expect(ServerUIControlRules.tabOnShow(tabs, requested: "b", fallback: "a", in: Reader()) == "a")
        #expect(ServerUIControlRules.tabOnShow([], requested: nil, fallback: nil, in: Reader()) == nil)
    }
}

// MARK: - The parser of the new grammar

@Suite struct ServerUIOperandUnionParserTests {
    private func parse(_ json: String, flow: Bool = false) throws -> (operand: ServerUIOperand?, parser: ServerUIExpressionParser) {
        var parser = ServerUIExpressionParser(flow: flow)
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let operand = parser.operand(value, at: "")
        return (operand, parser)
    }

    private func parseCondition(_ json: String, flow: Bool = false) throws -> (predicate: ServerUIPredicate?, parser: ServerUIExpressionParser) {
        var parser = ServerUIExpressionParser(flow: flow)
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let predicate = parser.predicate(value, at: "")
        return (predicate, parser)
    }

    private func codes(_ parser: ServerUIExpressionParser) -> [String] { parser.issues.map { "\($0.code.rawValue) \($0.pointer)" } }

    @Test func eachNewOperandNamesTheCapabilityItNeeds() throws {
        let clock = try parse(#"{"type":"clock","part":"today"}"#)
        #expect(clock.operand == .clock(.today) && clock.parser.needs == ["pipeline-operands"] && clock.parser.issues.isEmpty)
        let choose = try parse(#"{"type":"choose","cases":[{"when":{"type":"exists","value":{"type":"literal","value":"a"}},"then":{"type":"literal","value":"x"}}],"otherwise":{"type":"literal","value":"y"}}"#)
        #expect(choose.parser.needs == ["rules", "conditions"] as Set && choose.parser.issues.isEmpty)
        let date = try parse(#"{"type":"date","op":"days-between","from":{"type":"clock","part":"today"},"to":{"type":"literal","value":"2026-12-25"}}"#)
        #expect(date.parser.needs == ["pipeline-operands"] && date.operand != nil)
    }

    @Test func itemAndParamStandOnlyInsideAFlowAndControlNeverDoes() throws {
        let item = #"{"type":"item","path":["a","b"]}"#
        #expect(try codes(parse(item).parser) == ["invalid_combination "])
        #expect(try parse(item, flow: true).parser.issues.isEmpty)
        #expect(try parse(item, flow: true).operand == .item(path: ["a", "b"]))
        #expect(try codes(parse(#"{"type":"param","name":"p"}"#).parser) == ["invalid_combination "])
        #expect(try parse(#"{"type":"param","name":"p"}"#, flow: true).operand == .param(name: "p"))
        #expect(try codes(parse(#"{"type":"param","name":"9bad"}"#, flow: true).parser) == ["invalid_value /name"])
        var parser = ServerUIExpressionParser(allowControl: true, flow: true)
        _ = parser.operand(.object(["type": .string("control")]), at: "")
        #expect(codes(parser) == ["invalid_combination "])
    }

    @Test func aRuleGivesOneKindAndTheMismatchIsReportedAtTheFirstBranchThatDiffers() throws {
        let issues = try parse(#"{"type":"choose","cases":[{"when":{"type":"exists","value":{"type":"literal","value":"a"}},"then":{"type":"literal","value":"x"}},{"when":{"type":"exists","value":{"type":"literal","value":"b"}},"then":{"type":"literal","value":3}}],"otherwise":{"type":"literal","value":"y"}}"#)
        #expect(codes(issues.parser) == ["binding_type /cases/1/then"])
    }

    @Test func aRulesConditionIsAtMostThirtyTwoNodesAndSixDeepButADocumentPredicateIsNot() throws {
        func chain(_ depth: Int) -> String {
            var json = #"{"type":"exists","value":{"type":"literal","value":"a"}}"#
            for _ in 0..<depth { json = #"{"type":"not","of":\#(json)}"# }
            return json
        }
        let rule: (String) -> String = {
            #"{"type":"choose","cases":[{"when":\#($0),"then":{"type":"literal","value":"x"}}],"otherwise":{"type":"literal","value":"y"}}"#
        }
        #expect(try parse(rule(chain(4))).parser.issues.isEmpty)
        #expect(try codes(parse(rule(chain(6))).parser).contains("limit_exceeded /cases/0/when/of/of/of/of/of/of"))
        // A document predicate keeps the shipped limits (depth 8), so six levels are fine there.
        #expect(try parseCondition(chain(6)).parser.issues.isEmpty)
        #expect(try !parseCondition(chain(9)).parser.issues.isEmpty)
    }

    @Test func theLeavesCheckKindsAndCounts() throws {
        #expect(try codes(parseCondition(#"{"type":"compare","op":"above","left":{"type":"literal","value":"a"},"right":{"type":"literal","value":1}}"#).parser)
            == ["binding_type /left"])
        #expect(try codes(parseCondition(#"{"type":"compare","op":"eq","left":{"type":"literal","value":1},"right":{"type":"literal","value":"a"}}"#).parser)
            == ["binding_type /right"])
        #expect(try codes(parseCondition(#"{"type":"compare","op":"sideways","left":{"type":"literal","value":1},"right":{"type":"literal","value":1}}"#).parser)
            == ["unknown_variant /op"])
        #expect(try codes(parseCondition(#"{"type":"in","value":{"type":"literal","value":1},"in":[]}"#).parser) == ["limit_exceeded /in"])
        #expect(try parseCondition(#"{"type":"exists","value":{"type":"literal","value":1}}"#).parser.needs == ["conditions"])
        #expect(try codes(parseCondition(#"{"type":"nonsense"}"#).parser) == ["unknown_variant /type"])
    }

    @Test func aDateStyleNeedsTextAndNamesItsCapability() throws {
        let bad = try parse(#"{"type":"format","pattern":"{d}","args":{"d":{"type":"literal","value":3}},"formats":{"d":{"date":{"style":"long-date"}}}}"#)
        #expect(codes(bad.parser) == ["binding_type /formats/d"] && bad.parser.needs == ["pipeline-operands"])
        let good = try parse(#"{"type":"format","pattern":"{d}","args":{"d":{"type":"literal","value":"2026-11-15"}},"formats":{"d":{"date":{"style":"relative"}}}}"#)
        #expect(good.parser.issues.isEmpty)
        #expect(good.operand == .format(pattern: "{d}", args: ["d": text("2026-11-15")], formats: ["d": .date(.relative)]))
        #expect(try !parse(#"{"type":"format","pattern":"{d}","args":{"d":{"type":"literal","value":"x"}},"formats":{"d":{"date":{"style":"tiny"}}}}"#)
            .parser.issues.isEmpty)
    }
}
