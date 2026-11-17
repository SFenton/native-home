import Foundation
import Testing
@testable import HassCore

// MARK: - Template parameters (`sh.component-ref@1`: entity and state kinds, labels, origin, limits)

/// The tier-1 template changes folded into `sh.component-ref@1`: the `entity-id` and `state-id` kinds, `label` and `origin`, the raised
/// limits and the Studio's `fieldKind` rules. Each test pins one rule on its own, apart from the shared corpus.
@Suite(.timeLimit(.minutes(2)))
@MainActor
struct ServerUIComponentTemplateTests {
    typealias Fields = ServerUIComponentExpansion.Builder

    private static func json(_ text: String) throws -> JSONValue {
        var parser = try ServerUICompositionJSON(Data(text.utf8))
        return try parser.parse()
    }

    private static func publication(_ file: String) throws -> JSONValue {
        var parser = try ServerUICompositionJSON(Data(contentsOf: ServerUIContractCorpusTests.directory.appendingPathComponent(file)))
        return try parser.parse()
    }

    /// The library entry `{id, name, params, bindings, node}` with `extra` merged in, as the shape sees it.
    private static func entry(_ extra: String = "") throws -> JSONValue {
        try json("""
        {"id":"tile","name":"Tile","node":{"id":"body","title":"T","type":"text","layout":{"span":1},"props":{"value":{"type":"literal","value":"x"},"style":"body","unavailableText":"Unavailable"}}\(extra.isEmpty ? "" : "," + extra)}
        """)
    }

    private static func shapeIssues(_ entry: JSONValue) -> [ServerUICompositionError] {
        ServerUICompositionShape.issues(of: entry, against: ServerUICompositionShape.componentEntry)
    }

    private static func parameters(_ count: Int) -> String {
        "\"params\":[" + (0..<count).map { "{\"name\":\"p\($0)\",\"kind\":\"text\"}" }.joined(separator: ",") + "]"
    }

    // MARK: fieldKind (D1, D3, D6)

    @Test func entityFieldsHaveTheEntityKind() throws {
        let node = try Self.json("""
        {"id":"n","title":"t","binding":{"entityId":"light.demo_a","roomEntityId":"cover.demo_b","copySourceId":"light.demo_c"},
         "action":{"target":{"entity_id":{"type":"literal","value":"light.demo_d"}},"sourceId":"state"},
         "props":{"stateId":"tabs"},"source":{"entityId":{"type":"literal","value":"light.demo_e"}}}
        """)
        #expect(Fields.kind(of: "binding/entityId", in: node) == "entity-id")
        #expect(Fields.kind(of: "binding/roomEntityId", in: node) == "entity-id")
        #expect(Fields.kind(of: "binding/copySourceId", in: node) == "entity-id")
        #expect(Fields.kind(of: "action/target/entity_id/value", in: node) == "entity-id")
        #expect(Fields.kind(of: "source/entityId/value", in: node) == "entity-id")
    }

