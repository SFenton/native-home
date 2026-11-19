import Foundation
import HassTestSupport
import Testing
@testable import HassCore

// MARK: - Shared Studio and app corpus

/// Runs the shared publication corpus (`ContractCorpus/`, copied byte for byte from the Studio) through the app compiler.
///
/// Every `accept/` file must decode; every `reject/` file must throw the first issue `index.json` records (code, pointer and
/// capability); `capabilities.json` must equal the compiler's supported list. The corpus README says how to refresh the copy.
@Suite(.timeLimit(.minutes(2)))
@MainActor
struct ServerUIContractCorpusTests {
    /// One `index.json` entry.
    struct Case: Decodable, Sendable, CustomTestStringConvertible {
        struct Issue: Decodable, Equatable, Sendable {
            let code: String
            let pointer: String
            let capability: String?
        }

        let file: String
        let outcome: String
        let houseScripts: [String]?
        let issue: Issue?
        /// True for a case the Studio compiles that the app refuses until it ships the capability.
        let pending: Bool?

        var testDescription: String { file }
    }

    private struct Index: Decodable { let format: Int; let cases: [Case] }

    nonisolated static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("ContractCorpus", isDirectory: true)

    nonisolated static let cases: [Case] = {
        // A missing or malformed index yields no cases, and `indexIsCompleteAndWellFormed` then fails loudly.
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("index.json")),
              let index = try? JSONDecoder().decode(Index.self, from: data) else { return [] }
        return index.cases
    }()

    /// The house document a case needs: one remote that declares exactly the named scripts, else the demo house.
    static func house(for item: Case) -> HouseConfigSource {
        guard let scripts = item.houseScripts else {
            let source = HouseConfigSource()
            source.set(DemoHouse.config)
            return source
        }
        return ServerUIRemoteTestProvider.houseSource(scripts: scripts)
    }

    @Test func indexIsCompleteAndWellFormed() throws {
        let data = try Data(contentsOf: Self.directory.appendingPathComponent("index.json"))
        let index = try JSONDecoder().decode(Index.self, from: data)
        #expect(index.format == 1)
        let listed = index.cases.map(\.file)
        #expect(Set(listed).count == listed.count, "a file is listed twice")
        var onDisk: Set<String> = []
        for folder in ["accept", "reject"] {
            let names = try FileManager.default.contentsOfDirectory(atPath: Self.directory.appendingPathComponent(folder).path)
            onDisk.formUnion(names.filter { $0.hasSuffix(".json") }.map { "\(folder)/\($0)" })
        }
        #expect(onDisk == Set(listed), "index.json and the files on disk disagree")
        #expect(index.cases.allSatisfy { $0.outcome == "accept" || ($0.outcome == "reject" && $0.issue != nil) })
        #expect(index.cases.contains { $0.outcome == "accept" } && index.cases.contains { $0.outcome == "reject" })
    }

    /// The refusals the Studio gives for a field of a capability the app has not ingested, written without declaring it
    /// (`capability_manifest_mismatch`), by file. A shipped app does not know the field, so it refuses earlier with its own
    /// structural issue; such a case cannot carry the pending refusal (`unsupported_capability`) because it declares no id. Each stays here
    /// until its id is in ``ServerUIIngestedCapabilities``; from then on the exact first issue is checked like any other case.
    nonisolated static let undeclaredUseOfAPendingId: [String: String] = [
        "reject/component-values-capability-missing.json": "sh.component-values@1",
        "reject/component-values-key-capability-missing.json": "sh.component-values@1",
        "reject/fold-sides-capability-not-declared.json": "sh.fold-sides@1",
        "reject/fold-sides-switch-capability-not-declared.json": "sh.fold-sides@1",
        "reject/text-keep-read-missing-capability.json": "sh.text-keep@1",
        "reject/text-keep-expr-missing-capability.json": "sh.text-keep@1",
        "reject/profile-badges-avatar-capability-not-declared.json": "sh.avatar@1",
        "reject/profile-badges-badge-nodes-capability-not-declared.json": "sh.badge-nodes@1",
        "reject/profile-badges-badge-spoken-capability-not-declared.json": "sh.badge-spoken@1",
        "reject/profile-badges-shell-profile-capability-not-declared.json": "sh.shell-profile@1",
    ]

    /// The cases above that are still held back.
    nonisolated static func isHeldBackUntilIngested(_ file: String) -> Bool {
        undeclaredUseOfAPendingId[file].map { !ServerUIIngestedCapabilities.all.contains($0) } ?? false
    }

    /// A pending id's field written without the id is still refused by the app (as an unknown field or variant), and every held-back case names a
    /// case the index lists, so a renamed file cannot slip out of the gate unnoticed.
    @Test(arguments: undeclaredUseOfAPendingId.keys.sorted().filter(isHeldBackUntilIngested))
    func anUndeclaredUseOfAPendingIdIsStillRefused(_ file: String) throws {
        let item = try #require(Self.cases.first { $0.file == file }, "\(file) is not in index.json")
        #expect(item.outcome == "reject" && item.issue?.code == "capability_manifest_mismatch", "\(file)")
        let bytes = try Data(contentsOf: Self.directory.appendingPathComponent(file))
        let result: Result<ServerUICompositionPublication, any Error> = HouseConfigSource.$scoped.withValue(Self.house(for: item)) {
            Result { try ServerUICompositionPublication.decode(bytes) }
        }
        guard case .failure(let error) = result else { Issue.record("\(file) must be refused"); return }
        #expect(error is ServerUICompositionError, "\(file) threw \(error)")
    }

    @Test(arguments: cases)
    func fileDecodesWithTheRecordedOutcome(_ item: Case) throws {
        // A pending case whose capability a lane has since ingested is checked by that lane's own corpus suite.
        if item.pending == true, ServerUIIngestedCapabilities.all.contains(item.issue?.capability ?? "") { return }
        // The Studio's answer to an undeclared use of a pending id needs the id; until the app has it, `anUndeclaredUseOfAPendingIdIsStillRefused` holds the case.
        if Self.isHeldBackUntilIngested(item.file) { return }
        let bytes = try Data(contentsOf: Self.directory.appendingPathComponent(item.file))
        let result: Result<ServerUICompositionPublication, any Error> = HouseConfigSource.$scoped.withValue(Self.house(for: item)) {
            Result { try ServerUICompositionPublication.decode(bytes) }
        }
        switch item.outcome {
        case "accept":
            if case .failure(let error) = result { Issue.record("\(item.file) must decode, got \(error)") }
        case "reject":
            guard case .failure(let error) = result else {
                Issue.record("\(item.file) must be rejected")
                return
            }
            let thrown = try #require(error as? ServerUICompositionError, "\(item.file) threw \(error)")
            #expect(Case.Issue(code: thrown.code.rawValue, pointer: thrown.pointer, capability: thrown.capability) == item.issue,
                    "\(item.file) threw \(thrown)")
        default:
            Issue.record("\(item.file) has unknown outcome \(item.outcome)")
        }
    }

    /// Two decodes of the same bytes are the same document, member by member.
    @Test(arguments: cases.filter { $0.outcome == "accept" })
    func twoDecodesOfAnAcceptedFileAreEqual(_ item: Case) throws {
        let bytes = try Data(contentsOf: Self.directory.appendingPathComponent(item.file))
        let decoded: [ServerUICompositionDocument] = try HouseConfigSource.$scoped.withValue(Self.house(for: item)) {
            try (0..<2).map { _ in try ServerUICompositionPublication.decode(bytes).document }
        }
        #expect(decoded[0] == decoded[1], "\(item.file)")
    }

    /// Compares the Swift list with `capabilities.json`. With `FENTON_REGEN_CAPABILITIES=1` it rewrites the file from the list first.
    @Test func supportedCapabilitiesEqualTheCorpusList() throws {
        let url = Self.directory.appendingPathComponent("capabilities.json")
        let supported = ServerUICompositionPublication.supportedCapabilities
        if ProcessInfo.processInfo.environment["FENTON_REGEN_CAPABILITIES"] == "1" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            var text = String(decoding: try encoder.encode(supported.sorted()), as: UTF8.self)
            text += "\n"
            try Data(text.utf8).write(to: url, options: .atomic)
        }
        let corpus = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
        #expect(corpus == corpus.sorted(), "capabilities.json must be sorted")
        #expect(Set(supported).count == supported.count, "a capability is listed twice")
        #expect(supported.sorted() == corpus)
    }
}
