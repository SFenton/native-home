import Foundation
import Testing
@testable import HassCore

// MARK: - Fold sides corpus

/// The `sh.fold-sides@1` publication cases, run as the Studio records them now the app ships the id: the nine `fold-sides-*` accepts
/// decode, and each refusal throws the Studio's own first issue (`studioIssue`). The corpus files stay byte for byte as the Studio wrote them.
@Suite(.timeLimit(.minutes(2)))
@MainActor
struct ServerUIFoldSidesCorpusTests {
    nonisolated static let cases: [ServerUILayoutCorpusTests.Case] = ServerUILayoutCorpusTests.allCases { $0.hasPrefix("fold-sides-") }

    static var demoHouse: HouseConfigSource {
        let source = HouseConfigSource()
        source.set(DemoHouse.config)
        return source
    }

    @Test func theFamilyHasAllItsCases() { #expect(Self.cases.count == 22) }

    @Test(arguments: cases)
    func caseDecodesAsTheStudioCompilesIt(_ item: ServerUILayoutCorpusTests.Case) throws {
        let bytes = try Data(contentsOf: ServerUIContractCorpusTests.directory.appendingPathComponent(item.file))
        let result: Result<ServerUICompositionPublication, any Error> = HouseConfigSource.$scoped.withValue(Self.demoHouse) {
            Result { try ServerUICompositionPublication.decode(bytes) }
        }
        let expected = item.studioIssue ?? (item.pending == true ? nil : item.issue)
        guard let expected else {
            if case .failure(let error) = result { Issue.record("\(item.file) must decode, got \(error)") }
            return
        }
        guard case .failure(let error) = result, let thrown = error as? ServerUICompositionError else { Issue.record("\(item.file) must be rejected"); return }
        #expect(ServerUIContractCorpusTests.Case.Issue(code: thrown.code.rawValue, pointer: thrown.pointer, capability: thrown.capability) == expected, "\(item.file) threw \(thrown)")
    }

    @Test func theRuleAnswersTheStudiosWorkedExamples() {
        typealias I = ServerUIFoldSides.Input
        let items = [I(kind: .strip), I(kind: .staticallyHidden), I(kind: .section), I(kind: .pinned), I(kind: .section, said: .leading), I(kind: .section), I(kind: .strip)]
        #expect(ServerUIFoldSides.resolve(items) == [.span, nil, .leading, nil, .leading, .leading, .trailing])
        #expect(ServerUIFoldSides.lateSpans([I(kind: .section), I(kind: .strip, said: .span), I(kind: .section, said: .span)]) == [1, 2])
        #expect(!ServerUIFoldSides.usesFoldSides(switchedOn: false, items: [I(kind: .section), I(kind: .strip)]))
        #expect(ServerUIFoldSides.usesFoldSides(switchedOn: false, items: [I(kind: .section, said: .trailing)]))
        #expect(!ServerUIFoldSides.usesFoldSides(switchedOn: false, items: [I(kind: .pinned, said: .leading)]), "a pinned bar's side is ignored")
    }
}
