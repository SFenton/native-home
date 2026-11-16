import Foundation
import Testing
@testable import HassCore

// MARK: - Saved components (`sh.component-ref@1`)

/// The compile-time expansion: derived ids, parameter substitution, issue pointers and the plain document the compiler returns.
@Suite(.timeLimit(.minutes(2)))
@MainActor
struct ServerUIComponentExpansionTests {
    private static func publication(_ file: String) throws -> JSONValue {
        let bytes = try Data(contentsOf: ServerUIContractCorpusTests.directory.appendingPathComponent(file))
        var parser = try ServerUICompositionJSON(bytes)
        return try parser.parse()
    }

    private static func components(of expansion: ServerUIComponentExpansion, page: Int = 2) -> [JSONValue] {
        expansion.expanded["document"]?["pages"]?.array?[page]["components"]?.array ?? []
    }

    // MARK: Expansion

    @Test func rootKeepsTheReferenceIdAndInnerNodesAreDerived() throws {
        let expansion = ServerUIComponentExpansion(try Self.publication("accept/component-two-uses-one-page.json"))
        let uses = Self.components(of: expansion)
        #expect(uses.map { $0["id"]?.string } == ["home-guests", "guest-suite"])
        #expect(uses.map { $0["children"]?.array?.first?["id"]?.string } == ["home-guests~cmp-copy", "guest-suite~cmp-copy"])
        #expect(uses.allSatisfy { $0["type"]?.string == "section" })
        #expect(expansion.expanded["document"]?["componentLibrary"] == nil)
        #expect(expansion.usesComponents)
        #expect(expansion.issues.isEmpty)
    }

    @Test func argumentsFillOnlyTheBoundFields() throws {
        let expansion = ServerUIComponentExpansion(try Self.publication("accept/component-args-page-and-text.json"))
        let uses = Self.components(of: expansion)
        #expect(uses.map { $0["action"]?["pageId"]?.string } == ["page-lattice", "page-orbit"])
        #expect(uses.map { $0["action"]?["type"]?.string } == ["push", "push"])
        #expect(uses.map { $0["icon"]?["name"]?.string } == ["info.circle", "info.circle"])
    }

    @Test func textAndSymbolArgumentsReachTheirFields() throws {
        let expansion = ServerUIComponentExpansion(try Self.publication("accept/component-args-text-symbol-modal.json"))
        let use = try #require(Self.components(of: expansion).first)
        #expect(use["props"]?["subtitle"]?["value"]?.string == "Open the swatches")
        #expect(use["icon"]?["name"]?.string == "star")
        #expect(use["action"]?["modalId"]?.string == "modal-swatch")
    }

    @Test func aDocumentWithoutComponentsIsReturnedAsItIs() throws {
        let bytes = try Data(contentsOf: ServerUIContractCorpusTests.directory.appendingPathComponent("accept/fixture-composition-first-slice.json"))
        var parser = try ServerUICompositionJSON(bytes)
        let json = try parser.parse()
        let expansion = ServerUIComponentExpansion(json)
        #expect(expansion.expanded == json)
        #expect(!expansion.usesComponents)
        #expect(expansion.bodies.isEmpty)
    }

    @Test func theCompiledDocumentHoldsPlainNodesWithDerivedIds() throws {
        let bytes = try Data(contentsOf: ServerUIContractCorpusTests.directory.appendingPathComponent("accept/component-two-uses-one-page.json"))
        let publication = try HouseConfigSource.$scoped.withValue(HouseConfigSource()) { try ServerUICompositionPublication.decode(bytes) }
        let section = try #require(publication.document.pages[2].surface.components.first)
        #expect(section.node.id == "home-guests")
        #expect(section.childComponents.map(\.node.id) == ["home-guests~cmp-copy"])
        #expect(publication.capabilities.contains("sh.component-ref@1"))
    }

    @Test func aSecondDecodeGivesTheSameDocument() throws {
        let bytes = try Data(contentsOf: ServerUIContractCorpusTests.directory.appendingPathComponent("accept/component-args-page-and-text.json"))
        let first = try ServerUICompositionPublication.decode(bytes)
        let second = try ServerUICompositionPublication.decode(bytes)
        #expect(first.document == second.document)
        #expect(first.documentSha256 == second.documentSha256)
    }

    // MARK: Issue pointers

    @Test func structuralIssuesNameTheReferenceOrTheLibrary() throws {
        let missing = ServerUIComponentExpansion(try Self.publication("reject/component-args-missing.json"))
        #expect(missing.issues.map(\.pointer) == ["/document/pages/2/components/0/args/target"])
        let unknown = ServerUIComponentExpansion(try Self.publication("reject/component-args-unknown.json"))
        #expect(unknown.issues.contains { $0.code == .unknownField && $0.pointer.hasSuffix("/args/other") })
        let nested = ServerUIComponentExpansion(try Self.publication("reject/component-nested-ref.json"))
        #expect(nested.issues.map(\.pointer) == ["/document/componentLibrary/1/node/children/0/type"])
        #expect(nested.bodies.count == 2)
    }

    @Test func issuesInAnExpansionMoveBackToTheAuthor() throws {
        let expansion = ServerUIComponentExpansion(try Self.publication("accept/component-args-page-and-text.json"))
        let use = "/document/pages/2/components/1"
        func moved(_ code: ServerUICompositionError.Code, _ suffix: String) -> ServerUICompositionError {
            expansion.remapped([ServerUICompositionError(code, use + suffix)])[0]
        }
        // A bound field is the argument's fault.
        #expect(moved(.invalidReference, "/action/pageId").pointer == use + "/args/target")
        // The root's place is the reference's `componentId`; its id and width are the reference's own.
        #expect(moved(.invalidCombination, "/type").pointer == use + "/componentId")
        #expect(moved(.invalidCombination, "/layout/span").pointer == use + "/layout/span")
        #expect(moved(.duplicateID, "/id").pointer == use + "/id")
        // A limit counts the whole body in the place that uses it.
        #expect(moved(.limitExceeded, "/children/3").pointer == use)
        // Anything else is the body's.
        #expect(moved(.invalidValue, "/action/origin").pointer == "/document/componentLibrary/0/node/action/origin")
        // A pointer outside every use is left alone.
        let elsewhere = ServerUICompositionError(.invalidValue, "/document/pages/0/title")
        #expect(expansion.remapped([elsewhere]) == [elsewhere])
    }

    // MARK: Fields

    @Test func fieldKindsFollowWhereTheFieldSits() throws {
        let node = try #require(try Self.publication("accept/component-args-text-symbol-modal.json")["document"]?["componentLibrary"]?.array?.first?["node"])
        typealias Fields = ServerUIComponentExpansion.Builder
        #expect(Fields.kind(of: "props/subtitle/value", in: node) == "text")
        #expect(Fields.kind(of: "icon/name", in: node) == "symbol")
        #expect(Fields.kind(of: "action/modalId", in: node) == "modal-id")
        #expect(Fields.kind(of: "title", in: node) == "text")
        #expect(Fields.kind(of: "type", in: node) == nil)
        #expect(Fields.read(node, field: "action/missing") == nil)
        #expect(Fields.write(.string("x"), to: node, field: "action/missing") == nil)
        #expect(Fields.write(.string("x"), to: node, field: "action/modalId")?["action"]?["modalId"]?.string == "x")
        #expect(Fields.find("cmp-open", in: node) == node)
        #expect(Fields.find("nothing", in: node) == nil)
    }
}
