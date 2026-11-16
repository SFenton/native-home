import Foundation
import Testing
@testable import HassCore

// MARK: - Pending handshake

/// The capability handshake over the shared corpus: every case the index marks pending (the `pending-*` files and the flagged older ones) is refused as `unsupported_capability`,
/// every accept case is accepted, and the pending list never overlaps what the app ships.
@Suite(.timeLimit(.minutes(2)))
@MainActor
struct ServerUIPendingCorpusTests {
    nonisolated static let cases = ServerUIContractCorpusTests.cases

    @Test func pendingCasesExistAndNameAPendingCapability() throws {
        let data = try Data(contentsOf: ServerUIContractCorpusTests.directory.appendingPathComponent("capabilities.pending.json"))
        let pending = try JSONDecoder().decode([String].self, from: data)
        #expect(!pending.isEmpty)
        #expect(Set(pending).isDisjoint(with: ServerUICompositionPublication.supportedCapabilities), "a shipped capability is still pending")
        let pendingCases = Self.cases.filter { $0.pending == true }
        #expect(!pendingCases.isEmpty)
        for item in pendingCases {
            #expect(item.outcome == "reject", "\(item.file)")
            #expect(item.issue?.code == "unsupported_capability", "\(item.file)")
            #expect(item.issue?.capability.map(pending.contains) == true, "\(item.file) names a capability that is not pending")
        }
    }

    @Test(arguments: cases.filter { $0.pending == true })
    func pendingCaseIsRefusedAsUnsupportedCapability(_ item: ServerUIContractCorpusTests.Case) throws {
        let bytes = try Data(contentsOf: ServerUIContractCorpusTests.directory.appendingPathComponent(item.file))
        let result: Result<ServerUICompositionPublication, any Error> = HouseConfigSource.$scoped.withValue(ServerUIContractCorpusTests.house(for: item)) {
            Result { try ServerUICompositionPublication.decode(bytes) }
        }
        guard case .failure(let error) = result else {
            Issue.record("\(item.file) must be refused")
            return
        }
        let thrown = try #require(error as? ServerUICompositionError, "\(item.file) threw \(error)")
        #expect(thrown.code.rawValue == "unsupported_capability", "\(item.file) threw \(thrown)")
        #expect(thrown.capability == item.issue?.capability, "\(item.file)")
    }

    @Test(arguments: cases.filter { $0.outcome == "accept" })
    func acceptCaseIsAccepted(_ item: ServerUIContractCorpusTests.Case) throws {
        let bytes = try Data(contentsOf: ServerUIContractCorpusTests.directory.appendingPathComponent(item.file))
        do {
            _ = try HouseConfigSource.$scoped.withValue(ServerUIContractCorpusTests.house(for: item)) { try ServerUICompositionPublication.decode(bytes) }
        } catch { Issue.record("\(item.file) must be accepted, got \(error)") }
    }
}