    @Test func aLiteralUnderAnEntityKeyIsNoLongerText() throws {
        let node = try Self.json(#"{"id":"n","action":{"target":{"entity_id":{"type":"literal","value":"light.demo_d"}}},"props":{"subtitle":{"type":"literal","value":"hi"}}}"#)
        #expect(Fields.kind(of: "action/target/entity_id/value", in: node) != "text")
        #expect(Fields.kind(of: "props/subtitle/value", in: node) == "text")
    }

    @Test func aSourceIdStaysASourceIdAndACopySourceIdIsNot() throws {
        let node = try Self.json(#"{"id":"n","action":{"sourceId":"s","providerId":"p","copySourceId":"light.demo_a"},"titleSourceId":"t"}"#)
        #expect(Fields.kind(of: "action/sourceId", in: node) == "source-id")
        #expect(Fields.kind(of: "action/providerId", in: node) == "source-id")
        #expect(Fields.kind(of: "titleSourceId", in: node) == "source-id")
        #expect(Fields.kind(of: "action/copySourceId", in: node) == "entity-id")
    }

    @Test func aStateIdHasTheStateKind() throws {
        let node = try Self.json(#"{"id":"n","props":{"stateId":"tabs"},"action":{"type":"set-local","stateId":"tabs"}}"#)
        #expect(Fields.kind(of: "props/stateId", in: node) == "state-id")
        #expect(Fields.kind(of: "action/stateId", in: node) == "state-id")
    }

    @Test func aFieldThatIsNotAStringHasNoKind() throws {
        let node = try Self.json(#"{"id":"n","binding":{"entityId":5,"stateId":true}}"#)
        #expect(Fields.kind(of: "binding/entityId", in: node) == nil)
        #expect(Fields.kind(of: "binding/stateId", in: node) == nil)
        #expect(Fields.kind(of: "binding/missing", in: node) == nil)
    }

    // MARK: Shape (D4, D5)

    @Test func anEntryHoldsSixteenParametersAndNoMore() throws {
        #expect(Self.shapeIssues(try Self.entry(Self.parameters(16))).isEmpty)
        let over = Self.shapeIssues(try Self.entry(Self.parameters(17)))
        #expect(over.map(\.code) == [.limitExceeded])
        #expect(over.map(\.pointer) == ["/params"])
    }

    @Test func anEntryHoldsOneHundredTwentyEightBindingsAndNoMore() throws {
        func bindings(_ count: Int) -> String {
            "\"bindings\":[" + (0..<count).map { _ in #"{"param":"p","nodeId":"body","field":"title"}"# }.joined(separator: ",") + "]"
        }
        #expect(Self.shapeIssues(try Self.entry(bindings(128))).isEmpty)
        #expect(Self.shapeIssues(try Self.entry(bindings(129))).map(\.code) == [.limitExceeded])
    }

    @Test func aReferenceHoldsSixteenArguments() throws {
        func reference(_ count: Int) throws -> JSONValue {
            let args = (0..<count).map { "\"a\($0)\":\"v\"" }.joined(separator: ",")
            return try Self.json(#"{"id":"r","type":"component-ref","componentId":"tile","layout":{"span":1},"args":{\#(args)}}"#)
        }
        #expect(ServerUICompositionShape.issues(of: try reference(16), against: ServerUICompositionShape.componentRef).isEmpty)
        let over = ServerUICompositionShape.issues(of: try reference(17), against: ServerUICompositionShape.componentRef)
        #expect(over.map(\.code) == [.limitExceeded])
        #expect(over.map(\.pointer) == ["/args"])
    }

    @Test func everyKindIsAcceptedAndAnUnknownOneIsNot() throws {
        for kind in ServerUICompositionShape.componentParameterKinds {
            #expect(Self.shapeIssues(try Self.entry(#""params":[{"name":"p","kind":"\#(kind)"}]"#)).isEmpty, "\(kind)")
        }
        #expect(ServerUICompositionShape.componentParameterKinds.contains("entity-id") && ServerUICompositionShape.componentParameterKinds.contains("state-id"))
        #expect(Self.shapeIssues(try Self.entry(#""params":[{"name":"p","kind":"number"}]"#)).map(\.code) == [.unknownVariant])
    }

    @Test func aLabelIsReadAndAnOriginIsReadAndNothingElse() throws {
        #expect(Self.shapeIssues(try Self.entry(#""params":[{"name":"p","kind":"text","label":"Room name"}],"origin":{"id":"light-button","version":3}"#)).isEmpty)
        let expansion = ServerUIComponentExpansion(try Self.publication("accept/component-args-labels.json"))
        #expect(expansion.issues.isEmpty)
        #expect(expansion.expanded["document"]?["componentLibrary"] == nil)
    }

    @Test func aLabelIsOneToEightyVisibleCharacters() throws {
        func issues(_ label: String) throws -> [ServerUICompositionError] {
            Self.shapeIssues(try Self.entry("\"params\":[{\"name\":\"p\",\"kind\":\"text\",\"label\":\"\(label)\"}]"))
        }
        #expect(try issues("").map(\.code) == [.invalidValue])
        #expect(try issues("   ").map(\.code) == [.invalidValue])
        #expect(try issues(String(repeating: "a", count: 80)).isEmpty)
        let long = try issues(String(repeating: "a", count: 81))
        #expect(long.map(\.code) == [.limitExceeded])
        #expect(long.map(\.pointer) == ["/params/0/label"])
        // A control or format character is the builder's check, as for an entry's name.
        let control = ServerUIComponentExpansion(try Self.publication("reject/component-param-label-control.json"))
        #expect(control.issues.map(\.code) == [.invalidValue])
        #expect(control.issues.map(\.pointer) == ["/document/componentLibrary/0/params/0/label"])
    }

    @Test func anOriginNeedsAnIdentifierAndAVersionFromOneToNineThousandNineHundredNinetyNine() throws {
        func issues(_ origin: String) throws -> [ServerUICompositionError] { Self.shapeIssues(try Self.entry("\"origin\":\(origin)")) }
        #expect(try issues(#"{"id":"vent","version":9999}"#).isEmpty)
        #expect(try issues(#"{"id":"vent","version":1}"#).isEmpty)
        #expect(try issues(#"{"id":"vent","version":0}"#).map(\.code) == [.limitExceeded])
        #expect(try issues(#"{"id":"vent","version":10000}"#).map(\.code) == [.limitExceeded])
        #expect(try issues(#"{"id":"vent"}"#).map(\.code) == [.missingRequired])
        #expect(try issues(#"{"id":"bad id","version":1}"#).map(\.code) == [.invalidValue])
        #expect(try issues(#"{"id":"vent","version":1,"name":"x"}"#).map(\.code) == [.unknownField])
    }

    // MARK: Arguments (D1, D3)

    @Test func anEntityArgumentIsADomainAndAnObjectId() throws {
        let valid = ServerUIComponentExpansion(try Self.publication("accept/component-args-entity-id.json"))
        #expect(valid.issues.isEmpty)
        let malformed = ServerUIComponentExpansion(try Self.publication("reject/component-args-entity-id-malformed.json"))
        #expect(malformed.issues.map(\.code) == [.invalidValue])
        #expect(malformed.issues.map(\.pointer) == ["/document/pages/2/components/0/args/fan"])
        let bare = ServerUIComponentExpansion(try Self.publication("reject/component-args-entity-id-no-domain.json"))
        #expect(bare.issues.map(\.code) == [.invalidValue])
    }

    @Test func aStateArgumentIsCheckedAgainstTheLocalState() throws {
        let valid = ServerUIComponentExpansion(try Self.publication("accept/component-args-state-id.json"))
        #expect(valid.issues.isEmpty)
        #expect(valid.argumentReferences.map(\.catalog) == ["local-state", "local-state"])
        let notAnIdentifier = ServerUIComponentExpansion(try Self.publication("reject/component-args-state-id-not-an-identifier.json"))
        #expect(notAnIdentifier.issues.map(\.code) == [.invalidValue])
        #expect(notAnIdentifier.argumentReferences.isEmpty)
    }

    @Test func anEntityIdArgumentFillsTheFieldItIsBoundTo() throws {
        let expansion = ServerUIComponentExpansion(try Self.publication("accept/component-args-entity-id.json"))
        let targets = (expansion.expanded["document"]?["pages"]?.array?[2]["components"]?.array ?? []).compactMap {
            $0["onAction"]?["target"]?["entity_id"]?["value"]?.string ?? $0["action"]?["target"]?["entity_id"]?["value"]?.string
        }
        #expect(targets.count == 2 && Set(targets).count == 2)
    }

    // MARK: The compiler end to end

    @Test func aTextParameterCannotFillAnEntityField() throws {
        let expansion = ServerUIComponentExpansion(try Self.publication("reject/component-binding-text-on-entity-field.json"))
        #expect(expansion.issues.map(\.code) == [.bindingType])
        #expect(expansion.issues.map(\.pointer) == ["/document/componentLibrary/0/bindings/0/field"])
    }

    @Test func anEntityParameterCannotFillATextField() throws {
        let expansion = ServerUIComponentExpansion(try Self.publication("reject/component-binding-entity-id-on-text-field.json"))
        #expect(expansion.issues.map(\.code) == [.bindingType])
    }

    @Test func aWrongDomainEntityIsRefusedAtTheArgument() throws {
        let bytes = try Data(contentsOf: ServerUIContractCorpusTests.directory.appendingPathComponent("reject/component-args-entity-id-wrong-domain.json"))
        do {
            _ = try HouseConfigSource.$scoped.withValue(HouseConfigSource()) { try ServerUICompositionPublication.decode(bytes) }
            Issue.record("a vacuum style must refuse a light")
        } catch let issue as ServerUICompositionError {
            #expect(issue.code == .invalidCombination)
            #expect(issue.pointer == "/document/pages/2/components/0/args/robot")
        }
    }
}
