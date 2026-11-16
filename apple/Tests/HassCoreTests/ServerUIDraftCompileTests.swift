import Foundation
import HassTestSupport
import Testing
@testable import HassCore

// MARK: - Draft compile entry

/// The compile entry point `tools/parity_loop/draft.py` drives: it runs one publication file through the app's own
/// ``ServerUICompositionPublication/decode(_:)`` and reports the outcome as one JSON object, never an authored value.
///
/// `PARITY_DRAFT_PUBLICATION` names the file and `PARITY_DRAFT_RESULT` the file the result is written to. Without both, that test is
/// reported as skipped; the other tests check the reporting on the shared corpus in every run.
@Suite(.timeLimit(.minutes(5)))
@MainActor
struct ServerUIDraftCompileTests {
    /// The outcome of compiling one file: `{"ok":true,...}` or the compiler's first issue (code, pointer, capability).
    static func report(for bytes: Data) -> [String: Any] {
        let source = HouseConfigSource()
        source.set(DemoHouse.config)
        let result: Result<ServerUICompositionPublication, any Error> = HouseConfigSource.$scoped.withValue(source) {
            Result { try ServerUICompositionPublication.decode(bytes) }
        }
        switch result {
        case .success(let publication):
            return ["ok": true, "revision": publication.revision, "capabilities": publication.capabilities.count]
        case .failure(let error as ServerUICompositionError):
            var value: [String: Any] = ["ok": false, "code": error.code.rawValue, "pointer": error.pointer]
            if let capability = error.capability { value["capability"] = capability }
            return value
        case .failure:
            return ["ok": false, "code": "other", "pointer": ""]
        }
    }

    private static let corpus = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("ContractCorpus", isDirectory: true)

    /// Compiles the file `PARITY_DRAFT_PUBLICATION` names and writes the report to `PARITY_DRAFT_RESULT`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PARITY_DRAFT_PUBLICATION"] != nil
                   && ProcessInfo.processInfo.environment["PARITY_DRAFT_RESULT"] != nil))
    func compilesTheNamedPublication() throws {
        let environment = ProcessInfo.processInfo.environment
        let path = try #require(environment["PARITY_DRAFT_PUBLICATION"]), out = try #require(environment["PARITY_DRAFT_RESULT"])
        let report = Self.report(for: try Data(contentsOf: URL(fileURLWithPath: path)))
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        try data.write(to: URL(fileURLWithPath: out), options: .atomic)
    }

    @Test func reportsAnAcceptedFileAsOk() throws {
        let report = Self.report(for: try Data(contentsOf: Self.corpus.appendingPathComponent("accept/action-rules-row.json")))
        #expect(report["ok"] as? Bool == true)
    }

    @Test func reportsARejectedFileWithItsFirstIssue() throws {
        let index = try #require(JSONSerialization.jsonObject(
            with: Data(contentsOf: Self.corpus.appendingPathComponent("index.json"))) as? [String: Any])
        let cases = try #require(index["cases"] as? [[String: Any]])
        let item = try #require(cases.first { $0["outcome"] as? String == "reject" && $0["houseScripts"] == nil && $0["pending"] == nil })
        let issue = try #require(item["issue"] as? [String: Any])
        let file = try #require(item["file"] as? String)
        let report = Self.report(for: try Data(contentsOf: Self.corpus.appendingPathComponent(file)))
        #expect(report["ok"] as? Bool == false)
        #expect(report["code"] as? String == issue["code"] as? String)
        #expect(report["pointer"] as? String == issue["pointer"] as? String)
    }
}
