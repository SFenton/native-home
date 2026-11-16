import Foundation
import Testing
@testable import HassCore

// MARK: - The capabilities the grammar ships

/// `sh.conditions@1`, `sh.app-state@1` and `sh.home-status-counts@1` are shipped, and a document declares exactly the ones it uses.
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ServerUIOperandCapabilityTests {
    private func corpus(_ file: String) throws -> JSONValue {
        let url = ServerUIContractCorpusTests.directory.appendingPathComponent(file)
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }

    private func decode(_ json: JSONValue) throws -> ServerUICompositionPublication {
        try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
    }

    private func replacing(_ json: JSONValue, capabilities: [String]) -> JSONValue {
        guard case .object(var object) = json else { return json }
        object["capabilities"] = .array(capabilities.map(JSONValue.string))
        return .object(object)
    }

    @Test func theGrammarCapabilitiesAreShipped() {
        for id in ["sh.conditions@1", "sh.app-state@1", "sh.home-status-counts@1"] {
            #expect(ServerUIIngestedCapabilities.grammar.contains(id))
            #expect(ServerUICompositionPublication.supportedCapabilities.contains(id))
        }
    }

    @Test func aDocumentThatComparesDeclaresConditionsAndAppState() throws {
        let document = try corpus("accept/app-state-condition.json")
        let publication = try decode(document)
        #expect(publication.capabilities.contains("sh.conditions@1") && publication.capabilities.contains("sh.app-state@1"))
        guard case .array(let declared)? = document["capabilities"] else { return }
        let without = declared.compactMap(\.string).filter { $0 != "sh.conditions@1" }
        #expect(throws: ServerUICompositionError.self) { try decode(replacing(document, capabilities: without)) }
        do { _ = try decode(replacing(document, capabilities: without)) } catch let error as ServerUICompositionError {
            #expect(error.code == .capabilityManifestMismatch)
        }
    }

    @Test func anAppStateSourceNeedsItsCapabilityEvenWhenNothingReadsIt() throws {
        let document = try corpus("accept/app-state-window.json")
        guard case .array(let declared)? = document["capabilities"] else { return }
        let without = declared.compactMap(\.string).filter { $0 != "sh.app-state@1" }
        do { _ = try decode(replacing(document, capabilities: without)); Issue.record("must be refused") } catch let error as ServerUICompositionError {
            #expect(error.code == .capabilityManifestMismatch)
        }
    }

    @Test func aReadOfAHomeStatusCountNeedsItsCapabilityAndAKindOfNumber() throws {
        // The corpus case reads `count` as text: the Studio's first issue is a binding type at `/as`.
        let wrong = try corpus("reject/home-status-counts-wrong-kind.json")
        do { _ = try decode(wrong); Issue.record("must be refused") } catch let error as ServerUICompositionError {
            #expect(error.code == .bindingType && error.pointer.hasSuffix("/left/as"))
        }
    }
}
