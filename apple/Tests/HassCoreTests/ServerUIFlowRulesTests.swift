import Foundation
import Testing
@testable import HassCore

// MARK: - The Data Flow rules the corpus does not name

/// The rules of a Data Flow that no shared corpus case reaches: how a step types over an input that is no list, how a parameter takes its declared
/// kind, the format and `progress` operands, what a flow says about the entities, sources, viewer and clock it reads, and what the decoder refuses.
///
/// A flow here is data, as in the corpus; most tests build it from a request, parameters and steps written as JSON so the failing rule is on the page.
@Suite(.timeLimit(.minutes(1)))
struct ServerUIFlowRulesTests {
    // MARK: Fixtures

    private static func json(_ text: String) -> JSONValue {
        (try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) ?? .null
    }

    private static let attribute = #"{"type": "entity-attribute", "entityId": {"type": "literal", "value": "sensor.demo_case"}, "path": ["value"], "responseShape": SHAPE}"#
    private static let list = #"{"kind": "array", "of": {"kind": "object", "fields": {"t": {"shape": {"kind": "number"}}}}}"#

    /// The inputs of a flow.
    private static func inputs(request: String = attribute.replacingOccurrences(of: "SHAPE", with: list), parameters: String = "[]", steps: String = "[]",
                               output: String = #"{"kind": "scalar"}"#, schema: String = #"{"kind": "number"}"#, extra: String = "") -> JSONValue {
        json("""
        {"title": "Case", "parameters": \(parameters), "request": \(request), "steps": \(steps), "output": \(output), "schema": \(schema)\(extra)}
        """)
    }

    private static func decode(_ inputs: JSONValue) -> ServerUIFlowDecoder.Result { ServerUIFlowDecoder.decode(inputs, at: "") }

    private static func flow(_ inputs: JSONValue) throws -> ServerUIFlow {
        let decoded = decode(inputs)
        try #require(decoded.issues.isEmpty, "decode issues \(decoded.issues)")
        return try #require(decoded.flow)
    }

