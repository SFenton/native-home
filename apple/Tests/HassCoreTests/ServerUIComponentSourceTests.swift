import Foundation
import Testing
@testable import HassCore

// MARK: - Template-owned sources (`sh.component-ref@1`)

/// Data sources an entry owns: each use gets a copy, the body reads the copy, a binding fills the copy's entity, and the published
/// document holds the copies and nothing that only stood in for them.
@Suite(.timeLimit(.minutes(2)))
@MainActor
struct ServerUIComponentSourceTests {
    typealias Builder = ServerUIComponentExpansion.Builder

    private static func publication(_ file: String) throws -> JSONValue {
        var parser = try ServerUICompositionJSON(Data(contentsOf: ServerUIContractCorpusTests.directory.appendingPathComponent(file)))
        return try parser.parse()
    }

    private static func decode(_ file: String) throws -> ServerUICompositionPublication {
        let bytes = try Data(contentsOf: ServerUIContractCorpusTests.directory.appendingPathComponent(file))
        return try HouseConfigSource.$scoped.withValue(HouseConfigSource()) { try ServerUICompositionPublication.decode(bytes) }
    }

    /// Every string under a `sourceId` key in `value`, in order.
    private static func sourceIds(in value: JSONValue) -> [String] {
        switch value {
        case .object(let object):
            return object.keys.sorted().flatMap { key -> [String] in
                if key == "sourceId", let id = object[key]?.string { return [id] }
                return sourceIds(in: object[key] ?? .null)
            }
        case .array(let items): return items.flatMap(sourceIds)
        default: return []
        }
    }

    // MARK: Naming and rewriting

