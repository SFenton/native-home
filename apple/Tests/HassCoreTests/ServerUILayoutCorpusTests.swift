import Foundation
import Testing
@testable import HassCore

// MARK: - Layout corpus

/// The layout capabilities' corpus cases (`sh.tab-blocks@1`, `sh.tab-bar@1`, `sh.tab-fallback@1`, `sh.overlay@1`, `sh.tile-parts@1`,
/// `sh.tile-look@1`, `sh.badges@1`), run as the Studio records them once the app ships the capability: a case the Studio compiles is
/// accepted, and one it refuses throws the Studio's own first issue (`studioIssue`).
///
/// A case that also declares a capability another lane has not shipped is still refused for that capability, first in declaration order.
@Suite(.timeLimit(.minutes(2)))
@MainActor
struct ServerUILayoutCorpusTests {
    /// One `index.json` entry with the Studio's own answer.
    struct Case: Decodable, Sendable, CustomTestStringConvertible {
        let file: String
        let pending: Bool?
        let issue: ServerUIContractCorpusTests.Case.Issue?
        let studioIssue: ServerUIContractCorpusTests.Case.Issue?
        var testDescription: String { file }
    }
    private struct Index: Decodable { let cases: [Case] }
    private struct Envelope: Decodable { let capabilities: [String] }

    nonisolated static let cases: [Case] = {
        let url = ServerUIContractCorpusTests.directory.appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: url), let index = try? JSONDecoder().decode(Index.self, from: data) else { return [] }
        let families = ["tab-blocks-", "tab-bar-", "tab-fallback-", "overlay-", "tile-parts-", "tile-look-", "badge-"]
        return index.cases.filter { item in
            let stem = item.file.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: "pending-", with: "") ?? ""
            return families.contains { stem.hasPrefix($0) }
        }
    }()

    @Test func theFamilyHasCases() { #expect(Self.cases.count >= 59) }

    /// Cases whose condition uses the `compare` predicate of `sh.conditions@1` (lane L1a), which the parser does not read yet. Remove the
    /// entry when L1a merges; the case then reports the Studio's `invalid_reference`.
    nonisolated static let waitingOnConditions: Set<String> = []

    @Test(arguments: cases)
    func caseDecodesAsTheStudioCompilesIt(_ item: Case) throws {
        if Self.waitingOnConditions.contains(item.file) { return }
        let bytes = try Data(contentsOf: ServerUIContractCorpusTests.directory.appendingPathComponent(item.file))
        let declared = try JSONDecoder().decode(Envelope.self, from: bytes).capabilities
        let shipped = Set(ServerUICompositionPublication.supportedCapabilities)
        let result: Result<ServerUICompositionPublication, any Error> = HouseConfigSource.$scoped.withValue(HouseConfigSource.demo) {
            Result { try ServerUICompositionPublication.decode(bytes) }
        }
        if let waiting = declared.first(where: { !shipped.contains($0) }) {
            // Another lane's capability still gates the document.
            guard case .failure(let error) = result, let thrown = error as? ServerUICompositionError else {
                Issue.record("\(item.file) must be refused for \(waiting)"); return
            }
            #expect(thrown.code == .unsupportedCapability && thrown.capability == waiting, "\(item.file) threw \(thrown)")
            return
        }
        // Once the Studio promotes a case, its `issue` is the answer; while it is pending, `studioIssue` is.
        guard let expected = item.studioIssue ?? (item.pending == true ? nil : item.issue) else {
            if case .failure(let error) = result { Issue.record("\(item.file) must decode, got \(error)") }
            return
        }
        guard case .failure(let error) = result, let thrown = error as? ServerUICompositionError else {
            Issue.record("\(item.file) must be rejected"); return
        }
        #expect(ServerUIContractCorpusTests.Case.Issue(code: thrown.code.rawValue, pointer: thrown.pointer, capability: thrown.capability) == expected,
                "\(item.file) threw \(thrown)")
    }
}

extension HouseConfigSource {
    /// The demo house, for cases that need no remote.
    fileprivate static var demo: HouseConfigSource {
        let source = HouseConfigSource()
        source.set(DemoHouse.config)
        return source
    }
}