    /// A flow that gives one operand, so the operand's rules are the whole test.
    private static func operandFlow(_ operand: String, parameters: String = "[]", schema: String = #"{"kind": "string"}"#) -> JSONValue {
        inputs(request: #"{"type": "none", "value": \#(operand)}"#, parameters: parameters, schema: schema)
    }

    private static func codes(_ inputs: JSONValue) throws -> [ServerUICompositionError.Code] {
        ServerUIFlowCompiler.check(try #require(decode(inputs).flow), at: "").issues.map(\.code)
    }

    private static func run(_ inputs: JSONValue, response: JSONValue = .null, context: ServerUIFlowContext = ServerUIFlowContext()) throws -> JSONValue {
        let run = ServerUIFlowEvaluator.run(try #require(decode(inputs).flow), response: response, context: context)
        try #require(run.status == .ok)
        return run.output
    }

    /// What the last step left, before the output kind narrows it (a scalar output gives a list as null).
    private static func value(_ inputs: JSONValue, response: JSONValue) throws -> JSONValue {
        let run = ServerUIFlowEvaluator.run(try #require(decode(inputs).flow), response: response, context: ServerUIFlowContext())
        try #require(run.status == .ok)
        return run.value
    }

    private static let item = #"{"type": "item", "path": ["t"]}"#

    // MARK: Steps over an input that is no list

    @Test(arguments: [
        #"{"id": "s", "op": "sort", "by": [{"value": {"type": "item", "path": ["t"]}, "direction": "ascending", "kind": "number"}]}"#,
        #"{"id": "s", "op": "group", "by": {"type": "item", "path": ["t"]}}"#,
        #"{"id": "s", "op": "sum", "value": {"type": "item", "path": ["t"]}}"#,
        #"{"id": "s", "op": "min", "value": {"type": "item", "path": ["t"]}}"#,
        #"{"id": "s", "op": "max", "value": {"type": "item", "path": ["t"]}}"#,
        #"{"id": "s", "op": "average", "value": {"type": "item", "path": ["t"]}}"#,
        #"{"id": "s", "op": "unique", "by": {"type": "item", "path": ["t"]}}"#,
        #"{"id": "s", "op": "filter", "where": {"type": "compare", "op": "eq", "left": {"type": "item", "path": ["t"]}, "right": {"type": "literal", "value": 1}}}"#,
        #"{"id": "s", "op": "running-sum", "value": {"type": "item", "path": ["t"]}, "into": "total", "nullPropagates": false}"#,
        #"{"id": "s", "op": "annotate", "fields": {"lo": {"aggregate": "min", "value": {"type": "item", "path": ["t"]}}}}"#,
    ])
    func aStepThatNeedsAListRefusesANumber(_ step: String) throws {
        let number = Self.attribute.replacingOccurrences(of: "SHAPE", with: #"{"kind": "number"}"#)
        let found = try Self.codes(Self.inputs(request: number, steps: "[\(step)]"))
        #expect(found.contains(.bindingType), "\(step): \(found)")
    }

    @Test func selectKeyRefusesAnInputThatIsNoRecord() throws {
        let number = Self.attribute.replacingOccurrences(of: "SHAPE", with: #"{"kind": "number"}"#)
        let step = #"[{"id": "k", "op": "select-key", "key": {"type": "literal", "value": "a"}}]"#
        #expect(try Self.codes(Self.inputs(request: number, steps: step)).contains(.bindingType))
    }

    // MARK: Parameters

    @Test(arguments: [
        ("number", #""3""#, #"3"#), ("number", #""x""#, "null"), ("number", "4", "4"),
        ("boolean", "true", "true"), ("boolean", "5", "null"),
        ("string", #""a""#, #""a""#), ("string", "5", "null"),
        ("entity-id", #""light.demo""#, #""light.demo""#), ("entity-id", "5", "null"),
    ])
    func aParameterReadsAsItsDeclaredKind(_ kind: String, _ literal: String, _ expected: String) throws {
        let parameters = #"[{"name": "p", "type": "\#(kind)", "value": {"type": "literal", "value": \#(literal)}}]"#
        let flow = Self.operandFlow(#"{"type": "param", "name": "p"}"#, parameters: parameters)
        #expect(try Self.run(flow) == Self.json(expected), "\(kind) \(literal)")
    }

    @Test func aParameterHasTheShapeOfItsKind() {
        #expect(ServerUIFlowTyping.shape(of: .string) == .text)
        #expect(ServerUIFlowTyping.shape(of: .number) == .float)
        #expect(ServerUIFlowTyping.shape(of: .boolean) == .boolean)
        #expect(ServerUIFlowTyping.shape(of: .entityID) == .text(.entityId))
    }

    @Test func aParameterThatNamesItselfIsACycleAndReadsAsNull() throws {
        let parameters = #"[{"name": "p", "type": "number", "value": {"type": "param", "name": "p"}}]"#
        let flow = Self.operandFlow(#"{"type": "param", "name": "p"}"#, parameters: parameters, schema: #"{"kind": "number"}"#)
        #expect(try Self.codes(flow).contains(.invalidCombination))
        #expect(try Self.run(flow) == .null)
    }

    // MARK: Operands

    @Test func progressIsTheShareOfTheSpanThatHasPassed() throws {
        let progress = #"{"type": "date", "op": "progress", "from": {"type": "literal", "value": "2026-11-15T00:00:00"}, "to": {"type": "literal", "value": "2026-11-16T00:00:00"}}"#
        let flow = Self.operandFlow(progress, schema: #"{"kind": "number"}"#)
        let clock = ServerUIFlowContext(clock: ServerUIClock(now: "2026-11-15T12:00:00", utcOffsetMinutes: 0))
        #expect(try Self.run(flow, context: clock) == .number(0.5))
        #expect(try Self.run(flow) == .null, "no clock, no answer")
        let found = ServerUIFlowCompiler.check(try #require(Self.decode(flow).flow), at: "")
        #expect(found.issues.isEmpty, "\(found.issues)")
        #expect(found.capabilities.contains("flow-extras") && found.capabilities.contains("pipeline-operands"))
    }

    @Test func progressNeedsTwoDates() throws {
        let progress = #"{"type": "date", "op": "progress", "from": {"type": "literal", "value": 1}, "to": {"type": "literal", "value": 2}}"#
        #expect(try Self.codes(Self.operandFlow(progress, schema: #"{"kind": "number"}"#)).contains(.bindingType))
    }

    @Test func aFormatNeedsTheCapabilityOfEachWayItWritesAnArgument() throws {
        func capabilities(_ format: String, _ value: String) throws -> [String] {
            let operand = #"{"type": "format", "pattern": "{a}", "args": {"a": {"type": "literal", "value": \#(value)}}, "formats": {"a": \#(format)}}"#
            let flow = try #require(Self.decode(Self.operandFlow(operand)).flow)
            return ServerUIFlowCompiler.check(flow, at: "").capabilities
        }
        #expect(try capabilities(#"{"date": {"style": "hour"}}"#, #""2026-11-15T09:30:00""#).contains("flow-extras"))
        #expect(try capabilities(#"{"date": {"style": "short-date"}}"#, #""2026-11-15T09:30:00""#).contains("pipeline-operands"))
        #expect(try capabilities(#"{"text": {"case": "title"}}"#, #""armed_away""#).contains("pipeline-operands"))
        #expect(try capabilities(#"{"duration": {"style": "compact", "unit": "seconds"}}"#, "90").contains("duration-format"))
        #expect(try capabilities(#"{"number": {"maximumFractionDigits": 3, "minimumFractionDigits": 1}}"#, "1.5").contains("pipeline-operands"))
    }

    @Test func aFormatWhoseFewestDigitsPassItsMostIsRefused() throws {
        let operand = #"{"type": "format", "pattern": "{a}", "args": {"a": {"type": "literal", "value": 1.5}}, "formats": {"a": {"number": {"maximumFractionDigits": 1, "minimumFractionDigits": 3}}}}"#
        let decoded = Self.decode(Self.operandFlow(operand))
        let found = decoded.issues + (decoded.flow.map { ServerUIFlowCompiler.check($0, at: "").issues } ?? [])
        #expect(found.contains { $0.code == .invalidCombination }, "\(found)")
    }

    @Test func aFormatThatNamesNoArgumentForAPlaceholderIsRefused() throws {
        let operand = #"{"type": "format", "pattern": "{a}{b}", "args": {"a": {"type": "literal", "value": "x"}}}"#
        #expect(!Self.decode(Self.operandFlow(operand)).issues.isEmpty)
    }

    @Test func aRuleWhoseBranchesGiveDifferentKindsIsRefused() throws {
        let when = #"{"type": "compare", "op": "eq", "left": {"type": "literal", "value": 1}, "right": {"type": "literal", "value": 1}}"#
        let choose = #"{"type": "choose", "cases": [{"when": \#(when), "then": {"type": "literal", "value": "words"}}], "otherwise": {"type": "literal", "value": 2}}"#
        #expect(try Self.codes(Self.operandFlow(choose)).contains(.bindingType))
        let other = #"{"type": "choose", "cases": [{"when": \#(when), "then": {"type": "literal", "value": "a"}}, {"when": \#(when), "then": {"type": "literal", "value": 3}}], "otherwise": {"type": "literal", "value": "b"}}"#
        #expect(try Self.codes(Self.operandFlow(other)).contains(.bindingType))
    }

    @Test func aListOrRecordLiteralTypesAsAListOrRecord() throws {
        let literal = #"{"type": "literal", "value": [1, "a", {"k": true}]}"#
        let found = try Self.codes(Self.operandFlow(literal, schema: #"{"kind": "number"}"#))
        #expect(!found.isEmpty, "a list is no number")
        let record = #"{"type": "literal", "value": {"a": [1, 2], "c": false}}"#
        #expect(!(try Self.codes(Self.operandFlow(record, schema: #"{"kind": "number"}"#))).isEmpty)
    }

    @Test func aListOfOperandsTypesItsItems() throws {
        let list = #"{"type": "list", "items": [{"type": "literal", "value": 1}, {"type": "literal", "value": "a"}]}"#
        #expect(!(try Self.codes(Self.operandFlow(list, schema: #"{"kind": "number"}"#))).isEmpty)
    }

    @Test func aViewerPersonConditionIsUnknownInAFlowSoTheRuleFallsThrough() throws {
        let when = #"{"type": "viewer-person", "in": ["person.alex"]}"#
        let choose = #"{"type": "choose", "cases": [{"when": \#(when), "then": {"type": "literal", "value": "alex"}}], "otherwise": {"type": "literal", "value": "someone"}}"#
        #expect(try Self.run(Self.operandFlow(choose)) == .string("someone"))
    }

    // MARK: Evaluation edges

    @Test func groupingByAListOrRecordKeyFallsInOneGroupWithNoKey() throws {
        let response = Self.json(#"[{"t": [1]}, {"t": {"a": 1}}, {"t": "x"}, {"t": "x"}]"#)
        let steps = #"[{"id": "g", "op": "group", "by": {"type": "item", "path": ["t"]}}]"#
        let groups = try Self.value(Self.inputs(steps: steps), response: response)
        #expect(groups == Self.json(#"[{"key": null, "count": 2, "items": [{"t": [1]}, {"t": {"a": 1}}]}, {"key": "x", "count": 2, "items": [{"t": "x"}, {"t": "x"}]}]"#))
    }

    @Test func defaultFillsARecordAndLeavesAScalarAlone() throws {
        let steps = #"[{"id": "d", "op": "default", "path": ["a"], "value": {"type": "literal", "value": 5}}]"#
        let record = Self.attribute.replacingOccurrences(of: "SHAPE", with: Self.list)
        #expect(try Self.value(Self.inputs(request: record, steps: steps), response: Self.json("{}")) == Self.json(#"{"a": 5}"#))
        #expect(try Self.value(Self.inputs(request: record, steps: steps), response: Self.json(#"{"a": 2}"#)) == Self.json(#"{"a": 2}"#))
        #expect(try Self.value(Self.inputs(request: record, steps: steps), response: .number(7)) == .number(7))
    }

    @Test func annotateWritesEveryListWideAggregateOntoEveryRecord() throws {
        let steps = #"[{"id": "a", "op": "annotate", "fields": {"lo": {"aggregate": "min", "value": \#(Self.item)}, "hi": {"aggregate": "max", "value": \#(Self.item)}}}]"#
        let response = Self.json(#"[{"t": 4}, {"t": 9}, 3, {"t": null}]"#)
        let answer = try Self.value(Self.inputs(steps: steps), response: response)
        #expect(answer == Self.json(#"[{"t": 4, "lo": 4, "hi": 9}, {"t": 9, "lo": 4, "hi": 9}, 3, {"t": null, "lo": 4, "hi": 9}]"#))
    }

    @Test func aRunningSumKeepsAGapOnlyWhenAskedTo() throws {
        let response = Self.json(#"[{"t": 1}, {"t": null}, {"t": 2}]"#)
        func totals(_ propagates: Bool) throws -> JSONValue {
            let steps = #"[{"id": "r", "op": "running-sum", "value": \#(Self.item), "into": "total", "nullPropagates": \#(propagates)}]"#
            return try Self.value(Self.inputs(steps: steps), response: response)
        }
        #expect(try totals(false) == Self.json(#"[{"t": 1, "total": 1}, {"t": null, "total": 1}, {"t": 2, "total": 3}]"#))
        #expect(try totals(true) == Self.json(#"[{"t": 1, "total": 1}, {"t": null, "total": null}, {"t": 2, "total": null}]"#))
    }

    // MARK: What a flow says about what it reads

    private static let subscription = #"{"type": "ha-subscription", "kind": "todo-items", "entityId": {"type": "literal", "value": "todo.demo"}}"#
    private static let forecast = #"{"type": "ha-subscription", "kind": "weather-forecast", "entityId": {"type": "literal", "value": "weather.demo"}, "forecastType": "hourly"}"#
    private static let entities = #"{"type": "entities", "entityIds": [{"type": "literal", "value": "light.a"}, {"type": "literal", "value": "light.b"}], "attributes": []}"#
    private static let service = #"{"type": "service-response", "domain": "todo", "service": "get_items", "target": {"entity_id": {"type": "literal", "value": "todo.demo"}}, "timeoutSeconds": 10, "responseShape": {"kind": "object", "fields": {}}}"#

    @Test func aSubscriptionNamesItsKind() throws {
        let todo = try #require(try Self.flow(Self.inputs(request: Self.subscription)).subscription)
        #expect(todo.kindName == "todo-items")
        let weather = try #require(try Self.flow(Self.inputs(request: Self.forecast)).subscription)
        #expect(weather.kindName == "weather-forecast")
        #expect(try Self.flow(Self.inputs()).subscription == nil)
    }

    @Test func aFlowWatchesTheEntitiesItsRequestNames() throws {
        #expect(try Self.flow(Self.inputs(request: Self.entities)).watchedEntityIds == ["light.a", "light.b"])
        #expect(try Self.flow(Self.inputs()).watchedEntityIds == ["sensor.demo_case"])
        let refreshing = Self.decode(Self.inputs(request: Self.service, extra: #", "refresh": {"on": ["entity-change"], "entityIds": [{"type": "literal", "value": "sensor.a"}], "staleAfterSeconds": 60}"#))
        #expect(refreshing.issues.isEmpty, "\(refreshing.issues)")
        #expect(refreshing.flow?.watchedEntityIds == ["sensor.a"])
        #expect(try Self.flow(Self.inputs(request: Self.service)).watchedEntityIds.isEmpty)
        #expect(try Self.flow(Self.inputs(request: Self.subscription)).watchedEntityIds.isEmpty)
    }

    @Test func onlyAnEntityRequestReadsHeldEntities() throws {
        #expect(try Self.flow(Self.inputs(request: Self.entities)).readsHeldEntities)
        #expect(try Self.flow(Self.inputs()).readsHeldEntities)
        #expect(try !Self.flow(Self.inputs(request: Self.service)).readsHeldEntities)
        #expect(try !Self.flow(Self.inputs(request: Self.subscription)).readsHeldEntities)
    }

    @Test func aFlowCollectsTheOperandsOfEveryStepAndRequest() throws {
        let steps = """
        [{"id": "a", "op": "annotate", "fields": {"lo": {"aggregate": "min", "value": \(Self.item)}}},
         {"id": "s", "op": "sort", "by": [{"value": \(Self.item), "direction": "ascending", "kind": "number"}]},
         {"id": "m", "op": "map", "fields": {"x": {"type": "viewer", "field": "userId"}}},
         {"id": "f", "op": "filter", "where": {"type": "compare", "op": "above", "left": {"type": "clock", "part": "today"}, "right": {"type": "read", "from": {"type": "source", "sourceId": "other", "path": ["state"]}, "as": "number", "missing": "unavailable"}}}]
        """
        let flow = try Self.flow(Self.inputs(steps: steps))
        #expect(flow.operands.count == 3 && flow.predicates.count == 1, "\(flow.operands)")
        #expect(flow.readsViewer && flow.readsClock)
        #expect(flow.sourceIds == ["other"])
        let none = try Self.flow(Self.operandFlow(#"{"type": "viewer", "field": "userId"}"#))
        #expect(none.operands.count == 1 && none.readsViewer && !none.readsClock)
        let plain = try Self.flow(Self.inputs())
        #expect(!plain.readsViewer && !plain.readsClock && plain.sourceIds.isEmpty)
    }

    @Test func aServiceRequestCollectsItsTargetAndData() throws {
        let request = #"{"type": "service-response", "domain": "todo", "service": "get_items", "target": {"entity_id": {"type": "literal", "value": "todo.demo"}}, "data": {"type": "object", "fields": {"status": {"type": "literal", "value": "open"}}}, "timeoutSeconds": 10, "responseShape": {"kind": "object", "fields": {}}}"#
        #expect(try Self.flow(Self.inputs(request: request)).operands.count == 2)
    }

    // MARK: Service targets

    private static func service(target: String) -> JSONValue {
        let request = #"{"type": "service-response", "domain": "todo", "service": "get_items", "target": \#(target), "timeoutSeconds": 10, "responseShape": {"kind": "object", "fields": {}}}"#
        return inputs(request: request, schema: #"{"kind": "number"}"#)
    }

    @Test(arguments: [
        (#"{"area_id": {"type": "literal", "value": "kitchen"}}"#, true),
        (#"{"area_id": {"type": "literal", "value": ["kitchen", "den"]}}"#, true),
        (#"{"area_id": {"type": "literal", "value": ""}}"#, false),
        (#"{"area_id": {"type": "literal", "value": ["kitchen", ""]}}"#, false),
        (#"{"area_id": {"type": "literal", "value": 4}}"#, false),
        (#"{"entity_id": {"type": "literal", "value": ["todo.a", "todo.b"]}}"#, true),
        (#"{"entity_id": {"type": "literal", "value": "not an entity"}}"#, false),
        (#"{"entity_id": {"type": "literal", "value": ["todo.a", "nope"]}}"#, false),
        (#"{}"#, false),
    ])
    func aServiceTargetIsAnEntityOrAnIdOfItsKind(_ target: String, _ accepted: Bool) throws {
        let found = ServerUIFlowCompiler.check(try #require(Self.decode(Self.service(target: target)).flow), at: "")
        let targetIssues = found.issues.filter { $0.pointer.contains("/target") }
        #expect(targetIssues.isEmpty == accepted, "\(target): \(targetIssues)")
    }

    // MARK: What the decoder refuses

    @Test(arguments: [
        #"{"type": "http", "entityId": {"type": "literal", "value": "sensor.demo"}}"#,
        #"{"type": "ha-subscription", "kind": "camera-stream", "entityId": {"type": "literal", "value": "todo.demo"}}"#,
        #"{"type": "ha-subscription", "kind": "weather-forecast", "entityId": {"type": "literal", "value": "weather.demo"}, "forecastType": "yearly"}"#,
    ])
    func anUnknownRequestIsNotAFlow(_ request: String) {
        #expect(Self.decode(Self.inputs(request: request)).flow == nil, "\(request)")
    }

    @Test func anUnknownStepOrOutputIsNotAFlow() {
        #expect(Self.decode(Self.inputs(steps: #"[{"id": "x", "op": "median", "value": \#(Self.item)}]"#)).flow == nil)
        #expect(Self.decode(Self.inputs(output: #"{"kind": "table"}"#)).flow == nil)
    }

    @Test func aFlowSaysWhichClockItsDatesUse() throws {
        #expect(try Self.flow(Self.inputs(extra: #", "clock": {"zone": "home"}"#)).clockZone == .home)
        #expect(try Self.flow(Self.inputs(extra: #", "clock": {"zone": "device"}"#)).clockZone == .device)
        #expect(try Self.flow(Self.inputs()).clockZone == nil)
    }
}
