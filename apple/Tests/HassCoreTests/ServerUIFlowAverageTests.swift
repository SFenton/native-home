import Foundation
import Testing
@testable import HassCore

// MARK: - The average step

/// The `average` step of a Data Flow (`sh.flow-average@1`): how it decodes, types, declares its id, evaluates and what it costs.
///
/// The shared corpus (`ServerUIPipelineCorpusTests`, `ServerUIContractCorpusTests`) holds the Studio's answers for the same step; these tests
/// pin each rule on its own, with the data written out, so a failure names the rule that broke.
@Suite(.timeLimit(.minutes(1)))
struct ServerUIFlowAverageTests {
    // MARK: Fixtures

    private static func json(_ text: String) -> JSONValue {
        (try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) ?? .null
    }

    /// The inputs of a flow that reads `[{"t": …}, …]` from an entity attribute, runs `steps` and gives the one number the last of them makes.
    private static func inputs(steps: String, fieldShape: String = #"{"kind": "number"}"#) -> JSONValue {
        json("""
        {"title": "Case", "parameters": [],
         "request": {"type": "entity-attribute", "entityId": {"type": "literal", "value": "sensor.demo_case"}, "path": ["value"],
                     "responseShape": {"kind": "array", "of": {"kind": "object", "fields": {"t": {"shape": \(fieldShape)}}}}},
         "steps": \(steps), "output": {"kind": "scalar"}, "schema": {"kind": "number"},
         "refresh": {"on": ["open"], "staleAfterSeconds": 300}}
        """)
    }

    private static let averageSteps = #"[{"id": "mean", "op": "average", "value": {"type": "item", "path": ["t"]}}]"#

    private static func flow(_ inputs: JSONValue) throws -> ServerUIFlow {
        let decoded = ServerUIFlowDecoder.decode(inputs, at: "")
        try #require(decoded.issues.isEmpty, "decode issues \(decoded.issues)")
        return try #require(decoded.flow)
    }