    @Test func sourceKeysAreTheOnesThatNameASourceOrAProvider() {
        for key in ["sourceId", "providerId", "titleSourceId", "scopeProviderId", "SOURCEID"] { #expect(Builder.isSourceKey(key), "\(key)") }
        for key in ["copySourceId", "entityId", "source", "pageId"] { #expect(!Builder.isSourceKey(key), "\(key)") }
        for key in ["sourceIds", "providerIds", "ProviderIDs"] { #expect(Builder.isSourceListKey(key), "\(key)") }
        #expect(!Builder.isSourceListKey("sourceId"))
    }

    @Test func renamingChangesOnlySourceKeys() throws {
        let body = try ServerUIComponentSourceTests.json(#"""
        {"id":"state","sourceId":"state","copySourceId":"state","title":"state","sourceIds":["state","other"],
         "children":[{"providerId":"state","props":{"text":"state","scopeProviderId":"elsewhere"}}]}
        """#)
        let renamed = Builder.renamingSources(body, ["state": "tpl-9"])
        #expect(renamed["id"]?.string == "state")
        #expect(renamed["sourceId"]?.string == "tpl-9")
        #expect(renamed["copySourceId"]?.string == "state")
        #expect(renamed["title"]?.string == "state")
        #expect(renamed["sourceIds"]?.array?.compactMap(\.string) == ["tpl-9", "other"])
        #expect(renamed["children"]?.array?.first?["providerId"]?.string == "tpl-9")
        #expect(renamed["children"]?.array?.first?["props"]?["text"]?.string == "state")
        #expect(renamed["children"]?.array?.first?["props"]?["scopeProviderId"]?.string == "elsewhere")
        #expect(Builder.renamingSources(body, [:]) == body)
    }

    @Test func aFreshSourceIdNeverEqualsADocumentSource() {
        var builder = Builder()
        builder.takenSourceIds = ["tpl-1", "tpl-3"]
        let ids = (0..<3).map { _ in builder.freshSourceId() }
        #expect(ids == ["tpl-2", "tpl-4", "tpl-5"])
        #expect(ids.allSatisfy(ServerUICompositionShape.validID))
    }

    // MARK: Expansion

    @Test func eachUseGetsItsOwnSourceAndItsBodyReadsIt() throws {
        let expansion = ServerUIComponentExpansion(try Self.publication("accept/component-sources-two-uses.json"))
        let document = try #require(expansion.expanded["document"])
        let own = expansion.ownSourceCount
        let sources = try #require(document["dataSources"]?.array)
        #expect(own == 2)
        // One stand-in for the entry's own source while its body is checked, then one copy per use, after the document's own.
        #expect(expansion.appendedSources.map { $0.reference == nil } == [true, false, false])
        #expect(sources.count == own + 3)
        let copies = Array(sources[(own + 1)...])
        #expect(copies.compactMap { $0["entityId"]?["value"]?.string } == ["light.demo_lamp", "light.demo_porch"])
        let uses = (document["pages"]?.array?[2]["components"]?.array ?? []).flatMap { $0["children"]?.array ?? [$0] }
        let read = uses.flatMap(Self.sourceIds)
        #expect(Set(read).count == 2)
        #expect(Set(read) == Set(copies.compactMap { $0["id"]?.string }))
    }

    @Test func theDocumentAndTheBodyAreNotChanged() throws {
        let original = try Self.publication("accept/component-sources-two-uses.json")
        let expansion = ServerUIComponentExpansion(original)
        let library = original["document"]?["componentLibrary"]?.array?.first
        #expect(Self.sourceIds(in: library?["node"] ?? .null) == ["state"])
        #expect(expansion.issues.isEmpty)
        #expect(expansion.bodies.count == 1)
        // The body is checked against the stand-in, never against the name an author gave the source.
        #expect(Self.sourceIds(in: expansion.bodies[0].value).allSatisfy { $0.hasPrefix("tpl-") })
    }

    @Test func anArgumentThatEqualsAnOwnedSourceIdIsNotRewritten() throws {
        let expansion = ServerUIComponentExpansion(try Self.publication("accept/component-sources-source-id-arg-not-rewritten.json"))
        let document = try #require(expansion.expanded["document"])
        let use = try #require(document["pages"]?.array?[2]["components"]?.array?.first)
        #expect(Self.sourceIds(in: use).contains("state"))
        #expect(expansion.issues.isEmpty)
    }

    @Test func thePublishedDocumentHoldsTheCopiesAndNothingThatOnlyStoodInForThem() throws {
        let publication = try Self.decode("accept/component-sources-two-uses.json")
        let ids = publication.document.dataSources.map { source -> String in
            switch source {
            case .haEntity(let id, _): id
            default: ""
            }
        }
        #expect(ids.count == 4)
        #expect(Set(ids).count == 4)
        #expect(ids.prefix(2).allSatisfy { !$0.hasPrefix("tpl-") })
        #expect(ids.suffix(2).allSatisfy { $0.hasPrefix("tpl-") })
    }

    @Test func aSecondDecodeGivesTheSameSources() throws {
        let first = try Self.decode("accept/component-sources-two-uses.json")
        let second = try Self.decode("accept/component-sources-two-uses.json")
        #expect(first.document.dataSources == second.document.dataSources)
    }

    // MARK: Checks

    @Test func aRepeatedSourceIdIsReportedAtTheFirstOne() throws {
        let expansion = ServerUIComponentExpansion(try Self.publication("reject/component-source-duplicate-id.json"))
        #expect(expansion.issues.map(\.code) == [.duplicateID])
        #expect(expansion.issues.map(\.pointer) == ["/document/componentLibrary/0/sources/0/id"])
    }

    @Test func anOwnedEntityIsADomainAndAnObjectId() throws {
        let expansion = ServerUIComponentExpansion(try Self.publication("reject/component-source-bad-default-entity.json"))
        #expect(expansion.issues.map(\.code) == [.invalidValue])
        #expect(expansion.issues.map(\.pointer) == ["/document/componentLibrary/0/sources/0/entityId/value"])
    }

    @Test func aBindingNamesANodeOrASourceAndNotBothAndNotNeither() throws {
        let both = ServerUIComponentExpansion(try Self.publication("reject/component-source-binding-both-targets.json"))
        #expect(both.issues.first?.code == .invalidCombination)
        #expect(both.issues.first?.pointer == "/document/componentLibrary/0/bindings/0/sourceId")
        let neither = ServerUIComponentExpansion(try Self.publication("reject/component-source-binding-no-target.json"))
        #expect(neither.issues.first?.code == .missingRequired)
        #expect(neither.issues.first?.pointer == "/document/componentLibrary/0/bindings/0/nodeId")
        let unknown = ServerUIComponentExpansion(try Self.publication("reject/component-source-binding-unknown-source.json"))
        #expect(unknown.issues.first?.code == .invalidReference)
        #expect(unknown.issues.first?.pointer == "/document/componentLibrary/0/bindings/0/sourceId")
    }

    @Test func aSourceFieldThatIsNotAnEntityIsTheWrongKind() throws {
        let expansion = ServerUIComponentExpansion(try Self.publication("reject/component-source-binding-not-an-entity-field.json"))
        #expect(expansion.issues.first?.code == .bindingType)
        let twice = ServerUIComponentExpansion(try Self.publication("reject/component-source-binding-field-twice.json"))
        #expect(twice.issues.first?.code == .invalidCombination)
        #expect(twice.issues.first?.pointer == "/document/componentLibrary/0/bindings/1/field")
    }

    @Test func theCopiesCountTowardTheThousandSourceLimit() throws {
        let expansion = ServerUIComponentExpansion(try Self.publication("reject/component-sources-over-document-limit.json"))
        #expect(expansion.issues.map(\.code) == [.limitExceeded, .limitExceeded])
        #expect(expansion.issues.first?.pointer == "/document/modals/0/components/27/componentId")
        // The copies of every use are still added: the limit is reported, not enforced by dropping them.
        #expect(expansion.appendedSources.count == 1 * 8 + 126 * 8)
    }

    // MARK: Pointers

    @Test func anIssueInACopyMovesToTheArgumentThatFilledIt() throws {
        let expansion = ServerUIComponentExpansion(try Self.publication("accept/component-sources-two-uses.json"))
        let own = expansion.ownSourceCount
        // Index 0 is the stand-in; 1 and 2 are the uses `lamp-a` and `lamp-b`.
        let second = "/document/dataSources/\(own + 2)"
        func moved(_ code: ServerUICompositionError.Code, _ suffix: String) -> [ServerUICompositionError] {
            expansion.remapped([ServerUICompositionError(code, second + suffix)])
        }
        #expect(moved(.invalidValue, "/entityId/value").map(\.pointer) == ["/document/pages/2/components/1/args/lamp"])
        // What the argument did not fill, and the stand-in for the entry's own source, are the library's to report.
        #expect(moved(.invalidValue, "/id").isEmpty)
        #expect(expansion.remapped([ServerUICompositionError(.invalidValue, "/document/dataSources/\(own)/entityId/value")]).isEmpty)
        // A document source is not an appended one.
        let document = ServerUICompositionError(.invalidValue, "/document/dataSources/1/entityId/value")
        #expect(expansion.remapped([document]) == [document])
    }

    @Test func publishingDropsOnlyTheStandIns() throws {
        let expansion = ServerUIComponentExpansion(try Self.publication("accept/component-sources-two-uses.json"))
        let decoded = Array(0..<(expansion.ownSourceCount + expansion.appendedSources.count))
        let kept = expansion.published(decoded)
        #expect(kept == [0, 1, 3, 4])
        let none = ServerUIComponentExpansion(try Self.publication("accept/component-two-uses-one-page.json"))
        #expect(none.published([7, 8]) == [7, 8])
    }

    private static func json(_ text: String) throws -> JSONValue {
        var parser = try ServerUICompositionJSON(Data(text.utf8))
        return try parser.parse()
    }
}
