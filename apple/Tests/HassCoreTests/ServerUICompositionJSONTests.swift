import Foundation
import Testing
@testable import HassCore

// MARK: - Strict JSON parsing

@Suite struct ServerUICompositionJSONTests {
    private func parse(_ text: String) throws -> JSONValue {
        var parser = try ServerUICompositionJSON(Data(text.utf8))
        return try parser.parse()
    }

    // MARK: Duplicate keys

    @Test func canonicallyEquivalentKeysAreDuplicates() {
        // "é" and "é" are different bytes but the same Swift String, so a dictionary would merge them.
        let precomposed = #"{"x":{"é":1,"é":2}}"#
        #expect(throws: ServerUICompositionError(.duplicateKey, "/x/e\u{301}")) { try parse(precomposed) }
        // The same pair spelled with raw UTF-8 rather than escapes.
        #expect(throws: ServerUICompositionError(.duplicateKey, "/x/e\u{301}")) { try parse("{\"x\":{\"\u{e9}\":1,\"e\u{301}\":2}}") }
        // A different key is not a duplicate of a prefix of another.
        #expect(throws: Never.self) { try parse(#"{"x":{"e":1,"é":2}}"#) }
    }

    @Test func byteIdenticalAndEscapedKeysStillDuplicate() {
        #expect(throws: ServerUICompositionError(.duplicateKey, "/a")) { try parse(#"{"a":1,"a":2}"#) }
        #expect(throws: ServerUICompositionError(.duplicateKey, "/a")) { try parse(#"{"a":1,"a":2}"#) }
    }

    // MARK: Strings

    @Test func plainEscapedAndNonASCIIStringsDecodeToTheSameValues() throws {
        #expect(try parse(#""plain text""#) == .string("plain text"))
        #expect(try parse(#""tab\tquote\"slash\/back\\""#) == .string("tab\tquote\"slash/back\\"))
        #expect(try parse(#""Aé""#) == .string("A\u{e9}"))
        #expect(try parse("\"caf\u{e9} \u{1F600}\"") == .string("caf\u{e9} \u{1F600}"))
        #expect(try parse(#""😀""#) == .string("\u{1F600}"))
        #expect(try parse(#""""#) == .string(""))
    }

    @Test func malformedStringsAreRejected() {
        for text in [#""\ud800""#, #""\udc00""#, #""\x""#, "\"\u{1}\"", #""unterminated"#, #""bad\u12""#] {
            #expect(throws: ServerUICompositionError.self) { try parse(text) }
        }
        #expect(throws: ServerUICompositionError.self) {
            var parser = try ServerUICompositionJSON(Data([34, 0xC3, 0x28, 34]))
            _ = try parser.parse()
        }
    }

    // MARK: Canonical form

    @Test func canonicalFormIsKeyOrderedAndStable() {
        let value: JSONValue = .object(["b": .number(1), "a": .array([.string("x"), .null, .bool(true)]), "c": .number(0.5)])
        #expect(ServerUICompositionJSON.canonical(value) == #"{"a":["x",null,true],"b":1,"c":0.5}"#)
    }
}