    private static func run(_ steps: String = averageSteps, over parts: [String], budget: Int = ServerUIFlowEvaluator.budget) throws -> ServerUIFlowRun {
        let response = json("[" + parts.map { #"{"t": \#($0)}"# }.joined(separator: ",") + "]")
        return ServerUIFlowEvaluator.run(try flow(inputs(steps: steps)), response: response, context: ServerUIFlowContext(), budget: budget)
    }

    private static func mean(of parts: [String]) throws -> JSONValue {
        let run = try run(over: parts)
        try #require(run.status == .ok)
        return run.output
    }

    private static let largest = "\(Double.greatestFiniteMagnitude)"

    // MARK: Decoding

    @Test func decodesToAnAverageStepWithItsOperand() throws {
        let flow = try Self.flow(Self.inputs(steps: Self.averageSteps))
        let step = try #require(flow.steps.first)
        #expect(step.id == "mean" && step.operation.name == "average")
        guard case .average(let operand) = step.operation else { Issue.record("not an average step: \(step.operation)"); return }
        #expect(flow.operands.contains(operand), "the flow evaluates the operand like any other step's")
    }

    @Test(arguments: [
        (#"[{"id": "mean", "op": "average"}]"#, "missing value"),
        (#"[{"id": "mean", "op": "average", "value": {"type": "item", "path": ["t"]}, "round": 2}]"#, "an extra field"),
        (#"[{"id": "mean", "op": "average", "value": 3}]"#, "a value that is no operand"),
    ])
    func refusesAnAverageStepThatIsNotShapedRight(_ steps: String, _ why: String) {
        let found = ServerUICompositionShape.issues(of: Self.inputs(steps: steps), against: ServerUICompositionShape.flowInputs)
        let decoded = ServerUIFlowDecoder.decode(Self.inputs(steps: steps), at: "")
        #expect(!found.isEmpty || !decoded.issues.isEmpty || decoded.flow == nil, "\(why) must be refused")
    }

    @Test func theSchemaKnowsTheStepLikeMinAndMax() {
        for op in ["min", "max", "average"] {
            let steps = #"[{"id": "x", "op": "\#(op)", "value": {"type": "item", "path": ["t"]}}]"#
            #expect(ServerUICompositionShape.issues(of: Self.inputs(steps: steps), against: ServerUICompositionShape.flowInputs).isEmpty, "\(op)")
        }
    }

    // MARK: Typing and capabilities

    @Test func aNumberValueTypesAsANumberOrNull() throws {
        let found = ServerUIFlowCompiler.check(try Self.flow(Self.inputs(steps: Self.averageSteps)), at: "")
        #expect(found.issues.isEmpty, "\(found.issues)")
    }

    @Test func aValueTypedAsTextIsABindingTypeError() throws {
        let text = Self.inputs(steps: Self.averageSteps, fieldShape: #"{"kind": "string"}"#)
        let found = ServerUIFlowCompiler.check(try Self.flow(text), at: "")
        #expect(found.issues.map(\.code) == [.bindingType], "\(found.issues)")
        #expect(found.issues.first?.pointer == "/inputs/steps/0/value")
        // Exactly the rule `min` and `max` have.
        for op in ["min", "max"] {
            let steps = #"[{"id": "x", "op": "\#(op)", "value": {"type": "item", "path": ["t"]}}]"#
            let other = ServerUIFlowCompiler.check(try Self.flow(Self.inputs(steps: steps, fieldShape: #"{"kind": "string"}"#)), at: "")
            #expect(other.issues.map(\.code) == [.bindingType], "\(op)")
        }
    }

    @Test func aFlowThatAveragesDeclaresItsOwnIdAndNotFlowExtras() throws {
        let average = ServerUIFlowCompiler.check(try Self.flow(Self.inputs(steps: Self.averageSteps)), at: "")
        #expect(average.capabilities.contains("flow-average"))
        #expect(!average.capabilities.contains("flow-extras"), "average is not one of the flow extras")
        let lowest = ServerUIFlowCompiler.check(try Self.flow(Self.inputs(steps: #"[{"id": "x", "op": "min", "value": {"type": "item", "path": ["t"]}}]"#)), at: "")
        #expect(lowest.capabilities.contains("flow-extras") && !lowest.capabilities.contains("flow-average"))
    }

    @Test func aFlowWithoutAnAverageStepDoesNotNeedTheId() throws {
        let sum = ServerUIFlowCompiler.check(try Self.flow(Self.inputs(steps: #"[{"id": "x", "op": "sum", "value": {"type": "item", "path": ["t"]}}]"#)), at: "")
        #expect(!sum.capabilities.contains("flow-average"))
    }

    @Test func theIdIsListedAsIngestedAndPublished() {
        #expect(ServerUIIngestedCapabilities.flowAverage == ["sh.flow-average@1"])
        #expect(ServerUIIngestedCapabilities.all.contains("sh.flow-average@1"))
        #expect(ServerUICompositionPublication.supportedCapabilities.contains("sh.flow-average@1"))
    }

    // MARK: Evaluation

    @Test func theMeanOfNumbersIsTheirSumOverTheirCount() throws {
        #expect(try Self.mean(of: ["2", "6"]) == .number(4))
        #expect(try Self.mean(of: ["-4", "1"]) == .number(-1.5))
        #expect(try Self.mean(of: ["7"]) == .number(7))
    }

    @Test func nullAndNonNumbersAreSkippedAndNumericTextIsNotANumber() throws {
        #expect(try Self.mean(of: ["2", "null", #""10""#, "6", "true", "{}", "[]"]) == .number(4))
    }

    @Test func noNumbersAtAllGiveNullNotZero() throws {
        #expect(try Self.mean(of: ["null", #""10""#, "false", "[]"]) == .null)
        #expect(try Self.mean(of: []) == .null)
    }

    @Test func theMeanIsNotRounded() throws {
        #expect(try Self.mean(of: ["1", "2", "2"]) == .number(5.0 / 3.0))
        let printed = ServerUICompositionJSON.canonical(try Self.mean(of: ["1", "2", "2"]))
        #expect(printed == "1.6666666666666667")
    }

    @Test func ordinaryListsKeepTheirSumThenDivideResult() throws {
        let result = try Self.mean(of: ["0.1", "0.2", "0.3"])
        #expect(result == .number((0.1 + 0.2 + 0.3) / 3))
        #expect(ServerUICompositionJSON.canonical(result) == "0.20000000000000004")
    }

    @Test func zeroIsNeverNegativeZero() throws {
        let result = try Self.mean(of: ["-0.0", "0"])
        guard case .number(let value) = result else { Issue.record("\(result)"); return }
        #expect(value == 0 && value.sign == .plus)
        #expect(ServerUICompositionJSON.canonical(result) == "0")
    }

    // MARK: Overflow

    @Test(arguments: [1, 2, 3, 4])
    func repeatedLargestPartsHaveTheLargestAsTheirMean(_ count: Int) throws {
        let parts = Array(repeating: Self.largest, count: count)
        #expect(try Self.mean(of: parts) == .number(Double.greatestFiniteMagnitude), "\(count) parts")
        let negative = Array(repeating: "-" + Self.largest, count: count)
        #expect(try Self.mean(of: negative) == .number(-Double.greatestFiniteMagnitude), "\(count) negative parts")
    }

    @Test func largestPartsOfBothSignsCancelToZeroEvenWhenSameSignPartsOverflowFirst() throws {
        let big = Self.largest, small = "-" + Self.largest
        #expect(try Self.mean(of: [big, big, small, small]) == .number(0))
        #expect(try Self.mean(of: [big, small, big, small]) == .number(0))
    }

    @Test func aMixedOverflowingSumKeepsItsSignAndSize() throws {
        let big = Self.largest, small = "-" + Self.largest
        let positive = try Self.mean(of: [big, big, small])
        let negative = try Self.mean(of: [small, small, big])
        #expect(positive == .number(Double.greatestFiniteMagnitude / 3))
        #expect(negative == .number(-Double.greatestFiniteMagnitude / 3))
        #expect(ServerUICompositionJSON.canonical(positive) == "5.992310449541053e+307")
        #expect(ServerUICompositionJSON.canonical(negative) == "-5.992310449541053e+307")
    }

    @Test func aMeanOfFiniteNumbersIsAlwaysFinite() throws {
        let big = Self.largest
        for parts in [[big, big], [big, big, big], [big, "1", big], ["-" + big, "-" + big, "5"]] {
            guard case .number(let value) = try Self.mean(of: parts) else { Issue.record("not a number: \(parts)"); continue }
            #expect(value.isFinite, "\(parts)")
        }
    }

    // MARK: Cost

    @Test func costsWhatSumCostsOverTheSameList() throws {
        let parts = ["1", "2", "null", "4", "5"]
        let average = try Self.run(over: parts)
        let sum = try Self.run(#"[{"id": "total", "op": "sum", "value": {"type": "item", "path": ["t"]}}]"#, over: parts)
        #expect(average.status == .ok && sum.status == .ok)
        #expect(average.visits == sum.visits, "average \(average.visits) against sum \(sum.visits)")
        #expect(average.visits > parts.count, "the step spends the items and the operand's nodes")
    }

    @Test func costGrowsWithTheItemCount() throws {
        let few = try Self.run(over: Array(repeating: "1", count: 3))
        let many = try Self.run(over: Array(repeating: "1", count: 30))
        #expect(many.visits - few.visits == 27 * 2, "each item adds itself and its one operand node")
    }

    @Test func aBudgetTooSmallForTheListStopsTheRun() throws {
        let parts = Array(repeating: "1", count: 50)
        let whole = try Self.run(over: parts)
        let cut = try Self.run(over: parts, budget: whole.visits - 1)
        #expect(whole.status == .ok)
        #expect(cut.status == .overBudget)
    }
}
