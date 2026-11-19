import Foundation
import Testing
@testable import HassCore

// MARK: - The Data Flow evaluation corpus

/// Runs the Studio's Data Flow corpus (`ContractCorpus/pipelines`, copied byte for byte) through the app's decoder, typing and evaluator.
///
/// Each file is data, steps and the exact answer; a file also says whether the compiler accepts the flow and, for two, the shape after the
/// steps. The Studio runs the same files in `tests/pipeline-corpus.test.ts`, so a flow means the same thing on both sides, including the
/// four places JavaScript and Swift disagree (text equality, text order, number text, tie rounding).
@Suite(.timeLimit(.minutes(2)))
struct ServerUIPipelineCorpusTests {
    /// One corpus file.
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let file: JSONValue
        var testDescription: String { name }
        var inputs: JSONValue { file["inputs"] ?? .null }
        var response: JSONValue { file["response"] ?? .null }
        var expected: JSONValue { file["expected"] ?? .null }
    }

    nonisolated static let directory = ServerUIContractCorpusTests.directory.appendingPathComponent("pipelines", isDirectory: true)

    nonisolated static let cases: [Case] = {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".json") }.sorted()
        return names.compactMap { name in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
                  let file = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
            return Case(name: String(name.dropLast(5)), file: file)
        }
    }()

    @Test func theCorpusIsWholeAndNamedByItsFiles() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.directory.path).filter { $0.hasSuffix(".json") }.sorted()
        #expect(Self.cases.count == names.count, "a file did not decode")
        #expect(Self.cases.count == 51 + 28 + 12, "twelve of the files are the `flow-average-*` cases")
        #expect(Self.cases.map { $0.name + ".json" } == names)
        for item in Self.cases {
            #expect(item.file["format"] == .number(1))
            #expect((item.file["note"]?.string ?? "").count > 10)
        }
    }

    // MARK: Cases

    /// The flow a case holds, after its structure check.
    static func flow(_ item: Case) throws -> ServerUIFlow {
        let issues = ServerUICompositionShape.issues(of: item.inputs, against: ServerUICompositionShape.flowInputs)
        try #require(issues.isEmpty, "\(item.name): structure issues \(issues)")
        let decoded = ServerUIFlowDecoder.decode(item.inputs, at: "")
        try #require(decoded.issues.isEmpty, "\(item.name): decode issues \(decoded.issues)")
        return try #require(decoded.flow, "\(item.name): flow did not decode")
    }

    /// What the case's context gives a run.
    static func context(_ item: Case) -> ServerUIFlowContext {
        let context = item.file["context"] ?? .null
        let clock = context["clock"].flatMap { value -> ServerUIClock? in
            guard let now = value["now"]?.string, let offset = value["utcOffsetMinutes"]?.number else { return nil }
            return ServerUIClock(now: now, utcOffsetMinutes: Int(offset))
        }
        let viewer = context["viewer"].map {
            ServerUIViewer(userId: $0["userId"]?.string, isAdmin: $0["isAdmin"]?.bool, personEntityId: $0["personEntityId"]?.string)
        }
        let reads = context["reads"] ?? .null
        return ServerUIFlowContext(clock: clock, viewer: viewer) { sourceId, path in
            var current = reads[sourceId]
            for segment in path {
                guard case .object(let fields)? = current else { return nil }
                current = fields[segment]
            }
            return current
        }
    }

    @Test(arguments: cases)
    func evaluatesToItsRecordedAnswer(_ item: Case) throws {
        let flow = try Self.flow(item)
        let budget = item.file["budget"]?.number.map { Int($0) } ?? ServerUIFlowEvaluator.budget
        let run = ServerUIFlowEvaluator.run(flow, response: item.response, context: Self.context(item), budget: budget)
        let expected = item.expected
        #expect(run.status == (expected["status"]?.string == "ok" ? .ok : .overBudget), "\(item.name): status")
        guard run.status == .ok else { return }
        let output = expected["output"] ?? .null
        #expect(ServerUICompositionJSON.canonical(run.output) == ServerUICompositionJSON.canonical(output),
                "\(item.name): got \(ServerUICompositionJSON.canonical(run.output))")
        if let visits = expected["visits"]?.number { #expect(run.visits == Int(visits), "\(item.name): visits \(run.visits)") }
    }

    @Test(arguments: cases)
    func compilesExactlyWhenTheStudioDoes(_ item: Case) throws {
        let flow = try Self.flow(item)
        let found = ServerUIFlowCompiler.check(flow, at: "")
        if item.file["compiles"] == .bool(true) { #expect(found.issues.isEmpty, "\(item.name): \(found.issues)") }
        else { #expect(!found.issues.isEmpty, "\(item.name): the flow should be refused") }
    }

    @Test(arguments: cases.filter { $0.file["expectedShape"] != nil })
    func hasTheRecordedShapeAfterItsSteps(_ item: Case) throws {
        let flow = try Self.flow(item)
        let kinds = Dictionary(flow.parameters.map { ($0.name, $0.kind) }, uniquingKeysWith: { first, _ in first })
        var facts = ServerUIFlowTyping.Facts()
        let shapes = ServerUIFlowTyping.types(flow.steps, input: ServerUIFlowInference.shape(ofSamples: [item.response]),
                                              parameters: kinds, at: "", &facts)
        #expect(facts.issues.isEmpty, "\(item.name): \(facts.issues)")
        let last = try #require(shapes.last)
        #expect(ServerUICompositionJSON.canonical(last.json) == ServerUICompositionJSON.canonical(item.file["expectedShape"] ?? .null))
    }
}
